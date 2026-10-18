2026-10-17 키보드 초기 크기 전환 후속: `StickerKeyboard/KeyboardViewController.swift`는 루트 UIInputView를 생성하는 loadView에서 높이 제약도 함께 설치한다. 초기 미지정 idiom은 실제 기기 idiom으로 보완하고 iPhone 방향은 초기 verticalSizeClass 대신 화면·scene 방향으로 판단한다. iPad의 임시 호스트 폭 <400pt를 플로팅 상태로 간주해 240pt를 요청하던 분기를 제거했다. 표시 전·후 같은 화면 기준으로 높이를 계산하며 회전 갱신은 유지한다. 앞선 플로팅 전용 240pt 설명을 대체한다. 파일·타깃·리소스·저장소 변경은 없으며 실제 전환 시각 검증은 실행하지 않는다.

2026-10-17 iPad 키보드 높이: `StickerKeyboard/KeyboardViewController.swift`에서 iPhone 고정 높이를 iPad에 적용하던 경로를 분리했다. iPad는 호스트 화면 크기·방향에 따라 일반 모델 가로 352/세로 398pt, 대형 모델 가로 458/세로 398pt를 요청하고 좁은 플로팅 키보드는 240pt를 유지한다. 레이아웃 시 높이 변경이 필요한 경우만 갱신한다. iPhone 높이·상태·파일·타깃·리소스·저장 경로 변경은 없다. 기본 키보드와의 실제 높이 일치는 기기 UI에서 미검증이다.

# 파일 구조와 작업 가이드

2026-10-18 Mac 파일 배포 서명 보정: 앞선 ad-hoc 서명·프로비저닝 제거 안내를 철회한다. 해당 결과물은 기존 App Group index.json 접근 권한 오류를 유발했다. Scripts/BuildMacPortable.sh는 기본 Developer ID archive/export 및 --development의 기존 Xcode 서명·프로비저닝 유지 빌드만 지원한다. Developer ID 인증서가 없으면 기본 배포 작업을 중단하며 개발 빌드를 임의 Mac용 배포판으로 안내하지 않는다. arm64/x86_64 및 내장 플러그인 서명을 유지하고 날짜별 새 출력 폴더를 쓴다. README에 Xcode Archive → Developer ID → 공증 → 내보내기 절차를 기록한다. 앱 코드·타깃·리소스·기존 저장 경로 변경은 없으며 빌드 도구는 Xcode 타깃에 포함하지 않는다.

2026-10-17 기본 높이 전환 회귀 복구: 사용자 사진에서 팩 줄만 남고 그리드가 접히는 회귀를 확인했다. UICollectionView에는 자체 콘텐츠 높이를 제공하는 intrinsic height가 없어 루트 높이 요청을 없애면 탭 줄만으로 수직 fitting이 완료될 수 있다. `StickerKeyboard/KeyboardViewController.swift`의 기본 UIInputView(.keyboard)·allowsSelfSizing과 기존 240/200/380pt 높이 제약(999)을 복구한다. fitting override·viewDidAppear 재요청은 복구하지 않는다. 중복 라이브러리/썸네일 준비 제거와 권한 기록 guard 이동은 유지한다. 기본 시스템 높이만으로 충분하다는 앞선 설명을 철회한다. 기존 파일 내부 수정으로 파일·타깃·리소스·저장소 변경은 없다. 이번 변경은 새로 발생한 접힘 회귀를 되돌리는 범위이며 원래의 간헐적 빈 화면·여백·전환 깜빡임을 해결했다고 판단하지 않는다.

2026-10-17 키보드 깜빡임 재수정: 사용자 확인상 앞선 fitting override·높이 재게시 수정은 세 현상 모두에 효과가 없었다. 해당 접근을 철회하고 `StickerKeyboard/KeyboardViewController.swift`는 시스템 UIInputViewController의 기본 루트·기본 높이를 그대로 사용한다. loadView 교체, allowsSelfSizing, 240/200/380pt 루트 높이 제약, fitting override 및 viewDidAppear 재요청을 제거한다. 그리드는 실제 배정 영역으로 기존 최소 셀 크기와 최대 네 행을 계산하며 접근성 셀·팩 줄은 유지한다. 첫 라이브러리 복원은 viewWillAppear 한 곳에서 실행하고 같은 진입의 중복 썸네일 준비를 제거한다. `Views/KeyboardStatus.swift`는 표시 시작·접근 권한 변경 시에만 공유 접근 기록을 읽고 게시한다. 레이아웃마다 동기 defaults 접근을 반복하지 않는다. 키보드 기존 파일의 수명 주기·권한 관찰 책임 변경이며 파일·타깃·리소스·저장소 경계 변경은 없다. 이전 높이 협상 설명보다 이 항목을 우선한다. 테스트 없이 빌드·덮어쓰기 설치 대상으로 제공하며 사용자 앱에서 현상이 사라졌다고 판정한 결과는 아니다.

기본 높이 재수정 완료 범위: 앱·키보드 확장 iPhone Debug 빌드 성공, 연결된 iPhone 15 Pro에 기존 데이터 유지 덮어쓰기 설치 및 앱 실행 성공. 자동·수동 테스트는 실행하지 않았다. 기본 루트의 실제 호스트 높이와 세 현상의 개선 여부는 미검증이다.

2026-10-17 키보드 초기 높이 협상 후속: `StickerKeyboard/KeyboardViewController.swift` 내부의 비공개 StickerKeyboardInputView가 UIKit의 두 systemLayoutSizeFitting 진입점에 동일한 요청 높이(세로 240pt·가로 200pt·접근성 380pt)를 반환한다. 초기 제약 설치 전의 0 높이 또는 이전 키보드 제안 크기에 측정을 맡기지 않으며 intrinsicContentSize 재정의는 추가하지 않는다. 루트의 flexibleHeight autoresizing을 제거하고 기존 우선순위 999 높이 제약과 fitting 값을 함께 갱신한다. viewDidAppear에서 팩 줄과 최소 한 행도 들어가지 않는 높이일 때만 기존 제약을 한 번 재게시한다. 필수 호스트 제약·그리드 실제 bounds 계산·상태 저장·시스템 지구본/마이크 영역은 유지한다. 기존 파일 내부의 키보드 높이 측정 책임 변경이며 파일·타깃·리소스·저장 경로 변경은 없다. 호스트 소유 상단 17pt 여백 및 시스템 한글 키보드가 먼저 재배치되는 전환은 해결 판정하지 않는다.

키보드 높이 후속 빌드·설치: 앱과 키보드 확장의 iPhone Debug 빌드 성공. 연결된 iPhone 15 Pro에 기존 앱을 덮어쓰기 설치하고 실행했다. 자동·수동 테스트는 실행하지 않았으며 간헐적 빈 키보드·전환 깨짐의 실제 해결 여부는 미검증이다.

2026-10-17 iPhone·iPad 사이드바 선택 버튼 흰 점 후속: `Features/Library/SelectionControls.swift`는 전 플랫폼에서 동일한 시스템 Button과 visible 툴바 공유 배경을 사용한다. iOS 전용 직접 glassEffect·고정 크기·blurReplace·transaction 보정을 제거해 사이드바 열 이동 중 버튼 내용과 글래스를 시스템 내비게이션 바가 함께 이동하도록 한다. 선택/편집과 파란 완료 체크 및 동작 줄이기 처리는 유지한다. 같은 버튼을 사용하는 `Features/Settings/DownloadLogsView.swift`도 시스템 툴바 배경을 표시한다. 앞선 iOS 커스텀 선택 글래스 전환 설명을 대체하며 파일·타깃·리소스·저장 경로 변경은 없다.

위 수정은 iOS 실기기 Debug 빌드 성공 후 연결된 iPhone 15 Pro와 iPad Pro 12.9 M2에 기존 앱을 덮어쓰기 설치·실행했다. 자동 테스트와 수동 UI 검증은 실행하지 않았다.

2026-10-17 설치 팩 스크롤 최적화: `UI/AnimationPreview.swift`의 StickerLargePreview는 정적·애니메이션 포스터를 기존 StickerImages/StickerThumbnailDecoder의 직렬 비동기 디코더와 메모리 캐시로 읽는다. 셀별 detached 디코딩을 제거하고 파일 URL·픽셀 크기로 revision 변경을 구분한다. `Features/Library/InstalledPackView.swift`의 상세 그리드와 LibraryView의 팩 커버는 화면 구성 중 동기 이미지 디코딩을 하지 않는다. 목록·상세 스크롤 중에는 GIF 프레임 갱신과 신규 timeline 로딩을 보류하고 정지 후 재개한다. 상세의 셀별 가시성은 같은 파일의 InstalledStickerPreview가 관리하며 일반 모드에서는 선택 좌표 측정·드래그 선택 브리지를 만들지 않는다. 한 번 탭 복사·원본 PNG/GIF·선택 모드와 확대/축소는 유지한다. 기존 앱 파일 내부 변경이며 Shared·키보드·타깃·리소스·저장 경로 변경은 없다.

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
│   │   ├── Sync/                        # 앱 전용 CloudKit 목록·순서·삭제 동기화
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
| 업데이트 확인·차이·결과 저장 | `TelegramSticker/Core/Library/PackUpdateService.swift`, `TelegramSticker/Features/Library/PackUpdatesView.swift`, `TelegramSticker/UI/PackUpdateChangesView.swift` |
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

2026-10-16 iPad 사이드바 목록 정렬: LibraryView의 넓은 레이아웃은 plain 목록과 명시적 행·헤더 여백을 사용한다. 편집 시 기본 List 선택 여백 대신 행 내부 선택 버튼으로 bulkSelected를 갱신하고 선택 원과 미리보기 사이 16pt 간격을 둔다. 일반 탐색·드래그 순서 변경·공유 및 삭제는 기존 경로를 유지한다. LibraryListStyle은 같은 파일 내부의 표시 전용 modifier다. 파일 이동·타깃·리소스·저장 경로 변경은 없다.


