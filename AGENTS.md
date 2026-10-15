# Device preferences

- Use the existing iPhone 18 Pro Max simulator for iPhone UI verification.
- When the user requests installation on their iPhone, use the connected physical iPhone. Install the updated app over the existing installation to preserve its data.

# Build preferences

- After app changes, automatically build for the connected physical iPhone, install over the existing app to preserve data, and launch it. A Simulator build alone does not fulfill this workflow. If no iPhone is connected, build for Simulator and report that device installation is pending.

- Automatically build the app after making app changes and fix build errors before finishing.
- Do not run tests unless the user explicitly asks for them.
