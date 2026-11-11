# Phase 0: Core Foundations (`ToolRegistry`, `EventBus`, `MemoryStore`, Permission Tiers)

Phase 0 introduces four modular, protocol-first foundations shared across macOS (`VoiceOSCore`) and Windows (`VoiceAI.Core`).

## 1. Permission Tiers & Consequential Safety Gate

- **macOS**: `Sources/VoiceOSCore/Tools/PermissionTier.swift`, `Sources/VoiceOSCore/Platform/ToolApprovalCoordinator.swift`
- **Windows**: `windows/VoiceAI.Core/Tools/ToolRegistry.cs` (`PermissionTier`)

| Tier | Behavior | Examples |
|---|---|---|
| `READ_ONLY` | Executes immediately with zero UI interruption | `math_evaluate`, `mail_check_inbox`, `notes_read`, `memory_search` |
| `REVERSIBLE` | Executes with soft status feedback and event logging | `mail_draft`, `whatsapp_draft`, `notes_create`, `notion_create_page`, `memory_remember` |
| `CONSEQUENTIAL` | Suspended by `ToolApprovalCoordinator` until user approves in Notch Approval Card | `mail_send`, `whatsapp_send`, `slack_send`, `discord_send`, `terminal_run`, destructive MCP tools |

When a `CONSEQUENTIAL` tool runs inside `Voice.AI.app`, `AppState` implements `ToolApprovalPresenting` and displays the `actionApprovalCard` in `NotchGlassIslandView` with the `CONSEQUENTIAL` tier badge and scrubbed arguments. Without an approval presenter or explicit approval handler, consequential invocations fail closed.

## 2. MCP-Compatible `ToolRegistry` & `MCPClientAdapter`

- **macOS**: `Sources/VoiceOSCore/Tools/ToolRegistry.swift`, `Sources/VoiceOSCore/Marketplace/MCPClientAdapter.swift`
- **Windows**: `windows/VoiceAI.Core/Tools/ToolRegistry.cs`

Every built-in or external tool registers a `RegisteredToolSchema` (`inputSchema` JSON Schema), `PermissionTier`, and async handler under `ToolRegistryProtocol`.
- `exportMCPToolsList()` emits MCP `tools/list` JSON dictionaries.
- `MCPClientAdapter.connectAndRegisterServer` performs JSON-RPC 2.0 `initialize`, `tools/list`, and `tools/call` discovery and stores any optional bearer tokens strictly in macOS Keychain (`KeychainService`).

## 3. Typed Pub/Sub `EventBus`

- **macOS**: `Sources/VoiceOSCore/Events/EventBus.swift` (`EventBusProtocol`)
- **Windows**: `windows/VoiceAI.Core/Events/EventBus.cs` (`IEventBus`)

`EventBus.shared` supports filtered callback subscriptions, cancellable subscription IDs, Swift `AsyncStream<VoiceEvent>` consumers, and a bounded 200-event history buffer. Payloads are scrubbed via `SecretRedactor` before delivery. Currently emitted events include `.toolInvoked`, `.approvalRequested`, `.approvalResolved`, and `.memoryUpdated`; proactive system monitors (`.batteryChanged`, `.cpuMemoryPressure`, `.calendarUpcoming`, `.buildStatusChanged`) will hook in during Phase 2.

## 4. Encrypted Semantic `MemoryStore`

- **macOS**: `Sources/VoiceOSCore/Memory/MemoryStore.swift` (`MemoryStoreProtocol`), `Sources/VoiceOSCore/Memory/LocalEmbeddingProvider.swift` (`LocalEmbeddingProviding`)
- **Windows**: `windows/VoiceAI.Core/Memory/SemanticMemoryStore.cs` (`IMemoryStore`, `ILocalEmbeddingProvider`)

Stores three scopes per authenticated account in Keychain-bound AES-256 encrypted storage (`Application Support/Voice.AI/Memory/memory_<sha256(accountId)>.enc` on macOS, DPAPI/PBKDF2-AES on Windows):
- `.shortTerm`: bounded recent conversation turns
- `.longTerm`: persistent facts, preferences, projects, and people
- `.userProfile`: display name, preferred language, persona, and custom traits

Semantic retrieval uses 128-dim L2-normalized local feature-hashed word + character trigram vectors (`LocalEmbeddingProvider`) with optional localhost Ollama `/api/embeddings` support, plus `remember`, `forget`, and `searchSemantic`.

## 5. Centralized Secret Scrubbing

- **macOS**: `Sources/VoiceOSCore/Security/SecretRedactor.swift`
- **Windows**: `windows/VoiceAI.Core/Security/SecretRedactor.cs`

Extended pattern redaction (OpenAI, Anthropic, Google, Notion, GitHub, Slack/Discord webhooks, Bearer tokens, generic key/secret assignments, and payment cards) is enforced across `EncryptedChatHistoryManager`, `VoiceOSTelemetry`, `EventBus`, and `MemoryStore`.

