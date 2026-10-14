# Milestone 3 — 코드와 로컬 검증

> 후속 변경: 일부 파일 실패 시 성공 항목을 설치하고 실패 항목만 재시도하도록 정책을 변경했습니다. 아래의 미게시 설명은 최초 M3 검증 당시 기록입니다. 현재 동작은 [부분 설치·키보드 UI](PartialInstall-KeyboardUX.md)를 참고하세요.

처음에는 계정·Bot 준비 전 코드와 로컬 테스트를 진행했습니다. 이후 사용자의 계정·Bot 준비 및 OAuth 승인에 따라 2026-10-13 Worker를 최초 배포했습니다. 두 Secret 등록과 HTTPS 인증 차단 응답을 확인했습니다. 서버 실행 옵션 수정 후 사용자가 실제 팩 미리보기·설치와 오프라인 목록·복사·붙여넣기를 성공했다고 확인해 **M3 핵심 게이트를 통과**했습니다. 대상 앱 이름·투명도·팩 URL과 iPad 실기기 결과는 미기록이며 이후 검증 항목으로 유지합니다.

최초 배포: `https://stickerbridge.stickerbridge-worker.workers.dev`, 버전 `b7110fbf-023d-4302-aee2-e8c9aa9d75e2`. 기존 동명 Worker가 없음을 확인한 뒤 배포했습니다. rate-limit 두 binding 포함, Secret 목록은 배포 직후 비어 있습니다. 최초 공개 URL 확인은 TLS handshake 실패로 HTTP 응답을 확인하지 못했으며, DNS/TLS 전파 후 재검증해야 합니다.

후속 확인: 사용자가 두 Secret 등록·Deploy 완료를 알린 후 `wrangler secret list`에서 `BOT_TOKEN`, `ACCESS_KEY`의 `secret_text` 등록을 확인했습니다(값은 읽지 않음). 공개 HTTPS URL에 인증 없는 요청은 HTTP 401과 `unauthorized`, `retryable:false`로 응답해 이전 TLS 실패가 해소되었습니다. 이 응답은 Bot 토큰 유효성이나 Telegram 접근 성공을 증명하지 않습니다. 최신 개발 서명 앱은 iPhone 15 Pro에 설치했고, 앱 내 연결 설정과 실제 팩 가져오기 결과를 사용자에게 요청했습니다.

### 실제 미리보기 오류 수정

사용자 실기기의 ‘가져오기 서버에서 응답하지 않아요’ 오류를 추적했습니다. 인증은 통과했지만 Telegram HTTP 응답 전에 실패했습니다. Wrangler 4.149.0의 로컬 workerd에서 동일 코드를 가짜 토큰으로 실행해 `redirect: "error"`가 `Invalid redirect value`로 거부되는 것을 재현했습니다. Node mock 테스트는 이 런타임 제약을 검증하지 못했습니다.

Telegram API·파일 요청 모두 `redirect: "manual"`로 수정하고 3xx는 응답 본문을 취소한 뒤 `upstream_redirect`로 차단합니다. 리다이렉트 주소나 토큰은 전달·로그하지 않습니다. Telegram 401/403은 `telegram_auth_failed`, 재시도 불가로 구분합니다. 서버 5xx 진단은 고정된 실패 단계·오류 코드·HTTP 상태·분류값만 출력합니다. 실시간 진단 출력도 이 필드만 추려 확인했습니다.

수정 검증: Node 테스트 11개와 TypeScript 검사 통과. 로컬 workerd의 가짜 토큰 요청이 Telegram 응답(인증 거절)까지 도달해 기존 redirect 실행 오류 해소 확인. 사용자 계정의 Worker에 버전 `bd62b51e-7cf2-489c-8a28-a285f1de216b` 배포 완료. 실제 토큰으로 팩 미리보기·설치 성공 여부는 사용자 재시도 결과 대기 중입니다.