2026-10-16 선택·공유·알림 개선: `StickerDragSelection.swift`를 Features/Library에서 앱 공통 `UI/`로 옮겨 상세와 갤러리가 함께 사용한다. 갤러리는 미설치 팩의 드래그 범위 선택·전체 선택/선택 해제를 제공한다. `App/TabReselectionObserver.swift`는 시스템 탭 delegate를 전달하면서 내 스티커 팩 재선택을 홈 이동 이벤트로 연결한다. 하단 작업 버튼 규격과 행 상하 여백을 통일하고 넓은 사이드바도 공유·추가 툴바 그룹을 사용한다. `UI/PackLinkSharing.swift`는 실제 상세 공유 버튼에 iPad popover를 고정하고 목록 스와이프는 링크 텍스트 공유를 바로 연다. 최적화 완료 알림에는 세션·품질 목적지를 넣고 앱에서 준비 결과 및 revision 유효성을 확인한 뒤 비교·적용 화면을 연다. 기존 모달이 닫힐 때까지 대기하며 만료 결과는 재준비를 안내한다. 파일은 앱 동기화 그룹에만 포함되고 키보드·백엔드·저장 경로 변경은 없다. 테스트는 요청 없이는 실행하지 않는다.

2026-10-17 알림 종료 수정: WorkNotifications는 async delegate bridge 대신 명시적인 completion handler delegate를 사용하고, 알림 응답 및 foreground 표시의 완료 콜백을 MainActor에서 호출한다. iPad 종료 로그의 UIKit snapshot/state restoration 메인 스레드 assertion을 해결하기 위한 변경이다. 상세 공유 버튼은 기존 기본 전경색을 사용한다. 넓은 사이드바의 설치된 팩 제목은 고정 Section header 대신 일반 목록 행으로 배치해 스크롤과 함께 사라진다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로는 유지한다.

2026-10-17 목록 외형 통일: LibraryView는 세로 목록과 넓은 사이드바 모두 insetGrouped 스타일, 좌우 섹션 여백 20pt, 행 내부 사방 16pt를 사용한다. 넓은 화면의 plain/투명 행 배경과 LibraryListStyle modifier를 제거해 시스템 그룹 배경과 둥근 섹션 모서리를 공통 사용한다. 사이드바 선택 원의 이동 애니메이션과 상태는 유지한다. 기존 파일 내부 수정으로 타깃·리소스·저장 경로 변경은 없다.

2026-10-17 사이드바 색상·선택 수정: 목록/사이드바 모두 base userInterfaceLevel의 systemGroupedBackground와 secondarySystemGroupedBackground를 명시해 밝은 모드에서 회색 바탕·흰색 목록을 유지한다. 다크 모드는 시스템 의미 색상을 유지한다. 가로 전용 수동 선택 버튼과 강제 inactive EditMode를 제거하고 양쪽 모두 NavigationLink 및 List(selection:)/EditMode 바인딩으로 시스템 선택 원 애니메이션과 두 손가락 다중 선택을 사용한다. 앞선 가로 수동 선택·모션 설명을 대체하며 파일·타깃·저장 경로 변경은 없다.

2026-10-17 iPhone 가로 목록 모서리 수정: 넓은 사이드바의 Section leading margin에 실제 화면 leading safe-area inset을 더해 노치 안전 영역이 섹션의 왼쪽 둥근 모서리를 잘라내지 않도록 한다. 기본 20pt 여백, 시스템 선택·행 내부 여백·색상은 유지한다. 기존 파일 내부 변경이며 타깃·저장 경로 변경은 없다.

2026-10-17 사이드바 열기 선택 버튼 점 수정: SelectionToggleButton의 GlassEffectContainer와 glassEffectID를 제거해 내비게이션 열 이동 중 글래스가 작은 점으로 morph되는 경로를 없앤다. 버튼 자체의 interactive glassEffect와 선택/완료의 크기·색상 전환은 유지한다. 기존 파일 내부 수정으로 타깃·저장 경로 변경은 없다.

2026-10-17 사이드바 간격·툴바 후속: Section leading은 max(20pt, 실제 leading safe-area inset)으로 지정해 안전 영역에 기본 여백을 중복 추가하지 않는다. 넓은 사이드바의 scrollContent 상단 여백은 8pt로 줄인다. SelectionToggleButton의 직접 glassEffect·고정 frame·opacity 중첩 라벨·로컬 애니메이션과 두 호출부의 sharedBackgroundVisibility(.hidden)을 제거하고 시스템 Button/툴바 chrome으로 전환한다. 완료는 시스템 borderedProminent 체크 버튼이다. 앞선 글래스 ID만 제거하는 수정 설명을 대체하며 기존 파일 내부 변경이다.

2026-10-17 사이드바 재열기 버튼 블러 후속: InstalledPackView의 leading 툴바에 시스템 fixed ToolbarSpacer를 두어 열 사이를 이동하는 기본 sidebarToggle과 선택 버튼의 글래스 그룹을 분리한다. 선택 버튼은 기존 시스템 Button을 유지하고 UIKit 토글 이동·열 전환은 변경하지 않는다. 기존 파일 내부 변경이다.

2026-10-17 목록 공유 전체 선택 안정화: LibraryView의 편집·공유 선택은 모든 방향과 사이드바에서 행 버튼과 bulkSelected로 직접 관리한다. 시스템 List 선택 바인딩은 일반 탐색에서만 사용하며 편집 중 늦게 도착한 탐색 선택 콜백은 무시한다. 공유 진입 시 전체 팩 선택이 시스템 목록의 편집 전환에 의해 덮어써지지 않게 한다. 파일·타깃·리소스·저장 경로 변경은 없다.

2026-10-17 선택 버튼 재열기 블러 원인 분리: InstalledPackView에서 가로 선택 버튼에 붙이던 PackTitleBoundary UIKit background와 불필요한 fixed ToolbarSpacer를 제거한다. 방향에 관계없이 동일한 SelectionControls ToolbarContent를 유지한다. LandscapePackTitle은 선택 버튼에 측정 뷰를 삽입하지 않고 실제 시스템 버튼의 접근성 ID/라벨과 경계를 읽으며 공유 쪽 경계와 함께 제목 영역을 계산한다. 앞선 그룹 분리 수정 설명을 대체하며 기존 파일 내부 변경이다.

2026-10-17 목록 선택 원 모션 복구: LibraryView는 탐색·편집 사이에서 동일한 행 Button과 HStack을 유지하며 선택 원의 폭·위치·투명도를 애니메이션한다. 일반 탭은 selected 및 compactColumn으로 상세를 열고 편집 탭은 기존 bulkSelected를 갱신한다. 동작 줄이기 설정을 존중하며 공유 전체 선택 유지와 기존 파일·타깃·저장 경로는 보존한다.

2026-10-17 선택 상태 흐림 전환: 공통 SelectionToggleButton은 편집/선택과 완료 버튼을 안정적인 ZStack 안에서 Apple SwiftUI blurReplace transition으로 교체한다. 애니메이션은 active 변경에만 연결하며 Reduce Motion에서는 애니메이션을 생략한다. 직접 glassEffect·UIKit 측정 뷰는 추가하지 않는다. 기존 파일 내부 수정이다.

2026-10-17 사이드바 편집 작업 정렬: LibraryView는 목록 행의 실제 수평 중심을 목록 좌표계에서 측정하고 하단 편집·공유 작업을 같은 중심에 배치한다. 비대칭 안전 영역과 섹션 여백을 반영하며 작업 배너와 파일·타깃·저장 경로는 유지한다.

2026-10-17 iPhone 가로 목록 폭 조정: LibraryView의 휴대폰 가로 사이드바에서만 설치된 팩 섹션의 trailing 여백을 20pt에서 시스템 툴바 끝 여백에 맞춘 8pt로 줄인다. 목록을 오른쪽으로 확장하고 하단 작업은 기존 실제 행 중심 측정으로 함께 정렬한다. 기존 파일 내부 변경이다.

2026-10-17 가로 사이드바 상단 블러 복구: LibraryView의 iPhone 가로 목록 상단에 시스템 hard scroll-edge 효과를 명시한다. 하단 작업 정렬의 전체 높이 GeometryReader overlay를 제거하고 목록과 행의 중심을 onGeometryChange로 측정해 하단 영역만 overlay한다. 넓힌 목록 폭과 작업 중앙 정렬은 유지하며 기존 파일 내부 변경이다.

2026-10-17 상태 버튼 전환 공통화: `UI/ButtonLabelTransition.swift`는 Apple blurReplace 전환을 버튼 내부 라벨에 적용하는 공통 modifier와 문자열 버튼을 제공한다. SelectionToggleButton은 하나의 Button을 유지하고 confirm role·라벨만 상태에 따라 갱신한다. 갤러리 전체 선택/해제·설치 개수·선택 아이콘, 로그 복사됨·선택 아이콘, 가져오기 설치/업데이트 결과, 최적화 닫기/적용 개수와 상세 선택 아이콘에도 공통 라벨 전환을 사용한다. 앱 동기화 그룹에 자동 포함되며 키보드·서버 타깃과 저장 경로 변경은 없다.

2026-10-17 상단 블러 자동 전환 복원: LibraryView의 hard scroll-edge 및 hidden(false) 강제 지정을 제거한다. 상단 효과는 목록 스크롤 위치에 따른 시스템 기본 전환에 맡기며 목록 폭·하단 정렬 및 전체 높이 overlay 제거는 유지한다. 기존 파일 내부 변경이다.

2026-10-17 공통 흐림 전환 철회: 버튼 표시 문제로 UI/ButtonLabelTransition.swift와 모든 호출을 제거하고 일반 시스템 Button 라벨로 복구했다. SelectionToggleButton은 원래의 기본 편집/선택 버튼과 파란 borderedProminent 완료 체크 버튼으로 복원했다. 앞선 공통 흐림 전환 설명을 대체한다. 앱 동기화 그룹의 파일 삭제이며 키보드·저장 경로 변경은 없다.

2026-10-17 선택 버튼 형태 전환 수정: SelectionToggleButton은 단일 plain Button과 Apple GlassEffectContainer/glassEffectID를 사용한다. 동일한 capsule 글래스의 높이를 44pt로 유지하고 폭을 64pt에서 44pt로 애니메이션해 편집/선택 타원과 완료 원형 사이를 전환한다. 파란 tint는 완료에만 적용하고 내부 라벨에는 blurReplace를 사용한다. SelectionControls의 시스템 공유 배경은 숨겨 글래스 중첩을 막는다. 기존 파일 내부 변경이며 타깃·리소스·저장 경로 변경은 없다.

