import Foundation

@main
struct RetiredAISettingsMigrationTests {
    static func main() throws {
        func check(_ condition: Bool) { precondition(condition) }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "settings.json")
        RetiredAISettingsMigration.run(fileURL: file)
        precondition(!FileManager.default.fileExists(atPath: file.path))
        let invalid = Data("not JSON".utf8)
        try invalid.write(to: file)
        RetiredAISettingsMigration.run(fileURL: file)
        check(try Data(contentsOf: file) == invalid)

        let source = Data(
            #"""
            {
              "ai": {
                "enabled": true, "webSearch": true, "choices": true,
                "expandsReasoning": true, "systemPrompt": "old", "systemPromptEnabled": true,
                "retentionDays": 30, "opensTo": "recent", "newChatAfterMinutes": 5,
                "toolRounds": 10,
                "commands": {"ai-chat": {}, "ai-chat-window": {}, "future": {"alias": "keep"}},
                "connections": ["keep"], "installedOverrides": {"keep": true}
              },
              "appearance": {"compactBarCommands": ["command:show-notes", "command:ai-chat",
                "command:search-emoji", "command:ai-chat-window", "unknown", 42]},
              "commands": {"builtIn": {"ai-chat": {}, "quit": {"alias": "q"}}},
              "quickActions": {"targetLanguage": "fr"},
              "unknown": {"enabled": true}
            }
            """#.utf8)
        try source.write(to: file)
        let link = directory.appending(path: "linked.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let history = directory.appending(path: "ai-chats.sqlite3")
        let presets = directory.appending(path: "chat-presets.json")
        try source.write(to: history)
        try source.write(to: presets)
        RetiredAISettingsMigration.run(fileURL: link)
        check(try link.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true)
        let cleaned = try Data(contentsOf: file)
        let root = try JSONSerialization.jsonObject(with: cleaned) as! [String: Any]
        let ai = root["ai"] as! [String: Any]
        precondition(Set(ai.keys) == ["commands", "connections", "installedOverrides"])
        precondition((ai["commands"] as! [String: Any]).keys.sorted() == ["future"])
        let appearance = root["appearance"] as! [String: Any]
        precondition(
            (appearance["compactBarCommands"] as! NSArray).isEqual(to: [
                "command:show-notes", "command:search-emoji", "unknown", 42
            ]))
        let commands = root["commands"] as! [String: Any]
        precondition((commands["builtIn"] as! [String: Any]).keys.sorted() == ["quit"])
        precondition(root["quickActions"] != nil && root["unknown"] != nil)
        check(try Data(contentsOf: history) == source)
        check(try Data(contentsOf: presets) == source)
        RetiredAISettingsMigration.run(fileURL: file)
        check(try Data(contentsOf: file) == cleaned)
        for commands in ["{}", #"{"ai-chat": {}, "ai-chat-window": {}}"#] {
            try Data("{\"ai\":{\"enabled\":true,\"commands\":\(commands)}}".utf8).write(to: file)
            RetiredAISettingsMigration.run(fileURL: file)
            let migrated =
                try JSONSerialization.jsonObject(with: Data(contentsOf: file))
                as! [String: Any]
            precondition(migrated["ai"] == nil)
        }
        print("Retired AI settings migration tests passed")
    }
}
