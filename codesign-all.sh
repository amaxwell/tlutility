#!/bin/sh

IDENTITY="TeX Live Utility Signing Certificate"
IDENTITY="Developer ID Application: Adam Maxwell (966Z24PX4J)"

TLU_BUNDLE_PATH="$1"

# see https://mjtsai.com/blog/2021/02/18/code-signing-when-building-on-apple-silicon/
CODESIGN_FLAGS="--verbose --options runtime --timestamp --force --digest-algorithm=sha1,sha256"

LOCATION=${TLU_BUNDLE_PATH}/Contents/Frameworks

codesign $CODESIGN_FLAGS --sign "$IDENTITY" \
    "$LOCATION/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" \
    "$LOCATION/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/Autoupdate"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Sparkle.framework/Versions/A"

codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/FileView.framework/Versions/A"

codesign $CODESIGN_FLAGS --deep --sign "$IDENTITY" "$LOCATION/Python.framework"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/python3.9"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/2to3-3.9"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/idle3.9"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pip"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pip3"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pip3.9"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pydoc3.9"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/python3.9"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/python3.9-config"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/xattr"
# codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/wheel"


LOCATION="${TLU_BUNDLE_PATH}"/Contents/MacOS
codesign $CODESIGN_FLAGS --sign "$IDENTITY" --entitlements TLUNotifier/TLUNotifier/TLUNotifier.entitlements "$LOCATION/TLUNotifier.app"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/python_version.py"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/uninstall_local_agent.sh"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/parse_tlpdb.py"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/agent_installer.py"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/texdist_change_default.sh"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/tlu_ipctask"

codesign $CODESIGN_FLAGS --sign "$IDENTITY" "${TLU_BUNDLE_PATH}/Contents/Library/QuickLook/DVI.qlgenerator"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "${TLU_BUNDLE_PATH}/Contents/Library/Spotlight/DVIImporter.mdimporter"

codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$TLU_BUNDLE_PATH"

