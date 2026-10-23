---
name: Tunerfenster — Recordings and TV-mode extension
description: Observed native macOS patterns for the Recordings feature and its TV-mode integration.
colors:
  video-black: "#000000"
  video-message-white: "#ffffff"
  recording: "rgb(70% 6% 9%)"
typography:
  recording-title:
    fontFamily: "system-ui"
    fontSize: "13px"
    fontWeight: 500
  mode-label:
    fontFamily: "system-ui"
    fontSize: "12px"
    fontWeight: 400
spacing:
  panel-inset: "12px"
  section-gap: "10px"
  message-gap: "8px"
  row-gap: "5px"
---

# Design System: Tunerfenster

## Overview

### Scope: Recordings and TV-mode integration

**Creative North Star: "Native playback workspace"**

This records the built Recordings surface and the related TV-mode control change. It is a narrow extension of Tunerfenster's established SwiftUI/AppKit interface, not a global identity specification. The READMEs and implementation remain product authority; the feature contract is [.impeccable/briefs/recordings.md](.impeccable/briefs/recordings.md).

The interface is a compact macOS workspace: a searchable list supplies a large player, with programme metadata and transport controls close to the video. Standard controls, the macOS system font and SF Symbols supply the visual language. System, Light and Dark appearance and immediate German/English switching belong to the same interface.

**Key Characteristics:**
- Native semantic surfaces, text styles, selection and controls.
- A resizable list/player split with dense, readable metadata.
- Visible status text and symbols alongside state colors.
- One titlebar selector for Mosaic, TV and Recordings.

Evidence: `Sources/Tunerfenster/RecordingsView.swift`, `RecordingLibrary.swift`, `ViewingMode.swift`, `TunerfensterApp.swift`, `Monitor.swift`, `Playback.swift`, plus the supporting native `Appearance.swift`, `SymbolSegmentedPicker.swift` and `PlaybackWindow.swift`. Reviewed captures are [.impeccable/review/recordings-light-de.png](.impeccable/review/recordings-light-de.png), [.impeccable/review/recordings-dark-en.png](.impeccable/review/recordings-dark-en.png) and [.impeccable/review/tv-controls-light-de.png](.impeccable/review/tv-controls-light-de.png). All are 1320 × 820 with generated test video and fictitious metadata. Compact-window behavior is source-derived; there is no compact capture. No web detector ran for this native code.

## Colors

The feature inherits the macOS semantic palette. The frontmatter contains only explicit reusable colors; it does not freeze dynamic AppKit colors into sampled hex values.

### Primary
- **Native selection and accent:** the inset list owns selection highlighting; toolbar selection and the slider use native control styling. Respect the user's system appearance and accent.
- **Recording red:** `ThemeColors.recording` marks recordings in progress. Keep its status label and `record.circle` symbol.

### Neutral
- **Window surface:** `NSColor.windowBackgroundColor` surrounds the content.
- **Control surface:** `NSColor.controlBackgroundColor` supplies both Recordings panes.
- **Primary and secondary text:** native foreground roles separate titles from channel, date, counts and supporting text.
- **Video black / video message white:** video remains on black in either appearance. Opening, ended and failure messages use white over a dark translucent backing.

Warnings use `ThemeColors.warning`: a dark amber in Light appearance and native system orange in Dark appearance. Missing files and recording errors pair this color with a warning symbol and a localized label. Completed, playable recordings use secondary status text.

**The Native Roles Rule.** Preserve semantic AppKit surfaces and SwiftUI foreground roles when extending this feature; screenshots are appearance evidence, not fixed palette tokens.

## Typography

The macOS system font is used throughout. `system-ui` in the portable frontmatter represents the native system font; numeric frontmatter sizes correspond to SwiftUI/AppKit points on macOS, not a web layout contract.

- **Headline:** native `.headline` for the list heading, selected programme title and unselected-player prompt. Programme titles allow two lines.
- **Recording title:** the explicit medium system role in frontmatter; list titles allow two lines.
- **Metadata:** native `.caption` for channel, date, row state and transport times. Channel and date each stay on one line in the list.
- **Supporting copy:** native `.callout` for loading/error messages, empty-list copy and programme details.
- **Mode labels:** the explicit regular system role in frontmatter, accompanied by SF Symbols of matching point size.

Counts and transport times use monospaced digits. Programme detail text supports selection. Do not invent a display face or a fixed numeric size for a native text style whose size is controlled by macOS.

## Layout

Recordings uses `HSplitView`, with the library on the left and player on the right. The library has a minimum width of 240 points, ideal width of 320 and maximum of 420. The player has a minimum width of 320 and expands into the remaining space. The app's content minimum is 700 × 460; its default window is 1320 × 820. These are native minimum constraints, not responsive web breakpoints. No separate compact composition has been established or captured.

