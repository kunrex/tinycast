import AppKit
import Carbon.HIToolbox

@MainActor
final class WindowSwitchCoordinator: HealthCheckable {
    private let settings: AppSettings
    private let appIndex: AppIndex
    private let session: WindowSwitchSession
    private let palette: PaletteState
    private let paletteCoordinator: PaletteCoordinator
    private unowned let core: AppCore
    /// Armed by a repeat press with its modifiers held: letting go switches, as ⌘Tab does.
    private var releaseMonitor: Any?
    private let nativeTap = CommandTabTap()
    /// Survives Command release so only a native-opened picker claims plain Tab.
    private var nativeSession: UUID?
    private var nativeSearchMonitor: Any?
    private var observers: [NotificationToken] = []
    private var darwinObservers: [DarwinNotificationToken] = []
    private var pauseReasons: Set<String> = []
    private var nativeProblem: String?
    weak var healthTicker: HealthTicker?
    private static let chordModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    init(
        settings: AppSettings, appIndex: AppIndex, session: WindowSwitchSession,
        palette: PaletteState, paletteCoordinator: PaletteCoordinator, core: AppCore
    ) {
        self.settings = settings
        self.appIndex = appIndex
        self.session = session
        self.palette = palette
        self.paletteCoordinator = paletteCoordinator
        self.core = core
    }

