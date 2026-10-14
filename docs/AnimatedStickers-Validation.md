# TGS / WebM 애니메이션 지원

**2026-10-14 현재 구현과 검증은 [최신 변경 문서](Storage-GIF-Updates-Performance.md)를 참조하세요. 아래는 10월 13일 구현 당시의 범위·검증 기록이며 용량 제한, 정적 키보드 썸네일, 샘플 메뉴 등은 이후 변경되었습니다.**

2026-10-13. 사용자가 후속 구현 우선순위로 TGS/WebM을 선택해 진행한 범위입니다.

## 구현

- 메인 앱에서 TGS → Lottie 렌더링 → GIF, WebM → VP9 색상·알파 디코딩 → GIF 변환.
- 원본 형식을 기록하고 GIF, 정적 PNG, 256px PNG 썸네일을 완료된 팩 revision으로 함께 게시합니다.
- 기존 schemaVersion 1의 PNG 필드를 유지하고 선택적 `animationPath`를 추가했습니다. 이전 정적 팩은 그대로 읽습니다.
- 현재는 한 장 이상 성공하면 유효한 PNG/GIF 항목만 팩으로 게시하고, 실패한 ID는 별도로 기록합니다. 앱 재시작 후에도 실패 항목만 재시도합니다. 모든 항목 실패·취소·게시 오류는 기존 설치 팩을 유지합니다. [부분 설치 변경](PartialInstall-KeyboardUX.md).
- 애니메이션이 포함된 팩은 다운로드·변환을 한 항목씩 처리합니다. 정적 팩의 다운로드 동시성 3은 유지합니다.
- 키보드 그리드는 PNG 썸네일과 GIF 배지만 표시합니다. 탭은 GIF 복사, 길게 누르면 GIF/정적 PNG 선택. 확장에서 변환·네트워크·원본 영상 재생을 하지 않습니다.
- 메인 앱에서 한 항목씩 160px 프레임으로 움직임 미리보기, GIF/PNG 복사와 공유. 동작 줄이기 설정에서는 정적 프레임을 표시합니다.
- `+ → 움직이는 샘플 추가`는 자체 제작 TGS/WebM 두 항목을 실제 변환·저장합니다. 서버와 인증값 없이 검증할 수 있습니다.
- 기존 팩을 자동 변경하지 않습니다. 과거 정적 항목만 설치한 혼합 팩에 애니메이션을 추가하려면 현재는 팩을 삭제한 뒤 다시 가져와야 합니다.

## 지원 한도와 제한

- TGS: gzip 64KiB, 압축 해제 2MiB, 벡터 전용, 최대 512×512·60fps 입력·약 10초. 외부 이미지·텍스트 리소스는 거부합니다.
- WebM: 입력 2MiB 이하, 단일 VP9 8-bit I420 영상 트랙, 최대 512×512·약 10초·표시 프레임 300개. 오디오·암호화·lacing·중첩 요소의 unknown size는 지원하지 않습니다. WebM Segment의 unknown size는 허용합니다.
- Telegram 규격 문서는 3초를 안내하지만, 공식 블로그가 소개한 과거 Utya3D 팩에는 실제 약 3.3~3.9초 영상이 포함되어 있었습니다. 이를 잘라내지 않고 원본 시각으로 재생 시간을 보존하며 최대 90프레임을 균등 선택합니다.
- GIF의 1/100초 단위 때문에 30fps를 매번 0.03초로 저장하면 빨라집니다. 누적 시각을 정수 tick으로 반올림해 0.03/0.04초를 배분하고 전체 길이를 보존합니다.
- WebM은 먼저 RGBA 할당 없이 표시 프레임 수를 확인한 뒤, 정확한 출력 개수로 GIF encoder를 생성합니다. 프레임 전체를 배열에 보관하지 않습니다.
- VP9 디코더 자체도 512×512를 초과하는 비트스트림을 프레임 컨텍스트 할당 전에 거부하도록 빌드했습니다.
- 출력 GIF: 최대 90프레임·8MiB, 팩은 PNG·썸네일·GIF 합계 128MiB. 변환은 취소와 프레임 사이 15초 경과를 확인합니다. 단일 프레임 실행을 강제 중단하는 CPU 제한은 아닙니다.
- GIF는 색상 수와 1-bit 투명도 제한이 있어 TGS/WebM 원본의 반투명 가장자리·색상을 완전히 보존하지 못합니다. 정적 PNG 대안을 함께 저장합니다.
- 붙여넣는 앱이 GIF를 정지 이미지로 바꾸거나 거부할 수 있습니다. GIF 기록 성공과 대상 앱의 움직임·투명도·전송 성공을 구분합니다.
- Full Access가 없으면 목록·전환은 유지하며 GIF/PNG 복사 전에 차단합니다. 기존 클립보드를 읽지 않습니다.

