#!/usr/bin/env bash
# Ein-Befehl-Installation bzw. Update des LEITSTELLE-112-Vermittlungsdienstes auf einem
# gemieteten Linux-Server (Debian/Ubuntu, x86_64). Aufruf als root in der Server-Konsole:
#   curl -fsSL https://github.com/Mosi-pro/bavaria-sim/releases/latest/download/server.sh | bash
# oder (falls curl fehlt):
#   wget -qO- https://github.com/Mosi-pro/bavaria-sim/releases/latest/download/server.sh | bash
set -euo pipefail
URL="https://github.com/Mosi-pro/bavaria-sim/releases/latest/download/LEITSTELLE112-Server.tar.gz"
[ "$(id -u)" = "0" ] || { echo "Bitte als root ausführen (Anmeldung als root)."; exit 1; }
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] || { echo "Dieser Server hat die Architektur $ARCH – unterstützt wird nur x86_64."; exit 1; }
echo "== LEITSTELLE 112 – Vermittlungsdienst wird installiert =="
export DEBIAN_FRONTEND=noninteractive
command -v curl >/dev/null 2>&1 || { apt-get update -q && apt-get install -y -q curl ca-certificates >/dev/null; }
mkdir -p /root/leitstelle
cd /root/leitstelle
curl -fsSL -o paket.tar.gz "$URL"
tar -xzf paket.tar.gz
rm -f paket.tar.gz
bash installieren.sh
bash absichern_vps.sh
echo
if systemctl is-active --quiet leitstelle112-vermittlung; then
  echo "=================================================================="
  echo " FERTIG: Der Vermittlungsdienst läuft und startet automatisch neu."
  echo " Spieler verbinden sich automatisch (Port 24180)."
  echo " Update später: denselben Befehl einfach nochmal ausführen."
  echo "=================================================================="
else
  echo "Der Dienst läuft nicht. Protokoll:"
  journalctl -u leitstelle112-vermittlung -n 30 --no-pager || true
  exit 1
fi
