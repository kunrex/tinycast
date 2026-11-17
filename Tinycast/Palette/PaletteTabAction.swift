import Foundation

/// Tab carries search between the launcher and clipboard; a sub-screen exits to the launcher.
enum PaletteTabAction: Equatable {
    case carryQuery(PaletteMode)

    static func resolve(mode: PaletteMode, clipboardEnabled: Bool) -> Self {
        if mode == .launcher, clipboardEnabled { return .carryQuery(.clipboard) }
        return .carryQuery(.launcher)
    }
}
