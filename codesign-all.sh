#!/bin/sh

IDENTITY="TeX Live Utility Signing Certificate"
IDENTITY="Developer ID Application: Adam Maxwell (966Z24PX4J)"

TLU_BUNDLE_PATH="$1"

LOCATION=${TLU_BUNDLE_PATH}/Contents/Frameworks
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

codesign --verbose --options runtime --timestamp --force --sign "$IDENTITY" "$TLU_BUNDLE_PATH"


# prandtl:Release amaxwell$ codesign --display --verbose=4 TeX\ Live\ Utility.app
# Executable=/private/tmp/TLU-amaxwell/Release/TeX Live Utility.app/Contents/MacOS/TeX Live Utility
# Identifier=com.googlecode.mactlmgr.tlu
# Format=app bundle with Mach-O universal (x86_64 arm64)
# CodeDirectory v=20500 size=8039 flags=0x10000(runtime) hashes=244+3 location=embedded
# VersionPlatform=1
# VersionMin=720896
# VersionSDK=721152
# Hash type=sha256 size=32
# CandidateCDHash sha256=0515ccfc77fdf0f11e6bef68d08aec15bf914415
# CandidateCDHashFull sha256=0515ccfc77fdf0f11e6bef68d08aec15bf914415a53f2b5ee5987e9d02ca1bd5
# Hash choices=sha256
# CMSDigest=0515ccfc77fdf0f11e6bef68d08aec15bf914415a53f2b5ee5987e9d02ca1bd5
# CMSDigestType=2
# Executable Segment base=0
# Executable Segment limit=425984
# Executable Segment flags=0x1
# Page size=4096
# CDHash=0515ccfc77fdf0f11e6bef68d08aec15bf914415
# Signature size=8974
# Authority=Developer ID Application: Adam Maxwell (966Z24PX4J)
# Authority=Developer ID Certification Authority
# Authority=Apple Root CA
# Timestamp=Feb 5, 2021 at 00:24:01
# Info.plist entries=36
# TeamIdentifier=966Z24PX4J
# Runtime Version=11.1.0
# Sealed Resources version=2 rules=13 files=187
# Internal requirements count=1 size=220
