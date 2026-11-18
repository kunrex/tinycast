// Portions adapted from Rooms (MIT): https://github.com/saragordic/rooms/blob/main/LICENSE
import AppKit
@preconcurrency import ApplicationServices

extension AXWindowAccess {
    /// Slack when checking whether the app honoured the size we asked for.
    static let clampTolerance: CGFloat = 2

    /// The one write sequence, so a stubborn app lands the same way from any caller.
    static func write(
        _ target: CGRect, anchor: WindowPlacementEngine.Anchor, to window: AXUIElement,
        current: CGRect, canResize: Bool, canvas: CGRect?
    ) -> CGRect? {
        guard canResize else {
            var slot = anchor.place(current.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            guard setPosition(WindowPlacementEngine.rounded(slot).origin, on: window) else {
                return nil
            }
            return frame(of: window) ?? current
        }

        // size → position → size. See docs/features/window-management.md#applying-a-placement.
        _ = setSize(target.size, on: window)
        guard setPosition(target.origin, on: window) else {
            _ = setSize(current.size, on: window)  // Roll the shrink back; nothing visibly moved.
            return nil
        }
        _ = setSize(target.size, on: window)

        guard var actual = frame(of: window) else { return target }

        // The second resize can shift the origin: some apps anchor on a different corner.
        if abs(actual.minX - target.minX) > clampTolerance
            || abs(actual.minY - target.minY) > clampTolerance
        {
            _ = setPosition(target.origin, on: window)
            actual = frame(of: window) ?? actual
        }

        // An app-imposed minimum: re-place once per the anchor. No loop, which would jitter.
        if actual.width > target.width + clampTolerance
            || actual.height > target.height + clampTolerance
        {
            var slot = anchor.place(actual.size, in: target)
            if let canvas { slot = WindowPlacementEngine.clamped(slot, into: canvas) }
            _ = setPosition(WindowPlacementEngine.rounded(slot).origin, on: window)
            actual = frame(of: window) ?? actual
        }
        return actual
    }
}
