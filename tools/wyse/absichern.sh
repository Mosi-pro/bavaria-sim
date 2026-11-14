#!/usr/bin/env bash
# Sichert den Wyse für den Betrieb im Heimnetz ab (einmalig nach installieren.sh ausführen, als root).
#  * Eingehend nur Port 24180 (Vermittlung) aus dem Internet und SSH NUR aus dem Heimnetz
#  * Der Wyse darf keine Geräte im Heimnetz ansprechen (außer dem Router für DNS/Zeit)
#    -> selbst wenn jemand den Wyse übernehmen würde, käme er nicht an deine anderen Geräte
#  * Automatische Sicherheitsupdates, kein root-Login per SSH
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "Bitte als root ausführen (su -)."; exit 1; }
GW=$(ip -4 route show default | awk '{print $3; exit}')
NET=$(ip -4 route show scope link | awk '$1 ~ /\// {print $1; exit}')
[ -n "$GW" ] && [ -n "$NET" ] || { echo "Heimnetz konnte nicht erkannt werden (Router: '$GW', Netz: '$NET')."; exit 1; }
echo "Router: $GW   Heimnetz: $NET"
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q ufw unattended-upgrades >/dev/null
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow 24180/tcp comment 'LEITSTELLE 112 Vermittlung'
ufw allow from "$NET" to any port 22 proto tcp comment 'SSH nur aus dem Heimnetz'
ufw allow out to "$GW" comment 'Router (DNS, Zeit, DHCP)'
ufw deny out to 10.0.0.0/8 comment 'kein Zugriff auf Heimnetz'
ufw deny out to 172.16.0.0/12 comment 'kein Zugriff auf Heimnetz'
ufw deny out to 192.168.0.0/16 comment 'kein Zugriff auf Heimnetz'
ufw deny out to fd00::/8 comment 'kein Zugriff auf Heimnetz (IPv6)'
ufw --force enable
echo 'APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";' > /etc/apt/apt.conf.d/20auto-upgrades
if grep -qE '^#?PermitRootLogin' /etc/ssh/sshd_config; then
  sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
else
  echo 'PermitRootLogin no' >> /etc/ssh/sshd_config
fi
systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
echo
ufw status verbose
echo
echo "Fertig. SSH-Anmeldung ab jetzt mit deinem normalen Benutzer (danach 'su -' für root)."
