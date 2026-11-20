import Foundation

extension CommandID: SettingsFileRawValue {}

@main
@MainActor
struct CompactBarTests {
    private static var failures = 0

    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() throws {
        let defaults = CommandID.defaultCompactBarCommands
        check(
            defaults == [.clipboardHistory, .searchEmoji, .searchFiles, .searchQuicklinks],
            "the always-on commands lead the default")
        check(CommandID.compactBarOptions.count == 6, "six surviving destinations")
        check(CommandID(rawValue: "command:ai-chat") == nil, "retired Quick AI command is ignored")
        check(CommandID(rawValue: "command:ai-chat-window") == nil, "retired AI Chat command is ignored")
        for count in 0...CommandID.compactBarLimit {
            let commands = Array(defaults.prefix(count))
            var selection = CompactBarSelection()
            selection.move(by: -1, commands: commands)
            check(selection.command == nil, "Left stops at Search with \(count) slots")
            for command in commands {
                selection.move(by: 1, commands: commands)
                check(selection.command == command, "Right follows configured order")
            }
            selection.move(by: 1, commands: commands)
            check(selection.command == commands.last, "Right stops at the last visible slot")
            for _ in commands { selection.move(by: -1, commands: commands) }
            check(selection.command == nil, "Left returns to Search")
        }

        var selection = CompactBarSelection(command: .searchFiles)
        selection.reconcile(commands: [.searchFiles, .clipboardHistory])
        check(selection.command == .searchFiles, "reordering preserves the selected command")
        selection.reconcile(commands: [.clipboardHistory])
        check(selection.command == nil, "removing or disabling the selected command returns to Search")
        selection.command = .openCamera
        selection.move(by: 1, commands: defaults)
        check(selection.command == defaults.first, "an obsolete selection starts from Search")

        check(CommandID.compactBarCommands(from: []) == [], "empty means no shortcuts")
        let chosen: [CommandID] = [.searchSnippets, .searchEmoji, .mySchedule, .searchFiles]
        check(
            CommandID.compactBarCommands(from: chosen.map(\.rawValue)) == chosen,
            "all additional destinations retain their order")
        for invalid in [
            ["unknown"], [CommandID.quit.rawValue],
            [CommandID.searchFiles.rawValue, CommandID.searchFiles.rawValue],
            Array(CommandID.compactBarOptions.prefix(5)).map(\.rawValue)
        ] {
            check(
                CommandID.compactBarCommands(from: invalid) == nil,
                "invalid command lists are rejected whole")
        }

        let suite = "CompactBarTests.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let key = AppSettingsKey.compactBarCommands.rawValue
        check(
            preferences.stringArray(forKey: key).flatMap(CommandID.compactBarCommands(from:))
                ?? defaults == defaults, "missing preferences use defaults")
        preferences.set(chosen.map(\.rawValue), forKey: key)
        check(
            preferences.stringArray(forKey: key).flatMap(CommandID.compactBarCommands(from:)) == chosen,
            "stable identifiers round trip through isolated preferences")
        let retired = ["command:ai-chat", "command:ai-chat-window"]
        let legacy = [chosen[0].rawValue, retired[0], chosen[1].rawValue, retired[1]]
        preferences.set(legacy, forKey: key)
        preferences.synchronize()
        let restarted = UserDefaults(suiteName: suite)!
        check(
            restarted.stringArray(forKey: key).flatMap(CommandID.compactBarCommands(from:))
                == Array(chosen.prefix(2)),
            "restart removes only retired commands and retains the surviving custom order")
        check(
            CommandID.compactBarCommands(from: retired) == [],
            "an entirely retired selection stays empty rather than restoring defaults")
        check(
            CommandID.compactBarCommands(from: legacy + ["command:ai-chat-typo"]) == nil,
            "a retired entry does not conceal an unknown identifier")
        check(
            CommandID.compactBarCommands(from: legacy + [chosen[0].rawValue]) == nil,
            "a retired entry does not conceal duplicate survivors")
        preferences.set([], forKey: key)
        check(
            preferences.stringArray(forKey: key).flatMap(CommandID.compactBarCommands(from:)) == [],
            "an explicitly empty preference stays empty")

        let state = Commands()
        let binding = SettingsFileBinding.compactBarCommands(state, \.value)
        let legacyFile = SettingsFileFormat.render([.compactBarCommands: legacy.settingsJSON])
        let legacyParsed = try SettingsFileFormat.parse(legacyFile)
        check(
            binding.write(legacyParsed.values[.compactBarCommands]!).isEmpty
                && state.value == Array(chosen.prefix(2)),
            "settings.json filters exactly retired identifiers with the shared parser")
        check(
            binding.write(chosen.settingsJSON).isEmpty && state.value == chosen,
            "settings binding accepts the configured order")
        let encoded = SettingsFileFormat.render([.compactBarCommands: binding.read()])
        let decoded = try SettingsFileFormat.parse(encoded)
        check(
            decoded.values[.compactBarCommands] == chosen.settingsJSON,
            "settings JSON round trip retains identifiers")
        for invalid: SettingsFileJSON in [
            .array([.string("unknown")]), .array([.string(CommandID.quit.rawValue)]),
            .array([.string(CommandID.searchSnippets.rawValue), .string(CommandID.searchSnippets.rawValue)]),
            Array(CommandID.compactBarOptions.prefix(5)).settingsJSON, .bool(false),
            (legacy + ["unknown"]).settingsJSON,
            (legacy + [chosen[0].rawValue]).settingsJSON,
            .array([.string("command:ai-chat"), .number(42)])
        ] {
            check(
                !binding.write(invalid).isEmpty && state.value == chosen,
                "invalid settings leave the current configuration intact")
        }
        check(
            binding.write(.array([])).isEmpty && state.value.isEmpty,
            "settings binding accepts zero shortcuts")
        retiredNotesPreferences(preferences, key: key)
        retiredNotesSettings(binding, state: state)
        print("Compact bar tests: \(failures) failure(s)")
        exit(failures == 0 ? 0 : 1)
    }

