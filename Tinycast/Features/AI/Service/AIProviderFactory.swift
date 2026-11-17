import FoundationModels
import Foundation

@MainActor
enum AIProviderFactory {
    /// `guardrails` reaches only the on-device model, the one route that filters locally.
    static func make(
        selection: AIModelSelection,
        settings: AISettingsStore,
        keyStore: KeychainSecretStore = .aiAPIKeys,
        guardrails: SystemLanguageModel.Guardrails = .default
    ) throws -> any AIProvider {
        switch selection {
        case .appleIntelligence:
            guard settings.isRouteEnabled(.appleIntelligence) else {
                throw AIProviderError.unavailable(
                    String(localized: "Apple Intelligence is disabled in AI Settings."))
            }
            if let message = AppleIntelligenceProvider.status().message {
                throw AIProviderError.unavailable(message)
            }
            return AppleIntelligenceProvider(guardrails: guardrails)
        case .api(let connectionID, let model, let savedEffort):
            guard let connection = settings.connection(id: connectionID) else {
                throw AIProviderError.unavailable(String(localized: "Choose an API connection in Settings."))
            }
            guard settings.isRouteEnabled(.api(connectionID)) else {
                throw AIProviderError.unavailable(
                    String(localized: "\(connection.title) is disabled in AI Settings."))
            }
            let baseURL: URL
            do {
                baseURL = try AIEndpointPolicy.validate(connection.baseURL)
            } catch let error as AIEndpointPolicy.ValidationError {
                throw AIProviderError.unavailable(error.localizedDescription)
            }
            let key: String
            do {
                key = try keyStore.secret(for: connection.id) ?? ""
            } catch {
                throw AIProviderError.unavailable(
                    String(localized: "The API key could not be read from Keychain."))
            }
            let headers: [String: String]
            do {
                headers = try KeychainSecretStore.aiRequestHeaders.values(for: connection.id)
            } catch {
                throw AIProviderError.unavailable(
                    String(localized: "The request headers could not be read from Keychain."))
            }
            guard AIEndpointPolicy.isLoopback(connection.baseURL) || !key.isEmpty || !headers.isEmpty
            else {
                throw AIProviderError.unavailable(String(localized: "Add an API key in Settings."))
            }
            let effort = connection.offeredEffort(savedEffort, for: model)
            return HTTPAIProvider(
                configuration: AIHTTPConfiguration(
                    provider: connection.provider, baseURL: baseURL, model: model, effort: effort,
                    disablesThinking: effort == AIConnection.ReasoningOptions.noEffort
                        && connection.takesThinkingField,
                    maxOutputTokens: connection.outputLimits?[model], headers: headers),
                apiKey: key)
        }
    }
}
