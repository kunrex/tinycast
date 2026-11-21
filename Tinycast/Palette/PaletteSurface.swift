import SwiftUI

/// Tint only the surface, leaving foreground content and the underlying glass at full opacity.
struct PaletteSurface: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Theme.Colors.panelScrim
            .overlay {
                if settings.spotlightTintEnabled,
                    let tint = SpotlightTintColor(encoded: settings.spotlightTintColor) {
                    tint.color
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
