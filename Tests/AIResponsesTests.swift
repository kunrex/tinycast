import Foundation

@main
@MainActor
struct AIResponsesTests {
    static var passes = 0
    static var failures = 0

    static let configuration = AIHTTPConfiguration(
        provider: .openAI, baseURL: URL(string: "https://api.openai.com/v1")!,
        model: "gpt-6.1-terra")

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() async throws {
        endpointsStayWithinTheirProvider()
        requestBodiesKeepInstructionsAndText()
        try streamsKeepTextReasoningAndUsage()
        try searchesAndCitationsStream()
        try failuresTerminateAndRedactSecrets()
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func endpointsStayWithinTheirProvider() {
        for path in ["/v1", "/v1/", "/v1/chat/completions", "/v1/responses", "/v1/responses/"] {
            let url = URL(string: "https://api.openai.com" + path)!
            let native = AIHTTPConfiguration(provider: .openAI, baseURL: url, model: "any-model")
            expect(native.shape == .openAIResponses, "direct OpenAI uses Responses at \(path)")
            expect(
                native.endpointURL.path == "/v1/responses",
                "a saved base or full endpoint resolves Responses once at \(path)")
            expect(
                !AIConnection(provider: .openAI, baseURL: url.absoluteString).takesThinkingField,
                "an official endpoint never receives a gateway's thinking control")
        }
        for (provider, url) in [
            (AIProviderKind.openAI, "https://gateway.example/v1"),
            (.openAI, "https://api.openai.com.example/v1"),
            (.openAICompatible, "https://api.openai.com/v1"),
            (.gemini, AIProviderKind.gemini.defaultBaseURL),
            (.openRouter, AIProviderKind.openRouter.defaultBaseURL)
        ] {
            let compatible = AIHTTPConfiguration(
                provider: provider, baseURL: URL(string: url)!, model: "gpt-6.1-terra")
            expect(compatible.shape == .openAICompatible, "\(url) keeps its compatible wire format")
            expect(
                compatible.endpointURL.path.hasSuffix("/chat/completions"),
                "a model name never migrates another provider's endpoint")
        }
        let query = try? AIModelDiscovery.query(
            provider: .openAI, baseURL: configuration.endpointURL, apiKey: "", appTitle: "Tests")
        expect(query?.request.url?.path == "/v1/models", "a full Responses URL still discovers models")
    }

    static func requestBodiesKeepInstructionsAndText() {
        let body = AIRequestBody.make(
            AIRequest(instructions: "Answer briefly", prompt: "read"), configuration: configuration)
        expect(body["store"] as? Bool == false, "Responses state is never stored server-side")
        expect(body["stream"] as? Bool == true, "Responses streams through the existing transport")
        expect(body["instructions"] as? String == "Answer briefly", "instructions remain top-level")
        expect(body["messages"] == nil, "Responses never receives Chat Completions messages")
        expect(
            body["reasoning_effort"] == nil && body["reasoning"] == nil,
            "the migration preserves the model's default reasoning")
        let input = body["input"] as? [[String: Any]] ?? []
        expect(input.count == 1, "one input, without conversation history")
        expect(input.first?["role"] as? String == "user", "the prompt is a user turn")
        expect(input.first?["content"] as? String == "read", "the prompt stays plain text")
        expect(body["tools"] == nil, "Quick Action requests never advertise function tools")
        let plain = AIRequestBody.make(AIRequest(prompt: "hi"), configuration: configuration)
        expect(plain["instructions"] == nil && plain["tools"] == nil, "optional fields stay absent")
    }

    static func searchesAndCitationsStream() throws {
        let cited = "https://example.com/report"
        let linked = "https://news.example/story"
        let frames =
            try frame(["type": "response.output_item.added", "item": ["type": "web_search_call"]])
            + frame([
                "type": "response.output_item.done",
                "item": ["type": "web_search_call", "action": ["type": "search", "queries": ["rates"]]]
            ])
            + frame(["type": "response.output_text.delta", "delta": "Rates rose ([news](\(linked)))."])
            + frame([
                "type": "response.output_text.annotation.added",
                "annotation": ["type": "url_citation", "url": linked, "title": "News"]
            ])
            + frame([
                "type": "response.output_text.annotation.added",
                "annotation": ["type": "url_citation", "url": cited, "title": "Report"]
            ])
            + completed([])
        var decoder = AIStreamDecoder(shape: .openAIResponses)
        let events = try feed(frames, slice: 9, decoder: &decoder)
        expect(
            events == [
                .text("Rates rose ([news](\(linked)))."), .text(" ([example.com](\(cited)))")
            ],
            "a search reports its query and only a source the text lacks is linked")
    }

    static func streamsKeepTextReasoningAndUsage() throws {
        let output: [[String: Any]] = [[
            "type": "function_call", "call_id": "ignored", "name": "read", "arguments": "{}"
        ]]
        let frames =
            try frame(["type": "response.output_item.added", "item": ["type": "reasoning"]])
            + frame(["type": "response.output_text.delta", "delta": "Checking…"])
            + frame(["type": "response.function_call_arguments.delta", "delta": "{\"pa"])
        let complete = try completed(
            output,
            usage: [
                "input_tokens": 12, "output_tokens": 8,
                "input_tokens_details": ["cached_tokens": 4],
                "output_tokens_details": ["reasoning_tokens": 5]
            ])
        for slice in [1, 7, frames.count + complete.count] {
            var decoder = AIStreamDecoder(shape: .openAIResponses)
            let before = try feed(frames, slice: slice, decoder: &decoder)
            expect(!decoder.isTerminal, "deltas do not complete a response")
            expect(before == [.text("Checking…")], "native reasoning and function deltas are ignored")
            let events = before + (try feed(complete, slice: slice, decoder: &decoder))
            expect(decoder.isTerminal, "response.completed ends the stream")
            expect(events.contains(.text("Checking…")), "answer text streams once")
            expect(
                events.filter {
                    if case .text = $0 { return true }; return false
                }.count == 1,
                "the completed output does not repeat streamed text")
            expect(events == [.text("Checking…")], "usage at completion emits nothing")
            let repeated = try decoder.feed(complete)
            expect(repeated.isEmpty, "a repeated terminal event cannot repeat a call")
        }
        var refusal = AIStreamDecoder(shape: .openAIResponses)
        let refused = try refusal.feed(frame(["type": "response.refusal.delta", "delta": "Cannot help"]))
        expect(
            refused == [.text("Cannot help")], "refusals remain visible answer text")
    }

    static func failuresTerminateAndRedactSecrets() throws {
        for type in ["response.failed", "response.incomplete", "error"] {
            var decoder = AIStreamDecoder(shape: .openAIResponses, secrets: ["fixture-secret"])
            let failure: [String: Any] =
                type == "error"
                ? ["type": type, "message": "Failed with fixture-secret"]
                : [
                    "type": type,
                    "response": [
                        "error": ["message": "Failed with fixture-secret"],
                        "output": []
                    ]
                ]
            do {
                _ = try decoder.feed(frame(failure))
                expect(false, "\(type) must throw")
            } catch {
                expect(decoder.isTerminal, "\(type) terminates the decoder")
                expect(!error.localizedDescription.contains("fixture-secret"), "errors redact credentials")
                expect(error.localizedDescription.contains("[redacted]"), "the provider error is still shown")
            }
        }
        var incomplete = AIStreamDecoder(shape: .openAIResponses)
        do {
            _ = try incomplete.feed(
                frame([
                    "type": "response.incomplete",
                    "response": ["error": NSNull(), "incomplete_details": ["reason": "max_output_tokens"]]
                ]))
            expect(false, "an output limit is a failed turn")
        } catch {
            expect(error.localizedDescription.contains("max_output_tokens"), "the incomplete reason is shown")
        }
        var closed = AIStreamDecoder(shape: .openAIResponses)
        _ = try closed.feed(frame(["type": "response.output_text.delta", "delta": "partial"]))
        _ = try closed.finish()
        expect(!closed.isTerminal, "EOF never turns a truncated response into success")
        var malformed = AIStreamDecoder(shape: .openAIResponses)
        do {
            _ = try malformed.feed(Data("data: [DONE]\n\n".utf8))
            expect(false, "the Chat Completions terminator is not a Responses completion")
        } catch {
            expect(error as? AIProviderError == .malformedResponse, "invalid Responses data fails clearly")
        }
    }

    static func frame(_ value: [String: Any]) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return Data("data: ".utf8) + json + Data("\n\n".utf8)
    }

    static func completed(_ output: [[String: Any]], usage: [String: Any] = [:]) throws -> Data {
        try frame(["type": "response.completed", "response": ["output": output, "usage": usage]])
    }

    static func feed(_ data: Data, slice: Int, decoder: inout AIStreamDecoder) throws -> [AIStreamEvent] {
        var events: [AIStreamEvent] = []
        for offset in stride(from: 0, to: data.count, by: slice) {
            events += try decoder.feed(data.subdata(in: offset..<min(offset + slice, data.count)))
        }
        return events
    }
}