2026-10-17 선택 버튼 높이 보정: SelectionToggleButton의 높이와 완료 원형 지름을 44pt로 맞추고 fixedSize로 툴바 내부 수직 압축을 방지한다. 기존 타원↔원형 글래스 전환은 유지한다. 기존 파일 내부 변경이다.

2026-10-17 목록 두 손가락 선택 복구: LibraryView의 수동 선택 원·편집 행 버튼을 제거하고 List(selection:)와 실제 EditMode 바인딩으로 시스템 다중 선택을 사용한다. bulkSelected는 상세 탐색 selected와 분리된 안정적인 바인딩으로 유지해 공유 진입 시 전체 선택을 보존한다. 시스템 제스처로 선택이 시작되면 편집 작업을 표시한다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로 변경은 없다.

2026-10-17 녹화 기반 선택 버튼 점 후속: 사이드바 재열기 중 상세 선택 버튼이 작은 흰 글래스로 축소된 뒤 복원되는 장면을 확인했다. SelectionControls는 시스템 툴바 배경을 사용하고 SelectionToggleButton의 직접 glassEffect·고정 크기·라벨 transition을 제거한다. 단일 시스템 Button의 선택 텍스트/완료 체크 및 confirm role을 사용해 열 이동 시 배경과 버튼을 내비게이션 바에서 함께 관리한다. 앞선 직접 글래스 형태 전환 설명을 대체하며 파일·타깃·리소스·저장 경로 변경은 없다.

2026-10-17 선택 버튼 색상·모션 복구: SelectionToggleButton은 하나의 Button과 capsule glassEffect를 유지하며 64pt 편집/선택 버튼에서 44pt 파란 완료 버튼으로 폭·색을 함께 전환한다. 내부 글자/체크는 blurReplace를 사용하며 Reduce Motion을 존중한다. 별도 버튼 분기로 인한 모션 단절을 제거하고 시스템 공유 배경은 숨긴다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로 변경은 없다.

2026-10-17 사이드바 전환 흰 점 후속: SelectionToggleButton은 glassEffectTransition(.identity)로 툴바 재부착 중 글래스의 등장·퇴장 축소 전환을 생략한다. 바깥 transaction에서 내비게이션 애니메이션을 제거한 뒤 내부 active 값 전용 애니메이션만 적용해 사이드바 열 이동이 버튼의 글래스·라벨 전환에 전달되지 않도록 한다. 선택/완료의 폭·파란 tint·blurReplace와 시스템 사이드바 토글은 유지한다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로 변경은 없다.

2026-10-17 선택 버튼 교체 철회: 사용자 요청으로 UIKit UIButton 렌더링 교체를 되돌리고 교체 직전의 SwiftUI SelectionToggleButton을 복원했다. 기존 capsule glassEffect, 선택/완료 크기·색상·blurReplace 및 glassEffectTransition(.identity)/transaction 설정을 복원하며 다른 기능은 변경하지 않는다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로 변경은 없다.

## 2026-10-17 Mac Catalyst 및 iCloud 목록 동기화

- 앱 타깃은 iPhone·iPad·Mac Catalyst를 지원한다. Catalyst는 iPad idiom(Scale Interface to Match iPad), macOS 27.0 이상을 사용한다. 키보드 타깃 의존성과 확장 임베드에는 `ios` platform filter를 적용하므로 맥 번들에는 확장이 포함되지 않는다. `Shared/`의 의미와 키보드의 네트워크·변환 금지 경계는 유지한다.
- `App/StickerAppDelegate.swift`는 CloudKit 빌드의 APNs 등록·수신을 연결한다. `App/StickerMacCommands.swift`는 맥의 포커스별 복사·전체 선택·파일 열기 명령을 제공한다. 텍스트 입력 중에는 시스템 편집 액션으로 전달한다. 맥 시작 안내는 키보드 권한을 요구하지 않는다.
- `Core/Background/BackgroundWork.swift`는 동일한 진행·취소 API 아래 iOS continued processing과 Catalyst의 ProcessInfo activity를 분리한다. 맥의 미완료 수동 가져오기는 기존 ImportJobs draft로 재실행 시 재개한다.
- `Core/Sync/LibraryChangeJournal.swift`는 LibraryWriter가 게시하는 목록 변경의 write-ahead journal과 기기 논리 시계를 관리한다. `LibrarySyncModels.swift`는 CloudKit 전용 팩·순서·삭제 기록과 계정별 저장 모델이다. `LibrarySyncService.swift`는 CKSyncEngine, 최초 병합, 충돌 병합, 전송 큐, 계정 변경과 상태를 관리한다. 이 영역은 기능 화면 모델을 참조하지 않는다.
- `Features/Import/SyncDownloadCoordinator.swift`는 클라우드 목록을 기존 ImportCoordinator에 연결하고 원격 삭제·진행·취소·재시도를 담당한다. 원격 다운로드는 `syncOrigin`으로 LibraryWriter에 게시하여 재업로드하지 않는다. `Features/Settings/SyncSettingsView.swift`는 동기화 상태·계정 연결 확인·수동 재시도를 표시한다. 미다운로드 팩은 LibraryView의 별도 섹션에 표시하며 설치 전에는 공유 라이브러리 인덱스에 넣지 않는다.
- 모든 새 Swift 파일은 기존 앱 파일 시스템 동기화 그룹에만 포함된다. 키보드는 CloudKit·가져오기·변환 패키지를 연결하지 않는다. PNG·GIF·설치 revision 및 기존 App Group 경로·원자적 게시·경로 검증을 유지한다. 개별 스티커 삭제·화질 변경은 기기별로 유지하고, 마지막 스티커를 지워도 팩 목록 삭제로 전파하지 않는다.
- 추가 앱 전용 경로: `Application Support/LibrarySync/<account-hash>.json`(병합 메타데이터·전송 큐·엔진 상태), `clock-<account-scope>.json`(논리 시계), `Journal/<account-scope>/*.{pending,json}`(게시 전/완료 변경), `Downloads/<account-scope>/<pack-id>/`(재개 가능한 원격 다운로드). 계정 미연결 변경은 `unassigned` 범위에 보관한다. 키보드는 이 경로를 읽지 않는다.
- 기본 서명은 개인 개발 팀에서도 설치할 수 있도록 CloudKit을 끈다. `Configuration/TelegramSticker.entitlements`는 iOS, `TelegramSticker-Mac.entitlements`는 Catalyst 기본 서명이다. 유료 개발 팀에서는 `Configuration/CloudKit.xcconfig`와 각 플랫폼의 `*-iCloud.entitlements`를 사용한다. 앱의 `STICKERBRIDGE_APP_ENTITLEMENTS`만 전환하고 키보드 서명은 기존 파일을 유지한다. CloudKit 컨테이너는 `iCloud.com.sihyeon.TelegramSticker`, private zone은 `StickerLibrary`, 레코드는 `Pack` 및 `PackOrder`이며 JSON 메타데이터를 `payload` Bytes 필드에 저장한다. 첫 배포의 iCloud 환경은 Development다.
- 앱 초기화는 동기화를 중지한 뒤 로컬 데이터만 지운다. 전체 팩 삭제만 기기 간 전파한다. iCloud 기능 사용에는 유료 Apple Developer 팀·컨테이너·프로비저닝 구성이 필요하며 개인 팀에서는 설정에 제한을 표시한다.

Catalyst 시작 시 UIKit 시스템 탭과 NavigationSplitView의 네이티브 NSToolbar 그룹이 함께 재배치되며 AppKit 제약 예외가 발생하는 것을 확인했다. 맥의 ContentView는 상단 segmented 화면 선택과 각 기능 화면을 사용하고, SelectionControls는 맥에서 기본 시스템 버튼을 사용한다. iPhone·iPad의 TabView와 선택 글래스는 유지한다. CloudKit 활성화 플래그는 App-Info.plist의 빌드 변수 치환으로 실제 번들에 포함한다.

2026-10-17 완료 확인: Mac Catalyst arm64 Debug·Release 빌드 성공. Debug 앱을 `~/Applications/StickerBridge.app`에 설치하고 실행 프로세스 유지 확인. 맥 번들에 키보드 확장이 없고 샘플 PNG·TGS/WebM·Lottie 리소스와 App Group·Sandbox 서명을 포함함을 확인했다. 연결된 iPhone 15 Pro에 Debug 빌드·기존 앱 덮어쓰기 설치·실행 완료. 자동 테스트와 수동 기능 테스트는 실행하지 않았다. 개인 개발 팀의 iCloud/Push Notifications 서명 거절 때문에 실제 iCloud 연결·기기 간 동기화는 미확인 및 비활성화 상태다. CloudKit xcconfig의 앱 서명 전환과 키보드의 기존 서명 유지, 기본 번들의 CloudKit 플래그 NO를 확인했다.


2026-10-17 맥 UI를 iPad와 통일: 앞선 Mac idiom·상단 segmented 화면 선택·맥 전용 선택 버튼 설명을 대체한다. 앱의 TARGETED_DEVICE_FAMILY에서 6을 제거해 Catalyst를 iPad idiom으로 실행한다. ContentView는 전 플랫폼에서 동일한 TabView와 하단 배치용 compact 환경을 사용하고 각 탭 내용에는 실제 size class를 전달한다. SelectionControls의 맥 전용 기본 버튼과 상세의 맥 전용 복사 툴바를 제거해 iPad의 글래스 선택·공유·옵션 배치를 그대로 사용한다. LibraryView의 제목·가로 상세·사이드바 크기 및 방향 관찰도 공통 경로를 사용한다. 맥의 키보드 명령 포커스는 유지하되 별도 포커스 외곽선은 표시하지 않는다. 파일 이동·리소스·저장 형식 변경은 없다.

2026-10-17 iPad 배치 통일 완료 확인: Catalyst arm64 Debug·Release 및 연결된 iPhone Debug 빌드 성공. 맥 번들의 UIDeviceFamily가 [2]인 iPad UI 모드임을 확인하고 기존 맥 앱 위에 설치·실행했다. 연결된 iPhone 15 Pro에도 기존 앱을 덮어쓰기 설치·실행했다. 자동 테스트·수동 UI 테스트는 실행하지 않았다.


