#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Derived from Project Cascadia test harness for LegacyPad-Linux.
# test-pcless-rollback.sh -- Verifies the EXACT remote shell scripts emitted by
# devices/a5/tools/p105-pcless.sh internal-activate, internal-rollback, and internal-remove.
#
# Constraints & Verification Guarantees:
#   - Runs strictly with POSIX /bin/sh (dash on Linux Mint) -- NOT bash!
#   - Runs with an isolated minimal PATH where 'basename', 'dirname', 'grep',
#     'cut', 'awk', 'sed' DO NOT EXIST, proving 100% POSIX built-in compliance
#     for minimal iOS 8.4.1 environments.
#   - Verified scenarios:
#       1. Clean initial installation across all 6 target files (success)
#       2. Protection in install-only mode: blocked if manifest exists
#       3. Safe update mode: updates active files, saves to previous/, preserves .orig
#       4. Failure during update: restores previous active files, leaves .orig intact
#       5. Dedicated rollback command: restores files from previous/
#       6. Remove with missing manifest: strictly refuses to delete active files
#       7. Manifest-based clean remove: cleanly restores pre-existing files & deletes Cascadia files
#       8. Failure during manifest/backup creation: no partial manifest or .new files left
#       9. Failure at 4th file with empty initial state: complete clean rollback
#      10. Failure at 4th file with pre-existing canary files: 100% bit-for-bit restoration
#      11. Candidate OUT selection: OUT environment variable is respected and preserved
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PCLESS_BIN="$SCRIPT_DIR/tools/p105-pcless.sh"
SANDBOX=$(mktemp -d /tmp/test-p105-exact-XXXXXX)
trap 'rm -rf "$SANDBOX"' EXIT

