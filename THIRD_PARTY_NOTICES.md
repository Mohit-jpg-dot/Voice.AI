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

