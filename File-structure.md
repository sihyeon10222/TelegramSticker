# 파일 구조와 작업 가이드

기준일: 2026-10-15. 아래는 적용된 실제 구조다.
파일 추가·이동·삭제 또는 책임·타깃 변경 시 이 문서도 갱신한다.

## 구조

기능별 코드는 한곳에 모으고, 실제로 재사용하는 코드만 공통 영역에 둔다.
빈 계층·프로토콜·별도 패키지는 구조를 위해 추가하지 않는다.

```text
TelegramSticker/                         # 저장소 루트
├── AGENTS.md
├── File-structure.md
├── README.md
├── TelegramSticker.xcodeproj/
├── Configuration/                       # 앱 plist·두 타깃 entitlements
├── TelegramSticker/                     # iOS 앱
│   ├── App/                             # 앱 시작·탭·기능 연결
│   ├── Features/
│   │   ├── Library/                     # 팩 목록·상세
│   │   ├── Import/                      # 입력·다운로드 조율·재개·실패·받은 링크
│   │   ├── Gallery/                     # 추천 목록·메타데이터·미리보기
│   │   ├── Optimization/                # 비교·적용·복원
│   │   ├── Onboarding/
│   │   └── Settings/
│   ├── Core/                            # 앱 전용 공통 코드
│   │   ├── Networking/                  # Worker HTTP·세션·API DTO·요청 예산
│   │   ├── Media/                       # TGS·WebM·PNG·GIF 변환
│   │   ├── Library/                     # 설치 쓰기·용량 최적화·캐시·팩 링크
│   │   ├── Background/                  # 백그라운드 작업·알림
│   │   ├── Diagnostics/                 # 작업별 진단 로그
│   │   ├── RequestGate.swift
│   │   └── StickerImportError.swift     # 통신·변환·가져오기 공통 오류
│   ├── UI/                              # 공통 뷰·미리보기·공유 시트
│   ├── DebugSupport/                    # DEBUG fixture
│   └── Resources/                       # Assets·AnimationSamples·privacy·고지
├── StickerKeyboard/                     # 키보드 확장
│   ├── KeyboardViewController.swift     # 수명 주기·UI 구성·작업 취소
│   ├── State/                           # 목록·선택·복사 상태·키보드 전용 저장소
│   ├── Interaction/                     # 목록 로딩·페이징·드래그·복사
│   ├── Views/                           # 그리드·셀·팩 탭·상태 표시
│   └── Resources/                       # Info.plist·privacy
├── Shared/                              # 앱·키보드가 함께 쓰는 제품 코드
│   ├── Models/                          # Sticker·라이브러리 저장 모델
│   ├── Storage/                         # LibraryReader
│   ├── Imaging/                         # 이미지 캐시·디코딩·GIF 재생·검증
│   ├── Clipboard/                       # StickerCopyService
│   └── Keyboard/                        # 전체 접근 관찰 기록
├── StickerSamples/                      # 자체 제작 샘플 정의·PNG
├── Packages/StickerVP9/                 # 앱 전용 네이티브 디코더·외부 libvpx
├── TelegramStickerTests/                # 기존 단위 테스트
├── TelegramStickerUITests/              # 기존 UI 테스트
├── Scripts/                             # 샘플·fixture 생성
├── backend/worker/                      # 서버 전용
│   ├── src/
│   │   ├── index.ts                     # Cloudflare Worker 진입점
│   │   ├── app.ts                       # 설정·인증·라우팅·공통 오류 처리
│   │   ├── features/
│   │   │   ├── packs/                   # routes·pack-loader·asset-stream·검증·타입
│   │   │   ├── gallery/                 # 카탈로그 API
│   │   │   └── sessions/                # 발급 API·세션·접근키 인증
│   │   ├── integrations/telegram/       # API·파일 다운로드·응답 크기 제한
│   │   └── platform/                    # 응답·캐시·해시·공통 검증·Worker 타입
│   ├── test/
│   ├── package.json
│   ├── pnpm-lock.yaml
│   ├── pnpm-workspace.yaml
│   ├── tsconfig.json
│   ├── wrangler.jsonc
│   └── README.md
└── docs/                                # 이전 구현·검증 기록
```

에셋 내부·외부 소스·개인 IDE 설정·생성 파일의 세부 목록은 생략한다.

## 배치 규칙

- 기능 하나에서 쓰는 코드는 해당 `Features/` 안에 둔다. 파일이 적으면 평평하게 유지한다.
- 두 기능 이상이 사용하는 앱 기반 코드는 `Core/`, 공통 뷰는 `UI/`에 둔다.
- `Core/`는 기능 화면 모델을 참조하지 않는다. 가져오기 화면 상태를 보관하는 `ImportActivity`는 `Features/Import/` 소유다.
- 갤러리 미리보기 취소와 백그라운드 작업 시작의 연결은 가져오기·최적화 기능이 담당한다.
- 키보드 `KeyboardState`는 목록·선택·최근 사용·팩 순서·마지막 복사 항목을 관리한다. 외부에는 읽기와 변경 메서드를 제공한다.
- 키보드 컨트롤러에는 UIKit 뷰·애니메이션·제스처·Task 수명만 둔다. 상태 변경은 `KeyboardState`에 맡긴다.
- `Shared/`는 앱과 키보드가 실제로 함께 쓰는 코드다. 키보드 전용 저장소·레이아웃은 키보드에 둔다.
- 서버는 기능별 API와 처리 로직을 함께 두고, Telegram 통신을 `integrations/telegram/`에 맡긴다.
- 클라이언트 `Core/Networking/`과 서버는 HTTP API로 연결한다. 소스·설정·Secret·빌드 경계를 유지한다.
- 구조 정리를 위해 타입 이름·공개 API·저장 형식을 일괄 변경하지 않는다.

