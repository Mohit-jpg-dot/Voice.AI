#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# VoiceOS Reproducible Build Script
# Compiles native Swift source into VoiceOS.app with hardened runtime
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
LOGS_DIR="${BUILD_DIR}/logs"
RELEASE_CONFIG="${ROOT_DIR}/release/config.json"

mkdir -p "${BUILD_DIR}" "${LOGS_DIR}" "/tmp/clang_cache"
BUILD_LOG="${LOGS_DIR}/build.log"

exec > >(tee -a "${BUILD_LOG}") 2>&1

echo "================================================================="
echo "Building VoiceOS Native macOS Application"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "================================================================="

# 1. Read Release Configuration
APP_NAME=$(node -p "require('${RELEASE_CONFIG}').appName")
BUNDLE_ID=$(node -p "require('${RELEASE_CONFIG}').bundleIdentifier")
if [ -f "${ROOT_DIR}/VERSION" ]; then
  VERSION=$(cat "${ROOT_DIR}/VERSION" | tr -d '[:space:]')
else
  VERSION=$(node -p "require('${RELEASE_CONFIG}').version")
fi
BUILD_NUM=$(node -p "require('${RELEASE_CONFIG}').buildNumber")
MIN_MACOS=$(node -p "require('${RELEASE_CONFIG}').minMacOSVersion")
COPYRIGHT=$(node -p "require('${RELEASE_CONFIG}').copyright || 'Copyright © 2026 Voice.AI Team. All rights reserved.'")
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "release")

echo "App Name:         ${APP_NAME}"
echo "Bundle ID:        ${BUNDLE_ID}"
echo "Version:          ${VERSION} (Build ${BUILD_NUM})"
echo "Min macOS:        ${MIN_MACOS}"
echo "Git Commit:       ${COMMIT_HASH}"

# 2. Setup App Bundle Structure
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_BUNDLE}"
mkdir -p "${MACOS_DIR}" "${FRAMEWORKS_DIR}" "${RESOURCES_DIR}"

# 3. Compile VoiceOSCore Framework
echo "Compiling VoiceOSCore shared library..."
OBJ_DIR="${BUILD_DIR}/obj"
mkdir -p "${OBJ_DIR}"

swiftc \
  -target arm64-apple-macosx14.0 \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
  -module-cache-path /tmp/clang_cache \
  -Xlinker -install_name -Xlinker "@rpath/libVoiceOSCore.dylib" \
  -emit-module -emit-library -module-name VoiceOSCore \
  -o "${OBJ_DIR}/libVoiceOSCore.dylib" \
  "${ROOT_DIR}"/Sources/VoiceOSCore/*.swift "${ROOT_DIR}"/Sources/VoiceOSCore/*/*.swift

cp "${OBJ_DIR}/libVoiceOSCore.dylib" "${FRAMEWORKS_DIR}/libVoiceOSCore.dylib"

# 4. Compile VoiceOSApp Main Binary
echo "Compiling ${APP_NAME} binary..."
swiftc \
  -target arm64-apple-macosx14.0 \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk \
  -module-cache-path /tmp/clang_cache \
  -I "${OBJ_DIR}" -L "${FRAMEWORKS_DIR}" -lVoiceOSCore \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
  -o "${MACOS_DIR}/${APP_NAME}" \
  "${ROOT_DIR}"/Sources/VoiceOSApp/main.swift "${ROOT_DIR}"/Sources/VoiceOSApp/*/*.swift

# 5. Fix dylib ID and rpath
install_name_tool -id "@rpath/libVoiceOSCore.dylib" "${FRAMEWORKS_DIR}/libVoiceOSCore.dylib"
install_name_tool -change "${OBJ_DIR}/libVoiceOSCore.dylib" "@rpath/libVoiceOSCore.dylib" "${MACOS_DIR}/${APP_NAME}" || true
install_name_tool -change "${FRAMEWORKS_DIR}/libVoiceOSCore.dylib" "@rpath/libVoiceOSCore.dylib" "${MACOS_DIR}/${APP_NAME}" || true

# 6. Generate Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT}</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Voice.AI needs microphone access to dictate and process voice commands.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Voice.AI needs screen capture access to analyze circled on-screen context.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Voice.AI automates applications via Apple Events and native shortcuts.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Voice.AI uses local Whisper models to transcribe speech on device.</string>
    <key>NSContactsUsageDescription</key>
    <string>Voice.AI accesses contacts locally to resolve names when sending emails or messages upon your command.</string>
    <key>NSCameraUsageDescription</key>
    <string>Voice.AI uses the camera only if you explicitly turn on hand gesture controls in Settings.</string>
    <key>SUFeedURL</key>
    <string>https://voice.ai/appcast.xml</string>
    <key>VoiceAIGitCommit</key>
    <string>${COMMIT_HASH}</string>
</dict>
</plist>
EOF

# 7. Install Application Icon
echo "Installing Application Icon (AppIcon.icns)..."
if [ -f "${ROOT_DIR}/release/AppIcon.icns" ]; then
  cp "${ROOT_DIR}/release/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
elif [ -f "${ROOT_DIR}/AppIcon.icns" ]; then
  cp "${ROOT_DIR}/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 8. Generate Entitlements.plist
cat <<EOF > "${BUILD_DIR}/Entitlements.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

# 8. Code Signing (Sign inner dylib first, then app bundle)
SIGNING_IDENTITY=$(node -p "require('${RELEASE_CONFIG}').signingIdentity || ''")

if [ -n "${SIGNING_IDENTITY}" ]; then
  echo "Signing with Developer ID: ${SIGNING_IDENTITY}..."
  codesign --force --timestamp --options runtime --sign "${SIGNING_IDENTITY}" "${FRAMEWORKS_DIR}/libVoiceOSCore.dylib"
  codesign --force --timestamp --options runtime --entitlements "${BUILD_DIR}/Entitlements.plist" --sign "${SIGNING_IDENTITY}" "${APP_BUNDLE}"
else
  echo "No Developer ID configured in release/config.json. Ad-hoc signing with disabled library validation..."
  codesign --force --sign - "${FRAMEWORKS_DIR}/libVoiceOSCore.dylib"
  codesign --force --options runtime --entitlements "${BUILD_DIR}/Entitlements.plist" --sign - "${APP_BUNDLE}"
fi

# 9. Verify Signature
echo "Verifying app bundle signature..."
codesign --verify --deep --strict "${APP_BUNDLE}"
echo "✓ Signature verified successfully"

echo "================================================================="
echo "Build complete: ${APP_BUNDLE}"
echo "================================================================="
