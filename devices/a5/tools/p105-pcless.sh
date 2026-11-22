#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Derived from Project Cascadia (https://github.com/rzxvx/Project-Cascadia)
# for LegacyPad-Linux (https://github.com/Vodomia/LegacyPad-Linux).
#
# p105-pcless.sh -- PC-less Linux boot for iPad mini 1 (iPad2,5 / P105AP, iOS 8.4.1 12H321).
# Starts RAM-rooted Linux directly from jailbroken iOS without a computer or cable.
#
#   tools/p105-pcless.sh build     prepare all boot files in build/p105/pcless
#   tools/p105-pcless.sh verify    strict offline verification of artifacts, C unwrapper, and bootargs
#   tools/p105-pcless.sh check-ios safe read-only check of iPad model, iOS build, and free space (no writes)
#   tools/p105-pcless.sh install   atomic installation or safe upgrade to iPad with manifest, backup & rollback
#   tools/p105-pcless.sh update    alias for install when upgrading an existing installation
#   tools/p105-pcless.sh rollback  reverts active installation to previous version without touching original iOS backups
#   tools/p105-pcless.sh remove    manifest-based removal: restores original pre-existing files, deletes Cascadia files
#
# Boot chain:
#   iOS 8.4.1 (jailbroken) -> /usr/bin/linux (kloader)
#     -> iBEC.upgrade (starts from kloader wake, auto-boot -> upgrade)
#       -> /devicetree (img3 dtre)
#       -> /ramdisk (img3 rdsk)
#       -> /kernelcache (img3 krnl: Mach-O complzss holding staging-bundle.bin)
#     -> Linux loader at 0x80000000 -> Linux kernel (root=/dev/ram0)
#
# Storage & safety invariants:
#   - Installation phase writes boot files to iOS System HFS+ partition on NAND.
#   - Runtime Linux rootfs is 100% in RAM (/dev/ram0).
#   - Runtime Linux NAND write permissions are completely disabled.
#   - No NAND partitioning or FTL formatting.
#   - No NFS or USB cable dependency at runtime.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
OUT="${OUT:-$ROOT/build/p105/pcless}"
case "$OUT" in
    /*) ;;
    *) OUT="$(cd "$OUT" 2>/dev/null && pwd || echo "$(pwd)/$OUT")" ;;
esac

KLOADER="$ROOT/build/cache/kloader"
KLOADER_SHA256="bec212b4d99a1e3b9fa4add663fa884a2435045d1e47051415f4e26e197f8132"
D="/usr/local/cascadia"
BACKUP_DIR="/var/backups/cascadia-pcless"

say()  { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# Helper to write local linux launcher script
generate_linux_cmd() {
    cat <<'EOF'
#!/bin/sh
# linux -- boot the iPad mini 1 into RAM Linux (LegacyPad / Project Cascadia).
# Started by kloader on iOS 8.4.1.
# iBEC loads /kernelcache, /ramdisk, /devicetree from System and jumps to Linux.
# Linux rootfs is purely in RAM (/dev/ram0).
# No NAND partitions, no FTL, no NAND writes.

D=/usr/local/cascadia

for f in /kernelcache /ramdisk /devicetree "$D/kloader" "$D/iBEC.upgrade"; do
    if [ ! -s "$f" ]; then
        echo "linux: $f is missing -- run 'tools/p105-pcless.sh install' first" >&2
        exit 1
    fi
done

echo "Booting RAM Linux... (screen will turn black; press Home button once)"
sync; sync

L=/var/log/cascadia-linux.log
echo "(kloader log: $L)"
trap '' HUP PIPE
echo "== $(date): $D/kloader $D/iBEC.upgrade" >> "$L"
exec "$D/kloader" "$D/iBEC.upgrade" < /dev/null >> "$L" 2>&1
EOF
}

# Generator for remote atomic activation and rollback script
# Uses pure POSIX shell built-ins (no basename, no grep, no cut) for iOS sh compatibility.
# Args: [root_prefix] [fail_on_step] [fail_on_backup] [mode: auto|install|update]
generate_activate_script() {
    local P="${1:-}"
    local FAIL_ON_STEP="${2:-0}"
    local FAIL_ON_BACKUP="${3:-0}"
    local MODE="${4:-auto}"
    cat <<EOF
P="$P"
FAIL_ON_STEP="$FAIL_ON_STEP"
FAIL_ON_BACKUP="$FAIL_ON_BACKUP"
MODE="$MODE"
EOF
    cat <<'EOF'
set -e
export PATH="${PATH:-/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin}"

BK="${P}/var/backups/cascadia-pcless"
PREV="${BK}/previous"
PREV_TMP="${BK}/previous.tmp.$$"
MANIFEST="${BK}/manifest.txt"
MANIFEST_TMP="${BK}/manifest.tmp.$$"
D="${P}/usr/local/cascadia"

mkdir -p "$BK" "$D" "${P}/usr/bin"

TARGETS="${P}/kernelcache ${P}/ramdisk ${P}/devicetree ${P}/usr/local/cascadia/kloader ${P}/usr/local/cascadia/iBEC.upgrade ${P}/usr/bin/linux"

# Determine effective mode: install (first-time) or update (manifest exists)
if [ "$MODE" = "auto" ]; then
    if [ -f "$MANIFEST" ]; then
        ACTUAL_MODE="update"
    else
        ACTUAL_MODE="install"
    fi
else
    ACTUAL_MODE="$MODE"
fi

if [ "$ACTUAL_MODE" = "install" ] && [ -f "$MANIFEST" ]; then
    echo "ERROR: A prior Cascadia installation manifest already exists at $MANIFEST!" >&2
    echo "To update an existing installation, use update mode. To reset to stock, run remove first." >&2
    exit 1
fi
if [ "$ACTUAL_MODE" = "update" ] && [ ! -f "$MANIFEST" ]; then
    echo "ERROR: Cannot update: no existing manifest found at $MANIFEST! Run install first." >&2
    exit 1
fi

PHASE="backup"
CREATED_BACKUPS=""
MOVED=""

cleanup() {
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "Activation failed during $PHASE phase (exit code $rc)! Cleaning up..." >&2
        for t in $TARGETS; do
            rm -f "${t}.new"
        done
        if [ "$ACTUAL_MODE" = "install" ]; then
            if [ "$PHASE" = "backup" ]; then
                rm -f "$MANIFEST_TMP" "$MANIFEST"
                for b in $CREATED_BACKUPS; do
                    rm -f "$b"
                done
                rmdir "$BK" 2>/dev/null || true
            elif [ "$PHASE" = "activation" ]; then
                echo "Executing rollback for moved files to initial state..." >&2
                for m in $MOVED; do
                    bname="${m##*/}"
                    status=""
                    if [ -f "$MANIFEST" ]; then
                        while IFS=: read -r entry_target entry_status; do
                            if [ "$entry_target" = "$m" ]; then
                                status="$entry_status"
                                break
                            fi
                        done < "$MANIFEST"
                    fi
                    if [ "$status" = "existed" ] && [ -f "$BK/${bname}.orig" ]; then
                        echo "  Restoring original $m..." >&2
                        cp -p "$BK/${bname}.orig" "$m"
                    else
                        echo "  Removing newly created $m..." >&2
                        rm -f "$m"
                    fi
                done
                rm -rf "$BK"
            fi
        elif [ "$ACTUAL_MODE" = "update" ]; then
            echo "Executing rollback for moved files to previous active version..." >&2
            for m in $MOVED; do
                bname="${m##*/}"
                if [ -f "$PREV_TMP/${bname}" ]; then
                    echo "  Restoring previous active $m..." >&2
                    cp -p "$PREV_TMP/${bname}" "$m"
                fi
            done
            rm -rf "$PREV_TMP"
            # In update failure, initial .orig backups, manifest, and existing previous/ remain untouched!
        fi
        sync
        exit $rc
    fi
}
trap cleanup EXIT

