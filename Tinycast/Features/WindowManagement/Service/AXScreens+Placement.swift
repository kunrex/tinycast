import AppKit

/// Displays, converted into the AX space the geometry layer works in.
@MainActor
extension AXScreens {
    /// Cocoa screens flipped through one snapshotted anchor, never one each.
    static func converted(
        _ screens: [NSScreen], geometry: AXGeometry
    ) -> [WindowPlacementEngine.Screen] {
        screens.enumerated().map { index, screen in
            // A display with no number still needs a stable, collision-free id for this call.
            return WindowPlacementEngine.Screen(
                id: displayID(screen).map(Int.init) ?? -(index + 1),
                frame: geometry.flip(screen.frame),
                visibleFrame: geometry.flip(screen.visibleFrame))
        }
    }

    /// Every connected display a layout can name, left to right, with its persistent identity.
    static func layoutScreens(geometry: AXGeometry) -> [WindowLayoutScreen] {
        let screens = NSScreen.screens
        let converted = converted(screens, geometry: geometry)
        let ordered = WindowPlacementEngine.ordered(converted)
        return ordered.compactMap { screen in
            guard let index = converted.firstIndex(where: { $0.id == screen.id }),
                let uuid = uuid(of: screens[index])
            else { return nil }
            return WindowLayoutScreen(
                display: WindowLayoutDisplay(uuid: uuid, name: screens[index].localizedName),
                screen: screen)
        }
    }

}
