# Into the Abyss

Koop-Roguelike-Deckbuilder für 1–4 Spieler (rundenbasiert, 7 Klassen, 21 Spezialisierungen, 4 Biome).

## Download {#download}

**Windows 10/11:** [IntoTheAbyss.zip herunterladen](https://github.com/Naduos/into-the-abyss/raw/main/download/IntoTheAbyss.zip)

1. ZIP entpacken. Alle drei Dateien (`IntoTheAbyss.exe`, `IntoTheAbyss.pck`, `godot_wry.dll`) müssen im selben Ordner liegen.
2. `IntoTheAbyss.exe` starten.
3. Beim ersten Start zeigt Windows evtl. „Der Computer wurde durch Windows geschützt“ (SmartScreen), weil die Datei nicht signiert ist: **Weitere Informationen → Trotzdem ausführen**. Das kommt nur einmal.

Die exe zeigt genau dieselbe Oberfläche wie die Browser-Version (eingebautes Browserfenster über Microsoft WebView2, unter Windows 10/11 vorinstalliert). **F11** schaltet Vollbild um.

## Updates

Das Spiel aktualisiert sich **beim Start automatisch** (lädt nur die geänderten Spieldaten, wenige MB). Ohne Internet startet es einfach mit der vorhandenen Version. Nur wenn sich die Programmdatei selbst ändert, muss die ZIP neu geladen werden – das Spiel sagt dann Bescheid.

**Ab Version 3 einmal die ZIP neu herunterladen** (die neue Oberfläche braucht die Datei `godot_wry.dll`).

## Koop

- **Host:** „Host Co-op“ klicken. Die Lobby zeigt einen 4-Buchstaben-Code und die IP-Adressen (Heimnetz und Internet).
- **Mitspieler:** „Join Co-op“ und entweder den **Code** (braucht Internet, keine Portfreigabe nötig) oder die **IP-Adresse** des Hosts eingeben.
- Direktverbindung per IP: Im Heimnetz die LAN-Adresse nehmen. Übers Internet öffnet das Spiel **UDP-Port 24565** per UPnP automatisch; klappt das nicht, den Port im Router freigeben.
- Alle brauchen dieselbe Version (wird beim Verbinden per IP geprüft – einfach neu starten, dann wird aktualisiert).

## Browser-Version

`into-the-abyss.html` herunterladen und im Browser öffnen (Koop dort per Code).

## Inhalt des Repos

- `download/` – Komplettpaket für Windows
- `updates/` – automatische Updates (`latest.json` + Spieldaten)
- `source/` – Quelltext (Godot-Projekt und Kartenerweiterungen)

Verwendet [godot_wry](https://github.com/doceazedo/godot_wry) (MIT-Lizenz) für das eingebaute Browserfenster.
