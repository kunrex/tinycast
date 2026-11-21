import Foundation

/// What `SettingsBackup.SettingsData` carries, written out so a new setting has to be considered.
enum SettingsBackupCoverage {
    static let mirrored: [String: AppSettingsKey] = [
        "clipboardEnabled": .clipboardEnabled,
        "clipboardRetentionDays": .clipboardRetention,
        "clipboardDefaultAction": .clipboardDefaultAction,
        "clipboardDisabledApps": .clipboardDisabledApps,
        "hyperKey": .hyperKey,
        "hyperKeyIncludesShift": .hyperKeyIncludesShift,
        "hyperKeyQuickPress": .hyperKeyQuickPress,
        "hyperKeySecureInputCompatibility": .hyperKeySecureInputCompatibility,
        "showInMenuBar": .showInMenuBar,
        "automaticallyCheckForUpdates": .automaticallyCheckForUpdates,
        "emojiSkinTone": .emojiSkinTone,
        "emojiGridColumns": .emojiGridColumns,
        "popToRootSeconds": .popToRootTimeout,
        "escapeKeyBehavior": .escapeKeyBehavior,
        "appearance": .appearance,
        "language": .language,
        "calcNumberStyle": .calcNumberStyle,
        "interfaceSize": .interfaceSize,
        "compactMode": .compactMode,
        "compactBarCommands": .compactBarCommands,
        "searchScopes": .searchScopes,
        "launcherShowsSuggestions": .launcherShowsSuggestions,
        "rootSearchSensitivity": .rootSearchSensitivity,
        "openOnCursorScreen": .openOnCursorScreen,
        "paletteDraggable": .paletteDraggable,
        "animationsEnabled": .animationsEnabled,
        "spotlightTintEnabled": .spotlightTintEnabled,
        "spotlightTintColor": .spotlightTintColor,
        "fileSearchEnabled": .fileSearchEnabled,
        "fileSearchScopes": .fileSearchScopes,
        "fileSearchIgnorePatterns": .fileSearchIgnorePatterns,
        "fileSearchRemovedDefaultPatterns": .fileSearchRemovedDefaultPatterns,
        "fileSearchShowInLauncher": .fileSearchShowInLauncher,
        "customCommandsEnabled": .customCommandsEnabled,
        "customCommandsShowInLauncher": .customCommandsShowInLauncher,
        "snippetsShowInLauncher": .snippetsShowInLauncher,
        "snippetDefaultAction": .snippetDefaultAction,
        "navigationEnabled": .navigationEnabled,
        "navigationMimicsMacOS": .navigationMimicsMacOS,
        "menuSearchDisabledApps": .menuSearchDisabledApps,
        "menuSearchShowsAppleMenu": .menuSearchShowsAppleMenu,
        "quicklinksEnabled": .quicklinksEnabled,
        "quicklinksShowInLauncher": .quicklinksShowInLauncher,
        "quicklinkOpensNewWindow": .quicklinkOpensNewWindow,
        "quicklinkPassesSelectedText": .quicklinkPassesSelectedText,
        "quicklinkConfirmsBeforeDelete": .quicklinkConfirmsBeforeDelete,
        "appleShortcutsEnabled": .appleShortcutsEnabled,
        "extensionsShowInLauncher": .extensionsShowInLauncher,
        "supportReminders": .supportReminders
    ]

    /// The `SettingsData` fields no `AppSettings` key stands behind, and what they read instead.
    static let externallySourced: [String: String] = [
        "launchAtLogin": "Read from LaunchAtLogin, which owns the login item, not UserDefaults."
    ]

    /// Keys kept out of a backup on purpose, each with the reason it has to stay out.
    static let deliberatelyExcluded: [String: String] = [
        AppSettingsKey.dictationEnabled.rawValue:
            "Microphone capture is an opt-in capability on this Mac; a backup must not enable it.",
        AppSettingsKey.dictationMode.rawValue: "Dictation preferences stay local until backup supports them.",
        AppSettingsKey.dictationModel.rawValue: "Downloaded models are local to this Mac.",
        AppSettingsKey.dictationLanguage.rawValue:
            "Dictation preferences stay local until backup supports them.",
        AppSettingsKey.dictationMicrophone.rawValue: "Names a microphone attached to this Mac.",
        AppSettingsKey.dictationDestination.rawValue:
            "An import must not change where dictated text is sent.",
        AppSettingsKey.dictationAdaptsCapitalization.rawValue:
            "Dictation preferences stay local until backup supports them.",
        AppSettingsKey.dictationLiveInsertion.rawValue:
            "Dictation preferences stay local until backup supports them.",
        AppSettingsKey.dictationPlaysSounds.rawValue:
            "Dictation preferences stay local until backup supports them.",
        AppSettingsKey.dictationIdleRelease.rawValue:
            "Dictation memory use stays a device-local preference.",
        AppSettingsKey.clipboardTextSearchEnabled.rawValue:
            "Background OCR is an opt-in processing choice on this Mac; a backup must not enable it.",
        AppSettingsKey.snippetsEnabled.rawValue:
            "Doubles as keyword-expansion consent; an import must not enable keystroke listening.",
        AppSettingsKey.extensionPackageManager.rawValue:
            "Names a tool on this Mac; the machine a backup lands on may not have it.",
        AppSettingsKey.extensionCustomSearchPaths.rawValue:
            "Machine-local toolchain paths; the Mac a backup lands on may not have them, or may have "
            + "something else there.",
        AppSettingsKey.extensionsEnabled.rawValue:
            "Doubles as consent to run third-party JavaScript; an import must not switch it on.",
        AppSettingsKey.allowedDeepLinks.rawValue:
            "Each entry lets a web page or app run a command unasked; an import must not grant that.",
        AppSettingsKey.palettePosition.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.paletteExpandedCenterDisplays.rawValue:
            "Machine-local geometry: every entry names a display this Mac has, and no other one.",
        AppSettingsKey.autoSwitchInputSource.rawValue:
            "Names a keyboard input source installed on this Mac; another Mac may not have it.",
        AppSettingsKey.aiConnections.rawValue:
            "AI connection metadata stays on the Mac with the Keychain credentials it describes.",
        AppSettingsKey.aiShownModels.rawValue:
            "Names the models of this Mac's own connections, which another Mac may not have.",
        AppSettingsKey.aiDisabledRoutes.rawValue:
            "Names this Mac's own API connections and on-device model, which travel in no backup.",
        AppSettingsKey.quickActionsEnabled.rawValue:
            "Grants keystroke delivery into other apps through the Accessibility permission, and a "
            + "flag that grants a capability is never carried by a backup.",
        AppSettingsKey.quickActionModel.rawValue:
            "Names an external AI destination for text taken from whatever app is frontmost; an "
            + "import must not choose one.",
        AppSettingsKey.quickActionModelOverrides.rawValue:
            "Sends one action's text to its own AI destination, some keyed by actions that exist only "
            + "on the Mac that made them.",
        AppSettingsKey.quickActionPreviews.rawValue:
            "Says which actions may rewrite a document without showing the result first, which is a "
            + "decision each Mac makes about its own text.",
        AppSettingsKey.quickActionInstructions.rawValue:
            "Custom model instructions change transformed results and must not move unseen.",
        AppSettingsKey.quickActionLanguage.rawValue:
            "Follows the language the person at this Mac reads, not the one who wrote the backup.",
        AppSettingsKey.snippetsFolder.rawValue:
            "Names a folder on this Mac; the one a backup lands on may not have it.",
        AppSettingsKey.settingsFileEnabled.rawValue:
            "Lets a file on this Mac change its settings; an import must not hand that to another."
    ]
}
