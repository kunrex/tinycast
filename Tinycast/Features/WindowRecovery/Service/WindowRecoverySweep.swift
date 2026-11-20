// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

/// Reads restorable windows, including minimized windows and hidden apps' windows.
@MainActor
enum WindowRecoverySweep {
    private static let sweepTimeout: Float = 0.2
    private static let smallest = CGSize(width: 100, height: 60)

    struct Window {
        let bundleID: String
        let app: NSRunningApplication
        let application: AXUIElement
        let window: AXUIElement
        let windowID: UInt32?
        let title: String
        let frame: CGRect
        let isMinimized: Bool
    }

    static func windows() -> [Window] {
        var result: [Window] = []
        for app in AXWindowAccess.candidates() {
            guard let bundleID = app.bundleIdentifier else { continue }
            let application = AXWindowAccess.application(
                for: app.processIdentifier, timeout: sweepTimeout)
            for window in reportedWindows(of: application, app: app) {
                AXUIElementSetMessagingTimeout(window, sweepTimeout)
                let minimized = AXWindowAccess.bool(window, kAXMinimizedAttribute) == true
                guard isRestorable(window, of: app, minimized: minimized),
                    let frame = AXWindowAccess.frame(of: window),
                    frame.width >= smallest.width, frame.height >= smallest.height
                else { continue }
                result.append(Window(
                    bundleID: bundleID, app: app, application: application, window: window,
                    windowID: AXWindowAccess.windowID(of: window),
                    title: AXWindowAccess.string(window, kAXTitleAttribute) ?? "",
                    frame: frame, isMinimized: minimized))
            }
        }
        return result
    }

    private static func reportedWindows(
        of application: AXUIElement, app: NSRunningApplication
    ) -> [AXUIElement] {
        let windows = AXWindowAccess.windows(in: application)
        guard windows.isEmpty, !app.isHidden else { return windows }
        AXWindowAccess.setManualAccessibility(true, application: application)
        defer { AXWindowAccess.setManualAccessibility(false, application: application) }
        return AXWindowAccess.windows(in: application)
    }

    private static func isRestorable(
        _ window: AXUIElement, of app: NSRunningApplication, minimized: Bool
    ) -> Bool {
        guard !AXWindowAccess.isFullScreen(window) else { return false }
        let subrole = AXWindowAccess.string(window, kAXSubroleAttribute)
        if subrole == (kAXStandardWindowSubrole as String) { return true }
        guard subrole == (kAXDialogSubrole as String) else { return false }
        return app.isHidden || minimized
            || AXWindowAccess.element(window, kAXMinimizeButtonAttribute) != nil
    }
}