    func start() {
        session.onReset = { [weak self] in
            guard let self else { return }
            self.cancelNativeGesture()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        for (center, name, reason, paused) in [
            (workspace, NSWorkspace.willSleepNotification, "sleep", true),
            (workspace, NSWorkspace.didWakeNotification, "sleep", false),
            (workspace, NSWorkspace.sessionDidResignActiveNotification, "session", true),
            (workspace, NSWorkspace.sessionDidBecomeActiveNotification, "session", false),
            (distributed, Notification.Name("com.apple.screenIsLocked"), "lock", true),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), "lock", false)
        ] {
            observers.append(NotificationToken(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in
                        guard let self else { return }
                        if paused { self.pauseReasons.insert(reason) }
                        else { self.pauseReasons.remove(reason) }
                        self.applyNativeSwitching()
                    }
                }, center: center))
        }
        darwinObservers = [
            DarwinNotificationToken("com.apple.coregraphics.eventTapRemoved") { [weak self] in
                self?.recoverNativeTap()
            },
            DarwinNotificationToken("com.apple.tcc.access.changed") { [weak self] in
                guard let self else { return }
                self.stopNativeSwitching()
                self.healthTicker?.subscribe(self)
            }
        ]
        applyNativeSwitching()
    }

    func setMimicsMacOS(_ enabled: Bool) {
        if enabled { _ = Permissions.ensureAccessibility() }
        settings.navigationMimicsMacOS = enabled
        applyNativeSwitching()
    }

    func healthCheck() { applyNativeSwitching() }

    private func recoverNativeTap() {
        guard settings.navigationEnabled, settings.navigationMimicsMacOS,
            core.hotKeys.recordingAction == nil, pauseReasons.isEmpty,
            !core.secureInput.isActive, !nativeTap.isInstalled else { return }
        stopNativeSwitching()
        applyNativeSwitching()
    }

    func applyNativeSwitching() {
        let wanted = settings.navigationEnabled && settings.navigationMimicsMacOS
        core.hotKeys.navigationMimicsMacOS = wanted
        guard wanted, core.hotKeys.recordingAction == nil, pauseReasons.isEmpty,
            !core.secureInput.isActive else {
            stopNativeSwitching()
            healthTicker?.unsubscribe(self)
            return
        }
        guard Permissions.isAccessibilityTrusted() else {
            stopNativeSwitching()
            reportNativeProblem(String(localized: "Mimic macOS needs Accessibility access"))
            healthTicker?.subscribe(self)
            return
        }
        guard nativeTap.install(onIntent: { [weak self] in self?.handleNative($0) }) else {
            reportNativeProblem(String(localized: "Couldn’t replace Command-Tab. macOS switching is still available."))
            healthTicker?.subscribe(self)
            return
        }
        nativeProblem = nil
        healthTicker?.unsubscribe(self)
    }

    private func reportNativeProblem(_ message: String) {
        guard nativeProblem != message else { return }
        nativeProblem = message
        core.showMessage(message, tone: .danger)
    }

    private func cancelNativeGesture() {
        disarmNativeSearch()
        nativeSession = nil
        nativeTap.cancelGesture()
    }

    func prepareForTermination() {
        stopNativeSwitching()
        nativeTap.stop(drain: false)
        healthTicker?.unsubscribe(self)
        observers = []
        darwinObservers = []
    }

    private func stopNativeSwitching() {
        cancelNativeGesture()
        nativeTap.stop()
        disarmSwitchOnRelease()
    }

    private func handleNative(_ intent: CommandTabEngine.Intent) {
        if intent == .cancel {
            nativeSession = nil
            disarmNativeSearch()
            return
        }
        guard settings.navigationEnabled, settings.navigationMimicsMacOS,
            core.hotKeys.recordingAction == nil, Permissions.isAccessibilityTrusted(),
            !core.secureInput.isActive, !IsSecureEventInputEnabled() else { return }
        switch intent {
        case .cancel: break
        case .step(let backwards, let first):
            if first {
                disarmSwitchOnRelease()
                if !paletteCoordinator.isShowing(.switchWindows) {
                    paletteCoordinator.showPalette(mode: .switchWindows, seeding: "")
                    palette.selection = 0
                }
                nativeSession = session.identity
                armNativeSearch()
            }
            guard nativeSession == session.identity,
                paletteCoordinator.isShowing(.switchWindows) else { return }
            filterQuery()
            step(by: backwards ? -1 : 1, native: true)
        case .release:
            disarmNativeSearch()
        }
    }

    func cycleNativePicker(backwards: Bool) -> Bool {
        guard nativeSession == session.identity,
            paletteCoordinator.isShowing(.switchWindows) else { return false }
        filterQuery()
        step(by: backwards ? -1 : 1, native: true)
        return true
    }

    func filterQuery() {
        // A step can arrive before SwiftUI forwards the latest query to the session.
        if session.filter(palette.query) { palette.selection = 0 }
    }

    private func armNativeSearch() {
        guard nativeSearchMonitor == nil else { return }
        nativeSearchMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.nativeSession == self.session.identity,
                self.paletteCoordinator.isShowing(.switchWindows),
                self.paletteCoordinator.anchorView?.window?.isKeyWindow == true,
                event.modifierFlags.intersection([.command, .control, .option, .function]) == .command,
                let text = event.charactersIgnoringModifiers,
                text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }),
                !text.isEmpty
            else { return event }
            return NSEvent.keyEvent(
                with: .keyDown, location: event.locationInWindow,
                modifierFlags: event.modifierFlags.subtracting(.command), timestamp: event.timestamp,
                windowNumber: event.windowNumber, context: nil, characters: text,
                charactersIgnoringModifiers: text, isARepeat: event.isARepeat, keyCode: event.keyCode)
                ?? event
        }
    }

    private func disarmNativeSearch() {
        if let nativeSearchMonitor { NSEvent.removeMonitor(nativeSearchMonitor) }
        nativeSearchMonitor = nil
    }

    func applyEnabled() {
        appIndex.setCommandsVisible(
            [.switchWindows, .switchWindowsBackwards], settings.navigationEnabled)
        applyNativeSwitching()
        guard !settings.navigationEnabled else { return }
        session.reset()
        if palette.mode == .switchWindows { palette.prepare(mode: .launcher) }
    }

    func show(backwards: Bool = false) {
        guard settings.navigationEnabled, hasAccessibility() else { return }
        cancelNativeGesture()
        if paletteCoordinator.isShowing(.switchWindows) { return step(by: backwards ? -1 : 1) }
        disarmSwitchOnRelease()
        paletteCoordinator.togglePalette(mode: .switchWindows)
    }

    /// A link's text filters the list it opens; there is no held chord to switch on release.
    func show(query: String) {
        guard settings.navigationEnabled, hasAccessibility() else { return }
        cancelNativeGesture()
        disarmSwitchOnRelease()
        paletteCoordinator.togglePalette(mode: .switchWindows, seeding: query)
    }

    /// The first step lands on the window behind the current one, which the list opens on.
    private func step(by offset: Int, native: Bool = false) {
        let count = session.filtered.count
        guard count > 0 else { return }
        palette.selection = (palette.selection + offset + count) % count
        palette.followToken = UUID()
        if native { session.nativeLandingSelection = palette.selection }
        else { armSwitchOnRelease() }
    }

    /// A single press still searches: only a held chord, stepped again, switches on release.
    private func armSwitchOnRelease() {
        let held = NSEvent.modifierFlags.intersection(Self.chordModifiers)
        guard !held.isEmpty, releaseMonitor == nil else { return }
        releaseMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] in
            let event = $0
            guard let self, event.modifierFlags.isDisjoint(with: held) else { return event }
            self.switchOnRelease()
            return event
        }
    }

    private func disarmSwitchOnRelease() {
        if let releaseMonitor { NSEvent.removeMonitor(releaseMonitor) }
        releaseMonitor = nil
    }

    private func switchOnRelease() {
        disarmSwitchOnRelease()
        let rows = session.filtered
        guard paletteCoordinator.isShowing(.switchWindows), rows.indices.contains(palette.selection)
        else { return }
        activate(rows[palette.selection])
    }

    /// Every open sweeps anew, a restore included: hiding dropped the last snapshot.
    func load() {
        guard hasAccessibility() else { return }
        session.present(WindowSwitchSweep.snapshot(ranks: WindowZOrder.appRanks()))
    }

    func activate(_ entry: WindowSwitchEntry) {
        guard hasAccessibility() else { return }
        // Resolved before the hide: hiding resets the session, which drops the element table.
        guard let element = liveElement(for: entry) else {
            Task { await self.reportGone(entry) }
            return
        }
        // Restoring focus reactivates the displaced app, which races the raise below.
        paletteCoordinator.hidePalette(restoreFocus: false)
        if entry.isMinimized { _ = AXWindowAccess.unminimize(element.window) }
        AXWindowAccess.focus(element.window, in: element.application, of: element.app)
    }

    /// A full-screen window can't minimize, so its row must not join the minimized ones.
    func minimize(_ entry: WindowSwitchEntry) {
        guard !entry.isMinimized, hasAccessibility(), let element = liveElement(for: entry),
            !AXWindowAccess.isFullScreen(element.window), AXWindowAccess.minimize(element.window)
        else { return }
        session.markMinimized(entry.handle)
    }

    func hideApplication(_ entry: WindowSwitchEntry) {
        guard hasAccessibility(), let element = liveElement(for: entry) else { return }
        // Restoring focus would reactivate, and so unhide, an app hidden from in front.
        paletteCoordinator.hidePalette(restoreFocus: false)
        if !element.app.hide() {
            AXWindowAccess.setHidden(true, application: element.application)
        }
    }

    /// Rows leave when the app exits, so a quit refused by a save sheet keeps them.
    func quitApplication(_ entry: WindowSwitchEntry) {
        liveElement(for: entry)?.app.terminate()
    }

    private func liveElement(for entry: WindowSwitchEntry) -> WindowSwitchSweep.Element? {
        guard let element = session.element(for: entry.handle), !element.app.isTerminated
        else { return nil }
        return element
    }

    private func hasAccessibility() -> Bool {
        guard Permissions.ensureAccessibility() else {
            Task { await self.reportPermissionFailure() }
            return false
        }
        return true
    }

    // MARK: - Reporting

    private func reportPermissionFailure() async {
        let openSettings = await core.reportFailure(
            title: String(localized: "Tinycast Needs Accessibility Access"),
            message: String(localized: "Switching windows reads and raises other apps' windows."),
            symbol: "macwindow.on.rectangle", recovery: String(localized: "Open Settings"))
        if openSettings { Permissions.openAccessibilitySettings() }
    }

    private func reportGone(_ entry: WindowSwitchEntry) async {
        await core.showNotice(
            title: String(localized: "Couldn’t Switch to “\(entry.displayTitle)”"),
            message: String(localized: "It closed before the switch landed. Search again and retry."),
            symbol: "macwindow.on.rectangle", tone: .danger)
    }
}
