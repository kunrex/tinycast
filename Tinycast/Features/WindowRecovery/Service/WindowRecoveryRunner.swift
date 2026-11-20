// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

/// Restores recorded windows on request; lifecycle and scheduling belong to the caller.
@MainActor
enum WindowRecoveryRunner {
    @discardableResult
    static func returnParkedWindows(ledger: RoomParkingLedger) -> Int {
        guard AXIsProcessTrusted(), !ledger.isEmpty else { return 0 }
        let geometry = AXGeometry(screens: NSScreen.screens)
        let windows = WindowRecoverySweep.windows()
        let screens = AXScreens.recoveryFrames(geometry: geometry)
        let returned = windows.compactMap {
            restore(windowID: $0.windowID, bundleID: $0.bundleID, window: $0.window,
                    application: $0.application, screens: screens, ledger: ledger)
        }
        ledger.forget(returned)
        // A quit app's windows went with it; a running but slow app keeps its way back.
        ledger.keepOnly(
            bundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)))
        return returned.count
    }

    static func restore(
        windowID: UInt32?, bundleID: String, window: AXUIElement, application: AXUIElement,
        screens: [CGRect], ledger: RoomParkingLedger
    ) -> UInt32? {
        guard let windowID, let entry = ledger.entry(for: windowID),
            WindowRecoveryPolicy.matches(windowID: windowID, bundleID: bundleID, entry: entry)
        else { return nil }
        let home = WindowRecoveryPolicy.returnFrame(for: entry.frame, screens: screens)
        let restore = AXWindowAccess.suppressEnhancedUserInterface(on: application)
        defer { restore() }
        write(home, to: window)
        guard let now = AXWindowAccess.frame(of: window),
            WindowRecoveryPolicy.isReturned(now, to: home)
        else { return nil }
        return windowID
    }

    /// Restore only: top-leading, no canvas or placement-command anchoring.
    private static func write(_ target: CGRect, to window: AXUIElement) {
        AXUIElementSetMessagingTimeout(window, AXWindowAccess.messagingTimeout)
        if AXWindowAccess.bool(window, kAXMinimizedAttribute) == true {
            _ = AXWindowAccess.unminimize(window)
        }
        guard AXWindowAccess.isSettable(kAXPositionAttribute, on: window),
            let current = AXWindowAccess.frame(of: window)
        else { return }
        guard AXWindowAccess.isSettable(kAXSizeAttribute, on: window) else {
            let slot = CGRect(origin: target.origin, size: current.size)
            _ = AXWindowAccess.setPosition(WindowRecoveryPolicy.rounded(slot).origin, on: window)
            return
        }
        _ = AXWindowAccess.setSize(target.size, on: window)
        guard AXWindowAccess.setPosition(target.origin, on: window) else {
            _ = AXWindowAccess.setSize(current.size, on: window)
            return
        }
        _ = AXWindowAccess.setSize(target.size, on: window)
        guard var actual = AXWindowAccess.frame(of: window) else { return }
        if abs(actual.minX - target.minX) > 2 || abs(actual.minY - target.minY) > 2 {
            _ = AXWindowAccess.setPosition(target.origin, on: window)
            actual = AXWindowAccess.frame(of: window) ?? actual
        }
        if actual.width > target.width + 2 || actual.height > target.height + 2 {
            let slot = CGRect(origin: target.origin, size: actual.size)
            _ = AXWindowAccess.setPosition(WindowRecoveryPolicy.rounded(slot).origin, on: window)
        }
    }
}