## 의존성

- 앱에만 Lottie iOS 4.6.1 소스 패키지(Apache-2.0), libvpx 1.17.0 소스 기반 로컬 패키지(BSD 및 PATENTS)를 연결합니다. 키보드에는 두 디코더를 연결하지 않습니다.
- libvpx는 VP9 decoder-only scalar C 빌드입니다. SIMD보다 느릴 수 있으나 플랫폼별 미검증 바이너리 의존성을 피하고 실제 iPhone/Simulator에서 같은 소스를 빌드합니다.
- [로컬 패키지 출처·재생성 설정](../Packages/StickerVP9/README.md), 앱 `설정·샘플 → 오픈 소스 라이선스`에 배포 고지를 포함합니다.
- `Scripts/GenerateAnimatedFixtures.py`의 PyAV/Pillow는 개발용 fixture 생성에만 사용합니다. 앱에 포함하지 않습니다. 자체 원 도형 fixture는 CC0-1.0입니다.

## 검증 결과

- iOS 27 Simulator 기본 AVFoundation WebM capability probe는 playable=false였습니다. 실제 기능은 libvpx를 사용하며 이 probe를 지원 근거로 사용하지 않습니다.
- TGS와 WebM 각각 30프레임 GIF 및 유효 PNG 생성. 첫/마지막 프레임의 도형 이동과 투명한 모서리를 픽셀로 검사했습니다.
- 잘못된 gzip·뒤에 붙은 데이터·잘린 WebM·크기 초과 컨테이너를 거부하는 테스트.
- 초기 구현 당시 TGS/WebM 혼합 팩의 실패 시 미게시, 재시도 시 완료 TGS 재사용, 게시 GIF/PNG 재검증, 권한 없음일 때 I/O·쓰기 없음, GIF 쓰기 및 PNG 대안 분기 테스트.
- **iPhone 15 Pro / iOS 27.2: 변환·가져오기 관련 13개 단위 테스트 통과**. `/tmp/StickerBridge-Animation-DeviceTests.xcresult`.
- Worker 13개 테스트·TypeScript 검사·배포 dry-run 통과. 원본 형식별 signature 확인, TGS 64KiB 제한, 기존 인증·캐시·리다이렉트 차단 유지.
- Worker 배포 버전 `1d7a093d-ec47-4d59-b366-de140480eafb`. Secret 값은 변경하거나 읽지 않았습니다.
- iPhone·iPad iOS 27 Simulator 각각 **41개 단위/UI 테스트 통과(총 82회 실행)**. `/tmp/StickerBridge-Animation-Final.xcresult`.
- 움직이는 샘플 설치·미리보기·복사·재실행 유지 UI 테스트가 두 Simulator에서 통과했고, 첨부 스크린샷을 직접 확인했습니다.
- 서명된 iOS Debug·Release 빌드 성공. Release 키보드 바이너리에 Lottie·VP9 디코더 심볼이 없음을 확인했습니다.
- 새 앱을 연결된 iPhone에 설치했습니다. 기존 Bundle ID·Team·최소 OS·사용자 팩을 유지했습니다.
- 최종 미리보기 레이아웃 UI 테스트를 두 Simulator에서 다시 통과했습니다. `/tmp/StickerBridge-Animation-PreviewFinal.xcresult`.
- 컨테이너를 512px로 위장한 실제 768px VP9 bitstream 거부를 포함한 5개 변환 테스트도 iPhone에서 통과했습니다. `/tmp/StickerBridge-Animation-NativeLimit2.xcresult`.
- 첫 단일 Swift Testing 필터는 테스트를 0개 선택했습니다. 이를 통과 증거로 사용하지 않고 suite 전체를 실행해 위 결과를 확인했습니다.
- 실제 Telegram TGS `UtyaDuck` 40개 전체를 iPhone에서 변환·임시 팩 게시했습니다(GIF 합계 53,555,490바이트, 시간 보정 전 실행). 실제 WebM 검사에서 발견한 3초 초과 항목을 계기로 위 입력/출력 길이 처리를 수정했습니다.

