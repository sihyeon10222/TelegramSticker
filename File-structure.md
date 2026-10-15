# 파일 구조와 작업 가이드

기준일: 2026-10-15. 이 문서는 현재 저장소의 위치·책임·타깃 경계를 안내한다.
아래의 **현재 구조**는 실제 파일이고, **향후 정리안**은 아직 적용하지 않은 제안이다.
정리안을 근거로 파일이 이미 이동되었다고 가정하지 않는다.

## 클라이언트와 백엔드 경계

| 영역 | 현재 위치 | 책임 |
| --- | --- | --- |
| iOS 클라이언트 | `TelegramSticker/` | 화면, Worker 요청, 다운로드 조율, 로컬 변환·설치·최적화 |
| 키보드 확장 | `StickerKeyboard/` | 오프라인 목록 표시, 팩 전환, 스티커 복사 |
| iOS 공통 코드 | `Shared/`, `StickerSamples/` | 앱·키보드가 함께 사용하는 모델, 읽기, 이미지 처리, 복사 |
| 네이티브 디코더 | `Packages/StickerVP9/` | 메인 앱 전용 VP9 디코딩 |
| 서버 백엔드 | `backend/worker/` | Telegram API 연동, 인증, 갤러리 카탈로그, 캐시, 요청 제한, 파일 중계 |

클라이언트 내부 작업 코드와 서버 서비스 코드를 같은 `Services/` 폴더로 묶지 않는다.
`WorkerClient`는 클라이언트의 네트워크 어댑터이며 서버 구현이 아니다.
Telegram Bot Token과 Telegram API 호출은 백엔드에 둔다.
`Shared/`는 iOS 앱·키보드 공통 영역이며 클라이언트·서버 공통 소스 폴더가 아니다.
앱과 백엔드는 HTTP API로 연결하고, 각자의 설정·의존성·빌드 경계를 유지한다.

## 현재 구조

```text
TelegramSticker/
├── AGENTS.md                         # 작업 지침·빌드·기기·테스트 정책
├── File-structure.md                 # 이 문서
├── README.md                         # 프로젝트 소개·검증 문서 진입점
├── TelegramSticker.xcodeproj/        # 타깃·서명·패키지·공유 scheme
├── Configuration/
│   ├── App-Info.plist                # 백그라운드 작업·링크 파일 형식 선언
│   ├── TelegramSticker.entitlements
│   └── StickerKeyboard.entitlements
├── TelegramSticker/                  # 메인 앱
│   ├── TelegramStickerApp.swift
│   ├── ContentView.swift
│   ├── OnboardingView.swift
│   ├── LibraryView.swift
│   ├── LibraryWriter.swift
│   ├── GalleryView.swift
│   ├── GalleryCatalogStore.swift
│   ├── GalleryPreviewStore.swift
│   ├── GalleryStickerPreview.swift
│   ├── AnimationPreview.swift
│   ├── OptimizationView.swift
│   ├── StickerStorageOptimizer.swift
│   ├── KeyboardPlaybackBuilder.swift
│   ├── StorageSettingsView.swift
│   ├── BackgroundWork.swift
│   ├── PackLinkSharing.swift
│   ├── Import/
│   │   ├── ImportView.swift
│   │   ├── ImportCoordinator.swift
│   │   ├── ImportTypes.swift
│   │   ├── ImportSettings.swift
│   │   ├── WorkerClient.swift
│   │   ├── RequestGate.swift
│   │   ├── ImportJobCache.swift
│   │   ├── ImportFailure.swift
│   │   ├── AnimationQuality.swift
│   │   ├── StaticImageConverter.swift
│   │   ├── TGSConverter.swift
│   │   ├── WebMConverter.swift
│   │   └── ImportPreviewFixture.swift # DEBUG 전용 코드
│   ├── Assets.xcassets/
│   ├── AnimationSamples/
│   ├── PrivacyInfo.xcprivacy
│   └── ThirdPartyNotices.txt
├── StickerKeyboard/
│   ├── KeyboardViewController.swift
│   ├── Info.plist
│   └── PrivacyInfo.xcprivacy
├── Shared/
│   ├── StickerLibrary.swift          # 저장 모델·LibraryReader·접근 관찰 기록
│   ├── StickerThumbnailDecoder.swift
│   ├── GIFPlaybackView.swift         # 타임라인·디코더·뷰·재생 시계
│   ├── GIFValidation.swift
│   ├── PNGValidation.swift
│   ├── StickerGridLayout.swift
│   ├── KeyboardSelectionStore.swift
│   ├── KeyboardPackOrderStore.swift
│   └── RecentStickerStore.swift
├── StickerSamples/
│   ├── SampleSticker.swift           # 제품에서도 쓰는 모델·이미지 캐시 포함
│   ├── StickerCopyService.swift      # 제품에서도 쓰는 복사 서비스
│   └── Resources/                    # 자체 제작 샘플 PNG
├── Packages/StickerVP9/
│   ├── Package.swift
│   ├── README.md
│   └── Sources/CStickerVP9/
│       ├── StickerVP9.c              # 프로젝트 소유 C 래퍼
│       ├── include/StickerVP9.h
│       └── vendor/                   # libvpx 소스·생성 헤더·라이선스
├── TelegramStickerTests/             # 저장·변환·가져오기·레이아웃 등
│   └── Fixtures/                     # TGS·WebM·WebP 검증 입력
├── TelegramStickerUITests/           # 앱·실제 키보드·실기기 선택 검사
├── backend/                          # 서버 전용 경계
│   └── worker/
│       ├── src/index.ts              # 현재 서버 로직 진입점·구현
│       ├── test/
│       │   ├── worker.test.mjs
│       │   └── runtime.test.mjs
│       ├── package.json
│       ├── pnpm-lock.yaml
│       ├── pnpm-workspace.yaml
│       ├── tsconfig.json
│       ├── wrangler.jsonc
│       └── README.md
├── Scripts/
│   ├── GenerateSampleStickers.swift
│   └── GenerateAnimatedFixtures.py
└── docs/                             # 기능·검증 이력, Images/, branding/
```