## 작업별 시작 파일

| 작업 | 진입 파일 |
| --- | --- |
| 앱 진입·탭 | `TelegramSticker/App/TelegramStickerApp.swift`, `TelegramSticker/App/ContentView.swift` |
| 팩 목록·상세 | `TelegramSticker/Features/Library/LibraryModel.swift`, `TelegramSticker/Features/Library/InstalledPackView.swift` |
| 가져오기 화면·상태 | `TelegramSticker/Features/Import/ImportView.swift`, `TelegramSticker/Features/Import/ImportModel.swift`, `TelegramSticker/Features/Import/ImportActivity.swift` |
| 다운로드·설치·재개 | `TelegramSticker/Features/Import/ImportCoordinator.swift`, `TelegramSticker/Features/Import/ImportJobCache.swift` |
| 실패 기록 | `TelegramSticker/Features/Import/ImportFailureStore.swift` |
| 클라이언트 HTTP·세션 | `TelegramSticker/Core/Networking/WorkerClient.swift`, `TelegramSticker/Core/Networking/WorkerConfiguration.swift` |
| 요청 제어 | `TelegramSticker/Core/Networking/DownloadRequestBudget.swift`, `TelegramSticker/Core/RequestGate.swift` |
| 변환 | `TelegramSticker/Core/Media/TGSConverter.swift`, `TelegramSticker/Core/Media/WebMConverter.swift`, `TelegramSticker/Core/Media/StaticImageConverter.swift` |
| 설치 데이터·공유 읽기 | `TelegramSticker/Core/Library/LibraryWriter.swift`, `Shared/Storage/LibraryReader.swift` |
| 용량 최적화 | `TelegramSticker/Features/Optimization/OptimizationSession.swift`, `TelegramSticker/Core/Library/StickerStorageOptimizer.swift` |
| 캐시·초기화 | `TelegramSticker/Features/Settings/StorageSettingsView.swift`, `TelegramSticker/Core/Library/AppDisposableCache.swift` |
| 갤러리 | `TelegramSticker/Features/Gallery/GalleryView.swift`, `TelegramSticker/Features/Gallery/GalleryPreviewStore.swift` |
| 키보드 접근 안내 | `TelegramSticker/Features/Settings/KeyboardAccessMonitor.swift`, `Shared/Keyboard/KeyboardAccessReceipt.swift` |
| 백그라운드 진행·알림 | `TelegramSticker/Core/Background/BackgroundWork.swift`, `TelegramSticker/Core/Background/WorkNotifications.swift`, `TelegramSticker/UI/CurrentWorkBanner.swift` |
| 작업별 진단 로그 | `TelegramSticker/Core/Diagnostics/DownloadDiagnostics.swift`, `TelegramSticker/Features/Settings/DownloadLogsView.swift` |
| 링크 파싱·목록 파일 | `TelegramSticker/Core/Library/StickerLink.swift`, `TelegramSticker/Core/Library/PackLinkList.swift` |
| 링크 수신·공유 화면 | `TelegramSticker/Features/Import/PackLinkInbox.swift`, `TelegramSticker/Features/Import/ReceivedPackLinksView.swift`, `TelegramSticker/UI/PackLinkSharing.swift` |
| PNG 공유 | `TelegramSticker/UI/PNGShareSheet.swift` |
| 키보드 진입·상태 | `StickerKeyboard/KeyboardViewController.swift`, `StickerKeyboard/State/KeyboardState.swift` |
| 키보드 목록 로딩 | `StickerKeyboard/Interaction/KeyboardLibraryLoading.swift` |
| 키보드 페이징·드래그·복사 | `StickerKeyboard/Interaction/KeyboardPaging.swift`, `StickerKeyboard/Interaction/KeyboardPackReordering.swift`, `StickerKeyboard/Interaction/KeyboardCopying.swift` |
| 키보드 그리드·셀·팩 탭 | `StickerKeyboard/Views/StickerGridLayout.swift`, `StickerKeyboard/Views/StickerCell.swift`, `StickerKeyboard/Views/KeyboardLibrary.swift` |
| 키보드 선택·순서·최근 사용 | `StickerKeyboard/State/KeyboardSelectionStore.swift`, `StickerKeyboard/State/KeyboardPackOrderStore.swift`, `StickerKeyboard/State/RecentStickerStore.swift` |
| 제품 모델·이미지 | `Shared/Models/Sticker.swift`, `Shared/Imaging/StickerImages.swift`, `Shared/Imaging/GIFPlaybackView.swift` |
| 서버 진입·라우팅 | `backend/worker/src/index.ts`, `backend/worker/src/app.ts` |
| 서버 팩·파일 처리 | `backend/worker/src/features/packs/routes.ts`, `backend/worker/src/features/packs/pack-loader.ts`, `backend/worker/src/features/packs/asset-stream.ts` |
| 서버 갤러리·세션 | `backend/worker/src/features/gallery/routes.ts`, `backend/worker/src/features/sessions/routes.ts`, `backend/worker/src/features/sessions/session.ts` |
| Telegram API·파일 다운로드 | `backend/worker/src/integrations/telegram/client.ts`, `backend/worker/src/integrations/telegram/files.ts` |
| 서버 공통 기반 | `backend/worker/src/platform/response.ts`, `backend/worker/src/platform/worker-cache.ts`, `backend/worker/src/platform/types.ts` |
| 타깃·서명·패키지 | `TelegramSticker.xcodeproj/project.pbxproj`, `Configuration/App-Info.plist`, `Packages/StickerVP9/Package.swift`, `backend/worker/wrangler.jsonc` |

