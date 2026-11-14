# Third-Party Software and Model Notices

Voice.AI incorporates, interfaces with, or provides automated installers for the following third-party open-source libraries, runtimes, and machine learning models. Each is governed by its own respective license terms as detailed below.

---

## 1. Local Runtimes & Inference Engines

### Ollama
- **Homepage:** [https://ollama.com](https://ollama.com)
- **Source:** [https://github.com/ollama/ollama](https://github.com/ollama/ollama)
- **License:** MIT License
- **Notice:** Copyright (c) 2023-2026 Ollama Inc.
- **Usage:** Optional local inference server for offline neural LLMs.

### llama.cpp
- **Source:** [https://github.com/ggerganov/llama.cpp](https://github.com/ggerganov/llama.cpp)
- **License:** MIT License
- **Notice:** Copyright (c) 2023-2026 Georgi Gerganov and contributors.
- **Usage:** Underlying C/C++ engine for quantized GGUF model execution.

### whisper.cpp
- **Source:** [https://github.com/ggerganov/whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- **License:** MIT License
- **Notice:** Copyright (c) 2023-2026 Georgi Gerganov and contributors.
- **Usage:** Local offline high-accuracy speech-to-text transcription engine.

### Piper TTS
- **Source:** [https://github.com/rhasspy/piper](https://github.com/rhasspy/piper)
- **License:** MIT License
- **Notice:** Copyright (c) 2022-2026 Michael Hansen (Rhasspy).
- **Usage:** Ultra-fast local neural text-to-speech engine.

---

## 2. Open Weights Neural Models (Optional User Downloads)

### Qwen 2.5 (Alibaba Cloud)
- **Source:** [https://github.com/QwenLM/Qwen2.5](https://github.com/QwenLM/Qwen2.5)
- **License:** Apache License 2.0 (Models under 32B parameters)
- **Usage:** Recommended lightweight local multilingual chat and reasoning model.

### Llama 3 / 3.1 / 3.2 (Meta AI)
- **Source:** [https://llama.meta.com](https://llama.meta.com)
- **License:** Meta Llama 3 Community License Agreement
- **Usage:** High-performance local chat and vision models.

### Whisper Large-v3 / Medium / Small / Base (OpenAI)
- **Source:** [https://github.com/openai/whisper](https://github.com/openai/whisper)
- **License:** MIT License
- **Notice:** Copyright (c) 2022-2026 OpenAI.
- **Usage:** Multilingual speech recognition models.

---

## 3. UI, Geometry, and Clean-Room Attributions

### Boring Notch Architecture
- **Reference:** Mathematical coordinate transformations and concentric radii inspiration from open-source macOS HUD research (`boring.notch`).
- **Notice:** All Swift code in Voice.AI is a clean-room implementation authored from first principles in native SwiftUI and AppKit, as documented in `NOTICE.md`.

---

## 4. Web Services & Data Sources

### Open-Meteo
- **Homepage:** [https://open-meteo.com](https://open-meteo.com)
- **License:** Creative Commons Attribution 4.0 International (CC BY 4.0)
- **Usage:** Free real-time weather and forecast endpoint without API keys.

### Wikipedia & MediaWiki APIs
- **Homepage:** [https://www.wikimedia.org](https://www.wikimedia.org)
- **License:** Creative Commons Attribution-ShareAlike 4.0 (CC BY-SA 4.0)
- **Usage:** Factual knowledge summaries, definitions, and encyclopedic extracts.

### Google Programmable Search Engine API
- **Homepage:** [https://developers.google.com/custom-search](https://developers.google.com/custom-search)
- **Terms:** Governed by Google APIs Terms of Service and Custom Search JSON API quotas.
- **Usage:** Optional user-provided API key mode for direct web search snippets.

### Slack Web API
- **Homepage:** [https://api.slack.com](https://api.slack.com)
- **Terms:** Governed by Slack API Terms of Service.
- **Usage:** Official Web API for workspace channels, direct messages, and reactions.

### Discord Developer Platform & REST API
- **Homepage:** [https://discord.com/developers/docs](https://discord.com/developers/docs)
- **Terms:** Governed by Discord Developer Terms of Service and Policy.
- **Usage:** Official Bot REST API for server channels and replies. No user tokens or self-bots.

### Meta WhatsApp Business Cloud API
- **Homepage:** [https://developers.facebook.com/docs/whatsapp](https://developers.facebook.com/docs/whatsapp)
- **Terms:** Governed by WhatsApp Business Terms of Service and Meta Developer Policies.
- **Usage:** Official Graph API for outbound WhatsApp Business messaging and templates.

---

## 5. UI Engine & Preset Attributions

### islandcn
- **Source:** [https://github.com/opencoredev/islandcn](https://github.com/opencoredev/islandcn)
- **Pinned Commit:** `0011a41ea4882f3818caf35c98f3ee46b80c4a2c`
- **License:** MIT License
- **Copyright:** Copyright (c) 2026 Leo
- **Notice:** The engine architecture (activity stack, presentations, priority queue, alerts, reduced-motion fallbacks) and presets (timer, media, recording, transfer, battery, step ETA) in Voice.AI's dynamic notch are ported and translated from islandcn to native Swift (VoiceOSCore/VoiceOSApp) and C# (.NET Core in windows/).

```text
MIT License

Copyright (c) 2026 Leo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```