## 작업별 시작 파일

| 작업 | 먼저 읽을 현재 파일 |
| --- | --- |
| 앱 진입·탭·진행 작업 다시 열기 | `TelegramSticker/TelegramStickerApp.swift`, `TelegramSticker/ContentView.swift` |
| 온보딩·키보드 접근 관찰 | `TelegramSticker/OnboardingView.swift`, `Shared/StickerLibrary.swift` |
| 설치 팩 목록·상세·공유 | `TelegramSticker/LibraryView.swift`, `TelegramSticker/PackLinkSharing.swift` |
| 단일·일괄 가져오기·재시도 | `TelegramSticker/Import/ImportView.swift`, `TelegramSticker/Import/ImportCoordinator.swift` |
| 클라이언트 통신·세션·요청 제어 | `TelegramSticker/Import/WorkerClient.swift`, `TelegramSticker/Import/RequestGate.swift`, `TelegramSticker/Import/ImportSettings.swift` |
| 원격·로컬 데이터 형식 | `TelegramSticker/Import/ImportTypes.swift`, `Shared/StickerLibrary.swift` |
| TGS·WebM·정적 이미지 변환 | `TelegramSticker/Import/TGSConverter.swift`, `TelegramSticker/Import/WebMConverter.swift`, `TelegramSticker/Import/StaticImageConverter.swift`, `TelegramSticker/Import/AnimationQuality.swift` |
| 설치·업데이트·저장 안전성 | `TelegramSticker/LibraryWriter.swift`, `Shared/StickerLibrary.swift` |
| 용량 최적화·재생용 GIF | `TelegramSticker/OptimizationView.swift`, `TelegramSticker/StickerStorageOptimizer.swift`, `TelegramSticker/KeyboardPlaybackBuilder.swift` |
| 캐시 정리·초기화 | `TelegramSticker/StorageSettingsView.swift`, `TelegramSticker/Import/ImportJobCache.swift` |
| 갤러리 목록·미리보기 | `TelegramSticker/GalleryView.swift`, `TelegramSticker/GalleryCatalogStore.swift`, `TelegramSticker/GalleryPreviewStore.swift`, `TelegramSticker/GalleryStickerPreview.swift` |
| 백그라운드 진행·완료 알림 | `TelegramSticker/BackgroundWork.swift` |
| 실패 원인·다운로드 로그 | `TelegramSticker/Import/ImportFailure.swift`, `TelegramSticker/Import/ImportView.swift` |
| 키보드 표시·팩 전환·드래그·복사 | `StickerKeyboard/KeyboardViewController.swift`, `Shared/StickerGridLayout.swift`, `StickerSamples/StickerCopyService.swift` |
| GIF 재생·썸네일 | `Shared/GIFPlaybackView.swift`, `Shared/StickerThumbnailDecoder.swift`, `StickerSamples/SampleSticker.swift`, `TelegramSticker/AnimationPreview.swift` |
| 선택·순서·최근 사용 복원 | `Shared/KeyboardSelectionStore.swift`, `Shared/KeyboardPackOrderStore.swift`, `Shared/RecentStickerStore.swift` |
| 서버 API·인증·Telegram 중계 | `backend/worker/src/index.ts`, `backend/worker/README.md`, `backend/worker/wrangler.jsonc` |
| 타깃 포함 관계·번들·패키지 | `TelegramSticker.xcodeproj/project.pbxproj`, `Packages/StickerVP9/Package.swift` |

