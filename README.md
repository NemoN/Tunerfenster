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
| Apple Silicon (M1 or newer) | [Download arm64 DMG](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-2.0-arm64.dmg) |
| Intel (64-bit) | [Download x64 DMG](https://github.com/NemoN/Tunerfenster/releases/latest/download/Tunerfenster-2.0-x86_64.dmg) |

[All releases and SHA-256 checksums](https://github.com/NemoN/Tunerfenster/releases)

1. Open the DMG and drag **Tunerfenster** into **Applications**.
2. Start the app and open **Tunerfenster → Settings**.
3. Enter your TVHeadend URL, username and password, then connect.

Updates keep your settings. The app starts muted.

## Screenshots

These screenshots show Tunerfenster 1.9.0 connected to a real TVHeadend server.
The window header containing the private server address has been cropped out.

### Live TV with EPG and reception details

![Live TV with programme guide, channel logo and reception details](docs/screenshots/live-tv.png)

### Recording playback

![A recording from TVHeadend playing beside the recordings list](docs/screenshots/live-recordings.png)

### VLC stream statistics

![VLC stream statistics over the live picture](docs/screenshots/live-statistics.png)

### Tuner mosaic

13 tuners, with one live stream, an EPG scan and idle tuners.

![Real tuner mosaic showing a live stream, an EPG scan and idle tuners](docs/screenshots/live-mosaic.png)

<details>
<summary>Demo screenshots in English and German</summary>

The following examples use fictitious channels and generated test signals.

### Tuner mosaic

![Tuner mosaic in English](docs/screenshots/mosaic-en.png)

### TV mode with EPG and channel picon

![TV mode and programme guide in English](docs/screenshots/tv-en.png)

### German interface and reception details

![German interface with reception information](docs/screenshots/reception-de.png)

</details>

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
  by title or channel. Click a recording to view programme information, or
  double-click it to start playback at its saved position.
  Titles can include an episode name from the subtitle or an explicit episode field
  in the description, for example “Tatort: Charlie”. This works across series and
  programmes. Complete titles stay intact; repeated names and genre-only metadata
  are ignored. If the metadata is ambiguous, the original title remains. This changes
  only the displayed name, leaving server entries and files untouched. The player has pause,
  seeking and mute controls. Drag the horizontal divider above the programme
  information to give it more space and shrink the video. The app remembers
  the divider position. Selecting another recording stops the current player
  without starting the new one. An approximate duration from TVHeadend is marked
  **≈** when VLC cannot determine the file duration. Unavailable files are labelled.
  Delete a completed recording with its trash button or context menu. A confirmation
  names the recording before permanently deleting its file and entry from TVHeadend.
  Stop a running recording before deleting it.
  Server folders appear as expandable groups with recording counts, including
  subfolders. Recordings in the storage root or alone in a folder appear directly
  in the list, without a folder to expand. Search also matches folder names;
  hovering over a recording shows its path.
  Inside a folder, matching folder names are omitted from recording titles:
  “Tatort: Charlie” appears as “Charlie” under “Tatort”. Search and the player
  keep the full title.
  Each recording fits on one line: viewing status, title, channel, date and duration, with
  Delete on the right. Use Play in the player or context menu to start it. Small gaps separate aligned columns; numeric dates have
  leading zeros. A red filled dot after the title means the recording is still
  running; a warning symbol there marks errors or unavailable files. Hover for details.
  The leading symbol shows viewing status: an empty circle for unwatched,
  a half-filled circle for partly watched, and an eye for watched. Hover to see
  the resume time. Play continues from the saved position.
  The app syncs progress with TVHeadend every ten seconds, when paused, after
  seeking, when switching recordings or modes, and on quit. Failed updates stay
  saved locally for that server/account and are retried. At 90% or playback end,
  a completed recording is marked watched and its resume position is cleared.
  Existing watched marks are kept. The context menu offers **Mark as watched** and
  **Mark as unwatched**. Both clear the resume position and sync the chosen status
  with TVHeadend. A paused recording keeps that choice until playback continues.
  Use **Play from beginning** in the player or
  context menu to start over. Watched status and resume points are shared server
  data; other clients using the same recording can read or change them.
  Widen the list by dragging the divider beside the player. The app remembers
  the list width and which folders are expanded.
  Duration follows the date as hours:minutes:seconds with a clock icon.
  It uses the scheduled duration from TVHeadend; the file duration may differ.
  A dash means unavailable.
  Narrow lists hide channel and date first, then duration. All rows switch at the
  same list widths, including recordings inside folders and search results.
  The name, date and clock symbols beside the total count sort the list. Click the active
  symbol again to reverse the order. Folders and individual recordings are sorted
  together, including inside folders. The app remembers the sort order; folders use
  their newest recording for date sorting and their longest recording for duration
  sorting, including subfolders. Missing durations stay at the end in either direction.
  Refresh (⌘R) picks up recordings moved on the server.
  Switching to Recordings stops the app's live streams and keeps your channel assignments.

The title bar shows the installed version. To change how often the app refreshes
the tuner status, choose an interval from 1 to 60 seconds in Settings or at the
bottom right of the window. The app saves it automatically.

In the enlarged view, **↑ / ↓** and the arrow buttons switch channels in list
order, wrapping at either end. In full screen, mouse movement shows playback controls,
which hide after three seconds of inactivity. Recordings also show the timeline.
Dragging the playhead keeps the controls visible. Press **Esc**
to leave full screen, then **Esc** again to return to the mosaic.
Use **⌘1**, **⌘2** and **⌘3** to switch between Mosaic, TV and Recordings.
The app remembers the last mode. Clicking a recording shows its information.
Double-clicking, **Play recording** or **⌘P** starts playback with audio. **M** toggles mute.
During playback, **⌘P** pauses or resumes it. Double-click the video to enter or leave
full screen. **Esc** or **⌃⌘F** also leaves full screen.

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
