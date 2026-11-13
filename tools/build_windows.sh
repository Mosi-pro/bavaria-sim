#!/usr/bin/env bash
# Erstellt den Windows-Build (EXE) und den Installer.
#   tools/build_windows.sh [godot-binärdatei]
# Voraussetzungen siehe BUILD.md (Godot 4.7.1 + Exportvorlagen; für den Installer Inno Setup 6,
# unter Linux über Wine: Umgebungsvariable ISCC="wine C:\\InnoSetup\\ISCC.exe").
set -euo pipefail
GODOT="${1:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/windows"
cd "$ROOT"
rm -rf "$OUT" && mkdir -p "$OUT/config" "$OUT/config_standard/world" "$ROOT/build/installer"
echo "== Ressourcen importieren"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
echo "== Windows-Export"
"$GODOT" --headless --path . --export-release "Windows Desktop" "$OUT/LEITSTELLE112.exe" 2>&1 | grep -vE "^\s*$" | grep -iE "error|warn|export" || true
test -s "$OUT/LEITSTELLE112.exe" || { echo "Export fehlgeschlagen"; exit 1; }
echo "== Standardkonfiguration und Begleitdateien"
cp data/*.json "$OUT/config_standard/"
cp data/world/*.json "$OUT/config_standard/world/"
cp packaging/config_README.txt "$OUT/config/LIESMICH.txt"
cp packaging/LIESMICH.txt "$OUT/LIESMICH.txt"
cp packaging/LIZENZHINWEISE.txt "$OUT/LIZENZHINWEISE.txt"
ls -la "$OUT"
if [ -n "${ISCC:-}" ] || command -v iscc >/dev/null 2>&1; then
  echo "== Installer (Inno Setup)"
  ${ISCC:-iscc} /Q installer/LEITSTELLE112.iss
  ls -la build/installer
else
  echo "Hinweis: Inno Setup (ISCC) nicht gefunden – Installer wurde nicht erstellt."
fi
