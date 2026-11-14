#!/usr/bin/env bash
# Installiert bzw. aktualisiert den LEITSTELLE-112-Vermittlungsdienst auf einem Debian-PC (z. B. Dell Wyse 5070).
# Aufruf (als root, im Ordner mit diesem Skript und der Datei leitstelle112.x86_64):
#   sudo bash installieren.sh
set -euo pipefail
cd "$(dirname "$0")"
test -f leitstelle112.x86_64 || { echo "Datei leitstelle112.x86_64 fehlt im selben Ordner."; exit 1; }
id leitstelle >/dev/null 2>&1 || useradd --system --create-home --shell /usr/sbin/nologin leitstelle
install -d -o leitstelle -g leitstelle /opt/leitstelle112
install -m 0755 -o leitstelle -g leitstelle leitstelle112.x86_64 /opt/leitstelle112/leitstelle112.x86_64
install -m 0644 leitstelle112-vermittlung.service /etc/systemd/system/leitstelle112-vermittlung.service
# benötigte Bibliotheken für den Headless-Betrieb
apt-get install -y -q libfontconfig1 >/dev/null || true
if command -v ufw >/dev/null 2>&1; then ufw allow 24180/tcp >/dev/null || true; fi
systemctl daemon-reload
systemctl enable --now leitstelle112-vermittlung
systemctl restart leitstelle112-vermittlung
sleep 3
systemctl --no-pager --lines=5 status leitstelle112-vermittlung || true
echo
echo "Fertig. Protokoll ansehen mit:  journalctl -u leitstelle112-vermittlung -f"