## 타깃과 리소스

- 앱: `TelegramSticker/` + `Shared/` + `StickerSamples/`. Lottie·StickerVP9를 사용한다.
- 키보드: `StickerKeyboard/` + `Shared/` + `StickerSamples/`. 네트워크·가져오기·변환·Lottie·StickerVP9를 연결하지 않는다.
- Xcode 파일 시스템 동기화 그룹을 유지한다. 하위 폴더의 Swift 파일도 해당 타깃에 포함된다.
- 기존 앱 단위 테스트 타깃에는 키보드 전용 저장소 3개와 그리드 레이아웃 소스를 명시적으로 연결한다. `KEYBOARD_TEST_SUPPORT` 조건으로 두 저장소만 앱 모듈의 공유 경로 검증에 접근한다. 확장 실행 파일을 테스트 번들에 링크하지 않는다.
- 키보드 plist: `StickerKeyboard/Resources/Info.plist`. 두 구성의 `INFOPLIST_FILE`·리소스 제외 경로를 유지한다.
- 앱·키보드 privacy manifest, 샘플 PNG, 애니메이션 샘플, 에셋, 고지의 번들 조회 이름을 유지한다.
- 제품 모델 `Sticker`·이미지 캐시 `StickerImages`는 `Shared/`, 샘플 배열 `Sticker.all`은 `StickerSamples/SampleStickers.swift`에 둔다.
- `Packages/StickerVP9/Sources/CStickerVP9/vendor/`는 외부 소스·생성 헤더다. 패키지 README의 갱신 절차를 따른다.
- Worker의 `.ts` import는 명시적 확장자를 사용하고 타입 의존성은 `import type`으로 선언한다. 기존 런타임 검사 구성은 전체 모듈 그래프를 읽는다.

## 실행 중 데이터

소스 위치와 기기의 저장소는 별개다. 이번 구조 변경은 아래 경로·키·저장 형식·API 응답을 유지한다.

```text
App Group: group.com.sihyeon.TelegramSticker
└── StickerLibrary/
    ├── index.json
    ├── packs/<pack-id>/<revision>/
    │   ├── manifest.json
    │   ├── <sticker-id>-original.png
    │   ├── <sticker-id>-thumb.png
    │   ├── <sticker-id>-animation.gif
    │   └── <sticker-id>-playback.gif
    └── staging/<revision>/

앱 전용
├── Application Support/ImportJobs/
├── Application Support/ImportFailures/
├── Application Support/Gallery/catalog-v1.json
├── Application Support/download-log.json
├── Caches/GalleryPreviews/v1/
└── tmp/StickerOptimization-<UUID>/

키보드 전용
├── Application Support/Keyboard/selection-v1.json
└── UserDefaults                         # 최근 사용·팩 순서·선택 fallback
```

설치 변경은 앱의 `LibraryWriter`가 완성된 revision을 준비한 뒤 인덱스를 원자적으로 게시한다.
실패 시 기존 revision을 보존하며 키보드는 공유 팩을 읽기만 한다.
키보드 접근 관찰 기록은 App Group에 별도 저장하고 현재 권한의 실시간 조회로 해석하지 않는다.
서버 내부 파일 ID·Bot Token은 클라이언트에 노출하지 않는다.

진단 로그는 Task-local 작업 ID로 묶는다. 최근 완료 작업 40개·작업당 최근 3,000줄을 보관하고
연속 기록 저장은 500ms로 합친다. 기존 로그 경로와 이전 배열 형식 읽기를 유지한다.

## 변경 확인

이동한 선언의 호출부·접근 수준, 타깃 포함 관계, 리소스 조회, 저장 경로와 API 경계를 확인한다.
앱 빌드·연결된 iPhone 덮어쓰기 설치·실행과 테스트 정책은 [AGENTS.md](AGENTS.md)를 따른다.
테스트는 명시적으로 요청받았을 때만 실행한다. 기존 `docs/` 검증 기록은 당시 결과다.

2026-10-15 적용 확인: 연결된 iPhone 앱 빌드·기존 설치 덮어쓰기·실행 완료.
Simulator 앱 및 기존 테스트 타깃 컴파일 완료, 기존 팩 목록 화면 확인.
Worker 타입 검사·배포 없는 번들 검사 완료. 테스트 실행·Worker 배포는 하지 않았다.

