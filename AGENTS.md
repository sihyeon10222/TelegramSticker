# Device preferences

- Use the existing iPhone 18 Pro Max simulator for iPhone UI verification.
- When the user requests installation on their iPhone, use the connected physical iPhone. Install the updated app over the existing installation to preserve its data.

# Build preferences

- After app changes, automatically build for the connected physical iPhone, install over the existing app to preserve data, and launch it. A Simulator build alone does not fulfill this workflow. If no iPhone is connected, build for Simulator and report that device installation is pending.

- Automatically build the app after making app changes and fix build errors before finishing.
- Do not run tests unless the user explicitly asks for them.

# Versioning preferences

- Every app or keyboard code, resource, or project-setting change must increase both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` before building and installing the updated app. Use the next patch version for routine changes (for example, `1.0.1` → `1.0.2`) and increment the build number by one. Do not decrease either value.
- Keep Debug/Release and all app, keyboard extension, and Mac desktop bundle versions identical. Version settings are inherited from the project-level build configurations in `TelegramSticker.xcodeproj/project.pbxproj`; do not add target-level overrides.
- Increment once for a completed change, not once per device/platform or repeated build of the same change. Documentation-only edits do not require a version increment.
- Settings must display `CFBundleShortVersionString` and `CFBundleVersion` from the installed app bundle, never a hard-coded version label.
- Version and build-number values must contain only digits and dots. Display the app version and build number as separate values in Settings.

# Project structure

- Before working, read [File-structure.md](File-structure.md) at the repository root to identify current file locations, responsibilities, and target boundaries.
- Follow the current responsibility-based layout documented there. Keep file moves and behavior changes distinct, and preserve target and runtime storage boundaries.
- Keep feature-local code together in `Features/`. Use `Core/` for app code reused across features, `UI/` for reusable views, and `Shared/` only for production code used by both the app and keyboard. Avoid empty layers and unnecessary packages.
- Keep iOS client code and server backend code separate. Client HTTP requests belong to the app's `Core/Networking/` code; Telegram API integration, server authentication, server caching, and server services belong under `backend/worker/`.
- Keep keyboard library, selection, history, and ordering state in `StickerKeyboard/State/KeyboardState.swift`. Views and interaction handlers must use its methods rather than mutate stored state directly. Keep UIKit lifecycle and animation tasks in the controller.
- `Shared/` is shared by the iOS app and keyboard, not by the client and backend. Do not link networking, import orchestration, TGS/WebM conversion, Lottie, or StickerVP9 into the keyboard extension.
- Publish installed library changes through the main app's `LibraryWriter`. Preserve existing user data paths, revision publication, and path validation when reorganizing source files.
- When adding, moving, or deleting files or changing their responsibilities or target membership, update `File-structure.md` in the same task and verify Xcode target membership and resource lookup paths.
- Keep the build, device installation, and test policies above in effect.
