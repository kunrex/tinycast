import Foundation
import Observation

/// Quick Actions owns its route independently of provider connection settings.
@MainActor
@Observable
final class QuickActionSettingsStore {
    private let defaults: UserDefaults

    var settings: QuickActionSettings {
        didSet { persistSettings() }
    }
    /// An unset route defaults only to enabled, available on-device inference.
    private(set) var model: AIModelSelection? {
        didSet { persistModel() }
    }
    /// Keyed by `QuickAction.id`; an action without an entry follows `model`.
    private(set) var modelOverrides: [String: AIModelSelection] {
        didSet { persistModelOverrides() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var loaded = QuickActionSettings()
        loaded.storedPreviewChoices =
            defaults.dictionary(forKey: AppSettingsKey.quickActionPreviews.rawValue)
            as? [String: Bool] ?? [:]
        loaded.targetLanguage =
            defaults.string(forKey: AppSettingsKey.quickActionLanguage.rawValue) ?? ""
        loaded.storedInstructionOverrides =
            defaults.dictionary(forKey: AppSettingsKey.quickActionInstructions.rawValue)
            as? [String: String] ?? [:]
        settings = loaded
        model = Self.decode(
            AIModelSelection.self,
            from: defaults.data(forKey: AppSettingsKey.quickActionModel.rawValue))
        modelOverrides = Self.decodeOverrides(
            from: defaults.data(forKey: AppSettingsKey.quickActionModelOverrides.rawValue))
    }

    func select(_ selection: AIModelSelection?) {
        model = selection
    }

    func model(for action: QuickAction) -> AIModelSelection? {
        modelOverride(for: action) ?? model
    }

    func modelOverride(for action: QuickAction) -> AIModelSelection? {
        modelOverrides[action.id]
    }

    func setModelOverride(_ selection: AIModelSelection?, for action: QuickAction) {
        guard !action.usesTranslationFramework, modelOverrides[action.id] != selection else { return }
        modelOverrides[action.id] = selection
    }

    /// An unset route may default only to enabled, available on-device inference.
    func resolveModel(appleIntelligenceEnabled: Bool, appleIntelligenceAvailable: Bool) {
        guard model == nil, appleIntelligenceEnabled, appleIntelligenceAvailable else { return }
        model = .appleIntelligence
    }

    /// A removed connection must not leave a route pointing where nothing can answer.
    func repairModel(
        against connections: [AIConnection], appleIntelligenceEnabled: Bool,
        appleIntelligenceAvailable: Bool
    ) {
        if let model, !Self.reaches(model, through: connections) {
            self.model = nil
        }
        updateOverrides { Self.reaches($0, through: connections) ? $0 : nil }
        resolveModel(
            appleIntelligenceEnabled: appleIntelligenceEnabled,
            appleIntelligenceAvailable: appleIntelligenceAvailable)
    }

    private func updateOverrides(_ transform: (AIModelSelection) -> AIModelSelection?) {
        let updated = modelOverrides.compactMapValues(transform)
        if updated != modelOverrides { modelOverrides = updated }
    }

    private static func reaches(
        _ selection: AIModelSelection, through connections: [AIConnection]
    ) -> Bool {
        guard case .api(let id, let name, _) = selection else { return true }
        return connections.contains { $0.id == id && $0.models.contains(name) }
    }

    private func persistSettings() {
        defaults.set(
            settings.storedPreviewChoices, forKey: AppSettingsKey.quickActionPreviews.rawValue)
        defaults.set(settings.targetLanguage, forKey: AppSettingsKey.quickActionLanguage.rawValue)
        defaults.set(
            settings.storedInstructionOverrides,
            forKey: AppSettingsKey.quickActionInstructions.rawValue)
    }

    private func persistModel() {
        persist(model, forKey: .quickActionModel)
    }

    private func persistModelOverrides() {
        persist(modelOverrides.isEmpty ? nil : modelOverrides, forKey: .quickActionModelOverrides)
    }

    private func persist(_ value: (some Encodable)?, forKey key: AppSettingsKey) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key.rawValue)
            return
        }
        defaults.set(data, forKey: key.rawValue)
    }

    private static func decodeOverrides(from data: Data?) -> [String: AIModelSelection] {
        guard let data,
            let entries = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return entries.compactMapValues { entry in
            guard JSONSerialization.isValidJSONObject(entry),
                let encoded = try? JSONSerialization.data(withJSONObject: entry)
            else { return nil }
            return decode(AIModelSelection.self, from: encoded)
        }
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data?) -> Value? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
