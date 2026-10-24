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
  row-gap: "2px"
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
- Status symbols alongside state colors, with full text in help and accessibility labels.
- One titlebar selector for Mosaic, TV and Recordings.

Evidence: `Sources/Tunerfenster/RecordingsView.swift`, `RecordingLibrary.swift`, `ViewingMode.swift`, `TunerfensterApp.swift`, `Monitor.swift`, `Playback.swift`, plus the supporting native `Appearance.swift`, `SymbolSegmentedPicker.swift` and `PlaybackWindow.swift`. Reviewed captures are [.impeccable/review/recordings-light-de.png](.impeccable/review/recordings-light-de.png), [.impeccable/review/recordings-dark-en.png](.impeccable/review/recordings-dark-en.png) and [.impeccable/review/tv-controls-light-de.png](.impeccable/review/tv-controls-light-de.png). All are 1320 × 820 with generated test video and fictitious metadata. Compact-window behavior is source-derived; there is no compact capture. No web detector ran for this native code.

## Colors

The feature inherits the macOS semantic palette and the TV-mode surface treatments. The frontmatter contains only explicit reusable colors; it does not freeze dynamic AppKit colors into sampled hex values.

### Primary
- **Native selection and accent:** the inset list owns selection highlighting; toolbar selection and the slider use native control styling. Respect the user's system appearance and accent.
- **Recording red:** `ThemeColors.recording` marks recordings in progress with a small filled circle in library rows. Live recording controls keep their existing labels and symbols.

### Neutral
- **Window surface:** `NSColor.windowBackgroundColor` surrounds the content.
- **Control surface:** `NSColor.controlBackgroundColor` supplies both Recordings panes.
- **Primary and secondary text:** native foreground roles separate titles from channel, date, counts and supporting text.
- **Video black / video message white:** video remains on black in either appearance. Opening, ended and failure messages use white over a dark translucent backing.

Warnings use `ThemeColors.warning`: a dark amber in Light appearance and native system orange in Dark appearance. Missing files and recording errors pair this color with a warning symbol and localized help. Completed recordings have no availability checkmark. Running recordings use a small filled circle in `ThemeColors.recording` immediately after the title.

**The Native Roles Rule.** Preserve semantic AppKit surfaces and SwiftUI foreground roles when extending this feature; screenshots are appearance evidence, not fixed palette tokens.

## Typography

The macOS system font is used throughout. `system-ui` in the portable frontmatter represents the native system font; numeric frontmatter sizes correspond to SwiftUI/AppKit points on macOS, not a web layout contract.

- **Headline:** native `.headline` for the list heading, selected programme title and unselected-player prompt. Programme titles allow two lines.
- **Recording title:** the explicit medium system role in frontmatter; compact list titles stay on one line and truncate at the tail.
- **Metadata:** native `.caption` for channel, date, row state and transport times. Channel and date each stay on one line in the list.
- **Supporting copy:** native `.callout` for loading/error messages, empty-list copy and programme details.
- **Mode labels:** the explicit regular system role in frontmatter, accompanied by SF Symbols of matching point size.

Counts and transport times use monospaced digits. Programme detail text supports selection. Do not invent a display face or a fixed numeric size for a native text style whose size is controlled by macOS.

## Layout

Recordings uses an `NSSplitViewController` with stable SwiftUI hosting controllers, with the library on the left and player on the right. The library has a minimum width of 280 points, ideal width of 620 and expands when its divider is dragged. The player has a minimum width of 320 and expands into the remaining space. The app's content minimum is 700 × 460; its default window is 1320 × 820. These are native minimum constraints, not responsive web breakpoints. One width check at the list viewport controls metadata for every recording row, including nested folders and search results. It budgets 32 points for list insets and 160 for the title. Full metadata adds measured channel/date/duration widths and 70 points for controls and spacing. When that no longer fits, only duration remains, adding its measured width and 58 points for controls and spacing. At narrower widths duration disappears too. Folder indentation does not change these thresholds. Title, status and action buttons remain visible; full metadata remains in help and accessibility text.

