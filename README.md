# StickerBridge

[현재 파일 구조·작업별 진입점](File-structure.md) · [작업 지침](AGENTS.md)

기존 `TelegramSticker` iOS/iPadOS 앱과 `StickerKeyboard` 확장을 사용하는 스티커 키보드 기술 검증 프로젝트입니다. 최소 OS는 27.0입니다.

2026-10-14: 팩·GIF 저장 용량 제한을 제거하고 캐시 삭제, 실패 원인·항목별 재시도, Telegram 팩 업데이트, 앱의 큰 미리보기, 키보드 GIF 재생을 추가했습니다. 키보드는 iPhone 세로 기준 7열·4행을 표시하고, 좌우 드래그를 손가락에 맞춰 이동하며 전체 목록은 팩마다 새 줄에서 시작합니다. [최신 구현·검증 결과](docs/Storage-GIF-Updates-Performance.md).

2026-10-14: 키보드 재진입 상태 복원·초기 크기·셀 이미지·취소된 비동기 작업을 정리했습니다. [표시 안정화 변경·검증](docs/Keyboard-Presentation-Stability.md).

기존 **일부 실패 시 성공 항목 설치·실패 항목 재시도**와 **키보드 UI 개선**을 구현했습니다. 키보드는 대표 이미지로 팩을 고르며 하단 고정 안내 줄 없이 작은 스티커 그리드를 표시합니다. 불투명 배경을 없애 시스템 키보드 재질을 사용하며 마지막 선택 탭을 복원합니다. 팩 탭을 길게 잡고 드래그해 키보드 순서를 변경하고, 관리 메뉴에서 최근 사용을 비울 수 있습니다. 선택 시 개수 팝업은 표시하지 않습니다. 스티커 영역을 좌우로 밀면 탭 순서대로 팩을 바꿀 수 있으며, 대각선은 세로 스크롤로 처리합니다. 앱의 + 버튼은 Telegram 링크 입력으로 바로 연결되며 샘플 추가·복사 연습·개인정보 섹션은 제거했습니다.

**TGS/WebM 애니메이션 지원**도 구현했습니다. 메인 앱이 GIF와 정적 PNG를 함께 만들고, 키보드는 오프라인으로 GIF를 복사합니다. 사용자가 기존 정적 팩의 실제 미리보기·설치·오프라인 붙여넣기 및 최근 사용 유지를 확인했습니다.

실제 Telegram TGS 40개·WebM 17개 전체 가져오기 검사를 통과했고, 사용자가 iPhone에서 **키보드 GIF 복사 → 카카오톡 붙여넣기 후 움직임 유지**를 확인했습니다. GIF의 색상·반투명 표현과 다른 앱의 동작에는 제한이 있어 PNG 대안을 함께 제공합니다.

사용자가 M1 정상 작동과 M2 팩 목록·정렬·삭제 반영, Full Access 미허용 시 공유 읽기를 확인했습니다. iPad 실기기와 대상 앱별 공유·투명도 결과는 별도 검증 대상입니다.

- [용량·GIF·업데이트·성능 및 7×4 키보드](docs/Storage-GIF-Updates-Performance.md)
- [M2 저장 구조, 검증 절차](docs/Milestone2-Validation.md)
- [M3 구현·검증 범위](docs/Milestone3-Validation.md)
- [M4 사용성과 남은 검증](docs/Milestone4-Validation.md)
- [M5 후속 범위와 출시 계획](docs/Milestone5-Roadmap.md)
- [부분 설치·키보드 UI 및 검증](docs/PartialInstall-KeyboardUX.md)
- [TGS/WebM 구현 범위·한도·검증](docs/AnimatedStickers-Validation.md)
- [Worker 로컬 검증 및 이후 설정](backend/worker/README.md)
- [M1 설치, 검증 명령, 실기기 결과표](docs/Milestone1-Validation.md)
- `Shared`: 앱·키보드 공통 제품 모델·이미지 처리·저장소 읽기·복사 코드.
- `StickerSamples`: 두 타깃에 번들되는 자체 제작 샘플 정의·PNG. App Group 저장소가 아닙니다.
- `TelegramSticker/Networking`: 클라이언트 HTTP·세션. 서버 서비스는 `backend/worker/src/services`에서 관리합니다.
- `Scripts/GenerateSampleStickers.swift`: macOS CoreGraphics로 테스트 PNG 3장을 재생성합니다. 외부 의존성이 없습니다.

샘플 PNG는 이 프로젝트에서 직접 제작한 기하학적 테스트 이미지이며 CC0-1.0으로 제공합니다. Telegram의 스티커를 재배포하지 않습니다.
