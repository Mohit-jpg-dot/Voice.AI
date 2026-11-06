# Decision Record: "Google Search Only" Free Mode Architecture & Terms of Service Compliance

**Date:** 2026-11-06  
**Status:** Decided & Implemented  
**Scope:** Voice.AI macOS & Windows intelligence routing  

---

## 1. Context & Motivation
Some users have no cloud LLM API key (OpenAI, Anthropic Claude, Gemini) and cannot or will not install a local on-device model (due to limited RAM, disk space, or hardware capability). For these users, Voice.AI provides a third setup and operating mode: **"Google Search only (free, lightest)"**.

In this mode:
- No local LLM is loaded (0 MB model disk requirement, 0 MB GPU RAM used).
- No cloud LLM is invoked.
- Questions asked by voice or text are answered directly from web sources.
- Built-in system commands (open/close apps, play music, volume, screenshots, window navigation) continue to operate with 100% fidelity via the deterministic offline grammar engine.

---

## 2. Terms of Service & Technical Feasibility Analysis

### 2.1 Automated HTML Scraping of google.com (REJECTED)
- **Google Terms of Service:** Google strictly prohibits automated queries against `https://www.google.com/search`. Automated scraping triggers CAPTCHAs, IP rate-limits, and violates Google's ToS Section 3 ("Don't misuse our services").
- **Voice.AI Decision:** **STRICTLY REJECTED.** Voice.AI never scrapes google.com HTML result pages, never uses headless browsers against google.com, never rotates proxies, and never attempts CAPTCHA solving. Automated compliance tests explicitly verify that no code path issues scraping requests to google.com.

### 2.2 Google AI Overviews / SGE (UNAVAILABLE)
- **Availability:** Google does not provide a public, sanctioned API for AI Overviews (formerly Search Generative Experience).
- **Voice.AI Decision:** Voice.AI does not claim or fake AI Overviews. Only documented, sanctioned endpoints are utilized.

---

## 3. Implemented Compliant Paths (In Order of Priority)

### Priority 1: Official Google Custom Search JSON API (Recommended & Supported)
- **Description:** Google's official, sanctioned Programmable Search Engine API (`https://www.googleapis.com/customsearch/v1`).
- **Authentication:** User provides their own Google Cloud API Key and Search Engine ID (`cx`), created free of charge.
- **Quota & Eligibility:** Google provides 100 free search queries per day per project. The user can configure the search engine to search the entire web (via "Search the entire web" setting in Programmable Search Engine control panel).
- **Quota Transparency:** Voice.AI tracks daily query consumption in local device storage and shows the real remaining quota in the UI (e.g. `Queries Today: 3 / 100`).
- **ToS Compliance:** 100% compliant with Google APIs Terms of Service.
- **Labeling:** Results are explicitly labeled as `"via Google Custom Search API"`.

### Priority 2: User-Visible Google in Default Browser with Screen Reading (Flagged: Needs Legal Review)
- **Description:** The app opens `https://www.google.com/search?q=<query>` directly in the user's default browser (Safari, Chrome, Arc) in the user's visible session. With user consent, the app's native accessibility and OCR adapter reads the visible featured snippet or top search result card on screen and speaks it.
- **Guardrails:**
  - No automated background queries or hidden windows.
  - No auto-clicking or navigation manipulation.
  - If a CAPTCHA or consent wall appears, the user sees it and resolves it directly; the app never bypasses it.
  - Strictly human-rate limited.
- **Legal Status:** **NEEDS OWNER / LEGAL REVIEW.** Because this relies on reading page content rendered in the user's own browser window, it is shipped behind an explicit toggle in Settings:
  - Default: **OFF**.
  - UI label: `"Read from visible browser (Experimental - Needs Owner/Legal Review)"`.
- **Labeling:** When active and used, results are explicitly labeled as `"via Google (Read from your screen)"`.

### Priority 3: Free Labeled Non-Google Fallbacks (Always Available)
- **Description:** When the user has not configured a Google Custom Search API key or when their 100 daily queries are exhausted, Voice.AI provides instant answers via free, public knowledge APIs:
  1. **Wikipedia REST API:** Direct entity summaries, definitions, and facts (`https://en.wikipedia.org/api/rest_v1/page/summary/`).
  2. **DuckDuckGo Instant Answer API:** Direct definitions, calculations, and abstracts (`https://api.duckduckgo.com/?q=...&format=json&no_html=1`).
  3. **Open-Meteo API:** Direct real-time weather and temperature without API keys (`https://api.open-meteo.com/v1/forecast`).
- **Honest Labeling:** Voice.AI **NEVER** labels a non-Google fallback as Google. The answer card explicitly declares:
  - `"via Wikipedia (Not Google)"`
  - `"via DuckDuckGo (Not Google)"`
  - `"via Open-Meteo (Not Google)"`

---

## 4. No-Hallucination & Rule-Based Extract Guarantee
Because there is no LLM in the loop:
1. **Zero Paraphrasing:** The text presented on screen is copied word-for-word from the fetched search result snippet or entity abstract.
2. **Quoted Text:** The text is displayed in quotation marks with the original source URL link and retrieval latency (ms).
3. **Speech Truncation:** For spoken TTS, the engine takes the first 1-2 complete sentences ending in punctuation, followed by the spoken phrase `"Full answer on screen"`.

---

## 5. Security & Privacy Safeguards
1. **Query Privacy Disclosure:** The setup screen and Settings explicitly disclose: *"Your search queries are sent over HTTPS to the selected search provider (Google / Wikipedia). No audio recordings, no screen captures, and no account memories are ever transmitted."*
2. **Secret & Credential Blocker:** Before sending any query to web APIs, the regex safety sanitizer inspects the text for API keys (`sk-...`), private keys (`BEGIN PRIVATE KEY`), passwords, tokens, and credit card numbers. If detected, the query is blocked and an on-screen warning is displayed.
3. **Untrusted Content:** All fetched web results are treated strictly as untrusted data, never as prompt instructions.

---

## 6. Capability Profile Declaration
The `GoogleOnlyBrain` class implements the `ChatModel` protocol while declaring its truthful capabilities:
- `streaming: false`
- `toolCalling: false`
- `vision: false`
- `chat: false` (no conversational multi-turn reasoning)
- `search: true` (direct factual retrieval)

Features that require a reasoning model (Visual Cursor Guidance, Screen Vision, Summarization, Conversation, AI Dictation Polish) show an honest `[Disabled in Google Search Mode - Needs LLM]` tag in the UI with a one-click prompt to add a Cloud API key or install an on-device local model.

