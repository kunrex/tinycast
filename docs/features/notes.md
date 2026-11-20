# Notes (retired)

Tinycast's Notes feature has been removed, including its editor, repository, settings pane and
standalone harnesses. It has no launcher commands, hotkeys, deep-link routes, menu-bar item,
Quick Actions integration or core lifecycle.

## Existing data

User Markdown is left untouched, both in a previously chosen folder and in the former default:

```text
~/Library/Application Support/<bundle-id>/Notes/
```

Open those files in another Markdown editor. Tinycast does not move, convert or delete them.
Stored Notes preferences, window state, aliases, favorites, visibility and hotkey metadata remain
inert; old shortcuts do not reserve chords. Retired `note/*`, Notes command and `settings/notes`
links report unknown and perform no action.

The one-release [NotesSettingsMigration](../migrations.md) removes only the obsolete top-level
`notes` section and exact Notes compact-shortcut IDs from the active channel's settings file and
compact-shortcut defaults. It leaves user files and other preferences alone.

## Legacy backups

Notes documents and preferences are no longer exported or applied. Older format 1 archives remain
readable: supported categories can be restored, while Notes-only archives have no importable
categories. Legacy Notes payload bytes remain in the extracted archive and are not applied to user
folders. See [backup.md](backup.md).
