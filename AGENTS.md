# Device preferences

- Use the existing iPhone 18 Pro Max simulator for iPhone UI verification.
- When the user requests installation on their iPhone, use the connected physical iPhone. Install the updated app over the existing installation to preserve its data.

# Build preferences

- After app changes, automatically build for the connected physical iPhone, install over the existing app to preserve data, and launch it. A Simulator build alone does not fulfill this workflow. If no iPhone is connected, build for Simulator and report that device installation is pending.

- Automatically build the app after making app changes and fix build errors before finishing.
- Do not run tests unless the user explicitly asks for them.

# Project structure

- Before working, read [File-structure.md](File-structure.md) at the repository root to identify current file locations, responsibilities, and target boundaries.
- Follow the current responsibility-based layout documented there. Keep file moves and behavior changes distinct, and preserve target and runtime storage boundaries.
- Keep iOS client code and server backend code separate. Client HTTP requests belong to the app's networking code; Telegram API integration, server authentication, server caching, and server services belong under `backend/worker/`.
- `Shared/` is shared by the iOS app and keyboard, not by the client and backend. Do not link networking, import orchestration, TGS/WebM conversion, Lottie, or StickerVP9 into the keyboard extension.
- Publish installed library changes through the main app's `LibraryWriter`. Preserve existing user data paths, revision publication, and path validation when reorganizing source files.
- When adding, moving, or deleting files or changing their responsibilities or target membership, update `File-structure.md` in the same task and verify Xcode target membership and resource lookup paths.
- Keep the build, device installation, and test policies above in effect.
