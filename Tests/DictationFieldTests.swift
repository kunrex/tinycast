import AppKit
import SwiftUI

@main
@MainActor
struct DictationFieldTests {
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        try await testDelivery()
        try await testScopedCancellation()
        try await testLiveDeliveryFailure()
        try await testQueuedLiveChunk(cancelling: false)
        try await testQueuedLiveChunk(cancelling: true)
        try await testSoundsOff()
        try await testSounds()
        try await testCancelSilently()
        try await testCancelDuringStartCue()
        try await testBluetoothStartCue()
        print("ALL PASSED")
    }

    private static func testDelivery() async throws {
        for mode in [DictationMode.toggle, .pushToTalk] {
            let fixture = Fixture()
            fixture.settings.dictationMode = mode
            let editor = TestEditor()
            try await fixture.start(into: editor)
            fixture.coordinator.toggle(into: editor)
            try await wait { fixture.models.pending != nil }
            fixture.models.finish("Spoken words")
            try await wait { fixture.coordinator.field == nil }
            expect(editor.string == "Spoken words", "Both shortcut modes insert the field's transcript")
            expect(Paster.copies.isEmpty, "A field mic ignores the copy-only destination setting")
        }
    }

    private static func testScopedCancellation() async throws {
        let fixture = Fixture()
        let editor = TestEditor()
        fixture.coordinator.toggle(into: editor)
        fixture.coordinator.cancel(in: editor)
        try await wait { fixture.capture.stopCount > 0 }
        expect(fixture.coordinator.field == nil, "Cancellation covers a recording still starting")
        expect(!fixture.capture.isRecording, "A canceled start cannot leave recording active")

        try await fixture.start(into: editor)
        fixture.coordinator.cancel(in: TestEditor())
        expect(fixture.capture.isRecording, "Another editor cannot cancel this session")
        expect(fixture.coordinator.field != nil, "Unrelated teardown preserves the field owner")
        fixture.coordinator.cancel(in: editor)
        try await wait { !fixture.capture.isRecording }
    }

    private static func testLiveDeliveryFailure() async throws {
        let fixture = Fixture()
        fixture.settings.dictationDestination = .paste
        fixture.settings.dictationLiveInsertion = true
        _ = fixture.coordinator
        fixture.capture.snapshotSamples =
            [Float](repeating: 0.5, count: 32_000)
            + [Float](repeating: 0, count: 16_000)
        fixture.coordinator.pressed()
        try await waitLong { fixture.capture.isRecording }
        try await waitLong { fixture.models.pending != nil }
        fixture.models.finish("Spoken words")
        try await wait { fixture.models.finished }
        fixture.coordinator.accept()
        try await waitLong { !fixture.messages.isEmpty }
        expect(
            fixture.messages == ["Couldn't paste some dictation into this app"],
            "A failed live chunk is reported once at finish, never silently lost")
        expect(Paster.copies.isEmpty, "A paste destination copies nothing on the way out")
    }

    private static func testQueuedLiveChunk(cancelling: Bool) async throws {
        let fixture = Fixture()
        fixture.settings.dictationLiveInsertion = true
        let editor = TestEditor()
        var release: CheckedContinuation<Void, Never>?
        fixture.queue.enqueue(isAutomatic: false) {
            await withCheckedContinuation { release = $0 }
        }
        try await wait { release != nil }
        try await fixture.start(into: editor)
        fixture.capture.snapshotSamples =
            [Float](repeating: 0.5, count: 32_000)
            + [Float](repeating: 0, count: 16_000)
        try await waitLong { fixture.models.pending != nil }
        fixture.models.finish("Spoken words")
        try await wait { fixture.models.finished }

        guard cancelling else {
            fixture.coordinator.toggle(into: editor)
            release?.resume()
            try await wait { fixture.coordinator.field == nil }
            expect(editor.string == "Spoken words", "Finishing lets a queued live chunk land")
            expect(fixture.messages.isEmpty, "A landed live chunk reports nothing")
            return
        }
        fixture.coordinator.cancel(in: editor)
        release?.resume()
        await fixture.queue.drain()
        try await wait { !fixture.capture.isRecording }
        fixture.settings.dictationLiveInsertion = false
        // Stopping ignores a toggle, so retry until the cancelled session has wound down.
        try await wait {
            if fixture.coordinator.field == nil { fixture.coordinator.toggle(into: editor) }
            return fixture.capture.isRecording
        }
        fixture.coordinator.toggle(into: editor)
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("More words")
        try await wait { fixture.coordinator.field == nil }
        expect(editor.string == "More words", "Cancelling drops a queued live chunk")
        expect(fixture.messages.isEmpty, "A chunk dropped by cancelling never fails the next session")
    }

    private static func testSoundsOff() async throws {
        let fixture = Fixture()
        fixture.settings.dictationPlaysSounds = false
        let editor = TestEditor()
        AudioEvents.log = []
        fixture.coordinator.toggle(into: editor)
        expect(AudioEvents.log == ["duck"], "Without sounds, ducking still starts at the press")
        try await wait { fixture.capture.isRecording }
        fixture.coordinator.toggle(into: editor)
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Spoken words")
        try await wait { fixture.coordinator.field == nil }
        expect(
            !AudioEvents.log.contains("start cue") && !AudioEvents.log.contains("stop cue"),
            "No cue plays unless sounds are on")
    }

    private static func testSounds() async throws {
        let fixture = Fixture()
        let editor = TestEditor()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        try await Task.sleep(for: .milliseconds(20))
        expect(AudioEvents.log.isEmpty, "The start cue waits for the microphone's first samples")
        fixture.capture.onLevels?([])
        try await wait { AudioEvents.log.contains("duck") }
        expect(
            AudioEvents.log == ["start cue", "duck"],
            "The start cue plays on the first samples, with ducking")
        fixture.coordinator.toggle(into: editor)
        expect(
            AudioEvents.log == ["start cue", "duck", "restore", "stop cue"],
            "The stop cue plays once the volume is restored, before the microphone closes")
        expect(fixture.capture.isRecording, "The microphone is still open when the stop cue plays")
        try await wait { fixture.models.pending != nil }
        fixture.models.finish("Spoken words")
        try await wait { fixture.coordinator.field == nil }
        expect(editor.string == "Spoken words", "Sounds leave the transcript untouched")
    }

    private static func testCancelSilently() async throws {
        let fixture = Fixture()
        let editor = TestEditor()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        fixture.capture.onLevels?([])
        try await wait { AudioEvents.log.contains("duck") }
        fixture.coordinator.cancel(in: editor)
        try await wait { !fixture.capture.isRecording }
        try await Task.sleep(for: .milliseconds(50))
        expect(!AudioEvents.log.contains("stop cue"), "Cancelling plays no stop cue")
    }

    private static func testCancelDuringStartCue() async throws {
        let fixture = Fixture()
        let editor = TestEditor()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        fixture.capture.isBluetooth = true
        fixture.capture.onLevels?([])
        fixture.coordinator.cancel(in: editor)
        try await Task.sleep(for: .milliseconds(600))
        expect(
            !AudioEvents.log.contains("start cue") && !AudioEvents.log.contains("duck"),
            "A session cancelled before its start cue plays no cue and never ducks")
    }

    private static func testBluetoothStartCue() async throws {
        let fixture = Fixture()
        let editor = TestEditor()
        AudioEvents.log = []
        try await fixture.start(into: editor)
        fixture.capture.isBluetooth = true
        let samples = ContinuousClock.now
        fixture.capture.onLevels?([])
        try await wait { AudioEvents.log.contains("start cue") }
        expect(
            ContinuousClock.now - samples >= .milliseconds(500),
            "A Bluetooth microphone delays the start cue until its headset has switched output")
        fixture.coordinator.cancel(in: editor)
    }

    /// The live poll sleeps longer than `wait` allows.
    private static func waitLong(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(8)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func wait(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CocoaError(.coderInvalidValue) }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
        print("PASS  \(message)")
    }

    @MainActor
    private final class Fixture {
        let settings = AppSettings()
        let models = DictationModelStore()
        let queue = DeliveryQueue()
        var messages: [String] = []
        lazy var coordinator = DictationCoordinator(
            settings: settings, hotKeys: HotKeyManager(), models: models,
            injector: TextInjector(
                clipboardManager: ClipboardManager(), settings: settings, deliveryQueue: queue),
            audioDucker: DictationAudioDucker(), confirmEnable: { false },
            showMessage: { [weak self] message, _ in self?.messages.append(message) })

        var capture: DictationCapture { DictationCapture.latest! }
        var panel: DictationPanelController { DictationPanelController.latest! }

        func start(into editor: TestEditor) async throws {
            coordinator.toggle(into: editor)
            try await wait { capture.isRecording }
            expect(coordinator.field?.editor == ObjectIdentifier(editor), "The session belongs to its editor")
        }
    }

    @MainActor
    private final class TestEditor: NSTextView, InjectableTextView {}
}

