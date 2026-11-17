import Foundation
import Observation

@MainActor
@Observable
final class AISettingsStore {
    private let defaults: UserDefaults

    private(set) var connections: [AIConnection] {
        didSet { persistConnections() }
    }
    /// Per route, the models its picker lists; no entry lists all it offers, later ones too.
    private(set) var shownModels: [String: [String]] {
        didSet { defaults.set(shownModels, forKey: AppSettingsKey.aiShownModels.rawValue) }
    }
    /// The on-device model and API connections switched off without being removed.
    private(set) var disabledRoutes: Set<String> {
        didSet {
            defaults.set(disabledRoutes.sorted(), forKey: AppSettingsKey.aiDisabledRoutes.rawValue)
        }
    }
    /// Asked each time: the model lands mid-session, and a flag read at launch would never notice.
    @ObservationIgnored let isAppleIntelligenceAvailable: @Sendable () -> Bool

    init(
        defaults: UserDefaults = .standard,
        isAppleIntelligenceAvailable: @escaping @Sendable () -> Bool = { false }
    ) {
        self.defaults = defaults
        self.isAppleIntelligenceAvailable = isAppleIntelligenceAvailable
        connections = Self.decodeConnections(
            defaults.data(forKey: AppSettingsKey.aiConnections.rawValue))
        shownModels =
            defaults.dictionary(forKey: AppSettingsKey.aiShownModels.rawValue) as? [String: [String]]
            ?? [:]
        disabledRoutes = Set(
            defaults.stringArray(forKey: AppSettingsKey.aiDisabledRoutes.rawValue) ?? [])
    }

    func connection(id: UUID) -> AIConnection? {
        connections.first { $0.id == id }
    }

    func save(_ connection: AIConnection) {
        let connection = normalized(connection)
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
    }

    func removeConnection(id: UUID) {
        connections.removeAll { $0.id == id }
        shownModels[AIModelSource.api(id).storageKey] = nil
        disabledRoutes.remove(AIModelSource.api(id).storageKey)
    }

    func isRouteEnabled(_ source: AIModelSource) -> Bool {
        return !disabledRoutes.contains(source.storageKey)
    }

    func setRoute(_ source: AIModelSource, enabled: Bool) {
        if enabled {
            disabledRoutes.remove(source.storageKey)
        } else {
            disabledRoutes.insert(source.storageKey)
        }
    }

    func isModelShown(_ model: String, in source: AIModelSource) -> Bool {
        shownModels[source.storageKey]?.contains(model) ?? true
    }

    /// `available` is the route's whole list, needed the first time one model is hidden from it.
    func setModel(
        _ model: String, shown: Bool, in source: AIModelSource, available: [String]
    ) {
        var shownList = shownModels[source.storageKey] ?? available
        shownList.removeAll { $0 == model }
        if shown { shownList.append(model) }
        // All shown again drops the entry, so a model the route adds later appears too.
        let everything = Set(available)
        shownModels[source.storageKey] =
            everything.isSubset(of: shownList) ? nil : shownList.filter(everything.contains)
    }

    func showAllModels(in source: AIModelSource) {
        shownModels[source.storageKey] = nil
    }

    func hideAllModels(in source: AIModelSource) {
        shownModels[source.storageKey] = []
    }

    private func persistConnections() {
        guard let data = try? JSONEncoder().encode(connections) else { return }
        defaults.set(data, forKey: AppSettingsKey.aiConnections.rawValue)
    }

    private func normalized(_ connection: AIConnection) -> AIConnection {
        var connection = connection
        connection.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        connection.baseURL = connection.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        connection.models = connection.models.compactMap {
            let model = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty, seen.insert(model).inserted else { return nil }
            return model
        }
        connection.visionModels = connection.visionModels.filter(seen.contains)
        connection.reasoningOptions = connection.reasoningOptions?.filter {
            seen.contains($0.key) && !$0.value.efforts.isEmpty
        }
        if connection.reasoningOptions?.isEmpty == true { connection.reasoningOptions = nil }
        connection.outputLimits = connection.outputLimits?.filter { seen.contains($0.key) }
        if connection.outputLimits?.isEmpty == true { connection.outputLimits = nil }
        return connection
    }

    private static func decodeConnections(_ data: Data?) -> [AIConnection] {
        guard let data,
            let connections = try? JSONDecoder().decode([AIConnection].self, from: data)
        else { return [] }
        return connections
    }

}
