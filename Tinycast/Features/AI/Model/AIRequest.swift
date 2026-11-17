import Foundation

/// An attached picture, already encoded for the wire; every provider takes it as a data URL.
struct AIImage: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// A file a route reads natively; a text-ish file never becomes one, it inlines as text instead.
struct AIDocument: Equatable, Hashable, Sendable {
    let data: Data
    let mimeType: String
    /// On the wire, unlike an image's: a model shown three PDFs needs to tell them apart.
    let name: String

    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

/// Requests cap near 25 MB and a data URL costs a third more, so the ceiling lives here.
enum AIAttachmentBudget {
    static let maxCount = 6
    static let maxBytes = 10 * 1_048_576
    /// Inlined text rides the newest turn, which is never trimmed, so it is capped before staging.
    static let maxInlinedTextBytes = 32 * 1_024

    /// Counted jointly: two independent ceilings would let six of each through.
    static func admits(images: [AIImage], documents: [AIDocument], addingBytes bytes: Int) -> Bool {
        let used =
            images.reduce(0) { $0 + $1.data.count }
            + documents.reduce(0) { $0 + $1.data.count }
        return images.count + documents.count < maxCount && used + bytes <= maxBytes
    }

    /// The longest leading run that fits, for a turn assembled by any route but the composer.
    /// Images fill first, so a picture is never dropped in favour of a document behind it.
    static func bounded(
        _ images: [AIImage], _ documents: [AIDocument]
    )
        -> (images: [AIImage], documents: [AIDocument])
    {
        var total = 0
        var count = 0
        let keptImages = images.prefix { image in
            guard count < maxCount, total + image.data.count <= maxBytes else { return false }
            total += image.data.count
            count += 1
            return true
        }
        let keptDocuments = documents.prefix { document in
            guard count < maxCount, total + document.data.count <= maxBytes else { return false }
            total += document.data.count
            count += 1
            return true
        }
        return (Array(keptImages), Array(keptDocuments))
    }
}

struct AIMessage: Equatable, Sendable {
    enum Role: String, Equatable, Sendable {
        case system
        case user
        case assistant
    }

    let role: Role
    let text: String
    let images: [AIImage]
    /// Only a PDF ever lands here: a text-ish file is inlined into `text` before any transport.
    let documents: [AIDocument]
    init(
        role: Role, text: String, images: [AIImage] = [], documents: [AIDocument] = []
    ) {
        self.role = role
        self.text = text
        self.images = images
        self.documents = documents
    }
}

struct AIRequest: Equatable, Sendable {
    /// The highest every Claude model accepts, for one whose own ceiling the catalog never named.
    static let defaultMaxOutputTokens = 32_000

    let instructions: String?
    let messages: [AIMessage]
    let maxOutputTokens: Int
    /// Lets the model search the web; each route has its own switch for that, all off by default.
    let webSearch: Bool

    init(
        instructions: String? = nil, messages: [AIMessage],
        maxOutputTokens: Int = defaultMaxOutputTokens,
        webSearch: Bool = false
    ) {
        self.instructions = instructions
        self.messages = messages
        self.maxOutputTokens = maxOutputTokens
        self.webSearch = webSearch
    }

}

struct AIUsage: Equatable, Sendable {
    var inputTokens: Int?
    var outputTokens: Int?
    /// Prompt tokens served from or written to a cache; Anthropic counts them outside `inputTokens`.
    var cachedInputTokens: Int?
    /// The part of `outputTokens` the model spent thinking.
    var reasoningTokens: Int?
    var costUSD: Double?

    var totalTokens: Int? {
        guard let inputTokens, let outputTokens else { return nil }
        return inputTokens + outputTokens
    }

    /// What the conversation now occupies in the window: every prompt token plus the reply.
    var contextTokens: Int? {
        totalTokens.map { $0 + (cachedInputTokens ?? 0) }
    }
}

enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case thinking
    /// Reasoning text, where a route shares it; never answer text, and never sent back as context.
    case reasoning(String)
    case searching(String?)
    case searched(String?)
    case usage(AIUsage)
    case finished
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
