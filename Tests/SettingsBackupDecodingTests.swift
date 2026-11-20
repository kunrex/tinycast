import Foundation

@main
enum SettingsBackupDecodingTests {
    static func main() throws {
        let binding = HotKeyBinding.globe
        let shortcut = try JSONSerialization.jsonObject(with: JSONEncoder().encode(binding))
        let settings: [String: Any] = [
            "appearance": "dark", "clipboardEnabled": false, "clipboardRetentionDays": 90,
            "navigationEnabled": true, "menuSearchDisabledApps": ["com.example.private"],
            "menuSearchShowsAppleMenu": false, "language": "ja", "notesEnabled": true,
            "notesRendersMarkdown": true, "notesShowsFormattingBar": false, "notesShowsInMenuBar": true,
            "windowManagementEnabled": true, "windowManagementGap": 8,
            "windowManagementCycleMode": "cycle", "windowRoomsShowInLauncher": false
        ]
        let object: [String: Any] = [
            "settings": settings,
            "hotkeys": [
                "togglePalette": shortcut,
                "commands": ["command:switch-windows": shortcut, "command:create-room": shortcut],
                "apps": ["com.example.app": shortcut],
                "windowCommands": ["left-half": shortcut], "windowLayouts": ["old-layout": shortcut],
                "windowRooms": ["old-room": shortcut], "customWindowSizes": ["old-size": shortcut]
            ],
            "favoriteApps": ["com.example.app", "command:switch-windows"],
            "hiddenLauncherItems": ["command:search-menu-items"],
            "hiddenLauncherKinds": ["systemAction"], "launcherAliases": ["com.example.app": "work"],
            "pinnedEmoji": ["😀"],
            "customWindowSizes": [["id": "retired"]], "windowLayouts": [["id": "retired"]],
            "windowRooms": [["id": "retired"]]
        ]
        let backup = try SettingsBackup(json: JSONSerialization.data(withJSONObject: object))
        precondition(backup.settings?.appearance == "dark")
        precondition(backup.settings?.clipboardEnabled == false)
        precondition(backup.settings?.clipboardRetentionDays == 90)
        precondition(backup.settings?.navigationEnabled == true)
        precondition(backup.settings?.navigationMimicsMacOS == nil)
        precondition(backup.settings?.menuSearchDisabledApps == ["com.example.private"])
        precondition(backup.settings?.menuSearchShowsAppleMenu == false)
        precondition(backup.settings?.language == "ja")
        precondition(backup.hotkeys?.togglePalette == binding)
        precondition(backup.hotkeys?.commands?["command:switch-windows"] == binding)
        precondition(backup.hotkeys?.apps?["com.example.app"] == binding)
        precondition(backup.favoriteApps == ["com.example.app", "command:switch-windows"])
        precondition(backup.hiddenLauncherItems == ["command:search-menu-items"])
        precondition(backup.hiddenLauncherKinds == ["systemAction"])
        precondition(backup.launcherAliases == ["com.example.app": "work"])
        precondition(backup.pinnedEmoji == ["😀"])
        let encoded = try JSONSerialization.jsonObject(with: backup.encoded()) as! [String: Any]
        let encodedSettings = encoded["settings"] as! [String: Any]
        let encodedHotkeys = encoded["hotkeys"] as! [String: Any]
        for key in ["customWindowSizes", "windowLayouts", "windowRooms"] {
            precondition(encoded[key] == nil)
            precondition(encodedHotkeys[key] == nil)
        }
        precondition(encodedHotkeys["windowCommands"] == nil)
        for key in settings.keys where key.hasPrefix("window") || key.hasPrefix("notes") {
            precondition(encodedSettings[key] == nil)
        }
        let decodedAgain = try SettingsBackup(json: backup.encoded())
        precondition(decodedAgain.hotkeys?.commands?["command:switch-windows"] == binding)
        precondition(decodedAgain.settings?.clipboardRetentionDays == 90)
        for enabled in [true, false] {
            var updated = backup
            updated.settings?.navigationMimicsMacOS = enabled
            let restored = try SettingsBackup(json: updated.encoded())
            precondition(restored.settings?.navigationMimicsMacOS == enabled)
            precondition(restored.hotkeys?.commands?["command:switch-windows"] == binding)
        }
        print("SettingsBackupDecodingTests passed")
    }
}
