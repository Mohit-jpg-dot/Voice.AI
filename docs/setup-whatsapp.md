# WhatsApp Connector Setup Guide

Voice.AI provides unified WhatsApp voice automation with dual backends:
1. **Official WhatsApp Business Cloud API** (Graph API)
2. **Native WhatsApp Desktop Application Backend** (Deep links + Accessibility/UIA)

---

## 1. Zero Unofficial Libraries (Ban Prevention)

> [!WARNING]
> Voice.AI **DOES NOT** use unofficial reverse-engineered WhatsApp libraries (such as Puppeteer/web scraper wrappers or unauthorized protocol clients) because they pose a severe risk of permanent WhatsApp phone number bans. All operations use either Meta's official Cloud API or the native desktop application.

---

## 2. Dual Backends Explained

### A. Official Cloud API (Business Accounts)
- Uses Meta's Graph API (`https://graph.facebook.com/v19.0/{phone-number-id}/messages`).
- **24-Hour Customer Care Window**: Free-form replies are permitted within 24 hours of the user's last message. Outside of this 24-hour window, WhatsApp requires pre-approved template messages. Voice.AI detects error code `131047` and informs you via voice.

### B. Native Desktop App Backend (Personal & Business Accounts)
- Operates WhatsApp Desktop via official `whatsapp://send?phone=...&text=...` deep-linking and macOS Accessibility / Windows UI Automation.
- Allows messaging personal contacts by name or phone number without a Cloud API account.
- Every send strictly requires explicit approval before dispatch.

---

## 3. Configuration via Voice.AI Settings

1. Open **Voice.AI Settings** -> **Security & Email** -> **Messaging Connectors**.
2. Under **WhatsApp (Cloud API & Desktop)**:
   - For Cloud API: provide your **Cloud Token** and **Phone Number ID**.
   - For Desktop App only: no token needed; ensure WhatsApp Desktop is installed.
3. Click **Save** to persist settings in Keychain (`ai.voice.app.auth`) / Windows Credential Manager.

---

## 4. Example Voice Commands

- **English**:
  - *"Send Rahul a WhatsApp saying I'll be late"*
  - *"What did Priya say on WhatsApp?"*
  - *"Open Rahul's chat on WhatsApp"*
  - *"Dictate and send"*
- **Hindi & Hinglish**:
  - *"Rahul ko WhatsApp pe bolo main late aaunga"*
  - *"Priya ne kya bheja?"*
  - *"WhatsApp kholo"*