The library stacks a heading/count row, search field, optional error/retry area and inset list. Use the frontmatter's panel inset for library controls, player metadata, transport and programme details. The section gap separates library controls; rows use the smaller row gap and matching vertical padding.

The player stacks a metadata header, expanding clipped video, a transport row and optional scrollable description. Description height is capped at 110 points so it cannot consume the player. The transport uses a horizontal sequence: pause/resume/replay, elapsed time, expanding seek slider, duration, mute. Full screen with a selected recording presents only video and hides the toolbar. Before selection, a centered prompt fills the player pane.

**The Playback Space Rule.** Keep metadata and transport adjacent to the video; allow the video and split view to absorb available window space.

## Elevation & Depth

This surface is flat and relies on native selection, separators and differences between window/control surfaces. The Recordings view defines no custom shadows or decorative elevation. Its video-state message is the local exception to flat surface separation: a black backing at 85% opacity keeps white message text readable over video. Native toolbar controls retain macOS-provided depth and focus treatment.

## Shapes

Search uses the native rounded-border text field; the list uses native inset selection. The mode control is a small, rounded `NSSegmentedControl`. These shapes are system-owned rather than fixed feature radius tokens. The video is clipped to its pane. Video-state messages use a rounded rectangle with a 6-point corner radius and 20-point inset; this is a local overlay treatment, not a general card token.

## Components

### Titlebar mode selector and TV integration

A single native segmented control keeps symbol and localized text visible for Mosaic (`square.grid.2x2`), TV (`tv`) and Recordings (`rectangle.stack.badge.play`). It selects exactly one segment, uses equal segment distribution and occupies 300 points. Command-1, Command-2 and Command-3 provide the same mode changes.

In TV mode, omit the per-tuner collapse/enlarge button above the video. The titlebar mode selector remains the mode navigation. Existing tuner information, channel selection and statistics controls remain available. This condition is specific to TV mode.

### Search and library rows

Use a rounded-border search field with localized placeholder text. Search matches title or channel without changing the total-library count. Rows contain title, channel, date and a symbol-plus-label status; a trailing play or warning symbol indicates availability. Native selection identifies the chosen recording, and selecting a playable row starts playback with audio. Unavailable files remain visible and labelled; selecting one does not open playback.

Combine each row's content for accessibility and supply localized availability help. A refresh failure appears above the list with a warning and Retry button; Retry is disabled during refresh. A small progress indicator beside the heading communicates loading.

### Player and transport

The selected title and channel/date header precede black-backed video. Pause changes to resume when paused and to replay when playback ended or failed. Opening disables that action. The native seek slider is disabled while seeking is unavailable. Times use monospaced digits; an approximate TVHeadend duration has a visible `≈` prefix and explanatory help. The implementation can seek MPEG-TS by file position when VLC has no duration.

The mute button changes SF Symbol and exposes a localized accessibility value. M toggles audio when focus is outside editable text and blocking panels; Command-P pauses/resumes or replays. The toolbar's full-screen action uses native macOS full screen; Escape leaves it.

Entering Recordings stops this app's live streams, preserves manual assignments and the last TV tuner, and changes the footer status. The selected mode persists, but a recording is not automatically resumed at launch. Leaving Recordings clears its selection and stops its playback.

### Empty, loading and failure states

Keep loading, no-recordings and search-empty copy in the list pane, using a secondary stack symbol and centered callout. The unselected player has a larger `play.rectangle` symbol, headline and explanatory copy. Playback opening, ended and failure states appear inside the video area; replay is offered by the transport. Missing-file, permission and playback errors remain localized and readable in both appearances.

### Sidecar previews

[.impeccable/design.json](.impeccable/design.json) supplies schematic HTML previews for documentation tools. They illustrate structure and roles only. They do not replace the native controls, SF Symbols, system focus behavior or the reviewed macOS captures.

## Do's and Don'ts

### Do:
- **Do** extend Recordings with native macOS controls, semantic surfaces and system text roles.
- **Do** preserve symbol-plus-text status and localized accessibility labels/help.
- **Do** retain the list/player split and documented native minimum widths.
- **Do** distinguish approximate duration with `≈` and a localized explanation.
- **Do** verify additions in German and English and in Light and Dark appearance.

### Don't:
- **Don't** replace system colors with fixed screenshot samples.
- **Don't** restore the per-tuner collapse/enlarge button in TV mode.
- **Don't** treat test-video colors, fictitious metadata or HTML previews as app design tokens.
- **Don't** infer a compact layout or a global redesign from this feature-scoped record.
- **Don't** add decorative assets or motion to this extension; its contract retains the established native interface.
