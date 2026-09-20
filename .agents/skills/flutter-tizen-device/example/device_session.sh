#!/usr/bin/env bash
# Connect to a Tizen device, run the app, and print the VM Service URL.
# Companion to ../SKILL.md.

set -eu

DEVICE_IP="${DEVICE_IP:-192.168.0.101}"
DEVICE_PORT="${DEVICE_PORT:-26101}"
DEVICE_ID="${DEVICE_ID:-${DEVICE_IP}:${DEVICE_PORT}}"

# 1) Connect
sdb connect "${DEVICE_IP}:${DEVICE_PORT}"
sdb devices | grep -F "$DEVICE_ID" | grep -q $'\tdevice$' ||
	{
		echo "device not 'device' status — check developer mode + RSA prompt"
		exit 1
	}

# 2) flutter-tizen sees it
flutter-tizen devices | grep -F "$DEVICE_ID"

# 3) Run debug build with hot reload, capturing the VM Service URL
LOG=$(mktemp)
flutter-tizen run -d "$DEVICE_ID" --debug 2>&1 | tee "$LOG" &
FT_PID=$!

# 4) Wait for the VM Service URL, then print it for DevTools/manual attach
sleep 5
VM_URL=$(grep -oE 'http://127\.0\.0\.1:[0-9]+/[^ ]+' "$LOG" | head -1)
echo "VM Service URL: $VM_URL"

# 5) Detach cleanly when done
trap 'kill $FT_PID 2>/dev/null; sdb disconnect '"${DEVICE_IP}:${DEVICE_PORT}"'' EXIT
wait $FT_PID