2026-10-17 Catalyst 창 크기·레이아웃 후속: `App/MacWindowConfiguration.swift`는 앱 타깃 전용 UIViewRepresentable로 실제 UIWindowScene의 최소 크기 640×480pt·무제한 최대 크기·전체 화면 허용을 설정한다. TelegramStickerApp은 확장 가능한 콘텐츠 frame과 windowResizability(.contentMinSize)를 사용한다. 맥의 LibraryView는 창 폭 760pt 이상에서 두 열을 사용하고 사이드바 폭을 280~360pt로 제한하며 그보다 좁으면 compact 탐색으로 접는다. 맥에서는 창 비율 변경을 기기 회전으로 처리하지 않는다. 상세 제목은 iPad와 같은 상단 내비게이션 위치에 두되 맥의 live resize 중에는 시스템 navigationTitle의 말줄임을 사용하고 별도 UILabel 재부착·CADisplayLink 경계 측정을 사용하지 않는다. iPhone·iPad의 기존 배치·회전·제목 동작은 유지한다. 새 파일은 기존 앱 동기화 그룹에만 포함되고 키보드·리소스·저장소 변경은 없다.


리퀴드 글래스 버튼 후속: 사용자 확인에 따라 Catalyst의 SelectionToggleButton은 직접 glassEffect·고정 frame·blurReplace·폭 애니메이션을 사용하지 않고 시스템 glass/glassProminent 버튼 스타일로 동일 위치의 편집/선택·완료를 표시한다. 맥의 하단 팩 편집 버튼은 공통 액션 HStack을 사용하되 GlassEffectContainer의 합성·모핑 없이 각각 시스템 글래스로 렌더링하고 regular 크기를 사용한다. iPhone·iPad는 기존 글래스 효과·전환·컨테이너·small 크기를 유지한다. 파일·타깃·저장소 변경은 없다.

2026-10-17 창 크기·글래스 후속 완료 확인: Catalyst arm64 Debug·Release 및 연결된 iPhone Debug 빌드 성공. 맥 앱을 기존 위치에 덮어쓰기 설치·실행했고 연결된 iPhone 15 Pro도 기존 데이터 유지 설치·실행했다. MacWindowConfiguration은 앱 동기화 그룹으로 컴파일되며 키보드에는 포함되지 않는다. 자동 테스트·창 드래그·버튼 외형 수동 검증은 실행하지 않았다.


2026-10-17 스크린샷 기반 글래스 버튼 수정: 앞선 Catalyst glass/glassProminent 스타일 전환만으로는 가져오기 화면의 넓은 버튼 표면 깨짐이 남았고, 툴바 배경 hidden 설정 때문에 편집/선택은 글자만 표시됨을 사용자 스크린샷에서 확인했다. `UI/AppGlassAppearance.swift`는 앱 공통 버튼·패널·컨테이너의 플랫폼 경계다. iOS는 기존 Liquid Glass API를 사용하고, Catalyst 콘텐츠 버튼은 regularMaterial 캡슐·고정 선 테두리·강조 tint 및 명시적인 비활성/눌림 상태로 그린다. Catalyst에서 콘텐츠 버튼·패널의 glass shader와 컨테이너 모핑을 사용하지 않는다. 가져오기·갤러리·온보딩·저장 공간·최적화·현재 작업 배너·하단 팩 작업에 공통 경로를 적용한다. SelectionControls와 로그 선택 툴바는 Catalyst에서 sharedBackgroundVisibility(.visible)와 기본 시스템 Button을 사용해 시스템 글래스 캡슐을 복원한다. iPhone·iPad의 기존 툴바 background hidden과 커스텀 선택 전환은 유지한다. 새 파일은 기존 앱 동기화 그룹에만 포함되며 키보드·백엔드·리소스·데이터 경로 변경은 없다.

2026-10-17 스크린샷 후속 빌드·설치: Catalyst arm64 Debug·Release와 연결된 iPhone Debug 빌드 성공. 맥 앱 및 연결된 iPhone 15 Pro를 기존 데이터 유지 방식으로 덮어쓰기 설치·실행했다. 새 AppGlassAppearance는 앱 타깃으로 컴파일되며 키보드에는 포함되지 않는다. 자동 테스트와 수동 UI 테스트는 실행하지 않았다.


2026-10-17 모달 닫기·상세 공유 후속: `UI/AppGlassAppearance.swift`의 AppModalCloseToolbar는 가져오기·최적화·받은 링크·팩 공유 모달의 cancellationAction을 공통 처리한다. Catalyst는 해당 버튼의 시스템 툴바 배경만 숨기고 기존 CatalystMaterialButtonStyle로 반투명 캡슐을 직접 표시하며, iOS는 기존 기본 ToolbarItem/Button을 유지한다. `UI/PackLinkSharing.swift`의 PackLinkShareButton은 Catalyst에서 ShareLink를 직접 사용하여 SwiftUI가 실제 툴바 공유 앵커를 관리한다. Catalyst에서 네이티브 툴바로 추출된 버튼의 background UIView가 미부착 상태일 때 이전 ShareAnchor의 guard가 조용히 반환하던 경로를 제거한다. iPhone·iPad의 실제 공유 버튼 popover 앵커는 기존 구현을 유지한다. 기존 앱 타깃 내부 책임 변경이며 파일 이동·타깃·리소스·저장소 변경은 없다.

2026-10-17 모달 닫기·상세 공유 빌드·설치: Catalyst arm64 Debug와 연결된 iPhone Debug 빌드 성공. 맥 앱 및 연결된 iPhone 15 Pro에 기존 앱을 덮어쓰기 설치하고 실행했다. iPhone 첫 실행 요청은 LaunchServicesDataMismatch로 거부되었으나 재요청으로 실행 성공했다. 자동 테스트·수동 UI 및 공유 동작 테스트는 실행하지 않았다.

2026-10-17 Catalyst 상세 공유 위치 후속: UI/PackLinkSharing.swift의 맥 상세 공유 버튼은 실제 UIButton을 UIViewRepresentable로 툴바에 배치하고 동일 버튼의 bounds를 UIActivityViewController popover sourceView/sourceRect로 사용한다. ShareLink가 창 하단을 기준으로 표시하던 경로를 대체하며 공유창은 버튼 아래에 표시하도록 화살표 방향을 지정한다. iOS 공유 경로·파일·타깃·저장소 변경은 없다.

2026-10-17 상세 공유 위치 빌드·설치: Catalyst arm64 Debug 및 연결된 iPhone Debug 빌드 성공. 맥 앱과 iPhone 15 Pro에 기존 데이터를 유지해 덮어쓰기 설치·실행했다. 자동 테스트와 공유창 위치 수동 테스트는 실행하지 않았다.

2026-10-17 Catalyst 최소 창 탭바 잘림 수정: App/TelegramStickerApp.swift는 콘텐츠에 창 최소 높이 480pt를 중복 강제하지 않고 실제 제안 크기에 맞춘다. 창 최소 640×480은 기존 MacWindowConfiguration의 UIWindowScene sizeRestrictions에서 유지하고 SwiftUI windowResizability는 automatic으로 둔다. 제목 표시줄만큼 콘텐츠가 창 아래로 넘치는 것을 방지하며 탭바 디자인·iOS 동작·타깃·파일·저장소 변경은 없다.

2026-10-17 최소 창 탭바 수정 빌드·설치: Catalyst arm64 Debug와 연결된 iPhone Debug 빌드 성공. 맥 및 iPhone 15 Pro에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 자동 테스트·창 크기 변경 수동 테스트는 실행하지 않았다.

2026-10-17 iPhone·iPad 상세 공유 무반응 수정: UI/PackLinkSharing.swift의 iOS PackLinkShareButton은 기본 ShareLink로 공유창 표시와 버튼 앵커를 시스템에 맡긴다. 툴바 background UIView의 부착 여부에 의존하던 ShareAnchor/AnchorView를 제거했다. 기존 SwiftUI 아이콘·비활성 조건·접근성 ID를 유지하며 Catalyst의 실제 UIButton 앵커와 색상은 변경하지 않는다. 파일·타깃·저장소 변경은 없다.

2026-10-17 iOS 상세 공유 수정 확인: Catalyst arm64 Debug 및 연결된 iPhone Debug 빌드 성공. 맥과 iPhone 15 Pro에 기존 데이터 유지 방식으로 덮어쓰기 설치했다. 자동 테스트·공유 수동 테스트는 실행하지 않았다.

2026-10-17 iOS 편집/선택 전환 복원: Features/Library/SelectionControls.swift는 iPhone·iPad에서 기존 커스텀 캡슐 glassEffect, 활성 상태 44pt 파란 체크 버튼, blurReplace·폭/색 전환과 시스템 툴바 배경 숨김을 복원한다. Catalyst는 현재 시스템 버튼·표시 배경을 유지한다. 파일·타깃·저장소 변경은 없다.

2026-10-17 선택 전환 복원 빌드·설치: Catalyst arm64 Debug 및 연결된 iPhone Debug 빌드 성공. 맥과 iPhone 15 Pro에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 자동 테스트·수동 UI 테스트와 iPad 설치는 실행하지 않았다.


2026-10-17 맥 백그라운드 복사 팝업: `MacDesktop/`는 macOS 전용 `StickerBridgeDesktop.bundle` 타깃이다. `DesktopPlugin.swift`가 AppKit 메뉴 막대·accessory 실행 정책·로그인 실행(SMAppService)·Carbon 전역 ⌥⇧S·비활성 NSPanel·NSGlassEffectView·팩/최근 그리드를 관리한다. `DesktopBridge.swift`는 Foundation/Objective-C 호환 브리지 계약으로 번들과 Catalyst 앱에만 컴파일한다. 앱의 `App/MacDesktopCoordinator.swift`는 번들을 유지·로딩하고 기존 LibraryModel/LibraryReader에서 표시 데이터를 읽어 StickerCopyService로 PNG/GIF를 복사한다. 파일 경로 검증과 라이브러리 게시 경로는 기존 구현을 따른다. 설정의 MacDesktopSettings에서 로그인 실행·메뉴 막대 표시·오류를 관리하고 팝업 설정 버튼은 기존 앱의 설정 탭을 연다. Finder reopen은 관리 창을 표시하며 로그인 실행은 창을 숨긴다. Dock은 Catalyst에만 LSUIElement 및 accessory 정책으로 숨긴다.

