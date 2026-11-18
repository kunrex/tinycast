import FoundationModels
import Foundation

@main
@MainActor
struct AppleIntelligenceTests {
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

    static func main() async {
        statusCopyCoversEveryReason()
        deltasFollowCumulativeSnapshots()
        actionsStartWithOnlyInstructions()
        generationErrorsBecomeReadableFailures()
        if ProcessInfo.processInfo.environment["TINYCAST_TEST_APPLE_INTELLIGENCE"] == "1" {
            await onDeviceModelAnswers()
        } else {
            print("skip  on-device stream — set TINYCAST_TEST_APPLE_INTELLIGENCE=1 to run")
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func statusCopyCoversEveryReason() {
        expect(AppleIntelligenceStatus.available.message == nil, "available reads as no failure")
        expect(AppleIntelligenceStatus.available.isAvailable, "available is available")

        let unavailable: [AppleIntelligenceStatus] = [
            .deviceNotEligible, .notEnabled, .modelNotReady
        ]
        for status in unavailable {
            expect(!status.isAvailable, "\(status) is not available")
            expect(status.message?.isEmpty == false, "\(status) explains itself")
        }
        expect(
            Set(unavailable.compactMap(\.message)).count == unavailable.count,
            "each reason reads differently")

        expect(!AppleIntelligenceStatus.deviceNotEligible.isSupported, "ineligible hardware is unsupported")
        expect(
            AppleIntelligenceStatus.notEnabled.isSupported
                && AppleIntelligenceStatus.modelNotReady.isSupported,
            "a Mac that could run it after a change in System Settings is supported")
    }

    static func deltasFollowCumulativeSnapshots() {
        var delta = AppleIntelligenceDelta()
        let emitted = ["He", "Hello", "Hello!"].map { delta.delta(from: $0) }
        expect(emitted == ["He", "llo", "!"], "cumulative snapshots become deltas, got \(emitted)")

        // A revision replaces what came before, so dropping a stale prefix would truncate it.
        var revised = AppleIntelligenceDelta()
        _ = revised.delta(from: "Hello")
        expect(revised.delta(from: "Goodbye") == "Goodbye", "a revised snapshot is emitted whole")

        var repeated = AppleIntelligenceDelta()
        _ = repeated.delta(from: "Hello")
        expect(repeated.delta(from: "Hello").isEmpty, "an unchanged snapshot emits nothing")
    }

    static func actionsStartWithOnlyInstructions() {
        let turn = AppleIntelligenceProvider.turn(
            for: AIRequest(instructions: "Be brief.", prompt: "  selection  "))
        expect(turn.prompt == "selection", "the text prompt is trimmed")
        let entries = Array(turn.transcript)
        expect(entries.count == 1, "only instructions enter the initial transcript")
        if case .instructions(let instructions) = entries.first {
            expect(text(instructions.segments) == "Be brief.", "instructions lead the transcript")
        } else {
            expect(false, "the transcript opens with instructions")
        }
        let bare = AppleIntelligenceProvider.turn(for: AIRequest(prompt: "hi"))
        expect(Array(bare.transcript).isEmpty, "without instructions the transcript is empty")
        expect(bare.prompt == "hi", "the text is the prompt")
        let empty = AppleIntelligenceProvider.turn(for: AIRequest(prompt: " \n "))
        expect(empty.prompt == nil, "an empty prompt cannot be sent")
    }

    static func generationErrorsBecomeReadableFailures() {
        let context = LanguageModelSession.GenerationError.Context(
            debugDescription: "internal-detail-42")
        let errors: [LanguageModelSession.GenerationError] = [
            .exceededContextWindowSize(context), .guardrailViolation(context),
            .unsupportedLanguageOrLocale(context), .assetsUnavailable(context),
            .rateLimited(context), .concurrentRequests(context)
        ]
        var messages: [String] = []
        for error in errors {
            let message = AppleIntelligenceProvider.providerError(error).localizedDescription
            expect(!message.isEmpty, "\(error) explains itself")
            expect(
                !message.contains("internal-detail-42"),
                "\(error) does not leak its debug description")
            messages.append(message)
        }
        expect(Set(messages).count == messages.count, "each failure reads differently")
        expect(
            AppleIntelligenceProvider.providerError(.decodingFailure(context))
                == .malformedResponse,
            "a decoding failure is the shared malformed-response case")
    }

    static func onDeviceModelAnswers() async {
        let status = AppleIntelligenceProvider.status()
        guard status.isAvailable else {
            print("skip  on-device stream — \(status.message ?? "unavailable")")
            return
        }
        let request = AIRequest(
            instructions: "Reply with one short sentence.",
            prompt: "Name one colour.")
        var text = ""
        var finished = false
        do {
            for try await event in AppleIntelligenceProvider().stream(request) {
                switch event {
                case .text(let chunk): text += chunk
                }
            }
            finished = true
        } catch {
            expect(false, "the on-device stream failed: \(error.localizedDescription)")
            return
        }
        expect(!text.isEmpty, "the on-device model answered")
        expect(finished, "the on-device stream completed successfully")
    }

    private static func text(_ segments: [Transcript.Segment]) -> String {
        segments.compactMap { if case .text(let segment) = $0 { segment.content } else { nil } }
            .joined()
    }

}
