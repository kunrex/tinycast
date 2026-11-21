import AppKit
import SwiftUI

@MainActor protocol PaletteScreen {
    func activate(at selection: Int)
    func tab(at selection: Int, backwards: Bool) -> Bool
}
struct ScrollIntent {}
enum PaletteShortcut { case minimizeWindow, hideApp, quit, other }
struct PopoverMenuItem {
    init(title: String, systemImage: String, startsSection: Bool = false,
         shortcut: String, action: @escaping () -> Void) {}
}
struct PopoverMenuContent {
    let header: String
    let items: [PopoverMenuItem]
}
struct EmptyResults: View {
    let text: String
    var body: some View { EmptyView() }
}
struct WindowSwitchList: View {
    let entries: [WindowSwitchEntry]
    let selectedID: Int?
    let scroll: ScrollIntent
    let onActivate: (WindowSwitchEntry) -> Void
    var body: some View { EmptyView() }
}

func IsSecureEventInputEnabled() -> Bool { false }

@MainActor private final class EventMonitor {
    static var held: NSEvent.ModifierFlags = []
    static var monitors: [EventMonitor] = []
    let mask: NSEvent.EventTypeMask
    let handler: (NSEvent) -> NSEvent?
    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?) {
        self.mask = mask
        self.handler = handler
    }
}
extension NSEvent {
    var modifierFlags: ModifierFlags { ModifierFlags(rawValue: UInt(cgEvent?.flags.rawValue ?? 0)) }
    @MainActor static var modifierFlags: ModifierFlags { EventMonitor.held }
    @MainActor static func addLocalMonitorForEvents(
        matching mask: EventTypeMask, handler: @escaping (NSEvent) -> NSEvent?
    ) -> Any? {
        let monitor = EventMonitor(mask: mask, handler: handler)
        EventMonitor.monitors.append(monitor)
        return monitor
    }
    @MainActor static func removeMonitor(_ monitor: Any) {
        EventMonitor.monitors.removeAll { $0 === monitor as? EventMonitor }
    }
    @MainActor static func holdForTest(_ flags: ModifierFlags) { EventMonitor.held = flags }
    @MainActor static func releaseForTest() {
        EventMonitor.held = []
        let event = NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 55)!
        for monitor in EventMonitor.monitors where monitor.mask.contains(.flagsChanged) {
            _ = monitor.handler(event)
        }
    }
}

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
    var id: Int { handle }
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
    private var coordinator: WindowSwitchCoordinator?
    var windowSwitchCoordinator: WindowSwitchCoordinator {
        get { coordinator! }
        set { coordinator = newValue }
    }
    let hotKeys = HotKeyManager()
    let secureInput = SecureInputMonitor()
    var messages: [String] = []
    func showMessage(_ message: String, tone: DialogTone) { messages.append(message) }
    func reportFailure(title: String, message: String, symbol: String, recovery: String) async -> Bool { false }
    func showNotice(title: String, message: String, symbol: String, tone: DialogTone) async {}
}
