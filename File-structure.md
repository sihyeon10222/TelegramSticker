# 파일 구조와 작업 가이드

기준일: 2026-10-15. 아래 구조는 실제 코드에 적용된 현재 구조다.
파일 추가·이동·삭제 또는 책임·타깃 변경 시 같은 작업에서 이 문서를 갱신한다.

## 클라이언트와 백엔드 경계

| 영역 | 위치 | 책임 |
| --- | --- | --- |
| iOS 클라이언트 | `TelegramSticker/` | 화면, Worker 요청, 다운로드 조율, 로컬 변환·설치·최적화 |
| 키보드 확장 | `StickerKeyboard/` | 오프라인 목록 표시, 팩 전환, 스티커 복사 |
| iOS 공통 코드 | `Shared/` | 제품 모델, 라이브러리 읽기, 이미지 처리, 복사, 선택·순서·최근 사용 |
| 샘플 | `StickerSamples/` | 자체 제작 샘플 정의·PNG 리소스 |
| 네이티브 디코더 | `Packages/StickerVP9/` | 메인 앱 전용 VP9 디코딩 |
| 서버 백엔드 | `backend/worker/` | Telegram API 연동, 서버 인증·캐시·요청 제한, 카탈로그, 파일 중계 |

클라이언트 통신은 `TelegramSticker/Networking/`, 서버 서비스는 `backend/worker/src/services/`에 둔다.
`WorkerClient`는 클라이언트의 HTTP 어댑터다. Telegram Bot Token과 Telegram API 연동은 백엔드에서 관리한다.
`Shared/`는 iOS 앱·키보드 공통 코드이며 서버 공통 소스 영역이 아니다.
앱과 백엔드는 HTTP API로 연결하고 설정·의존성·빌드 경계를 유지한다.

## 현재 구조

외부 libvpx, 에셋 내부, 테스트·검증 문서의 세부 목록은 접어서 표시한다.