팩 목록과 상세의 선택 툴바는 `TelegramSticker/Features/Library/SelectionControls.swift`를 함께 사용한다. 표시 중인 버튼만큼 툴바 너비를 사용하고 GlassEffectContainer와 glassEffectID의 시스템 분리 전환을 사용한다. 앱 타깃의 동기화 그룹에 포함되며 키보드 타깃에는 포함되지 않는다.

갤러리 카드 메타데이터는 `Features/Gallery/GalleryMetadataStore.swift`에서 `Caches/GalleryPreviews/v1/metadata-<hash>.json`에 저장한다. 재진입 시 저장된 제목·스티커 정보를 먼저 표시한 뒤 10분 freshness 기준으로 서버를 갱신한다. 네트워크 실패 시 저장된 미리보기를 유지한다. PNG/GIF와 같은 100MiB LRU 캐시 예산 및 캐시 삭제 범위를 사용하고, 정리 세대가 변경된 이전 요청은 파일을 다시 생성하지 않는다. 앱 타깃 전용이며 타깃 변경은 없다.

팩 목록은 `LibraryView`의 편집 모드에서 행 전체를 길게 눌러 드래그하며, 드롭 시 `LibraryModel.move`를 호출해 순서를 게시한다. 재정렬 핸들은 표시하지 않으며 편집 중에는 길게 누르기 옵션 메뉴를 비활성화한다.

갤러리의 `GalleryPreviewState`는 카드가 LazyVGrid에서 제거되어도 제목·파일 경로·96px 디코딩 포스터를 유지한다(최대 600개 미리보기). 카드 재진입은 완성된 GIF를 정지 이미지로 덮어쓰지 않으며 화면 밖에서는 재생만 중지한다. 미완료 미리보기 작업은 카드 수명과 분리해 스크롤로 취소·재시작하지 않는다. 갤러리 이탈·백그라운드에서는 로딩을 취소하되 준비된 상태는 유지하고, 캐시 정리 시에만 파일·포스터 상태를 함께 비운다. `GalleryPreviewStore.swift`, `GalleryStickerPreview.swift`, `GalleryView.swift`의 앱 타깃 내부 변경이다.

팩 목록 선택은 SwiftUI List(selection:)과 EditMode 바인딩으로 시스템 다중 선택 제스처를 사용한다. 탐색 중인 팩 ID와 편집 중인 다중 선택 ID는 별도로 보관한다. 수동 체크박스와 탭 선택 처리는 두지 않는다. 드래그는 행 라벨에 붙이고 드롭 provider의 팩 ID를 읽어 순서를 저장한다. 두 방향 모두 insetGrouped 목록 스타일과 대칭인 행·섹션 inset을 사용해 선택 배경의 좌우 경계를 맞춘다.

목록 선택 바인딩은 생성 당시의 편집 모드를 캡처해 편집 종료 후 늦게 전달되는 선택 해제를 다중 선택 상태로 처리한다. 넓은 화면에서는 빈 목록 선택 이벤트가 현재 상세 팩을 해제하지 않으며 팩 삭제 시에만 사라진 ID를 정리한다. 좁은 화면에서는 뒤로가기의 빈 선택을 허용한다.

갤러리 재실행 복원은 `Features/Gallery/GalleryDiskCache.swift`의 로컬 전용 snapshot reader가 담당한다. 앱 init에서 첫 12개 카드의 저장된 메타데이터·96px 포스터·GIF 경로를 첫 SwiftUI 화면 생성 전에 복원하고, 나머지는 백그라운드에서 복원한다. 서버 요청·변환은 포함하지 않는다. 설치 라이브러리는 snapshot 묶음당 한 번 읽으며 기존 App Group 파일을 재사용한다. 복원 결과는 cache generation이 바뀌면 폐기하고 새로 로딩된 상태를 덮어쓰지 않는다. 새 파일은 기존 앱 동기화 그룹에 포함되며 키보드 타깃에는 포함되지 않는다.

`Features/Library/FixedPackChevron.swift`는 팩 행의 장식 화살표를 UIKit 셀의 오른쪽에 직접 고정한다. 편집 시 이동하는 contentView와 분리하며 셀 재사용/화면 해제 시 장식을 제거한다. 앱 동기화 타깃에만 포함된다.

팩 탐색은 `LibraryView`의 NavigationSplitView 사이드바(열기/닫기 가능)와 `InstalledPackView`의 적응형 목록/미리보기로 구성한다. iPad 및 폭 600pt 이상 iPhone 가로 화면에서 오른쪽 미리보기를 사용하고, 좁은 화면에서는 상단 미리보기를 사용한다. 회전 시 동일한 상세 뷰의 선택·미리보기 상태를 유지한다.

넓은 화면의 사이드바 편집·전체 선택·공유·추가는 시스템 상단 툴바에 배치한다. 사이드바 최대 폭은 화면 너비의 1/3, 최소 폭은 최대 폭 이내의 260pt로 제한한다. 좁은 사이드바에서는 공유·추가를 한 메뉴로 합치고 편집·전체 선택은 직접 표시한다. 가로 회전 시 사이드바를 연다. 홈 제목과 넓은 화면의 상세 팩 이름은 기본 navigationTitle을 사용하며 실제 표시된 툴바 버튼 너비에 따라 시스템이 정렬·말줄임한다.