# Backup phase
bstep=0
if [ "$ACTUAL_MODE" = "install" ]; then
    > "$MANIFEST_TMP"
    for t in $TARGETS; do
        bstep=$((bstep + 1))
        if [ "$FAIL_ON_BACKUP" -eq "$bstep" ]; then
            echo "Simulating synthetic failure at backup step $bstep on $t" >&2
            false
        fi
        bname="${t##*/}"
        if [ -f "$t" ]; then
            echo "$t:existed" >> "$MANIFEST_TMP"
            cp -p "$t" "$BK/${bname}.orig"
            CREATED_BACKUPS="$CREATED_BACKUPS $BK/${bname}.orig"
        else
            echo "$t:created" >> "$MANIFEST_TMP"
        fi
    done
    mv "$MANIFEST_TMP" "$MANIFEST"
elif [ "$ACTUAL_MODE" = "update" ]; then
    mkdir -p "$PREV_TMP"
    for t in $TARGETS; do
        bstep=$((bstep + 1))
        if [ "$FAIL_ON_BACKUP" -eq "$bstep" ]; then
            echo "Simulating synthetic failure at backup step $bstep on $t" >&2
            false
        fi
        bname="${t##*/}"
        if [ -f "$t" ]; then
            cp -p "$t" "$PREV_TMP/${bname}"
        fi
    done
