# Tunerfenster

[English](README.md) · [Deutsch](README.de.md)

<img src="docs/icon.png" width="96" height="96" alt="Tunerfenster-Symbol">

Eine native macOS-App für TVHeadend. Alle Tuner gemeinsam als Mosaik ansehen
oder in einen TV-Modus mit einem Sender, Programmführer und Senderlogo wechseln.
Die VLC-Wiedergabe-Engine ist integriert.

## Download

**Ab macOS 14. Eine separate VLC-Installation ist nicht nötig.**

| Dein Mac | Signierte und notarisierte Installationsdatei |
| --- | --- |
| Apple Silicon — M1 oder neuer | [arm64-DMG herunterladen](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-1.7.1-arm64.dmg) |
| Intel — 64 Bit | [x64-DMG herunterladen](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-1.7.1-x86_64.dmg) |

[Alle Releases und SHA-256-Prüfsummen](https://github.com/NemoN/Tunerfenster/releases)

1. Die DMG öffnen und **Tunerfenster** in **Applications / Programme** ziehen.
2. Die App starten und **Tunerfenster → Einstellungen** öffnen.
3. TVHeadend-Adresse, Benutzername und Passwort eingeben und verbinden.

Vorhandene Einstellungen bleiben bei einem Update erhalten. Jeder Start ist stumm.

## Screenshots

Die Screenshots zeigen einen lokalen Demo-Server mit erfundenen Sendern und
erzeugten Testsignalen. Sie enthalten keine Fernsehaufnahmen und keine private
Serverkonfiguration.

### Tuner-Mosaik

![Tuner-Mosaik auf Deutsch](docs/screenshots/mosaic-de.png)

### TV-Modus mit EPG und Senderlogo

![TV-Modus und Programmführer auf Deutsch](docs/screenshots/tv-de.png)

### Empfangsdaten

![Empfangsinformationen auf Deutsch](docs/screenshots/reception-de.png)

## Funktionen

- **Mosaik und TV-Modus:** Alle Tuner passen ins Fenster. Im TV-Modus läuft nur
  die gewählte Vorschau, ergänzt um laufende und nächste Sendung, Beschreibung
  und Fortschritt.
- **Aktiven Tunern folgen:** Bereits auf dem Server laufende Sender automatisch
  anzeigen. Freie Tuner und EPG-Abfragen haben eigene Zustände.
- **Manuelle Senderwahl:** Pro Kachel einen Sender wählen und alle manuellen
  Zuordnungen mit einem Button wieder auf „Folgend“ stellen.
- **Empfangsdaten:** Frequenz, V/H, LOW/HIGH, Empfangsart, Modulation,
  Symbolrate, FEC, Satellitenposition, Signal, SNR und CC-Fehler anzeigen,
  soweit TVHeadend diese Daten liefert.
- **Senderlogos:** Die in TVHeadend eingerichteten Picons, einschließlich
  SRP-Picons, neben dem Sendernamen in der vergrößerten Ansicht anzeigen.
- **Ton im Fokus:** Vergrößern schaltet den Ton dieses Senders ein; die Rückkehr
  ins Mosaik schaltet ihn wieder stumm. Manuelles Stummschalten bleibt möglich.
- **Gespeicherte Auswahl:** Manuelle Sender, Modus und ausgewählten TV-Tuner
  pro Server und Benutzer wiederherstellen, auch nach vorübergehenden Ausfällen.
- **Deutsch und Englisch:** Die Sprache direkt in der App wechseln. Menüs,
  Einstellungen und Statusmeldungen wechseln mit.
- **Integrierte Wiedergabe:** VLCKit 3.7.4 / libVLC 3.0.24 ist enthalten.
  Getrennte Builds für Apple Silicon und Intel.

## Arbeitsweise

Tunerfenster liest TVHeadends Status-, Service-, Sender- und EPG-APIs und öffnet
HTTP-Vorschauen mit niedriger Priorität und kurzlebigen Wiedergabetickets.
Automatische Vorschauen enden, wenn der externe Zuschauer den Sender verlässt.
Im TV-Modus werden die übrigen Vorschauen gestoppt. Die App verändert keine
Tuner-, Sender- oder Aufnahmekonfiguration.

**Eine Kachel reserviert keinen physischen Tuner.** TVHeadend entscheidet über
den tatsächlichen Empfangsweg. Eine manuelle Auswahl legt den Sender für die
Kachel fest; die HTTP-API kann den Stream nicht exklusiv an einen bestimmten
Hardware-Eingang binden.

LOW/HIGH wird aus der gemeldeten Frequenz berechnet. Die Grenze ist einstellbar
und liegt standardmäßig bei 11700 MHz. Es ist kein gemessener DiSEqC- oder
22-kHz-Zustand.

## Serverzugriff und Datenschutz

Der TVHeadend-Benutzer benötigt passende Rechte für Status-/Katalog-APIs und
Streaming. Direkte Service-Vorschauen können **Advanced streaming** erfordern;
Statusabfragen können je nach Serverkonfiguration Administratorrechte benötigen.
Digest, Basic und Zugriffe ohne Anmeldung werden unterstützt.

Passwörter liegen im macOS-Schlüsselbund. Gespeicherte Sender- und
Ansichtseinstellungen enthalten Service-IDs und Tunernamen, keine Passwörter
oder Wiedergabetickets. Ein MCP-Server wird nicht benötigt. Die Verbindung
wird direkt in der App eingerichtet.

## Selbst bauen

Benötigt Xcode oder geeignete macOS-Entwicklerwerkzeuge mit Swift 5.9 oder neuer.
Die DMG-Skripte verwenden die `diskutil image`-Befehle von macOS 27.

```bash
git clone https://github.com/NemoN/Tunerfenster.git
cd Tunerfenster
chmod +x ./*.sh scripts/*.sh
SIGN_IDENTITY=- ./build-app.sh
open dist/Tunerfenster.app
```

Beim ersten Build wird das festgelegte offizielle VideoLAN-Framework geladen,
über seine SHA-256-Prüfsumme geprüft und mit der passenden CPU-Architektur in die
App eingebettet. Build-Ausgaben und Download-Cache werden nicht mit Git erfasst.

Weitere Befehle stehen unter [Bauen, Testen und notarisierte Releases](docs/BUILDING.md).

## Drittanbieter-Software

Für den Tunerfenster-Quellcode ist derzeit keine Lizenz festgelegt.
Die Drittanbieter-Komponenten behalten ihre eigenen Lizenzen.

VLCKit / libVLC stammt von VideoLAN und Mitwirkenden und steht unter **LGPL 2.1
oder neuer**. Lizenztext, Quellcode-Verweise und Hinweise zum Austausch des
Frameworks sind in der App enthalten. Siehe [Drittanbieter-Hinweise](Resources/ThirdPartyNotices.txt).
Das Framework bleibt dynamisch geladen und kann für den lokalen Einsatz durch
eine kompatible, geänderte Version ersetzt werden.
