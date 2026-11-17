import AppKit
import SwiftUI

enum AIProviderRoute: Hashable {
    case appleIntelligence
    case api(UUID)

    var source: AIModelSource {
        switch self {
        case .appleIntelligence: return .appleIntelligence
        case .api(let id): return .api(id)
        }
    }
}

/// One page of a provider's detail; a route lists only the pages it has something to put on.
enum AIProviderTab: String, CaseIterable, Identifiable {
    case overview
    case models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "Overview")
        case .models: return String(localized: "Models")
        }
    }

    static func tabs(for route: AIProviderRoute) -> [AIProviderTab] {
        switch route {
        case .appleIntelligence: return [.overview]
        case .api: return [.overview, .models]
        }
    }
}

struct AIProvidersPanel: View {
    @Environment(AISettingsStore.self) private var settings

    let onDone: () -> Void

    @State private var selection: AIProviderRoute?
    @State private var keyStatuses: [UUID: Bool] = [:]
    @State private var connectionsWithHeaders: Set<UUID> = []
    @State private var keyError = false
    @State private var editor: AIConnectionEditorTarget?
    @State private var pendingRemoval: AIConnection?
    @State private var modelQuery = ""
    /// Kept across providers, as Mail keeps its tab across accounts; one without it shows Overview.
    @State private var tab = AIProviderTab.overview

    private let keyStore = KeychainSecretStore.aiAPIKeys
    private let headerStore = KeychainSecretStore.aiRequestHeaders

