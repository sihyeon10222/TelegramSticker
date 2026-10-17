# StickerBridge

Telegram 스티커 팩을 iPhone·iPad에 저장하고, 키보드에서 복사해 채팅 앱에 붙여넣는 앱입니다.
정적 스티커와 움직이는 스티커를 지원하며, 설치한 팩은 오프라인에서도 사용할 수 있습니다.

## 주요 기능

- **팩 가져오기**: 공개 Telegram 스티커 팩 링크를 입력하거나 갤러리에서 추천 팩을 골라 설치합니다. 여러 팩을 함께 가져올 수 있습니다.
- **스티커 키보드**: 팩별 목록과 최근 사용 목록에서 스티커를 복사합니다. 좌우로 밀어 팩을 전환하고, 팩 탭을 길게 눌러 순서를 바꿀 수 있습니다.
- **움직이는 스티커**: TGS·WebM 스티커를 기기에서 GIF로 변환합니다. 앱과 키보드에서 재생하며, 정적 PNG로도 복사할 수 있습니다.
- **팩 관리**: 설치한 팩의 미리보기·정렬·삭제·업데이트 확인, 일부 실패한 항목의 재시도를 지원합니다.
- **용량 관리**: 화질과 용량을 비교해 최적화하고, 필요하면 Telegram 원본을 다시 받아 복원합니다. 캐시 정리와 다운로드 로그 확인도 제공합니다.
- **링크 공유**: 팩 링크를 텍스트나 목록 파일로 공유하고, 받은 목록 파일에서 팩을 가져옵니다.

## 사용 방법

1. 앱을 열고 안내에 따라 **StickerBridge 키보드 추가**와 **전체 접근 허용**을 완료합니다. 안내 화면의 입력칸에서 키보드를 열어 허용 상태를 확인합니다.
2. **내 스티커 팩 → +**에서 공개 팩 링크를 입력하거나 **갤러리**에서 원하는 팩을 설치합니다.
3. 채팅 앱에서 지구본 버튼으로 StickerBridge 키보드를 선택합니다.
4. 스티커를 눌러 복사한 뒤 채팅 입력창에 붙여넣습니다.

지원 링크 형식: `https://t.me/addstickers/<팩이름>`

스티커 복사에는 키보드의 전체 접근 허용이 필요합니다. 키보드는 입력 내용이나 기존 클립보드 내용을 읽지 않으며, 설치된 스티커를 사용해 오프라인으로 동작합니다.
GIF의 움직임·투명도와 붙여넣기 방식은 대상 채팅 앱의 지원에 따라 달라집니다.
새 팩 설치·업데이트·원본 복원에는 인터넷 연결이 필요합니다.

## 앱 구성

| 구성 | 역할 |
| --- | --- |
| iOS 앱 | 팩 탐색·다운로드·로컬 변환·설치·용량 최적화 |
| 키보드 확장 | 설치된 스티커 표시·팩 전환·최근 사용·PNG/GIF 복사 |
| 공통 코드 | 앱·키보드가 사용하는 모델·저장소 읽기·이미지 처리·복사 |
| 서버 백엔드 | Telegram API 연동·팩 정보·파일 중계·추천 목록·세션·요청 제한 |

앱은 SwiftUI, 키보드는 UIKit으로 구성되어 있습니다. TGS 변환에는 Lottie, WebM 변환에는 libvpx 기반의 로컬 `StickerVP9` 패키지를 사용합니다.
백엔드는 TypeScript로 작성한 Cloudflare Worker이며, Telegram Bot Token은 서버에서 관리합니다. 앱은 서비스 이용 세션을 자동으로 발급받습니다.

## 개발 및 참고 문서

현재 프로젝트의 최소 지원 버전은 **iOS·iPadOS 27.0**입니다.
해당 SDK가 포함된 Xcode에서 `TelegramSticker.xcodeproj`를 열고 `TelegramSticker` 스킴을 실행합니다.
실기기 실행 시 개발 팀과 앱·키보드의 App Group 서명을 설정해야 합니다.

- [파일 구조와 작업별 시작 파일](File-structure.md)
- [개발 작업 지침](AGENTS.md)
- [백엔드 설정 및 API](backend/worker/README.md)
- [구현·검증 기록](docs/)
- [외부 라이브러리 고지](TelegramSticker/Resources/ThirdPartyNotices.txt)

저장소의 자체 제작 샘플 PNG는 CC0-1.0으로 제공합니다. 갤러리는 공개 팩 링크를 제공하며, 스티커 파일은 미리보기·설치 시 Telegram에서 받아옵니다.

