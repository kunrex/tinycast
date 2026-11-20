import AppKit

func IsSecureEventInputEnabled() -> Bool { false }

@MainActor @Observable final class AppSettings {
    var navigationEnabled = true
    var navigationMimicsMacOS = false
}
enum CommandID { case switchWindows, switchWindowsBackwards }
@MainActor final class AppIndex {
    func setCommandsVisible(_ commands: [CommandID], _ visible: Bool) {}
}
struct WindowSwitchEntry {
    let handle: Int
    var isMinimized = false
    var displayTitle: String { "Window" }
}
@MainActor final class NSRunningApplication {
    static let current = NSRunningApplication()
    var isTerminated = false
    var processIdentifier: pid_t { 0 }
    func hide() -> Bool { true }
    @discardableResult func terminate() -> Bool { true }
}
@MainActor enum WindowSwitchSweep {
    @MainActor struct Element {
        let window = AXUIElementCreateSystemWide()
        let application = AXUIElementCreateSystemWide()
        let app = NSRunningApplication.current
    }
    struct Snapshot {
        var entries: [WindowSwitchEntry]
        var elements: [Int: Element]
    }
    static func snapshot(ranks: [Int]) -> Snapshot {
        Snapshot(entries: (0..<3).map { WindowSwitchEntry(handle: $0) },
                 elements: Dictionary(uniqueKeysWithValues: (0..<3).map { ($0, Element()) }))
    }
}
enum WindowZOrder { static func appRanks() -> [Int] { [] } }
enum WindowSwitchOrder {
    static func sorted(_ entries: [WindowSwitchEntry]) -> [WindowSwitchEntry] { entries }
}
enum WindowSwitchQuery {
    static func rank(_ entries: [WindowSwitchEntry], for query: String) -> [WindowSwitchEntry] {
        query == "third" ? entries.filter { $0.handle == 2 } : entries
    }
}
enum PaletteMode { case launcher, switchWindows }
@MainActor final class PaletteState {
    var mode = PaletteMode.launcher
    var selection = 0
    var query = ""
    var followToken = UUID()
    func prepare(mode: PaletteMode) { self.mode = mode }
}
@MainActor final class PaletteCoordinator {
    let palette: PaletteState
    let session: WindowSwitchSession
    var visible = false
    var opens = 0
    var onOpen: (() -> Void)?
    var anchorView: NSView? { nil }
    init(palette: PaletteState, session: WindowSwitchSession) {
        self.palette = palette; self.session = session
    }
    func isShowing(_ mode: PaletteMode) -> Bool { visible && palette.mode == mode }
    func togglePalette(mode: PaletteMode, seeding: String? = nil) {
        if isShowing(mode), seeding == nil { hidePalette() }
        else { showPalette(mode: mode, seeding: seeding) }
    }
    func showPalette(mode: PaletteMode, seeding: String? = nil) {
        visible = true; palette.mode = mode; palette.selection = 0
        palette.query = seeding ?? ""; opens += 1; onOpen?()
    }
    func hidePalette(restoreFocus: Bool = true) { visible = false; session.reset() }
}
@MainActor enum AXWindowAccess {
    static var focuses = 0
    static func unminimize(_ window: AXUIElement) -> Bool { true }
    static func minimize(_ window: AXUIElement) -> Bool { true }
    static func isFullScreen(_ window: AXUIElement) -> Bool { false }
    static func setHidden(_ hidden: Bool, application: AXUIElement) {}
    static func focus(_ window: AXUIElement, in application: AXUIElement, of app: NSRunningApplication) { focuses += 1 }
}
@MainActor enum Permissions {
    static var trusted = true
    static var prompts = 0
    static func isAccessibilityTrusted() -> Bool { trusted }
    static func ensureAccessibility() -> Bool { prompts += 1; return trusted }
    static func openAccessibilitySettings() {}
}
@MainActor final class CommandTabTap {
    static weak var current: CommandTabTap?
    var handler: ((CommandTabEngine.Intent) -> Void)?
    var installs = 0
    var stops = 0
    var cancellations = 0
    var isInstalled = false
    var draining = false
    var fails = false
    init() { Self.current = self }
    func install(onIntent: @escaping @MainActor (CommandTabEngine.Intent) -> Void) -> Bool {
        installs += 1
        if fails { return false }
        isInstalled = true
        handler = onIntent; return true
    }
    func stop(drain: Bool = true) {
        stops += 1; handler = nil
        if !drain || !draining { isInstalled = false }
    }
    func cancelGesture() { cancellations += 1 }
}
@MainActor final class HotKeyManager {
    var navigationMimicsMacOS = false
    var recordingAction: Int?
}
@MainActor final class SecureInputMonitor { var isActive = false }
@MainActor protocol HealthCheckable: AnyObject { func healthCheck() }
@MainActor final class HealthTicker {
    func subscribe(_ value: any HealthCheckable) {}
    func unsubscribe(_ value: any HealthCheckable) {}
}
@MainActor final class DarwinNotificationToken {
    static var handlers: [String: @MainActor () -> Void] = [:]
    init(_ name: String, handler: @escaping @MainActor () -> Void) { Self.handlers[name] = handler }
    static func post(_ name: String) { handlers[name]?() }
}
enum DialogTone { case danger }
@MainActor final class AppCore {
    let hotKeys = HotKeyManager()
    let secureInput = SecureInputMonitor()
    var messages: [String] = []
    func showMessage(_ message: String, tone: DialogTone) { messages.append(message) }
    func reportFailure(title: String, message: String, symbol: String, recovery: String) async -> Bool { false }
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {}
}
