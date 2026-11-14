# Vermittlungsdienst auf dem Dell Wyse 5070 einrichten

Mit dem Vermittlungsdienst können Spieler über das Internet zusammen disponieren,
**ohne selbst etwas einzurichten**: Der Host bekommt einen Einladungscode, die Mitspieler
finden die Sitzung in der Serverliste oder geben den Code ein.

Der Dienst läuft bei dir zuhause auf dem Wyse. Er reicht die Spieldaten nur durch.
Die Simulation läuft weiter auf dem PC des Hosts, und Passwörter sieht der Dienst nie.

Einmaliger Aufwand: ca. 45 Minuten. Laufende Kosten: Strom, ca. 5 Watt.

---

## 0. Vorab prüfen: Hat dein Anschluss eine eigene öffentliche IPv4-Adresse?

Ohne eigene öffentliche IPv4-Adresse ist der Wyse von außen nicht erreichbar.

* **Fritzbox:** *Übersicht* → bei „Internet“ steht eine IPv4-Adresse, z. B. `91.x.x.x`.
  Steht dort „DS-Lite“ oder eine Adresse beginnend mit `100.64.` bis `100.127.`, hast du **keine** eigene IPv4.
* Im Zweifel beim Anbieter nachfragen. Viele Anbieter stellen auf Wunsch kostenlos auf eine eigene IPv4-Adresse um („Dual Stack“).

Hast du keine öffentliche IPv4-Adresse, muss der Dienst auf einem gemieteten Server laufen, z. B. einem Strato-V-Server.
Die Schritte 3 bis 6 gelten dort genauso, nur Schritt 4 (Router) entfällt.

---

## 1. Debian auf den Wyse installieren

Du brauchst einen USB-Stick (mind. 2 GB), Tastatur und Bildschirm. Diese brauchst du nur für die Einrichtung.

1. Auf einem anderen PC **Debian 12** („netinst“, amd64) von https://www.debian.org/download laden
   und mit **balenaEtcher** oder **Rufus** auf den USB-Stick schreiben.
2. Stick in den Wyse stecken, einschalten und sofort mehrmals **F12** drücken (Bootmenü) → USB-Stick wählen.
   * Startet der Stick nicht: Mit **F2** ins BIOS, dort *Secure Boot* ausschalten und *USB Boot* einschalten.
     Ist das BIOS gesperrt, lautet das Wyse-Standardpasswort bei vielen Geräten `Fireport`.
3. Installation („Install“, nicht „Graphical install“ nötig):
   * Sprache Deutsch, Rechnername z. B. `leitstelle`.
   * Root-Passwort und einen Benutzer anlegen (sichere Passwörter notieren!).
   * Festplatte: „Geführt – vollständige Festplatte verwenden“ (der interne eMMC-Speicher wird gelöscht).
   * Bei **Softwareauswahl**: *Debian-Desktop* und *GNOME* **abwählen**, nur
     **„SSH-Server“** und **„Standard-Systemwerkzeuge“** anhaken.
4. Nach dem Neustart anmelden und die IP-Adresse ablesen: `ip -4 addr` (z. B. `192.168.178.40`).

Ab jetzt kannst du Tastatur und Bildschirm abziehen und den Wyse von deinem PC aus bedienen:
`ssh deinbenutzer@192.168.178.40` (Windows: Eingabeaufforderung oder PowerShell).

## 2. Feste Adresse im Heimnetz

Damit die Portfreigabe dauerhaft stimmt, sollte der Wyse immer dieselbe Adresse im Heimnetz bekommen.

* **Fritzbox:** *Heimnetz* → *Netzwerk* → Gerät „leitstelle“ bearbeiten → **„Diesem Netzwerkgerät immer die gleiche IPv4-Adresse zuweisen“**.

## 3. Programm übertragen und installieren

1. Bei GitHub den neuesten Lauf von **„Build und Tests“** öffnen und das Paket
   **„LEITSTELLE112-Wyse-Vermittlung“** herunterladen und entpacken.
   Es enthält `leitstelle112.x86_64`, `installieren.sh` und `leitstelle112-vermittlung.service`.
2. Den Ordner auf den Wyse kopieren, z. B. von Windows aus:
   ```
   scp -r LEITSTELLE112-Wyse-Vermittlung deinbenutzer@192.168.178.40:~
   ```
3. Auf dem Wyse installieren:
   ```
   ssh deinbenutzer@192.168.178.40
   su -
   cd /home/deinbenutzer/LEITSTELLE112-Wyse-Vermittlung
   bash installieren.sh
   ```
   Am Ende muss „active (running)“ und „Vermittlungsdienst LEITSTELLE 112 gestartet“ erscheinen.

Der Dienst startet ab jetzt automatisch bei jedem Einschalten und nach Abstürzen neu.

