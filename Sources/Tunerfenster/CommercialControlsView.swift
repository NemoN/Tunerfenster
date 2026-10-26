import SwiftUI

struct CommercialSettingsView: View {
    @ObservedObject private var language = LanguageStore.shared
    @ObservedObject private var preferences = CommercialPreferences.shared

    var body: some View {
        DisclosureGroup(L10n.text("commercialSettings")) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(L10n.text("commercialAutomatic"), isOn: $preferences.automatic)
                    .help(L10n.text("commercialAutomaticHelp"))
                TextField(L10n.text("commercialHost"), text: $preferences.host, prompt: Text(L10n.text("commercialSameServer")))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L10n.text("commercialHost"))
                HStack {
                    Text(L10n.text("commercialPort"))
                    TextField("9982", value: $preferences.port, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                        .accessibilityLabel(L10n.text("commercialPort"))
                }
                Text(LocalizedStringKey(L10n.text("commercialSettingsHelp"))).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(.top, 8)
        }
    }
}
