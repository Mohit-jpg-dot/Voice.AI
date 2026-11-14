# Uninstalling Voice.AI & Complete Data Removal Guide

Voice.AI is designed to be completely clean and respectful of your operating system. It does not install hidden background daemons, kernel extensions, or system-wide monitoring agents.

---

## 1. Standard Uninstallation (Application Only)

To remove the application while retaining your settings, encrypted memory, and Keychain configurations:

1. Quit Voice.AI if it is running (`Cmd+Q` or click the menu bar icon → **Quit Voice.AI**).
2. Open **Finder** and navigate to your **Applications** folder.
3. Drag **Voice.AI.app** to the Trash (or select it and press `Cmd+Delete`).
4. Empty the Trash.

---

## 2. Complete Data Removal ("Nuclear" Wipe)

If you wish to remove 100% of local application caches, encrypted memory stores, settings, Keychain secrets, and downloaded AI models, run the following terminal commands:

```bash
# 1. Kill any active Voice.AI processes
pkill -f "Voice.AI" || true

# 2. Remove application configuration, encrypted chats, and databases
rm -rf ~/Library/Application\ Support/VoiceAI
rm -rf ~/Library/Application\ Support/VoiceOS

# 3. Remove application preferences (UserDefaults)
defaults delete ai.voice.app 2>/dev/null || true
defaults delete com.voiceos.app 2>/dev/null || true
rm -f ~/Library/Preferences/ai.voice.app.plist
rm -f ~/Library/Preferences/com.voiceos.app.plist

# 4. Remove temporary caches, logs, and crash logs
rm -rf ~/Library/Caches/ai.voice.app
rm -rf ~/Library/Caches/com.voiceos.app
rm -rf ~/Library/Logs/VoiceAI
rm -rf ~/Library/Logs/DiagnosticReports/Voice.AI*

# 5. Remove offline model weights and user plugins (optional)
# NOTE: This deletes downloaded Kokoro voice models (~86MB) and custom plugins
rm -rf ~/.voiceos

# 6. Delete API keys and OAuth tokens from macOS Keychain
security delete-generic-password -s "ai.voice.app.auth" 2>/dev/null || true
security delete-generic-password -s "ai.voice.app" 2>/dev/null || true
security delete-generic-password -l "VoiceOS" 2>/dev/null || true

echo "✓ Voice.AI and all associated local data completely removed."
```

---

## 3. Revoking macOS System Permissions

macOS tracks granted permissions independently in TCC (Transparency, Consent, and Control). To reset permissions granted to Voice.AI:

```bash
# Reset Microphone permission
tccutil reset Microphone ai.voice.app

# Reset Screen Capture permission
tccutil reset ScreenCapture ai.voice.app

# Reset Accessibility permission
tccutil reset Accessibility ai.voice.app

# Reset Automation (Apple Events) permission
tccutil reset AppleEvents ai.voice.app

# Reset Contacts permission
tccutil reset AddressBook ai.voice.app
```

---

## 4. Upgrading from a Previous Release

When installing a new release over an older version:
- **Settings & Preferences**: Automatically preserved in UserDefaults.
- **Keychain Secrets**: Preserved in Keychain `ai.voice.app.auth`.
- **Encrypted Local Memory & Shelf Items**: Preserved and automatically migrated in `~/Library/Application Support/VoiceAI`.
- **Replaced App Bundle**: Simply drag the new `Voice.AI.app` into `/Applications` and choose **Replace**.

