#!/bin/bash
# Preserve Xcode signing and provisioning; never ad-hoc re-sign shared containers.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
MODE="${1:---developer-id}"
OUTPUT="${2:-$ROOT/.build/MacDistribution/$(date +%Y%m%d-%H%M%S)}"
case "$MODE" in
  --developer-id)
    if ! security find-identity -v -p codesigning | /usr/bin/grep -q 'Developer ID Application:'; then
      echo 'Developer ID Application certificate required. In Xcode use Product > Archive > Distribute App > Developer ID. For this development Mac only, use --development.' >&2
      exit 1
    fi
    ;;
  --development) ;;
  *) echo "Usage: bash $0 [--developer-id|--development] [new-output-directory]" >&2; exit 1 ;;
esac
if [[ -e "$OUTPUT" ]]; then
  echo "Choose a new output directory: $OUTPUT already exists." >&2
  exit 1
fi
mkdir -p "$OUTPUT"
OUTPUT="$(cd "$OUTPUT" && pwd)"
if [[ "$MODE" == --development ]]; then
  xcodebuild -project "$ROOT/TelegramSticker.xcodeproj" -scheme TelegramSticker \
    -configuration Release -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -derivedDataPath "$ROOT/.build/MacSigned" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates build
  ditto "$ROOT/.build/MacSigned/Build/Products/Release-maccatalyst/TelegramSticker.app" "$OUTPUT/StickerBridge.app"
  echo 'Development build: other Macs must be authorized by its provisioning profile; this is not unrestricted distribution.'
else
  xcodebuild -project "$ROOT/TelegramSticker.xcodeproj" -scheme TelegramSticker \
    -configuration Release -destination 'generic/platform=macOS,variant=Mac Catalyst' \
    -archivePath "$OUTPUT/StickerBridge.xcarchive" \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates archive
  cat > "$OUTPUT/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST
  xcodebuild -exportArchive -archivePath "$OUTPUT/StickerBridge.xcarchive" \
    -exportPath "$OUTPUT/Export" -exportOptionsPlist "$OUTPUT/ExportOptions.plist" \
    -allowProvisioningUpdates
  ditto "$OUTPUT/Export/TelegramSticker.app" "$OUTPUT/StickerBridge.app"
  echo 'Developer ID export complete. Submit for notarization before distribution (Xcode Organizer can upload and export the notarized app).'
fi
codesign --verify --deep --strict "$OUTPUT/StickerBridge.app"
ditto -c -k --sequesterRsrc --keepParent "$OUTPUT/StickerBridge.app" "$OUTPUT/StickerBridge-Mac.zip"
echo "App: $OUTPUT/StickerBridge.app"
echo "Archive: $OUTPUT/StickerBridge-Mac.zip"
