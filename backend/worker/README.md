# StickerBridge 개인 테스트 Worker

2026-10-13: 일반 팩의 정적 원본뿐 아니라 TGS(gzip 64KiB 이하), WebM(EBML signature, Telegram 다운로드 범위 20MiB 이하)도 중계합니다. 변환과 코덱 검증은 메인 앱에서 수행합니다. 마스크·custom emoji 원본은 계속 거부하며 기존 인증·소속 확인·캐시·레이트 제한·리다이렉트 차단을 유지합니다.

계정 없이 Node 24 이상에서 로컬 테스트할 수 있습니다. 런타임 패키지 없이 Fetch API를 사용하며, TypeScript와 Wrangler는 버전을 고정한 개발 도구입니다. `pnpm-lock.yaml`을 유지하고 도구 업데이트 시 테스트·타입 검사·번들 검사를 다시 실행하세요.

테스트에는 Wrangler가 사용하는 것과 같은 버전의 Miniflare를 개발 의존성으로 명시합니다. `runtime.test.mjs`는 실제 workerd에서 production 진입점·rate-limit·캐시를 실행하고, outbound service로 가짜 Telegram 응답만 제공합니다. 이 테스트는 외부 네트워크·실제 Secret·계정을 사용하지 않습니다. 현재 Wrangler에 맞춘 Miniflare 5 alpha를 고정했으므로 두 도구를 함께 업데이트하고 API 변경을 확인해야 합니다. TypeScript 소스 모듈 전체는 Node 24의 `stripTypeScriptTypes`로 타입만 제거하여 Miniflare에 제공합니다. 실험 기능 경고가 표시될 수 있습니다.

```sh
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
pnpm check:bundle
```

`check:bundle`은 `wrangler deploy --dry-run`이며 업로드하지 않습니다. 의존성 설치 스크립트는 실행하지 않고 선택적 플랫폼 바이너리를 사용합니다. 현재 Mac에서 번들 검사를 통과했습니다. 다른 플랫폼에서 바이너리가 누락되면 설치 로그를 확인하세요.

## 서버 코드 구조

- `src/index.ts`: Worker 진입점과 기존 `createHandler` export.
- `src/routes/`: 인증 이후 라우팅, 갤러리·팩·파일 요청 조율.
- `src/services/`: Telegram 연동, 팩 정규화, 파일 스트리밍, 해시.
- `src/auth/`, `src/cache/`, `src/validation/`, `src/http/`: 서버 인증·캐시·검증·응답 형식.
- `src/types.ts`: Worker binding·요청별 런타임·내부 저장 타입.

클라이언트의 Worker 요청 코드는 저장소 루트의 `TelegramSticker/Networking/`에 있습니다.
서버 내부 파일 ID·Bot Token은 이 HTTP 경계를 넘기지 않습니다.
전체 구조는 [File-structure.md](../../File-structure.md)를 참고하세요.

## API

- `GET /v1/packs/{name}`: 정규화된 메타데이터. `?refresh=1`은 메타데이터 캐시를 우회하며 실제 조회 시각 `fetchedAt`(Unix 초)과 `refreshed=true`를 반환합니다. 이름은 영숫자·밑줄 1~64자.
- `GET /v1/packs/{name}/assets/{id}?variant=original|thumbnail`: 해당 팩 소속 ID만 허용. 일반 팩의 정적·TGS·WebM 원본 제공.
- 모든 요청: `Authorization: Bearer <별도 테스트 접근키>`.
- 오류: `{"error":{"code":"…","retryable":false}}`; 재시도 가능한 제한 응답에는 `Retry-After`.

`file_id`와 토큰 포함 Telegram URL은 클라이언트에 전달하지 않습니다. SHA-256(file_unique_id)를 공개 항목 ID로 사용하며, Telegram 파일 다운로드는 Worker가 중계합니다. 임의 URL·file_id 프록시는 제공하지 않습니다.

## 나중에 계정을 준비한 뒤

배포 주소: `https://stickerbridge.stickerbridge-worker.workers.dev`. 2026-10-14 캐시 우회·파일 스트리밍 버전은 `7f6182a2-7d81-49cf-a5d6-bd2045152260`입니다. 사용자가 기존 정적 팩의 실제 가져오기와 오프라인 붙여넣기 성공을 확인했습니다. 실제 Telegram 애니메이션 팩과 대상 앱의 GIF 붙여넣기는 별도 검증 대상입니다. 다음은 최초 설정 및 재구성 절차입니다.

1. Cloudflare 계정에서 Worker 사용 가능 여부를 확인하고 `pnpm exec wrangler login`으로 본인이 로그인합니다.
2. `wrangler.jsonc`의 Worker 이름과 rate-limit namespace ID가 계정 내 다른 서비스와 충돌하지 않는지 확인합니다. 현재 `73001`, `73002`는 프로젝트 기본값입니다.
3. 배포가 승인된 단계에서 `pnpm exec wrangler deploy`로 코드를 배포합니다. Secret이 없으면 모든 요청은 503으로 실패합니다.
4. `pnpm exec wrangler secret put BOT_TOKEN`, `pnpm exec wrangler secret put ACCESS_KEY`의 대화형 입력에 각각 값을 직접 입력합니다. 명령행 인수·채팅·코드·Git에 값을 넣지 않습니다.
5. `ACCESS_KEY`는 Bot Token과 다른, 충분히 무작위인 32바이트 이상의 회수 가능한 값으로 준비합니다(예: 비밀번호 관리자). 앱에는 Worker HTTPS 원점 주소와 이 접근키만 입력합니다. 앱은 접근키를 해당 기기의 Keychain에 보관합니다.
6. 앱에서 허가된 공개 팩 링크를 미리보기·설치한 뒤 비행기 모드의 키보드 복사를 검증합니다.