    private static func retiredNotesPreferences(_ preferences: UserDefaults, key: String) {
        let retired = ["command:show-notes", "command:create-note", "command:search-notes"]
        let valid: [CommandID] = [.searchSnippets, .searchEmoji]
        let fixtures: [([String], [CommandID])] = retired.map { identifier in
            ([valid[0].rawValue, identifier, valid[1].rawValue], valid)
        } + [
            ([retired[0], valid[1].rawValue, retired[1], retired[2]], [valid[1]]),
            (retired, []),
            ([], [])
        ]
        for (identifiers, expected) in fixtures {
            check(
                CommandID.compactBarCommands(from: identifiers) == expected,
                "FORWARD: retiring Notes preserves valid entries and order in \(identifiers)")
            preferences.set(identifiers, forKey: key)
            let restored = preferences.stringArray(forKey: key)
                .flatMap(CommandID.compactBarCommands(from:))
                ?? CommandID.defaultCompactBarCommands
            check(
                restored == expected,
                "FORWARD: legacy preference \(identifiers) does not restore defaults or Notes")
        }
    }

    private static func retiredNotesSettings(_ binding: SettingsFileBinding, state: Commands) {
        let retired = ["command:show-notes", "command:create-note", "command:search-notes"]
        let survivors = [CommandID.searchEmoji.rawValue, CommandID.searchSnippets.rawValue]
        for identifiers in [retired, [], [retired[0]] + survivors + retired] {
            let expected = identifiers.isEmpty || identifiers == retired
                ? [] : [CommandID.searchEmoji, .searchSnippets]
            check(binding.write(identifiers.settingsJSON).isEmpty && state.value == expected,
                "retired settings identifiers are filtered, preserving order and explicit empty")
        }
        for invalid in [
            ["unknown"], [CommandID.quit.rawValue],
            [CommandID.searchEmoji.rawValue, CommandID.searchEmoji.rawValue],
            Array(CommandID.compactBarOptions.prefix(5)).map(\.rawValue)
        ] {
            let mixed = [retired[0]] + invalid + Array(retired.dropFirst())
            check(CommandID.compactBarCommands(from: mixed) == nil,
                "retired plus genuinely invalid identifiers reject the whole value")
            let previous = state.value
            check(!binding.write(mixed.settingsJSON).isEmpty && state.value == previous,
                "retired plus invalid settings do not change the selection")
        }
    }

    private final class Commands {
        var value = CommandID.defaultCompactBarCommands
    }
}
