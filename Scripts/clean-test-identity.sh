#!/bin/zsh
# Removes the preferences, caches and Application Support folders macOS keeps
# for WorkFlow test bundle identities (see Scripts/test-identity.zsh).
#
# Usage: clean-test-identity.sh [BUNDLE_ID...]
#
# With bundle ids, removes each one's state; every id must be a
# com.picturesuo.WorkFlow.fmtest.* or nmtest.* identity. With none, removes
# only the state of per-run identities (fmtest.run<pid>, fmtest.bench<pid>,
# nmtest.run<pid>) whose process has ended.
set -euo pipefail

source "${0:A:h}/test-identity.zsh"

if (( $# == 0 )); then
    wf_test_identity_sweep_stale
    exit 0
fi
for id in "$@"; do
    if ! wf_test_identity_is_valid "$id"; then
        print -u2 -r -- "clean-test-identity: refusing $id (not a com.picturesuo.WorkFlow.fmtest or nmtest identity)"
        exit 2
    fi
done
for id in "$@"; do
    wf_test_identity_remove "$id"
done
