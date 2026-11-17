import SwiftUI

struct AISettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AISettingsStore.self) private var settings
    @Environment(ChatGPTSubscriptionManager.self) private var subscription
    @Environment(InstalledAIManager.self) private var installedAI

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
        .onAppear { core.applyInstalledAILifecycle() }
        .onChange(of: settings.enabledInstalledProviders) { core.applyInstalledAILifecycle() }
    }

    private var providerSummary: String {
        var providers: [String] = []
        if subscription.isConnected { providers.append("Codex") }
        for kind in InstalledAIKind.managedCLIKinds
        where installedAI.status(for: kind).isReady {
            providers.append(kind.title)
        }
        if !settings.connections.isEmpty {
            let count = settings.connections.count
            providers.append(String(localized: "\(count) API connections"))
        }
        return providers.isEmpty
            ? String(localized: "No external providers ready") : providers.joined(separator: ", ")
    }
}
