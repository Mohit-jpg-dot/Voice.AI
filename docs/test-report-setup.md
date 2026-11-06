# Voice.AI Setup & Authentication Test Report

**Date:** 2026-11-06  
**Test Suite:** `tests/setup_and_auth/test_setup_auth.swift`  
**Runner:** `build/setup_auth_test_runner`  
**Host Architecture:** Apple Silicon M5 (16 GB Unified Memory)  
**Target OS:** macOS 14.0+ (Darwin 26.5.2)  
**Overall Result:** **34 PASSED, 0 FAILED (100.0% Pass Rate)**

---

## Executive Summary

This report validates the end-to-end First-Run Setup Flow, Authentication Engine, Per-Account Encrypted History, Hardware Recommendation Profiler, Command Transparency Parity, and Local Model Download Manager for Voice.AI (`ai.voice.app`).

---

## Detailed Test Suite Results

### [Suite 1] Authentication Engine & PBKDF2 Cryptographic Security
- **Test 1.1:** Weak password rejection guidance (<8 chars, missing numbers/casing) &rarr; **PASS**
- **Test 1.2:** Account signup with 16-byte cryptographically secure salt & PBKDF2-SHA512 (100,000 iterations) &rarr; **PASS**
- **Test 1.3:** Duplicate email registration rejection (`AuthError.userAlreadyExists`) &rarr; **PASS**
- **Test 1.4:** Invalid password attempt rejection (`AuthError.invalidCredentials`) &rarr; **PASS**
- **Test 1.5:** Rate-limiting enforcement (5 failed attempts per 60s trigger `rateLimited(retryAfterSeconds:)`) &rarr; **PASS**
- **Test 1.6:** Successful credential login and active session generation &rarr; **PASS**
- **Test 1.7:** 30-day offline grace period active timestamp verification &rarr; **PASS**
- **Test 1.8:** JSON user data export generation with account profile &rarr; **PASS**
- **Test 1.9:** Privacy verification: JSON export never exposes password hashes, salts, or plaintext keys &rarr; **PASS**

### [Suite 2] Per-Account Encrypted Chat History & Secret Redaction
- **Test 2.1:** Conversation turn recording with AES-256 encryption at rest &rarr; **PASS**
- **Test 2.2:** Account A history persistence and retrieval &rarr; **PASS**
- **Test 2.3:** Active regex secret scrubber sanitizing API keys (`sk-proj-...` &rarr; `[REDACTED_API_KEY]`) &rarr; **PASS**
- **Test 2.4:** Account B isolation: Account B querying history sees zero cross-account leakage &rarr; **PASS**
- **Test 2.5:** Logged-out state query returns empty collection &rarr; **PASS**
- **Test 2.6:** Re-authenticating Account A unlocks and decrypts its history seamlessly &rarr; **PASS**

### [Suite 3] Hardware Specification & Profile Tier Recommendation
- **Test 3.1:** Dynamic Apple Silicon chip detection (`Apple M5`) &rarr; **PASS**
- **Test 3.2:** Physical RAM capacity detection (`16.0 GB`) &rarr; **PASS**
- **Test 3.3:** Primary APFS volume free disk space measurement (`282.7 GB`) &rarr; **PASS**
- **Test 3.4:** Hardware qualification for local offline models &rarr; **PASS**
- **Test 3.5:** Hardware recommendation tier mapping:
  - `Lite Tier` &rarr; `qwen2.5:3b` (Fast 3B model) &rarr; **PASS**
  - `Balanced Tier` &rarr; `qwen2.5:7b` (Standard 7B model) &rarr; **PASS**
  - `Best Tier` &rarr; `qwen2.5:14b` (High-Intelligence 14B model) &rarr; **PASS**

### [Suite 4] Command Transparency & Exact Execution Parity
- **Test 4.1:** Ollama Local Engine: exact command (`brew install ollama && ollama serve`), license `MIT` &rarr; **PASS**
- **Test 4.2:** Qwen 2.5 (7B Instruct): exact command (`ollama pull qwen2.5:7b`), license `Apache 2.0` &rarr; **PASS**
- **Test 4.3:** Whisper Multilingual Core: exact command (`voiceai models install whisper-small-multilingual`), license `MIT` &rarr; **PASS**
- **Test 4.4:** Neural Spoken Voice: exact command (`voiceai models install voice-piper-en-hi`), license `MIT` &rarr; **PASS**

### [Suite 5] Local Model Download Manager & Auto-Configuration
- **Test 5.1:** Multi-item installation queueing & state transitions &rarr; **PASS**
- **Test 5.2:** SHA-256 hash validation against signed catalog &rarr; **PASS**
- **Test 5.3:** Download progress tracking & auto-mark Ready &rarr; **PASS**
- **Test 5.4:** Automated configuration switching active ModelRouter to Local Mode &rarr; **PASS**

---

## Regression Verification Summary

| Test Suite | Tests Run | Passed | Failed | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Setup & Auth Suite** (`test_setup_auth.swift`) | 34 | 34 | 0 | **100% PASS** |
| **Core Architecture Suite** (`test_all_features.swift`) | 184 | 184 | 0 | **100% PASS** |
| **Hindi & Hinglish Benchmark** (`test_hindi_control.swift`) | 125 | 125 | 0 | **100% PASS** |
| **Brain & Multimodal Provider Suite** (`test_ai_brain.swift`) | 28 | 28 | 0 | **100% PASS** |
| **TOTAL** | **371** | **371** | **0** | **100% PASS** |

