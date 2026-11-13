LEITSTELLE 112 – eigene Konfiguration
=====================================

Dieser Ordner ist für eigene Anpassungen vorgesehen. Legen Sie hier eine Kopie einer
Datei aus dem Ordner "config_standard" ab und bearbeiten Sie sie. Beim Programmstart
haben Dateien in diesem Ordner Vorrang vor der eingebauten Standardkonfiguration.

  vehicle_types.json   Fahrzeugtypen, Geschwindigkeiten, Besatzung, Ausrüstung, Preise
  stations.json        Wachen, Fahrzeugbestand, Krankenhäuser
  incident_types.json  Einsatzstichwörter, Alarmierungsvorschläge und Einsatzlogik
  call_scripts.json    Gesprächsbausteine der Notrufe
  fms_status.json      FMS-Statusbezeichnungen, Farben und Funksprüche
  game_modes.json      Schwierigkeitsgrade, Tageskurven, Wetter, Karriere, Rollen
  scenarios.json       Szenarien
  organisations.json   Organisationen und Funkrufnamen
  world/bavaria.json   Stadtgeografie (Stadtteile, Autobahnen, Flüsse, Objekte)

Unterordner bitte beibehalten (z. B. config\world\bavaria.json).
Fehlerhafte Dateien werden ignoriert; dann gilt die Standardkonfiguration.
Spielstände, Einstellungen und die lokale Datenbank liegen unter
%APPDATA%\LEITSTELLE112
