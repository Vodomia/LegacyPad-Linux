#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# Isolated host-only tests; the real iPad is not accessed.
set -eu

base=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
bat="$tmp/sys/class/power_supply/battery"
pmu="$tmp/sys/class/power_supply/apple-pmu-usb"
mod="$tmp/sys/module/apple_pmu_charger/parameters"
mkdir -p "$bat" "$pmu" "$mod"

prepare() {
    printf '%s\n' 70 > "$bat/capacity"
    printf '%s\n' 300000 > "$bat/current_now"
    printf '%s\n' 290 > "$bat/temp"
    printf '%s\n' 1 > "$bat/present"
    printf '%s\n' 1 > "$pmu/online"
    printf '%s\n' 1000000 > "$pmu/input_current_limit"
    printf '%s\n' Y > "$mod/armed"
}

sed -e "s|/sys/class/power_supply/battery|$bat|g" \
    -e "s|/sys/class/power_supply/apple-pmu-usb|$pmu|g" \
    -e "s|/sys/module/apple_pmu_charger/parameters/armed|$mod/armed|g" \
    -e 's/\[ "$n" -le 7 \]/[ "$n" -le 2 ]/' \
    -e 's/\[ "$n" -lt 7 \]/[ "$n" -lt 2 ]/' \
    -e 's/sleep 60/sleep 0/' \
    "$base/overlay/usr/bin/legacypad-charge-gate" > "$tmp/gate"

expect_pass() {
    if ! sh "$tmp/gate" "$1" > "$tmp/out" 2>&1; then
        echo "FAIL: expected success ($2)" >&2; cat "$tmp/out" >&2; exit 1
    fi
    echo "PASS: $2"
}
expect_fail() {
    if sh "$tmp/gate" --once > "$tmp/out" 2>&1; then
        echo "FAIL: expected rejection ($1)" >&2; exit 1
    fi
    echo "PASS: $1"
}

prepare; expect_pass --once 'healthy snapshot'
prepare; expect_pass --gate 'sustained gate control flow'
prepare; printf '%s\n' 0 > "$pmu/online"; expect_fail 'cable disconnected'
prepare; printf '%s\n' 100000 > "$pmu/input_current_limit"; expect_fail '100 mA clamp'
prepare; printf '%s\n' -200000 > "$bat/current_now"; expect_fail 'net discharge'
prepare; printf '%s\n' N > "$mod/armed"; expect_fail 'disarmed driver'
prepare; printf '%s\n' 450 > "$bat/temp"; expect_fail 'high temperature'
prepare; printf '%s\n' 49 > "$bat/capacity"; expect_fail 'low state of charge'
prepare; rm "$bat/current_now"; expect_fail 'missing telemetry fails closed'
prepare; printf '%s\n' unknown > "$bat/temp"; expect_fail 'malformed telemetry fails closed'
echo 'PASS: all 10 host-only charging gate tests'
