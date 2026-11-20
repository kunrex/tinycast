import Foundation

@main
struct CalendarRemovalMigrationTests {
    static func main() throws {
        let suite = "CalendarRemovalMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appendingPathComponent(suite)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let target = folder.appendingPathComponent("dotfiles.json")
        let link = folder.appendingPathComponent("settings.json")
        let ranking = folder.appendingPathComponent("launcher-ranking.json")
        let retired = [
            "command:open-camera", "command:join-next-meeting", "command:my-schedule",
            "command:create-event", "command:copy-meeting-link", "command:open-in-calendar"
        ]
        let kept = ["command:show-notes", "window-command:left-half", "unknown", "file:~/Notes"]
        let retiredDefaults = [
            "calendarEnabled", "calendarShowInLauncher", "calendarLauncherLimit", "calendarSpan",
            "joinWindowMinutes", "autoJoinMeetings", "autoJoinConfirms", "autoJoinNamedProvidersOnly",
            "cameraPreview", "meetingBrowser", "menuBarEvents", "calendarMenuBarDisplay",
            "menuBarLinkedEventsOnly", "calendarMenuBarHidesWhenEmpty", "hideCurrentEvent",
            "hiddenMeetingCalendars"
        ]
        for key in retiredDefaults { defaults.set("retired", forKey: key) }
        defaults.set(true, forKey: "notesEnabled")
        defaults.set("microphone", forKey: "dictationMicrophone")
        for id in retired { defaults.set("binding", forKey: "hotkey." + id) }
        defaults.set("window-binding", forKey: "hotkey.windowCommand.left-half")
        defaults.set(kept + retired + ["meeting:occurrence"], forKey: "favoriteApps")
        defaults.set(kept + retired, forKey: "hiddenLauncherItems")
        defaults.set(kept + retired, forKey: "fallbackOrder")
        defaults.set(kept + retired, forKey: "disabledFallbacks")
        defaults.set(["meeting", "application", "unknown"], forKey: "hiddenLauncherKinds")
        defaults.set(["command:my-schedule", "command:show-notes", "unknown"], forKey: "compactBarCommands")
        defaults.set(["command:open-camera?input", "command:show-notes"], forKey: "allowedDeepLinks")
        defaults.set(["meeting:occurrence": "call", "command:open-camera": "cam", "unknown": "keep"],
                     forKey: "launcherAliases")
        try Data("""
            {"calendar":{"commands":{"my-schedule":{}},"enabled":true},
             "appearance":{"compactBarCommands":["command:my-schedule","command:show-notes","unknown"]},
             "commands":{"builtIn":{"open-camera":{},"unknown":{},"show-notes":{}}},
             "windowManagement":{"gap":8},"notes":{"enabled":true},"future":{"value":42}}
            """.utf8).write(to: target)
        try manager.createSymbolicLink(at: link, withDestinationURL: target)
        try Data("""
            {"meeting:occurrence":{"anchor":123},"command:open-camera":{"anchor":456},
             "window-command:left-half":{"anchor":789},"unknown":{"anchor":10}}
            """.utf8).write(to: ranking)

        func run() {
            CalendarRemovalMigration.run(defaults: defaults, settingsFileURL: link, rankingFileURL: ranking)
        }
        run()
        for key in retiredDefaults { precondition(defaults.object(forKey: key) == nil) }
        precondition(defaults.bool(forKey: "notesEnabled"))
        precondition(defaults.string(forKey: "dictationMicrophone") == "microphone")
        for id in retired { precondition(defaults.object(forKey: "hotkey." + id) == nil) }
        precondition(defaults.string(forKey: "hotkey.windowCommand.left-half") == "window-binding")
        precondition(defaults.stringArray(forKey: "favoriteApps") == kept)
        precondition(defaults.stringArray(forKey: "hiddenLauncherItems") == kept)
        precondition(defaults.stringArray(forKey: "fallbackOrder") == kept)
        precondition(defaults.stringArray(forKey: "disabledFallbacks") == kept)
        precondition(defaults.stringArray(forKey: "hiddenLauncherKinds") == ["application", "unknown"])
        precondition(defaults.stringArray(forKey: "compactBarCommands") == ["command:show-notes", "unknown"])
        precondition(defaults.stringArray(forKey: "allowedDeepLinks") == ["command:show-notes"])
        precondition(defaults.dictionary(forKey: "launcherAliases") as? [String: String] == ["unknown": "keep"])
        let destination = try manager.destinationOfSymbolicLink(atPath: link.path)
        precondition(destination == target.path)
        let settingsData = try Data(contentsOf: target)
        let settings = try JSONSerialization.jsonObject(with: settingsData) as! [String: Any]
        precondition(settings["calendar"] == nil)
        precondition((settings["windowManagement"] as? [String: Int]) == ["gap": 8])
        precondition((settings["future"] as? [String: Int]) == ["value": 42])
        let commands = (settings["commands"] as! [String: Any])["builtIn"] as! [String: Any]
        precondition(Set(commands.keys) == ["unknown", "show-notes"])
        let rankedData = try Data(contentsOf: ranking)
        let ranked = try JSONSerialization.jsonObject(with: rankedData) as! [String: Any]
        precondition(Set(ranked.keys) == ["window-command:left-half", "unknown"])
        run()
        let repeatedSettings = try Data(contentsOf: target)
        let repeatedRanking = try Data(contentsOf: ranking)
        precondition(repeatedSettings == settingsData)
        precondition(repeatedRanking == rankedData)
        try Data("invalid JSON".utf8).write(to: target)
        run()
        let invalid = try String(contentsOf: target, encoding: .utf8)
        precondition(invalid == "invalid JSON")
        CalendarRemovalMigration.run(
            defaults: defaults, settingsFileURL: folder.appendingPathComponent("missing.json"))
        print("Calendar removal migration tests passed")
    }
}