The library stacks a heading/count row, search field, optional error/retry area and inset list. Recordings reuses the TV detail-panel background, including its faint highlight/shade gradient and accessibility fallbacks. The native list has a transparent scroll background so it shares that semantic surface. The library, player and programme information each have their own eight-point clip and subtle border, matching the separate video and detail surfaces in TV mode. Both dividers have an eleven-point transparent gap with one centered six-point dot in the semantic tertiary label color. Neither a line nor a background bar is drawn, so the window surface remains visible around each dot. There is no enclosing surface around all three panels; saved dividers and compact rows remain intact. Use the frontmatter's panel inset for library controls, player metadata, transport and programme details. The section gap separates library controls; rows have a 24-point content height with native list spacing and six-point gaps between fields, without separator dots. Channel, date and duration widths fit the longest displayed value in the catalogue, capped at 100, 120 and 90 points, so rows remain aligned without unused column space. The trailing Delete button retains its 24-point click area.

Panel-separation verification: German/Dark and English/Light captures show three distinct rounded surfaces with the player title and transport grouped around the video. Native divider values were changed to check a wider list and taller programme area, then restored. Single-click selection kept playback stopped. The local build passed 195 tests with three optional skips.

Dot-divider verification: native captures in Light and Dark show only the centered dot in both transparent gaps. Accessibility resizing confirmed the 280-point library and 220-point player minima; original divider positions were restored. Automated mouse dragging did not change the reported positions, so direct mouse tracking was not independently confirmed. AppKit owns that tracking. All 195 active tests passed, with three optional skips.

The native split view autosaves its divider as `TunerfensterRecordingsV1`. Expanded folder identifiers are stored in `recordingExpandedFoldersV1`, including nested folders. Empty/loading catalogues do not clear this preference. A collapsed folder retains its children's expansion state for the next time it opens.

The library shows TVHeadend folders containing multiple recordings as native disclosure groups, with folder symbols and descendant recording counts. Strip the recording profile's storage root from visible paths. Files in the storage root or without path metadata appear directly in the list, including when several storage profiles are present. A folder containing only one recording, including through nested folders, is omitted and its recording appears at the nearest retained parent or in the main list. Retained folders keep their identifiers and expansion state. The original paths remain available for search, help and accessibility. Multiple storage roots stay separate when grouped. Search spans all folders and presents matching recordings as a flat list. Selecting a search result opens its visible ancestor folders for returning to normal browsing. Refresh follows server-side moves without restarting the selected player; the app does not move files.

Three native icon buttons immediately before the total count sort by name (`textformat.abc`), date (`calendar`) or duration (`clock`). The active control has an accent color and directional arrow; clicking it reverses the order. The default is newest first; selecting duration starts with longest first. Name sorting uses natural, localized comparison. Dates use a folder's newest descendant recording; duration uses its longest descendant recording. Missing dates or durations stay at the end in either direction. Equal durations use A–Z names, then newest-first dates and stable identifiers. Folders and individual recordings share one order at every level, so folders do not automatically precede recordings. Search results use the same comparison. `recordingSort` persists the choice across launches without changing playback or selection.

The player groups its metadata header, expanding clipped video and transport row in one panel. Video and transport have a one-point horizontal inset inside the panel border, keeping the side edges visible against the black picture. The picture itself has an eight-point corner radius, applied to the SwiftUI surface and native VLC host. Rounding belongs to the windowed host, so full-screen playback retains rectangular edges; the optional scrollable programme description has a separate panel below it. A second native split controller between these panels lets the reader trade video height for more text. The upper pane, including its header, has a 220-point minimum and the information pane a 70-point minimum. AppKit retains divider tracking, resize cursors, minimum sizes and accessibility; a small dot is the only drawn divider content. The divider uses its own TunerfensterRecordingDetailsV1 autosave name, separate from the library-width split. The transport uses a horizontal sequence: pause/resume/replay, elapsed time, expanding seek slider, duration, mute. Full screen during explicitly started playback hides the toolbar and offers temporary playback controls over the video. Before selection, a centered prompt fills the player pane.

