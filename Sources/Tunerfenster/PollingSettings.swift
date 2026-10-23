import SwiftUI

struct PollingInterval {
    static let key = "statusPollingSeconds"
    static let range = 1...60
    static let presets = [1, 2, 3, 5, 10, 15, 30, 60]

    static func validated(_ seconds: Int) -> Int { min(range.upperBound, max(range.lowerBound, seconds)) }

    static func load(from defaults: UserDefaults) -> Int {
        guard defaults.object(forKey: key) != nil else { return 3 }
        return validated(defaults.integer(forKey: key))
    }
}

struct PollingSettingsView: View {
    @ObservedObject var monitor: Monitor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Stepper(value: Binding(get: { monitor.pollingSeconds }, set: { monitor.setPollingSeconds($0) }), in: PollingInterval.range) {
                HStack {
                    Text(L10n.text("statusPollingInterval"))
                    Spacer()
                    Text(L10n.text("seconds", String(monitor.pollingSeconds))).monospacedDigit()
                }
            }
            .accessibilityLabel(L10n.text("statusPollingInterval"))
            .accessibilityValue(L10n.text("seconds", String(monitor.pollingSeconds)))
            Text(L10n.text("statusPollingNote")).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PollingIntervalMenu: View {
    @ObservedObject var monitor: Monitor
    @State private var customInterval = false

    var body: some View {
        Menu {
            Picker(L10n.text("statusPollingInterval"), selection: Binding(get: { monitor.pollingSeconds }, set: { monitor.setPollingSeconds($0) })) {
                ForEach(Array(Set(PollingInterval.presets + [monitor.pollingSeconds])).sorted(), id: \.self) { seconds in
                    Text(L10n.text("seconds", String(seconds))).tag(seconds)
                }
            }
            Divider()
            Button(L10n.text("customInterval")) { customInterval = true }
        } label: {
            Text(L10n.text("pollingEvery", String(monitor.pollingSeconds)))
        }
        .menuStyle(.borderlessButton).fixedSize()
        .help(L10n.text("statusPollingInterval"))
        .accessibilityLabel(L10n.text("statusPollingInterval"))
        .accessibilityValue(L10n.text("seconds", String(monitor.pollingSeconds)))
        .popover(isPresented: $customInterval) {
            PollingSettingsView(monitor: monitor).padding(18).frame(width: 320).playbackPanel()
        }
    }
}
