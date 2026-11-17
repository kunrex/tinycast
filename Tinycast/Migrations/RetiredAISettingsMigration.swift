import Foundation

/// Tidies only the settings mirror; conversation data and provider configuration stay untouched.
enum RetiredAISettingsMigration {
    static func run(fileURL: URL) {
        let target = fileURL.resolvingSymlinksInPath()
        guard let data = try? Data(contentsOf: target),
            let object = try? JSONSerialization.jsonObject(with: data),
            var root = object as? [String: Any]
        else { return }
        let original = root as NSDictionary
        if var ai = root["ai"] as? [String: Any] {
            for key in [
                "enabled", "webSearch", "choices", "expandsReasoning", "systemPrompt",
                "systemPromptEnabled", "retentionDays", "opensTo", "newChatAfterMinutes", "toolRounds"
            ] {
                ai.removeValue(forKey: key)
            }
            removeCommands(from: &ai, key: "commands")
            if let commands = ai["commands"] as? [String: Any], commands.isEmpty {
                ai.removeValue(forKey: "commands")
            }
            root["ai"] = ai.isEmpty ? nil : ai
        }
        if var commands = root["commands"] as? [String: Any] {
            removeCommands(from: &commands, key: "builtIn")
            root["commands"] = commands
        }
        if var appearance = root["appearance"] as? [String: Any],
            let commands = appearance["compactBarCommands"] as? [Any]
        {
            appearance["compactBarCommands"] = commands.filter {
                guard let id = $0 as? String else { return true }
                return id != "command:ai-chat" && id != "command:ai-chat-window"
            }
            root["appearance"] = appearance
        }
        guard !original.isEqual(to: root),
            var cleaned = try? JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return }
        cleaned.append(0x0A)
        try? cleaned.write(to: target, options: .atomic)
    }

    private static func removeCommands(from section: inout [String: Any], key: String) {
        guard var commands = section[key] as? [String: Any],
            commands["ai-chat"] != nil || commands["ai-chat-window"] != nil
        else { return }
        commands.removeValue(forKey: "ai-chat")
        commands.removeValue(forKey: "ai-chat-window")
        section[key] = commands.isEmpty ? nil : commands
    }
}