회귀 검사 보완: Wrangler와 같은 Miniflare 버전을 개발 의존성으로 고정하고 production 진입점을 실제 workerd에서 실행하는 테스트를 추가했습니다. 외부 요청은 outbound service의 가짜 Telegram 응답으로만 처리합니다. rate-limit과 캐시를 포함해 메타데이터·PNG 중계가 200으로 실행되고, API 302·파일 307이 다른 주소를 따라가지 않고 차단되는 것을 확인했습니다. 현재 `pnpm test`는 12개 모두 통과합니다. 이 테스트는 실제 사용자의 Bot 토큰과 팩 접근 성공 증거를 대신하지 않습니다.

사용자 실기기 재검증: 수정 배포 후 iPhone에서 **팩 미리보기·설치 모두 성공**했다고 확인했습니다. 팩 링크·제목은 아직 제공되지 않았으며, 성공 범위를 모든 팩으로 일반화하지 않습니다. 방금 설치한 팩을 네트워크 없이 키보드에서 열람·복사하고 대상 앱에 붙여넣는 M3 최종 게이트는 확인 대기 중입니다.

최종 게이트 후속 답변: 사용자가 비행기 모드·Wi‑Fi OFF의 확인 요청에 **오프라인 목록·복사·붙여넣기 성공**으로 답했습니다. 기기는 연결된 iPhone 15 Pro이며 OS는 이전 확인 기준 27.2입니다. 대상 앱 이름·투명도 결과는 답변에 없어 미기록으로 남깁니다. 이를 근거로 M4 온보딩·최근 사용 구현을 시작했습니다. 아래 목록은 일부 성공 확인 후에도 남는 세부 검증 항목입니다.

## 구현

- `TelegramSticker/Import`: 엄격한 링크 파서, Keychain 연결 설정, URLSession client, 최대 3개 네트워크 요청, 직렬 Image I/O 변환, 진행률·취소·완료 파일 재사용.
- 일반 팩의 정적 PNG/WebP만 설치. TGS/WebM과 특수 팩은 표시하되 원본 설치하지 않음.
- 손실·무손실 WebP를 PNG로 변환하고 투명·반투명·불투명 픽셀 보존 검사.
- 원본/PNG 2MiB, 100만 픽셀, 게시 팩의 PNG·썸네일·manifest 합계 128MiB 제한.
- 일부 실패 시 인덱스를 게시하지 않음. 재시도 시 준비된 PNG 재검증·재사용. 이미 설치한 팩은 네트워크 요청 전에 차단.
- 취소·종료된 작업 파일은 앱 전용 Application Support/ImportJobs에 남아 같은 팩 재시도에 사용됨. 다른 팩 설치를 시작할 때 이전 hash 디렉터리를 정리하며, 성공 시 현재 작업도 제거함. 이 정책은 가져오기 화면에서 안내함. 설치된 App Group 팩과 알 수 없는 파일은 정리 대상이 아님.
- 프로세스 내 공유 lease로 가져오기 화면이 닫혔다 다시 열려도 이전 작업의 취소가 끝나기 전에는 다른 작업이 파일을 정리하지 못하게 함. 이전 작업 정리 중에는 재시도 안내를 표시함. 프로세스가 종료되면 lease는 사라져 다음 실행에서 다시 시도할 수 있음.
- 앱·확장의 기존 타깃, iOS 27.0, Signing과 Bundle ID 유지. 네트워크·Keychain 코드는 앱 타깃에만 포함.
- Worker는 별도 테스트 접근키 인증, 입력 검증, 소속 검증, bounded stream, Secret 토큰 중계, 캐시·레이트 제한 구현.

## 검증 명령

2026-10-13 실행 결과:

| 검사 | 결과 |
|---|---|
| iPhone 18 Pro Max Simulator / iOS 27.0 | 단위 23개 + UI 4개 통과 |
| iPad Pro 13형 M5 Simulator / iOS 27.0 | 단위 23개 + UI 4개 통과 |
| Worker Node 테스트 | 9개 통과 |
| TypeScript strict 검사 | 통과 |
| Wrangler 4.149.0 dry-run | 통과, 업로드 없음 |
| pnpm 11.25.0 frozen-lockfile 설치 | 통과, 의존성 lifecycle scripts 미실행 |
| git diff --check | 통과 |

