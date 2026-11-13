# Voice.AI Integrations Setup Guide

Welcome to the unified setup guide for Voice.AI macOS & Windows integrations. This document explains how every application integration connects, the exact permissions requested, and step-by-step instructions for both end-users and developers.

---

## Table of Contents
1. [User Guide: Connecting in the App](#1-user-guide-connecting-in-the-app)
   - [Email (Gmail & Apple Mail)](#email-gmail-and-apple-mail)
   - [Slack](#slack)
   - [Discord](#discord)
   - [WhatsApp](#whatsapp)
   - [Spotify & Media](#spotify)
   - [Calendar, Reminders & Notes](#calendar-reminders-and-notes)
   - [Notion, Linear & Dev Tools](#notion-linear-and-dev-tools)
2. [Developer Guide: One-Time Provider Registration](#2-developer-guide-one-time-provider-registration)
   - [Google Cloud OAuth 2.0 (Gmail)](#google-cloud-oauth-20-registration)
   - [Slack App & Bot Scopes](#slack-app-registration)
   - [Discord Developer Portal & Bot Token](#discord-bot-registration)
   - [Meta WhatsApp Business Cloud API](#meta-whatsapp-business-api-registration)
3. [macOS System Permissions Table](#3-macos-system-permissions-table)
4. [Security & Privacy Architecture](#4-security-and-privacy-architecture)
5. [Platform Limits & Honesty Notes](#5-platform-limits-and-honesty-notes)
6. [Offline Mode & FAQ](#6-offline-mode-and-faq)

---

## 1. User Guide: Connecting in the App

You can connect and test any integration directly inside Voice.AI without manual terminal commands. Simply open **Apps > Installed Mac Applications** and click on any application tile.

### Email (Gmail and Apple Mail)
- **What you get**: Draft, review, edit, and send emails directly inside the Notch Pill. Debounced background draft sync with your real Gmail or Apple Mail mailbox, and a 10-second undo window.
- **Connection Methods**:
  1. **Use Mail.app (Recommended)**: Zero configuration required. Voice.AI communicates with Apple Mail via native macOS Apple Events.
  2. **Sign in with Google (OAuth PKCE)**: Connects directly to Google's official Gmail REST API with browser PKCE flow.
- **In-App Clicks**:
  1. Open Voice.AI Main Window -> **Apps** tab.
  2. Click **Email (Mail / Gmail)**.
  3. Select **Use Mail.app** (or **Sign in with Google**).
  4. Grant the macOS Automation permission prompt when prompted.
  5. Click **Test Connection** to verify mailbox availability.
- **Troubleshooting**:
  | Symptom | Cause | Fix |
  |---|---|---|
  | "Permission denied for Mail.app" | macOS Automation permission not granted | Open System Settings > Privacy & Security > Automation > Voice.AI and toggle Mail ON. |
  | "No account configured" | Apple Mail has no configured inboxes | Add an email account in Apple Mail Preferences > Accounts. |

---

### Slack
- **What you get**: Voice-controlled direct messages, channel postings (`#general`, `#dev`), thread replies, unread message summaries, and workspace presence updates.
- **In-App Clicks**:
  1. Open **Apps** -> click **Slack**.
  2. Click **Add to Slack**.
  3. Authorize your Slack workspace.
  4. The status badge will switch to **Connected (Active Workspace)**.
  5. Click **Test Connection** to verify authentication.
- **Troubleshooting**:
  | Symptom | Cause | Fix |
  |---|---|---|
  | "User token missing" | Workspace authorization not completed | Click **Add to Slack** and complete the browser consent prompt. |
  | "channel_not_found" | Bot or user is not a member of private channel | Invite Voice.AI to the private channel using `/invite @Voice.AI`. |

---

### Discord
- **What you get**: Voice-driven posting to Discord servers, channel chat, thread replies, and hands-free control.
- **Connection Method**: Official Discord Bot Token only. *(Personal user token self-bots are strictly blocked per Discord Terms of Service).*
- **In-App Clicks**:
  1. Open **Apps** -> click **Discord**.
  2. Click **Open Developer Portal** (or create a bot at discord.com/developers).
  3. Copy your Bot Token and paste it into the secure field.
  4. Click **Test Connection**; Voice.AI confirms the bot identity and marks it **Connected**.
- **Troubleshooting**:
  | Symptom | Cause | Fix |
  |---|---|---|
  | "Invalid Bot Token" | Token was regenerated or mistyped | Re-copy the Token from Discord Developer Portal > Bot > Reset Token. |
  | "Missing Permissions" | Bot role lacks Send Messages permission | In Server Settings > Roles, grant the bot Send Messages and Read Message History. |

---

### WhatsApp
- **What you get**: Dictate and send WhatsApp messages to any contact by name or number without opening browser tabs.
- **Connection Methods**:
  1. **WhatsApp Desktop (Accessibility - Recommended)**: Drives the official WhatsApp Desktop macOS client safely using deep links (`whatsapp://send`) and Accessibility. No account-ban risk.
  2. **WhatsApp Business Cloud API**: Official Meta Cloud API with 24-hour service window.
- **In-App Clicks**:
  1. Open **Apps** -> click **WhatsApp**.
  2. Verify WhatsApp Desktop is installed and signed in.
  3. Click **Open Accessibility** and ensure Voice.AI is enabled in System Settings.
  4. Run the harmless self-test (verifies accessibility focus without sending messages).
- **Troubleshooting**:
  | Symptom | Cause | Fix |
  |---|---|---|
  | "Accessibility untrusted" | Accessibility permission missing | Open System Settings > Privacy & Security > Accessibility and enable Voice.AI. |
  | "App not running" | WhatsApp Desktop is closed | Launch WhatsApp Desktop once to settle background services. |

---

### Spotify
- **What you get**: Hands-free playback of tracks, artists, and playlists in English, Hindi, and Hinglish. Real-time Now Playing visualizer in the Notch Island.
- **Setup**: Install Spotify Desktop. Voice.AI communicates via macOS Apple Events automatically.

---

### Calendar, Reminders and Notes
- **What you get**: Voice drafting of calendar meetings, Google Meet links, reminder tasks, and Apple Notes.
- **Setup**: One-click approval via macOS System Settings prompts for Calendars, Reminders, and Automation.

---

### Notion, Linear and Dev Tools
- **What you get**: Append voice notes to Notion databases, browse project status, and execute coding workflows via the App Builder.
- **Setup**: Provide internal integration tokens stored exclusively in macOS Keychain.

---

## 2. Developer Guide: One-Time Provider Registration

If you are deploying your own OAuth client IDs for production builds, configure them in `release/config.json`:

### Google Cloud OAuth 2.0 Registration
1. Visit the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a project named `Voice.AI`.
3. Under **APIs & Services > Library**, enable the **Gmail API**.
4. Under **OAuth consent screen**:
   - User Type: External (or Internal for Google Workspace).
   - Add scopes: `https://www.googleapis.com/auth/gmail.compose` (and optionally `gmail.readonly`).
   - Add test users while in Testing mode.
5. Under **Credentials > Create Credentials > OAuth client ID**:
   - Application type: **macOS / iOS / Desktop App**.
   - Bundle ID: `ai.voice.app`.
   - Custom URL Scheme: `ai.voice.app:/oauth2callback`.
6. Copy the **Client ID** (never store client secrets in client apps) into `release/config.json`.

### Slack App Registration
1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App** (From scratch).
2. Under **OAuth & Permissions**:
   - Redirect URL: `ai.voice.app:/slack/callback` or `http://127.0.0.1:8765/slack/callback`.
   - User Token Scopes: `chat:write`, `channels:read`, `im:read`, `users:read`, `search:read`.
3. Install the app to your workspace and copy the public Client ID.

### Discord Bot Registration
1. Go to [discord.com/developers/applications](https://discord.com/developers/applications).
2. Click **New Application** and enter name `Voice.AI Assistant`.
3. Navigate to **Bot** tab -> Click **Add Bot**.
4. Under Privileged Gateway Intents, enable **Message Content Intent** if channel reading is required.
5. Click **Reset Token** and paste the token into Voice.AI's Discord Setup screen.
6. Generate invite link via **OAuth2 > URL Generator** with permissions: `Send Messages`, `Read Messages/View Channels`.

### Meta WhatsApp Business API Registration
1. Go to [developers.facebook.com](https://developers.facebook.com/).
2. Create an App under **Business** type.
3. Add the **WhatsApp** product.
4. Retrieve the **Phone Number ID** and **Permanent Access Token** under WhatsApp > API Setup.

---

## 3. macOS System Permissions Table

Voice.AI follows the principle of least privilege. Permissions are requested only when the associated integration is activated:

| Permission | Reason & Usage | System Settings Pane |
|---|---|---|
| **Accessibility** | Driving WhatsApp Desktop, Discord, and window navigation | Privacy & Security > Accessibility |
| **Automation** | Interacting with Apple Mail, Spotify, and Apple Notes via Apple Events | Privacy & Security > Automation |
| **Calendars** | Reading and drafting meetings in Apple Calendar / Google Meet | Privacy & Security > Calendars |
| **Reminders** | Creating and checking personal tasks in Apple Reminders | Privacy & Security > Reminders |
| **Microphone** | Voice dictation and continuous hands-free speech recognition | Privacy & Security > Microphone |
| **Screen Recording** | Visual grounding and OCR for 'What is on my screen?' queries | Privacy & Security > Screen Recording |

---

## 4. Security & Privacy Architecture

1. **Keychain-Only Storage**: All OAuth access tokens, refresh tokens, Slack user tokens, and Discord bot tokens are stored in the macOS Keychain under access group `ai.voice.app.auth`.
2. **Secret Redaction**: Every outgoing log entry and transcript is processed by `SecretRedactor`, scrubbing JWTs, bearer tokens, API keys, and sensitive tokens.
3. **No Hidden Web Automation**: Voice.AI rejects embedded invisible browsers for Gmail or chat logins to avoid session interception and credential leaks.
4. **Data Isolation**: Incoming and outgoing emails and messages are wrapped in `<UNTRUSTED_EMAIL_DATA>` and `<UNTRUSTED_MESSAGE_DATA>` tags to prevent prompt injection attacks.
5. **No Password Handling**: Voice.AI never asks for or stores email passwords or Discord user passwords. Authentication is handled strictly via official OAuth PKCE or system-authenticated apps.

---

## 5. Platform Limits & Honesty Notes

- **WhatsApp Personal Accounts**: There is no official public API for personal WhatsApp accounts. Voice.AI drives the official desktop app via Accessibility. Delivery confirmation is not verifiable at the API level for desktop automation.
- **Discord Personal DMs**: Discord Terms of Service strictly forbid automated user accounts ("self-bots"). Voice.AI uses bot tokens for servers and shared channels, with Accessibility fallback for personal DMs with explicit user confirmation.
- **Gmail Quotas**: Standard Gmail consumer accounts allow up to 500 emails per day, while Google Workspace accounts allow up to 2,000. Attachment limits are enforced at 25 MB total MIME payload.

---

## 6. Offline Mode & FAQ

- **Does Voice.AI work offline?** Yes! Local Ollama models, Apple Mail drafting, Apple Notes, Reminders, and system control operate completely offline.
- **What happens if I click Send while offline?** Voice.AI marks the draft as **Queued (Offline)** and delivers it automatically when network connectivity is restored, with idempotency guards preventing duplicate sends.
- **How do I disconnect an account?** Open **Apps**, click the app icon, and click **Disconnect**. Voice.AI revokes the token with the provider and purges credentials from the Keychain immediately.

