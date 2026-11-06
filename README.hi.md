# Voice.AI — macOS और Windows के लिए वॉयस-फर्स्ट ऑटोनॉमस कंप्यूटर एजेंट

> **Voice.AI** एक अत्याधुनिक, बैकग्राउंड कंप्यूटर एजेंट है जो आवाज़ (Voice), स्क्रीन विज़न (Vision) और ऑटोनॉमस कंप्यूटर कंट्रोल द्वारा संचालित होता है। एक बटन दबाएं, बोलें, छोड़ें — या पूरी तरह हैंड्स-फ्री बात करें। यह हिंदी, हिंग्लिश और अंग्रेज़ी में सहजता से काम करता है।

[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B%20Sonoma%20%2F%20Tahoe-0071e3.svg)]()
[![Apple Silicon Native](https://img.shields.io/badge/Architecture-Apple%20Silicon%20(M1--M5)-black.svg)]()
[![Core Tests: 184/184](https://img.shields.io/badge/Core%20Tests-184%2F184%20PASSED-34c759.svg)]()
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

---

## 🚀 मुख्य विशेषताएं (Features)

1. **डायनामिक एडैप्टिव नॉच आइलैंड (MacBook Notch Glass)**:
   - मैकबुक के हार्डवेयर नॉच के साथ सहजता से जुड़ा रहता है।
   - उत्तर की लंबाई के अनुसार नॉच विंडो अपने आप बड़ी (`480pt` तक) और छोटी हो जाती है, ताकि कोई भी उत्तर कटे नहीं।
2. **नाउ प्लेइंग मीडिया प्लेयर (Now Playing Wings)**:
   - Spotify और YouTube पर चल रहे गाने या वीडियो का नाम और लाइव ऑडियो इक्वलाइज़र नॉच के किनारों पर दिखाई देता है।
   - आवाज़ से नियंत्रित करें: *"video chalao"*, *"pause karo"*, *"gana badlo"*, *"next track"*.
3. **कोडिंग एजेंट्स मॉनिटर (Coding Agents Monitor)**:
   - आपके चल रहे कोडिंग सब-एजेंट्स की प्रगति, पूर्ण किए गए कार्य और उनके प्रश्नों को नॉच के अंदर सीधे देखें और उत्तर दें।
4. **ऑटोनॉमस कंप्यूटर कंट्रोल (Computer Control)**:
   - ऐप्स खोलें और बंद करें: *"WhatsApp kholo"*, *"Spotify band karo"*, *"Safari open karo"*.
   - सिस्टम सेटिंग्स: *"Aawaz kam karo"*, *"Screen brightness 80% karo"*, *"Screenshot lo"*.
5. **तीन लचीले AI मोड्स (AI Modes)**:
   - **Cloud API**: OpenAI GPT-4o, Anthropic Claude 3.5 Sonnet, Google Gemini 1.5 Pro.
   - **100% Private Offline**: Ollama (Qwen 2.5 / Llama 3) + स्थानीय Whisper STT (बिना इंटरनेट के पूरा निजी)।
   - **Google Search Only (Free, Lightest)**: बिना किसी API key या भारी मॉडल के Google, MediaWiki और Open-Meteo से सटीक उत्तर और लाइव लिंक।

---

## 📦 इंस्टॉलेशन और क्विक स्टार्ट (Installation)

### macOS पर इंस्टॉल करें
1. [Voice.AI-1.0.0.dmg](build/Voice.AI-1.0.0.dmg) डाउनलोड करें।
2. DMG फाइल को खोलें और `Voice.AI.app` को अपने `Applications` फोल्डर में ड्रैग करें।
3. ऐप खोलें और **Accessibility** और **Microphone** की अनुमतियां दें।

### डेवलपर बिल्ड (Terminal से चलाएं)
```bash
# रिपोजिटरी क्लोन करें
git clone https://github.com/your-org/voice-ai.git
cd voice-ai

# ऐप बिल्ड करें
./scripts/build-app.sh

# सभी टेस्ट चलाएं
./scripts/run-tests.sh all
```

---

## 🗣️ हिंदी और हिंग्लिश कमांड्स के उदाहरण

| कमांड | कार्य |
|---|---|
| *"WhatsApp kholo"* | WhatsApp ऐप को तुरंत खोलता है |
| *"Spotify band karo"* | Spotify को सुरक्षित रूप से बंद करता है |
| *"Aawaz thodi kam karo"* | सिस्टम मास्टर वॉल्यूम कम करता है |
| *"Screenshot leke copy karo"* | स्क्रीनशॉट लेकर क्लिपबोर्ड में सुरक्षित करता है |
| *"YouTube pe latest tech video chalao"* | सफारी या क्रोम में यूट्यूब पर वीडियो शुरू करता है |
| *"Gana badlo"* / *"Agla gana"* | Spotify या YouTube पर अगला ट्रैक चलाता है |
| *"system design CS engineer kyu padhte hain"* | सिस्टम डिज़ाइन का सटीक विकिपीडिया व वेब उत्तर और लिंक दिखाता है |
| *"25 into 4 kitna hota hai"* | इन-बिल्ट मैथ कैलकुलेटर से तुरंत उत्तर देता है (`100`) |

---

## 🔒 गोपनीयता और सुरक्षा (Privacy)
- आपके द्वारा बोले गए शब्द और ऑडियो कभी भी किसी तीसरे पक्ष को बिना अनुमति नहीं भेजे जाते।
- पासवर्ड, क्रेडिट कार्ड और निजी टोकन को स्थानीय स्तर पर स्वचालित रूप से पहचान कर ब्लॉक कर दिया जाता है।
- लोकल मोड में डेटा पूरी तरह से आपके अपने मैक पर ही रहता है।

