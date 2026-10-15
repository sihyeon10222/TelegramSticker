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
