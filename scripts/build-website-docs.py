#!/usr/bin/env python3
"""
Builds website/docs-data.js from the repository's Markdown documentation files
so website/docs.html works interactively offline (file://) and on GitHub Pages.
"""

import json
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT_FILE = ROOT / "website" / "docs-data.js"

DOC_SPECS = [
    # Overview & Getting Started
    ("overview", "Overview", "Voice.AI Overview & Status", "README.md", "macOS & Windows"),
    ("sitemap", "Overview", "Documentation Sitemap", "docs/index.md", "Index"),
    ("how-to-grant-permissions", "Overview", "Granting macOS Permissions", "docs/how-to-grant-permissions.md", "macOS"),
    ("readme-hi", "Overview", "हिन्दी क्विकस्टार्ट (Hindi Guide)", "README.hi.md", "हिन्दी"),
    ("changelog", "Overview", "Release Changelog", "CHANGELOG.md", "Releases"),

    # Setup & Modes
    ("setup-free-offline", "Setup & Modes", "Free & Offline Setup (macOS)", "docs/setup-free-offline.md", "Private / Free"),
    ("setup-free-offline-windows", "Setup & Modes", "Free & Offline Setup (Windows)", "docs/setup-free-offline-windows.md", "Windows"),
    ("setup-ollama", "Setup & Modes", "Local AI with Ollama & Whisper", "docs/setup-ollama.md", "On-Device"),
    ("setup-api-key", "Setup & Modes", "Cloud API Key Quickstart", "docs/setup-api-key.md", "Cloud BYOK"),
    ("setup-cloud", "Setup & Modes", "Cloud Providers (OpenAI, Claude, Gemini)", "docs/setup-cloud.md", "Cloud"),
    ("setup-google-search-key", "Setup & Modes", "Google Custom Search Setup", "docs/setup-google-search-key.md", "Free Search"),
    ("windows-dev-setup", "Setup & Modes", "Windows Dev & WinUI 3 Setup", "docs/windows-dev-setup.md", ".NET 8 / WinUI 3"),

    # JARVIS Phases 0-3
    ("phase-0-foundations", "Phases 0-3", "Phase 0: ToolRegistry, EventBus & Memory", "docs/phase-0-foundations.md", "Phase 0"),
    ("phase-1-jarvis-feel", "Phases 0-3", "Phase 1: JARVIS Feel & Routines", "docs/phase-1-jarvis-feel.md", "Phase 1"),
    ("phase-2-proactive-assistant", "Phases 0-3", "Phase 2: Proactive Assistant & RAG", "docs/phase-2-proactive-assistant.md", "Phase 2"),
    ("phase-3-advanced", "Phases 0-3", "Phase 3: Iron Legion, CAD & Security", "docs/phase-3-advanced.md", "Phase 3"),

    # Architecture & Notch UI
    ("architecture-cross-platform", "Architecture & Notch", "Cross-Platform Architecture", "docs/architecture-cross-platform.md", "Core Spec"),
    ("google-mode-decision", "Architecture & Notch", "Google Search Mode Decision Record", "docs/google-mode-decision.md", "ADR"),
    ("notch-01-window-geometry", "Architecture & Notch", "Notch 01: Window & Geometry", "docs/notch-study/01-window-and-geometry.md", "Notch Study"),
    ("notch-02-animations-springs", "Architecture & Notch", "Notch 02: Physics & Springs", "docs/notch-study/02-animations-and-springs.md", "Notch Study"),
    ("notch-03-hover-gestures", "Architecture & Notch", "Notch 03: Hover & Gesture Tracking", "docs/notch-study/03-hover-gestures-and-tracking.md", "Notch Study"),
    ("notch-04-live-activities", "Architecture & Notch", "Notch 04: Live Activities & Wings", "docs/notch-study/04-live-activities-and-wings.md", "Notch Study"),
    ("notch-05-open-layout", "Architecture & Notch", "Notch 05: Open Layout & Chrome", "docs/notch-study/05-open-layout-and-chrome.md", "Notch Study"),
    ("notch-06-adaptation-matrix", "Architecture & Notch", "Notch 06: Voice.AI Adaptation Matrix", "docs/notch-study/06-voiceos-adaptation-matrix.md", "Notch Study"),

    # Tests & Verification
    ("real-test", "Tests & QA", "Computer-Use Agent QA Matrix", "real-test.md", "Computer Use"),
    ("hindi-control-report", "Tests & QA", "Hindi & Hinglish Control (125+)", "docs/hindi-control-report.md", "125/125"),
    ("test-report", "Tests & QA", "Core Verification Test Report", "docs/test-report.md", "Core Suite"),
    ("test-report-ai-brain", "Tests & QA", "AI Brain Benchmark Report", "docs/test-report-ai-brain.md", "Brain Suite"),
    ("test-report-google-mode", "Tests & QA", "Google Search Mode Test Report", "docs/test-report-google-mode.md", "Google Suite"),
    ("test-report-setup", "Tests & QA", "Auth & Onboarding Test Report", "docs/test-report-setup.md", "Auth Suite"),
    ("test-report-windows", "Tests & QA", "Windows Platform Parity Report", "docs/test-report-windows.md", ".NET Tests"),
    ("diagnosis", "Tests & QA", "Pipeline Diagnosis & Root Cause", "docs/diagnosis.md", "Diagnostics"),
    ("diagnosis-ai-brain", "Tests & QA", "AI Brain Diagnosis & Gap Analysis", "docs/diagnosis-ai-brain.md", "Diagnostics"),

    # Security & Governance
    ("security", "Security & Project", "Security & Threat Model", "SECURITY.md", "Security"),
    ("contributing", "Security & Project", "Contributing Guidelines", "CONTRIBUTING.md", "Community"),
    ("third-party-notices", "Security & Project", "Third-Party Notices", "THIRD_PARTY_NOTICES.md", "Notices"),
    ("code-of-conduct", "Security & Project", "Code of Conduct", "CODE_OF_CONDUCT.md", "Policy"),
]


