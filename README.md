# Tunerfenster

[English](README.md) · [Deutsch](README.de.md)

<img src="docs/icon.png" width="96" height="96" alt="Tunerfenster icon">

Tunerfenster is a native macOS app for watching TVHeadend streams. Show your
tuners in a mosaic, watch one channel with its programme guide and logo, or play
recordings stored on the server.

## Download

Requires macOS 14 or later. VLC is included.

| Your Mac | Signed and notarized installer |
| --- | --- |
| Apple Silicon (M1 or newer) | [Download arm64 DMG](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-1.9.0-arm64.dmg) |
| Intel (64-bit) | [Download x64 DMG](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-1.9.0-x86_64.dmg) |

[All releases and SHA-256 checksums](https://github.com/NemoN/Tunerfenster/releases)

1. Open the DMG and drag **Tunerfenster** into **Applications**.
2. Start the app and open **Tunerfenster → Settings**.
3. Enter your TVHeadend URL, username and password, then connect.

Updates keep your settings. The app starts muted.

## Screenshots

The screenshots show a local demo server with fictitious channels and generated
test signals. They contain no broadcast footage or private server configuration.

### Tuner mosaic

![Tuner mosaic in English](docs/screenshots/mosaic-en.png)

### TV mode with EPG and channel picon

![TV mode and programme guide in English](docs/screenshots/tv-en.png)

### German interface and reception details

![German interface with reception information](docs/screenshots/reception-de.png)

## Features

- The mosaic fits all tuners into the window. TV mode plays only the selected
  tuner. The programme guide shows the current and next programmes, descriptions
  and programme progress.
- Automatic tiles show channels already running on the server. Idle tuners and
  EPG scans have their own status labels.
- You can choose a channel for each tile. The selector opens at the current
  channel; double-click a row or use **Switch channel** to change it. **Follow
  all** resets manual assignments.
- Reception details include frequency, V/H, LOW/HIGH, delivery system,
  modulation, symbol rate, FEC, orbital position, signal, SNR and continuity
  errors, where TVHeadend supplies them.
- Picons from TVHeadend, including SRP picons, appear beside the channel name
  in the enlarged view.
- Enlarging a tile turns on its audio. Returning to the mosaic mutes it. You
  can also mute it manually or press **M** to toggle audio. In the mosaic,
  **M** unmutes the first active stream if all streams are muted.
- The statistics icon above the enlarged video opens VLC's input, demux,
  video and audio counters over the picture. It refreshes once per second.
- The app remembers manual channels, viewing mode and the selected TV tuner
  for each server and account. These choices survive temporary outages.
- You can switch between English and German in the app. Menus, settings and
  status messages use the selected language.
- Clicking the appearance icon just before Settings cycles through **Follow
  system**, **Light** and **Dark**. The app saves your choice.
- In the TV mode programme guide, **Record** starts a
  recording on TVHeadend. Your account needs recording permission and an active
  recording profile. The EPG end time and the profile's extra recording time
  determine when it stops. Existing recordings are shown in the guide. The red
  button pulses while recording. **Stop recording** ends it and keeps the file
  recorded so far.
- Channel up/down and **Choose channel** come before **Use all tuners**.
  In the single-channel view, frequency, signal, SNR, bitrate and CC errors
  appear below the programme guide.
- Playback uses VLCKit 3.7.4 / libVLC 3.0.24. Separate builds are available for
  Apple Silicon and Intel.
- **Recordings** lists recorded programmes and recordings in progress. Search
  by title or channel, then select a recording to play it. The player has pause,
  seeking and mute controls. An approximate duration from TVHeadend is marked
  **≈** when VLC cannot determine the file duration. Unavailable files are labelled.
  Switching to Recordings stops the app's live streams and keeps your channel assignments.

The title bar shows the installed version. To change how often the app refreshes
the tuner status, choose an interval from 1 to 60 seconds in Settings or at the
bottom right of the window. The app saves it automatically.

In the enlarged view, **↑ / ↓** and the arrow buttons switch channels in list
order, wrapping at either end. Full screen shows only the video. Press **Esc**
to leave full screen, then **Esc** again to return to the mosaic.
Use **⌘1**, **⌘2** and **⌘3** to switch between Mosaic, TV and Recordings.
The app remembers the last mode. Selecting a recording starts its audio;
**M** toggles mute. **⌘P** pauses or resumes recording playback.

## Software updates

While running, Tunerfenster checks GitHub once a day for a newer stable release.
When one is available, **View update** offers the DMG for your Mac. It detects
Apple Silicon even when the Intel app is running under Rosetta.

You can check at any time with **Tunerfenster → Check for Updates…**, or turn off
automatic checks in Settings or the Software Updates window. To install an
update, download the DMG in your browser, quit Tunerfenster and replace the app.
Your settings stay saved. Installation is manual. The update check sends no
TVHeadend address, credentials or tuner information to GitHub.

## How it works

Tunerfenster reads TVHeadend's status, service, channel and EPG APIs. It opens
HTTP streams with low priority and short-lived playback tickets. Automatic
streams stop when the external viewer leaves the channel. TV mode stops the
other streams. The app leaves tuner, channel and recording configuration alone.

TVHeadend chooses the physical tuner for each stream. A manual selection sets
the service for a tile. The HTTP API does not let the app reserve a particular
hardware input for that stream.

The app calculates LOW/HIGH from the reported frequency. The threshold defaults
to 11700 MHz and can be changed in Settings. The value does not measure the
DiSEqC or 22 kHz switching state.

## Server access and privacy

Your TVHeadend account needs streaming permission and access to the status and
catalog APIs. Depending on the server configuration, service streams may need
the **Advanced streaming** permission and status queries may need administrator
access. The app supports Digest, Basic and connections without authentication.
The recording button also requires TVHeadend's **Video Recorder → Basic**
permission. Recordings are stored on the server and continue if you switch
channels or quit Tunerfenster.

The app stores passwords in macOS Keychain. Saved channel and viewing preferences
contain service IDs and tuner names; they contain no passwords or playback
tickets. Enter the connection details in the app. An MCP server is not required.

## Build from source

To build the app, you need Xcode or compatible macOS command-line tools with
Swift 5.9 or newer. The DMG scripts use the macOS 27 `diskutil image` commands.

```bash
git clone https://github.com/NemoN/Tunerfenster.git
cd Tunerfenster
chmod +x ./*.sh scripts/*.sh
./build-app.sh --no-bootstrap
open dist/Tunerfenster.app
```

The build downloads the official VideoLAN framework at the pinned version,
checks its SHA-256 checksum and bundles the code for the selected CPU
architecture. Git ignores build outputs and the download cache.

Local builds use ad-hoc signing unless you pin a signing certificate. A stable
certificate keeps Keychain access across rebuilds; see the
[local signing setup](docs/BUILDING.md#local-build).

See [building, testing and notarized releases](docs/BUILDING.md) for architecture
selection, Developer ID signing and the commands used to reproduce a release.

## Third-party software

The Tunerfenster source code has no license yet. Third-party components keep
their own licenses.

VLCKit / libVLC comes from VideoLAN and its contributors under LGPL 2.1 or later.
The app includes the license, source references and instructions for replacing
the framework. See [third-party notices](Resources/ThirdPartyNotices.txt).
Tunerfenster loads the framework dynamically, so you can replace it with a
compatible modified build for local use.
