import Foundation

/// Portable sRGB color; the final byte is alpha, independent of whether tint is enabled.
struct SpotlightTintColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init?(encoded: String) {
        guard encoded.count == 9, encoded.first == "#",
            encoded.dropFirst().allSatisfy({ $0.isASCII && $0.isHexDigit }),
            let value = UInt32(encoded.dropFirst(), radix: 16)
        else { return nil }
        red = Double((value >> 24) & 255) / 255
        green = Double((value >> 16) & 255) / 255
        blue = Double((value >> 8) & 255) / 255
        alpha = Double(value & 255) / 255
    }

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    var encoded: String {
        let bytes = [red, green, blue, alpha].map { value in
            Int((min(max(value.isFinite ? value : 0, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X%02X", bytes[0], bytes[1], bytes[2], bytes[3])
    }
}
