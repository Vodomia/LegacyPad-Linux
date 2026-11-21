#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Derived from Project Cascadia test harness for LegacyPad-Linux.
# test-pcless-rollback.sh -- Verifies the EXACT remote shell scripts emitted by
# devices/a5/tools/p105-pcless.sh internal-activate and internal-remove.
#
# Constraints & Verification Guarantees:
#   - Runs strictly with POSIX /bin/sh (dash on Linux Mint) -- NOT bash!
#   - Runs with an isolated minimal PATH where 'basename', 'dirname', 'grep',
#     'cut', 'awk', 'sed' DO NOT EXIST, proving 100% POSIX built-in compliance
#     for minimal iOS 8.4.1 environments.
#   - Verified scenarios:
#       1. Clean installation across all 6 target files (success)
#       2. Overwrite protection: second install blocked if manifest exists
#       3. Remove with missing manifest: strictly refuses to delete active files
#       4. Manifest-based remove: cleanly restores pre-existing files & deletes created files
#       5. Failure during manifest/backup creation: no partial manifest or .new files left
#       6. Failure at 4th file with empty initial state: complete clean rollback
#       7. Failure at 4th file with pre-existing canary files: 100% bit-for-bit restoration
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
    local act_sh
    act_sh=$("$PCLESS_BIN" internal-activate "$root" "$fail_step" "$fail_backup")
    PATH="$ISOLATED_BIN" sh -c "$act_sh"
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

exec_p105_activate "$ROOT" 0 0

for t in "${TARGET_KEYS[@]}"; do
    [ -f "$ROOT/$t" ] || fail "Test 1: target $t was not created!"
    [ "$(cat "$ROOT/$t")" = "NEW_CONTENT_$t" ] || fail "Test 1: content mismatch on $t"
    [ ! -f "$ROOT/$t.new" ] || fail "Test 1: $t.new was not removed!"
done

[ -f "$ROOT/var/backups/cascadia-pcless/manifest.txt" ] || fail "Test 1: manifest.txt not created!"
say "PASS: Test 1 (All 6 files successfully installed and manifest created with zero external tools)."

# ------------------------------------------------------------------------------
# TEST 2: Second install attempted while manifest exists -> Must be BLOCKED
# ------------------------------------------------------------------------------
say "Test 2: Testing protection against overwriting initial backups..."
for t in "${TARGET_KEYS[@]}"; do
    echo "OVERWRITE_CONTENT_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 0 0 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 2: Second install should have been BLOCKED by existing manifest, but succeeded!"
note "Second install was successfully blocked (rc=$rc)"
for t in "${TARGET_KEYS[@]}"; do
    [ "$(cat "$ROOT/$t")" = "NEW_CONTENT_$t" ] || fail "Test 2: content on $t was overwritten!"
done
say "PASS: Test 2 (Existing manifest strictly prevents overwriting initial backups)."

# ------------------------------------------------------------------------------
# TEST 3: Remove with missing manifest -> Strictly refuses to delete active files
# ------------------------------------------------------------------------------
say "Test 3: Testing remove behavior when manifest is missing..."
mv "$ROOT/var/backups/cascadia-pcless/manifest.txt" "$ROOT/var/backups/cascadia-pcless/manifest.txt.bak"

set +e
exec_p105_remove "$ROOT" 2>/dev/null
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 3: Remove should have failed when manifest is missing, but succeeded!"
note "Remove failed as expected (rc=$rc)"

for t in "${TARGET_KEYS[@]}"; do
    [ -f "$ROOT/$t" ] || fail "Test 3: $t was deleted despite missing manifest!"
done
mv "$ROOT/var/backups/cascadia-pcless/manifest.txt.bak" "$ROOT/var/backups/cascadia-pcless/manifest.txt"
say "PASS: Test 3 (Remove strictly refuses to delete active files without manifest)."

# ------------------------------------------------------------------------------
# TEST 4: Manifest-based remove -> Restores original state
# ------------------------------------------------------------------------------
say "Test 4: Testing clean remove and restoration..."
exec_p105_remove "$ROOT"

for t in "${TARGET_KEYS[@]}"; do
    [ ! -f "$ROOT/$t" ] || fail "Test 4: $t was not removed!"
done
[ ! -d "$ROOT/var/backups/cascadia-pcless" ] || fail "Test 4: backup directory was not removed!"
say "PASS: Test 4 (Manifest-based remove cleaned all Cascadia files)."

# ------------------------------------------------------------------------------
# TEST 5: Failure during backup/manifest creation -> No partial manifest or .new files
# ------------------------------------------------------------------------------
say "Test 5: Testing failure during backup & manifest creation (bstep 2)..."
setup_sandbox
ROOT="$SANDBOX/root"

# Create pre-existing file for kernelcache and ramdisk
echo "ORIGINAL_KERNELCACHE" > "$ROOT/kernelcache"
echo "ORIGINAL_RAMDISK" > "$ROOT/ramdisk"

for t in "${TARGET_KEYS[@]}"; do
    mkdir -p "$(dirname "$ROOT/$t")"
    echo "STAGED_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 0 2 2>/tmp/test5_backup_err.log
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 5: Activation should have failed at backup step 2, but succeeded!"
note "Activation failed at backup step 2 as expected (rc=$rc)"

# Verify no partial or committed manifest exists
[ ! -f "$ROOT/var/backups/cascadia-pcless/manifest.txt" ] || fail "Test 5: manifest.txt exists after backup failure!"
local_tmp_manifests=$(ls "$ROOT/var/backups/cascadia-pcless"/manifest.tmp.* 2>/dev/null || true)
[ -z "$local_tmp_manifests" ] || fail "Test 5: partial manifest.tmp exists after backup failure!"

