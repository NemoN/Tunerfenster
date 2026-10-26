import SwiftUI

struct FocusedTunerView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    let tuner: Tuner
    let tile: AnyView
    @AppStorage("focusedDetailsVisible") private var detailsVisible = true
    @State private var handleHovered = false

    var body: some View {
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 1000
            // Keep the video at the same structural position when the panels
            // collapse or move below it, so the VLC surface stays attached.
            let layout = sideBySide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                tile.frame(maxWidth: .infinity, maxHeight: .infinity)
                detailsHandle(sideBySide: sideBySide)
                if detailsVisible {
                    if sideBySide {
                        Group {
                            if monitor.viewingMode == .tv {
                                tvDetails(compact: false, width: 320, height: geometry.size.height)
                            } else {
                                VStack(spacing: 10) {
                                    ProgrammeView(monitor: monitor, tuner: tuner).frame(maxHeight: .infinity)
                                    FocusedReceptionView(monitor: monitor, tuner: tuner)
                                }
                            }
                        }.frame(width: 320, height: geometry.size.height)
                    } else if monitor.viewingMode == .tv {
                        // Give height back to the video as the window shrinks.
                        // The compact minimum keeps the heading and current title visible.
                        let height = min(300, max(112, geometry.size.height - 440))
                        tvDetails(compact: true, width: geometry.size.width, height: height)
                            .frame(height: height)
                    } else {
                        ScrollView {
                            VStack(spacing: 10) {
                                ProgrammeView(monitor: monitor, tuner: tuner, scrolls: false)
                                FocusedReceptionView(monitor: monitor, tuner: tuner)
                            }
                        }.frame(height: min(300, max(130, geometry.size.height * 0.42)))
                    }
                }
            }
        }
    }

    private func tvDetails(compact: Bool, width: CGFloat, height: CGFloat) -> some View {
        RecordingSplitView(name: compact ? "TunerfensterTVDetailsCompactV2" : "TunerfensterTVDetailsV1",
                           isVertical: compact, minimumFirst: compact ? 280 : 100, minimumSecond: compact ? 160 : 96,
                           initialFraction: compact ? 0.7 : 0.84, initialLength: compact ? width : height,
                           proportionalResize: compact) {
            ProgrammeView(monitor: monitor, tuner: tuner, compact: compact, titleOnly: compact && height < 140)
                .frame(maxHeight: .infinity)
        } second: {
            FocusedReceptionView(monitor: monitor, tuner: tuner, expands: true)
                .frame(maxHeight: .infinity)
        }
    }

    private func detailsHandle(sideBySide: Bool) -> some View {
        let title = L10n.text(detailsVisible ? "hideProgrammeAndReception" : "showProgrammeAndReception")
        let symbol = sideBySide ? (detailsVisible ? "chevron.right" : "chevron.left") :
            (detailsVisible ? "chevron.down" : "chevron.up")
        return Button { detailsVisible.toggle() } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: sideBySide ? 24 : 64, height: sideBySide ? 96 : 24)
                .background {
                    DetailsHandleBackground(sideBySide: sideBySide, highlighted: handleHovered)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { handleHovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(L10n.text(detailsVisible ? "visible" : "hidden"))
        .accessibilityIdentifier("focusedDetailsToggle")
        .frame(maxWidth: sideBySide ? nil : .infinity, maxHeight: sideBySide ? .infinity : nil)
    }
}

