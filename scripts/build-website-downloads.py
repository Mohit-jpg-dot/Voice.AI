#!/usr/bin/env python3
"""
Build Website Downloads Script for Voice.AI
Reads website/latest.json, VERSION, and CHANGELOG.md.
Updates website/release.js and website/download.html to ensure zero version drift.
"""

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WEBSITE_DIR = ROOT / "website"
LATEST_JSON = WEBSITE_DIR / "latest.json"
RELEASE_JS = WEBSITE_DIR / "release.js"
DOWNLOAD_HTML = WEBSITE_DIR / "download.html"
CHANGELOG = ROOT / "CHANGELOG.md"


def main():
    if not LATEST_JSON.exists():
        raise SystemExit(f"Missing {LATEST_JSON}")

    with open(LATEST_JSON, "r", encoding="utf-8") as f:
        meta = json.load(f)

    version = meta["version"]
    build_num = str(meta.get("buildNumber", "43"))
    file_name = meta["fileName"]
    file_size = meta["fileSizeBytes"]
    sha256 = meta["sha256"]
    download_url = meta.get("downloadUrl", f"downloads/{file_name}")

    print(f"Updating website assets for Voice.AI v{version} (Build {build_num})...")

    # 1. Update website/release.js fallback metadata
    if RELEASE_JS.exists():
        content = RELEASE_JS.read_text(encoding="utf-8")

        # Replace FALLBACK_METADATA block
        new_fallback = f"""  const FALLBACK_METADATA = {{
    version: '{version}',
    buildNumber: '{build_num}',
    fileName: '{file_name}',
    fileSizeBytes: {file_size},
    sha256: '{sha256}',
    downloadUrl: '{download_url}'
  }};"""

        content = re.sub(
            r"  const FALLBACK_METADATA = \{[^}]+\};",
            new_fallback,
            content,
            flags=re.DOTALL
        )
        RELEASE_JS.write_text(content, encoding="utf-8")
        print("  ✓ Updated website/release.js fallback metadata")

    # 2. Update website/download.html
    if DOWNLOAD_HTML.exists():
        html = DOWNLOAD_HTML.read_text(encoding="utf-8")

        # Replace checksum and version displays
        html = re.sub(
            r'data-release-version="[^"]*"',
            f'data-release-version="{version}"',
            html
        )
        html = re.sub(
            r'id="mac-download-button"\s+href="[^"]*"',
            f'id="mac-download-button" href="{download_url}"',
            html
        )
        html = re.sub(
            r'id="dmg-sha256-hash">[^<]*<',
            f'id="dmg-sha256-hash">{sha256}<',
            html
        )
        DOWNLOAD_HTML.write_text(html, encoding="utf-8")
        print("  ✓ Updated website/download.html links and checksum")

    print("Website downloads build complete.")


if __name__ == "__main__":
    main()
