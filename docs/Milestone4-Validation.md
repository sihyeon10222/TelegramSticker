# Milestone 4 — 사용성과 안정화

2026-10-13 M3의 실제 설치·오프라인 복사·붙여넣기 성공을 사용자에게 확인한 뒤 시작했습니다. M4 전체 완료 판정은 아직 하지 않습니다.

## 첫 구현 범위

- 첫 실행에 스티커 키보드 목적, 설정 경로, 지구본 선택, Full Access, 직접 붙여넣기와 대상 앱 제한을 안내합니다. ‘나중에’ 또는 ‘시작하기’를 누르면 다시 자동 표시하지 않으며 설정·샘플에서 도움말을 볼 수 있습니다.
- 키보드에 최근 사용 탭을 추가합니다. 성공적으로 PNG를 기록한 항목 ID만 최근 순서로 최대 24개 저장합니다. 실패한 복사와 사용자가 타이핑한 내용은 기록하지 않습니다.
- 최근 사용 저장소는 확장의 `UserDefaults.standard`입니다. App Group이나 서버에 쓰지 않습니다. 정상 공유 목록에 없는 ID는 정리하되, 공유 저장소·manifest 오류가 있는 상태에서는 삭제로 오인해 기록을 지우지 않습니다.
- 앱·키보드 각각 PrivacyInfo.xcprivacy를 포함합니다. 자체 환경의 UserDefaults에 CA92.1, 앱·App Group 컨테이너 파일 메타데이터 사용에 C617.1을 선언합니다. 실제 개발 서명 산출물의 두 manifest 포함을 확인했습니다.
- 기존 타깃·Bundle ID·Team·최소 iOS/iPadOS 27.0 유지. 새 라이브러리나 문자 키 배열을 추가하지 않습니다.

## 검증

- RecentStickerTests: 24개 상한, 중복 제거·최신 순서, 재시작 복원, 삭제 ID 정리, 잘못된 설정 값 처리.
- UI: 첫 실행 안내 표시·닫기·재실행 후 반복하지 않음. 기존 설치·삭제·공유·복사·가져오기 검사 유지.
- plist 구문 검사 및 개발 서명 iOS 빌드 성공 (`/tmp/StickerBridge-M4-device.log`).
- 최초 Simulator 전체 검사: iPhone 32개 통과, iPad 31개 통과·미리보기 UI 1개 실패 (`/tmp/StickerBridge-M4-First.xcresult`). 온보딩·최근 사용 단위 검사는 두 기기에서 통과했습니다.
- 미리보기에서 입력 완료 시 키보드를 닫고 조회하도록 submit 동작과 버튼 동작을 보완했습니다. 해당 설치·삭제 흐름을 iPhone/iPad에서 다시 실행해 각각 통과했습니다 (`/tmp/StickerBridge-M4-Import.xcresult`). 전체 64회가 한 번에 통과했다고 주장하지 않습니다.
- iPhone/iPad 온보딩 첨부 이미지에서 내용·여백·스크롤 배치를 확인했습니다. `PrivacyInfo.xcprivacy`는 실제 앱과 확장 산출물 모두에서 확인했습니다.
- iPhone 사용자 확인: **최근 사용 표시·재진입 유지 성공**. 대상 앱 이름·투명도는 답변에 없어 미기록입니다.
- 주요 앱 화면(팩 목록·설정/샘플)의 XCUI 접근성 자동 검사: `sufficientElementDescription`, `trait`, `hitRegion`을 iPhone/iPad Simulator에서 각각 통과했습니다 (`/tmp/StickerBridge-M4-Accessibility.xcresult`). 검사 범위는 표시된 앱 화면이며 확장 전체 또는 실제 VoiceOver 탐색·읽기 품질의 증거로 확대하지 않습니다.
- 다크 모드·최대 접근성 글자 크기: iPhone Simulator에서 온보딩 표시/닫기/재시작과 가로 화면 샘플 복사 통과 (`/tmp/StickerBridge-M4-LargeDark-2.xcresult`). 큰 글씨에서 좁은 셀의 이름 줄바꿈을 줄이도록 앱의 세 그리드를 ScaledMetric으로 조정했고, 키보드 접근성 크기에서는 셀 크기를 늘렸습니다. 가로 전환의 실제 앱 frame을 기다리도록 보완한 후 가로 복사를 다시 통과했습니다 (`/tmp/StickerBridge-M4-LargeDark-3.xcresult`). 가로 첨부 PNG의 orientation 메타데이터 때문에 도구 미리보기 방향이 달라 전체 배치의 시각 판정은 실기기에서도 확인해야 합니다. 테스트 후 Simulator를 Light/기본 Large 글자 크기로 돌렸습니다.

## 1,000개 파일 실기기 측정과 개선

사용자는 당분간 iPhone·Simulator로 진행하도록 선택했습니다. iPad 실기기 항목은 미검증으로 유지합니다.

`LibraryPerformanceTests`는 앱의 별도 임시 저장소에 자체 샘플을 production writer로 10팩×100개 설치하고, 2,000개의 원본·썸네일 파일 경로를 검사합니다. 실제 App Group·설치 팩·클립보드를 변경하지 않습니다. 각 반복에서 목록 로딩, 200개 썸네일, 10개 복사 데이터 준비를 실행합니다. 네트워크는 사용하지 않습니다.

