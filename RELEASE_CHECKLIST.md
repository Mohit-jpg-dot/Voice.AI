# Voice.AI v1.1.0 Release Checklist & Execution Guide

This document contains the exact steps and copy-paste commands to publish the **Voice.AI v1.1.0** release.

---

## Pre-Release Verification Status

- [x] Version single-source-of-truth: `1.1.0` (Build `43`)
- [x] Release build verified: `build/Voice.AI.app`
- [x] Direct download packaged: `build/Voice.AI-1.1.0.dmg`
- [x] DMG SHA-256: `b4605fe4cda2d2b2001588d9d1c4eb2f469e20ceecdf6811fb926563050b4509`
- [x] Full test suite: 949 PASSED, 0 FAILED across 60 suites
- [x] Website download and metadata checks: 100% PASS
- [x] Notch shelf drag-and-drop & auto-removal verified

---

## Step 1: Clean Profile Manual QA (Run on your Mac)

Before publishing, verify the compiled app bundle locally:

```bash
# 1. Mount the newly built DMG
hdiutil attach build/Voice.AI-1.1.0.dmg

# 2. Launch the app directly from the DMG to verify Gatekeeper & fresh launch
open "/Volumes/Voice.AI 1.1.0/Voice.AI.app"

# 3. Test Shelf Drag & Drop:
# - Drag any image or file from Finder over the notch.
# - Verify the notch opens wide into the Shelf view immediately.
# - Drop the file into the Shelf.
# - Drag the file OUT of the Shelf: verify it is automatically removed from the tray.

# 4. Test Media Playback:
# - Play a song on Spotify or a video on YouTube.
# - Verify compact notch wings match Spotify sizing.
# - Expand notch: verify album artwork is large, track/creator text is crisp, and the progress scrubber bar does not clip outside the pill.

# 5. Unmount DMG when satisfied
hdiutil detach "/Volumes/Voice.AI 1.1.0"
```

---

## Step 2: Push Release Branch & Create Git Tag

Run these commands to push the release branch and tag:

```bash
# Ensure you are on the release branch
git checkout release/1.1.0

# Push branch to remote
git push -u origin release/1.1.0

# Create and push annotated release tag
git tag -a v1.1.0 -m "Release v1.1.0: Islandcn Engine Port, Shelf Drag-and-Drop, and Media Notch"
git push origin v1.1.0
```

---

## Step 3: Publish GitHub Release

Create the release on GitHub with the packaged DMG and checksum:

```bash
gh release create v1.1.0 \
  build/Voice.AI-1.1.0.dmg \
  website/downloads/Voice.AI-1.1.0.dmg.sha256 \
  --title "Voice.AI 1.1.0" \
  --notes-file CHANGELOG.md \
  --latest
```

*(Or upload `build/Voice.AI-1.1.0.dmg` and `Voice.AI-1.1.0.dmg.sha256` manually via https://github.com/opencoredev/Voice.AI/releases/new)*

---

## Step 4: Deploy Updated Website to GitHub Pages

Once the release is live, deploy the website with the updated downloads and documentation hub:

```bash
bash scripts/deploy-gh-pages.sh
```

---

## Step 5: (Optional) Code Signing & Apple Notarization

If you have an Apple Developer account configured in your Keychain:

```bash
# Sign with your Developer ID certificate
codesign --force --deep --options runtime --sign "Developer ID Application: Your Name (TEAMID)" build/Voice.AI.app

# Re-package and submit for notarization
bash scripts/make-dmg.sh
xcrun notarytool submit build/Voice.AI-1.1.0.dmg --keychain-profile "notarytool-profile" --wait

# Staple ticket to DMG
xcrun stapler staple build/Voice.AI-1.1.0.dmg
```
