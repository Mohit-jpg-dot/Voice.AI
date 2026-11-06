# How to Set Up Your Free Google Custom Search API Key & Engine ID

Voice.AI's **"Google Search only"** mode uses the official, compliant **Google Custom Search JSON API**. Google provides **100 free search queries per day** for personal use.

Follow these 4 simple steps to set up your free key in under 2 minutes:

---

## Step 1: Create a Google Cloud Project & API Key
1. Go to the [Google Cloud Console Credentials Page](https://console.cloud.google.com/apis/credentials).
2. Sign in with your Google Account.
3. Click **"Select a project"** at the top, then click **"New Project"**.
   - Project Name: `VoiceAI-Search`
   - Click **"Create"**.
4. In the left navigation, go to **"APIs & Services" > "Library"**.
5. Search for **"Custom Search API"**, click on it, and click **"Enable"**.
6. Go back to **"APIs & Services" > "Credentials"**.
7. Click **"+ CREATE CREDENTIALS"** at the top and select **"API Key"**.
8. Copy your generated API Key (starts with `AIzaSy...`).

---

## Step 2: Create a Programmable Search Engine (Search the Entire Web)
1. Open the [Google Programmable Search Engine Control Panel](https://programmablesearchengine.google.com/controlpanel/all).
2. Click **"Add"** (or **"Create a new search engine"**).
3. Fill in the basic settings:
   - Name: `VoiceAI Web Search`
   - What to search?: Select **"Search the entire web"**.
4. Click **"Create"**.
5. On the overview page, look for **"Search engine ID"** (starts with a string like `a1b2c3d4e5...` or `partner-pub-...`).
6. Copy your **Search Engine ID (cx)**.

---

## Step 3: Enter Credentials into Voice.AI
1. In Voice.AI, open **Settings** (or the Setup window) and select **"Google Search only (free, lightest)"**.
2. Paste your:
   - **Google API Key**: `AIzaSy...`
   - **Search Engine ID (cx)**: `a1b2...`
3. Click **"Save & Test Search"**.
4. Voice.AI will execute a test query ("What is the capital of India?") and display the live result card and your remaining daily quota (e.g. `100 / 100`).

---

## Step 4: Security & Quota Notes
- **Stored in Keychain:** Your Google API Key and Engine ID are saved in the encrypted macOS Keychain (`login.keychain-db`) under service `ai.voice.app`. They are never logged, synced, or shared.
- **Daily Quota:** Google allows 100 free requests every 24 hours. Voice.AI tracks your daily usage locally. When the quota is reached, Voice.AI seamlessly falls back to free Wikipedia and DuckDuckGo direct answers, clearly declaring the fallback source.
- **No Cloud LLM:** This mode sends search queries directly to Google's API without invoking any generative model. No OpenAI or Anthropic account is needed.

