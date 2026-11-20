// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics

/// The way back for a parked window, independent of room layouts and placement commands.
enum WindowRecoveryPolicy {
    static func returnFrame(for frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let first = screens.first, !screens.contains(where: {
            let shared = $0.intersection(frame)
            return !shared.isNull && shared.width * shared.height > 0
        }) else { return frame }
        let size = CGSize(width: min(frame.width, first.width), height: min(frame.height, first.height))
        return rounded(CGRect(
            x: first.midX - size.width / 2, y: first.midY - size.height / 2,
            width: size.width, height: size.height))
    }

    static func matches(windowID: UInt32?, bundleID: String, entry: RoomParkingLedger.Entry) -> Bool {
        windowID == entry.windowID && bundleID == entry.bundleID
    }

    static func isReturned(_ actual: CGRect, to home: CGRect) -> Bool {
        abs(actual.minX - home.minX) <= 16 && abs(actual.minY - home.minY) <= 16
    }

    static func rounded(_ rect: CGRect) -> CGRect {
        let minX = rect.minX.rounded()
        let minY = rect.minY.rounded()
        return CGRect(x: minX, y: minY,
                      width: max(0, rect.maxX.rounded() - minX),
                      height: max(0, rect.maxY.rounded() - minY))
    }
}