```text
TelegramSticker/
├── AGENTS.md
├── File-structure.md
├── README.md
├── TelegramSticker.xcodeproj/
├── Configuration/
│   ├── App-Info.plist
│   ├── StickerKeyboard.entitlements
│   └── TelegramSticker.entitlements
├── TelegramSticker/
│   ├── App/
│   │   ├── ContentView.swift
│   │   └── TelegramStickerApp.swift
│   ├── Background/
│   │   ├── BackgroundWork.swift
│   │   └── WorkNotifications.swift
│   ├── Components/
│   │   ├── AnimationPreview.swift
│   │   ├── CurrentWorkBanner.swift
│   │   └── KeyboardPermissionReminder.swift
│   ├── Concurrency/
│   │   └── RequestGate.swift
│   ├── Conversion/
│   │   ├── AnimationQuality.swift
│   │   ├── KeyboardPlaybackBuilder.swift
│   │   ├── StaticImageConverter.swift
│   │   ├── TGSConverter.swift
│   │   └── WebMConverter.swift
│   ├── DebugSupport/
│   │   └── ImportPreviewFixture.swift
│   ├── Diagnostics/
│   │   └── DownloadDiagnostics.swift
│   ├── Features/
│   │   ├── Gallery/
│   │   │   ├── GalleryCatalogStore.swift
│   │   │   ├── GalleryMetadataStore.swift
│   │   │   ├── GalleryPreviewStore.swift
│   │   │   ├── GalleryStickerPreview.swift
│   │   │   └── GalleryView.swift
│   │   ├── Import/
│   │   │   ├── Components/
│   │   │   │   ├── PackLinkReorderDropDelegate.swift
│   │   │   │   └── RemoteStickerPreview.swift
│   │   │   ├── ImportInput.swift
│   │   │   ├── ImportModel.swift
│   │   │   └── ImportView.swift
│   │   ├── Library/
│   │   │   ├── InstalledPackView.swift
│   │   │   ├── LibraryModel.swift
│   │   │   ├── LibraryView.swift
│   │   │   └── PackImportRequest.swift
│   │   ├── Onboarding/
│   │   │   └── OnboardingView.swift
│   │   ├── Optimization/
│   │   │   ├── OptimizationCenter.swift
│   │   │   ├── OptimizationRequest.swift
│   │   │   ├── OptimizationSession.swift
│   │   │   └── OptimizationView.swift
│   │   └── Settings/
│   │       ├── AppResetButton.swift
│   │       ├── DownloadLogsView.swift
│   │       ├── KeyboardAccessMonitor.swift
│   │       ├── KeyboardSettingsButton.swift
│   │       ├── KeyboardSetupAction.swift
│   │       ├── SettingsView.swift
│   │       └── StorageSettingsView.swift
│   ├── Importing/
│   │   ├── ImportActivity.swift
│   │   ├── ImportCoordinator.swift
│   │   ├── ImportFailure.swift
│   │   ├── ImportFailureStore.swift
│   │   ├── ImportJobCache.swift
│   │   ├── ImportProgress.swift
│   │   └── StickerImportError.swift
│   ├── Networking/
│   │   ├── DownloadRequestBudget.swift
│   │   ├── ImportSettings.swift
│   │   ├── RemoteGallery.swift
│   │   ├── RemotePack.swift
│   │   ├── WorkerClient.swift
│   │   └── WorkerConfiguration.swift
│   ├── Resources/
│   │   ├── AnimationSamples/
│   │   ├── Assets.xcassets/
│   │   ├── PrivacyInfo.xcprivacy
│   │   └── ThirdPartyNotices.txt
│   ├── Sharing/
│   │   ├── PNGShareSheet.swift
│   │   ├── PackLinkSharing.swift
│   │   └── StickerLink.swift
│   └── Storage/
│       ├── AppDisposableCache.swift
│       ├── LibraryWriter.swift
│       └── StickerStorageOptimizer.swift
├── StickerKeyboard/
│   ├── Clipboard/
│   │   └── KeyboardCopying.swift
│   ├── Navigation/
│   │   ├── KeyboardPackReordering.swift
│   │   ├── KeyboardPaging.swift
│   │   ├── PackDragScrollProxy.swift
│   │   └── PackDragSession.swift
│   ├── Presentation/
│   │   ├── KeyboardCollection.swift
│   │   ├── KeyboardLibrary.swift
│   │   └── KeyboardStatus.swift
│   ├── Resources/
│   │   ├── Info.plist
│   │   └── PrivacyInfo.xcprivacy
│   ├── Views/
│   │   ├── PackTabButton.swift
│   │   ├── PackTabScrollView.swift
│   │   └── StickerCell.swift
│   └── KeyboardViewController.swift
├── Shared/
│   ├── Clipboard/
│   │   └── StickerCopyService.swift
│   ├── Imaging/
│   │   ├── GIFPlaybackView.swift
│   │   ├── GIFValidation.swift
│   │   ├── PNGValidation.swift
│   │   ├── StickerImages.swift
│   │   └── StickerThumbnailDecoder.swift
│   ├── Keyboard/
│   │   ├── KeyboardAccessReceipt.swift
│   │   └── StickerGridLayout.swift
│   ├── Models/
│   │   ├── LibraryModels.swift
│   │   └── Sticker.swift
│   └── Storage/
│       ├── KeyboardPackOrderStore.swift
│       ├── KeyboardSelectionStore.swift
│       ├── LibraryReader.swift
│       └── RecentStickerStore.swift
├── StickerSamples/
│   ├── Resources/
│   └── SampleStickers.swift
├── Packages/
│   └── StickerVP9/
│       ├── .swiftpm/
│       │   └── xcode/
│       │       └── xcuserdata/
│       │           └── sihyeon.xcuserdatad/
│       │               └── xcschemes/
│       │                   └── xcschememanagement.plist
│       ├── Sources/
│       │   └── CStickerVP9/
│       │       ├── include/
│       │       │   └── StickerVP9.h
│       │       ├── vendor/
│       │       └── StickerVP9.c
│       ├── Package.swift
│       └── README.md
├── TelegramStickerTests/
├── TelegramStickerUITests/
├── Scripts/
│   ├── GenerateAnimatedFixtures.py
│   └── GenerateSampleStickers.swift
├── backend/
│   └── worker/
│       ├── src/
│       │   ├── auth/
│       │   │   └── session.ts
│       │   ├── cache/
│       │   │   └── worker-cache.ts
│       │   ├── http/
│       │   │   └── response.ts
│       │   ├── routes/
│       │   │   ├── gallery.ts
│       │   │   ├── handler.ts
│       │   │   └── packs.ts
│       │   ├── services/
│       │   │   ├── assets.ts
│       │   │   ├── digest.ts
│       │   │   ├── packs.ts
│       │   │   └── telegram.ts
│       │   ├── validation/
│       │   │   ├── content-type.ts
│       │   │   ├── limits.ts
│       │   │   └── response.ts
│       │   ├── index.ts
│       │   └── types.ts
│       ├── test/
│       │   ├── runtime.test.mjs
│       │   └── worker.test.mjs
│       ├── README.md
│       ├── package.json
│       ├── pnpm-lock.yaml
│       ├── pnpm-workspace.yaml
│       ├── tsconfig.json
│       └── wrangler.jsonc
└── docs/
```

