#!/usr/bin/env bash
# Setzt die Versionsnummer überall (Spiel, Windows-EXE-Ressourcen, Installer).
#   tools/set_version.sh 1.2.0
set -euo pipefail
V="${1:?Version angeben, z. B. 1.2.0}"
cd "$(dirname "$0")/.."
sed -i "s/^config\/version=\".*\"/config\/version=\"$V\"/" project.godot
sed -i "s/^application\/file_version=\".*\"/application\/file_version=\"$V.0\"/; s/^application\/product_version=\".*\"/application\/product_version=\"$V.0\"/" export_presets.cfg
sed -i "s/^#define AppVersion \".*\"/#define AppVersion \"$V\"/" installer/LEITSTELLE112.iss
grep -h "config/version\|file_version\|AppVersion \"" project.godot export_presets.cfg installer/LEITSTELLE112.iss