def extract_excerpt(markdown_text: str) -> str:
    for raw_line in markdown_text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith(("#", "```", "|", "---", "![", "[![", "<", "┌", "│", "├", "└")):
            continue
        cleaned = re.sub(r"^>\s*", "", line)
        cleaned = re.sub(r"\[([^\]]+)\]\([^\)]+\)", r"\1", cleaned)
        cleaned = re.sub(r"[*_`]", "", cleaned).strip()
        if len(cleaned) >= 24:
            return cleaned[:160] + ("…" if len(cleaned) > 160 else "")
    return "Voice.AI engineering and user documentation."


def main() -> None:
    entries = []
    for doc_id, category, title, rel_path, badge in DOC_SPECS:
        file_path = ROOT / rel_path
        if not file_path.is_file():
            raise FileNotFoundError(f"Missing documentation source: {file_path}")
        markdown = file_path.read_text(encoding="utf-8")
        words = len(markdown.split())
        read_minutes = max(1, round(words / 210))
        entries.append({
            "id": doc_id,
            "category": category,
            "title": title,
            "path": rel_path,
            "badge": badge,
            "words": words,
            "readMinutes": read_minutes,
            "excerpt": extract_excerpt(markdown),
            "markdown": markdown,
        })

    payload = json.dumps(entries, ensure_ascii=False)
    # Prevent closing </script> if markdown code samples ever mention it
    payload = payload.replace("</script>", "<\\/script>")
    OUT_FILE.write_text(
        "// Auto-generated by scripts/build-website-docs.py — do not hand-edit.\n"
        f"window.VOICE_AI_DOCS = {payload};\n",
        encoding="utf-8",
    )
    print(f"Generated {OUT_FILE.relative_to(ROOT)} with {len(entries)} documents.")


if __name__ == "__main__":
    main()