## 작업별 시작 파일

| 작업 | 현재 진입 파일 |
| --- | --- |
| 앱 진입·탭 | `TelegramSticker/App/TelegramStickerApp.swift`, `TelegramSticker/App/ContentView.swift` |
| 팩 목록·상세 | `TelegramSticker/Features/Library/LibraryModel.swift`, `TelegramSticker/Features/Library/LibraryView.swift`, `TelegramSticker/Features/Library/InstalledPackView.swift` |
| 가져오기 화면·작업 상태 | `TelegramSticker/Features/Import/ImportView.swift`, `TelegramSticker/Features/Import/ImportModel.swift`, `TelegramSticker/Importing/ImportActivity.swift` |
| 단일·일괄 가져오기·재개 | `TelegramSticker/Importing/ImportCoordinator.swift`, `TelegramSticker/Importing/ImportJobCache.swift` |
| 클라이언트 HTTP·세션·요청 제어 | `TelegramSticker/Networking/WorkerClient.swift`, `TelegramSticker/Networking/DownloadRequestBudget.swift`, `TelegramSticker/Concurrency/RequestGate.swift` |
| 연결 설정·API DTO | `TelegramSticker/Networking/ImportSettings.swift`, `TelegramSticker/Networking/WorkerConfiguration.swift`, `TelegramSticker/Networking/RemotePack.swift`, `TelegramSticker/Networking/RemoteGallery.swift` |
| TGS·WebM·정적 이미지 변환 | `TelegramSticker/Conversion/TGSConverter.swift`, `TelegramSticker/Conversion/WebMConverter.swift`, `TelegramSticker/Conversion/StaticImageConverter.swift` |
| 설치·저장 안정성 | `TelegramSticker/Storage/LibraryWriter.swift`, `Shared/Storage/LibraryReader.swift`, `Shared/Models/LibraryModels.swift` |
| 용량 최적화 | `TelegramSticker/Features/Optimization/OptimizationSession.swift`, `TelegramSticker/Features/Optimization/OptimizationView.swift`, `TelegramSticker/Storage/StickerStorageOptimizer.swift` |
| 캐시·초기화 | `TelegramSticker/Features/Settings/StorageSettingsView.swift`, `TelegramSticker/Features/Settings/AppResetButton.swift`, `TelegramSticker/Storage/AppDisposableCache.swift` |
| 갤러리 | `TelegramSticker/Features/Gallery/GalleryView.swift`, `TelegramSticker/Features/Gallery/GalleryCatalogStore.swift`, `TelegramSticker/Features/Gallery/GalleryPreviewStore.swift` |
| 온보딩·접근 관찰 | `TelegramSticker/Features/Onboarding/OnboardingView.swift`, `TelegramSticker/Features/Settings/KeyboardAccessMonitor.swift`, `Shared/Keyboard/KeyboardAccessReceipt.swift` |
| 백그라운드 진행·알림 | `TelegramSticker/Background/BackgroundWork.swift`, `TelegramSticker/Background/WorkNotifications.swift`, `TelegramSticker/Components/CurrentWorkBanner.swift` |
| 실패·진단 로그 | `TelegramSticker/Importing/ImportFailure.swift`, `TelegramSticker/Importing/ImportFailureStore.swift`, `TelegramSticker/Diagnostics/DownloadDiagnostics.swift`, `TelegramSticker/Features/Settings/DownloadLogsView.swift` |
| 링크·이미지 공유 | `TelegramSticker/Sharing/PackLinkSharing.swift`, `TelegramSticker/Sharing/StickerLink.swift`, `TelegramSticker/Sharing/PNGShareSheet.swift` |
| 키보드 수명 주기·초기 구성 | `StickerKeyboard/KeyboardViewController.swift` |
| 키보드 목록·복원·셀 표시 | `StickerKeyboard/Presentation/KeyboardLibrary.swift`, `StickerKeyboard/Presentation/KeyboardCollection.swift`, `StickerKeyboard/Presentation/KeyboardStatus.swift` |
| 키보드 페이징·팩 드래그 | `StickerKeyboard/Navigation/KeyboardPaging.swift`, `StickerKeyboard/Navigation/KeyboardPackReordering.swift` |
| 키보드 셀·탭·복사 | `StickerKeyboard/Views/StickerCell.swift`, `StickerKeyboard/Views/PackTabButton.swift`, `StickerKeyboard/Clipboard/KeyboardCopying.swift`, `Shared/Clipboard/StickerCopyService.swift` |
| 제품 스티커 모델·이미지 캐시 | `Shared/Models/Sticker.swift`, `Shared/Imaging/StickerImages.swift`, `Shared/Imaging/StickerThumbnailDecoder.swift` |
| GIF 재생·키보드 레이아웃 | `Shared/Imaging/GIFPlaybackView.swift`, `Shared/Keyboard/StickerGridLayout.swift`, `TelegramSticker/Conversion/KeyboardPlaybackBuilder.swift` |
| 선택·순서·최근 사용 | `Shared/Storage/KeyboardSelectionStore.swift`, `Shared/Storage/KeyboardPackOrderStore.swift`, `Shared/Storage/RecentStickerStore.swift` |
| 서버 진입·라우팅 | `backend/worker/src/index.ts`, `backend/worker/src/routes/handler.ts`, `backend/worker/src/routes/packs.ts`, `backend/worker/src/routes/gallery.ts` |
| 서버 Telegram 연동·팩 처리 | `backend/worker/src/services/telegram.ts`, `backend/worker/src/services/packs.ts`, `backend/worker/src/services/assets.ts` |
| 서버 인증·캐시·검증 | `backend/worker/src/auth/session.ts`, `backend/worker/src/cache/worker-cache.ts`, `backend/worker/src/validation/limits.ts`, `backend/worker/src/validation/response.ts`, `backend/worker/src/validation/content-type.ts` |
| 타깃·서명·패키지 | `TelegramSticker.xcodeproj/project.pbxproj`, `Configuration/App-Info.plist`, `Packages/StickerVP9/Package.swift`, `backend/worker/wrangler.jsonc` |

