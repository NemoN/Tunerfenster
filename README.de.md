# Tunerfenster

[English](README.md) · [Deutsch](README.de.md)

<img src="docs/icon.png" width="96" height="96" alt="Tunerfenster-Symbol">

Tunerfenster ist eine native macOS-App für TVHeadend-Streams. Du kannst alle
Tuner als Mosaik anzeigen, einen Sender mit Programmführer und Logo ansehen
oder Aufzeichnungen vom Server abspielen.

## Download

Benötigt macOS 14 oder neuer. VLC ist enthalten.

| Dein Mac | Signierte und notarisierte Installationsdatei |
| --- | --- |
| Apple Silicon (M1 oder neuer) | [arm64-DMG herunterladen](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-1.9.0-arm64.dmg) |
| Intel (64 Bit) | [x64-DMG herunterladen](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-1.9.0-x86_64.dmg) |

[Alle Releases und SHA-256-Prüfsummen](https://github.com/NemoN/Tunerfenster/releases)

1. Die DMG öffnen und **Tunerfenster** in **Applications / Programme** ziehen.
2. Die App starten und **Tunerfenster → Einstellungen** öffnen.
3. TVHeadend-Adresse, Benutzername und Passwort eingeben und verbinden.

Deine Einstellungen bleiben bei Updates erhalten. Die App startet stumm.

## Screenshots

Die Screenshots zeigen einen lokalen Demo-Server mit erfundenen Sendern und
erzeugten Testsignalen. Sie enthalten keine Fernsehaufnahmen oder privaten
Servereinstellungen.

### Tuner-Mosaik

![Tuner-Mosaik auf Deutsch](docs/screenshots/mosaic-de.png)

### TV-Modus mit EPG und Senderlogo

![TV-Modus und Programmführer auf Deutsch](docs/screenshots/tv-de.png)

### Empfangsdaten

![Empfangsinformationen auf Deutsch](docs/screenshots/reception-de.png)

## Funktionen

- Das Mosaik passt alle Tuner ins Fenster ein. Im TV-Modus läuft nur der gewählte
  Tuner. Der Programmführer zeigt die laufende und nächste Sendung mit
  Beschreibung und Fortschritt.
- Automatische Kacheln zeigen Sender, die bereits auf dem Server laufen. Freie
  Tuner und EPG-Abfragen haben eigene Statusanzeigen.
- Du kannst für jede Kachel einen Sender wählen. Die Liste öffnet sich beim
  aktuellen Sender; ein Doppelklick oder **Sender wechseln** schaltet um.
  **Alle auf Folgen** setzt die manuellen Zuordnungen zurück.
- Zu den Empfangsdaten gehören Frequenz, V/H, LOW/HIGH, Empfangsart, Modulation,
  Symbolrate, FEC, Satellitenposition, Signal, SNR und CC-Fehler, soweit TVHeadend
  sie liefert.
- Picons aus TVHeadend, einschließlich SRP-Picons, erscheinen in der vergrößerten
  Ansicht neben dem Sendernamen.
- Beim Vergrößern einer Kachel schaltet sich ihr Ton ein. Die Rückkehr ins Mosaik
  schaltet ihn stumm. Mit **M** schaltest du den Ton um. Sind im Mosaik alle
  Streams stumm, schaltet **M** den Ton des ersten aktiven Streams ein.
- Das Statistiksymbol über dem vergrößerten Video blendet VLCs Eingangs-,
  Demux-, Video- und Audiozähler ins Bild ein. Die Werte werden jede Sekunde aktualisiert.
- Die App merkt sich manuelle Sender, Modus und gewählten TV-Tuner für jeden
  Server und Benutzer. Diese Auswahl bleibt auch bei vorübergehenden Ausfällen
  erhalten.
- Du kannst in der App zwischen Deutsch und Englisch wechseln. Menüs,
  Einstellungen und Statusmeldungen verwenden die gewählte Sprache.
- Ein Klick auf das Darstellungssymbol direkt vor den Einstellungen wechselt
  zwischen „System folgen“, „Hell“ und „Dunkel“. Die Auswahl wird gespeichert.
- Im EPG des TV-Modus startet **Aufnehmen** eine Aufnahme auf
  TVHeadend. Dafür braucht dein Benutzer Aufnahmerechte und ein aktives
  Aufnahmeprofil. Das EPG-Ende und der eingestellte Nachlauf bestimmen das Ende;
  vorhandene Aufnahmen werden angezeigt. Während der Aufnahme pulsiert der rote
  Button. **Aufnahme stoppen** beendet die Aufnahme und behält die bisherige Datei.
- Sender hoch/runter und **Sender wählen** stehen vor **Alle belegen**.
  In der Einzelansicht stehen Frequenz, Signal, SNR, Datenrate und CC-Fehler
  unter dem EPG.
- Die Wiedergabe nutzt VLCKit 3.7.4 / libVLC 3.0.24. Es gibt getrennte Builds
  für Apple Silicon und Intel.
- **Aufnahmen** zeigt aufgezeichnete Sendungen und laufende Aufnahmen. Suche
  nach Titel oder Sender und wähle eine Aufnahme zum Abspielen. Der Player bietet
  Pause, Zeitleiste und Tonsteuerung. Eine ungefähre Dauer aus TVHeadend ist mit
  **≈** markiert, wenn VLC die Dateidauer nicht ermitteln kann. Nicht verfügbare
  Dateien sind gekennzeichnet. Beim Wechsel zu Aufnahmen stoppen die Live-Streams
  der App; deine Senderzuordnungen bleiben gespeichert.

Die Titelzeile zeigt die installierte Version. Wie oft die App den Tunerstatus
abfragt, stellst du in den Einstellungen oder rechts unten im Fenster ein.
Das Intervall kann 1 bis 60 Sekunden betragen und wird automatisch gespeichert.

In der vergrößerten Ansicht wechseln **↑ / ↓** und die Pfeilbuttons die Sender
in Listenreihenfolge. Nach dem letzten Sender folgt wieder der erste, beim
Zurückschalten nach dem ersten der letzte.
Vollbild zeigt nur das Video. **Esc** beendet das Vollbild, ein weiteres **Esc**
führt zurück ins Mosaik.
Mit **⌘1**, **⌘2** und **⌘3** wechselst du zwischen Mosaik, TV und Aufnahmen.
Die App merkt sich den zuletzt verwendeten Modus. Eine gewählte Aufnahme startet
mit Ton; **M** schaltet ihn stumm oder wieder ein. **⌘P** pausiert die Wiedergabe
oder setzt sie fort.

## Softwareupdates

Während die App läuft, prüft sie GitHub einmal täglich auf eine neuere stabile
Version. Ist eine verfügbar, bietet **Update ansehen** die DMG für deinen Mac an.
Die App erkennt Apple Silicon auch dann, wenn die Intel-Version unter Rosetta läuft.

Über **Tunerfenster → Nach Updates suchen …** kannst du jederzeit prüfen. Die
automatische Prüfung lässt sich in den Einstellungen oder im Fenster
Softwareupdates abschalten. Zum Installieren lädst du die DMG im Browser,
beendest Tunerfenster und ersetzt die App. Deine Einstellungen bleiben erhalten.
Du installierst Updates selbst. Die Prüfung sendet keine TVHeadend-Adresse,
Zugangsdaten oder Tunerdaten an GitHub.

## Arbeitsweise

Tunerfenster liest TVHeadends Status-, Service-, Sender- und EPG-APIs. Die App
öffnet HTTP-Streams mit niedriger Priorität und kurzlebigen Wiedergabetickets.
Automatische Streams enden, wenn der externe Zuschauer den Sender verlässt.
Im TV-Modus stoppen die übrigen Streams. Die App lässt die Tuner-, Sender-
und Aufnahmeeinstellungen unverändert.

TVHeadend wählt den physischen Tuner für jeden Stream. Die manuelle Auswahl
legt den Service für eine Kachel fest. Über die HTTP-API kann die App keinen
bestimmten Hardware-Eingang für diesen Stream reservieren.

Die App berechnet LOW/HIGH aus der gemeldeten Frequenz. Die Grenze liegt
standardmäßig bei 11700 MHz und lässt sich in den Einstellungen ändern. Der
Wert misst nicht den DiSEqC- oder 22-kHz-Schaltzustand.

## Serverzugriff und Datenschutz

Dein TVHeadend-Benutzer braucht Streamingrechte und Zugriff auf die Status- und
Katalog-APIs. Je nach Serverkonfiguration können Service-Streams die
Berechtigung **Advanced streaming** und Statusabfragen Administratorrechte
erfordern. Die App unterstützt Digest, Basic und Verbindungen ohne Anmeldung.
Für den Aufnahmebutton ist zusätzlich die TVHeadend-Berechtigung **Video
Recorder → Basic** nötig. Die Aufnahme wird auf dem Server gespeichert und läuft
auch dann weiter, wenn du den Sender wechselst oder Tunerfenster beendest.

Die App speichert Passwörter im macOS-Schlüsselbund. Die gespeicherten Sender-
und Ansichtseinstellungen enthalten Service-IDs und Tunernamen. Passwörter und
Wiedergabetickets stehen dort nicht. Die Verbindung richtest du direkt in der
App ein. Ein MCP-Server ist dafür nicht nötig.

## Selbst bauen

Zum Bauen brauchst du Xcode oder geeignete macOS-Entwicklerwerkzeuge mit Swift
5.9 oder neuer.
Die DMG-Skripte verwenden die `diskutil image`-Befehle von macOS 27.

```bash
git clone https://github.com/NemoN/Tunerfenster.git
cd Tunerfenster
chmod +x ./*.sh scripts/*.sh
./build-app.sh --no-bootstrap
open dist/Tunerfenster.app
```

Der Build lädt das offizielle VideoLAN-Framework in der festgelegten Version,
prüft seine SHA-256-Prüfsumme und bündelt den Code für die gewählte
CPU-Architektur. Git ignoriert Build-Ausgaben und den Download-Cache.

Lokale Builds werden ad hoc signiert, sofern kein festes Signaturzertifikat
hinterlegt ist. Ein festes Zertifikat erhält den Schlüsselbundzugriff über
mehrere Builds hinweg. Die [Einrichtung steht in der Bauanleitung](docs/BUILDING.md#local-build).

Weitere Befehle stehen unter [Bauen, Testen und notarisierte Releases](docs/BUILDING.md).

## Drittanbieter-Software

Für den Tunerfenster-Quellcode ist noch keine Lizenz festgelegt.
Drittanbieter-Komponenten behalten ihre eigenen Lizenzen.

VLCKit / libVLC stammt von VideoLAN und Mitwirkenden und steht unter LGPL 2.1
oder neuer. Die App enthält den Lizenztext, Quellcode-Verweise und eine Anleitung
zum Austausch des Frameworks. Siehe [Drittanbieter-Hinweise](Resources/ThirdPartyNotices.txt).
Tunerfenster lädt das Framework dynamisch. Du kannst es für den lokalen Einsatz
durch eine kompatible, geänderte Version ersetzen.
