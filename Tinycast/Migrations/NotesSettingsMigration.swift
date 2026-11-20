import Foundation

/// Retires Notes' settings-file section and saved compact shortcuts without touching user content.
enum NotesSettingsMigration {
    static func run(
        defaults: UserDefaults = .standard, fileURL: URL = AppPaths.settingsFile()
    ) {
        let key = "compactBarCommands"
        if let identifiers = defaults.stringArray(forKey: key) {
            let filtered = removingNotes(from: identifiers)
            if filtered != identifiers { defaults.set(filtered, forKey: key) }
        }

        let target = fileURL.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: target),
            var root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }
        var changed = root.removeValue(forKey: "notes") != nil
        if var appearance = root["appearance"] as? [String: Any],
            let identifiers = appearance[key] as? [String]
        {
            let filtered = removingNotes(from: identifiers)
            if filtered != identifiers {
                appearance[key] = filtered
                root["appearance"] = appearance
                changed = true
            }
        }
        guard changed,
            var output = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else { return }
        output.append(0x0A)
        try? output.write(to: target, options: .atomic)
    }

    private static func removingNotes(from identifiers: [String]) -> [String] {
        identifiers.filter {
            !["command:show-notes", "command:create-note", "command:search-notes"].contains($0)
        }
    }
}