@MainActor
final class AppSettings {
    var snippetsEnabled = false
    var dictationEnabled = true
    var dictationMode = DictationMode.toggle
    var dictationModel = DictationModel.redux
    var dictationMicrophone: String?
    var dictationLanguage: String?
    var dictationDestination = DictationDestination.copy
    var dictationAdaptsCapitalization = true
    var dictationLiveInsertion = false
    var dictationPlaysSounds = true
}

enum HotKeyAction { case dictation }

@MainActor
final class HotKeyManager {
    struct Binding {
        var shortcut: Int?
        var holdKey: Int?
    }
    func binding(for action: HotKeyAction) -> Binding? { nil }
    func conflictOwner(of binding: Binding, excluding action: HotKeyAction) -> String? { nil }
}

@MainActor
final class DictationCapture {
    static weak var latest: DictationCapture?
    var onLevels: (([Float]) -> Void)?
    var onLimit: (() -> Void)?
    var isRecording = false
    var isBluetooth = false
    var stopCount = 0

    init() { Self.latest = self }
    func start(microphoneID: String?) async throws { isRecording = true }
    var snapshotSamples: [Float] = []
    func snapshot() -> [Float] { snapshotSamples }
    func stop() async -> [Float] {
        isRecording = false
        stopCount += 1
        return [Float](repeating: 0, count: 1_600)
    }
}