## 책임별 코드 배치

- `Features/`: 기능별 SwiftUI 화면과 화면 모델. 큰 화면의 모델·세부 화면·보조 뷰는 같은 기능 아래에서 분리한다.
- `Networking/`: 클라이언트 HTTP·세션·API DTO·요청 속도 예산. 서버 서비스 구현을 넣지 않는다.
- `Importing/`: 다운로드·변환·설치 조율, 재개용 작업 파일, 실패 상태. 범용 캐시 정리는 `Storage/`에 둔다.
- `Conversion/`: 메인 앱의 로컬 변환기. `Concurrency/RequestGate.swift`는 다운로드와 변환이 사용하는 앱 내부 동시성 도구다.
- `Storage/`: 설치 데이터 쓰기·최적화·정리. 공유 읽기·영속 모델은 `Shared/Storage/`, `Shared/Models/`에 둔다.
- `Background/`, `Diagnostics/`, `Sharing/`, `Components/`: 각 기능에서 재사용하는 앱 내부 코드.
- `DebugSupport/`: DEBUG fixture 코드. UI 테스트 전용 실행 인수로만 사용한다.
- 키보드의 `Presentation/`, `Navigation/`, `Clipboard/`는 동일 타깃의 `KeyboardViewController` 확장이다. 저장 상태는 컨트롤러가 소유하고 해당 파일들이 내부 접근 수준으로 공유한다.
- `Sticker`와 `StickerImages`는 제품 코드다. 샘플 배열 `Sticker.all`은 `StickerSamples/SampleStickers.swift`의 별도 확장에 둔다.
- 서버 `routes/`는 요청·응답 조율, `services/`는 Telegram 연동·팩 처리·스트리밍, `auth/`는 인증, `cache/`는 캐시, `validation/`은 입력·응답 검증을 담당한다.

## 타깃과 리소스 규칙

