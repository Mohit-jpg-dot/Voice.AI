# Voice.AI Media & Screenshot Assets Guide

This directory holds official screenshots, social share cards, and media assets for the Voice.AI README, documentation hub, and website.

## Required Production Screenshots (Checklist for Manual Capture)

When capturing live screenshots from the running macOS application, use `Cmd+Shift+4` (Space) to capture with native macOS window drop shadows, or capture the Notch HUD directly from `IslandGalleryView`:

| File | Target Resolution | What to Show |
|---|---|---|
| `social-preview.png` | 1280 × 640 | Social card with dark glass theme, title, tagline, and feature badges (generated). |
| `notch-resting.png` | ~540 × 80 | Clean resting notch pill with subtle obsidian glass border and status indicator. |
| `notch-media.png` | ~620 × 96 | Active media playback wings (Spotify / YouTube) showing album artwork, song title, artist, and red equalizer bars. |
| `notch-shelf.png` | ~700 × 320 | Expanded Notch Shelf staging tray with multiple file tiles (`report.pdf`, images, text snippets) and drag-and-drop hot-zone. |
| `notch-approval.png` | ~640 × 260 | High-priority `.consequential` Tool Approval Card displaying action title, redacted parameter preview, and Cancel / Approve buttons. |
| `email-composer.png` | ~520 × 275 | Liquid obsidian email compose card showing Gmail/Mail recipient capsule chip, subject line, body preview, and blue Send pill. |

> **Note**: In headless test environments or until live Retina display captures are taken, README and web docs use structured SVG/CSS native UI previews and verified text tables to ensure zero fabricated or misleading imagery is presented to users.