## 타깃과 의존성 규칙

- 메인 앱은 `TelegramSticker/`, `Shared/`, `StickerSamples/`를 포함하고 Lottie·StickerVP9에 의존한다.
- 키보드는 `StickerKeyboard/`, `Shared/`, `StickerSamples/`를 포함한다. Lottie·StickerVP9·WorkerClient·변환 파이프라인을 연결하지 않는다.
- 단위 테스트와 UI 테스트는 각각 별도 Xcode 타깃이다. Worker 검사·의존성은 `backend/worker/`에서 관리한다.
- Xcode의 파일 시스템 동기화 그룹을 사용한다. 파일 이동 시 폴더뿐 아니라 타깃 포함 관계, plist 설정, 번들 리소스 조회도 확인한다.
- `StickerSamples/`의 두 Swift 파일은 현재 제품 코드다. 샘플 폴더 정리 시 테스트 전용으로 취급해 제거하지 않는다.
- `vendor/`는 외부 코드와 생성 헤더를 포함한다. 일반 앱 정리와 분리하고 패키지 README의 갱신 절차를 따른다. 테스트 실행은 루트 `AGENTS.md`의 사용자 요청 조건을 따른다.
- API 계약을 바꾸면 클라이언트 DTO·오류 처리와 Worker 응답을 함께 확인한다. 서버 내부 ID·Bot Token을 클라이언트로 노출하지 않는다.

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

## 향후 정리안 — 미적용

최상위 앱·키보드·백엔드 경계를 유지하고, 클라이언트 내부는 기능과 책임별로 정리한다.
폴더 이동과 동작·성능 변경을 구분해 진행한다.

```text
TelegramSticker/
├── App/
├── Features/
│   ├── Library/
│   ├── Import/
│   ├── Gallery/
│   ├── Optimization/
│   ├── Onboarding/
│   └── Settings/
├── Networking/                      # 클라이언트 Worker 요청·세션·요청 제어
├── Importing/                       # 다운로드 조율·재개
├── Conversion/                      # 로컬 TGS·WebM·이미지 변환
├── Storage/                         # 로컬 쓰기·용량 최적화
├── Background/
├── Diagnostics/
├── Sharing/
├── Components/
├── DebugSupport/
└── Resources/

StickerKeyboard/
├── KeyboardViewController.swift
├── Presentation/
├── Navigation/
├── Views/
└── Resources/

Shared/
├── Models/
├── Storage/
├── Imaging/
├── Clipboard/
└── Keyboard/

backend/worker/
├── src/
│   ├── index.ts
│   ├── routes/
│   ├── services/                    # 서버 내부 Telegram 연동·처리만
│   ├── auth/
│   ├── cache/
│   └── validation/
├── test/
└── 설정 파일·README                 # 기존 설정·lockfile 유지
```

