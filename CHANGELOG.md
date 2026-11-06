# Changelog

All notable changes to **Voice.AI** are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-11-06

### Added
- **Dynamic Adaptive Notch Sizing**: Auto-extending and auto-shrinking notch HUD window (`540pt` to `680pt` width, `118pt` to `480pt` height) adapting smoothly to answer length, completely eliminating text truncation and scroll clipping.
- **Interactive Web Source Buttons**: Direct one-click glass buttons (`Open on Wikipedia ↗`, `Open on Google Web Search ↗`) embedded inside answer cards to view full sources in the user's default browser.
- **Now Playing Media Dynamic Island**: Flanking wings displaying active playback title, artist, audio visualizer bars, and media controls for Spotify and YouTube.
- **Voice Playback Commands**: Added voice controls (*"play the current video"*, *"pause it"*, *"change it to next"*, *"previous"*, *"video chalao"*, *"gana badlo"*).
- **Coding Agents Monitor**: Real-time dashboard in the Notch displaying active background coding subagents, completed task checklists, execution timers, and interactive question approval buttons.
- **Google Search Free Mode (Lightweight, No LLM)**: Zero-cost factual search engine combining Google Custom Search API, MediaWiki extracts, Open-Meteo real-time weather, and instant offline mathematical evaluation.
- **Expanded Hindi & Hinglish Command Grammar**: 125 verified colloquial patterns for computer control, music playback, app switching, and volume management.
- **Unified Release Packaging**: Automated single DMG installer (`build/Voice.AI-1.0.0.dmg`) with verified SHA-256 checksums and Sparkle appcast generation.

### Changed
- Refactored `MathEngine` to support conversational Hindi/Hinglish phrasing (`"kitna hota hai"`, `"kya hoga"`, `"into"`, `"bhaag"`) and trailing question marks without syntax errors.
- Enhanced Wikipedia search fallback to use official MediaWiki Action and generator APIs, bypassing Cloudflare REST rate gates.
- Updated `NotchHUDWindowController` canvas dimensions to `700pt × 560pt` for ample visual breathing room.

### Fixed
- Fixed text clipping in compact pill answers where long search descriptions were cut off at line endings.
- Fixed `NSAppleScript` synchronous hang during command-line testing by wrapping automation in 1.5-second timeout safeguards.
- Fixed generic media command disambiguation to dynamically resolve to YouTube when an active video is playing.