번들은 Catalyst에만 의존·임베드·서명하며 iOS 및 키보드 확장에는 포함하지 않는다. 네트워크·변환·키보드 State 코드를 macOS 번들에 연결하지 않는다. 최근 24개 ID(`mac.recentStickers`), 마지막 팩(`mac.lastPack`), 메뉴 표시(`mac.menuVisible`), 로그인 최초 구성(`mac.loginConfigured`)은 맥 프로세스 기본 UserDefaults에만 저장하며 App Group 라이브러리·iOS 데이터 경로·CloudKit 형식은 변경하지 않는다. 복사 성공만 창을 닫으며 오류는 표시한다. 창 바깥 클릭·Esc·단축키 재입력으로도 닫힌다.

맥 팝업 런타임 경계 보완: Catalyst 프로세스에 로드되는 SwiftUI는 UIKit용이므로 macOS NSHostingView 심벌을 제공하지 않는다. macOS 번들에서 SwiftUI를 링크하지 않고 NSStackView/NSScrollView/NSButton 기반 AppKit 그리드와 비동기 썸네일 읽기를 사용한다. NSGlassEffectView는 유지한다. 최초 SwiftUI 호스팅 버전의 번들 로드 실패를 실행 로그에서 확인하고 제거했으며, 수정 후 설치한 앱 프로세스에서 StickerBridgeDesktop 실행 이미지 로드를 확인했다.

맥 팝업 완료 범위: AppKit 전환 후 Catalyst Debug·Release 빌드 성공, Debug 앱을 `~/Applications/StickerBridge.app`에 기존 데이터 유지 덮어쓰기 설치·실행했다. 앱·번들의 deep/strict 서명 검증 성공 및 실행 프로세스의 번들 로드를 확인했다. 번들은 AppKit·Carbon·ServiceManagement를 사용하고 SwiftUI에 링크하지 않는다. iOS Debug 빌드·연결된 iPhone 15 Pro 덮어쓰기 설치·실행은 앞선 단계에서 완료했다. iOS 번들에는 StickerKeyboard.appex만 있고 macOS 번들은 없다. 자동 테스트·수동 UI 테스트·로그인 재시작 검증은 실행하지 않았다.

2026-10-17 맥 스티커 팝업 이동·크기·팩 전환: `MacDesktop/DesktopPlugin.swift`의 PickerPanel은 transparent titlebar/fullSizeContentView를 사용하는 native resizable 비활성 패널이다. 상단 PickerDragHeader/배경 드래그로 이동하고 가장자리에서 크기를 조절한다(최소 360×260pt). NSWindowDelegate가 이동·크기 변경 및 닫기 시 프레임을 맥 기본 UserDefaults의 `mac.pickerFrame.v1`에 저장하고 새 팝업에서 복원한다. 연결 화면이 달라지거나 창이 화면 밖이면 사용 가능한 화면 안으로 크기·위치를 보정한다. PickerContentView는 창 너비에 맞춰 열 수를 재계산하고 그리드 문서는 위쪽부터 배치한다. PackSwipeScrollView가 가로 트랙패드/스크롤 제스처 한 번당 인접 팩으로 한 번 전환하며 최근 탭도 같은 순서에 포함한다. 세로 스크롤과 모멘텀을 분리해 연속 오전환을 막고 선택 탭을 가로 탭 줄에 노출한다. Esc도 공통 닫기 경로로 저장과 이벤트 모니터 정리를 수행한다. 파일·타깃·리소스·라이브러리 저장 경로는 변경하지 않는다.

팝업 이동·크기·팩 전환 빌드·설치: Catalyst Debug 및 최종 Release 빌드 성공. 최종 Release 앱을 기존 맥 앱 위에 덮어쓰기 설치·실행하고 deep/strict 서명 검증을 완료했다. 연결된 iPhone 15 Pro도 Debug 빌드·기존 데이터 유지 설치·실행했다. 자동 테스트·수동 UI 테스트는 실행하지 않았다.


2026-10-17 최적화 최종 적용 후 캐시 정리: `Features/Import/ImportJobCache.swift`는 적용 후 import lease를 유지한 채 기존 캐시 정리 경로로 비교 파일까지 삭제한다. `Features/Optimization/OptimizationSession.swift`는 적용 완료 후 모든 비교 참조를 비우고 `OptimizationView.swift`는 완료 상태에서 비교 생성 버튼을 숨기며 자동 삭제를 안내한다. 설치 라이브러리·설정·타깃·파일 배치는 유지한다.

2026-10-17 맥 팝업 키보드 구성·재생·페이지 모션: `App/MacDesktopCoordinator.swift`는 기존 reader의 경로 검증을 거친 작은 playback GIF와 원본 animation 경로를 표시 데이터에 추가한다(복사는 기존 StickerCopyService 유지). `MacDesktop/DesktopPlugin.swift`의 상단 탭은 전체·최근 사용·팩 대표 이미지 순서이며 팩 이름은 툴팁/접근성 설명으로만 제공한다. 기본은 전체이고 이전에 선택한 탭은 유지한다. 전체는 팩별 제목과 스티커 그리드를 모아 표시한다. PickerMediaButton의 NSImageView는 보이는 스티커·팩 대표 이미지에 대해서만 playback GIF→원본 GIF→정지 썸네일 순으로 로드하고 재생한다. 스크롤 밖/창 닫기 시 작업·재생을 중지한다. UIKit/SwiftUI 및 변환 라이브러리를 macOS 번들에 연결하지 않는다.

팩 페이지는 정지 화면 교체 대신 현재/이웃의 실제 PickerPageView를 viewport 안에서 이동한다. 고정된 PickerSwipeHandler가 손가락 이동량을 추적하고 임계치/취소 여부에 따라 0.24초 ease-out으로 전환 또는 복귀한다. 모멘텀은 추가 팩 전환을 일으키지 않으며 탭 클릭도 같은 방향 슬라이드를 사용한다. 시스템 동작 줄이기에서는 즉시 전환한다. 창 크기 변경 시 진행 중 전환을 취소하고 선택된 페이지를 유지한다. 기존 창 프레임 저장·Dock/메뉴 막대 정책·복사 성공 시 닫기·라이브러리 저장 경로·타깃/리소스 구성은 유지한다.


2026-10-17 Catalyst 모달 배경 합성 보정: `UI/AppGlassAppearance.swift`의 appModalBackground는 Mac Catalyst에서만 시스템 배경색을 명시적인 불투명 presentationBackground로 지정한다. 가져오기·최적화·받은 링크·팩 공유의 NavigationStack에 적용하여 모달의 반투명 바탕과 내부 재질이 겹치는 경로를 줄인다. iOS 모달·홈 화면·버튼 스타일은 유지한다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로 변경은 없다. 실제 사용자 환경의 글래스 깨짐 해소는 미검증이다.

전체/최근/이미지 탭·GIF·페이지 모션 완료 범위: 최종 Catalyst Release 및 iPhone Debug 빌드 성공. 맥 기존 설치에 최종 앱을 덮어쓰기 설치·실행하고 deep/strict 서명과 macOS 번들 로드를 확인했다. 연결된 iPhone 15 Pro도 기존 데이터를 유지해 설치·실행했다. 자동 테스트·수동 UI/애니메이션 테스트는 실행하지 않았다.

모달 배경 보정 빌드·설치: Catalyst arm64 Debug와 연결된 iPhone Debug 빌드 성공. 맥 앱 및 iPhone 15 Pro에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 자동 테스트·수동 UI 검증은 실행하지 않았다.

2026-10-17 맥 팝업 밀도·리사이즈·연속 전환: `MacDesktop/DesktopPlugin.swift`의 PickerPageView는 행별 NSStackView/빈 칸 제약과 팩 전체 버튼 생성을 제거한다. PickerGridDocument가 최대 약 72pt 셀·4pt 셀 간격·8pt 팩 간격·22pt 제목 영역의 좌표를 계산하고 마지막 행을 왼쪽부터 배치한다. 현재 보이는 영역과 앞뒤 한 행의 버튼/제목만 생성하고 최대 24개 재사용 버튼을 보관한다. 너비 변경 시 팩별 행 수·위치만 계산하고 화면 셀의 frame을 갱신하며, 셀 이미지도 Auto Layout 대신 고정 inset frame을 사용한다. live resize 동안 GIF 재생·신규 이미지 로딩을 보류하고 끝나면 재개한다. 이미지 파일/복사/라이브러리 경로는 유지한다.

새 스와이프·팩 선택 입력은 진행 중 settlement를 완료 처리하고 이전 completion token을 무효화하여 즉시 다음 동작을 받는다. 기존의 settling 입력 차단 및 0.35초 swipe 지연을 제거하고 중복 이벤트만 짧게 걸러낸다. 스와이프 이동·복귀 모션, 동작 줄이기, 창 프레임 저장, 팩 이미지 탭과 GIF는 유지한다. 파일·타깃·리소스 경계 변경은 없다. 기존 전체 그리드/행별 스택 설명보다 이 항목을 우선한다.

팝업 밀도·성능 후속 완료 범위: 최종 Catalyst Release 및 연결된 iPhone Debug 빌드 성공. 맥 앱과 iPhone 15 Pro에 기존 데이터를 유지해 덮어쓰기 설치·실행했다. 맥 설치 번들의 deep/strict 서명 검증을 완료했다. 자동 테스트·수동 UI/성능 테스트는 실행하지 않았으므로 실제 체감 리사이즈·스와이프 개선은 미검증이다.


2026-10-17 맥 제목·단축키 설정: MacWindowConfiguration은 Catalyst 창 제목을 숨기고 DesktopPlugin은 복사 팝업 상단 앱 이름을 제거한다. DesktopPlugin의 AppKit 단축키 기록 필드와 Carbon 등록이 사용자 조합을 받으며 등록 가능한 조합만 mac.shortcutKeyCode/mac.shortcutModifiers/mac.shortcutLabel에 저장한다. DesktopBridge와 MacDesktopCoordinator의 MacDesktopSettings로 기록 창을 연결하며 메뉴·팝업도 저장된 단축키를 표시한다. 기본값은 ⌥⇧S, 실패·취소 시 이전 설정을 유지한다. 기존 타깃·리소스·라이브러리 경계는 유지한다.

