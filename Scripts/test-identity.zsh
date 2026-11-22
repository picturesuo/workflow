# Per-run test bundle identities and the per-user state macOS keeps for them.
#
# Source this file from zsh. The test host and perf builds run under their own
# bundle identifier (com.picturesuo.WorkFlow.fmtest.*) so they never touch
# WorkFlow's preferences or History. macOS keys several caches by bundle id and
# never removes them: CoreML's compiled-model cache alone
# (~/Library/Caches/<id>/com.apple.e5rt.e5bundlecache) is 0.3-21 GB per id, so
# a fresh id per run fills the disk unless each run removes what it created.

# Only test identities, never WorkFlow's own or a legacy identity.
wf_test_identity_is_valid() {
    [[ $1 =~ '^com\.picturesuo\.WorkFlow\.(fmtest|nmtest)[.-][A-Za-z0-9.-]+$' ]]
}

# Every per-user location macOS or the app creates for a bundle id.
wf_test_identity_paths() {
    local id=$1
    local user_cache user_temp
    user_cache=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null) || user_cache=
    user_temp=$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null) || user_temp=
    print -rl -- \
        "$HOME/Library/Caches/$id" \
        "$HOME/Library/Application Support/$id" \
        "$HOME/Library/Preferences/$id.plist" \
        "$HOME/Library/HTTPStorages/$id" \
        "$HOME/Library/HTTPStorages/$id.binarycookies" \
        "$HOME/Library/Saved Application State/$id.savedState" \
        "$HOME/Library/WebKit/$id"
    [[ -n $user_cache ]] && print -r -- "${user_cache%/}/$id"
    [[ -n $user_temp ]] && print -r -- "${user_temp%/}/$id"
    return 0
}

# True when anything exists for the identity, its defaults domain included.
wf_test_identity_has_state() {
    local id=$1 item
    defaults read "$id" >/dev/null 2>&1 && return 0
    for item in "${(@f)$(wf_test_identity_paths "$id")}"; do
        [[ -e $item || -L $item ]] && return 0
    done
    return 1
}

# Deletes the identity's defaults domain and every per-user folder for it.
wf_test_identity_remove() {
    local id=$1 item
    if ! wf_test_identity_is_valid "$id"; then
        print -u2 -r -- "test-identity: refusing to remove state for $id (not a com.picturesuo.WorkFlow.fmtest or nmtest identity)"
        return 2
    fi
    defaults delete "$id" >/dev/null 2>&1 || true
    for item in "${(@f)$(wf_test_identity_paths "$id")}"; do
        [[ -e $item || -L $item ]] && rm -rf -- "$item"
    done
    return 0
}

# Removes the state of per-run identities whose run has ended. The headless
# runner and the documented hand-run commands name these identities after the
# PID of the shell running them (fmtest.run<pid>, fmtest.bench<pid>,
# nmtest.run<pid>), so a missing process means the run is over, including one
# that was SIGKILLed before its exit trap could clean up. A live PID, even a
# reused one, keeps its state. fmtest.perf<pid> is left to the perf scripts,
# since run-benchmark.sh --skip-build reuses an earlier run's identity.
wf_test_identity_sweep_stale() {
    local user_cache root entry id pid
    local -a roots
    local -A seen
    user_cache=$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null) || user_cache=
    roots=("$HOME/Library/Caches" "$HOME/Library/Application Support" "$HOME/Library/Preferences")
    [[ -n $user_cache ]] && roots+=("${user_cache%/}")
    for root in $roots; do
        for entry in "$root"/com.picturesuo.WorkFlow.(fmtest.run|fmtest.bench|nmtest.run)<->(|.plist)(N); do
            id=${${entry:t}%.plist}
            [[ -n ${seen[$id]-} ]] && continue
            seen[$id]=1
            pid=${id##*[^0-9]}
            [[ -n $pid ]] || continue
            ps -p "$pid" >/dev/null 2>&1 && continue
            wf_test_identity_remove "$id"
        done
    done
    return 0
}
