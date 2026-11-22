# Into the Abyss – Arbeitsregeln & Stand (ergänzt den Umzugsplan)

## Feste Regeln (vom Nutzer, gelten für jede Sitzung)
1. **Jede Karte hat ein eigenes Bild.** Keine zwei Karten teilen sich ein Artwork, auch keine neuen Karten. Bilder liegen in `CARD_ART` (54×54, Stil: kräftige Farben, dunkle Kontur, Glanzlinien) und werden über `SVG['card_' + key]` eingebunden.
2. **Neue Karten erscheinen automatisch im Glossar und in der Kartenvorschau der Klassenwahl.** Beides liest direkt aus `CARDS` (über `char`/`spec`). Neue Karten deshalb immer als normaler `CARDS`-Eintrag mit `spec`, `rarity` anlegen, nie als Sonderliste.
3. **Jede Regeländerung in der HTML wird sofort auch in der Godot-Engine nachgezogen** (`core/parts/*.gd`, danach `tools/export_data.sh`, `build.sh`, `tools/parity.sh`). Der Nutzer muss das nicht extra anfordern.
4. Für jede neue Spezialisierung: 2 Klassen-Modifikationen in `BUDDY_CLASS` (Build your Buddy) anlegen.
5. **Projekt-Sync macht Claude selbst**, auch für die HTML (`into-the-abyss.html` im Hauptordner). Das klappt, sobald die Datei einmal im Projekt liegt: zuerst `project_read`, dann `project_write` mit `local_path`. Der Nutzer muss nichts mehr hochladen.

## Kartenerweiterung (seit 22.11.2026)
- **Quelle:** pro Spezialisierung eine Datei `exp/<nr>_<spec>.js` neben der HTML. Sie enthält `addExpansion({karten}, {bilder})`.
  - `exp/inject.py` setzt alle Dateien zwischen die Marker `KARTEN-ERWEITERUNG START/ENDE` (vor `/* einbinden … */`).
  - Das Skript bricht bei doppelten Kartenschlüsseln ab.
  - `addExpansion` setzt `char` und `costConverted` und warnt, wenn eine Karte kein eigenes Bild hat.
- **Nur vorhandene Mechaniken verwenden.** Dann braucht Godot keinen neuen Code, der Datenexport genügt.
- **Kosten im 5-Energie-Maßstab.**
- **Aufwertung:**
  - Karten mit `fury`/`combo`/`reach` ohne andere Zahlenwerte werden beim Aufwerten 1 Energie billiger.
  - Karten ab 5 Energie werden beim Aufwerten immer billiger.
- **Ablauf pro Klasse:**
  - Bogen rendern mit `tools/exp_sheet.py <spec>`.
  - Simulation mit 24 Solo-Runs, vorher/nachher.
  - Godot-Export, Kompiliertest und `parity.sh`.
- **Fertig:**
  - Knockout Champion: Solo-Raum 7,6 → 8,75.
  - Drunk Master: 6,8 → 6,7.
  - Street Fighter at Night: 8,9 → 8,4.
  - Insgesamt 54 Karten. Parität ok.
- **Offen:** Knight (Templar, Barbarian, Gladiator), Mage (Fire, Ice, Storm), Assassin (Thief, Assassin, Deathbringer), Ranger (Deadeye, Stormweaver, Rift), Soulbinder (Chainweaver, Runebinder, Soulforger), Eldritch (Acolyte, Dreamweaver, Tidecaller).

## Auto-Update (Godot, seit 22.11.2026)
- **Startszene `boot/boot.tscn`:**
  - Lädt `user://update.pck`, wenn dessen Version höher ist als die eingebaute.
  - Fragt `https://github.com/<REPO>/releases/latest/download/latest.json` ab.
  - Lädt eine neuere `game.pck`, prüft SHA-256, aktiviert sie und startet das Spiel.
  - Offline oder bei Fehler startet die alte Version. Bei neuer Godot-Version kommt ein Hinweis auf das Komplettpaket.
- **`tools/release.sh [--full]`:**
  - Zählt `version.json` hoch, exportiert `game.pck` (ca. 1,2 MB) und erzeugt `latest.json`.
  - `--full` legt zusätzlich `IntoTheAbyss.zip` an (exe + pck, ca. 34 MB).
  - Lädt alles per `gh release create` hoch.
- **Einrichtung:** `tools/release.cfg` (`REPO=besitzer/repo`) braucht ein öffentliches GitHub-Repo. Noch nicht eingerichtet.
- **Koop:** `Game.game_version()` und `Game.version_mismatch_text(host_v)` sind fertig. Sie werden in Phase 3 in den Verbindungs-Handshake eingebaut.

## Stand 22.11.2026, 11:40
- Godot-Engine = HTML-Regelstand, inklusive der neuen Karten (Datenexport). Parität ok.
- Angriffssymbole: Area Attack sind jetzt drei Meteore, Splash ist das frühere Area-Symbol.
- Danach: Godot Phase 2 (Oberfläche) und Phase 3 (Koop/Export).
