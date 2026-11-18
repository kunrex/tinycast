import AppKit
import Carbon.HIToolbox
import Synchronization

private func commandTabCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<CommandTabTap.Session>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
}

@MainActor
final class CommandTabTap {
    private var session: Session?
    private var consumer: Task<Void, Never>?

    var isInstalled: Bool { session?.isInstalled == true }

    isolated deinit {
        session?.stop(drain: false)
        consumer?.cancel()
    }

    @discardableResult
    func install(onIntent: @escaping @MainActor (CommandTabEngine.Intent) -> Void) -> Bool {
        if session?.resume() == true { return true }
        stop(drain: false)
        let (stream, continuation) = AsyncStream<Session.Message>.makeStream()
        guard let session = Session(continuation: continuation, onStop: { [weak self] session, token in
            Task { @MainActor [weak self, weak session] in
                guard let self, let session, self.session === session,
                    session.isStopped(token) else { return }
                self.session = nil
                self.consumer?.cancel()
                self.consumer = nil
            }
        }) else { return false }
        self.session = session
        // One consumer preserves down/repeat/release order even when opening performs a slow AX sweep.
        consumer = Task { @MainActor [weak session] in
            for await message in stream {
                guard !Task.isCancelled, session?.accepts(message.generation) == true else { continue }
                onIntent(message.intent)
            }
        }
        return true
    }

    func cancelGesture() {
        session?.cancelGesture()
    }

    func stop(drain: Bool = true) {
        session?.stop(drain: drain)
        if !drain {
            session = nil
            consumer?.cancel()
            consumer = nil
        }
    }

    fileprivate final class Session: Sendable {
        struct Message: Sendable {
            let generation: UInt64
            let intent: CommandTabEngine.Intent
        }
        // Core Foundation permits cross-thread teardown; only the worker serves this run loop.
        private struct Installation: @unchecked Sendable {
            let port: CFMachPort
            let source: CFRunLoopSource
            var runLoop: CFRunLoop?
        }
        private struct State {
            var engine = CommandTabEngine()
            var running = true
            var capturing = true
            var drainToken: UInt64 = 0
            var installation: Installation?
        }
        private let state = Mutex(State())
        private let continuation: AsyncStream<Message>.Continuation
        private let onStop: @Sendable (Session, UInt64) -> Void

        init?(
            continuation: AsyncStream<Message>.Continuation,
            onStop: @escaping @Sendable (Session, UInt64) -> Void
        ) {
            self.continuation = continuation
            self.onStop = onStop
            let events: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
            guard let port = CGEvent.tapCreate(
                tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: events, callback: commandTabCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
            else { continuation.finish(); return nil }
            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
                CFMachPortInvalidate(port)
                continuation.finish()
                return nil
            }
            state.withLock { $0.installation = Installation(port: port, source: source) }
            let thread = Thread { [self] in run() }
            thread.name = "com.tinycast.command-tab"
            thread.qualityOfService = .userInteractive
            thread.start()
        }

        var isInstalled: Bool {
            state.withLock { state in
                guard state.running, let installation = state.installation else { return false }
                return CFMachPortIsValid(installation.port)
                    && CFRunLoopSourceIsValid(installation.source)
                    && CGEvent.tapIsEnabled(tap: installation.port)
            }
        }

        func resume() -> Bool {
            guard isInstalled else { return false }
            return state.withLock { state in
                guard state.running else { return false }
                state.capturing = true
                state.drainToken &+= 1
                return true
            }
        }

        func isStopped(_ token: UInt64) -> Bool {
            state.withLock { !$0.running && !$0.capturing && $0.drainToken == token }
        }

        func accepts(_ generation: UInt64) -> Bool {
            state.withLock { $0.running && $0.capturing && $0.engine.generation == generation }
        }

        func cancelGesture() {
            state.withLock { $0.engine.cancel() }
        }

        func stop(drain: Bool = true) {
            let token = state.withLock { state -> UInt64? in
                guard drain, state.running, state.engine.hasOwnedPress else {
                    tearDown(&state)
                    return nil
                }
                guard state.capturing else { return nil }
                state.capturing = false
                state.engine.cancel()
                state.drainToken &+= 1
                return state.drainToken
            }
            if let token {
                // Bound a missing OS release; resumed capture invalidates this deadline.
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.expireDrain(token)
                }
                return
            }
        }

        private func expireDrain(_ token: UInt64) {
            state.withLock { state in
                guard !state.capturing, state.drainToken == token else { return }
                tearDown(&state)
            }
        }

        private func tearDown(_ state: inout State) {
            guard state.running else { return }
            state.running = false
            state.capturing = false
            state.drainToken &+= 1
            state.engine.cancel()
            continuation.finish()
            onStop(self, state.drainToken)
            guard let installation = state.installation else { return }
            CGEvent.tapEnable(tap: installation.port, enable: false)
            guard let runLoop = installation.runLoop else { return }
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(runLoop)
        }

        private func run() {
            autoreleasepool {
                guard let installation = state.withLock({ $0.installation }),
                    let runLoop = CFRunLoopGetCurrent() else { return }
                let port = installation.port
                let source = installation.source
                defer { CFMachPortInvalidate(port) }
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                defer { CFRunLoopRemoveSource(runLoop, source, .defaultMode) }
                let running = state.withLock { state in
                    state.installation?.runLoop = runLoop
                    return state.running
                }
                if running { CFRunLoopRun() }
            }
        }

        func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
            let unchanged = Unmanaged.passUnretained(event)
            let input: CommandTabEngine.Input
            switch type {
            case .keyDown: input = .down
            case .keyUp: input = .up
            case .flagsChanged: input = .flags
            case .tapDisabledByTimeout, .tapDisabledByUserInput: input = .disabled
            default: return unchanged
            }
            let tag = event.getIntegerValueField(.eventSourceUserData)
            let available = !IsSecureEventInputEnabled() && AXIsProcessTrusted()
            let suppress = state.withLock { state in
                guard state.running else { return false }
                let result = state.engine.handle(
                    input, keyCode: Int(event.getIntegerValueField(.keyboardEventKeycode)),
                    flags: event.flags.rawValue, available: available && state.capturing,
                    isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                    synthetic: tag == HyperKeyTap.syntheticTag || tag == Paster.tinycastEventTag)
                if input == .disabled, let port = state.installation?.port {
                    CGEvent.tapEnable(tap: port, enable: true)
                }
                if let intent = result.intent {
                    continuation.yield(Message(generation: state.engine.generation, intent: intent))
                }
                if !state.capturing, !state.engine.hasOwnedPress { tearDown(&state) }
                return result.suppress
            }
            return suppress ? nil : unchanged
        }
    }
}
