import SwiftUI

struct FocusedTunerView: View {
    @ObservedObject var monitor: Monitor
    let tuner: Tuner
    let tile: AnyView

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 1000 {
                HStack(alignment: .top, spacing: 14) {
                    tile.frame(maxWidth: .infinity, maxHeight: .infinity)
                    ProgrammeView(monitor: monitor, tuner: tuner).frame(width: 320, height: geometry.size.height)
                }
            } else {
                VStack(spacing: 10) {
                    tile.frame(maxWidth: .infinity, maxHeight: .infinity)
                    ProgrammeView(monitor: monitor, tuner: tuner)
                        .frame(height: min(220, max(130, geometry.size.height * 0.38)))
                }
            }
        }
    }
}

struct ProgrammeView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var monitor: Monitor
    let tuner: Tuner
    @State private var logo: (key: String, image: NSImage)?

    private var logoKey: String {
        [monitor.connection.baseURL?.absoluteString ?? "", monitor.connection.username,
         monitor.programmeChannel?.uuid ?? "", monitor.programmeChannel?.icon_public_url ?? "",
         String(monitor.channelIconRevision), monitor.connected ? "online" : "offline"].joined(separator: "\n")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Text(L10n.text("programmeFor", monitor.preview(for: tuner)?.title ?? tuner.input.shortName))
                        .font(.headline).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let logo, logo.key == logoKey {
                        Image(nsImage: logo.image).resizable().scaledToFit()
                            .frame(width: 84, height: 50, alignment: .center)
                            .accessibilityLabel(L10n.text("channelLogo", monitor.programmeChannel?.name ?? ""))
                    }
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
                                ProgressView(value: current.progress(at: context.date)).accessibilityLabel(L10n.text("programmeProgress"))
                                if let details = current.details {
                                    Text(details).font(.callout).lineSpacing(3).textSelection(.enabled)
                                }
                            } else {
                                message(L10n.text("programmeNoCurrent"))
                            }
                            Divider()
                            if let next {
                                programme(next, label: "programmeNext", prominent: false)
                            } else {
                                message(L10n.text("programmeNoNext"))
                            }
                        }
                    }
                }
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
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

    private func message(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func programme(_ event: Programme, label: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.text(label)).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(time(event.startDate)) – \(time(event.stopDate))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(event.title ?? L10n.text("programmeUntitled"))
                .font(prominent ? .title2.weight(.semibold) : .headline).textSelection(.enabled)
            if let subtitle = event.subtitle, !subtitle.isEmpty, subtitle != event.title {
                Text(subtitle).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(language.language.locale))
    }
}