맥 제목·단축키 설정 완료 범위: Catalyst arm64 Release와 연결된 iPhone Debug 빌드 성공. 기존 맥 앱과 iPhone 15 Pro에 데이터 유지 덮어쓰기 설치·실행했으며 맥 앱 deep/strict 서명을 확인했다. 자동·수동 테스트는 실행하지 않았다.

2026-10-17 맥 팝업 공통 배열 확대·축소: `MacDesktop/DesktopPlugin.swift`의 PickerPanel은 ⌘+/⌘= 및 ⌘−(숫자패드 포함)를 팝업 내부에서 처리하고 PickerContentView는 트랙패드 magnify와 헤더 확대·축소 버튼을 같은 공통 설정에 연결한다. PickerModel의 셀 목표 크기(36~144pt, 기본 72pt)를 `mac.pickerCellSize.v1` 맥 UserDefaults에 저장하며 전체·최근·모든 팩과 다음 팝업 열기에 동일하게 적용한다. 키보드/버튼은 1.15배 단계, 핀치는 연속 배율로 조절한다. 핀치 종료·창 닫기 때 저장하며 취소 제스처는 시작 크기로 복구한다. PickerPageView는 열 수가 바뀔 때만 geometry를 재계산하고 기존 첫 가시 스티커 위치를 보정한다. 핀치 중 GIF/새 로딩 보류 및 셀 재사용 정책을 유지한다. 셀 간격은 4→2pt, 이미지 inset은 3→1pt, 팩 간격은 8→6pt, 제목 영역은 22→20pt로 줄였다. 기존 창 프레임/단축키 설정/스와이프/복사 경로 및 타깃·리소스 경계는 유지한다.

팝업 공통 배열 확대·축소 완료 범위: 최종 Catalyst Release와 실제 iPhone Debug 빌드 성공. 기존 맥 앱과 연결된 iPhone 15 Pro에 데이터 유지 덮어쓰기 설치·실행하고 맥 deep/strict 서명 검증을 완료했다. 자동 테스트·핀치/키 입력 수동 UI 테스트는 실행하지 않았다.


2026-10-17 맥 팝업 상단 영역 제거: DesktopPlugin의 단축키 안내·설정·확대/축소 버튼이 있던 헤더와 제약을 제거하고 팩 탭부터 배치한다. 기존 배경 드래그·핀치·⌘+/⌘−는 유지한다. PickerPanel은 팝업 내부 ⌘,를 처리해 기존 showManagement 경로로 앱 설정 탭을 열고, StickerMacCommands에도 동일한 설정 메뉴 단축키를 연결한다. 기존 파일 내부 변경이며 타깃·리소스·저장 경로 변경은 없다.

팝업 상단 영역 제거 완료 범위: Catalyst Release 및 연결된 iPhone Debug 빌드 성공. 맥과 iPhone 15 Pro에 기존 데이터 유지 덮어쓰기 설치·실행했고 맥 deep/strict 서명 검증을 완료했다. 자동·수동 테스트는 실행하지 않았다.

2026-10-17 플랫폼별 첫 실행 안내: Features/Onboarding/OnboardingView.swift는 팩 추가·복사·붙여넣기의 세 단계와 플랫폼별 사용법을 안내한다. iPad는 나란히 열린 채팅 앱, Catalyst는 실제 설정된 복사 단축키·메뉴 막대를 안내한다. iOS 키보드 설정은 선택형 접기 영역으로 제공하고 전체 접근 확인을 시작 조건으로 요구하지 않는다. 기존 hasCompletedOnboarding을 유지한다. DesktopPlugin은 메뉴 표시 기본값 true를 등록하고 기존 최초 로그인 실행 등록을 유지하며 사용자의 저장된 설정을 덮어쓰지 않는다. 파일·타깃·리소스·라이브러리 저장 경로 변경은 없다.

플랫폼별 첫 실행 안내 완료 범위: iOS Debug 및 Catalyst arm64 Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 기존 맥 앱에 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 자동·수동 테스트는 실행하지 않았다.


2026-10-17 맥 팩 목록 클릭 충돌 보정: `Features/Library/LibraryView.swift`는 Catalyst 일반 모드에서 List의 선택 바인딩을 nil로 분리하여 네이티브 행 선택과 팩 열기 Button의 클릭 경합을 줄인다. 편집 모드에서만 기존 다중 선택을 연결하며 iOS 선택 동작은 유지한다. 파일·책임·타깃·리소스·저장 경로 변경은 없다. Catalyst Release와 iPhone Debug 빌드 성공. 자동·수동 테스트는 실행하지 않았다. 실제 클릭 증상 해소는 사용자 확인이 필요하다.

2026-10-17 맥 편집 다중 선택·상세 키보드 확대/축소: LibraryView는 Catalyst에서 네이티브 List 선택 대신 행 Button이 bulkSelected의 해당 팩만 토글하고 체크 표시를 제공한다. 일반 클릭의 단일 선택 교체를 피하며 iOS 기본 선택은 유지한다. StickerMacCommands의 별도 scene focused value로 InstalledPackView의 열 수를 ⌘+/⌘=(확대), ⌘−(축소)로 2~10열 범위에서 한 열씩 조절한다. 기존 gridZoom 핀치 제스처는 변경하지 않았다. 컴파일러 타입 추론 한도를 피하도록 용량 계산의 경로 집합 생성을 명시적 반복문으로 풀었다. 기존 파일·타깃·리소스·저장 경계는 유지한다.

다중 선택·키보드 확대/축소 빌드: Catalyst Release 및 실제 iPhone Debug 빌드 성공. 맥 앱 데이터 유지 덮어쓰기 설치·실행 및 deep/strict 서명 확인 완료. 상세 SwiftUI 구성과 용량 비동기 계산을 기존 파일 내 private 속성·함수로 분리하여 컴파일러 추론 한도를 해결했다. 자동·수동 테스트는 실행하지 않았다.


2026-10-17 맥 GIF 파일 붙여넣기 호환: Shared/Clipboard/StickerCopyService는 Catalyst GIF 쓰기를 앱 시작 시 주입한 throwing writer에 위임한다. MacDesktopCoordinator와 DesktopBridge가 AppKit DesktopPlugin의 writeGIFToPasteboard로 연결하며 팝업·앱 상세가 같은 경로를 사용한다. DesktopPlugin은 Caches/StickerBridgeClipboard/Sticker-<UUID>.gif에 원본 데이터를 원자적으로 내보내고 하나의 NSPasteboardItem에 public.file-url·기존 NSFilenamesPboardType 파일 목록·com.compuserve.gif를 함께 게시한다. 팝업 닫기·앱 종료 후에도 파일을 유지하고 이후 GIF 복사 성공 시 7일 지난 내보내기만 정리한다. 쓰기 실패는 복사 실패로 반환한다. iOS·키보드는 기존 GIF 데이터 복사를 유지한다. 기존 파일 내부 책임 확장으로 파일·타깃·리소스·설치 라이브러리 경로 변경은 없다.

맥 GIF 붙여넣기 수정 빌드·설치: Catalyst arm64 Release 및 연결된 iPhone Debug 빌드 성공. 기존 맥 앱과 iPhone 15 Pro에 데이터 유지 덮어쓰기 설치·실행했고 맥 deep/strict 서명 확인을 완료했다. 자동·수동 테스트는 실행하지 않았으며 카카오톡 실제 붙여넣기 결과는 미검증이다.


2026-10-17 첫 실행 안내 정리: `Features/Onboarding/OnboardingView.swift`는 iPhone·iPad 키보드 사용 설명과 설정 버튼을 항상 표시한다. 접기 상태·화살표를 제거하고 iOS·Catalyst의 상단 기기 아이콘 및 시작하기 하단 영역의 재질 배경을 제거했다. 기존 파일·타깃·리소스·저장 경로는 유지한다. 앞선 선택형 접기 영역 설명을 대체한다.

첫 실행 안내 정리 빌드·설치: iOS Debug와 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 기존 맥 앱에 데이터를 유지해 덮어쓰기 설치·실행했다. 맥 deep/strict 서명을 확인했으며 테스트·수동 UI 검증은 실행하지 않았다.


2026-10-17 iCloud 설정 안내 정리: `Core/Sync/LibrarySyncService.swift`는 CloudKit 미설정 상태에서 개발자 팀 안내 문구 대신 빈 상태를 제공하며, `Features/Settings/SyncSettingsView.swift`는 비어 있는 상태를 표시하지 않는다. 기존 설정 동작과 동기화 데이터 경로는 유지한다. 두 기존 앱 파일 수정이며 타깃·리소스 변경은 없다.

iCloud 설정 안내 정리 빌드·설치: iOS Debug와 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2 및 기존 맥 앱에 덮어쓰기 설치·실행했다. 맥 deep/strict 서명을 확인했다. 테스트는 실행하지 않았다.

2026-10-18 키보드·맥 팝업 스크롤 복원: KeyboardState가 확장 전용 UserDefaults의 keyboard.scroll.v1.*에 탭별 세로 위치를 저장하고 KeyboardViewController/KeyboardPaging이 닫기·팩 전환 시 저장 및 레이아웃 후 복원을 수행한다. MacDesktop/DesktopPlugin의 PickerPageView는 탭별 mac.pickerScroll.v1.* 맥 기본 설정에 위치를 저장하고 새 페이지의 유효한 레이아웃에서 범위를 보정해 복원한다. iPad StickerGridLayout은 약 88pt 이상 정사각형 셀과 2pt 간격을 사용해 기존 작은 열 너비·늘어난 행 높이를 대체한다. GIF 표시는 iPhone과 동일한 StickerCell 내부 오버레이를 유지한다. 기존 파일 내부 책임 변경이며 타깃·리소스·설치 라이브러리 경로 변경은 없다. 테스트는 실행하지 않는다.

스크롤 복원·iPad 배열 조정 빌드·설치: iOS Debug 및 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 기존 맥 앱에 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 자동·수동 테스트는 실행하지 않았다.

