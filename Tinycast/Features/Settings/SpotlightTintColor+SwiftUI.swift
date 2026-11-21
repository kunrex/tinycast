import SwiftUI

extension SpotlightTintColor {
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        self.init(
            red: rgb.redComponent, green: rgb.greenComponent,
            blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }
}
