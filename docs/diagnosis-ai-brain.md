# AI Brain Architecture Diagnosis & Gap Analysis

**Date**: 2026-11-06  
**Application**: Voice.AI (`ai.voice.app`) for macOS  
**System Target**: Apple Silicon macOS Sonoma / Tahoe  
**Status**: Real Brain Transformation Specification  

---

## 1. Executive Summary

Voice.AI currently achieves high deterministic performance for common macOS commands and bilingual keyword parsing (184/184 unit tests, 125/125 Hindi/Hinglish dataset utterances). However, under the hood it lacks a genuine cognitive engine:
1. **No Real LLM Execution**: Complex conversational queries, reasoning, and coding prompts are not answered by an embedded or cloud LLM; instead, `AIProviderRouter` opens browser tabs (`https://chatgpt.com/?q=...`), and `FastWebSearchEngine` extracts snippets from DuckDuckGo/Wikipedia.
2. **Pseudo-Vision Screen Understanding**: `ScreenVisionService` runs basic offline OCR via Apple Vision (`VNRecognizeTextRequest`). It cannot semantically interpret complex diagrams, understand UI layouts, or answer qualitative questions about screen contents.
3. **Hard-Coded Guided Tutorials**: `VisualCursorGuideEngine` uses static coordinates (e.g. `screenRect.maxX - 180`) rather than a dynamic **Observe-Plan-Act-Verify** vision loop that looks at the application's actual interface and grounds clicks.
4. **No Unified Provider Architecture**: There is no swappable provider interface for Cloud (OpenAI, Claude, Gemini, OpenAI-compatible) and Local (Ollama) execution, no capability detection (probing vision, tool calling, JSON mode), and no secure Keychain storage for credentials.
5. **No Local Neural Speech or Voice Audition**: Speech relies on standard macOS `AVSpeechSynthesizer` voices with no streaming neural TTS or audition interface for picking warm voices across English and Hindi.

---

## 2. Detailed Inspection of Current Subsystems

### A. Conversational & Text Reply Generation
- **`AIProviderRouter.swift`**:
  ```swift
  public func url(for query: String) -> URL? {
      // Merely formats URLs for ChatGPT, Claude, and Gemini web interfaces
      return URL(string: "https://chatgpt.com/?q=\(encoded)")
  }
  ```
  *Limitation*: No direct API integration, no streaming tokens, no conversation context, no JSON output.
- **`HinglishParser.swift`**:
  Uses a static dictionary of ~10 conversational phrases (*"kya hal hai"* $\rightarrow$ *"Sab badhiya hai sir"*).
  *Limitation*: Cannot hold natural multi-turn conversations, admit uncertainty, or mirror conversational register.
- **`FastWebSearchEngine.swift`**:
  Hits DuckDuckGo Instant Answer API and Wikipedia REST endpoints.
  *Limitation*: No structured search provider (Brave, Tavily, Serper, SearXNG), no URL page fetching/reading tool, and no citation synthesis.

### B. Screen Vision & UI Grounding
- **`ScreenVisionService.swift`**:
  Captures screen buffers via `CGWindowListCreateImage` and extracts recognized text blocks via Apple Vision OCR.
  *Limitation*: Has no multimodal Vision Model (`VisionModel`) integration. Cannot describe what is on screen, debug visual errors, or ground UI coordinates.
- **`VisualCursorGuideEngine.swift`**:
  Uses pre-baked static steps for Blender (e.g., hardcoded coordinates `(x: screenRect.maxX - 180, y: 200)`).
  *Limitation*: Fails if Blender's UI is customized, docked differently, scaled, or running a different theme. Lacks an Observe-Plan-Act-Verify loop.

### C. Speech Recognition & Synthesis
- **`SpeechPipelineEngine.swift`**:
  Relies strictly on `AVSpeechSynthesizer` and filters output strings through `formatMinimalisticSpokenReply`.
  *Limitation*: No streaming neural TTS (e.g. Kokoro, Piper, OpenAI TTS, ElevenLabs), no audio audition in settings, no pitch/speed customization per persona.
- **`STTProviderEngine.swift`**:
  Contains vocabulary biasing and architecture scaffolds, but lacks live streaming WhisperKit / whisper.cpp with automatic language detection.

