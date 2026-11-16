# Conversation Memory Architecture in Voice.AI

Voice.AI features an on-device, privacy-preserving conversational memory system designed for macOS (VoiceOSCore) with cross-platform parity on Windows (VoiceAI.Core). Everything stays on your Mac: 100% local, AES-256 encrypted at rest, and bound to your account key in macOS Keychain.

---

## 1. Architecture Overview (Four Layers + Retrieval)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Working Context (Verbatim turns within Model Token Budget) │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│ 2. Conversation State & Task Ledger                         │
│    - Salience Decaying Entities (People, Files, Apps, URLs) │
│    - 1-Based Result Lists ("the second one", "last one")    │
│    - Truthful Task Verification Proofs (Exit codes, IDs)    │
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│ 3. Rolling Session Summaries (Preserves Decisions & Numbers)│
└─────────────────────────────────────────────────────────────┘
                              ▲
┌─────────────────────────────────────────────────────────────┐
│ 4. Episodic Memory & Long-Term Durable Facts                │
│    - Past conversation indexing ("What did we do yesterday?")│
│    - Explicit consent gate ("Do you want me to remember?")  │
│    - Key-based superseding & corrections                     │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Storage & Encryption at Rest

- **Unified SQLite Store (`UnifiedMemoryDatabase.swift`):**
  - Consolidates legacy fragmented stores into a single per-account SQLite database.
  - Tables: `conversations`, `messages`, `summaries`, `facts`, `corrections`, `tasks`, `entities`, `embeddings`.
  - Virtual FTS5 Full-Text Search tables: `messages_fts`, `summaries_fts`, `facts_fts`.
- **AES-256 Keychain-Bound Encryption:**
  - Database file on disk is AES-256 encrypted at rest using keys securely held in macOS Keychain (`ai.voice.app.unified_memory.key.<accountId>`).
  - Strict POSIX file permissions `0600`.
- **Zero-Data-Loss Migration:**
  - Automatically migrates existing records from `chat_history.json`, `memory.json`, and encrypted caches on first launch.

---

## 3. Working Context & Token Budgeting

Rather than hardcoded turn counts, `WorkingContextManager` dynamically allocates token budgets according to the active model:
- **Small Local 3B Models (e.g. Qwen 2.5 3B, Llama 3.2 3B):** 1,500 tokens
- **Medium Local 7B–9B Models (e.g. Qwen 3.5 9B):** 2,500 tokens
- **Cloud Models (Claude 3.5 Sonnet, GPT-4o, Gemini 2.0 Flash):** 5,000 tokens

Tool executions and outputs are summarized concisely as `[Action: <tool> (done) -> <summary>]` instead of injecting massive JSON dumps.

---

## 4. Conversation State & Follow-Up Resolution

`FollowUpResolver` uses `ConversationState` to rewrite ambiguous follow-up utterances deterministically before they reach the model:
- **Ordinal Indices (English & Hinglish):**
  - *"the second one"*, *"2nd one"*, *"dusra wala"* -> resolves to item 2 from `lastResultList`.
  - *"the last one"*, *"aakhri wala"* -> resolves to the last result list item.
- **Pronouns & Demonstratives:**
  - *"send that to David"*, *"open that PDF"*, *"isko bhej do"* -> resolves to top candidate entity.
- **Repetition & Analogies:**
  - *"again"*, *"wahi dobara karo"* -> re-executes last action on previous target.
  - *"do the same for Downloads"* -> applies last action verb to the new target.
- **Ambiguity Detection:**
  - When two candidate files or people have identical salience, the resolver asks: *"Did you mean File A or File B?"* instead of guessing.

---

## 5. Task Ledger (Truthful Execution Proofs)

The `TaskLedger` strictly separates user requests from verified outcomes:
- Status transitions (`requested`, `inProgress`, `waitingForApproval`, `succeeded`, `failed`, `cancelled`) are written **ONLY** by tool execution and verification logic (disk file presence, exit code 0, API message ID).
- Model responses are forbidden from claiming a task succeeded without recorded verification evidence.
- Completed tasks auto-expire after 30–60 minutes and are never promoted to permanent facts on their own.

---

## 6. Rolling Session Summaries & Episodic Memory

- **`RollingSessionSummaryEngine`:**
  - Triggers when turn count crosses threshold.
  - Preserves key decisions (*"agreed to use PostgreSQL"*), open questions, and exact numbers/dates (`$500`, `March 15`, `99.9%`).
- **`EpisodicMemoryManager`:**
  - Automatically generates smart, human-readable session titles.
  - Answers temporal recall queries:
    - *"What did we talk about yesterday?"* / *"Kal humne kya baat ki thi?"*
    - *"What did we do earlier today?"*
    - *"What was that restaurant I asked about?"*

---

## 7. Semantic Embeddings & Hybrid Search

- **Embedding Ladder (`LocalEmbeddingProvider.swift`):**
  1. **Primary:** Apple `NaturalLanguage` sentence embeddings (`NLEmbedding.sentenceEmbedding(for: .english)`) — on-device and Apple Silicon accelerated.
  2. **Secondary:** Local Ollama embedding model (`nomic-embed-text`) when running.
  3. **Tertiary:** Deterministic 128-dim FNV-1a feature hash vector.
- **Hybrid Ranking Formulation (`HybridMemorySearcher.swift`):**
  $$\text{Score} = (0.45 \times \text{SemanticSimilarity}) + (0.40 \times \text{FTS5KeywordScore}) + (0.15 \times \text{RecencyScore})$$
  Where recency follows a 30-day exponential half-life decay.

---

## 8. User Consent, Corrections & Privacy Controls

- **Consent Gating:**
  - `autoRememberSimplePreferences` setting is **OFF** by default.
  - Casual statements trigger: *"Do you want me to remember that [fact]?"*.
  - Explicit voice commands (*"remember that ..."*, *"yaad rakhna ki ..."*) are saved immediately with `user_explicit` provenance.
- **Instruction Rejection:**
  - Any memory attempting to weaken `CommandPolicy`, approvals, or path allowlists is immediately rejected.
- **Superseding & Deduplication:**
  - Updating a key (e.g. moving from Seattle to New York City) supersedes the older record without duplicating facts.
- **Privacy Controls:**
  - **Pause Memory:** Pauses reading/writing long-term facts.
  - **Incognito / Private Mode:** Zero persistence to disk.
  - **Forget Command:** *"forget that"*, *"forget about [topic]"*, *"clear all memory"*.