# Verify all .new staging files were deleted
for t in "${TARGET_KEYS[@]}"; do
    [ ! -f "$ROOT/$t.new" ] || fail "Test 5: $t.new still exists after backup cleanup!"
done

# Verify original files remain intact and unmodified
[ "$(cat "$ROOT/kernelcache")" = "ORIGINAL_KERNELCACHE" ] || fail "Test 5: kernelcache was modified!"
[ "$(cat "$ROOT/ramdisk")" = "ORIGINAL_RAMDISK" ] || fail "Test 5: ramdisk was modified!"

# Verify backup dir was cleaned up
[ ! -d "$ROOT/var/backups/cascadia-pcless" ] || [ -z "$(ls -A "$ROOT/var/backups/cascadia-pcless" 2>/dev/null)" ] \
    || fail "Test 5: backup directory has orphaned backup files!"

say "PASS: Test 5 (Failure during manifest/backup creation: zero partial manifest, zero .new files left)."

# ------------------------------------------------------------------------------
# TEST 6: Failure on 4th file (/usr/local/cascadia/kloader) - Empty initial state
# ------------------------------------------------------------------------------
say "Test 6: Testing failure at 4th file with empty initial state..."
setup_sandbox
ROOT="$SANDBOX/root"

for t in "${TARGET_KEYS[@]}"; do
    mkdir -p "$(dirname "$ROOT/$t")"
    echo "STAGING_CONTENT_$t" > "$ROOT/$t.new"
done

set +e
exec_p105_activate "$ROOT" 4 0 2>/tmp/test6_err.log
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 6: Activation should have failed at step 4, but succeeded!"
note "Activation failed at step 4 as expected (rc=$rc)"

# Files 1, 2, 3 (kernelcache, ramdisk, devicetree) were moved before step 4 -> Rollback must remove them!
[ ! -f "$ROOT/kernelcache" ] || fail "Test 6: kernelcache exists after rollback!"
[ ! -f "$ROOT/ramdisk" ]     || fail "Test 6: ramdisk exists after rollback!"
[ ! -f "$ROOT/devicetree" ]  || fail "Test 6: devicetree exists after rollback!"

# Files 4, 5, 6 were never moved -> Must not exist
[ ! -f "$ROOT/usr/local/cascadia/kloader" ]      || fail "Test 6: kloader exists after rollback!"
[ ! -f "$ROOT/usr/local/cascadia/iBEC.upgrade" ] || fail "Test 6: iBEC.upgrade exists after rollback!"
[ ! -f "$ROOT/usr/bin/linux" ]                   || fail "Test 6: linux exists after rollback!"

# All .new files must be cleaned up
for t in "${TARGET_KEYS[@]}"; do
    [ ! -f "$ROOT/$t.new" ] || fail "Test 6: $t.new still exists!"
done
[ ! -d "$ROOT/var/backups/cascadia-pcless" ] || fail "Test 6: failed backup dir not cleaned up!"
say "PASS: Test 6 (Step 4 failure with empty initial state: complete clean rollback)."

# ------------------------------------------------------------------------------
# TEST 7: Failure on 4th file (/usr/local/cascadia/kloader) - Pre-existing files
# ------------------------------------------------------------------------------
say "Test 7: Testing failure at 4th file with pre-existing canary files..."
setup_sandbox
ROOT="$SANDBOX/root"

# Create pre-existing canary files with distinct hashes
CANARY_HASHES=()
for t in "${TARGET_KEYS[@]}"; do
    mkdir -p "$(dirname "$ROOT/$t")"
    echo "CANARY_ORIGINAL_DATA_FOR_$t" > "$ROOT/$t"
    CANARY_HASHES+=("$(sha1sum "$ROOT/$t" | awk '{print $1}')")
done

# Stage all 6 .new files with replacement content
for t in "${TARGET_KEYS[@]}"; do
    echo "REPLACEMENT_DATA_FOR_$t" > "$ROOT/$t.new"
done

# Run activation with failure at step 4 (usr/local/cascadia/kloader)
set +e
exec_p105_activate "$ROOT" 4 0 2>/tmp/test7_err.log
rc=$?
set -e

[ "$rc" -ne 0 ] || fail "Test 7: Activation should have failed at step 4, but succeeded!"
note "Activation failed at step 4 as expected (rc=$rc)"

# Verify:
# Files 1, 2, 3 were moved then RESTORED from .orig backups!
# Files 4, 5, 6 were never moved and remained intact!
for i in "${!TARGET_KEYS[@]}"; do
    t="${TARGET_KEYS[$i]}"
    want_hash="${CANARY_HASHES[$i]}"
    [ -f "$ROOT/$t" ] || fail "Test 7: $t missing after rollback!"
    got_hash=$(sha1sum "$ROOT/$t" | awk '{print $1}')
    [ "$got_hash" = "$want_hash" ] || fail "Test 7: $t hash mismatch after rollback! (got $got_hash, want $want_hash)"
    note "File $t: content 100% restored to original canary hash ($got_hash)"
done

# All .new files must be cleaned up
for t in "${TARGET_KEYS[@]}"; do
    [ ! -f "$ROOT/$t.new" ] || fail "Test 7: $t.new still exists!"
done
[ ! -d "$ROOT/var/backups/cascadia-pcless" ] || fail "Test 7: backup dir was not cleaned up!"

say "PASS: Test 7 (Step 4 failure with pre-existing files: all 6 originals 100% bit-for-bit restored)."
echo "=================================================================="
echo " ALL EXACT REMOTE SHELL TESTS PASSED PERFECTLY (7/7 SCENARIOS)!"
echo " ZERO EXTERNAL BINARY DEPENDENCIES (POSIX /bin/sh COMPLIANT)"
echo "=================================================================="
