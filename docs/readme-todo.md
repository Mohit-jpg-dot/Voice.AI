# README & Repository Action Items (Owner Review)

This document tracks items that require repository owner input, production credential provisioning, or legal verification before public release.

---

## 1. Production Credentials & Apple Notarization
- [ ] **Apple Developer ID Certificate**: Configure Developer ID Application certificate and team ID in `release/config.json` (`signingIdentity` and `teamID`). Currently, builds are ad-hoc signed (`codesign -s -`) which allows local execution but requires users to right-click open on first launch if Gatekeeper is active.
- [ ] **Apple Notary Service**: Set up `xcrun notarytool` credentials in CI/CD pipeline for automated notarization tickets.
- [ ] **Sparkle Appcast URL**: Update `sparkleAppcastURL` in `release/config.json` to the production domain when hosting is deployed.

---

## 2. Legal & Terms of Service Verification
- [ ] **Browser Screen Reader Feature (Experimental)**:
  - Located in `Sources/VoiceOSCore/Brain/GoogleSearchEngine.swift` (`fetchBrowserScreenReading`).
  - Marked as **"needs owner/legal review"** in `docs/google-mode-decision.md`.
  - Ships defaulted to `OFF` (`isBrowserScreenReaderEnabled = false`) until legal counsel reviews automated reading of rendered search pages.
- [ ] **License Confirmation**:
  - The repository root contains an [MIT License](LICENSE) (Copyright (c) 2026 Voice.AI). Owner should confirm whether MIT remains the desired distribution license for the entire project.

---

## 3. Windows Version Build Verification
- [ ] **Windows CI Build Automation**:
  - Codebase exists under `windows/VoiceOS.Windows` (WinUI 3 / C#).
  - Status is **Beta / In-Progress**. Owner should set up Windows CI runner with `.NET 8` and `Windows App SDK` to produce verified MSIX installers.

