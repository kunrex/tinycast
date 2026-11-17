import Foundation

struct AIEffort: Equatable, Identifiable, Sendable {
    let id: String
    let detail: String?

    var title: String {
        switch id {
        case "default": return String(localized: "Default")
        case "none": return String(localized: "None")
        case "minimal": return String(localized: "Minimal")
        case "low": return String(localized: "reasoning-effort-low", defaultValue: "Low")
        case "medium": return String(localized: "reasoning-effort-medium", defaultValue: "Medium")
        case "high": return String(localized: "reasoning-effort-high", defaultValue: "High")
        case "xhigh": return String(localized: "Extra high")
        case "max": return String(localized: "Max")
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }
}