### D. Security & Model Provider Integration
- **Keychain Storage**: Non-existent. No `SecItem` operations exist in the codebase; API keys cannot be safely persisted.
- **Ollama Integration**: Completely missing. No HTTP client communicating with `http://localhost:11434` for `/api/chat`, `/api/tags`, model pulling, or capability probing.
- **Capability Detection**: No probing mechanism to test whether a model supports tool calling, vision, streaming, or JSON mode.

---

## 3. Architecture Blueprint: The New Model Layer

```
┌────────────────────────────────────────────────────────────────────────┐
│                          Unified Brain Layer                           │
│     (ModelRouter: Cloud Mode | Local Ollama Mode | Hybrid Mode)        │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
    ┌───────────────────────────────┼───────────────────────────────┐
    ▼                               ▼                               ▼
┌──────────────┐            ┌──────────────┐                ┌──────────────┐
│  ChatModel   │            │ VisionModel  │                │SpeechToText /│
│  (Streaming, │            │ (Multimodal  │                │TextToSpeech  │
│ Tools, JSON) │            │  Grounding)  │                │(Whisper/TTS) │
└───────┬──────┘            └───────┬──────┘                └───────┬──────┘
        │                           │                               │
┌───────┴───────────────────────────┴───────────────────────────────┴──────┐
│ Providers:                                                               │
│ • Cloud: OpenAI (GPT-4o/mini), Anthropic (Claude 3.5 Sonnet), Gemini     │
│ • Local: Ollama (Qwen 2.5/3.5, Llama 3.2 Vision, etc.) via :11434        │
│ • Audio: Local WhisperKit + High-fidelity TTS (System Enhanced/Cloud)    │
│ • Search: Brave Search / Tavily / Serper / SearXNG Provider              │
│ • Security: Apple Keychain Services (`ai.voice.app` namespace)           │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## 4. Phase-by-Phase Remediation Roadmap

1. **Phase 1: Provider Interfaces & Implementations**
   - Define clean, testable Swift protocols: `ChatModel`, `VisionModel`, `SpeechToText`, `TextToSpeech`, and `SearchProvider`.
   - Build `KeychainService` for encrypted, zero-leak credential management.
   - Implement `OpenAIProvider`, `AnthropicClaudeProvider`, `GeminiProvider`, and `GenericOpenAICompatibleProvider`.
   - Implement `OllamaProvider` targeting `http://localhost:11434` (`/api/chat`, `/api/tags`, `/api/pull`, streaming).
2. **Phase 2: Capability Detection & Model Router**
   - Probe real endpoints with mini-payloads to discover `{streaming, toolCalling, vision, jsonMode, contextLength, speed, cost}`.
   - Build `ModelRouter` supporting **Cloud Mode**, **Local Mode**, and **Hybrid Mode** with user consent guards.
3. **Phase 3: Conversational Brain & Persona Prompts**
   - Connect streaming chat completions with conversational memory across turns.
   - System prompts for **Friday** (warm, natural), **Ultron**, and **Roast** personas with bilingual Hindi/English/Hinglish mirroring.
4. **Phase 4: Real Web Search Integration**
   - Implement real `SearchProvider` (Brave / Tavily / Serper / SearXNG) and give the brain `web_search` and `fetch_page` tools.
5. **Phase 5: Speech & Voice Audition**
   - Build the Voice Picker with real audio audition (sample playback in English & Hindi) and streaming TTS.
6. **Phase 6: Vision & Observe-Plan-Act-Verify Blender Loop**
   - Implement `ScreenVisionEngine` with multimodal Vision Model grounding + AXUIElement / OCR refinement.
   - Implement the autonomous loop: Observe &rarr; Plan &rarr; Show &rarr; Act &rarr; Verify with autonomy levels (*Show only*, *Step by step*, *Auto*) and safety aborts.
7. **Phase 7: Test Suite, Benchmarks & Documentation**
   - Comprehensive test suite in `tests/ai-brain/` covering cloud, local, and hybrid modes.
   - Documentation in `docs/test-report-ai-brain.md`, `docs/setup-cloud.md`, and `docs/setup-ollama.md`.

