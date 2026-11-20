import Foundation

@main
enum WindowManagementRemovalMigrationTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "WindowManagementRemovalMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let settings = root.appendingPathComponent("settings.json")
        let ranking = root.appendingPathComponent("launcher-ranking.json")
        let id = UUID().uuidString.lowercased()
        let retired = [
            "window-command:left-half", "window-command:next-space", "window-size:\(id)",
            "window-layout:\(id)", "window-room:\(id)", "command:create-window-layout",
            "command:capture-window-layout", "command:switch-room", "command:create-room"
        ]
        let kept = [
            "com.example.app", "command:switch-windows", "command:search-menu-items",
            "window-command:left-half-extra", "window-command:future-command", "window-size:not-a-uuid",
            "window-layout:\(id)-extra", "window-roomish:\(id)", "command:create-room-extra",
            "file:window-room:\(id)", "extension:window-command:left-half", ""
        ]
        let removedKeys = [
            "windowManagementEnabled", "windowManagementShowInLauncher", "windowManagementGap",
            "windowManagementCycleMode", "windowManagementWrapDisplays", "windowManagementKeepProportions",
            "windowLayoutsShowInLauncher", "windowRoomsShowInLauncher", "customWindowSizes", "windowLayouts",
            "windowRooms", "roomMinimumWindowSizes", "boundWindowLayoutIDs", "boundWindowRoomIDs",
            "boundCustomWindowSizeIDs", "hotkey.windowCommand.left-half", "hotkey.windowCommand.next-space",
            "hotkey.customWindowSize.\(id)", "hotkey.windowLayout.\(id)", "hotkey.windowRoom.\(id)",
            "hotkey.command:create-window-layout", "hotkey.command:capture-window-layout",
            "hotkey.command:switch-room", "hotkey.command:create-room"
        ]
        let preservedKeys = [
            "navigationEnabled", "windowManagementEnabledExtra", "windowLayoutsOther", "boundAppBundleIDs",
            "hotkey.command:switch-windows", "hotkey.command:create-room-extra",
            "hotkey.windowCommand.left-half-extra", "hotkey.windowLayout.not-a-uuid",
            "hotkey.windowRoom.\(id)-extra", "hotkey.windowLayoutOther.\(id)"
        ]
        for key in removedKeys + preservedKeys { defaults.set("unchanged", forKey: key) }
        for key in ["favoriteApps", "hiddenLauncherItems"] {
            defaults.set(retired + kept, forKey: key)
        }
        defaults.set(Dictionary(uniqueKeysWithValues: (retired + kept).map { ($0, "alias \($0)") }),
                     forKey: "launcherAliases")
        defaults.set(["windowCommand", "windowLayout", "windowRoom", "application", "windowRoomExtra"],
                     forKey: "hiddenLauncherKinds")
        let grants = retired.flatMap { [$0, $0 + "?text=hello"] }
            + ["window-command%3Aleft-half?text=hello", "window-room%3A\(id)"]
        defaults.set(grants + kept + ["%invalid?text=hello", "?text=hello"], forKey: "allowedDeepLinks")
        let unrelated: [String: Any] = [
            "navigation": ["enabled": true, "commands": ["switch-windows": ["alias": "win"]]],
            "general": ["popToRootSeconds": 0, "showInMenuBar": false, "language": "ja"],
            "unknown": ["number": 1234567890123456789 as Int64, "null": NSNull(), "list": [1, 2, 3]],
            "windowManagementExtra": ["enabled": true]
        ]
        var original = unrelated
        original["windowManagement"] = ["enabled": true, "gap": 8, "rooms": [["id": id]]]
        try json(original).write(to: settings)
        let visits = Dictionary(uniqueKeysWithValues: (retired + kept).map {
            ($0, ["anchor": 999999999, "openedAt": 100, "searchTerms": ["term"]] as [String: Any])
        })
        try json(visits).write(to: ranking)
        let ledgers = ["room-parking.json", "room-parking.unreadable-\(UUID().uuidString).json"]
        for name in ledgers { try Data("unreadable recovery source".utf8).write(to: root.appendingPathComponent(name)) }
        func run() {
            WindowManagementRemovalMigration.run(
                defaults: defaults, settingsFileURL: settings, rankingFileURL: ranking)
        }
        run()
        for key in removedKeys { precondition(defaults.object(forKey: key) == nil, key) }
        for key in preservedKeys { precondition(defaults.string(forKey: key) == "unchanged", key) }
        for key in ["favoriteApps", "hiddenLauncherItems"] {
            precondition(defaults.stringArray(forKey: key) == kept, key)
        }
        precondition(defaults.dictionary(forKey: "launcherAliases") as? [String: String]
            == Dictionary(uniqueKeysWithValues: kept.map { ($0, "alias \($0)") }))
        precondition(defaults.stringArray(forKey: "hiddenLauncherKinds") == ["application", "windowRoomExtra"])
        precondition(defaults.stringArray(forKey: "allowedDeepLinks") == kept + ["%invalid?text=hello", "?text=hello"])
        precondition(tryObject(settings).isEqual(to: unrelated))
        precondition(tryObject(ranking).isEqual(to: visits.filter { kept.contains($0.key) }))
        let firstSettings = try Data(contentsOf: settings)
        let firstRanking = try Data(contentsOf: ranking)
        let firstDefaults = defaults.persistentDomain(forName: suite)! as NSDictionary
        run()
        precondition(tryData(settings) == firstSettings)
        precondition(tryData(ranking) == firstRanking)
        precondition(firstDefaults.isEqual(to: defaults.persistentDomain(forName: suite)!))
        for invalid in ["{ broken", "[1, 2]", "null", ""] {
            let data = Data(invalid.utf8)
            try data.write(to: settings)
            try data.write(to: ranking)
            run()
            precondition(tryData(settings) == data)
            precondition(tryData(ranking) == data)
        }
        try FileManager.default.removeItem(at: settings)
        let target = root.appendingPathComponent("dotfile.json")
        try json(original).write(to: target)
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: target)
        run()
        precondition(tryObject(target).isEqual(to: unrelated))
        let resourceValues = try settings.resourceValues(forKeys: [.isSymbolicLinkKey])
        precondition(resourceValues.isSymbolicLink == true)
        for name in ledgers {
            precondition(tryData(root.appendingPathComponent(name)) == Data("unreadable recovery source".utf8))
        }
        precondition(AppPaths.settingsFile(bundleID: "com.abueammar.tinycast.dev")
            != AppPaths.settingsFile(bundleID: "com.abueammar.tinycast"))
        print("WindowManagementRemovalMigrationTests passed")
    }

    private static func json(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func tryObject(_ url: URL) -> NSDictionary {
        (try! JSONSerialization.jsonObject(with: Data(contentsOf: url))) as! NSDictionary
    }

    private static func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }
}
