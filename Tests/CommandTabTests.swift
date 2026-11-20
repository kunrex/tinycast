import AppKit
import Carbon.HIToolbox
import Synchronization

// Private ports and unposted events exercise the shipped tap without capturing the user's keys.
private struct TapRecord: @unchecked Sendable {
    let port: CFMachPort
    let callback: CGEventTapCallBack
    let context: UnsafeMutableRawPointer?
}
private struct Fixture {
    var records: [TapRecord] = []
    var fail = false
    var secure = false
    var trusted = true
    var enables = 0
}
enum HyperKeyTap { static let syntheticTag: Int64 = 0x5459_4354 }
enum Paster { static let tinycastEventTag: Int64 = 0x5449_4E59 }
private let fixture = Mutex(Fixture())
func AXIsProcessTrusted() -> Bool { fixture.withLock { $0.trusted } }
func IsSecureEventInputEnabled() -> Bool { fixture.withLock { $0.secure } }
extension CGEvent {
    static func tapCreate(
        tap: CGEventTapLocation, place: CGEventTapPlacement, options: CGEventTapOptions,
        eventsOfInterest: CGEventMask, callback: CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        if fixture.withLock({ $0.fail }) { return nil }
        var context = CFMachPortContext()
        let port = CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil)!
        fixture.withLock { $0.records.append(TapRecord(port: port, callback: callback, context: userInfo)) }
        return port
    }
    static func tapIsEnabled(tap: CFMachPort) -> Bool { CFMachPortIsValid(tap) }
    static func tapEnable(tap: CFMachPort, enable: Bool) {
        if enable { fixture.withLock { $0.enables += 1 } }
    }
}

@main
@MainActor
struct CommandTabTests {
    static var checks = 0
    static var failures = 0
    static func check(_ condition: Bool, _ name: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(name)") }
    }
    static func settle() async { try? await Task.sleep(for: .milliseconds(30)) }

    static func engine() {
        let command = CommandTabEngine.command
        let shift = CommandTabEngine.shift
        var engine = CommandTabEngine()
        for extra in [UInt64(1 << 18), 1 << 19, 1 << 23] {
            check(!engine.handle(.down, keyCode: 48, flags: command | extra).suppress, "unrelated modifier passes")
            check(!engine.handle(.up, keyCode: 48, flags: command | extra).suppress, "unclaimed up passes")
        }
        check(!engine.handle(.down, keyCode: 0, flags: command).suppress, "non-Tab passes")
        check(!engine.handle(.down, keyCode: 48, flags: 0).suppress, "bare Tab passes")
        _ = engine.handle(.up, keyCode: 48, flags: 0)
        check(
            engine.handle(.down, keyCode: 48, flags: command).intent == .step(backwards: false, first: true),
            "first native press steps")
        check(
            engine.handle(.down, keyCode: 48, flags: command | shift, isAutorepeat: true).intent == .step(backwards: true, first: false),
            "repeat reverses")
        check(engine.handle(.flags, keyCode: 56, flags: command).intent == nil, "Shift release does not commit")
        check(engine.handle(.flags, keyCode: 55, flags: shift).intent == .commit, "Command release commits with Shift held")
        check(engine.handle(.up, keyCode: 48, flags: shift).suppress, "paired up swallowed despite changed flags")
        check(!engine.handle(.up, keyCode: 48, flags: shift).suppress, "up consumed only once")
        _ = engine.handle(.down, keyCode: 48, flags: command)
        let generation = engine.generation
        engine.cancel()
        check(engine.generation != generation, "recording/toggle cancellation invalidates queued intents")
        check(engine.handle(.flags, keyCode: 55, flags: 0).intent == nil, "cancelled release cannot commit")
        check(engine.handle(.up, keyCode: 48, flags: 0).suppress, "cancellation retains down/up pairing")
        _ = engine.handle(.down, keyCode: 48, flags: command)
        let fallback = engine.handle(.up, keyCode: 48, flags: shift)
        check(fallback.suppress && fallback.intent == .commit, "key-event release fallback")
        _ = engine.handle(.down, keyCode: 48, flags: command)
        _ = engine.handle(.disabled, keyCode: 0, flags: 0)
        check(engine.handle(.flags, keyCode: 55, flags: 0).intent == nil, "system disable cancels commit")
        check(
            !engine.handle(.down, keyCode: 48, flags: command, available: false).suppress,
            "Secure Input and revoked permissions fail open")
        check(!engine.handle(.down, keyCode: 48, flags: command, synthetic: true).suppress, "synthetics pass")
        for extra in [UInt64(0), 1 << 18, 1 << 19, 1 << 23] {
            var passed = CommandTabEngine()
            _ = passed.handle(.down, keyCode: 48, flags: extra)
            let repeatEvent = passed.handle(.down, keyCode: 48, flags: command, isAutorepeat: true)
            check(!repeatEvent.suppress && repeatEvent.intent == nil, "passed press cannot be acquired")
            check(!passed.handle(.up, keyCode: 48, flags: command).suppress, "passed press releases")
            var owned = CommandTabEngine()
            _ = owned.handle(.down, keyCode: 48, flags: command)
            check(owned.handle(.down, keyCode: 48, flags: extra, isAutorepeat: true).suppress,
                  "owned repeats stay suppressed across modifier changes")
            check(owned.handle(.up, keyCode: 48, flags: extra).suppress, "owned press releases")
        }
        var orphan = CommandTabEngine()
        check(!orphan.handle(.down, keyCode: 48, flags: command, isAutorepeat: true).suppress,
              "repeat without initial down passes")
    }