최초 목록 읽기 약 2.452초를 확인해 동일 폴더의 반복 안전성 검사와 URL 객체 생성을 줄였습니다. 안전한 상위 폴더는 한 번의 동기 snapshot 안에서만 재사용합니다. root 확인, 경로 순회·NUL·심볼릭 링크 차단, 각 파일 leaf 검사, revision 간 재검사는 유지합니다. warm snapshot 이후 leaf를 symlink로 바꿔도 해당 팩만 차단되는 회귀 검사도 통과했습니다.

최종 iPhone 15 Pro / iOS 27.2 실측 (`/tmp/StickerBridge-M4-DeviceUnits.xcresult`):

| 측정 | 결과 |
|---|---|
| 최초 1,000개 snapshot | 0.711초 |
| 반복 snapshot 5회 | 0.692~0.708초 |
| snapshot + 첫 24개 썸네일/일부 복사 준비 | 0.757~0.774초 |
| 반복 전체(200개 썸네일·10개 복사·추가 snapshot) | 1.934~1.958초 |
| 테스트 프로세스 physical footprint, 로드 시 | 66.27~66.75MiB |
| 각 반복 종료 시 footprint | 65.66~65.80MiB |
| 실기기 전체 단위 검사 | 29개 통과, 실패·건너뜀 없음 |

위 메모리는 SwiftUI 메인 앱·테스트 런타임을 포함한 **테스트 프로세스** 수치이며 키보드 확장 한도나 확장 메모리가 아닙니다. 5회 반복에서 종료 footprint가 지속 증가하지는 않았으나 장시간 UI 누수·실제 스크롤 프레임·확장 메모리 압박까지 증명하지 않습니다. 첫 24개 준비 시간은 OS의 키보드 표시 및 화면 렌더링 시간을 포함하지 않습니다. JSON 측정 첨부물을 xcresult에 보존했습니다.

최초 XCTest metric API 방식은 `measureWithMetrics` 호출 중 테스트 프로세스 종료로 실패했습니다 (`/tmp/StickerBridge-M4-Performance.xcresult`). 이후 반복 사이에 main actor를 양보하고 ContinuousClock과 자기 프로세스 footprint를 직접 기록하는 방식으로 변경해 측정을 완료했습니다. 최초 실패를 성공 검사에 포함하지 않습니다.

실제 키보드 Instruments 연결 시도: 사용자가 키보드를 열어 둔 상태에서 devicectl로 확장 PID 4103의 실행을 확인했습니다. xctrace의 Allocations는 PID와 프로세스 이름 모두 `Cannot find process`로 종료되어 trace를 기록하지 못했습니다. 사용자가 정상 작동을 확인하고 다음 작업 진행을 요청해 이 도구 문제 추적은 중단했습니다. 확장 자체의 Instruments 메모리 검증은 미검증으로 남기며 테스트 프로세스 수치로 대체하지 않습니다.

## 남은 수용 기준

| 항목 | 필요한 증거 |
|---|---|
| 최근 탭 실기기 | 성공 복사 후 최근에 표시, 재진입 순서 유지, 팩 삭제 후 정리 |
| 권한 OFF | 목록·전환 유지, 복사 안내, 권한 재허용 후 갱신 |
| iPad | 실제 회전·크기 변경·floating 키보드·전환 |
| 접근성 | 큰 글씨와 VoiceOver 선택·상태 읽기·초점, 다크 모드 대비 |
| 성능 | 약 1,000개·10개 팩 반복 진입/스크롤/복사의 Instruments 메모리·지연 측정 |
| 대상 앱 | 앱 이름·버전별 붙여넣기·투명도·수동 전송 결과 |
| 출시 | 4.4.1 대응 결정, 공개 백엔드 인증·통제, 저작권·약관·배포 정보 |

## App Store 4.4.1 결정 보류

[Apple 4.4.1](https://developer.apple.com/app-store/review/guidelines/#extensions)은 문자 등 키보드 입력, 다음 키보드 수단, Full Access 없이 작동하는 기능을 요구합니다. 현재 열람·전환은 권한 없이 가능하지만 이미지 복사는 권한에 의존하고 문자 입력은 없어 심사 위험이 남습니다.

출시용 선택안은 보조 영역에 소수 유니코드 문자 또는 텍스트 이모티콘을 두고 `insertText`로 입력하게 하는 것입니다. 한/영 배열은 재구현하지 않으며, 스티커 공간이 줄고 제품에 문자 입력 기능이 추가되는 UX 영향이 있습니다. 소수 버튼으로 심사 통과를 보장하지 않습니다. 개인 테스트 버전은 스티커 전용을 유지하며, 해당 입력 기능은 사용자 승인 전까지 구현하지 않습니다.

개인정보 이유 코드 근거: [Apple required-reason API 목록](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype). 2026-10-13 공식 문서 데이터에서 CA92.1의 자체 앱 접근, C617.1의 앱·App Group 파일 메타데이터 사용 범위를 확인했습니다. 출시 시 실제 API·서버 운영·정책과 함께 다시 점검해야 합니다.

롤백은 온보딩·최근 탭·해당 기본 설정 값만 대상으로 합니다. 이미 설치한 App Group 스티커 파일·인덱스는 제거하지 않습니다.
