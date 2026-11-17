import Foundation

struct AIModelOption: Identifiable {
    let selection: AIModelSelection
    let title: String
    let sourceTitle: String
    let menuIcon: PopoverMenuIcon

    static let appleIntelligenceIcon = PopoverMenuIcon.symbol("apple.intelligence")

    @MainActor
    static func availableGroups(settings: AISettingsStore) -> [AIModelOptionGroup] {
        var groups: [AIModelOptionGroup] = []
        if settings.isAppleIntelligenceAvailable(), settings.isRouteEnabled(.appleIntelligence) {
            let title = String(localized: "On device")
            groups.append(AIModelOptionGroup(
                source: .appleIntelligence, title: title,
                options: [AIModelOption(
                    selection: .appleIntelligence, title: AppleIntelligence.title,
                    sourceTitle: title, menuIcon: appleIntelligenceIcon)]))
        }
        for connection in settings.connections where settings.isRouteEnabled(.api(connection.id)) {
            let options = connection.models.filter {
                settings.isModelShown($0, in: .api(connection.id))
            }.map { model in
                AIModelOption(
                    selection: .api(connection: connection.id, model: model, effort: nil),
                    title: model, sourceTitle: connection.title,
                    menuIcon: icon(AIBrand.resolve(provider: connection.provider, model: model)))
            }
            if !options.isEmpty {
                groups.append(AIModelOptionGroup(
                    source: .api(connection.id), title: connection.title, options: options))
            }
        }
        return groups
    }

    /// An unrecognised model keeps the generic sparkle rather than borrowing someone's mark.
    static func icon(_ brand: AIBrand?) -> PopoverMenuIcon {
        brand.map { .asset($0.assetName) } ?? .symbol("sparkles")
    }

    @MainActor
    static func withDefaultEffort(
        _ selection: AIModelSelection, settings: AISettingsStore
    ) -> AIModelSelection {
        guard case .api(let connection, let model, _) = selection else { return selection }
        return selection.withEffort(
            settings.connection(id: connection)?.reasoningOptions(for: model)?.resolvedEffort(nil))
    }

    @MainActor
    static func efforts(
        for selection: AIModelSelection?, settings: AISettingsStore
    ) -> [AIEffort] {
        guard case .api(let connection, let model, _) = selection else { return [] }
        return settings.connection(id: connection)?.reasoningOptions(for: model)?
            .efforts.map { AIEffort(id: $0, detail: nil) } ?? []
    }

    var id: AIModelSelection { selection }
    func matches(_ other: AIModelSelection) -> Bool {
        selection.source == other.source && selection.model == other.model
    }
}

struct AIModelOptionGroup: Identifiable {
    let source: AIModelSource
    let title: String
    var options: [AIModelOption]
    var id: AIModelSource { source }
}