4. **Absichern** (im selben Ordner, weiterhin als root):
   ```
   bash absichern.sh
   ```
   Das richtet die Firewall ein: eingehend nur Port 24180 und SSH nur aus dem Heimnetz.
   Außerdem darf der Wyse **keine anderen Geräte in deinem Heimnetz erreichen**, schaltet
   automatische Sicherheitsupdates ein und sperrt die root-Anmeldung per SSH.

## 4. Portfreigabe im Router

Freizugeben ist **TCP-Port 24180** auf den Wyse. Das gilt nur für deinen Router, nicht für den der Kunden.

* **Fritzbox:** *Internet* → *Freigaben* → *Portfreigaben* → *Gerät für Freigaben hinzufügen* →
  Gerät „leitstelle“ → *Neue Freigabe* → *Portfreigabe*: Protokoll **TCP**, Port **24180** an Gerät, Port **24180**,
  „Freigabe aktiv“ anhaken → *OK*.

## 5. Eigene Adresse mit Strato-DynDNS

Die öffentliche IP-Adresse deines Anschlusses ändert sich gelegentlich. DynDNS sorgt dafür,
dass z. B. `spiel.deinedomain.de` immer auf deinen Anschluss zeigt.

1. **Strato-Kundenlogin** → *Domains* → *Domainverwaltung* → bei deiner Domain eine **Subdomain** anlegen,
   z. B. `spiel`.
2. Bei der Subdomain → *DNS* → **DynDNS** aktivieren und ein **DynDNS-Passwort** festlegen.
3. **Fritzbox:** *Internet* → *Freigaben* → *DynDNS* → „DynDNS benutzen“ anhaken:
   * Anbieter: **Benutzerdefiniert**
   * Update-URL: `https://dyndns.strato.com/nic/update?hostname=<domain>&myip=<ipaddr>`
   * Domainname: `spiel.deinedomain.de`
   * Benutzername: `spiel.deinedomain.de`
   * Kennwort: das DynDNS-Passwort aus Schritt 2

   Die genaue Update-Adresse steht auch in der Strato-Hilfe unter „DynDNS“.
   Nach ein paar Minuten zeigt die Fritzbox bei DynDNS einen grünen Punkt.

## 6. Adresse ins Spiel eintragen

Die Adresse des Dienstes lautet dann: **`ws://spiel.deinedomain.de:24180`**

* **Am einfachsten:** Nenne mir die Adresse. Ich trage sie fest ein (`data/network.json`),
  und jede neue EXE verbindet sich automatisch damit. Die Kunden müssen nichts tun.
* Zum Ausprobieren vorher: im Spiel *Einstellungen* → *Netzwerk* → „Vermittlungsdienst (Internet)“ eintragen.

## 7. Testen

1. PC A: *SPIEL ERSTELLEN* → Verbindung „Internet“ → Einladungscode erscheint in der Lobby.
2. PC B, am besten in einem **anderen Netz**, z. B. Laptop am Handy-Hotspot: *MULTIPLAYER* →
   Sitzung in der Liste anklicken oder Code eingeben → *Verbinden*.
3. Protokoll auf dem Wyse ansehen: `journalctl -u leitstelle112-vermittlung -f`
   (zeigt „Sitzung … eröffnet“ und alle 10 Minuten eine Statusmeldung).

## Updates

Neues Paket herunterladen, auf den Wyse kopieren und erneut `bash installieren.sh` ausführen.

## Sicherheit und Datenschutz

* Der Wyse sollte **nur** diesen Dienst ausführen. Speichere keine privaten Daten darauf.
* Regelmäßig Updates einspielen: `su -` dann `apt update && apt upgrade`.
  Automatisch geht es mit `apt install unattended-upgrades`.
* Der Dienst begrenzt Verbindungen (max. 300), Sitzungen (max. 60), Spieler pro Sitzung (max. 12)
  und die Datenmenge pro Verbindung.
* Der Dienst sieht die IP-Adressen der Spieler. Er speichert sie nicht, sie erscheinen aber kurz im Protokoll.
  Bei einem öffentlichen Angebot gehört ein Hinweis in die Datenschutzerklärung.
* Die Verbindung ist derzeit unverschlüsselt (`ws://`). Passwörter werden trotzdem nie übertragen,
  weil der Host sie per Challenge-Response prüft. Spielinhalte sind keine sensiblen Daten.
  Eine Verschlüsselung (`wss://`) ist später z. B. mit dem Programm *Caddy* nachrüstbar.

## Wie viel hält der Wyse aus?

Eine Sitzung mit 4 Spielern erzeugt ca. 10–40 KB/s.
Ein Wyse 5070 und eine normale DSL-Leitung schaffen problemlos 10–20 gleichzeitige Sitzungen.
Der Dienst braucht ca. 100–150 MB Arbeitsspeicher.