fi

PHASE="activation"

# Activation phase
step=0
for t in $TARGETS; do
    step=$((step + 1))
    if [ "$FAIL_ON_STEP" -eq "$step" ]; then
        echo "Simulating synthetic failure at activation step $step on $t" >&2
        false
    fi
    mv "${t}.new" "$t"
    MOVED="$MOVED $t"
done

# If update succeeded, commit PREV_TMP to PREV
if [ "$ACTUAL_MODE" = "update" ]; then
    rm -rf "$PREV"
    mv "$PREV_TMP" "$PREV"
fi

chmod 755 "${P}/usr/local/cascadia/kloader" "${P}/usr/bin/linux"
trap - EXIT
EOF
}

# Generator for remote rollback script (reverts active files to previous Cascadia version)
generate_rollback_script() {
    local P="${1:-}"
    cat <<EOF
P="$P"
EOF
    cat <<'EOF'
set -e
export PATH="${PATH:-/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin}"

BK="${P}/var/backups/cascadia-pcless"
PREV="${BK}/previous"
MANIFEST="${BK}/manifest.txt"

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: No Cascadia installation manifest found at $MANIFEST!" >&2
    exit 1
fi

if [ ! -d "$PREV" ]; then
    echo "ERROR: No previous version backup found at $PREV to roll back to!" >&2
    echo "To revert to stock iOS, run remove instead." >&2
    exit 1
fi

echo "Rolling back active files to previous version from $PREV..."
TARGETS="${P}/kernelcache ${P}/ramdisk ${P}/devicetree ${P}/usr/local/cascadia/kloader ${P}/usr/local/cascadia/iBEC.upgrade ${P}/usr/bin/linux"

for t in $TARGETS; do
    bname="${t##*/}"
    if [ -f "$PREV/${bname}" ]; then
        echo "  Restoring previous $t..."
        mv "$PREV/${bname}" "$t"
    fi
done

rm -rf "$PREV"
chmod 755 "${P}/usr/local/cascadia/kloader" "${P}/usr/bin/linux" 2>/dev/null || true
sync
echo "Rollback to previous version completed successfully."
EOF
}

