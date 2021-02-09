#!/bin/sh

IDENTITY="TeX Live Utility Signing Certificate"
IDENTITY="Developer ID Application: Adam Maxwell (966Z24PX4J)"

TLU_BUNDLE_PATH="$1"

LOCATION=${TLU_BUNDLE_PATH}/Contents/Frameworks
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" \
    "$LOCATION/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" \
    "$LOCATION/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/Autoupdate"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/Sparkle.framework/Versions/A"

codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/FileView.framework/Versions/A"

LOCATION="${TLU_BUNDLE_PATH}"/Contents/MacOS
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" --entitlements TLUNotifier/TLUNotifier/TLUNotifier.entitlements "$LOCATION/TLUNotifier.app"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/python_version.py"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/uninstall_local_agent.sh"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/parse_tlpdb.py"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/agent_installer.py"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/texdist_change_default.sh"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$LOCATION/tlu_ipctask"

codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "${TLU_BUNDLE_PATH}/Contents/Library/QuickLook/DVI.qlgenerator"
codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "${TLU_BUNDLE_PATH}/Contents/Library/Spotlight/DVIImporter.mdimporter"

codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$TLU_BUNDLE_PATH"