**The Playback Space Rule.** Keep metadata and transport adjacent to the video; allow the video and split view to absorb available window space.

## Elevation & Depth

This surface relies on native selection, separators and the same faint surface gradients as TV mode. Recordings defines no custom shadows or decorative elevation. Its video-state message is the local exception to flat surface separation: a black backing at 85% opacity keeps white message text readable over video. Native toolbar controls retain macOS-provided depth and focus treatment.

EPG and focused reception panels use a faint vertical highlight and shade over the semantic control background. The slim disclosure handle has a subtle diagonal light gradient that becomes clearer on hover. Live-video labels use a dark backdrop with a 24-point fade toward the picture, while retaining a dark area directly behind text. Increased contrast or reduced transparency replaces these gradients with solid surfaces. Small secondary text in the detail panels uses the system secondary label color with a minimum opacity of 60% for readability on the light surface. These refinements add no shadows and retain the existing dimensions.

## Shapes

Search uses the native rounded-border text field; the list uses native inset selection. The mode control is a small, rounded `NSSegmentedControl`. These shapes are system-owned rather than fixed feature radius tokens. The video is clipped to its pane. Video-state messages use a rounded rectangle with a 6-point corner radius and 20-point inset; this is a local overlay treatment, not a general card token.

## Components

### Titlebar mode selector and TV integration

A single native segmented control keeps symbol and localized text visible for Mosaic (`square.grid.2x2`), TV (`tv`) and Recordings (`rectangle.stack.badge.play`). It selects exactly one segment, uses equal segment distribution and occupies 300 points. Command-1, Command-2 and Command-3 provide the same mode changes.

In TV mode, omit the per-tuner collapse/enlarge button above the video. The titlebar mode selector remains the mode navigation. Existing tuner information, channel selection and statistics controls remain available. This condition is specific to TV mode.

### Dynamic tuner headers

Tile positions and playback IDs stay fixed. When TVHeadend reports a single reception source for a manual stream, its header uses that physical tuner's name and the displaced name moves to the other tile. Chains and cycles of assignments keep every tuner name unique. Status and reception metadata follow the displayed physical input, while channel choices, players, audio and saved preferences retain their original tile IDs. If sources are shared, unknown or conflict with another active stream, the affected headers keep their original names and retain the explicit routing note. The routing note is otherwise omitted from the mosaic, focused reception summary and reception popover.

Headers abbreviate manual mode as a green `M` and idle/free as `F` in both languages. Tooltips and accessibility labels retain the full localized status. Other status labels and colors keep their existing meaning.

### EPG and reception disclosure

TV mode and the enlarged mosaic tile share a small centered chevron button that hides or shows EPG and reception details together. At content widths of at least 1000 points, the details occupy a 320-point sidebar, with a 24-point handle gutter next to the video. In narrower windows the details sit below the video and the handle runs horizontally between them. The visible handle is smaller than its 24 × 96-point (or 64 × 24-point) click area. Native semantic surfaces and secondary foreground styling adapt it to Light and Dark appearance.

The handle remains at the right or bottom edge when the details are hidden; the video takes the released space. A shared `focusedDetailsVisible` preference, initially true, remembers the choice across tuners, viewing modes and app launches. The button has localized action text, help and visibility value. `AnyLayout` retains the video's structural position when the layout changes. Full screen hides these panels and reveals temporary playback controls on mouse movement.

### Live recording controls

