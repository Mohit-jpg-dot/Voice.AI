# SECURITY & THREAT MODEL — VoiceOS

VoiceOS executes actions across your operating system driven by voice input. Security and privacy are foundational.

## Core Security Principles

1. **Untrusted Data Isolation (Prompt Injection Guard)**:
   - Screen content, accessibility trees, web pages, emails, memory records, and external agent outputs are strictly treated as **UNTRUSTED data**.
   - Untrusted data can NEVER trigger tool execution, approvals, or permission scope elevation.
   - Only direct, authenticated user speech or explicit user clicks can authorize actions.

2. **Payload-Bound Approvals**:
   - Consequential actions (deletions, file overwrites, emails, calendar invites, spending, terminal commands) generate an exact, immutable payload signature.
   - Confirmation binds strictly to this payload. If an action's arguments change, previous approval is immediately invalidated.

3. **Keychain-Secured Secrets**:
   - All cloud API tokens, OAuth refresh tokens, and encryption keys are stored exclusively in the macOS Keychain (`kSecClassGenericPassword`).
   - Secrets are never written to disk logs, transcripts, or telemetry.

4. **Offline First & Zero Cloud Telemetry**:
   - Audio transcription and personal memory run locally via quantized Whisper.cpp and SQLite.
   - Zero telemetry is transmitted unless explicitly opted-in by the user.

## Threat Model & Mitigations

| Threat Vector | Mitigation Strategy |
| :--- | :--- |
| **Voice Spoofing / Ambient Audio** | Broad/destructive actions require a spoken confirmation phrase + explicit physical click or passphrase. Ambient "yes" is never accepted. |
| **Prompt Injection via Screen/Email** | AX/OCR scanner isolates retrieved text as raw string data in sanitized XML envelopes; model planner rejects commands sourced from document context. |
| **Malicious Remote Phone Control** | QR-paired end-to-end encrypted relay with device-specific Ed25519 keys, biometrics (Face ID) re-auth for sensitive scopes, and Mac-side visual indicator. |
| **Memory Poisoning** | Local SQLite memory database is schema-versioned, HMAC-signed, with complete provenance auditing ("Why do you think that?"). |
| **Password Fields & Terminals** | Secure text input fields (`NSSecureTextField` / AX role `AXSecureTextField`) are detected and skipped; dictation will never capture or insert into credentials. |
| **Messaging Prompt Injection** | Incoming Slack, Discord, and WhatsApp content is scrubbed of injection triggers and isolated inside `<UNTRUSTED_MESSAGE_DATA>` tags. Messages can never invoke tools. |
| **Messaging Connectors & ToS** | Send actions strictly require `.consequential` Notch Approval Card. Zero unofficial WhatsApp libraries (ban prevention); zero Discord self-bots (Discord ToS compliance). Tokens stored in `ai.voice.app.auth` Keychain. |

