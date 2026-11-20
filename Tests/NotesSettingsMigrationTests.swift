import Foundation

@main
@MainActor
struct NotesSettingsMigrationTests {
    private static var failures = 0

    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("notes-migration-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let activeID = "NotesSettingsMigrationTests.\(UUID())"
        let otherID = "NotesSettingsMigrationTests.\(UUID())"
        let active = UserDefaults(suiteName: activeID)!
        let other = UserDefaults(suiteName: otherID)!
        defer {
            active.removePersistentDomain(forName: activeID)
            other.removePersistentDomain(forName: otherID)
            try? manager.removeItem(at: root)
        }
        let key = "compactBarCommands"
        let identifiers = ["command:show-notes", "command:show-notes-extra", "command:search-emoji", "command:create-note",
            "command:search-notes", "command:search-emoji"]
        active.set(identifiers, forKey: key)
        other.set(identifiers, forKey: key)
        active.set(true, forKey: "notesEnabled")
        active.set("~/My Notes", forKey: "notesFolder")
        active.set(["keep": 42], forKey: "unknown")

        let note = root.appendingPathComponent("User Notes/Keep.md")
        try manager.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        let markdown = Data("# User-owned Markdown\n- [ ] Never change this.\n".utf8)
        try markdown.write(to: note)
        let file = root.appendingPathComponent(AppPaths.settingsFile(bundleID: activeID).deletingLastPathComponent()
            .lastPathComponent).appendingPathComponent("settings.json")
        let otherFile = root.appendingPathComponent(AppPaths.settingsFile(bundleID: otherID).deletingLastPathComponent()
            .lastPathComponent).appendingPathComponent("settings.json")
        let original: [String: Any] = [
            "notes": ["folder": note.deletingLastPathComponent().path, "unknown": true],
            "appearance": ["compactBarCommands": identifiers, "unknown": ["nested": true]],
            "general": ["showInMenuBar": false],
            "unknown": ["notes": "keep", "null": NSNull(), "array": [1, "two", false]]
        ]
        let bytes = try JSONSerialization.data(withJSONObject: original)
        for url in [file, otherFile] {
            try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try bytes.write(to: url)
        }
        NotesSettingsMigration.run(defaults: active, fileURL: file)
        let expected = ["command:show-notes-extra", "command:search-emoji", "command:search-emoji"]
        check(active.stringArray(forKey: key) == expected, "only exact retired IDs are removed, without validation")
        check(other.stringArray(forKey: key) == identifiers, "another preference domain is untouched")
        check(active.bool(forKey: "notesEnabled") && active.string(forKey: "notesFolder") == "~/My Notes",
            "Notes preferences remain installed")
        check(active.dictionary(forKey: "unknown") as NSDictionary? == ["keep": 42] as NSDictionary,
            "unknown preferences survive")
        var expectedJSON = original
        expectedJSON.removeValue(forKey: "notes")
        var appearance = original["appearance"] as? [String: Any] ?? [:]
        appearance[key] = expected
        expectedJSON["appearance"] = appearance
        let migrated = try Data(contentsOf: file)
        let actual = try JSONSerialization.jsonObject(with: migrated) as? NSDictionary
        check(actual == expectedJSON as NSDictionary, "only the obsolete section and exact IDs change")
        check(try Data(contentsOf: otherFile) == bytes, "another channel's settings file is untouched")
        NotesSettingsMigration.run(defaults: active, fileURL: file)
        check(try Data(contentsOf: file) == migrated, "second launch does not rewrite the file")

        let target = root.appendingPathComponent("dotfiles.json")
        let link = root.appendingPathComponent("linked-settings.json")
        try bytes.write(to: target)
        try manager.createSymbolicLink(at: link, withDestinationURL: target)
        NotesSettingsMigration.run(defaults: active, fileURL: link)
        check(try manager.destinationOfSymbolicLink(atPath: link.path) == target.path, "the symlink survives")
        check(try Data(contentsOf: target) == migrated, "the symlink target receives the repair")
        let directoryLink = root.appendingPathComponent("linked-directory")
        try manager.createSymbolicLink(at: directoryLink, withDestinationURL: file.deletingLastPathComponent())
        try bytes.write(to: file)
        NotesSettingsMigration.run(defaults: active, fileURL: directoryLink.appendingPathComponent("settings.json"))
        check(try Data(contentsOf: file) == migrated, "directory symlinks are followed too")
        check(try Data(contentsOf: note) == markdown, "user Markdown is never opened for mutation")

        for untouched in [Data("not JSON".utf8), Data("[]".utf8), Data("{ \"unknown\": 1 }".utf8)] {
            try untouched.write(to: file)
            NotesSettingsMigration.run(defaults: active, fileURL: file)
            check(try Data(contentsOf: file) == untouched, "invalid or unrelated files are left byte-for-byte intact")
        }
        let missing = root.appendingPathComponent("absent/settings.json")
        NotesSettingsMigration.run(defaults: active, fileURL: missing)
        check(!manager.fileExists(atPath: missing.deletingLastPathComponent().path), "no missing folders are created")
        for value in [["command:show-notes", "command:create-note", "command:search-notes"], []] {
            active.set(value, forKey: key)
            NotesSettingsMigration.run(defaults: active, fileURL: missing)
            check(active.stringArray(forKey: key) == [], "all retired and explicit empty preferences stay empty")
        }
        active.removeObject(forKey: key)
        NotesSettingsMigration.run(defaults: active, fileURL: missing)
        check(active.object(forKey: key) == nil, "missing preferences remain absent")
        print("Notes settings migration tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }
}
