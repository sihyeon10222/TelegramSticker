# Milestone 1 검증

## 상태

- 서버 없는 PNG 키보드 기술 검증 단계입니다. M2 이후 기능은 구현하지 않았습니다.
- 최소 지원 OS: iOS/iPadOS 27.0. 기존 앱·확장·테스트 타깃, Bundle ID, Team 유지.
- Simulator 빌드: 성공. iPhone·iPad에서 각각 단위 테스트 9개, UI 테스트 2개가 통과했습니다(총 22개 실행).
- **사용자가 개발자 신뢰 후 직접 정상 작동을 확인하고 M2 진행을 요청했습니다.** 대상 앱 이름·투명도·iPad 결과는 별도로 미검증입니다. 아래 자동 테스트 결과는 M1 당시 기록입니다.

### 실기기 설치 확인 — 2026-10-13

- iPhone 15 Pro / iOS 27.2 연결 및 Developer Mode 활성화를 확인했습니다.
- 기존 Team과 자동 서명으로 앱·확장 실기기 빌드가 성공했고 앱 설치도 성공했습니다.
- `codesign --verify --deep --strict` 검사는 통과했습니다.
- 실행 요청은 iOS가 보안 사유로 거부했습니다. 오류는 서명·entitlement 또는 개발자 프로파일 신뢰 문제를 열거하므로, 원인을 신뢰 문제로 확정하지 않습니다. 기기에서 개발자 신뢰 상태와 직접 실행 결과를 확인하는 중입니다.
- 이후 사용자가 개발자 신뢰를 누른 뒤 직접 테스트했고 정상 작동한다고 보고했습니다. 이에 따라 M2로 진행합니다. 대상 앱별 세부 결과는 보고되지 않았으므로 추정하지 않습니다.
- iPad 실기기는 미검증입니다.

## 구현 경계

앱과 키보드가 `StickerSamples`의 소스와 PNG 리소스를 각자의 번들에 포함합니다. 이는 Xcode 소스 멤버십이며 App Group이 아닙니다. 네트워크·Telegram·공유 저장소·외부 의존성이 없습니다.

복사 서비스는 권한을 먼저 검사하고 파일 읽기·PNG 검증 뒤 `public.png` Data를 `UIPasteboard.setItems`에 기록합니다. Handoff를 제한하는 `localOnly`를 사용합니다. 기존 클립보드나 채팅 문맥은 읽지 않습니다. API에 붙여넣기 성공 콜백이 없으므로 `복사됨`은 기록 요청 안내입니다.

메인 앱의 입력 칸은 시스템 키보드 전환 연습용입니다. 이미지 붙여넣기 대상이 아니며 입력한 텍스트는 저장하지 않습니다. 이미지 검증은 아래 대상 앱에서 진행합니다.

## 자동 검증 결과

| 환경 | 앱+확장 빌드 | 단위 테스트 | 메인 앱 UI 테스트 |
|---|---|---|---|
| iPhone 18 Pro Max Simulator / iOS 27.0 | 성공 | 9개 통과 | 2개 통과 |
| iPad Pro 13-inch (M5) Simulator / iPadOS 27.0 | 성공 | 9개 통과 | 2개 통과 |

단위 테스트는 권한 거부 시 I/O 미실행, 파일 누락·읽기 실패, 손상·잘림·타 형식·크기 초과 거부, PNG 바이트 및 알파 보존, 양쪽 번들의 동일 리소스·표시명·Full Access 설정, 권한 재평가를 검사합니다. 메인 앱 UI 테스트는 3개 복사 버튼의 피드백·설정 안내·회전 후 사용성을 검사합니다. 이 테스트는 실제 키보드의 시스템 권한이나 대상 앱의 붙여넣기를 대신하지 않습니다.

## 실행 명령

프로젝트 디렉터리에서 실행합니다. `DEVELOPER_DIR`로 설치된 Xcode를 선택하므로 전역 `xcode-select`를 바꿀 필요가 없습니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project TelegramSticker.xcodeproj -scheme TelegramSticker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=5ABA3105-0BE7-4C40-8FF9-2E8388758F39' \
  CODE_SIGNING_ALLOWED=NO build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project TelegramSticker.xcodeproj -scheme TelegramSticker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=5ABA3105-0BE7-4C40-8FF9-2E8388758F39' \
  -destination 'platform=iOS Simulator,id=BAE113D3-1819-4943-997C-2A0583CA5ED5' \
  -parallel-testing-enabled NO test