총 27개 테스트를 두 Simulator에서 54회 실행했으며 실패·건너뜀·런타임 경고가 없습니다. Xcode의 AppIntents 미사용 메타데이터 경고와 테스트 시작 시 debugger 조회 진단은 있었으나 테스트 실행은 성공했습니다. 결과 번들: `/tmp/StickerBridge-M3-Final.xcresult`, 로그: `/tmp/StickerBridge-M3-final.log`. UI 첨부 이미지에서 iPhone/iPad 미리보기의 내용·버튼·썸네일 배치를 확인했습니다. 임시 경로의 결과물은 시스템 정리 시 사라질 수 있습니다.

후속 복구 보완 검증: iPhone Simulator에서 ImportTests 8개 통과 (`/tmp/StickerBridge-M3-Recovery.xcresult`). 다운로드 도중 취소해도 기존 인덱스 revision과 설치 팩이 유지되고, 취소 후 재시도가 성공함을 확인했습니다. 같은 팩 재시도 파일 보존, 다른 팩 시작 시 이전 임시 파일 정리, 진행 중 작업 보호, 알 수 없는 파일 보존도 확인했습니다. 이 보완 후 전체 54회 검사를 반복한 것은 아닙니다.

Release 검증: `generic/platform=iOS`, `Release`, `CODE_SIGNING_ALLOWED=NO`로 앱과 키보드 확장 빌드 성공 (`/tmp/StickerBridge-M3-release.log`). Release 앱 바이너리에서 DEBUG fixture 클래스·실행 인수·가짜 서버·테스트 접근키 표식이 없음을 확인했습니다. 확장은 포함되어 있고, 확장 바이너리에는 가져오기 client·설정·coordinator와 Telegram 주소 표식이 없습니다. 이는 서명 없는 기기용 컴파일·패키징 검사이며 App Store 배포 서명이나 실기기 실행을 검증한 것은 아닙니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project TelegramSticker.xcodeproj -scheme TelegramSticker \
  -destination 'platform=iOS Simulator,id=5ABA3105-0BE7-4C40-8FF9-2E8388758F39' \
  -destination 'platform=iOS Simulator,id=BAE113D3-1819-4943-997C-2A0583CA5ED5' \
  -parallel-testing-enabled NO test
```

Worker 명령은 [README](../backend/worker/README.md)에 있습니다. 테스트는 가짜 Telegram 응답으로 인증·제한·토큰 비노출·크기 초과·경로 조작·형식 제한·만료 경로 재조회·오류 정제를 검증합니다. Cloudflare 운영 환경의 제한 정확도나 실제 Telegram 접근성을 증명하지 않습니다.

앱 단위 테스트는 링크 변형·악성 입력, Bot Token 오입력 거부, HTTP 인증 실패, 메타데이터 불일치, 이미지 변환, 부분 실패 미게시·재시도, 중복 차단, 서버별 draft 복원을 검증합니다. WebP fixture는 자체 제작 샘플 PNG로 생성한 CC0 테스트 이미지입니다.

UI 테스트는 DEBUG 전용 `--import-ui-fixture` launch argument에서만 URLProtocol로 자체 PNG와 혼합 형식 메타데이터를 반환합니다. Keychain을 변경하지 않고 네트워크를 사용하지 않습니다. 실제 배포 코드의 서버 설정 기본값으로 사용하지 않습니다.

## 실제 연동 시 남은 게이트

1. 개인 테스트 Worker 배포와 두 Secret 설정(별도 실행 요청 필요).
2. 허가된 공개 일반 팩·없는 팩·애니메이션만 있는 팩의 실제 응답 확인.
3. 정상 팩 설치 후 비행기 모드에서 키보드 열람·PNG 복사·대상 앱 붙여넣기 확인.
4. 앱 종료·네트워크 중단·저장 공간 부족·실기기 권한 변경 확인.
5. 기기/OS/대상 앱 버전, 복사/붙여넣기/투명도/전송 결과를 개별 기록. 현재 M3 항목은 모두 실기기 미검증.
