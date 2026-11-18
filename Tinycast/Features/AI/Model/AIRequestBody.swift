import Foundation

/// The text-only JSON body each route expects.
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
            "input": [["role": "user", "content": input.prompt.trimmingCharacters(in: .whitespacesAndNewlines)]],
            "stream": true,
            "store": false
        ]
        if let instructions = input.instructions?.nonEmpty { body["instructions"] = instructions }
        if let effort = configuration.requestedEffort { body["reasoning"] = ["effort": effort] }
        return body
    }

    private static func openAI(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        var messages = [["role": "user", "content": input.prompt.trimmingCharacters(in: .whitespacesAndNewlines)]]
        if let instructions = input.instructions?.nonEmpty {
            messages.insert(["role": "system", "content": instructions], at: 0)
        }
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "stream": true
        ]
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

    private static func anthropic(
        _ input: AIRequest, configuration: AIHTTPConfiguration
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "user", "content": input.prompt.trimmingCharacters(in: .whitespacesAndNewlines)]],
            "max_tokens": configuration.maxOutputTokens ?? input.maxOutputTokens,
            "stream": true
        ]
        if let instructions = input.instructions?.nonEmpty { body["system"] = instructions }
        if let effort = configuration.requestedEffort { body["output_config"] = ["effort": effort] }
        return body
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
