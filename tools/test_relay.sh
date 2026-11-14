#!/usr/bin/env bash
# Mehrspielertest über den Vermittlungsdienst: Vermittlung + Host + 2 Clients als getrennte Prozesse.
set -u
GODOT="${1:-godot}"
cd "$(dirname "$0")/.."
PORT=$((25000 + RANDOM % 900))
TMP="$(mktemp -d)"
"$GODOT" --headless --path . -- --vermittlung --port=$PORT > "$TMP/relay.log" 2>&1 &
RELAY=$!
sleep 4
ARGS="--relay=ws://127.0.0.1:$PORT --codefile=$TMP/code.txt --port=$((PORT+500))"
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=host $ARGS > "$TMP/host.log" 2>&1 &
HOST=$!
for i in $(seq 1 40); do [ -s "$TMP/code.txt" ] && break; sleep 0.5; done
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=badclient $ARGS > "$TMP/bad.log" 2>&1
"$GODOT" --headless --path . res://tests/net_test.tscn -- --role=client $ARGS > "$TMP/client.log" 2>&1
wait $HOST
kill $RELAY 2>/dev/null
grep -hE "^(PASS|FAIL|RESULT)|SCRIPT ERROR" "$TMP"/host.log "$TMP"/bad.log "$TMP"/client.log
grep -h "Sitzung\|gestartet" "$TMP/relay.log" | head -5
if grep -qE "^FAIL|SCRIPT ERROR" "$TMP"/*.log || [ "$(grep -c '^RESULT.*OK' "$TMP"/host.log "$TMP"/bad.log "$TMP"/client.log | awk -F: '{s+=$2} END {print s}')" != "3" ]; then
  echo "VERMITTLUNGSTEST FEHLGESCHLAGEN (Protokolle: $TMP)"; exit 1
fi
echo "VERMITTLUNGSTEST BESTANDEN"; rm -rf "$TMP"
