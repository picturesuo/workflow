#!/bin/zsh
# Runs WorkFlow's headless XCTest suite under a per-run test bundle identity
# and removes everything macOS kept for that identity when the run ends,
# whether the tests pass, fail, or are interrupted.
#
# Usage: Scripts/test.sh [xcodebuild arguments...]
#
# With no -only-testing or -skip-testing argument it runs the complete safe
# headless suite with its required local skips; with one, it runs exactly the
# selection given. Other arguments are passed to xcodebuild test.
#
# The identity defaults to com.picturesuo.WorkFlow.fmtest.run<pid>, so the
# test host never reads or changes WorkFlow's own preferences or History and
# concurrent runs never share a preferences domain. Set
# WORKFLOW_TEST_BUNDLE_ID to another com.picturesuo.WorkFlow.fmtest.* id to
# choose one; its state is removed afterwards only when this run created it.
# Each run also removes the state of earlier fmtest.run<pid> runs whose
# process has ended, so a run that was killed outright is cleaned up later.
set -euo pipefail

ROOT=${0:A:h:h}
cd "$ROOT"
source "$ROOT/Scripts/test-identity.zsh"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}

wf_test_identity_sweep_stale

if [[ -n ${WORKFLOW_TEST_BUNDLE_ID:-} ]]; then
    bundle_id=$WORKFLOW_TEST_BUNDLE_ID
    if [[ $bundle_id != com.picturesuo.WorkFlow.fmtest* ]] || ! wf_test_identity_is_valid "$bundle_id"; then
        print -u2 -r -- "test.sh: WORKFLOW_TEST_BUNDLE_ID must be a com.picturesuo.WorkFlow.fmtest.* identity, not $bundle_id"
        exit 2
    fi
    owns_identity=true
    if wf_test_identity_has_state "$bundle_id"; then
        owns_identity=false
        print -u2 -r -- "test.sh: $bundle_id already has preferences or caches; keeping them after this run"
    fi
else
    bundle_id="com.picturesuo.WorkFlow.fmtest.run$$"
    owns_identity=true
fi

host="$ROOT/build/Build/Products/Debug/WorkFlow.app/Contents/MacOS/WorkFlow"
cleanup() {
    local exit_status=$?
    trap - EXIT INT TERM HUP
    # An interrupted xcodebuild can leave its test host running, and the host
    # would recreate its caches after they are removed.
    if pkill -TERM -f "^$host( |$)" 2>/dev/null; then
        local deadline=$(( SECONDS + 10 ))
        while pgrep -f "^$host( |$)" >/dev/null && (( SECONDS < deadline )); do sleep 0.2; done
        pkill -KILL -f "^$host( |$)" 2>/dev/null || true
    fi
    if $owns_identity; then
        wf_test_identity_remove "$bundle_id" || true
    fi
    exit $exit_status
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

selection=()
if (( ! ${@[(I)-(only|skip)-testing:*]} )); then
    selection=(
        -only-testing:OpenSuperWhisperTests
        -skip-testing:OpenSuperWhisperTests/ClipboardUtilPasteIntegrationTests
        -skip-testing:OpenSuperWhisperTests/ClipboardUtilKeyboardLayoutTests
        -skip-testing:OpenSuperWhisperTests/KeyboardLayoutProviderTests
        -skip-testing:OpenSuperWhisperTests/IndicatorWindowGeometryTests/testWindowKeepsPanelSizeAfterPresent
        -skip-testing:OpenSuperWhisperTests/ClipboardRestoreTests/testMissingTargetDoesNotRedirectPasteAndKeepsTranscriptOnClipboard
    )
fi

print -u2 -r -- "test.sh: running under $bundle_id"
xcodebuild test \
    -scheme OpenSuperWhisper \
    -derivedDataPath build \
    -clonedSourcePackagesDirPath SourcePackages \
    -destination 'platform=macOS,arch=arm64' \
    "${selection[@]}" \
    "$@" \
    CODE_SIGNING_ALLOWED=NO \
    PRODUCT_BUNDLE_IDENTIFIER="$bundle_id"