하단 편집 작업은 높이·위치를 유지하는 overlay 안에서 opacity만 0.2초 동안 전환한다. 숨길 때 높이를 0으로 변경하거나 호스트를 제거하지 않는다. 편집 버튼과 작업 진행 바를 따로 측정하며 표시되는 높이만큼 목록 스크롤 여백을 확보한다. 글래스 버튼 내부에는 편집 모드의 레이아웃 애니메이션을 전달하지 않는다.

선택 글래스 버튼은 HStack과 GlassEffectContainer의 기본 레이아웃·분리 전환을 사용한다. 숨겨진 버튼 너비를 예약하거나 offset으로 위치를 보정하지 않는다. 홈과 상세의 호출부가 튀지 않는 동일한 편집 전환 transaction을 제공하며 컨트롤 내부에서 암시적 애니메이션을 중복 적용하지 않는다. 글래스 효과·ID·전환은 Button 자체에 함께 적용한다. 넓은 화면 사이드바 오른쪽에는 separator 색의 경계를 표시한다.

편집/전체 선택은 방향과 관계없이 동일한 56×44pt·88×44pt 캡슐을 사용한다. 사이드바 메뉴도 동일한 LibraryToolbarGlassLabel로 라벨 높이를 44pt로 정한 뒤 글래스를 적용한다. Menu의 자체 intrinsic 높이에 글래스 크기를 맡기지 않는다.

사이드바 토글은 빈 상세와 선택한 팩 상세를 감싸는 공통 navigation 툴바 항목으로 유지한다. 상세 열에서도 자동 sidebarToggle을 제거해 숨김 상태에서 시스템 토글이 추가되지 않도록 한다. 팩 revision 변경으로 상세 뷰를 재생성하지 않고 팩 ID가 바뀔 때 로컬 선택·미리보기만 초기화한다. 사이드바 숨김으로 목록이 사라져도 편집 상태를 초기화하지 않으며 탭 이동 시 초기화한다.


2026-10-15 버튼 동작 재구성: 위 선택 툴바의 가변 너비·glassEffectID 분리 전환 설명은 다음 구현으로 대체한다. `SelectionControls.swift`는 편집/완료와 전체 선택 버튼에 고정 슬롯을 두고, 숨긴 슬롯은 터치·접근성에서 제외한다. 편집 상태는 애니메이션 없는 단일 transaction으로 바꾼다. 목록 하단 작업 영역은 68pt 높이와 스크롤 여백을 유지해 편집/공유 전환 시 콘텐츠 위치를 바꾸지 않는다. 갤러리 설치·선택 해제 버튼도 배치를 유지한다. 상세 미리보기는 그리드 크기를 변경하지 않는 overlay이며 명시적인 닫기 버튼을 제공한다. 수정 파일은 기존 앱 동기화 그룹에 포함되며 타깃·리소스·저장 경로는 변경하지 않는다.

가로 버튼 후속 수정: 선택 버튼과 `LibraryToolbarGlassLabel`은 모두 interactive Liquid Glass를 사용한다. 가변 너비와 matched geometry morph는 사용하지 않는다. 가로 사이드바의 principal HStack/강제 폭을 제거하고 세로와 동일한 leading 선택 컨트롤, trailing 44pt 글래스 메뉴로 구성한다. 사이드바 최소 폭은 화면 1/3 제한 안에서 300pt다. 팩 선택에 따른 강제 사이드바 열기와 중복 회전 처리를 제거했다. 상세 뷰가 회전/열 변경으로 잠시 사라져도 선택 상태를 지우지 않고 팩·탭 변경 시에만 초기화한다. 미리보기 닫기도 interactive Liquid Glass다. 파일·타깃·리소스 경계 변경은 없다.

가로 실제 화면 검증에서 빈 상세→팩 상세 진입 시 사이드바 토글이 선택 버튼 뒤로 이동하는 것을 추가 확인했다. `LibrarySidebarToggle`을 공통 글래스 버튼으로 분리하고 상세 leading HStack의 첫 슬롯에 두어 빈 상세와 같은 위치를 유지한다. 팩 상세는 토글 동작을 주입받으며 열 상태는 LibraryView가 소유한다.

회전·간격 검증 후속: 팩 목록은 세로/가로 모두 좌우 scrollContent 여백 20pt, 행 내부 여백 16pt를 사용한다. 기존 `TelegramStickerUITests.swift`에 목록 기본/편집/전체 선택 및 상세 기본/미리보기/전체 선택에서 양쪽 가로 방향↔세로 회전을 반복하는 회귀 검증을 추가했다. 사용자의 명시적 테스트 요청에 따라 기존 iPhone 18 Pro Max에서 해당 테스트만 실행한다. fixture는 시뮬레이터에만 사용하며 실기기 설치에는 테스트 인자를 전달하지 않는다.

모션 후속 수정: 앞선 무애니메이션 transaction 설명을 대체한다. 고정된 버튼 슬롯과 스크롤 여백은 유지하되 `SelectionControls.update`는 0.25초 smooth로 편집/사이드바 상태를 전환한다. 전체 애니메이션 금지 transaction은 제거했다. 하단 작업·갤러리 설치 버튼은 0.2초 opacity, 미리보기는 0.25초 opacity 전환을 사용한다. Reduce Motion 활성 시 커스텀 전환은 생략한다.

