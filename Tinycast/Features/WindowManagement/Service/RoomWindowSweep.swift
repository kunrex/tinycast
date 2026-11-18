// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

/// Reads every window a room can hold, once: minimized ones and hidden apps' windows included.
@MainActor
enum RoomWindowSweep {
    private static let normalLayer = 0

    struct Snapshot {
        var screens: [WindowLayoutScreen]
        /// `handle` is the index into this array, and the key into `elements`.
        var windows: [RoomLiveWindow]
        var elements: [Int: WindowInventory.Element]

        func window(_ handle: Int) -> RoomLiveWindow? {
            windows.indices.contains(handle) ? windows[handle] : nil
        }

        /// The display a room lands on; the first one when that display is gone.
        func screen(uuid: String?) -> WindowLayoutScreen? {
            let uuid = uuid?.lowercased()
            return screens.first { $0.display.uuid == uuid } ?? screens.first
        }
    }

    static func snapshot() -> Snapshot {
        let geometry = AXGeometry(screens: NSScreen.screens)
        let ranks = frontRanks()
        var windows: [RoomLiveWindow] = []
        var elements: [Int: WindowInventory.Element] = [:]
        for window in WindowRecoverySweep.windows() {
            let handle = windows.count
            windows.append(RoomLiveWindow(
                handle: handle, bundleID: window.bundleID,
                appName: window.app.localizedName ?? window.bundleID, title: window.title,
                windowID: window.windowID, frame: window.frame, isMinimized: window.isMinimized,
                isAppHidden: window.app.isHidden,
                frontRank: window.windowID.flatMap { ranks[$0] } ?? .max,
                appURL: window.app.bundleURL))
            elements[handle] = WindowInventory.Element(
                bundleID: window.bundleID, app: window.app,
                application: window.application, window: window.window)
        }
        return Snapshot(
            screens: AXScreens.layoutScreens(geometry: geometry), windows: windows,
            elements: elements)
    }

    /// Front-to-back by window number. Titles are never read, so no Screen Recording grant.
    private static func frontRanks() -> [UInt32: Int] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let listing = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var ranks: [UInt32: Int] = [:]
        for window in listing where window[kCGWindowLayer as String] as? Int == normalLayer {
            guard let number = window[kCGWindowNumber as String] as? UInt32 else { continue }
            ranks[number] = ranks.count
        }
        return ranks
    }
}