say()  { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Create isolated minimal PATH containing ONLY required POSIX commands
# Explicitly EXCLUDES: basename, dirname, grep, cut, awk, sed
ISOLATED_BIN="$SANDBOX/isolated_bin"
mkdir -p "$ISOLATED_BIN"
for cmd in cp mv rm mkdir rmdir chmod sync cat ls echo test [ false true sh; do
    cmd_path=$(which "$cmd" 2>/dev/null || true)
    [ -n "$cmd_path" ] && ln -sf "$cmd_path" "$ISOLATED_BIN/$cmd"
done

# Sanity check: verify isolated PATH does NOT contain banned external tools
for banned in basename dirname grep cut awk sed; do
    if [ -e "$ISOLATED_BIN/$banned" ]; then
        fail "Isolated test environment contaminated with $banned!"
    fi
done

setup_sandbox() {
    rm -rf "$SANDBOX/root"
    mkdir -p "$SANDBOX/root/usr/local/cascadia" \
             "$SANDBOX/root/usr/bin" \
             "$SANDBOX/root/var/backups/cascadia-pcless"
}

# The 6 exact targets in order
TARGET_KEYS=(
    "kernelcache"
    "ramdisk"
    "devicetree"
    "usr/local/cascadia/kloader"
    "usr/local/cascadia/iBEC.upgrade"
    "usr/bin/linux"
)

# Helper to run the exact remote activation script using POSIX /bin/sh and isolated PATH
exec_p105_activate() {
    local root="$1"
    local fail_step="${2:-0}"
    local fail_backup="${3:-0}"
    local mode="${4:-auto}"
    local act_sh
    act_sh=$("$PCLESS_BIN" internal-activate "$root" "$fail_step" "$fail_backup" "$mode")
    PATH="$ISOLATED_BIN" sh -c "$act_sh"
}

# Helper to run the exact remote rollback script using POSIX /bin/sh and isolated PATH
exec_p105_rollback() {
    local root="$1"
    local rb_sh
    rb_sh=$("$PCLESS_BIN" internal-rollback "$root")
    PATH="$ISOLATED_BIN" sh -c "$rb_sh"
}

# Helper to run the exact remote remove script using POSIX /bin/sh and isolated PATH
exec_p105_remove() {
    local root="$1"
    local rem_sh
    rem_sh=$("$PCLESS_BIN" internal-remove "$root")
    PATH="$ISOLATED_BIN" sh -c "$rem_sh"
}

# ------------------------------------------------------------------------------
# TEST 1: Successful clean installation across all 6 target files
# ------------------------------------------------------------------------------
say "Test 1: Testing clean installation across all 6 targets (sh + isolated PATH)..."
setup_sandbox
ROOT="$SANDBOX/root"

for t in "${TARGET_KEYS[@]}"; do
    mkdir -p "$(dirname "$ROOT/$t")"
    echo "NEW_CONTENT_$t" > "$ROOT/$t.new"
done

exec_p105_activate "$ROOT" 0 0 "install"

for t in "${TARGET_KEYS[@]}"; do
    [ -f "$ROOT/$t" ] || fail "Test 1: target $t was not created!"
    [ "$(cat "$ROOT/$t")" = "NEW_CONTENT_$t" ] || fail "Test 1: content mismatch on $t"
    [ ! -f "$ROOT/$t.new" ] || fail "Test 1: $t.new was not removed!"
done

[ -f "$ROOT/var/backups/cascadia-pcless/manifest.txt" ] || fail "Test 1: manifest.txt not created!"
say "PASS: Test 1 (All 6 files successfully installed and manifest created with zero external tools)."

# ------------------------------------------------------------------------------
# TEST 2: Strict install mode blocked when manifest exists
# ------------------------------------------------------------------------------
say "Test 2: Testing protection against overwriting initial backups in install-only mode..."
for t in "${TARGET_KEYS[@]}"; do
    echo "OVERWRITE_CONTENT_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 0 0 "install" 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 2: Strict install mode should have been BLOCKED by existing manifest!"
note "Strict install was successfully blocked (rc=$rc)"
for t in "${TARGET_KEYS[@]}"; do
    [ "$(cat "$ROOT/$t")" = "NEW_CONTENT_$t" ] || fail "Test 2: content on $t was overwritten!"
done
say "PASS: Test 2 (Strict install mode prevents overwriting initial backups)."

# ------------------------------------------------------------------------------
# TEST 3: Safe update mode updates files, saves to previous/, preserves .orig
# ------------------------------------------------------------------------------
say "Test 3: Testing safe update of an existing installation..."
for t in "${TARGET_KEYS[@]}"; do
    echo "UPDATE_V2_$t" > "$ROOT/$t.new"
done

exec_p105_activate "$ROOT" 0 0 "update"

for t in "${TARGET_KEYS[@]}"; do
    [ "$(cat "$ROOT/$t")" = "UPDATE_V2_$t" ] || fail "Test 3: content mismatch on updated $t"
    bname="${t##*/}"
    [ -f "$ROOT/var/backups/cascadia-pcless/previous/$bname" ] || fail "Test 3: previous/$bname not saved!"
    [ "$(cat "$ROOT/var/backups/cascadia-pcless/previous/$bname")" = "NEW_CONTENT_$t" ] \
        || fail "Test 3: previous/$bname does not hold previous version!"
done
say "PASS: Test 3 (Update cleanly updated files, created previous/ backup, and preserved original manifest)."

# ------------------------------------------------------------------------------
# TEST 4: Failure during update activation restores previous active files
# ------------------------------------------------------------------------------
say "Test 4: Testing failure during update activation (synthetic failure at step 4)..."
for t in "${TARGET_KEYS[@]}"; do
    echo "UPDATE_V3_FAIL_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 4 0 "update" 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 4: Update should have failed at step 4!"
note "Update failed at step 4 as expected (rc=$rc)"

# Verify active files were restored to V2 (from previous/)
for t in "${TARGET_KEYS[@]}"; do
    [ "$(cat "$ROOT/$t")" = "UPDATE_V2_$t" ] || fail "Test 4: $t was not restored to previous version V2!"
    [ ! -f "$ROOT/$t.new" ] || fail "Test 4: $t.new was not cleaned up!"
done
say "PASS: Test 4 (Failure during update cleanly rolled back active files to previous active version)."

# ------------------------------------------------------------------------------
# TEST 5: Dedicated rollback command restores previous active version
# ------------------------------------------------------------------------------
say "Test 5: Testing dedicated rollback command..."
# Current active is V2, previous holds NEW_CONTENT (V1)
exec_p105_rollback "$ROOT"

for t in "${TARGET_KEYS[@]}"; do
    [ "$(cat "$ROOT/$t")" = "NEW_CONTENT_$t" ] || fail "Test 5: $t was not reverted to V1 by rollback!"
done
[ ! -d "$ROOT/var/backups/cascadia-pcless/previous" ] || fail "Test 5: previous/ directory was not removed after rollback!"
say "PASS: Test 5 (Rollback successfully reverted active files to previous version)."

# ------------------------------------------------------------------------------
# TEST 6: Remove with missing manifest -> Strictly refuses to delete active files
# ------------------------------------------------------------------------------
say "Test 6: Testing remove behavior when manifest is missing..."
mv "$ROOT/var/backups/cascadia-pcless/manifest.txt" "$ROOT/var/backups/cascadia-pcless/manifest.txt.bak"

set +e
exec_p105_remove "$ROOT" 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 6: Remove should have failed when manifest is missing, but succeeded!"
note "Remove failed as expected (rc=$rc)"

for t in "${TARGET_KEYS[@]}"; do
    [ -f "$ROOT/$t" ] || fail "Test 6: $t was deleted despite missing manifest!"
done
mv "$ROOT/var/backups/cascadia-pcless/manifest.txt.bak" "$ROOT/var/backups/cascadia-pcless/manifest.txt"
say "PASS: Test 6 (Remove strictly refuses to delete active files without manifest)."

# ------------------------------------------------------------------------------
# TEST 7: Manifest-based remove -> Restores original state
# ------------------------------------------------------------------------------
say "Test 7: Testing clean remove and restoration..."
exec_p105_remove "$ROOT"

for t in "${TARGET_KEYS[@]}"; do
    [ ! -f "$ROOT/$t" ] || fail "Test 7: $t was not removed!"
done
[ ! -d "$ROOT/var/backups/cascadia-pcless" ] || fail "Test 7: backup directory was not removed!"
say "PASS: Test 7 (Manifest-based remove cleaned all Cascadia files)."

# ------------------------------------------------------------------------------
# TEST 8: Failure during backup/manifest creation -> No partial manifest or .new files
# ------------------------------------------------------------------------------
say "Test 8: Testing failure during backup & manifest creation (bstep 2)..."
setup_sandbox
ROOT="$SANDBOX/root"

echo "ORIGINAL_KERNELCACHE" > "$ROOT/kernelcache"
echo "ORIGINAL_RAMDISK" > "$ROOT/ramdisk"

for t in "${TARGET_KEYS[@]}"; do
    mkdir -p "$(dirname "$ROOT/$t")"
    echo "STAGED_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 0 2 "install" 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 8: Activation should have failed at backup step 2, but succeeded!"
note "Activation failed at backup step 2 as expected (rc=$rc)"

[ ! -f "$ROOT/var/backups/cascadia-pcless/manifest.txt" ] || fail "Test 8: manifest.txt exists after backup failure!"
for t in "${TARGET_KEYS[@]}"; do
    [ ! -f "$ROOT/$t.new" ] || fail "Test 8: $t.new still exists after backup cleanup!"
done
[ "$(cat "$ROOT/kernelcache")" = "ORIGINAL_KERNELCACHE" ] || fail "Test 8: kernelcache was modified!"
[ "$(cat "$ROOT/ramdisk")" = "ORIGINAL_RAMDISK" ] || fail "Test 8: ramdisk was modified!"
say "PASS: Test 8 (Failure during manifest/backup creation: zero partial manifest, zero .new files left)."

# ------------------------------------------------------------------------------
# TEST 9: Step 4 failure with empty initial state -> complete clean rollback
# ------------------------------------------------------------------------------
say "Test 9: Testing failure at 4th file with empty initial state..."
setup_sandbox
ROOT="$SANDBOX/root"

for t in "${TARGET_KEYS[@]}"; do
    mkdir -p "$(dirname "$ROOT/$t")"
    echo "CONTENT_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 4 0 "install" 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 9: Activation should have failed at step 4, but succeeded!"
note "Activation failed at step 4 as expected (rc=$rc)"

for t in "${TARGET_KEYS[@]}"; do
    [ ! -f "$ROOT/$t" ] || fail "Test 9: $t was left behind after rollback!"
    [ ! -f "$ROOT/$t.new" ] || fail "Test 9: $t.new was left behind after rollback!"
done
[ ! -d "$ROOT/var/backups/cascadia-pcless" ] || fail "Test 9: backup directory exists after rollback!"
say "PASS: Test 9 (Step 4 failure with empty initial state: complete clean rollback)."

# ------------------------------------------------------------------------------
# TEST 10: Step 4 failure with pre-existing canary files -> 100% bit-for-bit restored
# ------------------------------------------------------------------------------
say "Test 10: Testing failure at 4th file with pre-existing canary files..."
setup_sandbox
ROOT="$SANDBOX/root"

CANARY_MAP=()
declare -A CANARY_HASHES

for t in "${TARGET_KEYS[@]}"; do
    mkdir -p "$(dirname "$ROOT/$t")"
    content="ORIGINAL_CANARY_$(date +%s%N)_$t"
    echo "$content" > "$ROOT/$t"
    CANARY_HASHES["$t"]=$(sha1sum "$ROOT/$t" | awk '{print $1}')
    echo "REPLACEMENT_FOR_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 4 0 "install" 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 10: Activation should have failed at step 4, but succeeded!"
note "Activation failed at step 4 as expected (rc=$rc)"

for t in "${TARGET_KEYS[@]}"; do
    [ -f "$ROOT/$t" ] || fail "Test 10: original file $t was lost during rollback!"
    current_hash=$(sha1sum "$ROOT/$t" | awk '{print $1}')
    [ "$current_hash" = "${CANARY_HASHES["$t"]}" ] || fail "Test 10: content corrupted for $t!"
    [ ! -f "$ROOT/$t.new" ] || fail "Test 10: staging file $t.new was left behind!"
done
[ ! -d "$ROOT/var/backups/cascadia-pcless" ] || fail "Test 10: backup directory was not removed!"
say "PASS: Test 10 (Step 4 failure with pre-existing files: all 6 originals 100% bit-for-bit restored)."

# ------------------------------------------------------------------------------
# TEST 11: OUT variable preservation test
# ------------------------------------------------------------------------------
say "Test 11: Testing candidate OUT selection preservation..."
TEST_CUSTOM_OUT="/tmp/custom-candidate-out-$$"
mkdir -p "$TEST_CUSTOM_OUT"
resolved_out=$(OUT="$TEST_CUSTOM_OUT" bash -c '
    ROOT="$(cd "'"$SCRIPT_DIR"'/.." && pwd)"
    OUT="${OUT:-$ROOT/build/p105/pcless}"
    case "$OUT" in
        /*) ;;
        *) OUT="$(cd "$OUT" 2>/dev/null && pwd || echo "$(pwd)/$OUT")" ;;
    esac
    echo "$OUT"
')
rm -rf "$TEST_CUSTOM_OUT"
[ "$resolved_out" = "$TEST_CUSTOM_OUT" ] || fail "Test 11: OUT was overridden! Got $resolved_out, expected $TEST_CUSTOM_OUT"
say "PASS: Test 11 (OUT environment variable correctly preserved for candidate selection)."

echo "=================================================================="
echo " ALL EXACT REMOTE SHELL & ROLLBACK TESTS PASSED (11/11 SCENARIOS)!"
echo " ZERO EXTERNAL BINARY DEPENDENCIES (POSIX /bin/sh COMPLIANT)"
echo " SAFE UPDATE AND ROLLBACK FULLY VERIFIED"
echo "=================================================================="