가로 사이드바 표시 선호는 `wideColumnVisibility`에 별도로 보관하여, 닫은 상태에서 세로→가로로 돌아와도 강제로 열리지 않는다. `testRotationPreservesHiddenSidebar`는 상세 유지·양방향 회전·재열기를 검증한다.

2026-10-16 상단 정렬 수정: SelectionControls의 전체 선택 버튼은 편집 중에만 레이아웃에 포함해 기본 상태의 navigationTitle 중앙 정렬 공간을 확보한다. 목록 공유 버튼은 상세 ShareLink와 같은 iconOnly Label을 사용한다. 가로 레이아웃 진입 시 columnVisibility를 항상 .all로 설정하며, 이전 닫힘 상태를 회전 후 복원하지 않는다. 기존 숨김 상태 보존 설명을 대체한다. 파일·타깃·리소스·저장 경로 변경은 없다.

2026-10-16 최종 목록 배경 규칙: 앞선 scrollContent 수평 여백 설명을 대체한다. 설치된 팩 Section의 `listSectionMargins`를 사용하고, leading은 20pt + 가로 화면의 실제 leading safe-area inset, trailing은 20pt로 지정한다. 시스템이 행 내용에만 적용하던 노치 안전 영역을 섹션 배경에도 반영해 회색 배경이 왼쪽으로 과도하게 확장되지 않도록 한다. 행 내부는 양쪽 16pt다. 모션 복원과 가로 사이드바 상태 보존 규칙은 유지한다.

2026-10-16 상세 스티커 탭 확대 미리보기 제거: InstalledPackView에서 미리보기 상태·overlay·닫기 버튼·품질 표시 패널과 관련 초기화를 제거했다. 기본 스티커 탭은 동작하지 않고 선택 모드에서만 선택을 전환한다. 길게 누르기 복사·공유, 그리드 GIF 재생과 핀치 열 수 조절은 유지한다. 기존 상세 미리보기 설명을 대체하며 파일·타깃·리소스 경계는 변경하지 않는다.

사이드바 토글은 시스템이 회전 중 갱신하는 `columnVisibility`가 아니라 사용자의 가로 상태 `wideColumnVisibility`를 기준으로 반전한다. 시스템의 중간 열 상태 때문에 첫 재열기 탭이 닫힘으로 처리되는 경우를 방지한다.

2026-10-16 최신 변경 통합: 미리보기 제거와 가로 진입 시 사이드바 열기 동작을 유지한다. 회전 중 UIKit이 보정하는 `columnVisibility`와 버튼이 반전할 `wideColumnVisibility`를 분리하고, `preferredCompactColumn`을 명시해 세로 상세와 가로 사이드바 재열기를 동기화한다. 가로 진입 시 두 표시 상태 모두 .all로 맞춘다. 회귀 검증은 목록 기본/편집/전체 선택, 상세 기본/개별 선택/전체 선택, 사이드바 닫기 후 회전·재토글의 7가지 상태로 구성한다. 기존 숨김 선호 보존·미리보기 테스트 설명을 대체한다.

2026-10-16 최종 검증: 기존 iPhone 18 Pro Max에서 현재 UI 기준 회전 회귀 테스트 3개(7가지 진입 상태, 양방향 가로/세로 전환)가 모두 통과했다. 실기기 Debug 빌드와 연결된 iPhone 15 Pro 덮어쓰기 설치·실행을 완료했다. 상세 스티커의 선택 여부는 접근성 isSelected로 노출해 개별 선택 유지도 검증한다.

2026-10-16 툴바 전환 구조 수정: 앞선 커스텀 글래스·고정 44pt 높이·HStack 선택 컨트롤 설명을 대체한다. `SelectionControls.swift`는 View가 아닌 ToolbarContent로 편집/완료와 전체 선택을 각각 식별자가 있는 시스템 ToolbarItem으로 제공한다. 상세 사이드바 토글도 독립된 항목이며 빈 상세와 같은 ID를 사용한다. 목록 메뉴와 사이드바 토글의 커스텀 glassEffect, 고정 frame, plain 스타일, sharedBackgroundVisibility(.hidden)을 제거해 내비게이션 바가 가로/세로 크기·눌림 효과·글래스·삽입 전환을 관리한다. 선택 컨트롤 자체의 중복 암시적 애니메이션을 제거하고 콘텐츠 상태 전환은 기존 단일 withAnimation을 유지한다. 기존 앱 동기화 그룹 내부 수정이며 타깃·리소스·저장 경로 변경은 없다.

2026-10-16 사이드바 이동 동기화: 앞선 수동 사이드바 토글·wideColumnVisibility 설명을 대체한다. NavigationSplitView의 기본 sidebarToggle을 복원하고 LibrarySidebarToggle, 상세 콜백 주입, 수동 열 반전 함수를 제거했다. 버튼 탭에서 columnVisibility와 preferredCompactColumn을 동시에 변경하거나 선택 컨트롤의 0.25초 애니메이션을 적용하지 않는다. 시스템 분할 컨트롤러가 토글 버튼과 열 전환을 함께 관리한다. preferredCompactColumn은 기존 회전 처리에서만 설정하며 가로 진입 시 .all로 여는 동작은 유지한다. 기존 앱 소스 내부 수정으로 파일·타깃·리소스·저장 경로 변경은 없다.

