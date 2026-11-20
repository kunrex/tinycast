import Foundation

struct AIResponsesDecoder: Sendable {
    private let secrets: [String]
    private var citations = AICitationLinker()
    private(set) var isTerminal = false

    init(secrets: [String]) {
        self.secrets = secrets
    }

    mutating func decode(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = event["type"] as? String
        else {
            throw AIProviderError.malformedResponse
        }
        switch type {
        case "response.output_text.delta", "response.refusal.delta":
            guard let delta = event["delta"] as? String else {
                throw AIProviderError.malformedResponse
            }
            guard !delta.isEmpty else { return [] }
            citations.record(delta)
            return [.text(delta)]
        case "response.output_text.annotation.added":
            guard let annotation = event["annotation"] as? [String: Any],
                annotation["type"] as? String == "url_citation",
                let url = annotation["url"] as? String,
                let link = citations.link(to: url)
            else { return [] }
            return [.text(link)]
        case "response.completed":
            guard let response = event["response"] as? [String: Any],
                response["output"] is [[String: Any]]
            else { throw AIProviderError.malformedResponse }
            isTerminal = true
            return []
        case "response.failed", "response.incomplete", "error":
            let response = event["response"] as? [String: Any] ?? event
            let error = response["error"] as? [String: Any]
            let details = response["incomplete_details"] as? [String: Any]
            throw AIProviderError.responseFailed(
                AIProviderFailure.described(
                    AIProviderFailure.stopped,
                    said: error?["message"] as? String ?? response["message"] as? String
                        ?? details?["reason"] as? String,
                    secrets: secrets))
        default:
            return []
        }
    }

}