@MainActor
final class DictationModelStore {
    var pending: CheckedContinuation<String, any Error>?
    var finished = false

    func isInstalled(_ model: DictationModel) -> Bool { true }
    func download(_ model: DictationModel) async throws {}
    func delete(_ model: DictationModel) async throws {}
    func stop() async {}
    func prepareForTermination() {}

    func transcribe(_ samples: [Float], model: DictationModel, language: String?) async throws -> String {
        defer { finished = true }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }

    func finish(_ text: String) {
        let continuation = pending
        pending = nil
        continuation?.resume(returning: text)
    }
}

@MainActor
final class DictationPanelController {
    enum Phase { case listening, transcribing }
    @MainActor
    final class State {
        var phase = Phase.listening
        var levels: [Float] = []
    }
    static weak var latest: DictationPanelController?
    let state = State()
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?
    var isVisible = false
    init() { Self.latest = self }
    func show() { isVisible = true }
    func close() { isVisible = false }
}

@MainActor
enum AudioEvents {
    static var log: [String] = []
}

@MainActor
final class DictationAudioDucker {
    func begin() { AudioEvents.log.append("duck") }
    func end() { AudioEvents.log.append("fade up") }
    func restoreImmediately() { AudioEvents.log.append("restore") }
}

@MainActor
final class DictationCueRunner {
    enum Cue { case start, stop }

    func play(_ cue: Cue) { AudioEvents.log.append(cue == .start ? "start cue" : "stop cue") }
}

@MainActor
final class ClipboardManager {
    static let internalType = NSPasteboard.PasteboardType("com.tinycast.internal")
    func prepareForTinycastPasteboardMutation() {}
    func synchronizeAfterTinycastPasteboardMutation(changeCount: Int) {}
    func pauseCapture() {}
    func resumeCapture() {}
}

enum Permissions {
    @discardableResult
    static func ensureAccessibility() -> Bool { false }
    static func isAccessibilityTrusted() -> Bool { false }
}

@MainActor
enum Paster {
    static let tinycastEventTag: Int64 = 0x54494E59
    static var copies: [String] = []
    static func copyPlainText(_ text: String) { copies.append(text) }
    static func postCommandV(toPid pid: pid_t? = nil) {}
    static func postCommandC(toPid pid: pid_t? = nil) {}
}

enum DialogTone { case danger }
