// Adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import CoreGraphics

/// Where a window waits while its room is elsewhere.
enum RoomParking {
    /// A 1-pt sliver stays on `visible`, so macOS keeps it; no corner may spill onto a display.
    static func origin(for size: CGSize, on visible: CGRect, avoiding others: [CGRect]) -> CGPoint {
        let corners = [
            CGPoint(x: visible.maxX - 1, y: visible.maxY - 1),
            CGPoint(x: visible.minX + 1 - size.width, y: visible.maxY - 1),
            CGPoint(x: visible.maxX - 1, y: visible.minY + 1 - size.height),
            CGPoint(x: visible.minX + 1 - size.width, y: visible.minY + 1 - size.height)
        ]
        func spill(_ origin: CGPoint) -> CGFloat {
            let parked = CGRect(origin: origin, size: size)
            return others.reduce(0) { $0 + overlapArea($1, parked) }
        }
        return corners.first { spill($0) == 0 }
            ?? corners.min { spill($0) < spill($1) } ?? corners[0]
    }

    private static func overlapArea(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let shared = lhs.intersection(rhs)
        return shared.isNull ? 0 : shared.width * shared.height
    }
}
