import Foundation

@main
@MainActor
struct AIProviderTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func requestBodiesCarryOneTextPrompt() {
        for provider in AIProviderKind.allCases {
            let configuration = AIHTTPConfiguration(
                provider: provider, baseURL: URL(string: provider.defaultBaseURL)!, model: "m")
            let body = AIRequestBody.make(
                AIRequest(instructions: "Be brief", prompt: "summarise"), configuration: configuration)
            let key = configuration.shape == .openAIResponses ? "input" : "messages"
            let messages = body[key] as? [[String: String]] ?? []
            expect(messages.last == ["role": "user", "content": "summarise"], "one text user prompt")
            expect(messages.count == (configuration.shape == .openAICompatible ? 2 : 1), "no history")
            expect(body["tools"] == nil && body["plugins"] == nil, "no outbound search or tools")
            if configuration.shape == .anthropic {
                expect(body["system"] as? String == "Be brief", "Anthropic retains instructions")
                expect(body["max_tokens"] as? Int == AIRequest.defaultMaxOutputTokens, "output budget")
            }
        }
    }

    static func main() async throws {
        providerPresetsResolveEndpoints()
        modelCatalogBuildsProviderRequests()
        requestHeadersAreValidated()
        modelCatalogDecodesProviderResponses()
        modelCatalogSearchesWithoutRenderingEverything()
        exactMatchNamesOnlyAWholeModel()
        endpointPolicyRejectsUnsafeRemoteURLs()
        storedKeysDoNotFollowARetargetedConnection()
        savingAConnectionDecidesItsKey()
        sseFramesSurviveSplits()
        openAIAndAnthropicStreamsDecode()
        capturedStreamsDecodeHoweverTheyArrive()
        thinkTagStreamsDecodeHoweverTheyArrive()
        brokenStreamsFailLoudly()
        refusalsShowTheProvidersOwnWords()
        brandsResolveFromModelIDs()
        requestBodiesCarryOneTextPrompt()
        settingsPersistAndRepairSelections()
        shownModelsFilterThePicker()
        switchedOffRoutesLeaveTheDefault()
        onDeviceSelectionsRoundTripAndLead()
        anthropicSearchesAndCitationsDecode()
        aGatewayOffersNoneAsItsReasoningEffort()
        declaredLevelsNeverOutliveTheirDestination()
        vendorsTakeTheirOwnDeclaredLevels()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func anthropicSearchesAndCitationsDecode() {
        let cite = #"{"type":"citations_delta","citation":{"url":"https://swift.org/a_(b)"}}"#
        let payloads = [
            #"{"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","name":"web_search"}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\":\"swift "}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"6\"}"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","content":[]}}"#,
            #"{"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}"#,
            #"{"type":"content_block_delta","index":2,"delta":"# + cite + "}",
            #"{"type":"content_block_delta","index":2,"delta":"# + cite + "}",
            #"{"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Swift 6 shipped."}}"#,
            #"{"type":"content_block_stop","index":2}"#,
            #"{"type":"message_stop"}"#
        ]
        var decoder = AIStreamDecoder(shape: .anthropic)
        let stream = Data(payloads.map { "data: \($0)\n\n" }.joined().utf8)
        let events = (try? decoder.feed(stream)) ?? []
        let link = " ([swift.org](https://swift.org/a_%28b%29))"
        expect(
            events == [
                .text("Swift 6 shipped."), .text(link)
            ],
            "server search frames are ignored, and a block's sources follow it once")
        expect(decoder.isTerminal, "ignored tool frames still reach Anthropic message_stop")
        var linker = AICitationLinker()
        expect(
            link == linker.link(to: "https://swift.org/a_(b)"),
            "HTTP citation normalization escapes parentheses in the target")
        expect(linker.link(to: "https://swift.org/a_(b)") == nil, "citations are deduplicated")
        for url in ["file:///tmp/private", "javascript:alert(1)", "tinycast://search", "mailto:a@b.com"] {
            expect(linker.link(to: url) == nil, "citation links reject non-web schemes")
        }
        linker.record("Already linked https://example.com/report")
        expect(linker.link(to: "https://example.com/report") == nil, "text links are not repeated")
    }

    static func aGatewayOffersNoneAsItsReasoningEffort() {
        let gateway = AIConnection(
            provider: .openAI, baseURL: "https://gateway.example/v1", models: ["m"])
        expect(
            gateway.reasoningOptions(for: "m")?.efforts == ["default", "none"],
            "a preset pointed away from its own API offers the one effort a gateway can honour")
        expect(
            gateway.reasoningOptions(for: "m")?.resolvedEffort(nil) == "default",
            "and reasoning stays on until the reader picks None")
        expect(
            AIConnection(provider: .openAI, models: ["m"]).reasoningOptions(for: "m") == nil,
            "a preset on its own API offers none, because a vendor rejects what it does not define")
        expect(
            AIConnection(provider: .anthropic, baseURL: "https://gateway.example", models: ["m"])
                .reasoningOptions(for: "m") == nil,
            "the Anthropic shape never takes the gateway's thinking switch")

        let catalogued = AIConnection(
            id: UUID(), provider: .openRouter, baseURL: "https://gateway.example", models: ["m"],
            reasoningOptions: ["m": .init(efforts: ["high", "low"], defaultEffort: "high")])
        expect(
            catalogued.reasoningOptions(for: "m")?.efforts == ["high", "low"],
            "a published catalog always wins over the synthesized switch")

        let turn = AIRequest(prompt: "hi")
        let url = URL(string: "https://gateway.example/v1")!
        let on = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(provider: .openAI, baseURL: url, model: "m"))
        expect(on["thinking"] == nil, "reasoning left alone sends no key at all")

        let off = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: url, model: "m", effort: "none",
                disablesThinking: true))
        expect(
            (off["thinking"] as? [String: String])?["type"] == "disabled",
            "None asks the endpoint to answer directly")
        expect(off["reasoning_effort"] == nil, "None sends no effort field beside it")

        var declared = AIConnection(
            provider: .openAI, baseURL: "https://gateway.example/v1", models: ["m"])
        declared.declareLevels(["high", "low", "bogus"], for: "m")
        expect(
            declared.reasoningOptions(for: "m")?.efforts == ["default", "low", "high", "none"],
            "declared levels sit in ladder order between Default and None, and strangers drop")
        expect(
            declared.reasoningOptions(for: "m")?.resolvedEffort(nil) == "default",
            "a declaration leaves reasoning alone until the reader picks a level")
        expect(declared.declaredLevels(for: "m") == ["low", "high"], "the declaration reads back")
        declared.declareLevels([], for: "m")
        expect(
            declared.reasoningOptions(for: "m")?.efforts == ["default", "none"],
            "clearing it returns to the Default/None pair")

        let level = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: url, model: "m", effort: "low"))
        expect(
            level["reasoning_effort"] as? String == "low",
            "a declared level goes out as OpenAI's own reasoning_effort")
        expect(level["reasoning"] == nil, "and not as OpenRouter's reasoning object")
        let unset = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .openAI, baseURL: url, model: "m", effort: "default"))
        expect(unset["reasoning_effort"] == nil, "Default still sends no field")
    }

    static func declaredLevelsNeverOutliveTheirDestination() {
        var gateway = AIConnection(
            provider: .openAI, baseURL: "https://gateway.example/v1", models: ["m"])
        gateway.declareLevels(["low", "high"], for: "m")
        expect(gateway.offeredEffort("high", for: "m") == "high", "a declared level is sent")
        expect(gateway.offeredEffort(nil, for: "m") == nil, "no saved effort sends none")

        gateway.declareLevels(["low"], for: "m")
        expect(
            gateway.offeredEffort("high", for: "m") == nil,
            "a chat still holding an unticked level stops sending it")

        var vendor = gateway
        vendor.baseURL = AIProviderKind.openAI.defaultBaseURL
        vendor.dropDeclaredLevels()
        expect(
            vendor.reasoningOptions(for: "m") == nil,
            "levels declared for a gateway are not offered once the URL is the vendor's own")
        expect(vendor.offeredEffort("low", for: "m") == nil, "nor sent to the vendor")

        let openRouter = AIConnection(
            id: UUID(), provider: .openRouter, models: ["m"],
            reasoningOptions: ["m": .init(efforts: ["high", "low"], defaultEffort: "high")])
        expect(
            openRouter.offeredEffort("high", for: "m") == "high",
            "OpenRouter's own catalog still reaches its default URL")
        expect(
            openRouter.offeredEffort("xhigh", for: "m") == nil,
            "a level its catalog dropped is not sent")
        expect(
            AIConnection(provider: .openAI, models: ["m"]).offeredEffort("high", for: "m") == nil,
            "an old OpenRouter effort left on a vendor connection is not sent")

        var retargeted = gateway
        retargeted.dropDeclaredLevels()
        expect(
            retargeted.reasoningOptions == nil,
            "levels declared for one gateway are dropped when the URL moves")
        var movedOpenRouter = openRouter
        movedOpenRouter.dropDeclaredLevels()
        expect(
            movedOpenRouter.reasoningOptions == openRouter.reasoningOptions,
            "OpenRouter's catalog is no declaration, so a moved URL keeps it")

        expect(gateway.takesDeclaredLevels, "a gateway takes declared levels")
        expect(vendor.takesDeclaredLevels, "and so does a vendor's own URL")
        expect(
            !AIConnection(provider: .openRouter, baseURL: "https://proxy.example/v1")
                .takesDeclaredLevels,
            "OpenRouter at any URL does not, because its catalog names the levels")
    }

    static func vendorsTakeTheirOwnDeclaredLevels() {
        var openAI = AIConnection(provider: .openAI, models: ["m"])
        openAI.declareLevels(["max", "none", "low", "xhigh", "bogus"], for: "m")
        expect(
            openAI.reasoningOptions(for: "m")?.efforts == ["default", "low", "xhigh", "max", "none"],
            "OpenAI takes its whole ladder, with None only once declared")
        var anthropic = AIConnection(provider: .anthropic, models: ["m"])
        anthropic.declareLevels(["minimal", "none", "low", "max"], for: "m")
        expect(
            anthropic.reasoningOptions(for: "m")?.efforts == ["default", "low", "max"],
            "Anthropic has no minimal effort and no None")
        var gemini = AIConnection(provider: .gemini, models: ["m"])
        gemini.declareLevels(["xhigh", "high", "none"], for: "m")
        expect(
            gemini.reasoningOptions(for: "m")?.efforts == ["default", "high", "none"],
            "Gemini stops at high and may declare None")
        expect(gemini.offeredEffort("none", for: "m") == "none", "a declared None is sent")

        let turn = AIRequest(prompt: "hi")
        func body(_ provider: AIProviderKind, effort: String?) -> [String: Any] {
            AIRequestBody.make(
                turn,
                configuration: AIHTTPConfiguration(
                    provider: provider, baseURL: URL(string: provider.defaultBaseURL)!,
                    model: "m", effort: effort))
        }
        expect(
            (body(.openAI, effort: "high")["reasoning"] as? [String: String])?["effort"] == "high",
            "Responses carries the effort in its reasoning object")
        expect(
            (body(.anthropic, effort: "max")["output_config"] as? [String: String])?["effort"]
                == "max",
            "Anthropic carries it in output_config")
        let geminiNone = body(.gemini, effort: "none")
        expect(
            geminiNone["reasoning_effort"] as? String == "none" && geminiNone["thinking"] == nil,
            "a vendor's None is its own reasoning_effort, never the gateway switch")
        expect(
            body(.openAI, effort: "default")["reasoning"] == nil
                && body(.anthropic, effort: "default")["output_config"] == nil
                && body(.gemini, effort: "default")["reasoning_effort"] == nil,
            "Default sends no field on any vendor")

        let catalog = Data(
            """
            {"data":[
                {"id":"claude-a","display_name":"Claude A","max_tokens":128000,"capabilities":{
                    "effort":{"supported":true,"max":{"supported":true},
                              "low":{"supported":true},"xhigh":{"supported":false}}}},
                {"id":"claude-b","capabilities":{"effort":{"supported":false}}}
            ]}
            """.utf8)
        let models = try? AIModelDiscovery.decode(catalog, shape: .openAI)
        expect(
            models?.first?.reasoningOptions?.efforts == ["low", "max"],
            "Anthropic's catalog names each model's supported efforts in ladder order")
        expect(
            models?.last?.reasoningOptions?.efforts == [],
            "a model without effort support names none")
        expect(
            models?.map(\.maxOutputTokens) == [128_000, nil],
            "and each model's output ceiling where it states one")

        var saved = AIConnection(provider: .anthropic, models: ["claude-a", "claude-b", "claude-c"])
        saved.declareLevels(["high"], for: "claude-c")
        saved.adoptCatalog(
            (models ?? [])
                + [
                    .init(
                        id: "claude-c", name: "C",
                        reasoningOptions: .init(efforts: ["low"], defaultEffort: nil))
                ])
        expect(
            saved.declaredLevels(for: "claude-a") == ["low", "max"],
            "a model saved before its catalog was read takes the catalog's levels")
        expect(saved.reasoningOptions?["claude-b"] == nil, "a model with no effort support takes none")
        expect(saved.declaredLevels(for: "claude-c") == ["high"], "a reader's own declaration stays")
        expect(saved.outputLimits == ["claude-a": 128_000], "only a stated ceiling is stored")

        let url = URL(string: AIProviderKind.anthropic.defaultBaseURL)!
        let known = AIRequestBody.make(
            turn,
            configuration: AIHTTPConfiguration(
                provider: .anthropic, baseURL: url, model: "claude-a", maxOutputTokens: 128_000))
        expect(known["max_tokens"] as? Int == 128_000, "a known model may answer up to its ceiling")
        let unknown = AIRequestBody.make(
            turn, configuration: AIHTTPConfiguration(provider: .anthropic, baseURL: url, model: "x"))
        expect(
            unknown["max_tokens"] as? Int == AIRequest.defaultMaxOutputTokens,
            "an unknown one keeps the cap every Claude model accepts")
    }

    static func providerPresetsResolveEndpoints() {
        let expected: [(AIProviderKind, String)] = [
            (.openAI, "https://api.openai.com/v1/responses"),
            (.anthropic, "https://api.anthropic.com/v1/messages"),
            (.gemini, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"),
            (.openRouter, "https://openrouter.ai/api/v1/chat/completions"),
            (.openAICompatible, "https://api.openai.com/v1/chat/completions")
        ]
        for (provider, endpoint) in expected {
            let configuration = AIHTTPConfiguration(
                provider: provider,
                baseURL: URL(string: provider.defaultBaseURL)!,
                model: "model")
            expect(
                configuration.endpointURL.absoluteString == endpoint,
                "\(provider.title) resolves its documented streaming endpoint")
        }
        let explicit = AIHTTPConfiguration(
            provider: .openAICompatible,
            baseURL: URL(string: "https://example.com/chat/completions")!,
            model: "model")
        expect(
            explicit.endpointURL.absoluteString == "https://example.com/chat/completions",
            "an explicit completion endpoint is not appended twice")
    }

    static func modelCatalogBuildsProviderRequests() {
        let expected: [(AIProviderKind, String)] = [
            (.openAI, "https://api.openai.com/v1/models"),
            (.anthropic, "https://api.anthropic.com/v1/models?limit=1000"),
            (.gemini, "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"),
            (.openRouter, "https://openrouter.ai/api/v1/models/user"),
            (.openAICompatible, "https://api.openai.com/v1/models")
        ]
        for (provider, endpoint) in expected {
            let query = try? AIModelDiscovery.query(
                provider: provider, baseURL: URL(string: provider.defaultBaseURL)!,
                apiKey: "secret", appTitle: "Tinycast")
            expect(
                query?.request.url?.absoluteString == endpoint,
                "\(provider.title) resolves its model catalog endpoint")
        }

        let anthropic = try? AIModelDiscovery.query(
            provider: .anthropic, baseURL: URL(string: "https://api.anthropic.com")!,
            apiKey: "secret", appTitle: "Tinycast"
        ).request
        expect(
            anthropic?.value(forHTTPHeaderField: "x-api-key") == "secret",
            "Anthropic model discovery uses x-api-key authentication")
        let gemini = try? AIModelDiscovery.query(
            provider: .gemini, baseURL: URL(string: AIProviderKind.gemini.defaultBaseURL)!,
            apiKey: "secret", appTitle: "Tinycast"
        ).request
        expect(
            gemini?.value(forHTTPHeaderField: "x-goog-api-key") == "secret",
            "Gemini model discovery uses native API-key authentication")
        let openAI = try? AIModelDiscovery.query(
            provider: .openAI, baseURL: URL(string: AIProviderKind.openAI.defaultBaseURL)!,
            apiKey: "secret", appTitle: "Tinycast"
        ).request
        expect(
            openAI?.value(forHTTPHeaderField: "Authorization") == "Bearer secret",
            "OpenAI-compatible discovery uses bearer authentication")
        let local = try? AIModelDiscovery.query(
            provider: .openAICompatible, baseURL: URL(string: "http://localhost:11434/")!,
            apiKey: "", appTitle: "Tinycast"
        ).request
        expect(
            local?.url?.absoluteString == "http://localhost:11434/models",
            "a root endpoint appends one model path separator")
        let headerOnly = try? AIModelDiscovery.query(
            provider: .anthropic, baseURL: URL(string: "https://gateway.example.com")!,
            apiKey: "", appTitle: "Tinycast",
            headers: ["anthropic-version": "2024-01-01", "X-Tenant": "acme"]
        ).request
        expect(
            headerOnly?.value(forHTTPHeaderField: "x-api-key") == nil,
            "an empty key sends no credential header")
        expect(
            headerOnly?.value(forHTTPHeaderField: "Anthropic-Version") == "2024-01-01"
                && headerOnly?.value(forHTTPHeaderField: "x-tenant") == "acme",
            "custom headers are sent and replace a default of the same name in any case")
    }

    static func requestHeadersAreValidated() {
        typealias Headers = AIRequestHeaders
        expect(
            (try? Headers.validated([
                (" X-Tenant ", " acme\n"), ("", " "), ("Authorization", "Bearer\ttoken")
            ])) == ["X-Tenant": "acme", "Authorization": "Bearer\ttoken"],
            "names and values are trimmed, a blank row is dropped and a tab is kept")
        expect(
            (try? Headers.validated([("", "value")])) == nil
                && (try? Headers.validated([("X Tenant", "acme")])) == nil,
            "a missing name or one outside the HTTP token set is refused")
        expect(
            (try? Headers.validated([("X-Tenant", "a"), ("x-tenant", "b")])) == nil,
            "a name repeated in another case is refused")
        expect(
            (try? Headers.validated([("X-Tenant", "a\r\nX-Injected: b")])) == nil,
            "a value cannot carry a line break into another header")
    }

    static func modelCatalogDecodesProviderResponses() {
        let openAI = Data(
            """
            {"data":[
                {"id":"model-a"},
                {"id":"model-b","name":"Model B",
                 "architecture":{"input_modalities":["text","image"]},
                 "reasoning":{"supported_efforts":["high","medium","low"],
                              "default_effort":"medium"}},
                {"id":"model-a"}
            ]}
            """.utf8)
        let openAIModels = try? AIModelDiscovery.decode(openAI, shape: .openAI)
        expect(
            openAIModels == [
                .init(id: "model-a", name: "model-a"),
                .init(
                    id: "model-b", name: "Model B", inputModalities: ["text", "image"],
                    reasoningOptions: .init(
                        efforts: ["high", "medium", "low"], defaultEffort: "medium"))
            ],
            "OpenAI-compatible model lists are named and deduplicated")
        expect(
            openAIModels?.map(\.acceptsImages) == [nil, true],
            "only a catalog that lists modalities says whether a model takes images")
        expect(
            openAIModels?.last?.reasoningOptions?.resolvedEffort(nil) == "medium",
            "OpenRouter reasoning metadata keeps the model's advertised default")

        let gateway = Data(
            """
            {"data":[
                {"id":"model-c","name":"Model C","reasoning":true,
                 "architecture":{"input_modalities":["text","image"]}},
                {"id":"model-d","reasoning":"high"},
                {"id":"model-e","reasoning":{"supported_efforts":["low"],"default_effort":"low"}}
            ]}
            """.utf8)
        let gatewayModels = try? AIModelDiscovery.decode(gateway, shape: .openAI)
        expect(
            gatewayModels == [
                .init(id: "model-c", name: "Model C", inputModalities: ["text", "image"]),
                .init(id: "model-d", name: "model-d"),
                .init(
                    id: "model-e", name: "model-e",
                    reasoningOptions: .init(efforts: ["low"], defaultEffort: "low"))
            ],
            "a reasoning field that is not an object is ignored, and the catalog still loads")

        let gemini = Data(
            """
            {"models":[
                {"name":"models/gemini-chat","displayName":"Gemini Chat",\
                 "supportedGenerationMethods":["generateContent"]},
                {"name":"models/gemini-embed","displayName":"Gemini Embed",\
                 "supportedGenerationMethods":["embedContent"]}
            ]}
            """.utf8)
        let geminiModels = try? AIModelDiscovery.decode(gemini, shape: .gemini)
        expect(
            geminiModels == [.init(id: "gemini-chat", name: "Gemini Chat")],
            "Gemini discovery keeps generation models and strips the resource prefix")
    }

    static func modelCatalogSearchesWithoutRenderingEverything() {
        let models = [
            AIModelDiscovery.Model(id: "openai/gpt-small", name: "GPT Small"),
            AIModelDiscovery.Model(id: "anthropic/claude", name: "Claude"),
            AIModelDiscovery.Model(id: "openai/gpt-large", name: "GPT Large"),
            AIModelDiscovery.Model(id: "google/gemini", name: "Gemini")
        ]
        expect(
            AIModelDiscovery.search(models, query: "").isEmpty,
            "an empty search never renders the complete provider catalog")
        expect(
            AIModelDiscovery.search(models, query: "openai").map(\.id)
                == ["openai/gpt-small", "openai/gpt-large"],
            "a provider name finds its models in provider order")
        expect(
            AIModelDiscovery.search(models, query: "GPT Large").first?.id
                == "openai/gpt-large",
            "an exact display-name match ranks first")
        expect(
            AIModelDiscovery.search(
                models, query: "gpt", excluding: ["openai/gpt-small"], limit: 1
            ).map(\.id) == ["openai/gpt-large"],
            "search excludes selected models and caps visible results")
    }

    static func exactMatchNamesOnlyAWholeModel() {
        let models = [
            AIModelDiscovery.Model(id: "gpt-5.4-mini", name: "GPT-5.4 Mini"),
            AIModelDiscovery.Model(id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4")
        ]
        expect(
            AIModelDiscovery.exactMatch(models, query: " GPT-5.4-MINI ")?.id == "gpt-5.4-mini",
            "an exact ID matches regardless of case and surrounding spaces")
        expect(
            AIModelDiscovery.exactMatch(models, query: "claude sonnet 4")?.id
                == "claude-sonnet-4-20250514",
            "a display name resolves to its model ID")
        expect(
            AIModelDiscovery.exactMatch(models, query: "gpt-5") == nil,
            "a short ID that a listed ID contains is not an exact match")
        expect(
            AIModelDiscovery.exactMatch(models, query: "  ") == nil,
            "a blank query matches nothing")
        let aliased = [
            AIModelDiscovery.Model(id: "gateway-default", name: "gpt-5"),
            AIModelDiscovery.Model(id: "gpt-5", name: "GPT-5")
        ]
        expect(
            AIModelDiscovery.exactMatch(aliased, query: "gpt-5")?.id == "gpt-5",
            "an exact ID wins over an earlier model whose display name matches")
    }

    static func endpointPolicyRejectsUnsafeRemoteURLs() {
        expect(
            (try? AIEndpointPolicy.validate("https://example.com/v1")) != nil,
            "remote HTTPS endpoints are accepted")
        expect(
            (try? AIEndpointPolicy.validate("http://localhost:11434/v1")) != nil,
            "local HTTP endpoints are accepted")
        expect(
            (try? AIEndpointPolicy.validate("http://127.0.0.1:1234/v1")) != nil,
            "IPv4 loopback endpoints are accepted")
        expect(
            (try? AIEndpointPolicy.validate("http://example.com/v1")) == nil,
            "remote plaintext endpoints are rejected")
        expect(
            (try? AIEndpointPolicy.validate("not a url")) == nil,
            "malformed endpoints are rejected")
        expect(
            (try? AIEndpointPolicy.validate("ftp://localhost/v1")) == nil,
            "a loopback host does not excuse a scheme the transport cannot speak")
        expect(
            (try? AIEndpointPolicy.validate("file:///etc/hosts")) == nil,
            "file URLs are not a provider")
    }

    static func storedKeysDoNotFollowARetargetedConnection() {
        var saved = AIConnection()
        saved.provider = .openAI
        saved.baseURL = "https://api.openai.com/v1"
        expect(
            AIEndpointPolicy.sameDestination(saved, saved),
            "an untouched connection still points where its key was issued")

        var switchedProvider = saved
        switchedProvider.provider = .anthropic
        expect(
            !AIEndpointPolicy.sameDestination(switchedProvider, saved),
            "a new provider is a new destination, so the OpenAI key must not go to Anthropic")

        var switchedURL = saved
        switchedURL.baseURL = "https://gateway.example.com/v1"
        expect(
            !AIEndpointPolicy.sameDestination(switchedURL, saved),
            "a retyped base URL is a new destination, whatever the provider preset still says")

        var renamed = saved
        renamed.name = "Work key"
        renamed.models = ["gpt-5.4-mini"]
        expect(
            AIEndpointPolicy.sameDestination(renamed, saved),
            "editing a label or the model list is not a retarget and keeps the saved key")
    }

    static func savingAConnectionDecidesItsKey() {
        var remote = AIConnection()
        remote.provider = .openAI
        remote.baseURL = "https://api.openai.com/v1"
        var local = remote
        local.baseURL = "http://localhost:11434/v1"
        var moved = remote
        moved.baseURL = "https://gateway.example.com/v1"
        typealias Policy = AIConnectionKeyPolicy

        expect(
            Policy.resolve(
                enteredKey: "  sk-new \n", connection: remote, saved: nil, hasStoredKey: false,
                hasHeaders: false)
                == .store("sk-new"),
            "a typed key is stored trimmed")
        expect(
            Policy.resolve(
                enteredKey: "sk-new", connection: moved, saved: remote, hasStoredKey: true, hasHeaders: false)
                == .store("sk-new"),
            "a retarget that brings its own key replaces the old one")
        expect(
            Policy.resolve(
                enteredKey: " ", connection: moved, saved: remote, hasStoredKey: true, hasHeaders: false)
                == .reject("Enter an API key for this endpoint — the saved key stays with the old one."),
            "a remote retarget without a key is refused, so the old key never reaches the new host")
        expect(
            Policy.resolve(
                enteredKey: "", connection: local, saved: remote, hasStoredKey: true, hasHeaders: false)
                == .removeStored,
            "a retarget to loopback drops the key issued for the remote endpoint")
        expect(
            Policy.resolve(
                enteredKey: "", connection: remote, saved: nil, hasStoredKey: false, hasHeaders: false)
                == .reject("Enter an API key for this remote provider."),
            "a new remote connection needs a key")
        expect(
            Policy.resolve(
                enteredKey: "", connection: local, saved: nil, hasStoredKey: false, hasHeaders: false)
                == .keep,
            "a loopback endpoint saves without a key")
        expect(
            Policy.resolve(
                enteredKey: "", connection: remote, saved: remote, hasStoredKey: true, hasHeaders: false)
                == .keep,
            "an unchanged endpoint keeps its saved key")
        expect(
            Policy.resolve(
                enteredKey: "", connection: moved, saved: remote, hasStoredKey: false, hasHeaders: false)
                == .reject("Enter an API key for this remote provider."),
            "with no saved key there is nothing to retarget, only a missing key")
        expect(
            Policy.resolve(
                enteredKey: "", connection: remote, saved: nil, hasStoredKey: false, hasHeaders: true)
                == .keep,
            "request headers can authenticate a remote endpoint without a key")
        expect(
            Policy.resolve(
                enteredKey: "", connection: moved, saved: remote, hasStoredKey: true, hasHeaders: true)
                == .removeStored,
            "a retarget authenticated by headers drops the old key rather than carry it over")
    }

    static func sseFramesSurviveSplits() {
        var parser = SSEParser()
        expect(parser.feed(Data("data: hel".utf8)).isEmpty, "a partial SSE frame waits")
        expect(
            parser.feed(Data("lo\n\ndata: world\r\n\r\n".utf8)) == ["hello", "world"],
            "split LF and CRLF frames are reassembled")
        expect(
            parser.feed(Data(": keepalive\n\ndata: final".utf8)).isEmpty,
            "comments are ignored and a final unterminated frame waits")
        expect(parser.finish() == ["final"], "finish flushes the final frame")
    }

    static func openAIAndAnthropicStreamsDecode() {
        var openAI = AIStreamDecoder(shape: .openAICompatible)
        let openAIData = Data(
            """
            data: {"choices":[{"delta":{"reasoning":"working"}}]}

            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2}}

            data: [DONE]

            """.utf8)
        var events = (try? openAI.feed(openAIData)) ?? []
        events += (try? openAI.finish()) ?? []
        expect(events == [.text("Hello")], "native reasoning and usage-only frames emit no text")
        expect(openAI.isTerminal, "the OpenAI done marker terminates the stream")

        var anthropic = AIStreamDecoder(shape: .anthropic)
        let anthropicData = Data(
            """
            data: {"type":"message_start","message":{"usage":{"input_tokens":4}}}

            data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Hmm"}}

            data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hi"}}

            data: {"type":"message_delta","usage":{"output_tokens":1}}

            data: {"type":"message_stop"}

            """.utf8)
        var anthropicEvents = (try? anthropic.feed(anthropicData)) ?? []
        anthropicEvents += (try? anthropic.finish()) ?? []
        expect(anthropicEvents == [.text("Hi")], "Anthropic thinking and usage frames emit nothing")
        expect(anthropic.isTerminal, "Anthropic message_stop terminates the stream")
    }

    /// Real OpenRouter captures, with the reasoning ones proving thought never leaks into text.
    static func capturedStreamsDecodeHoweverTheyArrive() {
        let captures: [(file: String, text: String?)] = [
            ("openrouter-plain", "1, 2, 3."),
            ("openrouter-gemma", nil),
            ("openrouter-nemotron-reasoning", nil),
            ("openrouter-cohere-reasoning", nil)
        ]
        for capture in captures {
            guard let data = FileManager.default.contents(atPath: "Tests/ai-fixtures/\(capture.file).txt")
            else {
                expect(false, "\(capture.file) fixture is readable")
                continue
            }
            let whole = decodeAll(data, slice: data.count)
            let sliced = decodeAll(data, slice: 7)
            expect(whole == sliced, "\(capture.file) decodes the same in 7-byte slices")
            let text = whole.compactMap { event -> String? in
                if case .text(let text) = event { return text }
                return nil
            }.joined()
            if let expected = capture.text {
                expect(text == expected, "\(capture.file) yields exactly its answer text")
            } else {
                expect(!text.isEmpty, "\(capture.file) yields answer text")
            }
            expect(!text.contains("<think>"), "\(capture.file) never leaks leading think tags")
        }
    }

    static func thinkTagStreamsDecodeHoweverTheyArrive() {
        guard let data = FileManager.default.contents(atPath: "Tests/ai-fixtures/openai-think-tags.txt")
        else {
            expect(false, "think tags: fixture is readable")
            return
        }
        let whole = decodeAll(data, slice: data.count)
        expect(whole == decodeAll(data, slice: 7), "think tags: fixture survives 7-byte slices")
        expect(answerText(whole) == "The answer.", "think tags: fixture suppresses reasoning")

        let content = Array("<think>reason</think>\n\nanswer")
        for first in 0...content.count {
            for second in first...content.count {
                let fragments = [
                    String(content[..<first]), String(content[first..<second]),
                    String(content[second...])
                ]
                let events = decodeContent(fragments)
                expect(
                    answerText(events) == "answer",
                    "think tags: content splits \(first),\(second) suppress reasoning and keep answer")
            }
        }
        let characters = decodeContent(content.map(String.init))
        expect(
            answerText(characters) == "answer",
            "think tags: one character per delta suppresses reasoning and keeps answer")
        let spaced = decodeContent([" \n", "<think> ", "\n", "reason \n</thi", "nk>\n", "\t", "answer", " \n"]
        )
        expect(
            answerText(spaced) == "answer \n",
            "think tags: reasoning and its separator are removed; answer trailing space stays")
        expect(
            decodeContent(["<think>r</think>answer"])
                == [.text("answer")],
            "think tags: a single delta emits only answer text")
        for literal in [
            "<div>x</div>", "<thinking>…", "\n\nHello", "Hello <think>x</think> world",
            "Hello<think>x</think> world", "</think>answer"
        ] {
            let events = decodeContent(literal.map(String.init))
            expect(
                answerText(events) == literal,
                "think tags: literal content stays verbatim: \(literal.debugDescription)")
        }
        for content in ["<think></think>", "<think> \n\t</think>"] {
            expect(
                decodeContent(content.map(String.init)).isEmpty,
                "think tags: empty or whitespace-only reasoning emits nothing")
        }
        let secondBlock = decodeContent(["<think>r</think>", "answer <think>literal</think> world"])
        expect(
            answerText(secondBlock) == "answer <think>literal</think> world",
            "think tags: recognition never resumes after the first block")
        for done in [true, false] {
            let unclosed = decodeContent(["<think>reason</thi"], done: done)
            expect(
                unclosed.isEmpty,
                "think tags: unclosed reasoning is suppressed at \(done ? "DONE" : "EOF")")
            expect(
                answerText(decodeContent(["<thi"], done: done)) == "<thi",
                "think tags: undecided content flushes at \(done ? "DONE" : "EOF")")
        }
        for end in 0...content.count {
            let prefix = String(content[..<end])
            let expected: String
            if end < "<think>".count {
                expected = prefix
            } else if let close = prefix.range(of: "</think>") {
                expected = String(prefix[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                expected = ""
            }
            for done in [true, false] {
                expect(
                    answerText(decodeContent(prefix.map(String.init), done: done)) == expected,
                    "think tags: every prefix at DONE or EOF suppresses only recognized reasoning")
            }
        }
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        _ = try? decoder.feed(contentFrame("<thi"))
        expect((try? decoder.finish()) == [.text("<thi")], "think tags: EOF flushes the held prefix")
        expect((try? decoder.finish()) == [], "think tags: EOF never flushes twice")
        var terminated = AIStreamDecoder(shape: .openAICompatible)
        _ = try? terminated.feed(contentFrame("<think>r</thi"))
        expect(
            (try? terminated.feed(Data("data: [DONE]\n\n".utf8)))
                == [],
            "think tags: DONE discards the unfinished reasoning suffix")
        expect((try? terminated.finish()) == [], "think tags: EOF after DONE never flushes twice")
        let tools = Data(
            """
            data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"read","arguments":"{}"}}]}}]}

            data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}

            data: {"choices":[],"usage":{"prompt_tokens":2,"completion_tokens":3}}

            data: [DONE]

            """.utf8)
        let toolEvents = decodeAll(contentFrame("<think>r</think>") + tools, slice: 7)
        expect(
            toolEvents.isEmpty,
            "think tags: unrequested function calls and usage-only frames emit nothing")
        let native = Data(
            """
            data: {"choices":[{"delta":{"reasoning_content":"native"}}]}

            data: {"choices":[{"delta":{"content":"answer"}}]}

            data: [DONE]

            """.utf8)
        expect(
            decodeAll(native, slice: 7) == [.text("answer")],
            "think tags: native reasoning_content is ignored")
    }

    private static func contentFrame(_ content: String) -> Data {
        guard let encoded = try? JSONEncoder().encode(content),
            let quoted = String(bytes: encoded, encoding: .utf8)
        else {
            preconditionFailure("A content string must encode as JSON")
        }
        return Data("data: {\"choices\":[{\"delta\":{\"content\":\(quoted)}}]}\n\n".utf8)
    }

    private static func decodeContent(_ fragments: [String], done: Bool = true) -> [AIStreamEvent] {
        var data = fragments.reduce(into: Data()) { $0 += contentFrame($1) }
        if done { data += Data("data: [DONE]\n\n".utf8) }
        return decodeAll(data, slice: max(1, data.count))
    }

    private static func answerText(_ events: [AIStreamEvent]) -> String {
        events.compactMap { event -> String? in
            if case .text(let text) = event { return text }
            return nil
        }.joined()
    }

    private static func decodeAll(_ data: Data, slice: Int) -> [AIStreamEvent] {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        var events: [AIStreamEvent] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + slice, data.count)
            events += (try? decoder.feed(data[offset..<end])) ?? []
            offset = end
        }
        events += (try? decoder.finish()) ?? []
        let hasDone = String(decoding: data, as: UTF8.self).contains("data: [DONE]")
        expect(decoder.isTerminal == hasDone, "only a done marker completes a compatible stream")
        if hasDone {
            expect((try? decoder.feed(contentFrame("late"))) == [], "text after terminal is ignored")
        }
        return events
    }

    /// A refusal is read, not discarded: the status's line, then what the provider said under it.
    static func refusalsShowTheProvidersOwnWords() {
        func body(_ json: String) -> Data { Data(json.utf8) }
        func shown(_ status: Int, _ json: String, retryAfter: String? = nil) -> String {
            AIProviderFailure.description(
                status: status, body: body(json), retryAfter: retryAfter, secrets: [])
        }
        let general = "The provider rejected the model or request (HTTP 400)."
        expect(
            shown(
                400,
                #"{"error":{"object":"error","type":"invalid_request_error","message":"#
                    + #""Model accounts/fireworks/models/glm-5p3-flash does not support image input."}}"#)
                == "\(general)\n\nModel accounts/fireworks/models/glm-5p3-flash does not support image input.",
            "OpenAI's error shape shows its message under the line")
        expect(
            shown(
                400,
                #"{"error":{"message":"Provider returned error","code":400,"metadata":"#
                    + #"{"raw":"{\"error\":{\"message\":\"Maximum context length is 8192 tokens\"}}","#
                    + #""provider_name":"Fireworks"}}}"#)
                == "\(general)\n\nMaximum context length is 8192 tokens",
            "OpenRouter's nested upstream body is read through its raw string")
        expect(
            shown(
                400,
                #"{"type":"error","error":{"type":"invalid_request_error","message":"prompt is too long"}}"#)
                == "\(general)\n\nprompt is too long",
            "Anthropic's shape too")
        expect(
            shown(
                400, #"[{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}]"#)
                == "\(general)\n\nAPI key not valid.",
            "and Gemini's array")
        expect(
            shown(404, #"{"object":"error","message":"The model `x` does not exist.","code":404}"#)
                == "The provider rejected the model or request (HTTP 404).\n\nThe model `x` does not exist.",
            "and vLLM's")
        expect(
            shown(429, #"{"error":{"message":"You exceeded your current quota."}}"#, retryAfter: "12")
                == "Rate limit reached — retry after 12 seconds.\n\nYou exceeded your current quota.",
            "a status keeps its own line, with the provider's reason under it")
        expect(
            shown(400, "Bad request: unknown field") == "\(general)\n\nBad request: unknown field",
            "a plain-text body is shown as sent")
        expect(
            shown(502, "<html><body>Bad gateway</body></html>")
                == "The provider is temporarily unavailable (HTTP 502).",
            "an HTML error page is not pasted into the chat")
        expect(
            shown(401, "") == "API key rejected — check it in Settings.",
            "an empty body leaves the line alone")
        expect(
            shown(
                502,
                #"{"error":{"message":"Upstream timed out","metadata":{"raw":"<html>Bad gateway</html>"}}}"#)
                == "The provider is temporarily unavailable (HTTP 502).\n\nUpstream timed out",
            "an HTML page nested in the body gives way to the message beside it")
        expect(
            shown(502, #"{"error":"<html><body>Bad gateway</body></html>"}"#)
                == "The provider is temporarily unavailable (HTTP 502).",
            "and is left out when it is all there is")
        expect(
            shown(400, #"{"error":{"message":"Provider returned error","metadata":{"raw":"{\"code\":7}"}}}"#)
                == "\(general)\n\nProvider returned error",
            "an upstream body with no message falls back to the wrapper's")
        expect(
            shown(400, #""Bad request""#) == "\(general)\n\nBad request",
            "a bare JSON string loses its quotes")
        expect(
            shown(400, "[Errno 111] Connection refused") == "\(general)\n\n[Errno 111] Connection refused",
            "text that only starts like JSON is still text")

        let echo = String(repeating: "A", count: AIProviderFailure.bodyLimit)
        let oversized =
            #"{"detail":[{"type":"string_type","msg":"Input should be a valid string","input":"\#(echo)"}]}"#
        expect(
            AIProviderFailure.description(
                status: 422, body: body(oversized).prefix(AIProviderFailure.bodyLimit), retryAfter: nil,
                secrets: [])
                == "The provider rejected the model or request (HTTP 422).\n\nInput should be a valid string",
            "a body the cap cut still gives up the message near its start")
        expect(
            shown(400, #"{"error":{"message":"Half a mess"#) == general,
            "and one cut inside its message shows no fragment of JSON")
        expect(
            shown(400, "[\n  {\"error\": {\"message\": \"Too long\"}") == "\(general)\n\nToo long",
            "a cut array is read the same way, however it is spaced")
        expect(
            shown(400, #"["first error", "second"#) == general, "and a cut list of strings is not shown raw")
        expect(shown(400, "[1, 2,") == general, "nor a cut list of anything else")
        expect(
            shown(400, #"["model"] is not supported"#) == "\(general)\n\n[\"model\"] is not supported",
            "a sentence that opens with a bracket and closes it is still a sentence")
        expect(
            shown(400, "{model} was not found") == "\(general)\n\n{model} was not found",
            "whichever bracket it is")
        expect(
            shown(400, "[request timed out]") == "\(general)\n\n[request timed out]",
            "and so is one that is bracketed from end to end")
        expect(
            shown(
                400,
                #"{"message":"<html>Bad gateway</html>","detail":"Reduce your prompt","padding":"#)
                == "\(general)\n\nReduce your prompt",
            "a cut body's first candidate being an HTML page does not hide the next one")
        expect(
            shown(
                400,
                #"{"error":{"message":"Provider returned error","metadata":{"raw":"{\"error\":{\"mess"}}}"#)
                == "\(general)\n\nProvider returned error",
            "an upstream body that arrived cut falls back to the wrapper's message")
        expect(
            shown(
                422,
                #"{"detail":[{"input":{"error":"boom from a tool"},"msg":"Input should be a valid string","x":"#
            )
                == "The provider rejected the model or request (HTTP 422).\n\nInput should be a valid string",
            "an `error` echoed back in the request does not pass for the message")

        let long = String(repeating: "x", count: AIProviderFailure.messageLimit + 50)
        expect(
            shown(400, #"{"error":{"message":"\#(long)"}}"#).hasSuffix("x…")
                && shown(400, #"{"error":{"message":"\#(long)"}}"#).count
                    == general.count + 2 + AIProviderFailure.messageLimit + 1,
            "a very long message is cut rather than filling the chat")

        let key = "fw_3c8a7b2e91d04f5a"
        let echoed = AIProviderFailure.description(
            status: 400,
            body: body(#"{"error":{"message":"Bad header: Bearer \#(key), also sk-proj-abcdefghijklmnop"}}"#),
            retryAfter: nil, secrets: [key])
        expect(
            !echoed.contains(key) && !echoed.contains("sk-proj-abcdef") && echoed.contains("[redacted]"),
            "the key, a bearer token and key-shaped strings never reach the transcript")

        let filler = String(repeating: "x", count: AIProviderFailure.messageLimit - 8)
        let straddling = AIProviderFailure.description(
            status: 400, body: body(#"{"error":{"message":"\#(filler) sk-proj-abcdefghijklmnop"}}"#),
            retryAfter: nil, secrets: [])
        expect(
            !straddling.contains("sk-pro"),
            "a key the cut lands inside is redacted first, not left half-shown")
        expect(
            AIProviderFailure.redacted("Invalid key: abc123.", secrets: ["abc123"])
                == "Invalid key: [redacted].",
            "a short key is redacted too")
        expect(
            AIProviderFailure.redacted("Port 7 refused key 7 (70 tries)", secrets: ["7", ""])
                == "Port [redacted] refused key [redacted] (70 tries)",
            "but only as a whole word, so it cannot eat into a longer one")
        expect(
            AIProviderFailure.redacted("Invalid key: abcdef", secrets: ["abcdef"])
                == "Invalid key: [redacted]",
            "a short key with no digit in it is a key all the same")
        expect(
            AIProviderFailure.redacted("Received API Key = sk-1234", secrets: ["sk-1234"])
                == "Received API Key = [redacted]",
            "as is a local proxy's short key, which no key shape would catch")
    }

    static func brokenStreamsFailLoudly() {
        var decoder = AIStreamDecoder(shape: .openAICompatible)
        let failure = Data(
            """
            data: {"choices":[{"delta":{"content":"Par"}}]}

            data: {"error":{"message":"Provider returned error","code":502}}

            data: {"choices":[{"delta":{"content":"never"}}]}

            """.utf8)
        var events: [AIStreamEvent] = []
        var thrown: Error?
        do { events = try decoder.feed(failure) } catch { thrown = error }
        expect(
            thrown as? AIProviderError == .responseFailed("Provider returned error"),
            "a mid-stream error payload fails with the provider's message")
        expect(decoder.isTerminal, "a mid-stream error ends the stream")
        expect(events.isEmpty, "nothing after the error is decoded")

        var relayed = AIStreamDecoder(shape: .openAICompatible, secrets: ["hunter2-gateway-key"])
        let upstream =
            Data(
                (#"data: {"error":{"message":"Provider returned error","code":400,"metadata":{"raw":"#
                    + #""{\"error\":{\"message\":\"Too long for key hunter2-gateway-key\"}}"}}}"#).utf8)
            + Data("\n\n".utf8)
        var relayedError: Error?
        do { _ = try relayed.feed(upstream) } catch { relayedError = error }
        expect(
            relayedError as? AIProviderError == .responseFailed("Too long for key [redacted]"),
            "a mid-stream error reads through to the upstream reason, with the connection's key out")

        var paged = AIStreamDecoder(shape: .openAICompatible)
        let page = Data(#"data: {"error":{"message":"<html>Bad gateway</html>"}}"#.utf8) + Data("\n\n".utf8)
        var pagedError: Error?
        do { _ = try paged.feed(page) } catch { pagedError = error }
        expect(
            pagedError as? AIProviderError
                == .responseFailed("The provider stopped the response with an error."),
            "a mid-stream error that is only an HTML page says so in Tinycast's own words")

        var bracketed = AIStreamDecoder(shape: .openAICompatible)
        let prose =
            Data(#"data: {"error":{"message":"[\"model\"] is not supported"}}"#.utf8) + Data("\n\n".utf8)
        var bracketedError: Error?
        do { _ = try bracketed.feed(prose) } catch { bracketedError = error }
        expect(
            bracketedError as? AIProviderError == .responseFailed(#"["model"] is not supported"#),
            "a mid-stream message that opens with a bracket is still shown")

        var malformed = AIStreamDecoder(shape: .openAICompatible)
        let garbage = Data("data: {not json\n\n".utf8)
        expect(
            (try? malformed.feed(garbage)) == nil,
            "unparseable JSON is rejected rather than skipped")
        expect(malformed.isTerminal, "a malformed frame ends the stream")

        var overloaded = AIStreamDecoder(shape: .anthropic)
        let said =
            Data(
                #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#.utf8)
            + Data("\n\n".utf8)
        var overloadedError: Error?
        do { _ = try overloaded.feed(said) } catch { overloadedError = error }
        expect(
            overloadedError?.localizedDescription
                == "The provider stopped the response with an error.\n\nOverloaded",
            "an Anthropic error event shows what it said under the line")

        var echoing = AIStreamDecoder(shape: .anthropic, secrets: ["hunter2-gateway-key"])
        let echoed =
            Data(
                #"data: {"type":"error","error":{"type":"api_error","message":"Bad key hunter2-gateway-key"}}"#
                    .utf8)
            + Data("\n\n".utf8)
        var echoedError: Error?
        do { _ = try echoing.feed(echoed) } catch { echoedError = error }
        expect(
            echoedError?.localizedDescription.hasSuffix("Bad key [redacted]") == true,
            "and never the key the connection was using")

        var pagedAnthropic = AIStreamDecoder(shape: .anthropic)
        let anthropicPage =
            Data(
                #"data: {"type":"error","error":{"type":"api_error","message":"<html>Bad gateway</html>"}}"#
                    .utf8)
            + Data("\n\n".utf8)
        var pagedAnthropicError: Error?
        do { _ = try pagedAnthropic.feed(anthropicPage) } catch { pagedAnthropicError = error }
        expect(
            pagedAnthropicError?.localizedDescription == "The provider stopped the response with an error.",
            "nor an HTML page in place of a message")

        var anthropic = AIStreamDecoder(shape: .anthropic)
        let rejected = Data(
            "data: {\"type\":\"error\",\"error\":{\"type\":\"authentication_error\"}}\n\n".utf8)
        var anthropicError: Error?
        do { _ = try anthropic.feed(rejected) } catch { anthropicError = error }
        expect(
            anthropicError as? AIProviderError
                == .responseFailed("API key rejected — check it in Settings."),
            "an Anthropic error event names the cause without echoing the key")

        var silent = AIStreamDecoder(shape: .openAICompatible)
        let truncated = Data("data: {\"choices\":[{\"delta\":{\"content\":\"half\"}}]}\n\n".utf8)
        let partial = (try? silent.feed(truncated)) ?? []
        expect(partial == [.text("half")], "text before a cut-off is still delivered")
        expect(!silent.isTerminal, "a stream without a done marker stays open for the caller to fail")
    }

    static func brandsResolveFromModelIDs() {
        let expected: [(String, AIBrand?)] = [
            ("openai/gpt-oss-20b", .openAI), ("o4-mini", .openAI), ("o3", .openAI),
            ("anthropic/claude-sonnet-4", .claude), ("google/gemma-3-27b-it", .gemini),
            ("x-ai/grok-4", .x), ("deepseek/deepseek-r1", .deepSeek), ("qwen/qwq-32b", .qwen),
            ("mistralai/codestral-2501", .mistral), ("meta-llama/llama-3.3-70b", .meta),
            ("moonshotai/kimi-k2", .kimi), ("minimax/minimax-m1", .miniMax),
            ("perplexity/sonar-pro", .perplexity), ("z-ai/glm-4.5", .zai),
            ("openrouter/auto", .openRouter), ("cohere/command-r", nil), ("o10", nil)
        ]
        for (model, brand) in expected {
            expect(
                AIBrand.resolve(model: model) == brand, "\(model) resolves to \(String(describing: brand))")
        }
        expect(
            AIBrand.resolve(provider: .anthropic, model: "whatever") == .claude,
            "a vendor endpoint names its brand regardless of the model id")
        expect(
            AIBrand.resolve(provider: .openAICompatible, model: "deepseek-chat") == .deepSeek,
            "a compatible endpoint resolves the brand from the model id")
    }

    static func onDeviceSelectionsRoundTripAndLead() {
        let encoded = try? JSONEncoder().encode(AIModelSelection.appleIntelligence)
        let decoded = encoded.flatMap { try? JSONDecoder().decode(AIModelSelection.self, from: $0) }
        expect(decoded == .appleIntelligence, "the on-device selection survives a round trip")
        expect(
            AIModelSelection.appleIntelligence.model == AppleIntelligence.modelID,
            "the on-device selection reports a stable model id")
        expect(
            AIModelSelection.appleIntelligence.source == .appleIntelligence,
            "the on-device selection is its own source")
        expect(AIModelSelection.appleIntelligence.isOnDevice, "on-device remains identifiable")
        for source in ["codex", "chatGPT", "claude", "grok", "openCode", "cursor"] {
            let legacy = Data("{\"\(source)\":{\"model\":\"old\",\"effort\":\"high\"}}".utf8)
            expect(
                (try? JSONDecoder().decode(AIModelSelection.self, from: legacy)) == nil,
                "retired \(source) selections are not executable")
        }

        let suite = "AIProviderTests.onDevice"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }

        let store = AISettingsStore(defaults: defaults, isAppleIntelligenceAvailable: { true })
        expect(store.isRouteEnabled(.appleIntelligence), "the on-device route starts enabled")
    }

    static func settingsPersistAndRepairSelections() {
        let suite = "AIProviderTests.persistence"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }
        let firstID = UUID()
        let secondID = UUID()

        var first = AIConnection(
            id: firstID, name: "  Work  ", provider: .openRouter,
            models: [" model-a ", "model-a", "model-b"],
            reasoningOptions: [
                "model-b": .init(efforts: ["medium", "low"], defaultEffort: "medium")
            ])
        first.baseURL = " https://openrouter.ai/api/v1 "
        let store = AISettingsStore(defaults: defaults)
        store.save(first)
        store.save(
            AIConnection(id: secondID, provider: .gemini, models: ["gemini-model"]))
        expect(store.connections.first?.name == "Work", "connection names are normalized")
        expect(
            store.connections.first?.models == ["model-a", "model-b"],
            "models are trimmed and deduplicated")
        let reopened = AISettingsStore(defaults: defaults)
        expect(reopened.connections == store.connections, "connection metadata survives a restart")
        reopened.removeConnection(id: firstID)
        expect(reopened.connections.map(\.id) == [secondID], "removing one connection keeps the other")
    }

    static func switchedOffRoutesLeaveTheDefault() {
        let suite = "AIProviderTests.disabledRoutes"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }
        let store = AISettingsStore(defaults: defaults)
        let first = AIConnection(provider: .openRouter, models: ["first-model"])
        let second = AIConnection(provider: .gemini, models: ["second-model"])
        store.save(first)
        store.save(second)
        store.setRoute(.api(first.id), enabled: false)
        let reopened = AISettingsStore(defaults: defaults)
        expect(
            !reopened.isRouteEnabled(.api(first.id)) && reopened.isRouteEnabled(.api(second.id)),
            "a switched-off connection stays off after a restart")
        reopened.setRoute(.appleIntelligence, enabled: false)
        expect(
            !reopened.isRouteEnabled(.appleIntelligence),
            "the on-device model can be switched off like a connection")
        reopened.setRoute(.api(first.id), enabled: true)
        reopened.removeConnection(id: second.id)
        reopened.removeConnection(id: first.id)
        expect(
            !reopened.disabledRoutes.contains(AIModelSource.api(first.id).storageKey),
            "removing a connection forgets that it was switched off")
    }

    static func shownModelsFilterThePicker() {
        let suite = "AIProviderTests.shownModels"
        let defaults = isolatedDefaults(suite)
        defer { discardSuite(suite, defaults) }
        let store = AISettingsStore(defaults: defaults)
        let available = ["a", "b", "c"]
        let source = AIModelSource.api(UUID())
        expect(
            available.allSatisfy { store.isModelShown($0, in: source) },
            "a route nobody has trimmed lists every model")
        store.setModel("b", shown: false, in: source, available: available)
        let reopened = AISettingsStore(defaults: defaults)
        expect(
            reopened.isModelShown("a", in: source) && !reopened.isModelShown("b", in: source),
            "an unticked model stays out of the picker after a restart")
        expect(
            !reopened.isModelShown("d", in: source),
            "a trimmed route does not list a model it adds later")
        expect(
            reopened.isModelShown("b", in: .api(UUID())),
            "trimming one route leaves the others listing everything")
        reopened.setModel("b", shown: true, in: source, available: available)
        expect(
            reopened.shownModels[source.storageKey] == nil
                && reopened.isModelShown("d", in: source),
            "ticking every model back returns the route to listing all, later ones included")
        reopened.hideAllModels(in: source)
        expect(
            available.allSatisfy { !reopened.isModelShown($0, in: source) },
            "Hide All leaves no models listed")
        let connection = AIConnection(provider: .openRouter, models: ["x", "y"])
        reopened.save(connection)
        reopened.setModel("y", shown: false, in: .api(connection.id), available: connection.models)
        reopened.removeConnection(id: connection.id)
        expect(
            reopened.shownModels[AIModelSource.api(connection.id).storageKey] == nil,
            "removing a connection forgets which of its models were shown")
    }
}

private func discardSuite(_ name: String, _ defaults: UserDefaults) {
    defaults.removePersistentDomain(forName: name)
    UserDefaults.standard.removeSuite(named: name)
    CFPreferencesAppSynchronize(name as CFString)
    try? FileManager.default.removeItem(
        at: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Preferences/\(name).plist"))
}

private func isolatedDefaults(_ name: String) -> UserDefaults {
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}
