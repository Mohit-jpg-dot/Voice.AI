# Voice.AI — macOS और Windows के लिए ओपन-सोर्स वॉयस कंप्यूटर एजेंट

> **Voice.AI** एक मुफ़्त और ओपन-सोर्स (MIT लाइसेंस) ऑटोनॉमस वॉयस एजेंट है, जिसे macOS के लिए Swift में और Windows के लिए C# में बनाया गया है। यह हिंदी, हिंग्लिश और अंग्रेज़ी में सहजता से काम करता है—आवाज़ से ऐप्स चलाना, कहीं भी डिक्टेशन लिखना, ईमेल और मैसेज भेजना, फाइल्स को नॉच शेल्फ में रखना और कंप्यूटर को स्वचालित रूप से नियंत्रित करना।

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-0071e3.svg)](#-इंस्टॉलेशन-और-क्विक-स्टार्ट)
[![Release: v1.1.0](https://img.shields.io/badge/Release-v1.1.0-orange.svg)](https://github.com/Mohit-jpg-dot/Voice.AI/releases)
[![macOS Tests: 949/949](https://img.shields.io/badge/macOS%20Tests-949%2F949%20PASSED-34c759.svg)](#-बिल्ड-और-परीक्षण)
[![Windows Core: 200/200](https://img.shields.io/badge/Windows%20Core-200%2F200%20PASSED-34c759.svg)](#-बिल्ड-और-परीक्षण)

---

## 🚀 मुख्य विशेषताएं (Key Capabilities)

1. **डायनामिक एडैप्टिव नॉच आइलैंड (Liquid Dynamic Island)**:
   - मैकबुक के हार्डवेयर नॉच के साथ सहजता से जुड़ा रहता है या एक्सटर्नल स्क्रीन पर ऊपर तैरता है।
   - उत्तर की लंबाई के अनुसार अपने आप बड़ा और छोटा होता है, जिससे कोई भी टेक्स्ट नहीं कटता।
2. **नॉच शेल्फ (Notch Shelf Staging Tray)**:
   - किसी भी फ़ाइल, पीडीएफ, तस्वीर या लिंक को नॉच की तरफ ड्रैग करें—शेल्फ तुरंत खुल जाता है। फ़ाइल्स को स्टोर करें, क्विक लुक से देखें और एक क्लिक में एयरड्रॉप करें।
3. **नाउ प्लेइंग मीडिया प्लेयर (Media Wings)**:
   - Spotify और YouTube पर चल रहे गाने/वीडियो का नाम, एल्बम आर्ट और लाइव लाल ऑडियो इक्वलाइज़र दिखाता है।
   - आवाज़ से नियंत्रित करें: *"video chalao"*, *"pause karo"*, *"gana badlo"*, *"agla gaana"*.
4. **ऑटोनॉमस कंप्यूटर कंट्रोल (`⌃` Control Mode)**:
   - स्क्रीन पर देखकर निर्णय लेता है और काम करता है: *"Click the blue download button"*, *"form submit karo"*.
5. **वॉयस ईमेल और मैसेजिंग (Email & Team Messaging)**:
   - Slack, Discord और WhatsApp पर सीधे आवाज़ से संदेश भेजें: *"Rahul ko WhatsApp pe bolo main late aaunga"*, *"Slack pe dev channel me likho build passed"*.
6. **तीन लचीले AI मोड्स (Three AI Modes)**:
   - **100% Private Offline**: बिना इंटरनेट के अपने कंप्यूटर पर Ollama (Llama 3.2 / Qwen 2.5) और स्थानीय Whisper चलाएं—डेटा कंप्यूटर से बाहर कभी नहीं जाता।
   - **Cloud Models (BYOK)**: अपनी खुद की API Key (Claude 3.5 Sonnet, OpenAI GPT-4o, Gemini) का उपयोग करें।
   - **Free Search Mode**: बिना किसी API Key के Google Search, Wikipedia और Open-Meteo से सटीक जानकारी।

---

## 📦 इंस्टॉलेशन और क्विक स्टार्ट (Installation)

### 1. डिस्क इमेज डाउनलोड करें
- **डाउनलोड**: [**Voice.AI-1.1.0.dmg**](https://github.com/Mohit-jpg-dot/Voice.AI/releases/download/v1.1.0/Voice.AI-1.1.0.dmg) (16.2 MB)
- **न्यूनतम ओएस**: macOS Sonoma 14.0 या नया
- **आर्किटेक्चर**: Apple Silicon (`arm64` — M1, M2, M3, M4)
- **SHA-256**: `b4605fe4cda2d2b2001588d9d1c4eb2f469e20ceecdf6811fb926563050b4509`

### 2. Applications फोल्डर में ड्रैग करें
DMG फाइल खोलें और **Voice.AI** को अपने **Applications** फोल्डर में डालें।

### 3. पहली बार खोलने का तरीका (Gatekeeper)
> [!NOTE]
> ओपन-सोर्स कम्युनिटी बिल्ड होने के कारण macOS पहली बार खोलने पर सुरक्षा चेतावनी दे सकता है।
> - Finder में `Voice.AI.app` पर **राइट-क्लिक (Right-click)** करें और **Open** चुनें।
> - या **System Settings → Privacy & Security** में जाकर सबसे नीचे **Open Anyway** पर क्लिक करें।

---

## 🗣️ हिंदी और हिंग्लिश वॉयस कमांड्स

| श्रेणी | उदाहरण वॉयस कमांड | कार्य |
|---|---|---|
| **ऐप और सिस्टम कंट्रोल** | *"WhatsApp kholo"*, *"Spotify band karo"*, *"Screen lock kar do"* | ऐप्स को तुरंत खोलता, बंद करता या सिस्टम नियंत्रित करता है। |
| **मीडिया प्लेयर** | *"Video chalao"*, *"Gana pause karo"*, *"Agla gana lagao"* | सक्रिय Spotify या YouTube टैब का प्लेबैक नियंत्रित करता है। |
| **यूनिवर्सल डिक्टेशन** | `Fn` की दबाकर रखें, बोलें और छोड़ दें | आपका बोला हुआ वाक्य तुरंत टाइप हो जाता है (`Fn+D` से क्लिपबोर्ड कॉपी)। |
| **नॉच शेल्फ** | *"Shelf dikhao"*, *"Shelf saaf karo"*, *"AirDrop these files"* | शेल्फ ट्रे खोलता है, फाइल्स दिखाता है और एयरड्रॉप करता है। |
| **वॉयस ईमेल** | *"Boss ko leave application draft karo"*, *"Send it"* | ईमेल ड्राफ्ट करता है और अप्रूवल कार्ड पर पुष्टि के बाद भेजता है। |
| **टीम मैसेजिंग** | *"Slack pe engineering channel me likho build passed"* | स्लैक चैनल पर संदेश पोस्ट करता है। |
| **टाइमर और बैटरी** | *"10 minute ka timer lagao"*, *"Kitna time bacha hai?"*, *"Battery kitni hai?"* | लाइव काउंटडाउन टाइमर शुरू करता है और बैटरी प्रतिशत बताता है। |
| **ऑफलाइन गणित** | *"25 * 4 kitna hota hai?"*, *"80 ka 15 percent"* | बिना इंटरनेट के 5 मिलीसेकंड में स्थानीय रूप से गणना करता है। |

---

## 🛡️ सुरक्षा और गोपनीयता (Security & Privacy)

- **कन्सीक्वेंशियल अप्रूवल (Consequential Approval)**: कोई भी महत्वपूर्ण कार्य (ईमेल भेजना, मैसेज पोस्ट करना, फाइल डिलीट करना) आपकी सीधी पुष्टि (Approval Card) के बिना कभी नहीं हो सकता।
- **हार्डन्ड कमांड पॉलिसी (CommandPolicy)**: खतरनाक टर्मिनल कमांड्स (`sudo`, `rm -rf`, `mkfs`, `eval`) हमेशा के लिए ब्लॉक हैं। केवल सुरक्षित कमांड्स ही चल सकती हैं।
- **कीचेन में सुरक्षा (Keychain)**: आपके सभी API टोकन macOS Keychain (`ai.voice.app.auth`) में एन्क्रिप्टेड रहते हैं।

---

## 🛠️ बिल्ड और परीक्षण (Build & Test)

```bash
# रिपोजिटरी क्लोन करें
git clone https://github.com/Mohit-jpg-dot/Voice.AI.git
cd Voice.AI

# macOS ऐप बिल्ड करें
bash scripts/build-app.sh

# सभी 949 कोर टेस्ट चलाएं
VOICE_AI_TEST_MODE=1 bash scripts/run-tests.sh core

# DMG इंस्टॉलर बनाएं
bash scripts/make-dmg.sh
```

---

## 📄 लाइसेंस (License)

Voice.AI **[MIT License](LICENSE)** के तहत मुफ़्त और ओपन-सोर्स सॉफ्टवेयर है।
तृतीय-पक्ष ओपन-सोर्स क्रेडिट्स के लिए [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) देखें।
