# Tastaturübersicht+ (BTT Keyboard Overlay)

Ein Nachbau der macOS-Tastaturübersicht als schwebendes Overlay – mit einer
Erweiterung: Tasten, die von **BetterTouchTool** mit einer Text-Ersetzung
belegt sind (z. B. Fn+A → α), zeigen die BTT-Ersetzung statt des
System-Zeichens. Ohne Wortvorschläge.

## Funktionen

- **Live-Vorschau wie das Original**: Die Tasten zeigen, was der aktuelle
  Modifier-Zustand (⇧ ⌃ ⌥ ⌘ fn ⇪) erzeugen würde – berechnet mit
  `UCKeyTranslate` aus dem aktiven Tastaturlayout, also exakt das, was macOS
  tippen würde.
- **BTT-Ersetzungen**: Tastatur-Trigger mit der Aktion „Text einfügen“ werden
  direkt aus dem BTT-Datenstore gelesen und auf den Tasten angezeigt
  (blau markiert, kleiner Punkt in der Ecke). BTT hat Vorrang, weil BTT den
  Shortcut abfängt, bevor das Layout-Zeichen die App erreicht.
- **Akzenttasten (dead keys)** sind orange markiert. Nach Druck einer
  Akzenttaste (z. B. ´ oder ⌥U) zeigen die Tasten die komponierten Zeichen
  (á, é, ü, …) – wie im Original. `esc` bricht den Zustand ab.
- **Gedrückte Tasten leuchten** (braucht die Berechtigung
  „Eingabeüberwachung“).
- **Klickbare Modifier**: Ein Klick auf ⇧/⌥/fn … rastet den Modifier für die
  Vorschau ein – funktioniert auch ganz ohne Berechtigung.
- **Klick auf eine Zeichentaste kopiert das Zeichen** in die Zwischenablage.
- **F-Reihe** zeigt Mediensymbole, mit fn die F-Nummern.
- Layout-Wechsel (z. B. Deutsch → US) wird automatisch übernommen; Änderungen
  am BTT-Store werden beobachtet und neu geladen.
- Schwebendes, nicht aktivierendes Panel: bleibt über allen Fenstern und
  stiehlt keiner App den Fokus.

## Bauen & Starten

```bash
./build.sh
open "build/Tastaturübersicht+.app"
```

Beim ersten Start fragt macOS nach der Berechtigung **Eingabeüberwachung**
(Systemeinstellungen → Datenschutz & Sicherheit → Eingabeüberwachung).
Ohne sie zeigt das Overlay keine live gedrückten Tasten/Modifier; die
Vorschau per Klick auf die Modifier funktioniert trotzdem.

Zum Entwickeln reicht `swift build` bzw. `swift run KeyboardOverlay`.
Debug-Ausgabe der gefundenen BTT-Ersetzungen:

```bash
.build/debug/KeyboardOverlay --dump-btt
```

## Wie die BTT-Ersetzungen gelesen werden

BTT speichert seine Trigger in einem Core-Data-SQLite-Store unter
`~/Library/Application Support/BetterTouchTool/btt_data_store.version_*`.
Die App kopiert die Datenbank (inkl. WAL) in ein Temp-Verzeichnis und liest
aus `ZBTTBASEENTITY` alle Einträge der Entität `Gesture`:

- `ZKEYCODE` – virtueller Keycode, `ZMODIFIERKEYS` – CGEventFlags-Bits
  (`0x20000` ⇧, `0x40000` ⌃, `0x80000` ⌥, `0x100000` ⌘, `0x800000` fn)
- `ZACTIONDATA` – JSON mit `BTTActionTextToPaste`; der Text liegt in einem
  von drei Formaten vor:
  1. Klartext
  2. RTF (`{\rtf…`)
  3. Base64-kodiertes NSArchiver-„streamtyped“-Archiv (NSTextStorage);
     BTT nutzt dabei `_` statt `/` im Base64-Alphabet
- Einfüge-Aktionen hängen entweder direkt am Trigger oder als Kind-Eintrag
  (`ZPARENT` → Trigger mit Keycode/Modifiern).

## Grenzen

- Angezeigt werden BTT-Trigger vom Typ Tastatur-Shortcut mit Text-Aktion;
  Tastensequenzen (Schreibersetzungen über mehrere Tasten) und andere
  Aktionstypen erscheinen nicht.
- Physisches Layout ist das deutsche ISO-Layout eines Apple-Keyboards
  (MacBook / Magic Keyboard) ohne Ziffernblock.
