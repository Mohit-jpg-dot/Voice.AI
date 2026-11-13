# Discord Connector Setup Guide

Voice.AI interfaces with Discord via official Bot REST endpoints and desktop Accessibility fallback, strictly complying with Discord's Terms of Service.

---

## 1. Discord ToS Compliance: Official Bot vs Desktop Fallback

> [!IMPORTANT]
> **No Self-Bots or User-Token Automation**: Voice.AI strictly refuses to implement Discord self-bots or automate user tokens, which violates Discord Terms of Service and results in account termination.

- **Bot REST Backend**: Voice.AI connects via an official Discord Bot Token to servers, channels, and threads the bot is invited to.
- **Personal DMs & Private Desktop Fallback**: For personal direct messages outside the bot's reach, Voice.AI drives the Discord Desktop app via native macOS Accessibility / Windows UI Automation with explicit user confirmation.

---

## 2. Configuration via Voice.AI Settings

1. Create a Discord Application at the [Discord Developer Portal](https://discord.com/developers/applications).
2. Enable the **Message Content Intent** under the Bot tab.
3. Invite your bot to your desired Discord servers with `Send Messages`, `Read Message History`, and `Add Reactions` permissions.
4. Open **Voice.AI Settings** -> **Security & Email** -> **Messaging Connectors**.
5. Paste your Bot Token and click **Connect**. Credentials are encrypted in macOS Keychain (`ai.voice.app.auth`) / Windows Credential Manager.

---

## 3. Example Voice Commands

- **English**:
  - *"Reply to the last message on Discord with 'sounds good'"*
  - *"Check unread messages on Discord"*
  - *"React with a thumbs up on Discord"*
- **Hindi & Hinglish**:
  - *"Discord pe jawab do sounds good"*
  - *"Discord khol do"*