2026-10-18 재표시 깜빡임·열기 비용 조정: 키보드는 초기 cache generation 수신만으로 프로세스 이미지 캐시를 지우지 않고 실제 세대 변경 때만 비운다. 목록 맨 앞 28개 사전 디코딩을 제거하고 저장 위치 복원 후 실제 가시 셀의 누락 포스터만 첫 표시 전에 채운다. MacDesktopCoordinator는 게시 index의 revision/cacheGeneration이 같으면 경로 검증을 마친 스냅샷을 재사용한다. DesktopPlugin은 동일 스냅샷에서 패널·그리드·셀 이미지를 유지하고 숨김 중 애니메이션만 보류한다. 최근 목록은 내용이 바뀐 경우만 재구성한다. PickerMediaButton은 숨김 시 이미지를 비우지 않으며 셀 재사용 때 작은 PNG 포스터를 즉시 제공한 뒤 GIF를 비동기 로드한다. 포스터 캐시는 8MB 한도로 유지한다. 기존 파일 내부 책임 변경으로 파일·타깃·리소스·설치 라이브러리 경로는 유지한다. 테스트는 실행하지 않는다.

재표시 비용 조정 빌드·설치: 최종 iOS Debug 및 Catalyst arm64 Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 기존 맥 앱에 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 자동·수동 테스트 및 성능 측정은 실행하지 않았으며 실제 호스트에서의 깜빡임 해소·속도 변화는 미검증이다.

2026-10-18 팩 스와이프 모션: KeyboardPaging은 손가락 이동을 직접 추적하고 놓는 속도로 0.18초 앞 위치를 예측해 전환/복귀를 결정한다. 남은 이동 거리로 정규화한 속도를 UIKit spring(mass 1/stiffness 300/damping 34)에 전달한다. DesktopPlugin의 PickerSwipeHandler는 트랙패드 이벤트의 시간·이동량으로 release velocity를 계산하고 동일한 예측 기준 및 AppKit 페이지 레이어의 CASpringAnimation에 전달한다. 두 페이지에 동일한 이동량·스프링을 적용하며 끝 탭은 비선형 저항으로 복귀한다. 동작 줄이기는 즉시 전환하고 기존 모멘텀 중복 전환 차단·가시 셀 재사용·스크롤 복원·타깃 경계를 유지한다. 새 파일·리소스·저장 경로 변경은 없다. 테스트는 실행하지 않는다.

속도 연동 스와이프 빌드·설치: 최종 iOS Debug 및 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 맥 기존 설치에 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 자동·수동 테스트는 실행하지 않았으며 실제 스와이프 감각은 미검증이다.

2026-10-18 iOS 키보드 스와이프 깜빡임 보정: KeyboardPaging은 전환 완료 시 미리보기 UICollectionView 자체를 현재 페이지로 승격하고 두 그리드의 역할을 교환한다. 동일 팩을 다른 그리드에 reloadData해 GIF·셀을 재생성하던 완료 경로를 제거했다. 역할 교환 시 접근성·상호작용·빈 목록 배경·스크롤 표시를 함께 이전하며 양쪽 pan gesture에 동일한 팩 스와이프 우선순위를 적용한다. 목적 페이지는 화면 밖에서 저장된 스크롤 위치와 가시 포스터를 준비한 뒤 노출한다. KeyboardLibraryLoading의 가시 포스터 준비를 임의 그리드에도 적용하도록 분리했다. 기존 파일 내부 책임 변경으로 파일·타깃·리소스·라이브러리 저장 경로는 유지한다. 속도 연동 스프링 모션은 유지하며 테스트는 실행하지 않는다.

iOS 스와이프 깜빡임 보정 빌드·설치: iOS Debug 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2에 기존 데이터를 유지해 덮어쓰기 설치·실행 완료. 자동·수동 테스트는 실행하지 않았으며 실제 스와이프 깜빡임 해소는 미검증이다.

2026-10-18 키보드 스와이프 시작 지연 보정: KeyboardPaging.preparePage에서 목적 화면의 모든 누락 PNG를 메인 스레드에서 동기 디코딩하던 prepareGridPosters 호출을 제거했다. 셀 구성은 메모리 캐시를 즉시 사용하고 누락 이미지는 기존 직렬 비동기 StickerThumbnailDecoder로 처리한다. reload 직후 레이아웃의 콘텐츠 크기만 계산하고 저장 Y를 설정한 뒤 한 번 레이아웃해 팩 맨 앞 셀을 먼저 생성·취소하던 작업도 줄였다. 깜빡임 보정의 실제 페이지 승격·GIF 유지와 속도 연동 스프링은 유지한다. 기존 파일 내부 변경으로 타깃·리소스·저장 경로 변경은 없다. 테스트는 실행하지 않는다.

스와이프 시작 지연 보정 빌드·설치: 최종 iOS Debug 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 테스트·성능 측정은 실행하지 않았으며 실제 반응속도는 미검증이다.

2026-10-18 맥 빠른 스크롤·연속 팩 이동: DesktopPlugin의 PickerMediaLoader는 PNG 디코딩과 GIF 파일 읽기를 각각 직렬 actor에서 수행한다. PickerMediaButton의 셀 구성 중 동기 파일 읽기를 제거하고 8MB 포스터 캐시를 유지한다. PickerPageView는 세로 스크롤 중 GIF 로딩·재생을 보류하고 마지막 입력 140ms 후 재개하며 스크롤 위치 설정 쓰기도 정지 시 한 번 게시한다(닫기·페이지 제거 시에도 저장). PickerContentView는 가로 누적 이동에서 완전히 지난 페이지 너비를 차감하며 실제 incoming 페이지를 현재로 승격하여 동일한 트랙패드·가로 휠 제스처로 여러 팩을 통과한다. 마지막 잔여 이동과 release velocity로 기존 스프링 전환/복귀를 수행한다. 손을 뗀 후 모멘텀의 추가 팩 전환 방지는 유지한다. 파일·타깃·리소스·라이브러리 저장 경로 변경은 없다. 테스트는 실행하지 않는다.

맥 스크롤·연속 팩 이동 빌드·설치: Catalyst Release 및 iOS Debug 빌드 성공. 맥과 연결된 iPhone 15 Pro·iPad Pro 12.9 M2에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 자동·수동 테스트 및 성능 측정은 실행하지 않았다.

2026-10-18 키보드·맥 팩 탭 Liquid Glass: KeyboardViewController의 상단 팩 탭·관리·다음 키보드 줄을 interactive UIGlassEffect(.regular)의 UIVisualEffectView로 감싼다. MacDesktop/DesktopPlugin의 팩 탭 스크롤 영역은 interactive NSGlassEffectView(.regular)로 감싼다. 양쪽 18pt 모서리·소폭 가로 inset을 사용하며 기존 탭 높이·그리드·제스처·페이지 재사용을 유지한다. 기존 파일 내부 UI 구성 변경으로 파일·타깃·리소스·저장 경로는 변경하지 않는다. 테스트는 실행하지 않는다.

팩 탭 Liquid Glass 빌드·설치: iOS Debug와 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2 및 맥에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 자동·수동 테스트는 실행하지 않았다.

2026-10-18 팩 헤더 글래스 의도 보정: 앞선 둥근 interactive 탭 배경을 제거했다. KeyboardViewController는 그리드와 분리된 세로 스택 대신 전체 높이 그리드 위에 사각 UIGlassEffect(.regular) 헤더를 겹친다. 헤더 높이에 맞춘 contentInset으로 초기 콘텐츠를 아래에 두고 스크롤된 스티커는 헤더 뒤로 지나간다. 스크롤 저장·복원은 inset을 제외한 논리 위치를 유지한다. DesktopPlugin도 전체 높이 viewport 위에 전체 폭·모서리 0의 NSGlassEffectView를 겹치고 페이지의 56pt 상단 inset을 저장 위치에 보정한다. 기존 파일 내부 UI 구성 변경으로 파일·타깃·리소스·라이브러리 저장 경로는 유지한다. 앞선 둥근 팩 탭 Liquid Glass 설명을 대체한다.

사각 글래스 헤더 보정 빌드·설치: iOS Debug 및 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 맥에 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 자동·수동 테스트는 실행하지 않았다.

2026-10-18 팩 상단 글래스 전체 원복: 사용자의 원복 요청에 따라 둥근 탭 글래스와 사각 겹침 헤더를 모두 제거했다. KeyboardViewController는 기존 topBar/그리드 세로 스택과 0 상단 contentInset으로, DesktopPlugin은 기존 tabScroll/viewport/message 스택 및 16pt 외곽 여백으로 복원했다. 헤더 inset 보정도 제거했다. 글래스 적용 전의 스크롤 복원·팩 스와이프 모션·페이지 재사용·맥 연속 팩 이동·스크롤 성능 수정은 유지한다. 기존 맥 팝업 창 자체의 글래스는 유지한다. 파일·타깃·리소스·저장 경로 변경은 없다.

상단 글래스 원복 빌드·설치: iOS Debug 및 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 맥에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 테스트는 실행하지 않았다.

2026-10-18 대각선 팩 스와이프 판정: KeyboardPaging의 가로 시작 기준을 |vx| > 2×|vy|에서 |vx| > 0.85×|vy|로, DesktopPlugin의 트랙패드/가로 휠 축 선택 기준을 |dx| > 1.2×|dy|에서 |dx| > 0.85×|dy|로 완화했다. 약한 대각선 및 45도 이동도 가로 팩 이동으로 처리하며 세로 성분이 충분히 큰 입력은 기존 세로 스크롤로 유지한다. 스프링·페이지 재사용·연속 팩 이동·저장 위치·타깃 경계는 유지한다. 기존 두 파일 내부 판정 변경이며 테스트는 실행하지 않는다.

대각선 판정 조정 빌드·설치: iOS Debug 및 Catalyst Release 빌드 성공. 연결된 iPhone 15 Pro·iPad Pro 12.9 M2와 맥에 기존 데이터 유지 덮어쓰기 설치·실행 완료. 맥 deep/strict 서명 확인 완료. 테스트는 실행하지 않았다.


