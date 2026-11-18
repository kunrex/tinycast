import Foundation

struct AIRequest: Equatable, Sendable {
    /// The highest every Claude model accepts, for one whose own ceiling the catalog never named.
    static let defaultMaxOutputTokens = 32_000

    let instructions: String?
    let prompt: String
    let maxOutputTokens: Int

    init(
        instructions: String? = nil, prompt: String,
        maxOutputTokens: Int = defaultMaxOutputTokens
    ) {
        self.instructions = instructions
        self.prompt = prompt
        self.maxOutputTokens = maxOutputTokens
    }
}

enum AIStreamEvent: Equatable, Sendable {
    case text(String)
}

enum AIProviderError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case responseFailed(String)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .responseFailed(let message): return message
        case .malformedResponse:
            return String(localized: "The provider returned malformed streaming data.")
        }
    }
}