After a recording has stopped, a current programme offers the red “Record again” / “Erneut aufnehmen” action with a note that the previous recording is kept. Each start creates a separate DVR entry for the rest of the programme. Recording controls track its returned UUID independently of the EPG, which can still reference an earlier file. A five-second status check updates the stop action while the controls are visible; a fresh EPG and upcoming-recordings check prevents starting a duplicate active recording.

### Search and library rows

Use a rounded-border search field with localized placeholder text. Search matches title, channel, programme details or folder without changing the total-library count. Each compact row shows status, title, channel, numeric date/time and duration on a single line, with spacing between columns. Metadata columns share widths across rows, even if a value is absent; dates and times use leading zeros. Duration appears immediately after date, right-aligned with monospaced digits as hours:minutes:seconds. A small SF Symbol `clock`, with a 12-point frame and three-point gap, precedes its value. Localized help identifies the scheduled TVHeadend duration; the actual file length can differ. Missing or invalid durations show an em dash beside the clock. Channel and date hide before duration when the pane narrows. A small red filled circle follows the title while recording; a warning triangle there marks errors or missing files. The title truncates before either symbol, keeping them visible. Completed recordings have no status checkmark. Localized help and accessibility labels retain full duration and status. A trailing borderless Delete button has a 24-point click area. There is no separate Play button in library rows. Titles have the strongest type role; metadata uses caption text. Native selection identifies the chosen recording, and selecting a row shows programme information without requesting a stream. A double-click starts the chosen recording at its saved position. Selecting a different row stops current playback and checkpoints its position. Unavailable files remain visible. Full metadata and search-result folder paths remain in the row's help and accessibility text.

Recording titles can include episode names from explicit German or English episode fields in the description or from the subtitle, regardless of series or programme name. Matching series metadata allows titles such as “Star Trek: Voyager” to receive an episode suffix. Complete titles and ambiguous cases keep the original name. Word-based comparisons ignore case, accents and punctuation to prevent repeated series or episode names; genre, origin and year metadata are ignored. The derived title is shared by the list, player, search, name sorting, help and confirmation dialogs; server entries and filenames are unchanged.

Within an expanded folder, recording rows omit a matching folder-name prefix and its colon or dash, for example “Charlie” under “Tatort”. Matching visible ancestor prefixes can also be omitted in nested folders. Never produce an empty title or remove a partial word or a name in the middle of a title. Name sorting within the folder uses these shorter labels. Main-list rows, search results, player headings, help and action labels retain the full recording title.

Combine each row's content for accessibility and supply localized availability help. A refresh failure appears above the list with a warning and Retry button; Retry is disabled during refresh. A small progress indicator beside the heading communicates loading.

Prepare titles, dates, accessibility text, folder ordering and metadata widths once per catalogue/search/sort/language change. Reuse that snapshot while scrolling, resizing, expanding folders or changing playback state. Pane width only selects the shared column visibility; a catalogue refresh, deletion or connection reset invalidates the cached data, including changes to existing UUIDs.

A leading 14-point SF Symbol shows viewing state: `circle` for unwatched, `circle.lefthalf.filled` for partly watched and `eye.fill` for watched. Use secondary foreground in both appearances. Localized help and the combined accessibility label include the state and resume time. Keep it visible at every list width. These values come from TVHeadend's playposition, playcount and watched fields, overlaid with unsent local checkpoints; progress changes reuse the prepared list data. An explicit playcount takes priority over the historical watched timestamp. The row context menu offers Mark as watched and Mark as unwatched; both clear the resume position and write the counter through the serialized progress queue. Newer manual intent replaces older pending completion writes. A paused or ended player cannot immediately undo that intent; automatic completion is suppressed for the current session after a manual unwatched mark.

Completed recordings have a trailing native trash button and a matching context-menu action. Delete in the focused list requests the same action for the selected recording. An alert names the recording and states that its file will be permanently deleted from TVHeadend; Cancel and a destructive Delete button are the only actions. Running recordings cannot be deleted here. A small progress indicator replaces the trash symbol while deletion is pending. Errors appear above the list, and items disappear only after a server check confirms their removal. Deleting the playing recording stops its player; deleting another one preserves current playback.

