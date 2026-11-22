#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
# test-power-diagnostics.sh -- Unit test for legacypad-power and legacypad-status

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POWER_BIN="$SCRIPT_DIR/../overlay/usr/bin/legacypad-power"
STATUS_BIN="$SCRIPT_DIR/../overlay/usr/bin/legacypad-status"

chmod +x "$POWER_BIN" "$STATUS_BIN"

TMP_DIR=$(mktemp -d /tmp/test-power-XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT

BAT_DIR="$TMP_DIR/sys/class/power_supply/battery"
PMU_DIR="$TMP_DIR/sys/class/power_supply/apple-pmu-usb"
MOD_DIR="$TMP_DIR/sys/module/apple_pmu_charger/parameters"

mkdir -p "$BAT_DIR" "$PMU_DIR" "$MOD_DIR"

setup_mock() {
    status="$1"
    cap="$2"
    cur="$3"
    volt="$4"
    temp="$5"
    online="$6"
    pmu_lim="$7"

    echo "$status" > "$BAT_DIR/status"
    echo "$cap" > "$BAT_DIR/capacity"
    echo "$cur" > "$BAT_DIR/current_now"
    echo "$volt" > "$BAT_DIR/voltage_now"
    echo "$temp" > "$BAT_DIR/temp"
    echo "1" > "$BAT_DIR/present"
    echo "1000000" > "$BAT_DIR/charge_now"
    echo "4000000" > "$BAT_DIR/charge_full"
    echo "4490000" > "$BAT_DIR/charge_full_design"
    echo "150" > "$BAT_DIR/cycle_count"

    echo "$online" > "$PMU_DIR/online"
    echo "$pmu_lim" > "$PMU_DIR/input_current_limit"

    echo "1" > "$MOD_DIR/armed"
    echo "1000" > "$MOD_DIR/max_input_ma"
    echo "60" > "$MOD_DIR/sag_retry_sec"
}

# Run wrapper replacing sysfs roots for test
run_test_power() {
    sed -e "s|/sys/class/power_supply/battery|$BAT_DIR|g" \
        -e "s|/sys/class/power_supply/apple-pmu-usb|$PMU_DIR|g" \
        -e "s|/sys/module/apple_pmu_charger/parameters|$MOD_DIR|g" \
        "$POWER_BIN" > "$TMP_DIR/power_wrapped.sh"
    chmod +x "$TMP_DIR/power_wrapped.sh"
    "$TMP_DIR/power_wrapped.sh" "$@"
}

run_test_status() {
    sed -e "s|/sys/class/power_supply/battery|$BAT_DIR|g" \
        -e "s|/sys/class/power_supply/apple-pmu-usb|$PMU_DIR|g" \
        "$STATUS_BIN" > "$TMP_DIR/status_wrapped.sh"
    chmod +x "$TMP_DIR/status_wrapped.sh"
    "$TMP_DIR/status_wrapped.sh" "$@"
}

echo "=== Test 1: Critical Cable Drain Incident (-386 mA, 100 mA limit, plugged) ==="
setup_mock "Discharging" "12" "-386000" "3650000" "295" "1" "100000"

# legacypad-power should exit with 1 (warning/alarm state)
set +e
out_power=$(run_test_power)
code_power=$?
set -e

echo "$out_power"
if [ "$code_power" -ne 1 ]; then
    echo "FAIL: expected exit code 1 for draining on cable, got $code_power" >&2
    exit 1
fi
echo "$out_power" | grep -q "CRITICAL ALARM: BATTERY IS DRAINING ON CABLE" || { echo "FAIL: missing critical alarm header" >&2; exit 1; }
echo "$out_power" | grep -q "Current Deficit: -386 mA" || { echo "FAIL: missing current deficit" >&2; exit 1; }
echo "$out_power" | grep -q "29.5 °C" || { echo "FAIL: temperature display incorrect" >&2; exit 1; }
echo "$out_power" | grep -q "3.65 V" || { echo "FAIL: voltage display incorrect" >&2; exit 1; }

# legacypad-status check
out_status=$(run_test_status)
echo "$out_status" | grep -q "CRITICAL: Battery is DISCHARGING (-386 mA) on cable!" || { echo "FAIL: missing status critical warning" >&2; exit 1; }
echo "PASS: Test 1 (Critical Cable Drain Alarm)"

echo "=== Test 2: Healthy 10W Wall Charger Charging (+752 mA, 1000 mA limit) ==="
setup_mock "Charging" "45" "752000" "3920000" "290" "1" "1000000"

set +e
out_power=$(run_test_power)
code_power=$?
set -e

if [ "$code_power" -ne 0 ]; then
    echo "FAIL: expected exit code 0 for normal charging, got $code_power" >&2
    exit 1
fi
echo "$out_power" | grep -q "HEALTHY: Device is actively charging (+752 mA net into battery)" || { echo "FAIL: missing healthy charging status" >&2; exit 1; }
echo "$out_power" | grep -q "Average Current:    +752 mA (CHARGING into battery)" || { echo "FAIL: missing average current" >&2; exit 1; }
echo "PASS: Test 2 (Healthy Wall Charging)"

echo "=== Test 3: Standalone Scriptable Check (--check) ==="
setup_mock "Discharging" "15" "-386000" "3700000" "280" "1" "100000"
set +e
run_test_power --check
check_code=$?
set -e
if [ "$check_code" -ne 1 ]; then
    echo "FAIL: expected --check code 1 for cable drain, got $check_code" >&2
    exit 1
fi

setup_mock "Charging" "50" "250000" "3900000" "280" "1" "500000"
set +e
run_test_power --check
check_code=$?
set -e
if [ "$check_code" -ne 0 ]; then
    echo "FAIL: expected --check code 0 for healthy charging, got $check_code" >&2
    exit 1
fi
echo "PASS: Test 3 (--check flag)"

echo "=== Test 4: Reset Sag Latch (--reset-sag) ==="
setup_mock "Discharging" "20" "-200000" "3700000" "280" "1" "100000"
run_test_power --reset-sag 1000 >/dev/null 2>&1 || true
read_val=$(cat "$PMU_DIR/input_current_limit")
if [ "$read_val" != "1000000" ]; then
    echo "FAIL: --reset-sag did not write 1000000 to input_current_limit (got $read_val)" >&2
    exit 1
fi
echo "PASS: Test 4 (--reset-sag wrote $read_val uA)"

echo "=== ALL POWER DIAGNOSTIC TESTS PASSED ==="