| 현재 파일·구성 | 향후 배치·분리 방향 |
| --- | --- |
| `TelegramStickerApp.swift`, `ContentView.swift` | 앱 내부 `App/`; 설정 화면·공통 배너는 해당 기능·컴포넌트로 분리 |
| `LibraryView.swift` | `Features/Library/`; LibraryModel·팩 상세·공유 시트를 책임별로 분리 |
| `Import/ImportView.swift` | `Features/Import/`; ImportModel·작업 상태·미리보기·로그 화면 분리 |
| `GalleryView.swift`, 갤러리 Store·Preview 파일 | `Features/Gallery/`; 공통 통신·변환은 각 전용 영역 사용 |
| `OptimizationView.swift` | `Features/Optimization/`; 비교 세션·화면 분리 |
| `OnboardingView.swift`, `StorageSettingsView.swift` | 해당 Feature; 공통 접근 관찰·초기화 처리는 책임별 분리 |
| `Import/WorkerClient.swift`, `ImportSettings.swift` | `Networking/`; 클라이언트 연결 설정·세션 유지 |
| `Import/RequestGate.swift` | 요청 속도 예산은 `Networking/`; 범용 gate는 사용 범위를 확인해 앱 내부 공통 코드로 분리 |
| `Import/ImportCoordinator.swift`, `ImportJobCache.swift` | `Importing/`; 범용 캐시 정리·초기화는 `Storage/`로 분리 |
| `Import/ImportTypes.swift`, `ImportFailure.swift` | API DTO는 `Networking/`, 가져오기 상태는 `Importing/`, 로그는 `Diagnostics/` |
| 변환기·`AnimationQuality.swift`, `KeyboardPlaybackBuilder.swift` | 앱 내부 `Conversion/` |
| `LibraryWriter.swift`, `StickerStorageOptimizer.swift` | 앱 내부 `Storage/` |
| `BackgroundWork.swift`, `PackLinkSharing.swift`, `AnimationPreview.swift` | 각각 `Background/`, `Sharing/`, `Components/` |
| `Import/ImportPreviewFixture.swift` | `DebugSupport/`; DEBUG 조건 유지 |
| `StickerSamples/SampleSticker.swift` | 제품 모델은 `Shared/Models/`, 이미지 캐시는 `Shared/Imaging/`, 샘플 정의·이미지는 기존 샘플 영역에 유지 |
| `StickerSamples/StickerCopyService.swift` | `Shared/Clipboard/` |
| `Shared/StickerLibrary.swift` | 모델·Reader·키보드 접근 관찰을 각각 `Models/`, `Storage/`, `Keyboard/`로 분리 |
| 나머지 `Shared/` 파일 | 이미지 검증·재생·썸네일은 `Imaging/`, 선택·순서·최근 사용은 `Storage/`, 그리드는 `Keyboard/` |
| `KeyboardViewController.swift` | 컨트롤러 조율을 남기고 초기 표시·팩 전환·드래그·셀을 해당 확장 하위 폴더로 분리 |
| `backend/worker/src/index.ts` | 서버 진입점을 유지하며 라우트·서버 서비스·인증·캐시·검증 분리 |

## 문서 유지

- 파일 추가·이동·삭제 또는 책임·타깃·저장 경로 변경 시 이 문서를 같은 작업에서 갱신한다.
- 새 코드의 위치는 현재 구조와 변경 목적을 기준으로 정한다. 아직 없는 정리안 전체를 자동 적용하지 않는다.
- 기존 검증 문서는 당시 결과다. 현재 코드의 성공·성능 수치로 그대로 인용하지 않는다.
- 빌드·실기기 설치·테스트 실행 정책은 [AGENTS.md](AGENTS.md)를 따른다.