```

## 실기기 준비

1. iOS/iPadOS 27 이상 기기를 Mac에 연결하고 신뢰·Developer Mode를 활성화합니다.
2. Xcode의 두 타깃 Signing & Capabilities에서 기존 Team과 Automatic signing을 확인합니다. App Group은 추가하지 않습니다.
3. `TelegramSticker` scheme으로 기기에 설치합니다.
4. 설정 → 일반 → 키보드 → 키보드 → 새로운 키보드 추가 → StickerBridge.
5. 처음에는 전체 접근을 끕니다. 메인 앱 안내에 있는 전환 연습 칸에서 지구본을 길게 눌러 StickerBridge를 선택합니다.

## 실기기 시나리오

1. 전체 접근 OFF: PNG 3개가 표시되고 스크롤·키보드 전환이 가능합니다. 탭하면 권한 안내가 보이며 복사를 시도하지 않아야 합니다.
2. Apple 한국어·영어·이모지 키보드로 왕복 전환합니다. 시스템 지구본이 있는 기기에서는 중복 지구본을 표시하지 않습니다. 확장 내 버튼이 필요한 기기에서는 짧은 탭과 길게 누르기를 모두 확인합니다.
3. 키보드 설정에서 전체 접근을 ON으로 바꾸고 대상 앱 입력창에 다시 진입합니다.
4. 스티커 탭 → `복사됨 · 채팅창에서 붙여넣기` → 대상 앱에서 직접 붙여넣기 → 본인에게 보내기 등 사용자가 선택한 곳에 직접 전송합니다. 자동 전송은 없습니다.
5. 세 이미지의 배경 투명도와 반투명 영역을 밝고 어두운 배경에서 비교합니다. 하트의 작은 보라색 하트, 별의 둥근 빛 테두리는 반투명입니다.
6. 같은 PNG를 메인 앱에서 복사한 결과와 비교합니다. 키보드에서만 실패하면 권한/확장 경로를, 양쪽 모두 특정 앱에서 실패하면 대상 앱 지원 여부를 조사합니다.
7. 전체 접근을 다시 OFF로 바꾸고 복사가 차단되는지 확인합니다. 기존 클립보드가 남아 있을 수 있으므로 OFF 상태에서 기존 이미지를 붙일 수 있다는 이유로 새 복사가 성공했다고 판단하지 않습니다.
8. 앱·확장 재실행, 비행기 모드, iPad 회전·floating, 큰 글자·VoiceOver를 확인합니다. 앱 자체의 표시와 실제 전송 결과를 따로 기록합니다.

## 실기기 결과표

실제로 관찰한 값만 적습니다. iPhone 연결·설치와 별개로 아래 사용자 시나리오는 아직 미검증입니다.

| 기기 | OS | 대상 앱/버전 | Full Access | 키보드 표시 | 복사 안내 | 붙여넣기 | 투명도 | 수동 전송 |
|---|---|---|---|---|---|---|---|---|
| iPhone 15 Pro | 확인 필요 | 메모 / 확인 필요 | OFF·ON·재OFF | 미검증 | 미검증 | 미검증 | 미검증 | 미검증 |
| iPhone 15 Pro | 확인 필요 | 메시지 / 확인 필요 | ON | 미검증 | 미검증 | 미검증 | 미검증 | 미검증 |
| iPhone 15 Pro | 확인 필요 | 카카오톡 / 확인 필요 | ON | 미검증 | 미검증 | 미검증 | 미검증 | 미검증 |
| iPad Pro 12.9형 M2 | 확인 필요 | 메모 / 확인 필요 | OFF·ON·재OFF | 미검증 | 미검증 | 미검증 | 미검증 | 미검증 |
| iPad Pro 12.9형 M2 | 확인 필요 | 메시지 / 확인 필요 | ON | 미검증 | 미검증 | 미검증 | 미검증 | 미검증 |
| iPad Pro 12.9형 M2 | 확인 필요 | 카카오톡 / 설치 여부 확인 | ON | 미검증 | 미검증 | 미검증 | 미검증 | 미검증 |

완료 게이트: 실기기에서 키보드가 표시되고 최소 한 대상 앱에서 PNG 복사·붙여넣기가 확인되어야 합니다. 카카오톡과 iPad 결과는 별도로 명시합니다. 사용자의 정상 작동 보고와 명시적인 다음 단계 요청을 근거로 M2에 진행했으며, 위 표의 앱별 상세 결과는 계속 미검증으로 구분합니다.

## 진단과 제한

- 서명 실패: 개발자 계정·Team·기기 등록·provisioning profile 문제를 먼저 확인합니다.
- 복사 권한 안내: 해당 StickerBridge 키보드의 전체 접근 설정을 확인하고 입력창에 다시 진입합니다.
- 이미지 오류: 원본 PNG의 번들 포함 여부·파일 손상을 확인합니다. 클립보드를 읽어 검사하지 않습니다.
- 대상 앱 붙여넣기 불가: 메인 앱에서 같은 샘플을 복사해 비교합니다. M2의 메인 앱 공유 기능이 후속 대안이며 현재 구현되어 있지 않습니다.
- 스티커 전용 MVP에는 문자 입력 기능이 없습니다. App Review 4.4.1 적합성 및 실제 심사 통과를 보장하지 않습니다.

## 참고

- [Apple Custom Keyboard](https://developer.apple.com/documentation/uikit/creating-a-custom-keyboard)
- [Apple Open Access](https://developer.apple.com/documentation/uikit/configuring-open-access-for-a-custom-keyboard)
- [Apple 보관 문서: UIPasteboard와 Open Access](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/CustomKeyboard.html)
- [App Review 4.4.1](https://developer.apple.com/app-store/review/guidelines/#extensions)
