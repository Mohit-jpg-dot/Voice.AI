#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Voice.AI Unified Test Runner
# Runs individual or all test suites cleanly without cluttering build/
# Usage: ./scripts/run-tests.sh [all|core|brain|auth|google|hindi]
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build"
OBJ_DIR="${BUILD_DIR}/obj"
TARGET="${1:-all}"
TMP_RUNNER="/tmp/voice_ai_test_runner"

if [ ! -f "${OBJ_DIR}/libVoiceOSCore.dylib" ]; then
    echo "VoiceOSCore not compiled yet. Running build-app.sh first..."
    bash "${SCRIPT_DIR}/build-app.sh"
fi

SWIFT_FLAGS=(
    -target arm64-apple-macosx14.0
    -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
    -module-cache-path /tmp/clang_cache
    -I "${OBJ_DIR}"
    -L "${OBJ_DIR}"
    -lVoiceOSCore
    -Xlinker -rpath -Xlinker "${OBJ_DIR}"
)

run_suite() {
    local name="$1"
    local source="$2"
    local as_lib="$3"
    
    echo "================================================================="
    echo "Running Test Suite: ${name}"
    echo "================================================================="
    
    rm -f "${TMP_RUNNER}"
    if [ "${as_lib}" = "true" ]; then
        swiftc -parse-as-library "${SWIFT_FLAGS[@]}" "${source}" -o "${TMP_RUNNER}"
    else
        swiftc "${SWIFT_FLAGS[@]}" "${source}" -o "${TMP_RUNNER}"
    fi
    
    VOICE_AI_TEST_MODE=1 "${TMP_RUNNER}"
    rm -f "${TMP_RUNNER}"
    echo ""
}

case "${TARGET}" in
    core)
        run_suite "VoiceOS Core Suites" "${ROOT_DIR}/Tests/core/test_core.swift" false
        ;;
    brain)
        run_suite "AI Brain & Provider Routing" "${ROOT_DIR}/Tests/ai-brain/test_brain.swift" true
        ;;
    auth)
        run_suite "Setup & Authentication" "${ROOT_DIR}/Tests/setup_and_auth/test_setup_auth.swift" true
        ;;
    google)
        run_suite "Google Search & Math Engine" "${ROOT_DIR}/Tests/google_mode/test_google_mode.swift" true
        ;;
    hindi)
        run_suite "Hindi & Hinglish Natural Commands" "${ROOT_DIR}/Tests/hindi_commands/test_runner.swift" false
        ;;
    all)
        echo "Running All Voice.AI Test Suites..."
        run_suite "VoiceOS Core Suites" "${ROOT_DIR}/Tests/core/test_core.swift" false
        run_suite "AI Brain & Provider Routing" "${ROOT_DIR}/Tests/ai-brain/test_brain.swift" true
        run_suite "Setup & Authentication" "${ROOT_DIR}/Tests/setup_and_auth/test_setup_auth.swift" true
        run_suite "Google Search & Math Engine" "${ROOT_DIR}/Tests/google_mode/test_google_mode.swift" true
        run_suite "Hindi & Hinglish Natural Commands" "${ROOT_DIR}/Tests/hindi_commands/test_runner.swift" false
        echo "================================================================="
        echo "✓ All Voice.AI test suites completed successfully!"
        echo "================================================================="
        ;;
    *)
        echo "Unknown target: ${TARGET}"
        echo "Usage: ./scripts/run-tests.sh [all|core|brain|auth|google|hindi]"
        exit 1
        ;;
esac

