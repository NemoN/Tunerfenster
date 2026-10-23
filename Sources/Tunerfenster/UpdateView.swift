import AppKit
import SwiftUI

struct UpdatePreference: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var updater: UpdateChecker

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(L10n.text("automaticUpdateChecks"), isOn: $updater.automaticChecks)
            Text(L10n.text("automaticUpdateNote"))
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: updater.automaticChecks) { _, enabled in
            if enabled { Task { await updater.check(automatically: true) } }
        }
    }
}

struct UpdateSettingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var updater: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text("softwareUpdates")).font(.headline)
            UpdatePreference(updater: updater)
            HStack {
                Button(L10n.text("checkForUpdates")) {
                    openWindow(id: "updates")
                    Task { await updater.check() }
                }.disabled(updater.isChecking)
                if updater.isChecking { ProgressView().controlSize(.small).accessibilityLabel(L10n.text("updateChecking")) }
                Spacer()
                Text(L10n.text("installedVersion", updater.currentVersion)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct UpdateBanner: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var updater: UpdateChecker
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if updater.showBanner, let update = updater.available {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle").foregroundStyle(Color.accentColor)
                Text(L10n.text("updateAvailable", update.version.description)).font(.callout)
                Spacer(minLength: 8)
                Button(L10n.text("viewUpdate")) { openWindow(id: "updates") }
                Button { updater.dismissBanner() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help(L10n.text("updateLater")).accessibilityLabel(L10n.text("updateLater"))
            }
            .padding(12).background(Color.accentColor.opacity(0.09))
            .padding(.horizontal, 14).padding(.bottom, 10)
        }
    }
}

struct UpdateView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject var updater: UpdateChecker
    @State private var openingFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Tunerfenster").font(.title2.weight(.semibold))
                Text(L10n.text("updateInstalled", updater.currentVersion, updater.architecture.title))
                    .foregroundStyle(.secondary).font(.callout)
            }
            if updater.isChecking {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text("updateChecking"))
                }.accessibilityElement(children: .combine)
            }
            if let update = updater.available {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("updateAvailable", update.version.description)).font(.title3.weight(.semibold))
                    if let download = update.downloadURL {
                        Text(L10n.text("updateInstallNote")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 12) {
                            Button(L10n.text("downloadUpdate", update.architecture == .appleSilicon ? "Apple Silicon" : "Intel")) { open(download) }
                                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                            Button(L10n.text("updateReleaseNotes")) { open(update.releaseURL) }
                        }
                    } else {
                        Text(L10n.text("updateMissingAsset", update.architecture.title))
                            .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button(L10n.text("updateReleaseNotes")) { open(update.releaseURL) }.buttonStyle(.borderedProminent)
                    }
                }
            } else if !updater.isChecking, updater.failure == nil {
                if case .noReleases = updater.result {
                    Text(L10n.text("updateNoReleases")).fixedSize(horizontal: false, vertical: true)
                } else if case .upToDate = updater.result {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.text("updateUpToDate"), systemImage: "checkmark.circle")
                            .font(.headline)
                        Text(L10n.text("updateUpToDateNote", updater.currentVersion)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if let failure = updater.failure {
                Label(failure.message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if openingFailed {
                Text(L10n.text("updateOpenFailed")).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            UpdatePreference(updater: updater)
            HStack(alignment: .center, spacing: 12) {
                if let date = updater.lastChecked {
                    Text(L10n.text("updateLastChecked", date.formatted(.dateTime.day().month().hour().minute().locale(language.language.locale))))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(L10n.text("checkForUpdates")) {
                    openingFailed = false
                    Task { await updater.check() }
                }.disabled(updater.isChecking)
            }
        }
        .padding(26).frame(width: 520, alignment: .leading)
        .task { if updater.result == nil { await updater.check() } }
    }

    private func open(_ url: URL) { openingFailed = !NSWorkspace.shared.open(url) }
}
