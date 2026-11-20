import AppKit

/// The one Cocoa↔AX converter. See docs/features/window-recovery.md#coordinate-space.
struct AXGeometry {
    let anchorHeight: CGFloat

    /// Snapshot once per command: mixing anchors corrupts coordinates.
    @MainActor
    init(screens: [NSScreen]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        anchorHeight = primary?.frame.height ?? 0
    }

    func flip(_ rect: CGRect) -> CGRect {
        CGRect(
            x: rect.origin.x, y: anchorHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
