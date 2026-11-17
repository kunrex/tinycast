import Foundation

/// The JSON body each route expects. Pure on purpose: a wrong shape is a mid-conversation 400.
enum AIRequestBody {
    static func make(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        switch configuration.shape {
        case .openAIResponses: return responses(input, configuration: configuration)
        case .openAICompatible: return openAI(input, configuration: configuration)
        case .anthropic: return anthropic(input, configuration: configuration)
        }
    }

    private static func responses(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "input": input.messages.flatMap(responseMessages),
            "stream": true,
            "store": false
        ]
        if let instructions = input.instructions?.nonEmpty { body["instructions"] = instructions }
        if let effort = configuration.requestedEffort { body["reasoning"] = ["effort": effort] }
        if input.webSearch { body["tools"] = [["type": "web_search"]] }
        return body
    }

    private static func responseMessages(_ message: AIMessage) -> [[String: Any]] {
        var items: [[String: Any]] = []
        if !message.images.isEmpty || !message.documents.isEmpty {
            var parts: [[String: Any]] = []
            if let text = message.text.nonEmpty { parts.append(["type": "input_text", "text": text]) }
            parts += message.images.map { ["type": "input_image", "image_url": $0.dataURL] }
            parts += message.documents.map {
                ["type": "input_file", "filename": $0.name, "file_data": $0.dataURL]
            }
            items.append(["role": message.role.rawValue, "content": parts])
        } else if let text = message.text.nonEmpty {
            items.append(["role": message.role.rawValue, "content": text])
        }
        return items
    }

    private static func openAI(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        var messages = input.messages.compactMap(openAIMessage)
        if let instructions = input.instructions?.nonEmpty {
            messages.insert(["role": "system", "content": instructions], at: 0)
        }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "stream": true
        ]
        // OpenRouter's own search layer, so it works for every model it routes.
        if input.webSearch, configuration.provider == .openRouter {
            body["plugins"] = [["id": "web"]]
        }
        if let effort = configuration.requestedEffort {
            if configuration.provider == .openRouter {
                body["reasoning"] = ["effort": effort]
            } else if !configuration.disablesThinking {
                body["reasoning_effort"] = effort
            }
        }
        if configuration.disablesThinking {
            body["thinking"] = ["type": "disabled"]
        }
        return body
    }

    /// The basic version: later ones filter through code execution, which not every model runs.
    private static var anthropicWebSearch: [String: Any] {
        ["type": "web_search_20250305", "name": "web_search", "max_uses": 5]
    }

    private static func anthropic(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        let systemParts =
            ([input.instructions]
            + input.messages.compactMap { $0.role == .system ? $0.text : nil })
            .compactMap { $0?.nonEmpty }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": input.messages.compactMap(anthropicMessage),
            "max_tokens": configuration.maxOutputTokens ?? input.maxOutputTokens,
            "stream": true
        ]
        if !systemParts.isEmpty { body["system"] = systemParts.joined(separator: "\n\n") }
        if let effort = configuration.requestedEffort { body["output_config"] = ["effort": effort] }
        if input.webSearch { body["tools"] = [anthropicWebSearch] }
        return body
    }

    /// Plain text stays a string; only a message with images takes the content-part array.
    private static func openAIMessage(_ message: AIMessage) -> [String: Any]? {
        let text = message.text.nonEmpty
        let hasAttachments = !message.images.isEmpty || !message.documents.isEmpty
        guard text != nil || hasAttachments else { return nil }
        guard hasAttachments else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = []
        if let text { parts.append(["type": "text", "text": text]) }
        parts += message.images.map { ["type": "image_url", "image_url": ["url": $0.dataURL]] }
        parts += message.documents.map {
            ["type": "file", "file": ["filename": $0.name, "file_data": $0.dataURL]]
        }
        return ["role": message.role.rawValue, "content": parts]
    }

    private static func anthropicMessage(_ message: AIMessage) -> [String: Any]? {
        guard message.role != .system else { return nil }
        let text = message.text.nonEmpty
        let hasAttachments = !message.images.isEmpty || !message.documents.isEmpty
        guard text != nil || hasAttachments else { return nil }
        guard hasAttachments else {
            return ["role": message.role.rawValue, "content": text ?? ""]
        }
        var parts: [[String: Any]] = message.images.map {
            [
                "type": "image",
                "source": [
                    "type": "base64", "media_type": $0.mimeType,
                    "data": $0.data.base64EncodedString()
                ]
            ]
        }
        parts += message.documents.map {
            [
                "type": "document",
                "source": [
                    "type": "base64", "media_type": $0.mimeType,
                    "data": $0.data.base64EncodedString()
                ]
            ]
        }
        // Text stays last: a document block has to precede the instruction that refers to it.
        if let text { parts.append(["type": "text", "text": text]) }
        return ["role": message.role.rawValue, "content": parts]
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