### Player and transport

The selected title and channel/date header precede black-backed video. Pause changes to resume when paused and to replay when playback ended or failed. Opening disables that action. The native seek slider is disabled while seeking is unavailable. Times use monospaced digits; an approximate TVHeadend duration has a visible `≈` prefix and explanatory help. The implementation can seek MPEG-TS by file position when VLC has no duration.

The mute button changes SF Symbol and exposes a localized accessibility value. M toggles audio when focus is outside editable text and blocking panels; Command-P pauses/resumes or replays. The toolbar's full-screen action uses native macOS full screen; Escape leaves it. Double-clicking an active recording or focused live video toggles the same native window full screen. A window-local mouse monitor detects clicks inside the visible VLC canvas, including its embedded child views; metadata, transport, lists, sheets and other windows do not trigger it. The standard Control-Command-F shortcut remains available. Full screen hides the windowed chrome and reveals temporary playback controls on mouse movement. Each SwiftUI video surface owns a separate native host; only the current host sizes the shared VLC canvas during transitions. Old surfaces cannot resize a canvas that has moved to full screen.

An explicit playback action reads the latest resume point and seeks once VLC is ready. Selection shows programme information and a Play recording button over black video, without loading a still frame. The timeline remains disabled until playback has started. The native List primary action starts a recording on double-click; single-click selection and refresh never request a stream or write playback progress. Its native NSSlider retains keyboard and accessibility behavior, with an 8 × 18-point rectangular playhead in the system accent color and a disabled semantic color. Its vertical center follows the track’s bar rectangle rather than the native round knob’s drawing bounds, keeping it centered on the line in windowed and full-screen playback. The transport Play button, context-menu Play action and Command-P start playback. Only explicitly started playback writes automatic progress checkpoints; refreshing keeps ongoing playback intact. The transport begins with `backward.end.fill`, labelled Play from beginning, also offered in the row context menu. Save position every ten seconds and on pause, seek completion, recording/mode changes and quit. Mark completed recordings watched at 90% or playback end, clearing their resume point. Preserve existing watched marks. Serialize partial server updates, verify them by reading back, and retain failed checkpoints locally per server/account. Show sync failures with a Retry button above the list. A failed resume seek keeps the stored position and shows a short warning beside the transport. Startup zeros never replace a pending resume point. Allow at most five seconds for the final sync on quit; unsent checkpoints remain available for retry on launch.

Progress verification: 182 tests executed, 179 passed and three optional checks skipped. Native checks covered the three viewing symbols, German/Dark and English/Light, pause saving, forward/backward seeking, server readback, quit and resuming the same MPEG-TS recording after restart. Pane width, expanded folders, sort order and the user's language/appearance were restored. No release artifacts were produced.

Manual marking follow-up: 187 tests executed, 184 passed and three optional checks skipped. Native checks confirmed the context menu and removal of status checkmarks. Server readback confirmed a test recording changed from unwatched to watched and back to its original unwatched state. The local app remained connected with the existing pane width, language, appearance and folder expansion.

Previous selection and details check: 191 tests executed, 188 passed and three optional checks skipped. Native checks confirmed selection without playback, explicit Play at the saved position, and stopping playback when another recording is selected. Resizing through the native divider's accessibility value changed the video and information heights; the split position survived a restart. Automated mouse dragging did not move the divider, so direct mouse interaction remains unverified. The local build is connected; no release was created.

Previous paused-frame check (the feature was subsequently removed): 192 tests executed, 189 passed and three optional checks skipped. Native checks covered German/Dark and English/Light, loading the saved frame without autoplay, seeking while paused, explicit Play and pause, and switching recordings. Server readback retained the original resume point and unwatched state during frame loading and paused seeking. The native timeline has a visible rectangular playhead in both appearances. Language, appearance, selection, divider sizes and the tested resume point were restored.