Worker 소스는 `BOT_TOKEN`과 `ACCESS_KEY` Secret을 요구합니다. 로컬 upstream 연결이 필요하면 추적되지 않는 `.dev.vars`를 사용하되, 계정 준비 전 테스트는 가짜 응답만 사용합니다.

## 제한과 운영

- 인증·레이트 제한 후 내부 캐시 조회. 메타데이터 10분, 이미지 24시간.
- IP당 팩 20회/분, asset 240회/분. Cloudflare 위치별 제한이며 정확한 전역 비용 상한이 아닙니다.
- 메타데이터 JSON만 2MiB로 제한합니다. 파일은 20MiB 범위에서 스트리밍하며 선언 크기·실제 수신량을 검사합니다. TGS의 64KiB 압축 입력 방어는 유지합니다. API/헤더 조회 15초, 스트림 읽기 대기 30초 제한. 리다이렉트를 거부하고 토큰 URL은 노출하지 않습니다.
- Cloudflare workerd의 실행 제약을 확인해 `redirect: "manual"`과 3xx 명시적 차단을 사용합니다. Node mock만으로 런타임 fetch 옵션의 지원 여부를 증명할 수 없어 로컬 workerd도 검사했습니다.
- 원본 URL·인증값·upstream 예외를 로그나 오류 응답에 기록하지 않습니다. 앱도 기존 클립보드나 채팅 문맥을 수집하지 않습니다.
- 공개 배포용 인증·전역 사용량 통제·권리 검토는 미완료입니다. 개인 테스트용 접근키를 앱에 하드코딩하거나 공개 서비스 인증으로 사용하지 마세요.
- 서버는 형식별 헤더를 판별하고, 실제 이미지·영상 프레임·픽셀·디코딩 검증은 앱에서 수행합니다.

공식 자료: [Telegram Bot API](https://core.telegram.org/bots/api), [Cloudflare Secrets](https://developers.cloudflare.com/workers/configuration/secrets/), [Rate limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/), [Cache API](https://developers.cloudflare.com/workers/runtime-apis/cache/).


## 설정 없는 앱 연결 (2026-10-15)

일반 사용자는 서버 주소/접근키를 입력하지 않습니다. 앱은 고정된 운영 HTTPS 원점의
`POST /v1/session`에서 1시간짜리 HMAC 서명 이용 토큰을 자동 발급받습니다.
앱 프로세스 안에서 동시 요청의 토큰 발급을 공유하고, 만료 전에 갱신하며 401이면 한 번 재발급합니다.
Bot Token 및 기존 ACCESS_KEY는 앱에 포함하지 않습니다. 기존 수동 연결 Keychain 데이터는
읽지 않으며 사용자 설치 팩은 변경하지 않습니다.

`PUBLIC_IMPORT_ENABLED=true`는 로그인 없는 공개 서비스 모드입니다. 세션 발급과 팩 조회는
기존 IP별 PACK_LIMIT, 이미지 조회는 ASSET_LIMIT을 적용합니다. 임의 파일 프록시는 허용하지 않습니다.
이 세션은 앱의 진위를 증명하는 인증이 아닙니다. 누구나 같은 공개 세션 API를 호출할 수 있고,
IP별 제한도 분산 남용이나 전역 비용 상한을 보장하지 않습니다. App Attest는 아직 구현하지 않았습니다.
공개 배포 전 운영 사용량/비용 제한 및 필요 시 App Attest를 별도로 준비해야 합니다.
긴급 차단하려면 PUBLIC_IMPORT_ENABLED를 false로 바꿉니다. 기존 ACCESS_KEY 인증 경로는 유지됩니다.
ACCESS_KEY 교체 시 기존 세션은 무효화되며 앱이 새 세션을 발급받습니다.

이번 변경의 확인 범위: Simulator 앱 빌드와 TypeScript 타입 검사. 테스트 및 실제 신규 설치
가져오기 흐름은 실행하지 않았습니다.


## 원격 추천 목록 관리

Cloudflare Dashboard → Storage & databases → KV → **GALLERY_CATALOG** → KV Pairs에서
**recommended-packs**의 값을 편집합니다. 한 줄에 `https://t.me/addstickers/<name>` 하나씩
넣고 저장하세요. 줄 순서가 갤러리 순서이며 같은 팩은 처음 한 번만 표시됩니다.
추가/삭제/정렬에 앱 또는 Worker 재배포가 필요하지 않습니다.

- 모두 숨기려면 값을 빈 문자열로 저장합니다. 키 자체를 삭제하면 설정 오류로 처리됩니다.
- JSON이나 쉼표 목록이 아니라 줄바꿈으로 구분한 링크 목록입니다.
- 잘못된 링크가 포함되면 서버는 gallery_catalog_invalid를 반환하고 앱은 마지막 정상 목록을 유지합니다.
- 앱에서 갤러리를 당겨 새로고침할 수 있습니다. KV 전파/캐시 때문에 60초 이상 걸릴 수 있습니다.
- `/v1/gallery`는 기존 서비스 이용 토큰 인증 및 PACK_LIMIT을 적용합니다.
- 새로운 KV namespace를 다시 구성할 때는 wrangler.jsonc의 GALLERY_CATALOG binding을 연결하고
  recommended-packs 키를 먼저 등록해야 합니다. 기존 팩 API는 KV 장애와 관계없이 유지됩니다.

2026-10-15 생성 namespace: fcb899c9239c42319083ddb5b260089a.
배포 버전: 6b5f341f-d99b-46cf-b737-46468650ad0a.
배포 후 실제 `/v1/gallery` 응답에서 초기 11개 링크의 개수와 순서를 확인했습니다.
