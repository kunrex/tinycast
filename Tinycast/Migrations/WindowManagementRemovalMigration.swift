import Foundation

/// One-release cleanup only; window recovery owns its ledger independently.
enum WindowManagementRemovalMigration {
    static func run() {
        run(
            defaults: .standard, settingsFileURL: AppPaths.settingsFile(),
            rankingFileURL: AppPaths.applicationSupport().appendingPathComponent("launcher-ranking.json"))
    }

    static func run(defaults: UserDefaults, settingsFileURL: URL, rankingFileURL: URL) {
        for key in retiredDefaults { defaults.removeObject(forKey: key) }
        for key in defaults.dictionaryRepresentation().keys where isRetiredHotkey(key) {
            defaults.removeObject(forKey: key)
        }
        for key in ["favoriteApps", "hiddenLauncherItems", "allowedDeepLinks", "hiddenLauncherKinds"] {
            guard let values = defaults.array(forKey: key) else { continue }
            let remaining = values.filter { value in
                guard let value = value as? String else { return true }
                if key == "hiddenLauncherKinds" { return !retiredKinds.contains(value) }
                if key == "allowedDeepLinks" {
                    let row = String(value.prefix { $0 != "?" })
                    return !isRetiredEntry(row.removingPercentEncoding ?? row)
                }
                return !isRetiredEntry(value)
            }
            if remaining.count != values.count { defaults.set(remaining, forKey: key) }
        }
        if let aliases = defaults.dictionary(forKey: "launcherAliases") {
            let remaining = aliases.filter { !isRetiredEntry($0.key) }
            if remaining.count != aliases.count { defaults.set(remaining, forKey: "launcherAliases") }
        }
        cleanJSON(at: settingsFileURL) { object in
            object.removeValue(forKey: "windowManagement") != nil
        }
        cleanJSON(at: rankingFileURL) { object in
            let keys = object.keys.filter(isRetiredEntry)
            for key in keys { object.removeValue(forKey: key) }
            return !keys.isEmpty
        }
    }

    private static let retiredDefaults = [
        "windowManagementEnabled", "windowManagementShowInLauncher", "windowManagementGap",
        "windowManagementCycleMode", "windowManagementWrapDisplays", "windowManagementKeepProportions",
        "windowLayoutsShowInLauncher", "windowRoomsShowInLauncher", "customWindowSizes",
        "windowLayouts", "windowRooms", "roomMinimumWindowSizes", "boundWindowLayoutIDs",
        "boundWindowRoomIDs", "boundCustomWindowSizeIDs"
    ]
    private static let retiredKinds: Set<String> = ["windowCommand", "windowLayout", "windowRoom"]
    private static let builtIns: Set<String> = [
        "command:create-window-layout", "command:capture-window-layout",
        "command:switch-room", "command:create-room"
    ]
    private static let windowCommands: Set<String> = [
        "left-half", "right-half", "top-half", "bottom-half", "top-left-quarter", "top-right-quarter",
        "bottom-left-quarter", "bottom-right-quarter", "first-three-fourths", "last-three-fourths",
        "first-third", "center-third", "last-third", "first-two-thirds", "last-two-thirds", "maximize",
        "almost-maximize", "reasonable-size", "maximize-height", "maximize-width", "center",
        "center-half", "center-two-thirds", "make-larger", "make-smaller", "restore", "move-left",
        "move-right", "move-up", "move-down", "move-to-left-edge", "move-to-right-edge",
        "move-to-top-edge", "move-to-bottom-edge", "next-display", "previous-display",
        "toggle-fullscreen", "previous-space", "next-space"
    ]

    private static func isRetiredEntry(_ key: String) -> Bool {
        if builtIns.contains(key) { return true }
        if key.hasPrefix("window-command:") {
            return windowCommands.contains(String(key.dropFirst("window-command:".count)))
        }
        return ["window-size:", "window-layout:", "window-room:"].contains {
            hasUUID(key, prefix: $0)
        }
    }

    private static func isRetiredHotkey(_ key: String) -> Bool {
        if key.hasPrefix("hotkey."), builtIns.contains(String(key.dropFirst("hotkey.".count))) {
            return true
        }
        if key.hasPrefix("hotkey.windowCommand.") {
            return windowCommands.contains(String(key.dropFirst("hotkey.windowCommand.".count)))
        }
        return ["hotkey.customWindowSize.", "hotkey.windowLayout.", "hotkey.windowRoom."].contains {
            hasUUID(key, prefix: $0)
        }
    }

    private static func hasUUID(_ key: String, prefix: String) -> Bool {
        key.hasPrefix(prefix) && UUID(uuidString: String(key.dropFirst(prefix.count))) != nil
    }

    private static func cleanJSON(at url: URL, remove: (inout [String: Any]) -> Bool) {
        let target = url.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: target),
            var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            remove(&object),
            let cleaned = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? cleaned.write(to: target, options: .atomic)
    }
}