    static func deliver(
        _ index: Int, _ type: CGEventType, flags: CGEventFlags = .maskCommand,
        autorepeat: Bool = false
    ) -> Bool {
        let record = fixture.withLock { $0.records[index] }
        let result = Mutex(false)
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: type == .keyDown)!
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: autorepeat ? 1 : 0)
            let proxy = OpaquePointer(Unmanaged.passUnretained(record.port).toOpaque())
            let swallowed = record.callback(proxy, type, event, record.context) == nil
            result.withLock { $0 = swallowed }
            done.signal()
        }
        check(done.wait(timeout: .now() + 2) == .success, "callback never waits for main")
        return result.withLock { $0 }
    }

    static func ownerIsEmpty(_ tap: CommandTabTap) -> Bool {
        Mirror(reflecting: tap).children
            .filter { $0.label == "session" || $0.label == "consumer" }
            .allSatisfy { Mirror(reflecting: $0.value).children.isEmpty }
    }

    static func sessionObject(_ index: Int) -> AnyObject {
        let context = fixture.withLock { $0.records[index].context! }
        return Unmanaged<AnyObject>.fromOpaque(context).takeUnretainedValue()
    }

    static func ownerCleanup() async {
        let tap = CommandTabTap()
        var index = fixture.withLock { $0.records.count }
        check(tap.install { _ in }, "cleanup fixture installs")
        weak var immediate = sessionObject(index)
        tap.stop()
        await settle()
        check(immediate == nil && ownerIsEmpty(tap), "immediate default stop clears session and consumer")

        index = fixture.withLock { $0.records.count }
        check(tap.install { _ in }, "replacement-race fixture installs")
        weak var replaced = sessionObject(index)
        tap.stop()
        check(tap.install { _ in }, "replace before queued cleanup runs")
        index += 1
        weak var replacement = sessionObject(index)
        await settle()
        check(replaced == nil && replacement != nil && !ownerIsEmpty(tap),
              "old completion cannot clear replacement owner")
        check(deliver(index, .keyDown), "replacement still captures")
        tap.stop()
        check(tap.install { _ in }, "resume before drain completion")
        check(sessionObject(index) === replacement, "resume retains session identity")
        check(deliver(index, .keyUp), "resumed session drains physical release")
        await settle()
        check(replacement != nil && !ownerIsEmpty(tap), "resume prevents owner cleanup")

        // Let the obsolete drain deadline fire while the resumed session is still installed.
        try? await Task.sleep(for: .milliseconds(5200))
        check(replacement != nil && !ownerIsEmpty(tap)
              && fixture.withLock { CFMachPortIsValid($0.records[index].port) },
              "obsolete drain expiry cannot clear resumed session")
        check(deliver(index, .keyDown), "resumed session still captures after old deadline")
        tap.stop()
        check(deliver(index, .keyUp), "drain completion preserves paired release")
        await settle()
        check(replacement == nil && ownerIsEmpty(tap), "drain completion clears session and consumer")
    }

    static func repeatedGestures() async {
        let tap = CommandTabTap()
        let index = fixture.withLock { $0.records.count }
        var intents: [CommandTabEngine.Intent] = []
        check(tap.install { intents.append($0) }, "repeated gesture fixture installs")
        check(tap.isInstalled, "owner forwards installed health")
        for backwards in [false, true, false] {
            let flags: CGEventFlags = backwards ? [.maskCommand, .maskShift] : .maskCommand
            check(deliver(index, .keyDown, flags: flags), "independent gesture captures initial down")
            check(deliver(index, .keyUp, flags: flags), "independent gesture pairs Tab up")
            _ = deliver(index, .flagsChanged, flags: [])
            await settle()
            check(intents == [.step(backwards: backwards, first: true), .commit],
                  "independent gesture delivers fresh step and exactly one commit")
            intents = []
            tap.cancelGesture() // Palette hide/reset must not uninstall or lose the next gesture.
            check(tap.isInstalled && fixture.withLock { $0.records.count } == index + 1,
                  "palette reset retains the same healthy installation")
        }
        CFMachPortInvalidate(fixture.withLock { $0.records[index].port })
        check(!tap.isInstalled, "owner reports genuinely removed port unhealthy")
        tap.stop(drain: false)
        check(!tap.isInstalled, "stopped owner reports unhealthy")
    }

    static func main() async {
        engine()
        let tap = CommandTabTap()
        var intents: [CommandTabEngine.Intent] = []
        check(tap.install { intents.append($0) }, "tap installs")
        check(!deliver(0, .keyDown, flags: []), "bare Tab down passes")
        check(!deliver(0, .keyDown, autorepeat: true), "callback cannot acquire passed autorepeat")
        check(!deliver(0, .keyUp), "passed Tab up passes after Command transition")
        check(deliver(0, .keyDown), "native down intercepted")
        check(deliver(0, .keyDown, flags: [.maskCommand, .maskControl], autorepeat: true),
              "callback suppresses owned invalid-chord repeats")
        check(deliver(0, .keyUp), "matching up intercepted")
        check(deliver(0, .keyDown, flags: [.maskCommand, .maskShift]), "reverse repeat intercepted")
        check(!deliver(0, .flagsChanged, flags: .maskShift), "release passes onward")
        check(intents.isEmpty, "main can remain blocked throughout a quick chord")
        await settle()
        check(
            intents == [.step(backwards: false, first: true), .step(backwards: true, first: false), .commit],
            "single consumer delivers in order")
        _ = deliver(0, .keyDown)
        tap.cancelGesture()
        await settle()
        check(intents.count == 3, "generation drops stale open")
        _ = deliver(0, .keyDown)
        _ = deliver(0, .tapDisabledByTimeout)
        await settle()
        check(
            intents.count == 4 && intents.last == .cancel && fixture.withLock { $0.enables } == 1,
            "timeout cancels queued selection and reenables")
        check(deliver(0, .keyUp), "disabled tap preserves swallowed release")
        _ = deliver(0, .tapDisabledByUserInput)
        check(fixture.withLock { $0.enables } == 2, "user-input disable reenables")
        await settle()
        let beforeStop = intents.count
        fixture.withLock { $0.secure = true }
        check(!deliver(0, .keyDown), "Secure Input native chord passes")
        fixture.withLock { $0.secure = false; $0.trusted = false }
        check(!deliver(0, .keyDown), "revoked grant passes")
        fixture.withLock { $0.trusted = true }
        _ = deliver(0, .keyDown)
        tap.stop()
        check(deliver(0, .keyDown, flags: .maskAlternate, autorepeat: true),
              "drain-only tap suppresses repeats without switching")
        check(deliver(0, .keyUp), "stopped tap drains matching release")
        await settle()
        check(intents.count == beforeStop, "teardown cancels queued activation")
        check(fixture.withLock { !CFMachPortIsValid($0.records[0].port) }, "worker releases its port")
        fixture.withLock { $0.fail = true }
        check(!tap.install { _ in }, "install failure is synchronous")
        fixture.withLock { $0.fail = false }
        check(tap.install { intents.append($0) }, "failed installation can retry")
        _ = deliver(1, .keyDown)
        await settle()
        check(intents.last == .step(backwards: false, first: true), "fresh install has fresh gesture")
        tap.stop()
        check(tap.install { intents.append($0) }, "reapply resumes existing drain")
        check(deliver(1, .keyUp), "resumed session retains owned release")
        await settle()
        check(intents.last == .step(backwards: false, first: true), "resume cannot commit cancelled gesture")
        tap.stop(drain: false)
        check(tap.install { intents.append($0) }, "new tap installs after teardown")
        weak var expired = sessionObject(2)
        _ = deliver(2, .keyDown)
        tap.stop()
        try? await Task.sleep(for: .milliseconds(5200))
        check(fixture.withLock { !CFMachPortIsValid($0.records[2].port) },
              "missing release expires drain and releases worker")
        check(expired == nil && ownerIsEmpty(tap), "drain expiry clears session and consumer")
        tap.stop(drain: false)
        await ownerCleanup()
        await repeatedGestures()
        print("\(checks) Command-Tab checks; \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
