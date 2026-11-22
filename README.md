# Into the Abyss

Koop-Roguelike-Deckbuilder für 1–4 Spieler (rundenbasiert, 7 Klassen, 21 Spezialisierungen, 4 Biome).

## Download {#download}

**Windows:** [IntoTheAbyss.zip herunterladen](https://github.com/Naduos/into-the-abyss/raw/main/download/IntoTheAbyss.zip)

1. ZIP entpacken (beide Dateien `IntoTheAbyss.exe` und `IntoTheAbyss.pck` müssen im selben Ordner liegen).
2. `IntoTheAbyss.exe` starten.
3. Beim ersten Start zeigt Windows evtl. „Der Computer wurde durch Windows geschützt“ (SmartScreen), weil die Datei nicht signiert ist: **Weitere Informationen → Trotzdem ausführen**. Das kommt nur einmal.

## Updates

Das Spiel aktualisiert sich **beim Start automatisch** (lädt nur die geänderten Spieldaten, ca. 3 MB). Ohne Internet startet es einfach mit der vorhandenen Version. Nur wenn sich die Godot-Engine ändert, muss die ZIP neu geladen werden – das Spiel sagt dann Bescheid.

## Koop

- **Host:** „Host Co-op“ klicken. Im Heimnetz verbinden sich Freunde über die angezeigte LAN-Adresse. Übers Internet öffnet das Spiel den Port per UPnP automatisch; klappt das nicht, im Router **UDP-Port 24565** freigeben.
- **Mitspieler:** IP des Hosts eingeben, „Join“.
- Der Host wählt die Helden und verteilt sie auf die Spieler. Alle brauchen dieselbe Version (wird beim Verbinden geprüft – einfach neu starten, dann wird aktualisiert).

## Browser-Version

`into-the-abyss.html` herunterladen und im Browser öffnen.

## Inhalt des Repos

- `download/` – Komplettpaket für Windows
- `updates/` – automatische Updates (`latest.json` + Spieldaten)
- `source/` – Quelltext (Godot-Projekt und Kartenerweiterungen)