    var body: some View {
        VStack(spacing: 0) {
            SettingsEditorHeader(
                title: "AI Providers",
                subtitle: "On-device models and API connections."
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.dialogInset)
            .padding(.top, Theme.Spacing.dialogInset)
            .padding(.bottom, Theme.Spacing.xl)
            Divider()
            HStack(spacing: 0) {
                list
                    .frame(width: Theme.Size.aiProvidersList)
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Stated, never intrinsic: selecting a longer provider must not resize the panel.
            .frame(height: Theme.Size.aiProvidersPanel.height)
            Divider()
            HStack {
                Spacer(minLength: 0)
                Button("Done", action: onDone)
                    .buttonStyle(.modalAction(.primary, fillsWidth: false))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Theme.Spacing.xxl)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .frame(width: Theme.Size.aiProvidersPanel.width)
        .settingsEditorPanelSurface(controlsOnGlass: false)
        .releasesFocusOnOutsideClick()
        .settingsEditorPanel(item: $editor) { target in
            AIConnectionEditorPanel(
                target: target,
                onSave: saveConnection,
                onCancel: { editor = nil })
        }
        .confirmationDialog(
            pendingRemoval.map { String(localized: "Remove “\($0.title)”?") }
                ?? String(localized: "Remove connection?"),
            isPresented: removalPresented,
            titleVisibility: .visible
        ) {
            Button("Remove Connection", role: .destructive) {
                if let pendingRemoval { removeConnection(pendingRemoval) }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("Its saved API key will also be deleted from Keychain.")
        }
        .onAppear {
            selection = selection ?? initialSelection
            loadKeyStatuses()
        }
        .onChange(of: selection) { modelQuery = "" }
        .onChange(of: settings.connections.map(\.id)) { _, ids in
            if case .api(let id) = selection, !ids.contains(id) { selection = .appleIntelligence }
        }
    }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section("On This Mac") {
                    listRow(.appleIntelligence)
                }
                Section("API Connections") {
                    if settings.connections.isEmpty {
                        Text("None yet")
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(settings.connections) { listRow(.api($0.id)) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            Divider()
            listActions
        }
    }

    private func listRow(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            AIProviderTile(icon: icon(for: route))
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .lineLimit(1)
                Text(caption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .tag(route)
    }

    private var listActions: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Menu {
                ForEach(AIProviderKind.allCases) { provider in
                    Button(provider.title) {
                        editor = AIConnectionEditorTarget(
                            connection: AIConnection(provider: provider),
                            hasStoredKey: false, headers: [:], isNew: true)
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add API Connection")
            .accessibilityLabel("Add API Connection")
            Button {
                pendingRemoval = selectedConnection
            } label: {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)
            .disabled(selectedConnection == nil)
            .help("Remove API Connection")
            .accessibilityLabel("Remove API Connection")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .appleIntelligence?:
            detailForm(.appleIntelligence) { _ in appleIntelligenceSections }
        case .api(let id)?:
            if let connection = settings.connection(id: id) {
                detailForm(.api(id)) { connectionSections(connection, tab: $0) }
            }
        case nil:
            ContentUnavailableView("Select a provider", systemImage: "sparkles")
        }
    }

    private func detailForm<Content: View>(
        _ route: AIProviderRoute, @ViewBuilder content: (AIProviderTab) -> Content
    ) -> some View {
        let tabs = AIProviderTab.tabs(for: route)
        let shown = tabs.contains(tab) ? tab : .overview
        return VStack(spacing: 0) {
            detailHeader(route)
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.top, Theme.Spacing.xl)
            if tabs.count > 1 {
                Picker("Page", selection: $tab) {
                    ForEach(tabs) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
                .padding(.top, Theme.Spacing.xl)
            }
            Form { content(shown) }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
        }
        .id(route)
    }

    private func detailHeader(_ route: AIProviderRoute) -> some View {
        HStack(spacing: Theme.Spacing.xl) {
            AIProviderTile(icon: icon(for: route), size: Theme.Size.settingsRowIcon * 1.5)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title(for: route))
                    .font(Theme.Typography.panelTitle)
                    .lineLimit(1)
                Text(kindCaption(for: route))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.lg)
            switch route {
            case .api(let id):
                if let connection = settings.connection(id: id) {
                    Button("Edit…") { edit(connection) }
                }
            case .appleIntelligence:
                EmptyView()
            }
            routeToggle(route)
        }
    }

    // MARK: On this Mac

    @ViewBuilder
    private var appleIntelligenceSections: some View {
        let available = settings.isAppleIntelligenceAvailable()
        if !settings.isRouteEnabled(.appleIntelligence) { turnedOffSection() }
        Section {
            LabeledContent {
                if available {
                    Text("Ready")
                        .foregroundStyle(.secondary)
                } else if AppleIntelligenceProvider.status().isSupported {
                    Button("Open System Settings…") {
                        NSWorkspace.shared.open(AppleIntelligence.settingsURL)
                    }
                }
            } label: {
                Text(AppleIntelligence.title)
                Text(
                    available
                        ? String(localized: "Runs on this Mac. Nothing leaves it.")
                        : AppleIntelligenceProvider.status().message
                            ?? String(localized: "Not available on this Mac."))
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Choose a model in Quick Actions settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func turnedOffSection(footer: String? = nil) -> some View {
        Section {
            LabeledContent {
                EmptyView()
            } label: {
                Label("Turned off", systemImage: "pause.circle")
                Text("Tinycast leaves it alone, and its models stay out of every model picker.")
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: API connections

    @ViewBuilder
    private func connectionSections(
        _ connection: AIConnection, tab: AIProviderTab
    ) -> some View {
        if !settings.isRouteEnabled(.api(connection.id)) { turnedOffSection() }
        if tab == .models {
            modelsSection(
                route: .api(connection.id),
                models: connection.models.map { ProviderModel(id: $0, name: $0) })
        } else {
            connectionSection(connection)
        }
    }

    private func connectionSection(_ connection: AIConnection) -> some View {
        Section {
            LabeledContent("Provider", value: connection.provider.title)
            LabeledContent("Base URL") {
                Text(connection.baseURL)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LabeledContent("API key") {
                Text(keyStatus(connection))
                    .foregroundStyle(
                        keyIsMissing(connection) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            }
            if connectionsWithHeaders.contains(connection.id) {
                LabeledContent("Request headers") {
                    Text("Stored in Keychain").foregroundStyle(.secondary)
                }
            }
            if keyError {
                Label("The login Keychain could not be accessed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Keys stay in your login Keychain, tied to the endpoint they were saved for.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Models

    @ViewBuilder
    private func modelsSection(route: AIProviderRoute, models: [ProviderModel]) -> some View {
        if models.isEmpty {
            Section {
                Text("Models are listed here once \(title(for: route)) is ready.")
                    .foregroundStyle(.secondary)
            }
        } else {
            let source = route.source
            let shownSet = settings.shownModels[source.storageKey].map(Set.init)
            let shownCount = shownSet.map { set in models.count { set.contains($0.id) } } ?? models.count
            let matches = filtered(models)
            Section {
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button("Show All") { settings.showAllModels(in: source) }
                            .disabled(shownCount == models.count)
                        Button("Hide All") { settings.hideAllModels(in: source) }
                    }
                    .fixedSize()
                } label: {
                    Text("\(shownCount) of \(models.count) models in the model picker")
                }
                if models.count > Self.filterThreshold {
                    SettingsFilterField(prompt: "Filter models", query: $modelQuery)
                }
                if matches.isEmpty {
                    Text("No model matches “\(modelQuery)”.")
                        .foregroundStyle(.secondary)
                }
                if !matches.isEmpty {
                    AIModelChecklist(
                        items: matches.map { model in
                            AIModelChecklist.Item(
                                id: model.id, title: model.name,
                                isOn: shownSet?.contains(model.id) ?? true)
                        },
                        onToggle: { id, isOn in
                            settings.setModel(
                                id, shown: isOn, in: source, available: models.map(\.id))
                        })
                }
            }
        }
    }

    /// Keep larger catalogs searchable without adding a filter to short lists.
    private static let filterThreshold = 8

    private func filtered(_ models: [ProviderModel]) -> [ProviderModel] {
        let query = modelQuery.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: - Titles and glyphs

    private func title(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return AppleIntelligence.title
        case .api(let id):
            return settings.connection(id: id)?.title ?? String(localized: "API Connection")
        }
    }

    private func kindCaption(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence: return String(localized: "On this Mac · No account needed")
        case .api(let id):
            let provider = settings.connection(id: id)?.provider.title ?? ""
            return String(localized: "API connection · \(provider)")
        }
    }

    /// The one line a reader scans the list for: is it usable, and if not, why.
    private func caption(for route: AIProviderRoute) -> String {
        switch route {
        case .appleIntelligence:
            guard settings.isRouteEnabled(.appleIntelligence) else { return String(localized: "Off") }
            return settings.isAppleIntelligenceAvailable()
                ? String(localized: "Ready · Runs on this Mac") : String(localized: "Unavailable")
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return "" }
            guard settings.isRouteEnabled(.api(id)) else { return String(localized: "Off") }
            if keyIsMissing(connection) { return String(localized: "Key missing") }
            let count = modelCount(connection.models.count)
            return connection.name.isEmpty ? count : "\(connection.provider.title) · \(count)"
        }
    }

    private func icon(for route: AIProviderRoute) -> PopoverMenuIcon {
        switch route {
        case .appleIntelligence: return AIModelOption.appleIntelligenceIcon
        case .api(let id):
            guard let connection = settings.connection(id: id) else { return .symbol("sparkles") }
            // OpenRouter is its own brand; resolving by model would show whichever vendor came first.
            if connection.provider == .openRouter { return .asset(AIBrand.openRouter.assetName) }
            return AIModelOption.icon(
                AIBrand.resolve(provider: connection.provider, model: connection.models.first ?? ""))
        }
    }

    private func modelCount(_ count: Int) -> String {
        String(localized: "\(count) models")
    }

    // MARK: - Actions

    private var initialSelection: AIProviderRoute { .appleIntelligence }

    private var selectedConnection: AIConnection? {
        guard case .api(let id) = selection else { return nil }
        return settings.connection(id: id)
    }

    private func routeToggle(_ route: AIProviderRoute) -> some View {
        // Off for display only: the stored choice belongs to the reader, not to this Mac.
        let unsupported =
            route == .appleIntelligence && !AppleIntelligenceProvider.status().isSupported
        return Toggle(
            "Enable \(title(for: route))",
            isOn: Binding(
                get: { !unsupported && settings.isRouteEnabled(route.source) },
                set: { settings.setRoute(route.source, enabled: $0) })
        )
        .labelsHidden()
        .toggleStyle(.switch)
        .disabled(unsupported)
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } })
    }

    private func keyIsMissing(_ connection: AIConnection) -> Bool {
        keyStatuses[connection.id] != true && !AIEndpointPolicy.isLoopback(connection.baseURL)
            && !connectionsWithHeaders.contains(connection.id)
    }

    private func keyStatus(_ connection: AIConnection) -> String {
        if keyStatuses[connection.id] == true { return String(localized: "Stored in Keychain") }
        if AIEndpointPolicy.isLoopback(connection.baseURL) {
            return String(localized: "None needed locally")
        }
        return connectionsWithHeaders.contains(connection.id)
            ? String(localized: "Not set") : String(localized: "Missing")
    }

    private func edit(_ connection: AIConnection) {
        do {
            editor = AIConnectionEditorTarget(
                connection: connection,
                hasStoredKey: keyStatuses[connection.id] == true,
                headers: try headerStore.values(for: connection.id),
                isNew: false)
        } catch {
            // An editor opened without the saved headers would erase them on Save.
            keyError = true
        }
    }

    private func saveConnection(
        _ connection: AIConnection, key: String, headers: [String: String], isNew: Bool
    ) -> String? {
        let outcome = AIConnectionKeyPolicy.resolve(
            enteredKey: key, connection: connection, saved: settings.connection(id: connection.id),
            hasStoredKey: keyStatuses[connection.id] == true, hasHeaders: !headers.isEmpty)
        do {
            switch outcome {
            case .store(let key): try keyStore.setSecret(key, for: connection.id)
            case .removeStored: try keyStore.removeSecret(for: connection.id)
            case .keep: break
            case .reject(let message): return message
            }
            try headerStore.setValues(headers, for: connection.id)
            settings.save(connection)
            editor = nil
            selection = .api(connection.id)
            loadKeyStatuses()
            return nil
        } catch {
            keyError = true
            return isNew
                ? String(localized: "The key could not be saved to Keychain.")
                : String(localized: "The saved key could not be updated in Keychain.")
        }
    }

    private func removeConnection(_ connection: AIConnection) {
        do {
            try keyStore.removeSecret(for: connection.id)
            try headerStore.removeSecret(for: connection.id)
            settings.removeConnection(id: connection.id)
            pendingRemoval = nil
            loadKeyStatuses()
        } catch {
            keyError = true
        }
    }

    private func loadKeyStatuses() {
        var statuses: [UUID: Bool] = [:]
        var withHeaders: Set<UUID> = []
        do {
            for connection in settings.connections {
                statuses[connection.id] = try keyStore.hasSecret(for: connection.id)
                if try headerStore.hasSecret(for: connection.id) { withHeaders.insert(connection.id) }
            }
            keyError = false
        } catch {
            keyError = true
        }
        keyStatuses = statuses
        connectionsWithHeaders = withHeaders
    }
}

private struct ProviderModel: Identifiable {
    let id: String
    let name: String
}

private struct AIProviderTile: View {
    let icon: PopoverMenuIcon
    var size = Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2

    var body: some View {
        let scale = size / (Theme.Size.settingsSidebarGlyph + Theme.Spacing.xs * 2)
        glyph
            .frame(
                width: Theme.Size.settingsSidebarGlyph * scale,
                height: Theme.Size.settingsSidebarGlyph * scale
            )
            .foregroundStyle(.primary)
            .padding(Theme.Spacing.xs * scale)
            .background(
                Theme.Colors.controlSurface,
                in: RoundedRectangle(
                    cornerRadius: Theme.Radius.thumbnail * scale, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        switch icon {
        case .asset(let name):
            Image(name).resizable().renderingMode(.template).scaledToFit()
        case .symbol(let name):
            Image(systemName: name).resizable().scaledToFit()
        case .file, .thumbnail, .blank:
            Image(systemName: "sparkles").resizable().scaledToFit()
        }
    }
}