# Generator for remote manifest-based remove and restore script
# Restores original stock iOS files and deletes Cascadia-installed files.
generate_remove_script() {
    local P="${1:-}"
    cat <<EOF
P="$P"
EOF
    cat <<'EOF'
set -e
export PATH="${PATH:-/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin}"

BK="${P}/var/backups/cascadia-pcless"
PREV="${BK}/previous"
MANIFEST="${BK}/manifest.txt"
D="${P}/usr/local/cascadia"

TARGETS="${P}/kernelcache ${P}/ramdisk ${P}/devicetree ${P}/usr/local/cascadia/kloader ${P}/usr/local/cascadia/iBEC.upgrade ${P}/usr/bin/linux"

# Clean up any lingering staging files
for t in $TARGETS; do
    rm -f "${t}.new"
done
rm -f "${P}/var/log/cascadia-linux.log"

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: No Cascadia installation manifest found at $MANIFEST!" >&2
    echo "Refusing to remove active files without manifest to protect system files." >&2
    exit 1
fi

echo "Found installation manifest at $MANIFEST. Restoring original system state..."
while IFS=: read -r target status; do
    [ -n "$target" ] || continue
    bname="${target##*/}"
    if [ "$status" = "existed" ]; then
        if [ -f "$BK/${bname}.orig" ]; then
            echo "  Restoring original $target..."
            mv "$BK/${bname}.orig" "$target"
        else
            echo "  WARNING: Backup $BK/${bname}.orig missing for $target!" >&2
        fi
    elif [ "$status" = "created" ]; then
        echo "  Removing Cascadia-installed $target..."
        rm -f "$target"
    fi
done < "$MANIFEST"

rm -rf "$PREV"
rm -f "$MANIFEST"
rm -rf "$BK"
rmdir "$D" 2>/dev/null || true
sync
echo "System restored to stock iOS state. All Cascadia files removed."
EOF
}

verify_bootargs() {
    say "Verifying bootargs in kernel image and bundle..."
    python3 -c "
import struct, sys

def check_dtb_bootargs(dtb_bytes):
    magic, total, off_struct, off_strings = struct.unpack_from('>IIII', dtb_bytes, 0)
    assert magic == 0xd00dfeed, 'not a valid DTB'
    p = off_struct
    strings = dtb_bytes[off_strings:]
    bootargs = None
    has_ppn_node = False
    while p < len(dtb_bytes):
        token = struct.unpack_from('>I', dtb_bytes, p)[0]
        p += 4
        if token == 1: # FDT_BEGIN_NODE
            name_end = dtb_bytes.find(b'\0', p)
            nodename = dtb_bytes[p:name_end].decode('latin1', 'replace')
            p = (name_end + 4) & ~3
            if 'ppn@1200000' in nodename:
                has_ppn_node = True
        elif token == 3: # FDT_PROP
            val_len, name_off = struct.unpack_from('>II', dtb_bytes, p)
            p += 8
            prop_val = dtb_bytes[p:p+val_len]
            p = (p + val_len + 3) & ~3
            prop_name_end = strings.find(b'\0', name_off)
            prop_name = strings[name_off:prop_name_end].decode('latin1', 'replace')
            if prop_name == 'bootargs':
                bootargs = prop_val.decode('latin1', 'replace').rstrip('\0')
        elif token == 9: # FDT_END
            break
    return bootargs, has_ppn_node

zimage = '$ROOT/output/zImage-dtb'
with open(zimage, 'rb') as f:
    d = f.read()

off = d.rfind(bytes.fromhex('d00dfeed'))
assert off >= 0, 'No DTB magic found in zImage-dtb'
args, has_ppn = check_dtb_bootargs(d[off:])

assert args is not None, 'bootargs not found in appended DTB'
assert 'root=/dev/ram0' in args, 'root=/dev/ram0 not found in bootargs'
assert 'apple_ppn.allow_write=1' not in args, 'apple_ppn.allow_write found in bootargs'
assert 'apple_ftl.enable_write=1' not in args, 'apple_ftl.enable_write found in bootargs'
assert 'apple_ftl.write_volume' not in args, 'apple_ftl.write_volume found in bootargs'
assert not has_ppn, 'PPN hardware node unexpectedly present in RAM device tree'

print('  bootargs: ' + args)
" || fail "Bootargs verification failed: RAM root (/dev/ram0) and write-lock invariants violated!"
    note "Bootargs verified: root=/dev/ram0, zero NAND write flags, PPN node absent"
}