Double-click follow-up: 193 tests executed, 190 passed and three optional checks skipped. Single-click selection does not load video; the native List primary action starts playback on double-click. Native checks confirmed video double-click entry and exit, Control-Command-F entry and exit, and Escape exit. A canvas-host regression check prevents a previous surface from resizing the active video during full-screen transitions. The rectangular timeline remains unchanged. The app was left connected in German/Dark, with the original folder expansion, divider sizes and selected recording; the playback test position was restored.

Entering Recordings stops this app's live streams, preserves manual assignments and the last TV tuner, and changes the footer status. The selected mode persists, but a recording is not automatically resumed at launch. Leaving Recordings clears its selection and stops its playback.


### Full-screen playback controls

A window-local pointer monitor receives movement over VLC’s embedded child views. It reveals the bottom overlay and extends a monotonic three-second deadline. One timer handles inactivity; movement does not allocate a timer per event. The overlay stays visible while tracking the seek slider. Tab navigation pins it until pointer movement resumes; VoiceOver keeps it visible. Reduced Motion removes the short opacity transition. Increased contrast and reduced transparency use the existing solid video-control background instead of the fade.

The overlay reuses the TV-mode bottom video fade, centered programme/channel text and an exit-full-screen button. Recordings reuses the exact same transport as windowed playback: restart, play/pause/replay, elapsed time, rectangular-playhead timeline, duration and mute. Focused live TV offers channel up/down and mute. A native view probe excludes the visible control region from video double-click handling, so adjusting a control cannot toggle full screen. Hidden controls leave the video unobstructed; full-screen exit clears interaction state and restores mouse-event settings when the window controller detaches.

Windowed transport uses plain SF Symbol buttons and the shared detail-panel background. Programme text has a maximum reading width of 760 points, eighteen-point padding and clearer spacing, with a localized section label. The video, native split dividers and recording-list behavior retain their established layout and saved settings.

Verification: 198 tests executed, 195 passed and three optional checks skipped. The new state tests cover the inactivity deadline, dragging, keyboard navigation, VoiceOver and full-screen reentry. Native visual checks covered German/Dark, English/Light and the full-screen transport. The final build hid the controls after inactivity, revealed them after pointer input and hid them again after the next idle interval; Escape returned to the windowed view. The real recording used for playback checks retained its original server resume position and unwatched state. No release artifacts were produced.

### Empty, loading and failure states

Keep loading, no-recordings and search-empty copy in the list pane, using a secondary stack symbol and centered callout. The unselected player has a larger `play.rectangle` symbol, headline and explanatory copy. Playback opening, ended and failure states appear inside the video area; replay is offered by the transport. Missing-file, permission and playback errors remain localized and readable in both appearances.

### Sidecar previews

[.impeccable/design.json](.impeccable/design.json) supplies schematic HTML previews for documentation tools. They illustrate structure and roles only. They do not replace the native controls, SF Symbols, system focus behavior or the reviewed macOS captures.

## Do's and Don'ts

### Do:
- **Do** extend Recordings with native macOS controls, semantic surfaces and system text roles.
- **Do** preserve recognizable status symbols and localized accessibility labels/help.
- **Do** retain the list/player split and documented native minimum widths.
- **Do** distinguish approximate duration in the player with `≈` and a localized explanation; library rows use a clock icon and localized help.
- **Do** verify additions in German and English and in Light and Dark appearance.

### Don't:
- **Don't** replace system colors with fixed screenshot samples.
- **Don't** restore the per-tuner collapse/enlarge button in TV mode.
- **Don't** treat test-video colors, fictitious metadata or HTML previews as app design tokens.
- **Don't** infer a compact layout or a global redesign from this feature-scoped record.
- **Don't** add decorative assets or motion to this extension; its contract retains the established native interface.
