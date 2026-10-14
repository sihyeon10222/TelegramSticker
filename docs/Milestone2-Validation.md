# Milestone 2 — 로컬 팩과 공유 저장소

## 범위

기존 앱과 키보드 타깃에 `group.com.sihyeon.TelegramSticker` App Group을 연결합니다. 메인 앱에서 자체 제작 PNG로 된 기본 샘플(3개), 하트와 별(2개) 팩을 설치·삭제·정렬하고 복사·시스템 공유를 제공합니다. 키보드는 설치된 팩을 읽고 전체/팩별로 표시합니다. 서버·Telegram·외부 패키지는 추가하지 않았습니다.

M1은 사용자가 개발자 신뢰 후 직접 정상 작동을 확인하고 다음 단계 진행을 요청했습니다. 대상 앱 이름·투명도·iPad 결과는 별도로 미검증입니다.

## 저장 구조와 실패 처리

- `Shared/StickerLibrary.swift`: 버전 있는 Codable 인덱스·manifest와 읽기 전용 reader. 앱·확장 양쪽에 포함됩니다.
- `TelegramSticker/LibraryWriter.swift`: 앱 전용 actor. 키보드 타깃에는 포함하지 않습니다.
- `StickerLibrary/staging/<UUID>` → PNG 검증·256px 썸네일·SHA256 기록 → `packs/<packID>/<revision>`으로 이동 → 마지막에 `index.json`을 원자적으로 기록합니다.
- 게시 전 오류/취소는 기존 인덱스를 유지합니다. 원본 PNG 바이트와 투명도를 보존합니다.
- 삭제는 인덱스에서 먼저 제외한 뒤 파일을 정리합니다. 이전 목록을 보던 키보드가 파일 오류를 만나면 다시 읽습니다.
- 앱 시작 시 임시 파일을 정리합니다. 유효한 기존 인덱스가 있을 때만 24시간 넘은 미참조 revision을 정리합니다. 잘못된/새 버전 인덱스 때문에 정상 팩을 삭제하지 않습니다.
- 상대 경로 탈출, 절대 경로, 심볼릭 링크를 거부합니다. 팩/파일 크기와 개수도 제한합니다.
- 깨진 manifest는 다른 팩과 분리해 경고하고 앱에서 삭제할 수 있습니다. 인덱스 자체 손상은 안내만 표시하고 보존합니다.
- 공유 컨테이너를 사용할 수 없으면 앱은 원인을 안내하고 키보드는 번들 샘플로 복구합니다. 키보드의 목록 읽기는 Full Access로 차단하지 않으며 복사 직전에만 권한을 검사합니다.

## 서명 확인

앱·키보드의 실기기 빌드가 성공했으며 양쪽 provisioning profile과 서명 entitlement에 동일한 App Group이 포함됨을 확인했습니다. App Group 추가를 위해 Bundle ID·Team·최소 OS·Swift 언어 모드는 바꾸지 않았습니다.

## 자동 검증

저장소 단위 테스트: 전체 팩 원자적 게시, 재시작 reader, 디스크 부족을 주입한 게시 실패, 손상 PNG, 동시 중복 설치, 정렬·삭제·오래된 정렬 요청, 잘못된 JSON·미지원 schema 보존, 경로 탈출·심볼릭 링크, 누락 manifest·PNG, 중단 staging·고아 revision 정리를 검사합니다.

기존 M1 PNG·권한 테스트도 유지합니다. 앱 UI는 로컬 팩 설치 → 앱 재실행 → PNG 복사 → 팩 삭제 흐름과 기존 샘플/안내·회전 흐름을 검사합니다.

