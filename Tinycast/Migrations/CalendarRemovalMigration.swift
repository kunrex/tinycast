import Foundation

/// Retires only Tinycast's calendar preferences and launcher references, never calendar events.
enum CalendarRemovalMigration {
    private static let retiredCommands: Set<String> = [
        "command:open-camera", "command:join-next-meeting", "command:my-schedule",
        "command:create-event", "command:copy-meeting-link", "command:open-in-calendar"
    ]

    static func run(
        defaults: UserDefaults, settingsFileURL: URL, rankingFileURL: URL? = nil
    ) {
        for key in [
            "calendarEnabled", "calendarShowInLauncher", "calendarLauncherLimit", "calendarSpan",
            "joinWindowMinutes", "autoJoinMeetings", "autoJoinConfirms", "autoJoinNamedProvidersOnly",
            "cameraPreview", "meetingBrowser", "menuBarEvents", "calendarMenuBarDisplay",
            "menuBarLinkedEventsOnly", "calendarMenuBarHidesWhenEmpty", "hideCurrentEvent",
            "hiddenMeetingCalendars"
        ] {
            defaults.removeObject(forKey: key)
        }
        for command in retiredCommands { defaults.removeObject(forKey: "hotkey." + command) }
        for key in ["favoriteApps", "hiddenLauncherItems", "fallbackOrder", "disabledFallbacks"] {
            pruneArray(key, defaults: defaults, removing: isRetired)
        }
        pruneArray("hiddenLauncherKinds", defaults: defaults) { $0 == "meeting" }
        pruneArray("compactBarCommands", defaults: defaults) { $0 == "command:my-schedule" }
        pruneArray("allowedDeepLinks", defaults: defaults) {
            isRetired(String($0.split(separator: "?", maxSplits: 1).first ?? ""))
        }
        if let aliases = defaults.dictionary(forKey: "launcherAliases") {
            let retained = aliases.filter { !isRetired($0.key) }
            if retained.count != aliases.count { defaults.set(retained, forKey: "launcherAliases") }
        }
        rewriteJSON(at: settingsFileURL) { root in
            var changed = root.removeValue(forKey: "calendar") != nil
            if var appearance = root["appearance"] as? [String: Any],
                let commands = appearance["compactBarCommands"] as? [String]
            {
                let retained = commands.filter { $0 != "command:my-schedule" }
                if retained != commands {
                    appearance["compactBarCommands"] = retained
                    root["appearance"] = appearance
                    changed = true
                }
            }
            if var commands = root["commands"] as? [String: Any],
                let builtIn = commands["builtIn"] as? [String: Any]
            {
                let retained = builtIn.filter { !retiredCommands.contains("command:" + $0.key) }
                if retained.count != builtIn.count {
                    commands["builtIn"] = retained
                    root["commands"] = commands
                    changed = true
                }
            }
            return changed
        }
        if let rankingFileURL {
            rewriteJSON(at: rankingFileURL) { root in
                let retained = root.filter { !isRetired($0.key) }
                guard retained.count != root.count else { return false }
                root = retained
                return true
            }
        }
    }

    private static func isRetired(_ identifier: String) -> Bool {
        identifier.hasPrefix("meeting:") || retiredCommands.contains(identifier)
    }

    private static func pruneArray(
        _ key: String, defaults: UserDefaults, removing: (String) -> Bool
    ) {
        guard let stored = defaults.stringArray(forKey: key) else { return }
        let retained = stored.filter { !removing($0) }
        if retained != stored { defaults.set(retained, forKey: key) }
    }

    private static func rewriteJSON(
        at url: URL, update: (inout [String: Any]) -> Bool
    ) {
        let target = url.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: target),
            var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            update(&root),
            let updated = try? JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? updated.write(to: target, options: .atomic)
    }
}
