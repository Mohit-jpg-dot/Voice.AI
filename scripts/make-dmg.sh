#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# VoiceOS DMG Packaging Script
# Creates a Tahoe glass styled macOS DMG installer with drag-to-Applications layout
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
RELEASE_CONFIG="${ROOT_DIR}/release/config.json"
WEBSITE_DIR="${ROOT_DIR}/website"
WEBSITE_DOWNLOADS="${WEBSITE_DIR}/downloads"

echo "================================================================="
echo "Packaging VoiceOS macOS DMG"
echo "Timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "================================================================="

# 1. Read Release Configuration
APP_NAME=$(node -p "require('${RELEASE_CONFIG}').appName")
if [ -f "${ROOT_DIR}/VERSION" ]; then
  VERSION=$(cat "${ROOT_DIR}/VERSION" | tr -d '[:space:]')
else
  VERSION=$(node -p "require('${RELEASE_CONFIG}').version")
fi
BUILD_NUM=$(node -p "require('${RELEASE_CONFIG}').buildNumber")
MIN_MACOS=$(node -p "require('${RELEASE_CONFIG}').minMacOSVersion")
DMG_NAME="Voice.AI-${VERSION}.dmg"
INSTALLER_DMG_NAME=$(node -p "require('${RELEASE_CONFIG}').installerDmgName")
SIGNING_IDENTITY=$(node -p "require('${RELEASE_CONFIG}').signingIdentity || ''")

APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
if [ ! -d "${APP_BUNDLE}" ]; then
  echo "Error: App bundle not found at ${APP_BUNDLE}. Run scripts/build-app.sh first."
  exit 1
fi

# Ensure output directories exist
mkdir -p "${BUILD_DIR}" "${WEBSITE_DOWNLOADS}"

DMG_OUTPUT="${BUILD_DIR}/${DMG_NAME}"
DMG_STAGING="${BUILD_DIR}/dmg_staging"

rm -rf "${DMG_STAGING}" "${DMG_OUTPUT}"
mkdir -p "${DMG_STAGING}/.background"

# 2. Populate DMG Staging Directory
echo "Populating DMG staging directory..."
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

# Generate and install background image
python3 "${SCRIPT_DIR}/generate-dmg-assets.py" "${DMG_STAGING}/.background/background.png"

# Install Volume Icon
if [ -f "${ROOT_DIR}/release/AppIcon.icns" ]; then
  cp "${ROOT_DIR}/release/AppIcon.icns" "${DMG_STAGING}/.VolumeIcon.icns"
fi

# 3. Create DMG using hdiutil
echo "Creating compressed UDZO disk image..."
hdiutil create \
  -volname "${APP_NAME}" \
  -srcfolder "${DMG_STAGING}" \
  -ov \
  -format UDZO \
  "${DMG_OUTPUT}"

# 4. Copy to website downloads directory
echo "Copying DMG to website downloads folder..."
cp "${DMG_OUTPUT}" "${WEBSITE_DOWNLOADS}/${DMG_NAME}"

# 5. Calculate SHA-256 Checksums
echo "Calculating SHA-256 checksums..."
SHA256_HASH=$(shasum -a 256 "${DMG_OUTPUT}" | awk '{print $1}')
echo "${SHA256_HASH}  ${DMG_NAME}" > "${BUILD_DIR}/${DMG_NAME}.sha256"
echo "${SHA256_HASH}  ${DMG_NAME}" > "${WEBSITE_DOWNLOADS}/${DMG_NAME}.sha256"

FILE_SIZE_BYTES=$(stat -f%z "${DMG_OUTPUT}")
RELEASE_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo "DMG File:   ${DMG_OUTPUT}"
echo "File Size:  ${FILE_SIZE_BYTES} bytes"
echo "SHA-256:    ${SHA256_HASH}"

# 6. Optional DMG Signing
IS_SIGNED=false
IS_NOTARIZED=false
STATUS_LABEL="Unsigned development build, not notarized"