2026-10-16 선택 UI 개선: 앱의 팩 목록·팩 상세·다운로드 로그에서 전체 선택/전체 해제 기능을 제거했다. 선택 모드 종료는 시스템 파란 원형 완료 체크 버튼을 사용한다. 상세 제목은 방향과 관계없이 inline navigationTitle로 중앙 정렬·말줄임한다. `Features/Library/StickerDragSelection.swift`는 상세 그리드의 셀 위치 수집과 UIKit 방향 판정·경로 선택·가장자리 자동 스크롤을 담당한다. 가로 시작은 선택/해제, 세로 시작은 스크롤이며 드래그 시작 셀의 상태로 동작을 고정한다. 새 파일은 앱 파일 시스템 동기화 그룹에만 포함되며 키보드·저장 경로 변경은 없다.

2026-10-16 선택·가로 레이아웃 후속: StickerDragSelection은 표시 순서 ID와 드래그 시작 선택 snapshot을 이용해 시작~현재 항목의 연속 범위를 선택/해제한다. 되짚으면 범위 밖은 시작 상태로 복원한다. SelectionToggleButton은 단일 Button·GlassEffectContainer·glassEffectID를 유지하며 56pt 캡슐↔44pt 파란 원형과 글자↔체크 표시를 전환한다. `Features/Library/LibraryNavigationLayout.swift`는 실제 툴바 액션 경계 표시와 상세 제목의 남은 영역 중앙 정렬·말줄임, UIKit 회전 완료 후 사이드바 확장을 담당한다. LibraryView의 섹션 leading에 안전 영역을 중복 추가하지 않고 좌우 20pt를 적용한다. 가로에서 수동 닫기는 허용하되 세로→가로 전환 후 다시 연다. 새 파일은 앱 동기화 그룹에만 포함되며 키보드·저장 경로 변경은 없다. 앞선 경로 통과 항목만 선택·기본 navigationTitle 정렬·노치 inset 추가 설명을 대체한다.

2026-10-16 제목 겹침 수정: LibraryNavigationLayout의 툴바 경계 marker·좌표 변환·1pt 제목 호스트와 영역 밖 UILabel 배치를 제거했다. 상세 principal은 시스템이 제안하는 제목 영역 안에서 확장하는 SwiftUI Text로 중앙 정렬·한 줄 끝 말줄임·clipping을 적용한다. LibraryNavigationLayout은 회전 완료 사이드바 확장만 담당한다. 선택 버튼의 비활성 글자는 primary(밝은 모드 검정/어두운 모드 시스템 전경), 활성 체크는 흰색을 사용한다. 앞선 툴바 경계 기반 제목 배치 설명을 대체하며 파일·타깃·리소스·저장 경로 변경은 없다.

2026-10-16 상세 헤더 통합: 앞선 별도 principal 제목 설명을 대체한다. InstalledPackView는 선택·제목·공유/옵션을 하나의 고정 외부 폭 trailing ToolbarItem에 배치한다. 내부 HStack에서 제목이 버튼 사이 남은 폭을 사용해 중앙 정렬·말줄임하고, 선택 전환에 따른 내부 폭 변화를 동일 smooth transaction으로 애니메이션한다. 현재 GeometryReader 상세 열 너비에서 시스템 leading 버튼과 양끝 여백용 84pt를 제외한 폭을 사용한다. 열 너비가 바뀌면 툴바 chrome만 재생성해 UIKit이 이전 방향의 제목 폭을 유지하지 않게 한다. 그리드·선택 상태는 유지하며 제목은 측정 영역 밖으로 확장하지 않는다. 파일·타깃·저장 경로 변경은 없다.

2026-10-16 상세 툴바 표시 복구: 단일 trailing packHeader와 상세 폭에서 84pt를 빼는 계산·너비 기반 id 재생성을 제거했다. InstalledPackView의 navigationTitle(pack.title)와 독립적인 leading 선택, trailing 공유·옵션 ToolbarItem을 복원했다. principal 커스텀 제목·영역 밖 좌표 보정은 사용하지 않고 시스템이 제목 크기·말줄임·회전 배치를 관리한다. packOptions는 기존 상세 기능을 유지하는 뷰 속성이다. 앞선 상세 헤더 통합 설명을 대체한다. 파일·타깃·리소스·저장 경로 변경은 없다.

2026-10-16 제목 여백 정렬: InstalledPackView의 선택 버튼과 첫 trailing 공유 버튼에 실제 경계 측정 뷰를 부착한다. LibraryNavigationLayout의 PackCenteredTitle은 동일 좌표계에서 두 버튼 사이 폭을 계산해 좌우 8pt 간격과 중앙 정렬·한 줄 말줄임을 적용한다. 회전·선택 버튼 크기 전환 중에도 경계를 갱신한다. 파일·타깃·리소스·저장 경로 변경은 없다.

