#!/bin/sh

IDENTITY="TeX Live Utility Signing Certificate"
IDENTITY="Developer ID Application: Adam Maxwell (966Z24PX4J)"

TLU_BUNDLE_PATH="$1"

# see https://mjtsai.com/blog/2021/02/18/code-signing-when-building-on-apple-silicon/
CODESIGN_FLAGS="--verbose --timestamp --force --digest-algorithm=sha1,sha256 --options runtime"

LOCATION=${TLU_BUNDLE_PATH}/Contents/Frameworks

codesign $CODESIGN_FLAGS --sign "$IDENTITY" \
    "$LOCATION/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/fileop"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" \
    "$LOCATION/Sparkle.framework/Versions/A/Resources/Autoupdate.app/Contents/MacOS/Autoupdate"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Sparkle.framework/Versions/A"

codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/FileView.framework/Versions/A"

pushd .
cd "$LOCATION"
find Python.framework/Versions/3.9/lib/ -type f -perm -u=x -exec codesign $CODESIGN_FLAGS --sign "$IDENTITY" {} \;
find Python.framework/Versions/3.9/bin/ -type f -perm -u=x -exec codesign $CODESIGN_FLAGS --sign "$IDENTITY" {} \;
find Python.framework/Versions/3.9/lib/ -type f -name "*dylib" -exec codesign $CODESIGN_FLAGS --sign "$IDENTITY" {} \;
find Python.framework/Versions/3.9/lib/ -type f -name "*.a" -exec codesign $CODESIGN_FLAGS --sign "$IDENTITY" {} \;
find Python.framework/Versions/3.9/lib/ -type f -name "*.o" -exec codesign $CODESIGN_FLAGS --sign "$IDENTITY" {} \;
popd
    
codesign --entitlements python_entitlements.plist $CODESIGN_FLAGS --deep --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/Resources/Python.app"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/python3.9"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/2to3-3.9"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/idle3.9"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pip"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pip3"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pip3.9"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/pydoc3.9"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/python3.9"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/python3.9-config"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/xattr"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/Python.framework/Versions/3.9/bin/wheel"
codesign $CODESIGN_FLAGS --deep --entitlements python_entitlements.plist --sign "$IDENTITY" "$LOCATION/Python.framework"

LOCATION="${TLU_BUNDLE_PATH}"/Contents/MacOS
codesign $CODESIGN_FLAGS --sign "$IDENTITY" --entitlements TLUNotifier/TLUNotifier/TLUNotifier.entitlements "$LOCATION/TLUNotifier.app"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/tlu_ipctask"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/texliveupdatecheck"
# Scripts are now in Resources, because the assholes at Apple changed bundle layout requirements somewhere along the way
# and notarization is failing when Dick Koch includes it in the MacTeX package. Although I'm not sure this is
# the real problem as notarization is bitching about the Python framework, and this may cause a notarization failure
# when I try and notarize. Hooray for trying random shit until finding something that works, since this security
# theater is a fragile house of cards.
#codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/python_version.py"
#codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/uninstall_local_agent.sh"
#codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/parse_tlpdb.py"
#codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/agent_installer.py"
#codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$LOCATION/texdist_change_default.sh"

codesign $CODESIGN_FLAGS --sign "$IDENTITY" "${TLU_BUNDLE_PATH}/Contents/Library/QuickLook/DVI.qlgenerator"
codesign $CODESIGN_FLAGS --sign "$IDENTITY" "${TLU_BUNDLE_PATH}/Contents/Library/Spotlight/DVIImporter.mdimporter"

codesign $CODESIGN_FLAGS --sign "$IDENTITY" "$TLU_BUNDLE_PATH"

