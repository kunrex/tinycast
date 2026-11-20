import AppKit
import ColorSync

/// Connected display geometry in AX coordinates, independent of placement models.
@MainActor
enum AXScreens {
    static func recoveryFrames(geometry: AXGeometry) -> [CGRect] {
        NSScreen.screens.filter { uuid(of: $0) != nil }.map { geometry.flip($0.frame) }.sorted {
            $0.minX != $1.minX ? $0.minX < $1.minX : $0.minY < $1.minY
        }
    }

    /// Lowercased, so a stored identity and a live one can never miss each other on case.
    static func uuid(of screen: NSScreen) -> String? {
        guard let id = displayID(screen),
            let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
            let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string.lowercased()
    }

    static func displayID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }
}