2026-10-16 제목 표시 복구: PackCenteredTitle은 principal 호스트가 UINavigationBar의 자식이라는 가정을 제거하고 실제 양쪽 액션 marker의 공통 상위 뷰에서 제목을 배치한다. marker 갱신 시 참조를 다시 등록하며 측정 전에는 제목 호스트 내부 UILabel을 표시한다. 1pt 고유 폭 대신 최대 200pt의 정상 제목 폭을 제공해 이름이 완전히 숨겨지지 않도록 한다. 파일·타깃·리소스·저장 경로 변경은 없다. 요청에 따라 테스트·UI 검증 없이 실기기 빌드·덮어쓰기 설치·실행만 수행한다.

2026-10-16 제목 가용 폭 수정: 앞선 marker·공통 상위 뷰·200pt fallback 방식을 제거했다. PackCenteredTitle은 현재 제목 위치에 해당하는 UINavigationBar를 찾고 공개 UIControl/버튼 접근성 특성을 가진 실제 액션의 경계로 제목 폭을 정한다. 제목 UILabel은 한 줄 끝 말줄임과 clipping을 적용하며 버튼 사이 좌우 8pt를 사용한다. 방향별 고정 최대 폭은 없다. 기존 파일 내부 수정으로 타깃·리소스·저장 경로 변경은 없다. 테스트 없이 실기기 빌드·설치·실행만 수행한다.

2026-10-16 상세 헤더 레이아웃 교체: 앞선 UIKit 제목 overlay·버튼 탐색·CADisplayLink 배치를 모두 제거했다. InstalledPackView는 상세 시스템 navigationBar를 숨기고 ScrollView의 top safeAreaInset에 뒤로(컴팩트)·선택·제목·공유/옵션을 단일 SwiftUI HStack으로 배치한다. 버튼 그룹은 고유 폭을 유지하고 제목만 남은 폭을 사용하며 양쪽 8pt 간격·한 줄 말줄임·clipping을 적용한다. LibraryNavigationLayout은 다시 회전 관찰만 담당한다. 파일·타깃·리소스·저장 경로 변경은 없다. 테스트와 UI 검증 없이 실기기 빌드·덮어쓰기 설치·실행한다.

2026-10-16 시스템 상세 툴바 복원: safeAreaInset의 packHeader와 수동 뒤로 버튼·공유/옵션 glass·고정 44pt 헤더를 제거했다. InstalledPackView는 원래 시스템 navigationBar와 SelectionControls, 독립 ShareLink/옵션 ToolbarItem을 사용한다. 제목만 principal의 한 줄 SwiftUI Text로 두고 시스템이 제안한 영역 안에서 중앙 정렬·끝 말줄임·clipping을 적용한다. 별도 좌표 보정·UIKit overlay·폭 제한은 없다. 앞선 별도 상세 헤더 설명을 대체한다. 파일·타깃·리소스·저장 경로 변경은 없으며 테스트·UI 검증 없이 실기기 빌드·덮어쓰기 설치·실행한다.

2026-10-16 공유 버튼 눌림 중 제목 겹침 수정: InstalledPackView의 무한 최대 폭 principal Text를 제거하고 navigationTitle(pack.title)과 inline 표시만 사용한다. 시스템 내비게이션 바가 공유·옵션 버튼의 눌림 전환 중에도 제목의 가용 폭과 말줄임을 관리한다. 기존 독립 툴바 버튼과 선택 상태는 유지하며 파일·타깃·리소스·저장 경로 변경은 없다. 테스트 없이 실기기 빌드·덮어쓰기 설치·실행한다.

2026-10-16 가로 상세 제목 정렬: LibraryView가 화면의 실제 가로 여부를 상세에 전달한다. 가로에서만 LibraryNavigationLayout의 LandscapePackTitle과 선택·공유 액션 경계 marker를 사용해 두 버튼 사이 영역 중앙에 한 줄 제목을 배치하고 해당 폭에서 말줄임한다. 사이드바 및 선택 버튼 전환 중에도 실제 경계를 반영한다. 세로는 기존 시스템 navigationTitle을 유지한다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로 변경은 없다.

2026-10-16 가로 팩별 제목 정렬 보정: 앞선 PackTitleBounds 약한 참조와 principal 내부 UILabel 배치를 대체한다. 가로 제목은 표시 중인 상세 UINavigationBar 안의 실제 marker를 찾아 버튼 사이 폭 전체를 쓰는 UILabel을 해당 bar에 배치한다. marker 참조 누락 시 시스템 제목 영역으로 정렬하던 fallback을 제거하고 가로 navigationTitle은 비워 중복 제목을 방지한다. 뷰 해제·세로 전환 시 label과 displayLink를 제거한다. 세로 및 다른 동작은 유지하며 기존 파일 내부 수정이다.

2026-10-16 가로 제목 미표시 수정: LandscapePackTitle이 UIKit UINavigationBar를 반드시 찾도록 한 조건을 제거했다. 실제 선택·공유 marker 및 principal의 공통 상위 뷰를 제목 배치 컨테이너로 사용한다. 버튼들이 아직 부착되지 않은 동안은 principal 호스트 내부에 제목을 표시해 제목을 제거하는 경로를 없앤다. 세로·버튼·회전·저장 동작과 타깃 경계는 유지한다.
