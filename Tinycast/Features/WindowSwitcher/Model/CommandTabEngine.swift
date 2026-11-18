import Foundation

/// Ownership lasts for a whole physical Tab press, independently of the switching gesture.
struct CommandTabEngine: Sendable {
    enum Input: Sendable { case down, up, flags, disabled }
    enum Intent: Equatable, Sendable {
        case step(backwards: Bool, first: Bool)
        case commit
        case cancel
    }
    struct Result: Sendable {
        var suppress = false
        var intent: Intent?
    }

    static let command: UInt64 = 1 << 20
    static let shift: UInt64 = 1 << 17
    static let forbidden: UInt64 = (1 << 18) | (1 << 19) | (1 << 23)
    private var tabOwned: Bool?
    var hasOwnedPress: Bool { tabOwned == true }
    private var switching = false
    private(set) var generation: UInt64 = 0

    mutating func cancel() {
        switching = false
        generation &+= 1
    }

    mutating func handle(
        _ input: Input, keyCode: Int, flags: UInt64, available: Bool = true,
        isAutorepeat: Bool = false, synthetic: Bool = false
    ) -> Result {
        guard !synthetic else { return Result() }
        if input == .disabled {
            cancel()
            return Result(intent: .cancel)
        }
        let validChord = flags & Self.command != 0 && flags & Self.forbidden == 0
        var suppress = false
        if keyCode == 48 {
            if input == .down {
                if !isAutorepeat {
                    tabOwned = available && validChord
                }
                suppress = hasOwnedPress
            } else if input == .up {
                suppress = hasOwnedPress
                tabOwned = nil
            }
        }
        guard available else {
            let wasSwitching = switching
            if wasSwitching { cancel() }
            return Result(suppress: suppress, intent: wasSwitching ? .cancel : nil)
        }
        // Some keyboards deliver the release on a key event rather than flagsChanged.
        if switching, flags & Self.command == 0 {
            switching = false
            return Result(suppress: suppress, intent: .commit)
        }
        guard input == .down, keyCode == 48, suppress, validChord else {
            return Result(suppress: suppress)
        }
        // A cancelled gesture cannot restart from a repeat of its still-owned press.
        guard !isAutorepeat || switching else { return Result(suppress: suppress) }
        let first = !switching
        switching = true
        return Result(suppress: true, intent: .step(backwards: flags & Self.shift != 0, first: first))
    }
}
