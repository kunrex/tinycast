---
title: Deeplinks
description: Run any command from a tinycast:// link, with text and arguments, from Karabiner, Shortcuts, scripts or a web page.
---

**Anything you can give a shortcut, you can also run from a link.** Use links from
Karabiner-Elements, Shortcuts, a Stream Deck, a script or a web page:

```sh
open -g "tinycast://command/clipboard-history"
```

## Get a link

Copy the link instead of typing it. Rows you create, like quicklinks, use an ID that stays the same
when you rename them.

- **In the launcher**: select a row and press <kbd>⇧</kbd><kbd>⌘</kbd><kbd>C</kbd>, or open its
  actions with <kbd>⌘</kbd><kbd>K</kbd> and choose **Copy Deeplink**. Anything you typed into the
  row's fields is part of the link.
- **In Settings**: right-click a shortcut field and choose **Copy Deeplink**.

Apps and System Settings panes have no Tinycast link. Use `open -a` and `x-apple.systempreferences:`
for them.

## What links can do

| Link                                   | What it does                                          |
| -------------------------------------- | ----------------------------------------------------- |
| `tinycast://`                          | Opens the launcher                                    |
| `tinycast://search?fallbackText=2%2B2` | Opens the launcher with `2+2` typed                   |
| `tinycast://command/clipboard-history` | Runs a built-in command                               |
| `tinycast://system-action/lock-screen` | Runs a [system action](/docs/launcher/system-actions) |
| `tinycast://settings/permissions`      | Opens Settings on a pane                              |

A link to a command that opens a screen works like its shortcut: open it twice and the screen
closes. Retired `note/*`, `command/show-notes`, `command/create-note`, `command/search-notes`
and `settings/notes` links report unknown and do nothing, including when they carry input.
Retired chat, Quick AI, window-management and Uninstall links likewise perform no action.

## Send text and arguments

Links take three parameters. Encode their values for a URL.

- **`fallbackText`** types text into the command's first field. For example,
  `tinycast://command/search-files?fallbackText=~/Downloads/` opens Search Files already searching.
- **`arguments`** fills fields. Use JSON: an object fills fields by name, a list fills them in order.
- **`context`** fills an editor. For example,
  `tinycast://command/create-quicklink?context={"name":"Docs","link":"https://example.com"}` opens a
  new quicklink already filled in. Nothing is saved until you press Save.

`fallbackText` works with Clipboard History, Search Emoji & Symbols, Calculator History, Search
Quicklinks, Search Files, Define Word, Search Snippets, Search Custom Commands, Search Menu Items,
Switch Windows and Create Snippet.

A few more things links can carry:

- **Many quicklinks or snippets at once.** Give `context` a list, like
  `[{"name":"Docs","link":"https://example.com"},{"name":"Mail","link":"mailto:"}]`. Tinycast asks
  before it adds them, and skips any you already have.
- **A volume level.** `tinycast://system-action/set-volume?fallbackText=40` sets the volume to 40%
  without the picker.

If a link's input is broken or too long, Tinycast says it can't open the link and runs nothing.

## Links that ask first

**A link from another app or a web page asks before it runs, if it carries text or arguments, or if
it acts outside Tinycast.** Acting outside Tinycast includes system actions,
quicklinks, snippets, custom commands and Apple Shortcuts. The question shows the text or
arguments, so you can see what will run. You can choose:

- **Always Allow**: run it now, and never ask again for this command with this exact input.
- **Run Once**: run it now, and ask next time.
- **Cancel**: run nothing. Pressing <kbd>Return</kbd> chooses this.

A link with no input that only opens a Tinycast screen, like Clipboard History or Settings, never
asks. Restart, Shut Down and other big system actions still ask their own question too.

To make a command ask again, remove it in **Settings → General → Deeplinks**. This list is never
part of a backup.

A quicklink that points to a `tinycast://` link runs it without asking, because you made it. It
can't point to another quicklink.

## Karabiner-Elements

Use `open -g`, so the link runs without bringing Tinycast forward:

```json
{
  "description": "Hyper+V opens Tinycast clipboard history",
  "manipulators": [
    {
      "type": "basic",
      "from": {
        "key_code": "v",
        "modifiers": { "mandatory": ["left_command", "left_control", "left_option", "left_shift"] }
      },
      "to": [{ "shell_command": "open -g 'tinycast://command/clipboard-history'" }]
    }
  ]
}
```

Snippets and Paste Sequentially need `open -g`, so
the text goes to the app you're in.

## Extension links

Extension commands use their own links, like `raycast://extensions/<owner>/<extension>/<command>`.
See [Compatibility](/docs/extensions/compatibility).
