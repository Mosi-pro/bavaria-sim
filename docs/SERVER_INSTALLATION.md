# Vermittlungsdienst auf dem gemieteten Server installieren

Mit dem Vermittlungsdienst können Spieler über das Internet zusammen disponieren, ohne
selbst etwas einzurichten (keine Portfreigabe, keine IP-Adressen). Das Spiel ab Version
1.4.1 verbindet sich automatisch mit

    ws://v2202611458938560247.nicesrv.de:24180

Dauer: etwa 15 Minuten. Du brauchst nur deinen Windows-PC.

---

## 1. Paket herunterladen

Lade `LEITSTELLE112-Wyse-Vermittlung-<Version>.tar.gz` herunter (Releases auf GitHub
oder aus dem Chat) und lege es in deinen Ordner **Downloads**.

## 2. Datei auf den Server kopieren

Auf dem Windows-PC **PowerShell** öffnen (Startmenü → „PowerShell“) und eingeben
(Versionsnummer ggf. anpassen):

```
cd $HOME\Downloads
scp LEITSTELLE112-Wyse-Vermittlung-1.4.1.tar.gz root@v2202611458938560247.nicesrv.de:/root/
```

- Beim ersten Mal kommt die Frage „Are you sure you want to continue connecting?“ → `yes` eintippen.
- Danach nach dem **root-Passwort** des Servers gefragt (steht in der E-Mail bzw. im Kundenbereich
  deines Anbieters). Beim Tippen erscheinen keine Zeichen – das ist normal.

## 3. Am Server anmelden

```
ssh root@v2202611458938560247.nicesrv.de
```

Kurz prüfen, ob der Server passt:

```
uname -m
cat /etc/os-release | head -2
```

`uname -m` muss `x86_64` ausgeben. Unterstützt werden Debian 11/12/13 und Ubuntu 22.04/24.04.
(Bei `aarch64` ist es ein ARM-Server – dann bitte melden.)

## 4. Installieren

Weiter in derselben SSH-Sitzung:

```
mkdir -p /root/leitstelle && cd /root/leitstelle
tar -xzf /root/LEITSTELLE112-Wyse-Vermittlung-1.4.1.tar.gz
bash installieren.sh
```

Am Ende muss `active (running)` erscheinen.

## 5. Absichern (wichtig!)

```
bash absichern_vps.sh
```

Das schaltet die Firewall ein (offen bleiben nur SSH und Port 24180), aktiviert automatische
Sicherheitsupdates und sperrt IP-Adressen, die SSH-Passwörter durchprobieren (fail2ban).

> Nicht `absichern.sh` verwenden – das ist für den Wyse im Heimnetz und würde dich auf dem
> Mietserver aussperren.

## 6. Testen

Auf dem Server:

```
systemctl status leitstelle112-vermittlung --no-pager
journalctl -u leitstelle112-vermittlung -n 20 --no-pager
```

Auf dem Windows-PC (neue PowerShell):

```
Test-NetConnection v2202611458938560247.nicesrv.de -Port 24180
```

`TcpTestSucceeded : True` bedeutet: Der Dienst ist aus dem Internet erreichbar.

Im Spiel: Hauptmenü → **SPIEL ERSTELLEN** → „Über das Internet“ – es erscheint ein
Einladungscode. Mitspieler wählen **MULTIPLAYER**, geben den Code ein und sind drin.

Hat der Anbieter eine eigene Firewall im Kundenbereich (z. B. „Firewall“ im Server-Control-Panel),
dort ebenfalls **TCP 24180 eingehend** erlauben.

## Updates des Vermittlungsdienstes

Neues Paket wie in Schritt 2 hochladen, dann:

```
cd /root/leitstelle && tar -xzf /root/LEITSTELLE112-Wyse-Vermittlung-<Version>.tar.gz && bash installieren.sh
```

## Empfohlen: SSH-Schlüssel statt Passwort

Auf dem **Windows-PC** (PowerShell):

```
ssh-keygen -t ed25519
type $HOME\.ssh\id_ed25519.pub | ssh root@v2202611458938560247.nicesrv.de "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Danach testen, ob `ssh root@v2202611458938560247.nicesrv.de` **ohne Passwort** klappt.
Erst dann auf dem Server die Passwort-Anmeldung abschalten:

```
echo "PasswordAuthentication no" > /etc/ssh/sshd_config.d/10-nur-schluessel.conf
systemctl reload ssh
```

Wichtig: Den privaten Schlüssel (`id_ed25519` ohne `.pub`) niemals weitergeben und sichern.

## Sicherheit

- Auf dem Server läuft nur der Vermittlungsdienst unter einem eigenen Benutzer ohne Rechte
  (`leitstelle`), nicht als root. Er speichert keine Spielstände und keine Passwörter.
- Sitzungspasswörter werden nie im Klartext übertragen (Challenge-Response mit PBKDF2-HMAC-SHA256).
- Zugangsdaten zum Server (root-Passwort, Schlüssel) niemals in Chats, Discord oder E-Mails weitergeben.
