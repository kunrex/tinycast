import Foundation

extension SettingsFileBinding {
    static func compactBarCommands<Root: AnyObject>(
        _ root: Root, _ path: ReferenceWritableKeyPath<Root, [CommandID]>
    ) -> SettingsFileBinding {
        SettingsFileBinding(
            .compactBarCommands,
            read: { root[keyPath: path].map(\.rawValue).settingsJSON },
            write: { json in
                guard let identifiers = [String](settingsJSON: json),
                    let commands = CommandID.compactBarCommands(from: identifiers)
                else { return [.invalidValue(.compactBarCommands)] }
                if root[keyPath: path] != commands { root[keyPath: path] = commands }
                return []
            })
    }
}