- iPhone·iPad Simulator에서 각 17개 단위 테스트와 3개 UI 테스트, 총 40회 실행이 통과했습니다.
- PNG 공유 시트 표시 검사를 추가하면서 시스템 뷰 식별자 차이로 실패했던 테스트를 수정했습니다. 수정한 설치·재실행·복사·공유 시트 표시·삭제 통합 UI 테스트가 양쪽 Simulator에서 다시 통과했습니다(2회, 실제 실행 개수 확인).
- 마지막 키보드 오류 안내 보완까지 실기기 빌드·설치에 성공했습니다. 사용자 검증 이후의 보완은 파일 오류 안내 유지와 화면/접근성 명칭 수정입니다.
- 결과 번들: `/tmp/StickerBridge-M2-Tests-2.xcresult`, `/tmp/StickerBridge-M2-ShareContent.xcresult`. 마지막 공유 검사는 로딩 배경만 확인하지 않고 실제 시스템 공유 항목 목록이 나타날 때까지 검사해 양쪽에서 통과했습니다. 전체 테스트 이후 변경한 공유 검사만 추가 실행했으며, 전체 검사를 다시 실행했다고 주장하지 않습니다.

## 실기기 확인 순서

1. 새 빌드를 설치한 뒤 앱의 **내 스티커 팩 → + → 기본 샘플 추가**, **하트와 별 추가**를 실행합니다.
2. 팩 상세에서 복사와 공유를 확인합니다. 공유 시트의 대상 앱 지원 여부는 대상 앱에 따라 다릅니다.
3. 목록의 **편집**으로 순서를 바꿉니다. 앱을 다시 열어 같은 순서가 유지되는지 확인합니다.
4. 메모 등 입력창에서 StickerBridge로 전환합니다. **전체 / 기본 샘플 / 하트와 별** 탭과 팩별 스티커 수를 확인합니다.
5. 전체 접근 OFF에서도 설치 팩 목록을 볼 수 있고 탭하면 복사 권한 안내가 나오는지 확인합니다. ON에서는 복사 후 사용자가 붙여넣습니다.
6. 앱에서 팩을 삭제하고 키보드에 재진입하거나 팩 탭을 누르면 목록이 갱신되는지 확인합니다. 전부 삭제하면 번들 샘플이 표시됩니다.
7. 비행기 모드, 앱/확장 재시작, iPad 회전·공유 시트도 확인합니다.

| 항목 | iPhone 실기기 | iPad 실기기 |
|---|---|---|
| App Group 포함 빌드·서명 | 확인 | 같은 산출물, 설치 미검증 |
| 설치·실행 | 설치·실행 성공 | 미검증 |
| 앱→키보드 팩 목록·순서 공유 | 사용자 확인: 정상 | 미검증 |
| Full Access OFF에서 공유 파일 읽기 | 사용자 확인: 정상 | 미검증 |
| 공유 시트·PNG 붙여넣기·투명도 | 미검증 | 미검증 |
| 삭제·순서 변경 후 키보드 재진입 | 사용자 확인: 정상 | 미검증 |
| 비행기 모드·전체 앱 재시작 | 미검증 | 미검증 |

사용자가 iPhone에서 목록 공유, Full Access OFF 읽기, 삭제·순서 반영을 모두 확인했다고 보고했습니다. 이를 M2 핵심 실기기 게이트 통과 근거로 기록합니다. iPad 실기기·대상 앱별 공유·투명도 등 나머지 항목은 추정하지 않습니다. Telegram/Worker는 M3 범위입니다.

## 실행 명령

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project TelegramSticker.xcodeproj -scheme TelegramSticker \
  -destination 'platform=iOS Simulator,id=5ABA3105-0BE7-4C40-8FF9-2E8388758F39' \
  -destination 'platform=iOS Simulator,id=BAE113D3-1819-4943-997C-2A0583CA5ED5' \
  -parallel-testing-enabled NO test
```

## 권한 근거

Apple 문서는 Full Access 미허용 키보드에도 containing app의 공유 컨테이너 읽기 전용 접근을 허용한다고 설명합니다. 실제 지원 OS와 서명에서는 위 실기기 절차로 검증합니다. [Apple Open Access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)

## 롤백

이번 단계의 Shared 소스·앱 팩 화면·키보드 reader 연결 및 App Group entitlement만 이전 단계로 되돌립니다. 번들 샘플·복사 서비스·기존 타깃은 유지합니다. App Group의 사용자 팩 데이터를 자동 삭제하거나 프로젝트 전체를 초기화하지 않습니다.
