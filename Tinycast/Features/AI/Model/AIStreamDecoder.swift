import Foundation

struct SSEParser: Sendable {
    private var buffer = Data()

    mutating func feed(_ data: Data) -> [String] {
        buffer.append(data)
        var payloads: [String] = []
        while let boundary = nextBoundary() {
            let frame = buffer[..<boundary.lowerBound]
            buffer.removeSubrange(buffer.startIndex..<boundary.upperBound)
            if let payload = Self.payload(in: frame) { payloads.append(payload) }
        }
        return payloads
    }

    mutating func finish() -> [String] {
        guard !buffer.isEmpty else { return [] }
        defer { buffer.removeAll() }
        return Self.payload(in: buffer).map { [$0] } ?? []
    }

    private func nextBoundary() -> Range<Data.Index>? {
        let lf = buffer.range(of: Data([0x0A, 0x0A]))
        let crlf = buffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A]))
        switch (lf, crlf) {
        case (let lhs?, let rhs?): return lhs.lowerBound < rhs.lowerBound ? lhs : rhs
        case (let range?, nil), (nil, let range?): return range
        case (nil, nil): return nil
        }
    }

    private static func payload(in frame: some DataProtocol) -> String? {
        let text = String(decoding: frame, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
        var dataLines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(":") { continue }
            if line == "data" {
                dataLines.append("")
            } else if line.hasPrefix("data:") {
                var value = line.dropFirst(5)
                if value.first == " " { value = value.dropFirst() }
                dataLines.append(String(value))
            }
        }
        return dataLines.isEmpty ? nil : dataLines.joined(separator: "\n")
    }
}

/// Sources an API cites beside its text, inlined as Markdown links.
struct AICitationLinker: Sendable {
    private var text = ""
    private var linked: Set<String> = []

    mutating func record(_ delta: String) {
        text += delta
    }

    /// Nil for a page the reply already links, so a source the model wrote itself is not repeated.
    mutating func link(to string: String) -> String? {
        guard let url = URL(string: string), url.scheme == "https" || url.scheme == "http",
            !text.contains(string), linked.insert(string).inserted
        else { return nil }
        let target = string.replacing("(", with: "%28").replacing(")", with: "%29")
        let host = url.host() ?? url.absoluteString
        let label = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return " ([\(label)](\(target)))"
    }
}

struct AIStreamDecoder: Sendable {
    private let shape: AIHTTPConfiguration.APIShape
    /// What a provider's own error text must never show; the decoder is handed it, never reads it.
    private let secrets: [String]
    private var parser = SSEParser()
    private var thinkTags = AIThinkTagDecoder()
    private var responses: AIResponsesDecoder
    private var citations = AICitationLinker()
    private var citedURLs: [Int: [String]] = [:]
    private(set) var isTerminal = false

    init(shape: AIHTTPConfiguration.APIShape, secrets: [String] = []) {
        self.shape = shape
        self.secrets = secrets
        responses = AIResponsesDecoder(secrets: secrets)
    }

    mutating func feed(_ data: Data) throws -> [AIStreamEvent] {
        try decode(parser.feed(data))
    }

    mutating func finish() throws -> [AIStreamEvent] {
        var events = try decode(parser.finish())
        if shape == .openAICompatible, !isTerminal { events += thinkTags.finish() }
        return events
    }

    private mutating func decode(_ payloads: [String]) throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for payload in payloads where !isTerminal {
            if payload == "[DONE]", shape != .openAIResponses {
                isTerminal = true
                if shape == .openAICompatible { events += thinkTags.finish() }
                continue
            }
            switch shape {
            case .openAIResponses:
                do {
                    events.append(contentsOf: try responses.decode(payload))
                    isTerminal = responses.isTerminal
                } catch {
                    isTerminal = true
                    throw error
                }
            case .openAICompatible:
                events.append(contentsOf: try decodeOpenAI(payload))
            case .anthropic:
                events.append(contentsOf: try decodeAnthropic(payload))
            }
        }
        return events
    }

    private mutating func decodeOpenAI(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let chunk = try? JSONDecoder().decode(OpenAIChunk.self, from: data)
        else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        // OpenRouter reports a mid-stream failure as a 200 payload, so it's an event, not a status.
        if chunk.error?.message != nil {
            isTerminal = true
            throw AIProviderError.responseFailed(
                AIProviderFailure.providerMessage(in: data)
                    .map { AIProviderFailure.kept($0, secrets: secrets) } ?? AIProviderFailure.stopped)
        }
        var events: [AIStreamEvent] = []
        if let choice = chunk.choices?.first {
            if let content = choice.delta?.content, !content.isEmpty {
                events += thinkTags.feed(content)
            }
        }
        return events
    }

    private mutating func decodeAnthropic(_ payload: String) throws -> [AIStreamEvent] {
        guard let data = payload.data(using: .utf8),
            let event = try? JSONDecoder().decode(AnthropicEvent.self, from: data)
        else {
            isTerminal = true
            throw AIProviderError.malformedResponse
        }

        let index = event.index ?? 0
        switch event.type {
        case "content_block_delta":
            if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                citations.record(text)
                return [.text(text)]
            }
            if event.delta?.type == "citations_delta", let url = event.delta?.citation?.url {
                citedURLs[index, default: []].append(url)
                return []
            }
            return []
        case "content_block_stop":
            let links = (citedURLs.removeValue(forKey: index) ?? []).compactMap {
                citations.link(to: $0)
            }
            return links.isEmpty ? [] : [.text(links.joined())]
        case "message_stop":
            isTerminal = true
            return []
        case "error":
            isTerminal = true
            throw AIProviderError.responseFailed(
                AIProviderFailure.described(
                    Self.anthropicErrorMessage(event.error?.type), said: event.error?.message,
                    secrets: secrets))
        default:
            return []
        }
    }

    private static func anthropicErrorMessage(_ type: String?) -> String {
        switch type {
        case "authentication_error": return String(localized: "API key rejected — check it in Settings.")
        case "rate_limit_error": return String(localized: "Rate limit reached — try again later.")
        default: return AIProviderFailure.stopped
        }
    }
}

private struct OpenAIChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta?
    }

    struct ErrorBody: Decodable { let message: String? }

    let choices: [Choice]?
    let error: ErrorBody?
}

private struct AnthropicEvent: Decodable {
    struct Delta: Decodable {
        struct Citation: Decodable { let url: String? }

        let type: String?
        let text: String?
        let citation: Citation?
    }

    struct ErrorBody: Decodable {
        let type: String?
        let message: String?
    }

    let type: String
    let index: Int?
    let delta: Delta?
    let error: ErrorBody?
}