struct ProgrammeView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    let tuner: Tuner
    var scrolls = true
    var compact = false
    var titleOnly = false
    @State private var logo: (key: String, image: NSImage)?

    private var logoKey: String {
        [monitor.connection.baseURL?.absoluteString ?? "", monitor.connection.username,
         monitor.programmeChannel?.uuid ?? "", monitor.programmeChannel?.icon_public_url ?? "",
         String(monitor.channelIconRevision), monitor.connected ? "online" : "offline"].joined(separator: "\n")
    }

    var body: some View {
        Group {
            if scrolls { ScrollView { programmeContent } }
            else { programmeContent }
        }
        .background { DetailPanelBackground() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("programmeGuide"))
        .task(id: logoKey) {
            let key = logoKey
            guard let channel = monitor.programmeChannel else { logo = nil; return }
            let image = await monitor.channelIcon(for: channel)
            guard !Task.isCancelled else { return }
            logo = image.map { (key, $0) }
        }
    }

    private var programmeContent: some View {
            VStack(alignment: .leading, spacing: 16) {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    programmeHeader(current: monitor.programme?.current(at: context.date))
                }
                if !monitor.connected {
                    message(L10n.text("programmeOffline"))
                } else if monitor.paused {
                    message(L10n.text("programmePaused"))
                } else if monitor.preview(for: tuner) == nil {
                    message(L10n.text("programmeNoChannel"))
                } else if monitor.programmeChannel == nil {
                    message(L10n.text("programmeUnmapped"))
                } else if monitor.programmeLoading {
                    ProgressView(L10n.text("programmeLoading"))
                } else if let error = monitor.programmeError {
                    message(error.localizedDescription)
                    Button(L10n.text("retryProgramme")) { monitor.updateProgramme(force: true) }
                } else {
                    TimelineView(.periodic(from: .now, by: 15)) { context in
                        let current = monitor.programme?.current(at: context.date)
                        let next = monitor.programme?.next(at: context.date)
                        VStack(alignment: .leading, spacing: 16) {
                            if let current {
                                programme(current, label: "programmeNow", prominent: true)
                                if !titleOnly {
                                    ProgressView(value: current.progress(at: context.date)).accessibilityLabel(L10n.text("programmeProgress"))
                                    if monitor.viewingMode == .tv && !compact {
                                        recordingControls(current)
                                    }
                                    if let details = current.details {
                                        Text(details).font(.callout).lineSpacing(3).textSelection(.enabled)
                                    }
                                }
                            } else {
                                message(L10n.text("programmeNoCurrent"))
                            }
                            if !titleOnly {
                                Divider()
                                if let next {
                                    programme(next, label: "programmeNext", prominent: false)
                                } else {
                                    message(L10n.text("programmeNoNext"))
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, titleOnly ? 0 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AutomaticScrollIndicators())
    }

    private func programmeHeader(current: Programme?) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Text(L10n.text("programmeFor", monitor.preview(for: tuner)?.title ?? monitor.headerTuner(for: tuner).input.shortName))
                    .font(.headline).textSelection(.enabled)
                    .lineLimit(compact ? 2 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                if compact, monitor.viewingMode == .tv, monitor.connected, !monitor.paused,
                   !monitor.programmeLoading, monitor.programmeError == nil, let current {
                    recordingControls(current, compact: true)
                        .layoutPriority(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if let logo, logo.key == logoKey {
                Image(nsImage: logo.image).resizable().scaledToFit()
                    .frame(width: 84, height: 50, alignment: .center)
                    .frame(height: 34)
                    .offset(y: 10)
                    .accessibilityLabel(L10n.text("channelLogo", monitor.programmeChannel?.name ?? ""))
            }
        }
    }

    private func recordingControls(_ event: Programme, compact: Bool = false) -> some View {
        ProgrammeRecordingControls(recorder: monitor.recorder, event: event,
                                   connected: monitor.connected && !monitor.paused,
                                   startedAt: monitor.recordingStartedAt(for: event), compact: compact) {
            monitor.updateProgramme(force: true)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(ThemeColors.detailSecondary).fixedSize(horizontal: false, vertical: true)
    }

    private func programme(_ event: Programme, label: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.text(label)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(time(event.startDate)) – \(time(event.stopDate))")
                    .font(.caption).foregroundStyle(ThemeColors.detailSecondary).monospacedDigit()
            }
            Text(event.title ?? L10n.text("programmeUntitled"))
                .font(prominent ? .title2.weight(.semibold) : .headline).textSelection(.enabled)
            if !titleOnly, let subtitle = event.subtitle, !subtitle.isEmpty, subtitle != event.title {
                Text(subtitle).font(.callout).foregroundStyle(ThemeColors.detailSecondary).textSelection(.enabled)
            }
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(language.language.locale))
    }
}

private struct ProgrammeRecordingControls: View {
    @ObservedObject var recorder: Recorder
    let event: Programme
    let connected: Bool
    let startedAt: Date?
    var compact = false
    let refreshProgramme: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var buttonFocused: Bool
    private var key: String { Recorder.key(event) }
    private var current: Programme { recorder.recording(for: event) }
    private var recording: Bool { recorder.isRecording(event) }
    private var restart: Bool { recorder.canRestart(event) }
    private var busy: Bool { recorder.pending.contains(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if recording {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 8) {
                        if !reduceMotion && scenePhase != .background {
                            let pulse = Int(context.date.timeIntervalSince1970 / 0.8).isMultiple(of: 2)
                            recordingButton(tint: pulse ? ThemeColors.recording : ThemeColors.recordingPulse)
                                .animation(.easeInOut(duration: 0.6), value: pulse)
                        } else {
                            recordingButton(tint: ThemeColors.recording)
                        }
                        if !busy, let elapsed = RecordingElapsed.label(since: startedAt, at: context.date) {
                            Text(elapsed)
                                .font(.callout).foregroundStyle(ThemeColors.detailSecondary)
                                .monospacedDigit().fixedSize()
                                .accessibilityLabel(L10n.text("recordingElapsed"))
                                .accessibilityValue(elapsed)
                        }
                    }
                }
                if !compact { Text(L10n.text("recordingActive")).font(.caption).foregroundStyle(.secondary) }
            } else if restart {
                recordingButton(tint: ThemeColors.recording)
                if !compact {
                    Text(L10n.text("recordingKept")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                availability
            } else if current.recordingIsFinished || recorder.stopped.contains(current.dvrUuid ?? "") {
                Label(L10n.text("recordingStopped"), systemImage: "checkmark.circle").font(.callout)
                if !compact {
                    Text(L10n.text("recordingKept")).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if current.hasRecording || recorder.submitted.contains(key) {
                Label(L10n.text(recorder.submitted.contains(key) ? "recordingRequested" : "recordingExists"), systemImage: "checkmark.circle")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                recordingButton(tint: ThemeColors.recording)
                availability
            }
            if current.recordingHasError {
                Label(L10n.text("recordingServerError"), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(ThemeColors.warning).fixedSize(horizontal: false, vertical: true)
            }
            if let error = recorder.errors[key] {
                Text(error.localizedDescription).font(.caption).foregroundStyle(ThemeColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: "\(key)/\(event.dvrUuid ?? "")/\(connected)") {
            guard connected else { return }
            await recorder.refreshAvailability()
            while !Task.isCancelled {
                await recorder.refreshRecording(event)
                do { try await Task.sleep(for: .seconds(5)) }
                catch { return }
            }
        }
    }

    @ViewBuilder private var availability: some View {
        if recorder.checking {
            ProgressView(L10n.text("recordingChecking")).controlSize(.small)
        } else if let error = recorder.availabilityError {
            Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(L10n.text("recordingCheckAgain")) { Task { await recorder.refreshAvailability(force: true) } }
                .font(.caption)
        }
    }

    private func recordingButton(tint: Color) -> some View {
        let title = L10n.text(recording ? (busy ? "recordingStopping" : "stopRecording") : (busy ? "recordingRequesting" : (restart ? "recordAgain" : "recordUntilEnd")))
        return Button {
            let stop = recording
            Task {
                if stop { await recorder.stop(event) }
                else { await recorder.record(event) }
                refreshProgramme()
            }
        } label: {
            if recording {
                Text(title)
            } else {
                Label(title, systemImage: "record.circle")
            }
        }
        .buttonStyle(RecordingButtonStyle(color: tint, compact: compact))
        .fixedSize()
        .focused($buttonFocused)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(buttonFocused ? Color.accentColor : .clear, lineWidth: 2))
        .disabled(!connected || (recording ? !recorder.canStop(event) : !recorder.canRecord(event)))
        .help(L10n.text(recording ? "stopRecordingHelp" : (restart ? "recordAgainHelp" : "recordUntilEndHelp")))
        .accessibilityValue(recording ? L10n.text("recordingActive") : "")
    }
}

private struct RecordingButtonStyle: ButtonStyle {
    let color: Color
    var compact = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(compact ? .caption.weight(.medium) : .callout.weight(.medium))
            .padding(.horizontal, compact ? 8 : 11).padding(.vertical, compact ? 5 : 6)
            .foregroundStyle(.white)
            .background {
                RoundedRectangle(cornerRadius: 6).fill(color)
                    .brightness(configuration.isPressed ? -0.12 : 0)
            }
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.45)
    }
}