build() {
    local ibec="$ROOT/build/firmware/iBEC.patched"
    local dt="$ROOT/build/firmware/DeviceTree.dec"
    local ipsw="${IPSW:-$REPO/iPad2,5_8.4.1_12H321_Restore.ipsw}"
    local bundle="${BUNDLE:-$ROOT/output/staging-bundle.bin}"

    [ -s "$ibec" ] || fail "missing $ibec: run ./cascadia a5 firmware first"
    [ -s "$dt" ] || fail "missing $dt: run ./cascadia a5 firmware first"
    [ -s "$ipsw" ] || fail "missing $ipsw: place iPad2,5_8.4.1_12H321_Restore.ipsw in project root"
    [ -s "$bundle" ] || fail "missing $bundle: run assemble or ./cascadia a5 build"

    verify_bootargs

    mkdir -p "$OUT"
    say "1. iBEC: patching for standalone upgrade boot from System (patch-ibec-upgrade.py)"
    python3 "$ROOT/scripts/patch-ibec-upgrade.py" "$ibec" "$OUT/iBEC.upgrade" | sed 's/^/  /'

    say "2. Packaging kernelcache, ramdisk, devicetree (make-pcless.py)"
    python3 "$ROOT/scripts/make-pcless.py" --board p105 --ipsw "$ipsw" \
        --bundle "$bundle" --devicetree "$dt" --out "$OUT"

    say "3. Generating local linux launcher script"
    generate_linux_cmd > "$OUT/linux"
    chmod 755 "$OUT/linux"

    say "Build complete in $OUT"
}

verify() {
    say "Verifying PC-less build artifacts in $OUT..."
    [ -d "$OUT" ] || fail "$OUT does not exist. Run 'build' first."

    # 1. Verify existence and sizes of all generated artifacts
    for f in kernelcache ramdisk devicetree iBEC.upgrade linux; do
        [ -s "$OUT/$f" ] || fail "missing or empty artifact: $OUT/$f"
        note "$f: $(stat -c%s "$OUT/$f") bytes"
    done

    # 2. Strict verification of kloader binary
    [ -s "$KLOADER" ] || fail "missing $KLOADER: kloader binary not found in build/cache"
    local k_hash
    k_hash=$(sha256sum "$KLOADER" | awk '{print $1}')
    [ "$k_hash" = "$KLOADER_SHA256" ] || fail "kloader SHA256 mismatch: got $k_hash, expected $KLOADER_SHA256"
    note "kloader: verified ($k_hash)"

    # 3. Mandatory C verification test (unwrap, layer extract, assemble, wrap)
    say "Compiling and running C verification tool (test-pcless)..."
    local test_bin="/tmp/test-pcless"
    gcc -Wall -Wextra -O2 -I "$ROOT/app" -o "$test_bin" "$ROOT/tests/test-pcless.c" "$ROOT/app/pcless.c" \
        || fail "Compilation of test-pcless failed! C verification must not be skipped."

    local bundle="${BUNDLE:-}"
    if [ -z "$bundle" ]; then
        if [ -s "$OUT/candidate-staging-bundle.bin" ]; then
            bundle="$OUT/candidate-staging-bundle.bin"
        elif [ -s "$OUT/staging-bundle.bin" ]; then
            bundle="$OUT/staging-bundle.bin"
        elif [[ "$OUT" == *"candidate"* ]] && [ -s "$ROOT/output/candidate-staging-bundle.bin" ]; then
            bundle="$ROOT/output/candidate-staging-bundle.bin"
        else
            bundle="$ROOT/output/staging-bundle.bin"
        fi
    fi
    note "Using bundle for C verification: $bundle"

    "$test_bin" "$OUT/kernelcache" "$bundle" \
                "$ROOT/output/linux-boot.bin" "$ROOT/output/zImage-dtb" \
        || fail "C verification test failed! kernelcache does not wrap bundle correctly."
    note "C test verification: PASSED (unwrap, layer extract, assemble, wrap bit-for-bit identical)"

    # 4. Verify bootargs inside bundle and device tree
    verify_bootargs

    say "All PC-less artifacts verified successfully."
}

