import Foundation

@main
@MainActor
struct PaletteTabTests {
    static func main() {
        for enabled in [false, true] {
            for mode in PaletteMode.allCases {
                let expected: PaletteTabAction = mode == .launcher && enabled
                    ? .carryQuery(.clipboard) : .carryQuery(.launcher)
                precondition(
                    PaletteTabAction.resolve(mode: mode, clipboardEnabled: enabled) == expected,
                    "Tab must carry search only between surviving screens")
            }
        }
        precondition(PaletteMode(rawValue: "ai") == nil)
        precondition(PaletteMode(rawValue: "aiHistory") == nil)
        print("Palette Tab checks passed")
    }
}