### 최종 확인

- `/tmp/StickerBridge-Animation-Regression.xcresult`: iPhone·iPad Simulator 각각 **43개 통과·실서버 opt-in 검사 1개 생략**, 실패 없음. 총 86회 통과·2회 생략. 기존 정적 가져오기·저장·복사·온보딩·접근성·화면 회전 검사 포함.
- `/tmp/StickerBridge-Animation-LiveFinal.xcresult`: **iPhone 15 Pro / iOS 27.2에서 16개 통과**, 생략·실패 없음. 실제 서버를 통한 `UtyaDuck` 40개 및 `Utya3D` 17개 전체 설치, 변환 6개 검사, 가져오기 9개 검사 포함. 사용자 App Group의 팩은 변경하지 않고 임시 저장소를 정리합니다.
- `/tmp/StickerBridge-GIF-Artifacts.xcresult`: 마지막 논리 캔버스 크기 차단 검사를 포함한 변환 6개 통과. 자체 제작 TGS/WebM GIF를 첨부했습니다.
- 첨부 GIF를 **Pillow의 합성 프레임 디코더**로도 검사했습니다. 각각 30프레임·총 1,000ms, disposal=2, 첫/마지막 프레임의 투명 모서리 유지와 도형 중심 160→352px 이동, 불투명 픽셀 수 일정. 이전 도형이 잔상으로 누적되지 않았습니다.
- `/tmp/StickerBridge-animation-release-complete.log`: 최종 서명 Release 빌드 성공. iPhone 설치·실행 완료.
- 실제 팩 실패 진단용 원본은 Git에 추가하지 않았습니다. `LiveAnimationImportTests`는 opt-in 실행 시 해당 전용 진단 폴더를 정리합니다. 최종 설치 후 해당 경로 조회에서는 폴더가 발견되지 않았습니다.
- **사용자 실기기 확인: StickerBridge 키보드에서 GIF를 복사해 카카오톡에 붙여넣었을 때 움직임 유지 성공.** 복사한 샘플의 원본 형식과 카카오톡 버전·투명도 결과는 별도 제공되지 않았으므로 추정하지 않습니다.

실서버 검사는 실제 기기의 기존 Keychain 연결 설정을 사용합니다. 인증값을 출력하지 않습니다. 사용자별 설정과 네트워크가 필요한 검사이므로 기본 실행에서는 생략합니다.

```sh
TEST_RUNNER_STICKERBRIDGE_LIVE_IMPORT=1 \
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project TelegramSticker.xcodeproj -scheme TelegramSticker \
  -destination 'platform=iOS,id=<연결한_실기기_UDID>' \
  -only-testing:TelegramStickerTests/LiveAnimationImportTests test
```

선택적으로 `TEST_RUNNER_STICKERBRIDGE_LIVE_FORMAT=video` 또는 `animated`로 한 형식만 검사할 수 있습니다. 테스트 결과에서 실제 실행 개수와 생략 여부를 확인해야 합니다.
- 최초 전체 실행에서는 변경 전 UI 문구를 기대하던 가져오기 UI 테스트 1개가 실패했습니다. 새 문구로 기대값을 갱신한 뒤 위 82회 실행이 모두 통과했습니다.

## 아직 확인하지 않은 실제 사용 결과

- 위 두 팩 외 다른 Telegram 공개 팩의 호환성 및 복잡한 TGS의 실행 시간.
- 메모·Apple 메시지의 GIF 붙여넣기와 움직임, 각 앱의 투명도·수동 전송. 카카오톡의 움직임 유지는 위 사용자 확인으로 기록합니다.
- iPad 실기기 및 키보드 실제 프로세스의 GIF 복사 순간 메모리. 기존 정적 PNG 성공을 GIF 성공으로 간주하지 않습니다.

검증할 때는 `+ → 움직이는 샘플 추가` 후 메인 앱의 `움직임 보기`를 확인하고, 같은 항목을 키보드에서 탭해 대상 앱에 붙여넣습니다. 정지 이미지가 되면 길게 눌러 PNG 복사 또는 메인 앱 GIF 공유와 비교합니다. 기기·OS·대상 앱 버전별로 결과를 남깁니다.
