# Windows-Version erstellen

Ergebnis: `build/windows/LEITSTELLE112.exe` (eigenständig, Spieldaten eingebettet) und
`build/installer/LEITSTELLE112_Setup_1.0.0.exe` (Inno-Setup-Installer).

## Variante A – automatisch über GitHub Actions (empfohlen)

Jeder Push startet `.github/workflows/build.yml`:

1. **tests** (Linux): 81 Kerntests und der Mehrspielertest mit drei Prozessen.
2. **windows** (Windows Server): Export der EXE, **Selbsttest der EXE unter Windows**, Bau des Installers.

Die fertigen Dateien stehen im Workflow-Lauf unter *Artifacts → LEITSTELLE112-Windows* zum Download.

## Variante B – unter Windows von Hand

1. **Godot 4.7.1** (Standard-Version, nicht .NET) von https://godotengine.org/download/archive/ laden und entpacken.
2. Im Godot-Editor das Projekt öffnen (`project.godot`) → *Editor → Exportvorlagen verwalten → Herunterladen und installieren*.
3. *Projekt → Exportieren …* → Vorlage **Windows Desktop** → *Projekt exportieren* → `build\windows\LEITSTELLE112.exe`
   (Ohne `rcedit` erhält die EXE das Standardsymbol; mit rcedit unter *Editoreinstellungen → Export → Windows* das eigene Symbol.)
4. Begleitdateien kopieren:
   ```bat
   mkdir build\windows\config build\windows\config_standard\world
   copy data\*.json build\windows\config_standard\
   copy data\world\*.json build\windows\config_standard\world\
   copy packaging\config_README.txt build\windows\config\LIESMICH.txt
   copy packaging\LIESMICH.txt build\windows\
   copy packaging\LIZENZHINWEISE.txt build\windows\
   ```
5. **Inno Setup 6** installieren (https://jrsoftware.org/isinfo.php) und ausführen:
   ```bat
   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" installer\LEITSTELLE112.iss
   ```
6. Prüfen: `build\windows\LEITSTELLE112.exe --headless --selbsttest --log-file selbsttest.log` → `SELBSTTEST BESTANDEN`.

## Variante C – unter Linux (so wurde der mitgelieferte Build erstellt)

```bash
# Godot 4.7.1 (Linux) als "godot" im PATH, Exportvorlagen unter ~/.local/share/godot/export_templates/4.7.1.stable
# optional: rcedit-x64.exe + wine für das Programmsymbol (Editoreinstellung export/windows/rcedit)
# Inno Setup 6 unter Wine (32-bit-Wine erforderlich: dpkg --add-architecture i386; apt install wine32:i386)
ISCC="wine C:\\InnoSetup\\ISCC.exe" xvfb-run -a tools/build_windows.sh
```

`tools/build_windows.sh` importiert die Ressourcen, exportiert die EXE, kopiert Standardkonfiguration
und Begleitdateien und baut – sofern `ISCC` verfügbar ist – den Installer.

## Der Installer

* Auswahl des Installationsverzeichnisses (Standard: `C:\Program Files\LEITSTELLE 112`)
* Startmenüeintrag, optional Desktopverknüpfung
* Deinstallation über *Einstellungen → Apps* oder Startmenü „LEITSTELLE 112 entfernen“
* Keine weiteren Laufzeitumgebungen erforderlich (kein Godot, Python, .NET o. ä.)

Spielstände, Einstellungen und die lokale Datenbank liegen unter `%APPDATA%\LEITSTELLE112`
und bleiben bei einer Deinstallation erhalten.

## Systemvoraussetzungen

Windows 10/11 64 Bit, Grafikkarte mit Vulkan-Unterstützung (Forward+-Renderer), aktueller Grafiktreiber.

## Hilfswerkzeuge

* `python3 tools/gen_stations.py` – erzeugt `data/stations.json` neu (überschreibt Handänderungen!)
* `python3 tools/gen_audio.py` – erzeugt alle Töne neu (benötigt numpy)