- 메인 앱은 `TelegramSticker/`, `Shared/`, `StickerSamples/`를 포함하고 Lottie·StickerVP9에 의존한다.
- 키보드는 `StickerKeyboard/`, `Shared/`, `StickerSamples/`를 포함한다. 네트워크·가져오기·TGS/WebM 변환·Lottie·StickerVP9를 연결하지 않는다.
- Xcode 파일 시스템 동기화 그룹을 유지한다. 하위 폴더의 Swift 파일도 기존 타깃에 포함된다.
- 키보드 plist는 `StickerKeyboard/Resources/Info.plist`다. 두 빌드 구성의 `INFOPLIST_FILE`과 동기화 그룹 리소스 제외 경로를 함께 유지한다.
- 앱 에셋·애니메이션 샘플·고지·privacy manifest는 `TelegramSticker/Resources/`에 둔다. 키보드 privacy manifest는 `StickerKeyboard/Resources/`에 둔다.
- 리소스 이동 시 번들 조회 이름을 보존한다. 자체 제작 샘플 PNG는 두 타깃에 계속 번들된다.
- `Packages/StickerVP9/Sources/CStickerVP9/vendor/`는 외부 소스와 생성 헤더다. 패키지 README의 갱신 절차를 따르고 일반 구조 정리에서 수정하지 않는다.
- API 변경 시 클라이언트 DTO·오류 처리와 Worker 응답을 함께 확인한다. 서버 내부 파일 ID와 Bot Token을 클라이언트로 노출하지 않는다.
- Worker의 `.ts` 모듈은 명시적 확장자로 import한다. 타입 전용 의존성에는 `import type`을 사용한다. 런타임 검사는 전체 모듈 그래프를 Miniflare에 제공하도록 구성되어 있다.

## 실행 중 데이터 위치


소스 폴더와 기기의 실행 중 저장소는 별개다. 파일 구조 정리로 기존 사용자 데이터 경로를 바꾸지 않는다.

```text
App Group: group.com.sihyeon.TelegramSticker
└── StickerLibrary/
    ├── index.json
    ├── packs/<pack-id>/<revision>/
    │   ├── manifest.json
    │   ├── <sticker-id>-original.png
    │   ├── <sticker-id>-thumb.png
    │   ├── <sticker-id>-animation.gif  # 애니메이션 항목만
    │   └── <sticker-id>-playback.gif   # 작은 키보드 재생 파일
    └── staging/<revision>/

메인 앱 전용 저장소
├── Application Support/ImportJobs/   # 초안·재개용 작업 파일
├── Application Support/ImportFailures/
├── Application Support/Gallery/catalog-v1.json
├── Application Support/download-log.json
├── Caches/GalleryPreviews/v1/
└── tmp/StickerOptimization-<UUID>/   # 원본·최적화 비교용 임시 라이브러리

키보드 확장 전용 저장소
├── Application Support/Keyboard/selection-v1.json
└── UserDefaults                     # 최근 사용·팩 순서·선택 fallback
```

설치 팩 게시·변경은 메인 앱의 `LibraryWriter`가 담당한다.
완성된 revision을 준비한 뒤 인덱스를 원자적으로 게시하고, 실패 시 기존 revision을 보존한다.
키보드는 설치 팩을 읽고 자체 선택·순서·최근 사용을 저장한다.
전체 접근 관찰 기록은 별도로 App Group에 기록하며, 현재 권한의 실시간 조회 결과로 해석하지 않는다.

## 구조 변경 시 확인

1. 이동·추출한 선언의 호출부와 접근 수준을 확인한다. 역할 분리만으로 저장 형식·사용자 동작을 바꾸지 않는다.
2. 타깃 포함 관계·리소스 조회·네트워크 경계를 확인한다.
3. 앱 변경 후 빌드·연결된 iPhone 덮어쓰기 설치·실행 정책은 [AGENTS.md](AGENTS.md)를 따른다.
4. 테스트는 사용자가 명시적으로 요청할 때만 실행한다. 코드 이동으로 필요한 테스트 import·타입 참조는 함께 갱신한다.
5. 기존 `docs/`의 검증 결과는 당시 기록이다. 현재 코드의 동작·성능 증거로 대체하지 않는다.

이번 정리는 폴더·파일 책임 분리다. 로그 저장 빈도, 파일 조회 비용, 변환 성능, 이전 UI와 맞지 않는 테스트 시나리오의 개선은 별도 동작 변경으로 다룬다.

## 작업별 진단 기록

`Diagnostics/DownloadDiagnostics.swift`는 Task-local 작업 ID로 동시 팩 다운로드의 상세 로그를 같은 일괄 작업에 연결한다. 다운로드·업데이트·복원·최적화·팩 미리보기는 각각 별도 작업이며, 갤러리와 기타 서비스 오류는 별도 진단 묶음이다. 기존 `Application Support/download-log.json` 경로를 유지하고 이전 배열 형식은 이전 버전 로그로 읽는다. 최근 완료 작업 40개, 작업당 최근 3,000줄을 보관하며 연속 기록의 디스크 저장은 500ms로 합친다. `Features/Settings/DownloadLogsView.swift`는 작업 선택·복사와 팩/오류 필터를 담당한다. 메인 앱 타깃만 사용하며 키보드에는 연결하지 않는다.
