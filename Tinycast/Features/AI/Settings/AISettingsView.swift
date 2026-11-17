import SwiftUI

struct AISettingsView: View {
    @Environment(AISettingsStore.self) private var settings

    @State private var providersPresented = false

    var body: some View {
        Form {
            Section {
                SettingsRow(
                    title: "Providers", subtitle: providerSummary, anchor: .aiProviders
                ) {
                    Button("Manage…") { providersPresented = true }
                }
            } header: {
                SettingsSectionHeader(.aiProviders)
            }
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.ai)
        .settingsEditorPanel(isPresented: $providersPresented) {
            AIProvidersPanel(onDone: { providersPresented = false })
        }
    }

    private var providerSummary: String {
        var providers: [String] = []
        if !settings.connections.isEmpty {
            let count = settings.connections.count
            providers.append(String(localized: "\(count) API connections"))
        }
        return providers.isEmpty
            ? String(localized: "No external providers ready") : providers.joined(separator: ", ")
    }
}
