#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Voice.AI Version Consistency Checker
# Validates that all sources of truth agree on the current release version.
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

VERSION_FILE="${ROOT_DIR}/VERSION"
if [ ! -f "${VERSION_FILE}" ]; then
  echo "❌ FAILED: VERSION file missing at ${VERSION_FILE}"
  exit 1
fi

EXPECTED_VERSION=$(cat "${VERSION_FILE}" | tr -d '[:space:]')
echo "================================================================="
echo "Checking Version Consistency across Voice.AI (Target: ${EXPECTED_VERSION})"
echo "================================================================="

FAILURES=0

check_match() {
  local file="$1"
  local pattern="$2"
  local desc="$3"

  if [ ! -f "${file}" ]; then
    echo "❌ [MISSING] ${file}"
    FAILURES=$((FAILURES + 1))
    return
  fi

  if grep -q "${pattern}" "${file}"; then
    echo "  ✓ PASS: ${desc} in ${file#$ROOT_DIR/}"
  else
    echo "  ✗ FAIL: ${desc} NOT matched in ${file#$ROOT_DIR/}"
    FAILURES=$((FAILURES + 1))
  fi
}

# 1. Check release/config.json
check_match "${ROOT_DIR}/release/config.json" "\"version\": \"${EXPECTED_VERSION}\"" "release/config.json version"
check_match "${ROOT_DIR}/release/config.json" "\"dmgName\": \"Voice.AI-${EXPECTED_VERSION}.dmg\"" "release/config.json dmgName"

# 2. Check website/latest.json
check_match "${ROOT_DIR}/website/latest.json" "\"version\": \"${EXPECTED_VERSION}\"" "website/latest.json version"
check_match "${ROOT_DIR}/website/latest.json" "\"fileName\": \"Voice.AI-${EXPECTED_VERSION}.dmg\"" "website/latest.json fileName"

# 3. Check website/downloads/latest.json
check_match "${ROOT_DIR}/website/downloads/latest.json" "\"version\": \"${EXPECTED_VERSION}\"" "website/downloads/latest.json version"
check_match "${ROOT_DIR}/website/downloads/latest.json" "\"fileName\": \"Voice.AI-${EXPECTED_VERSION}.dmg\"" "website/downloads/latest.json fileName"

# 4. Check CHANGELOG.md has an entry for this version
check_match "${ROOT_DIR}/CHANGELOG.md" "## \[${EXPECTED_VERSION}\]" "CHANGELOG.md entry ## [${EXPECTED_VERSION}]"

echo "================================================================="
if [ "${FAILURES}" -eq 0 ]; then
  echo "✓ All version checks PASSED (100% consistent with VERSION: ${EXPECTED_VERSION})"
  exit 0
else
  echo "❌ ${FAILURES} version consistency check(s) FAILED"
  exit 1
fi