2026-10-18 이전 화면 상태 잔류 방지: LibraryView는 설치 팩 상세의 SwiftUI identity를 pack.id로 구분하여 팩 전환 시 공유 시트·삭제 확인·확대 상태 등 이전 팩의 로컬 상태가 새 팩에 이어지지 않게 한다. InstalledPackView의 부분적인 pack.id 변경 초기화는 제거한다. LibraryModel.refresh는 요청 세대와 취소 여부를 확인한 뒤 결과·오류를 게시하여 늦게 끝난 과거 목록이 최신 결과를 덮지 않게 한다. KeyboardState의 기존 snapshot 재사용 및 KeyboardLibraryLoading의 비동기 갱신 생략 조건은 libraryRevision과 cacheGeneration을 함께 비교한다. 갱신된 키보드 목록을 적용한 뒤 현재 탭의 저장 스크롤 위치를 다시 보정한다. 기존 파일 내부 변경이며 파일·타깃·리소스·설치 데이터 경로는 유지한다. 테스트는 실행하지 않는다.

이전 화면 상태 잔류 방지 빌드·설치: 앱·키보드 확장의 iOS Debug 실기기 빌드 성공. 연결된 iPhone 15 Pro에 기존 데이터를 유지해 덮어쓰기 설치·실행 완료. 테스트·수동 UI 검증은 실행하지 않았으며 사용자가 관찰한 간헐적 구형 UI 노출의 실제 재현·해소 여부는 미검증이다.


2026-10-18 배포 서명 보정 완료: Catalyst Release arm64/x86_64 정상 서명 빌드 성공. 기존 팀 RKQCX265PQ·App Group entitlement·embedded.provisionprofile 및 deep/strict 서명 확인. 이전 .build/MacDistribution의 앱·ZIP과 ~/Applications/StickerBridge.app을 정상 개발 서명 빌드로 교체하고 설치 앱 실행 완료. 기존 라이브러리 데이터·경로는 수정하지 않았다. 앱 소스 변경이 없어 iOS 재빌드·재설치는 하지 않았다. 테스트·수동 UI 확인은 실행하지 않았으며 임의 Mac 배포용 Developer ID 내보내기는 인증서 부재로 미수행이다.

2026-10-18 스티커팩 업데이트 흐름: 앱 전용 Core/Library/PackUpdateService.swift는 메타데이터만으로 추가·삭제·변경·미설치 복구·이름·순서 차이를 계산하고 팩별 요청을 합친다. 사용자가 시작한 전체 조회는 화면 수명과 분리한 Task 및 기존 BackgroundWork의 updateCheck로 진행한다. Caches/PackUpdateChecks/<telegramName>.json의 원본 조회 결과를 재실행 시 현재 설치 revision과 다시 비교하며 앱 초기화에서 지운다. HTTP API·서버 제한·Shared 저장 형식은 변경하지 않는다.

Features/Library/PackUpdatesView.swift는 단일·선택·전체 변경 내역과 명시적 업데이트 실행을, UI/PackUpdateChangesView.swift는 가져오기 화면과 공통으로 쓰는 이전/이후 이미지 표시를 담당한다. 두 새 화면과 서비스는 TelegramSticker 파일 시스템 동기화 그룹을 통해 앱 타깃에만 포함되며 키보드에는 포함하지 않는다. 목록·상세의 당겨서 새로고침은 전체 Telegram 팩을 확인하고, 목록 상단에서 업데이트 개수·실행·내역을 제공한다. WorkNotifications의 packUpdates 목적지를 ContentView가 내 스티커 팩 목록과 변경 내역으로 연결한다. 업데이트가 있으면 전체 조회를 끝낼 때마다 알린다.

LibraryWriter의 LocalStickerInput은 앱 내부 ReusableStickerFiles로 기존 PNG·썸네일·GIF·키보드 재생 파일의 안전한 경로를 검증하고 새 revision에 그대로 복사한다. ImportCoordinator는 새로 적용한 파일의 스티커 ID를 ImportResult로 반환하고 메타데이터 변경에도 항목 이름을 갱신한다. 업데이트 일괄 적용은 사용자의 팩 정렬을 바꾸지 않는다. 최적화 제안은 이번에 받은 ID만 전달하며, StickerStorageOptimizer의 준비·적용에서도 대상 밖 파일과 품질을 재사용한다. 파일·변환 결과의 기존 App Group 게시 경로, revision 원자성 및 키보드 읽기 경계는 유지한다.

InstalledPackView의 핀치·Catalyst 단축키 열 수는 앱 전용 UserDefaults의 library.stickerGrid.columns.v1에 2~10 범위로 기기별·모든 팩 공통 저장한다. 저장 전 기본값은 compact 4/regular 5열이며 저장 후 회전·팩 전환·재실행으로 초기화하지 않는다. 리소스 추가·이동 및 번들 조회 경로 변경은 없다. 테스트와 수동 UI 검증은 실행하지 않는다.

업데이트 흐름 빌드·설치: 최종 iOS Debug 및 Catalyst arm64 Release 빌드 성공. 세 새 Swift 파일이 앱 타깃에서 컴파일됨을 확인했고 기존 키보드·리소스 타깃 경계를 유지했다. 연결된 iPhone 15 Pro에 기존 데이터를 유지해 최신 앱 덮어쓰기 설치 완료. 설치 직후 기기가 unavailable로 바뀌어 CoreDevice 오류 4016으로 실행은 연결 복구 대기 상태다. 자동 테스트·수동 UI 검증 및 실제 성능 측정은 실행하지 않았다.

2026-10-18 업데이트 선택 적용 후속: LibraryView의 목록 상단 업데이트 안내는 미적용 차이가 있는 팩이 한 개 이상일 때만 표시한다. 확인 중·업데이트 없음·완료 상태만으로 안내 섹션을 유지하지 않는다. PackUpdatesView는 업데이트가 남은 팩만 카드로 표시하며 조회 실패는 별도 접기 영역에 둔다. 팩 제목 오른쪽 업데이트는 해당 팩 전체 적용, 추가·삭제·변경 버튼은 해당 종류만 적용하며, 상단 파란 모두 업데이트는 표시 대상 팩 전체를 바로 적용한다. 재조회는 창의 당겨서 새로고침과 실패 항목 다시 확인으로 제공한다.

Core/Library의 PackUpdateScope(all/additions/deletions/changes)는 앱 내부 적용 범위를 정의한다. ImportModel은 선택 범위를 ImportCoordinator 및 재개용 BatchImportDraft.updateScope에 전달하며 이전 draft는 all로 읽는다. 추가만 적용하면 기존 스티커·팩 이름·기존 상대 순서를 유지하고 원본의 다음 기존 스티커 앞에 새 항목을 삽입한다. 삭제만 적용하면 원본에서 없어진 항목만 제거한다. 변경만 적용하면 공통 항목의 메타데이터·형식·순서와 팩 이름을 반영하고 미선택 추가·삭제는 보존한다. 실제 원본 조회 메타데이터는 전체 그대로 유지해 부분 적용 뒤 남은 차이와 알림 개수를 다시 계산한다. 미선택 실패 기록과 pending 상태를 유지하며, 키보드·HTTP API·설치 manifest 형식·리소스·타깃 경계 변경은 없다. 테스트 및 수동 UI 검증은 실행하지 않는다.

업데이트 선택 적용 빌드·설치 완료: 최종 iOS Debug 및 Catalyst arm64 Release 빌드 성공. 연결 복구된 iPhone 15 Pro에 기존 데이터 유지 덮어쓰기 설치 및 최신 앱 실행 완료. 앞선 실행 대기 상태는 해소됐다. 자동 테스트·수동 UI 검증은 실행하지 않았다.

2026-10-18 업데이트 종류별 적용 버튼 제거: PackUpdatesView의 추가·삭제·변경 개별 적용 버튼과 해당 화면의 범위 선택 전달을 제거했다. 팩 제목 오른쪽 업데이트와 상단 모두 업데이트, 종류별 변경 내역·미리보기는 유지한다. 이전 재개 작업을 위한 내부 범위 읽기는 유지하며 파일·타깃·리소스·저장 형식 변경은 없다. 테스트는 실행하지 않는다.

종류별 버튼 제거 빌드·설치: iOS Debug 및 Catalyst arm64 Release 빌드 성공. 연결된 iPhone 15 Pro에 데이터 유지 덮어쓰기 설치·실행 완료. 테스트·수동 UI 검증은 실행하지 않았다.

2026-10-18 업데이트 미리보기 GIF·요약 정리: UI/PackUpdateChangesView.swift는 팩 제목 아래 중복된 작은 추가·삭제·변경 개수 요약을 제거하고 종류별 섹션 제목·이미지는 유지한다. 설치된 이전/삭제 항목은 안전한 경로로 기존 playback GIF(없으면 원본 GIF)를 연결하고, 추가/변경 후 항목은 기존 GalleryPreviewStore 캐시·변환·재생을 재사용한다. 화면이 활성일 때 재생하고 동작 줄이기 설정은 존중한다. 메타데이터 전체 업데이트 확인에는 미디어 로딩을 추가하지 않으며 표시된 미리보기에서만 준비한다.

갤러리와 업데이트 두 기능에서 재사용하는 GalleryStickerPreview.swift를 Features/Gallery/에서 UI/로 이동했다. 이동은 원본 소스 변경 없이 수행했으며 앱 파일 시스템 동기화 그룹의 동일 타깃을 유지한다. GalleryPreviewStore의 설치 파일 재사용은 원본 형식이 일치할 때만 허용한다. 리소스·번들 조회·Shared·키보드·설치 라이브러리 저장 경로 변경은 없다. 사용자 지시에 따라 앞으로 Xcode 작업은 연결된 모든 지원 기기에 빌드·설치하며, 이번 작업은 iPhone·iPad·Mac 모두 설치 대상으로 한다. 테스트 및 수동 UI 검증은 실행하지 않는다.

GIF 미리보기·요약 정리 완료: iPhone 15 Pro와 iPad Pro 12.9 M2 각각의 실기기 목적지 Debug 빌드 및 Catalyst arm64 Release 빌드 성공. 두 실기기에 데이터 유지 덮어쓰기 설치·실행 완료. Mac은 기존 ~/Applications/StickerBridge.app을 정상 Xcode 서명 빌드로 교체하고 실행했으며 deep/strict 서명 확인을 완료했다. 이전 Mac 앱 번들은 .build/MacInstallBackup.*에 보관했고 App Group·사용자 데이터는 수정하지 않았다. 이동한 GalleryStickerPreview.swift가 앱 타깃에서 컴파일됨을 확인했다. 테스트 및 수동 UI 검증은 실행하지 않았다.
