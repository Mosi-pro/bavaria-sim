#!/usr/bin/env bash
# Mehrspieler-Integrationstest: startet Host und Clients als getrennte Prozesse.
# Aufruf: tools/test_multiplayer.sh [Pfad zur Godot-Binärdatei]
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
PORT=$((24000 + RANDOM % 900))
TMP="$(mktemp -d)"
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=host --port=$PORT > "$TMP/host.log" 2>&1 &
HOST=$!
sleep 4
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=badclient --port=$PORT > "$TMP/bad.log" 2>&1
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=client --port=$PORT > "$TMP/client.log" 2>&1
wait $HOST
grep -hE "^(PASS|FAIL|RESULT)|SCRIPT ERROR" "$TMP"/host.log "$TMP"/bad.log "$TMP"/client.log
if grep -qE "^FAIL|SCRIPT ERROR" "$TMP"/*.log || [ "$(grep -c '^RESULT.*OK' "$TMP"/*.log | awk -F: '{s+=$2} END {print s}')" != "3" ]; then
  echo "MEHRSPIELERTEST FEHLGESCHLAGEN (Protokolle: $TMP)"; exit 1
fi
echo "MEHRSPIELERTEST BESTANDEN"; rm -rf "$TMP"
