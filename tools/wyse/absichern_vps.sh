#!/usr/bin/env bash
# Absicherung für einen gemieteten Server (VPS / Root-Server im Rechenzentrum).
# NICHT das Heimnetz-Skript absichern.sh verwenden – das würde SSH auf das Heimnetz beschränken
# und dich auf einem Mietserver aussperren.
#  * Eingehend nur SSH (22, mit Schutz gegen Passwort-Raten) und Port 24180 (Vermittlung)
#  * Automatische Sicherheitsupdates
#  * fail2ban sperrt IP-Adressen nach mehreren falschen SSH-Anmeldungen
# Aufruf als root:  bash absichern_vps.sh
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "Bitte als root ausführen."; exit 1; }
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q ufw unattended-upgrades fail2ban >/dev/null
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw limit 22/tcp comment 'SSH (mit Begrenzung)'
ufw allow 24180/tcp comment 'LEITSTELLE 112 Vermittlung'
ufw --force enable
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
cat > /etc/fail2ban/jail.d/sshd.local <<'JAIL'
[sshd]
enabled = true
backend = systemd
maxretry = 5
bantime = 1h
JAIL
systemctl enable --now fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban || true
echo
ufw status verbose
echo
echo "Fertig. Offen sind nur SSH (22) und die Vermittlung (24180)."
echo "Root-Anmeldung per SSH bleibt erlaubt, damit du dich nicht aussperrst."
echo "Empfehlung: SSH-Schlüssel einrichten und danach Passwort-Anmeldung abschalten (siehe Anleitung)."