## 맥에서 사용하기

Mac Catalyst의 iPad UI 모드로 macOS 27.0 이상에서 실행합니다. 하단 탭·사이드바·상세 및 툴바 구성은 iPad와 공유합니다. 창은 최소 640×480pt부터 크기를 조절할 수 있고, 좁은 창에서는 목록과 상세를 한 열로 표시합니다. 앱에서 팩을 설치한 다음 스티커를 클릭해 선택하고 **⌘C**를 누른 뒤 채팅창에 **⌘V**로 붙여넣으세요. 우클릭 메뉴에서 GIF 대신 PNG로 복사하거나 공유할 수 있습니다. **⌘O**는 `.stickerlinks` 링크 목록 파일을 엽니다. 팩 목록과 스티커 선택 영역의 **⌘A**도 지원합니다. 붙여넣기의 애니메이션·투명도는 대상 앱의 지원에 따라 달라집니다.

맥에서는 iOS 키보드 확장을 설치하지 않으며 전체 접근 설정이 필요하지 않습니다. 앱이 실행 중이면 다른 앱을 사용하거나 창을 최소화해도 가져오기를 계속합니다. 앱을 종료한 동안에는 작업하지 않으며, 미완료 가져오기는 재실행 후 기존 작업 파일로 이어받습니다.

Xcode의 `TelegramSticker` 스킴에서 **My Mac (Mac Catalyst)**를 선택하거나 다음으로 빌드합니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project TelegramSticker.xcodeproj -scheme TelegramSticker \
  -configuration Debug -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -allowProvisioningUpdates build
```

## iCloud 동기화와 개발자 서명

동기화 코드는 앱에 포함되며 **팩 목록·순서·팩 삭제**를 같은 Apple 계정의 기기 사이에서 맞춥니다. PNG·GIF는 기존 서비스에서 기기별로 다운로드합니다. 개별 스티커 삭제, 최적화 화질, 캐시, 키보드 최근 사용·설정은 동기화하지 않습니다. 최초 연결은 클라우드 목록과 기존 로컬 팩을 합치고, 클라우드 삭제 기록은 보존합니다. 앱 초기화는 해당 기기의 동기화를 끄고 로컬 데이터만 지웁니다.

**현재 개인 개발 팀은 iCloud와 Push Notifications 서명을 지원하지 않습니다.** 따라서 기본 빌드는 동기화를 비활성화하고, 설정 화면에 계정 구성 필요 상태를 표시합니다. 맥·iPhone의 로컬 설치·복사 기능은 사용할 수 있습니다.

실제 동기화 활성화에는 다음 구성이 필요합니다.

1. 유료 Apple Developer Program 팀에 앱과 키보드의 Bundle ID·App Group을 등록합니다. 앱 ID에서 iCloud/CloudKit 및 Push Notifications를 활성화합니다.
2. 앱에 `iCloud.com.sihyeon.TelegramSticker` 컨테이너와 기존 `group.com.sihyeon.TelegramSticker` App Group을 연결합니다. iOS 및 Mac Catalyst 개발용 프로비저닝에 이를 포함합니다. 키보드는 기존 App Group만 사용합니다.
3. 모든 기기를 같은 Apple 계정에 로그인하고 **Development** 환경 빌드로 업데이트합니다. 아래 빌드의 `YOUR_PAID_TEAM_ID`를 실제 팀 ID로 바꿉니다. 개발 환경에서는 앱이 private `StickerLibrary` zone과 `Pack`·`PackOrder` 레코드의 `payload` Bytes 필드를 생성합니다.
4. 각 기기의 설정 → iCloud에서 동기화를 켭니다. 기기 간 다운로드 실패는 팩 목록의 다시 시도 또는 지금 동기화로 재시도합니다.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project TelegramSticker.xcodeproj -scheme TelegramSticker \
  -configuration Debug -xcconfig Configuration/CloudKit.xcconfig \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  DEVELOPMENT_TEAM=YOUR_PAID_TEAM_ID -allowProvisioningUpdates build
```

iPhone/iPad는 같은 xcconfig와 팀으로 iOS 실기기 destination을 지정합니다. xcconfig는 앱 전용 서명 변수를 바꾸므로 키보드에 CloudKit entitlement를 추가하지 않습니다. 실제 iCloud 연결·기기 간 동작은 지원하는 팀의 서명과 설치 전에는 확인할 수 없습니다. 공개 배포와 Production 스키마 승격은 별도 작업입니다.