check_ios() {
    say "Connecting to iPad for safe read-only hardware & space audit..."
    . "$ROOT/tools/ios-ssh.sh"
    BOARD_MODEL=iPad2,5
    ios_setup p105pcless
    ios_connect || fail "SSH connection/authentication to iOS failed!"
    ios_check_model

    say "Verifying device hardware model and iOS build version..."
    local dev_mach dev_build
    dev_mach=$(ios 'sysctl -n hw.machine' 2>/dev/null || ios 'uname -m')
    dev_build=$(ios 'sysctl -n kern.osversion' 2>/dev/null || ios 'sw_vers -buildVersion 2>/dev/null || true')

    [ "$dev_mach" = "iPad2,5" ] || fail "Target device hw.machine is '$dev_mach', expected 'iPad2,5'!"
    [ "$dev_build" = "12H321" ] || fail "Target device kern.osversion is '$dev_build', expected '12H321'!"
    note "Hardware model: $dev_mach (VERIFIED)"
    note "iOS build version: $dev_build (VERIFIED)"

    say "Checking iOS System partition space..."
    local free_kb
    free_kb=$(ios 'df -k /' | awk 'NR==2 {print $4}')
    note "System partition (/) free space: ${free_kb} KB ($((free_kb / 1024)) MB)"

    local need_kb=38000
    if [ "$free_kb" -lt "$need_kb" ]; then
        fail "Insufficient space on iOS System partition! Needed: ~${need_kb} KB, Free: ${free_kb} KB"
    else
        note "Space check: PASS (${free_kb} KB available > ${need_kb} KB needed)"
    fi

    # Check for stale .new files from any previous interrupted attempt
    local stale_files
    stale_files=$(ios '
        for f in /kernelcache.new /ramdisk.new /devicetree.new /usr/local/cascadia/kloader.new /usr/local/cascadia/iBEC.upgrade.new /usr/bin/linux.new; do
            [ -e "$f" ] && echo "$f"
        done
    ' 2>/dev/null || true)
    if [ -n "$stale_files" ]; then
        say "NOTICE: Found stale staging files from a previous run (will be cleaned during install):"
        echo "$stale_files" | sed 's/^/    /'
    fi

    say "Checking existing boot files on iOS (read-only)..."
    ios 'for f in /kernelcache /ramdisk /devicetree /usr/local/cascadia/kloader /usr/local/cascadia/iBEC.upgrade /usr/bin/linux; do
        if [ -e "$f" ]; then
            ls -l "$f"
        else
            echo "  $f: not present"
        fi
    done'

    say "Read-only iOS audit completed successfully. Device is 100% compatible."
}

install() {
    # If artifacts already exist in $OUT, use them directly; otherwise build them.
    if [ ! -s "$OUT/kernelcache" ] || [ ! -s "$OUT/ramdisk" ] || [ ! -s "$OUT/devicetree" ] || [ ! -s "$OUT/iBEC.upgrade" ] || [ ! -s "$OUT/linux" ]; then
        say "Artifacts missing in $OUT; building..."
        build
    else
        say "Using existing pre-built artifacts in $OUT"
    fi
    verify

    say "Connecting to iPad for PC-less installation..."
    . "$ROOT/tools/ios-ssh.sh"
    BOARD_MODEL=iPad2,5
    ios_setup p105pcless
    ios_connect || fail "SSH connection/authentication to iOS failed!"

    # 1. Strict pre-installation hardware & OS validation
    say "1. Pre-install validation: hw.machine and kern.osversion..."
    local dev_mach dev_build
    dev_mach=$(ios 'sysctl -n hw.machine' 2>/dev/null || ios 'uname -m')
    dev_build=$(ios 'sysctl -n kern.osversion' 2>/dev/null || ios 'sw_vers -buildVersion 2>/dev/null || true')

    [ "$dev_mach" = "iPad2,5" ] || fail "ABORT: Target device hw.machine is '$dev_mach', expected 'iPad2,5'!"
    [ "$dev_build" = "12H321" ] || fail "ABORT: Target device kern.osversion is '$dev_build', expected '12H321'!"
    note "Device verified: hw.machine=$dev_mach, kern.osversion=$dev_build"

    # 2. Check for prior installation manifest to choose install vs update mode
    say "2. Checking for prior installation manifest on device..."
    local prior_manifest
    prior_manifest=$(ios "[ -f '$BACKUP_DIR/manifest.txt' ] && echo 'yes' || true" 2>/dev/null || true)
    local install_mode="install"
    if [ "$prior_manifest" = "yes" ]; then
        say "Existing installation detected (manifest at $BACKUP_DIR/manifest.txt)."
        say "Safe update mode: initial iOS backups (*.orig) will be preserved."
        say "Current active files will be saved to $BACKUP_DIR/previous before activation."
        install_mode="update"
    else
        say "Clean initial installation detected on iOS."
        install_mode="install"
    fi

    # 3. Check for stale .new files from an interrupted prior attempt
    say "3. Checking for stale staging (.new) files from interrupted attempts..."
    local stale_files
    stale_files=$(ios '
        for f in /kernelcache.new /ramdisk.new /devicetree.new /usr/local/cascadia/kloader.new /usr/local/cascadia/iBEC.upgrade.new /usr/bin/linux.new; do
            [ -e "$f" ] && echo "$f"
        done
    ' 2>/dev/null || true)
    if [ -n "$stale_files" ]; then
        say "WARNING: Found stale staging files from an interrupted prior run:"
        echo "$stale_files" | sed 's/^/    /'
        say "Cleaning up stale staging files..."
        ios 'rm -f /kernelcache.new /ramdisk.new /devicetree.new /usr/local/cascadia/kloader.new /usr/local/cascadia/iBEC.upgrade.new /usr/bin/linux.new'
        note "Stale staging files successfully removed."
    else
        note "No stale staging files found."
    fi

    # 4. Space validation
    say "4. Pre-install validation: free space on System partition..."
    local free_kb
    free_kb=$(ios 'df -k /' | awk 'NR==2 {print $4}')
    local need_kb=38000
    [ "$free_kb" -ge "$need_kb" ] || fail "ABORT: Insufficient space on / (${free_kb} KB < ${need_kb} KB)"
    note "Free space verified: ${free_kb} KB"

    # 5. Remount / read-write if currently read-only
    if ios 'mount' | grep -E ' on / ' | grep -q 'read-only'; then
        note "System partition is read-only: remounting read-write for installation"
        ios 'mount -uw /'
    fi

    # 6. Define all 6 files to stage and install with direct literal paths
    local FILES=(
        "$OUT/kernelcache:/kernelcache"
        "$OUT/ramdisk:/ramdisk"
        "$OUT/devicetree:/devicetree"
        "$KLOADER:/usr/local/cascadia/kloader"
        "$OUT/iBEC.upgrade:/usr/local/cascadia/iBEC.upgrade"
        "$OUT/linux:/usr/bin/linux"
    )

    # Setup host trap: if upload is interrupted or fails mid-transfer, cleanup remote .new files
    cleanup_staging_trap() {
        say "Upload interrupted! Cleaning up remote staging (.new) files..."
        ios 'rm -f /kernelcache.new /ramdisk.new /devicetree.new /usr/local/cascadia/kloader.new /usr/local/cascadia/iBEC.upgrade.new /usr/bin/linux.new' 2>/dev/null || true
    }
    trap cleanup_staging_trap ERR INT TERM

    say "5. Uploading all 6 boot files to staging paths (.new)..."
    ios "mkdir -p '/usr/local/cascadia'"
    for item in "${FILES[@]}"; do
        local src="${item%%:*}"
        local dst="${item##*:}"
        note "Uploading $(basename "$src") -> ${dst}.new..."
        ios "cat > '${dst}.new'" < "$src"
    done
    ios "chmod 755 '/usr/local/cascadia/kloader.new' '/usr/bin/linux.new'"

    say "6. Verifying SHA1 checksums and file sizes of all 6 uploaded files on iPad..."
    for item in "${FILES[@]}"; do
        local src="${item%%:*}"
        local dst="${item##*:}"
        local want_size want_sha got_info got_size got_sha

        want_size=$(stat -c%s "$src")
        want_sha=$(sha1sum "$src" | awk '{print $1}')

        got_info=$(ios "
            export PATH='/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin'
            ls -l '${dst}.new'
            if type openssl >/dev/null 2>&1; then
                openssl sha1 '${dst}.new'
            elif type sha1sum >/dev/null 2>&1; then
                sha1sum '${dst}.new'
            elif type shasum >/dev/null 2>&1; then
                shasum '${dst}.new'
            fi
        " | awk 'NR == 1 {size = $5} /SHA1/ {sub(/.*= /, ""); sum = $0} /^[0-9a-f]{40}/ {sum = $1} END {print size " " sum}')
        got_size=$(echo "$got_info" | awk '{print $1}')
        got_sha=$(echo "$got_info" | awk '{print $2}')

        if [ "$got_size" != "$want_size" ] || [ "$got_sha" != "$want_sha" ]; then
            say "INTEGRITY CHECK FAILED for ${dst}.new!"
            note "Expected: size=$want_size sha1=$want_sha"
            note "Received: size=$got_size sha1=$got_sha"
            say "Cleaning up staging files..."
            ios "rm -f /kernelcache.new /ramdisk.new /devicetree.new /usr/local/cascadia/kloader.new /usr/local/cascadia/iBEC.upgrade.new /usr/bin/linux.new"
            fail "Installation aborted due to checksum mismatch on $(basename "$dst")"
        fi
        note "Verified $(basename "$dst"): size=$got_size, sha1=$got_sha (MATCH)"
    done

    # Remove upload trap before activating
    trap - ERR INT TERM

    say "7. Generating manifest, pre-install backup, and activating with atomic rollback..."
    local act_script
    act_script=$(generate_activate_script "" 0 0 "$install_mode")
    ios "$act_script" || fail "Activation failed during remote move operations; rollback was executed."
    note "All 6 files successfully activated with manifest and backup secured."

    say "8. Flushing filesystem journal (sync; sleep 40; sync)..."
    ios 'sync; sleep 40; sync'

    say "INSTALLATION COMPLETE AND VERIFIED!"
    echo "=================================================================="
    echo " PC-less RAM Linux is installed on iPad mini 1."
    echo " Mode: $install_mode (initial .orig backups preserved)"
    echo " To boot Linux without a computer or cable:"
    echo "   1. On iPad (via MobileTerminal / MTerminal or SSH), run as root:"
    echo "        linux"
    echo "   2. The screen will turn black. Press the Home button once."
    echo "   3. Linux will boot into RAM (/dev/ram0) on the iPad screen."
    echo "   4. Note: If boot hangs before userspace, hold Power + Home"
    echo "      for 10 seconds to cold-reboot back into normal iOS."
    echo "=================================================================="
}

rollback() {
    say "Connecting to iPad to rollback to previous version..."
    . "$ROOT/tools/ios-ssh.sh"
    BOARD_MODEL=iPad2,5
    ios_setup p105pcless
    ios_connect || fail "SSH connection/authentication to iOS failed!"
    ios_check_model

    say "Executing rollback to previous version..."
    local rb_script
    rb_script=$(generate_rollback_script "")
    ios "$rb_script" || fail "Rollback failed on device."
    say "Rollback to previous version completed successfully."
}

remove() {
    say "Connecting to iPad to remove PC-less files..."
    . "$ROOT/tools/ios-ssh.sh"
    BOARD_MODEL=iPad2,5
    ios_setup p105pcless
    ios_connect || fail "SSH connection/authentication to iOS failed!"
    ios_check_model

    say "Restoring/removing files according to Cascadia installation manifest..."
    local rem_script
    rem_script=$(generate_remove_script "")
    ios "$rem_script" || fail "Remove failed on device."
    say "PC-less boot files removed/restored cleanly. Pre-existing files preserved."
}

# Subcommands for internal verification / testing of exact shell scripts
case "${1:-}" in
    build) build ;;
    verify) verify ;;
    check-ios) check_ios ;;
    install) install ;;
    update) install ;;
    rollback) rollback ;;
    remove) remove ;;
    internal-activate)
        generate_activate_script "${2:-}" "${3:-0}" "${4:-0}" "${5:-auto}"
        ;;
    internal-rollback)
        generate_rollback_script "${2:-}"
        ;;
    internal-remove)
        generate_remove_script "${2:-}"
        ;;
    *)
        echo "usage: $0 build | verify | check-ios | install | update | rollback | remove"
        exit 2
        ;;
esac
