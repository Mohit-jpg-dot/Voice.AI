# Slack Connector Setup Guide

Voice.AI includes first-class voice and tool control for Slack via the official Slack Web API using OAuth User Tokens.

---

## 1. Supported Scopes

Voice.AI uses an official user token (`xoxp-...`) to act on your behalf in Slack. The required scopes are:

| Scope | Permission Tier | Purpose |
|---|---|---|
| `chat:write` | **Consequential** | Send messages and reply to threads (requires explicit Notch Card approval) |
| `channels:read` | Read-Only | Discover public channels in your workspace |
| `groups:read` | Read-Only | Discover private channels you belong to |
| `im:read` | Read-Only | Discover direct message conversations |
| `im:history` | Read-Only | Read incoming DMs and unread messages |
| `channels:history` | Read-Only | Read channel message history |
| `users:read` | Read-Only | Resolve team member names and mentions |
| `search:read` | Read-Only | Search workspace message history |
| `reactions:write` | Reversible | Add emoji reactions to messages |
| `users.profile:write` | Reversible | Update your Slack status and emoji |

---

## 2. Configuration via Voice.AI Settings

1. Open **Voice.AI Settings** -> **Security & Email** -> **Messaging Connectors**.
2. Under **Slack (Web API)**, paste your user token (`xoxp-...`).
3. Click **Connect** (credentials are saved securely in Keychain service `ai.voice.app.auth` / Windows Credential Manager).
4. Click **Test** to verify connection against `auth.test`.

---

## 3. Example Voice Commands

- **English**:
  - *"Message #general on Slack: standup in 5 minutes"*
  - *"Read my unread Slack messages"*
  - *"Search Slack for invoice"*
  - *"React with a thumbs up"*
  - *"Set my Slack status to in a meeting"*
- **Hindi & Hinglish**:
  - *"Slack pe general channel me likho standup in 5 minutes"*
  - *"Mere unread messages padho"*
  - *"Slack pe dev-team channel khol do"*

---

## 4. Safety & Rate Limits

- Every message send or post strictly requires explicit user approval on the Notch card or voice confirmation (*"Yes"* / *"Haan bhejo"*).
- Incoming message content is untrusted and wrapped in `<UNTRUSTED_MESSAGE_DATA>`.
- API rate limits adhere to standard Slack Tier 2/3 limits with automatic exponential backoff.