if [ -n "${SIGNING_IDENTITY}" ]; then
  echo "Signing DMG with Developer ID: ${SIGNING_IDENTITY}..."
  if codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_OUTPUT}"; then
    IS_SIGNED=true
    STATUS_LABEL="Signed Developer ID build"
  fi
fi

# 7. Generate release metadata (release/latest.json & website/latest.json)
echo "Generating release metadata..."
cat <<EOF > "${ROOT_DIR}/release/latest.json"
{
  "appName": "${APP_NAME}",
  "version": "${VERSION}",
  "buildNumber": "${BUILD_NUM}",
  "releaseDate": "${RELEASE_DATE}",
  "fileName": "${DMG_NAME}",
  "fileSizeBytes": ${FILE_SIZE_BYTES},
  "sha256": "${SHA256_HASH}",
  "minMacOSVersion": "${MIN_MACOS}",
  "architectures": ["arm64"],
  "signed": ${IS_SIGNED},
  "notarized": ${IS_NOTARIZED},
  "statusLabel": "${STATUS_LABEL}",
  "releaseNotesUrl": "https://voice.ai/blog",
  "downloadUrl": "downloads/${DMG_NAME}",
  "installerUrl": "downloads/${INSTALLER_DMG_NAME}"
}
EOF

cp "${ROOT_DIR}/release/latest.json" "${WEBSITE_DIR}/latest.json"
cp "${ROOT_DIR}/release/latest.json" "${WEBSITE_DOWNLOADS}/latest.json"

# 8. Generate Sparkle appcast.xml
echo "Generating Sparkle appcast.xml..."
cat <<EOF > "${WEBSITE_DIR}/appcast.xml"
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${APP_NAME} Changelog &amp; Updates</title>
    <link>https://voice.ai/appcast.xml</link>
    <description>Most recent updates for ${APP_NAME}</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>$(date -R)</pubDate>
      <sparkle:minimumSystemVersion>${MIN_MACOS}</sparkle:minimumSystemVersion>
      <enclosure
        url="https://voice.ai/downloads/${DMG_NAME}"
        sparkle:version="${BUILD_NUM}"
        sparkle:shortVersionString="${VERSION}"
        length="${FILE_SIZE_BYTES}"
        type="application/octet-stream"
        sparkle:edSignature="UNSIGNED_DEV_KEY" />
    </item>
  </channel>
</rss>
EOF

# 9. Verification Pass: Mount DMG and inspect
echo "================================================================="
echo "Verifying DMG Integrity..."
echo "================================================================="
MOUNT_DIR=$(mktemp -d /tmp/voiceos_mount_XXXXXX)
hdiutil attach "${DMG_OUTPUT}" -mountpoint "${MOUNT_DIR}" -nobrowse -quiet

echo "Mounted DMG at: ${MOUNT_DIR}"
ls -la "${MOUNT_DIR}"

if [ -d "${MOUNT_DIR}/${APP_NAME}.app" ]; then
  echo "✓ ${APP_NAME}.app successfully found inside mounted DMG"
fi

if [ -L "${MOUNT_DIR}/Applications" ]; then
  echo "✓ Applications symlink successfully found inside mounted DMG"
fi

# Run codesign check on the app inside mounted volume
codesign --verify --deep --strict "${MOUNT_DIR}/${APP_NAME}.app" && echo "✓ Codesign verification passed inside DMG"

# Detach
hdiutil detach "${MOUNT_DIR}" -quiet
rm -rf "${MOUNT_DIR}"
rm -rf "${DMG_STAGING}"
echo "✓ DMG unmounted successfully and staging cleaned"

echo "================================================================="
echo "DMG build and packaging complete!"
echo "DMG File:      ${DMG_OUTPUT}"
echo "SHA-256:       ${SHA256_HASH}"
echo "================================================================="

