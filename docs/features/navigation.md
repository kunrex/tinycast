# Navigation

Commands that move you somewhere rather than changing something, behind one switch:
**Switch Windows** raises any open window of any running app, or activates a regular running app
with no eligible windows. **Switch Windows Backwards** walks the
same list the other way, and **Search Menu Bar Items** presses any item in the front app's menu bar. The second has its own page —
[menu-search.md](menu-search.md) — because its internals are a menu walk; this page owns the
switcher and the pane the two share.

Ships **off**. Settings › Navigation is the switch, and while it is off none of them is in the
launcher and a still-recorded shortcut for any does nothing.

Settings also offers **Mimic macOS**, off by default, above the window command shortcuts. With
Navigation enabled it replaces ⌘Tab / ⌘⇧Tab with the searchable window switcher. The first press
opens, loads and steps immediately; repeats cycle. Experimentally, releasing Command leaves the
picker open, even with Shift still held. Tab / Shift-Tab and the existing arrow navigation select
rows; Enter or a row click switches. Typing searches with or without Command held. A fresh ⌘Tab
on the open picker cycles the current selection without reloading. Escape follows the standard
palette behavior (clear the query, then leave). Launcher invocation and custom-shortcut first-open
and release-to-activate behavior are unchanged.

The two saved window shortcuts remain persisted and conflict-reserved, but are temporarily
**unregistered** (Carbon, modifier-only and Secure Input equivalents) and guarded at dispatch.
Their recorders remain disabled. Turning Mimic macOS off restores the same bindings. Menu Search,
aliases and launcher visibility are unchanged: the per-command checkboxes only control visibility,
never execution. Navigation's master switch is the capability gate.

Accessibility is required. Explicitly checking Mimic macOS uses the existing permission gate;
startup and settings-file/backup application never prompt. Missing permission or a failed tap install
reports in the existing HUD and leaves native macOS switching available. Saved shortcuts remain
suppressed while the toggle is on, including during failure or Secure Input; uncheck it to restore
them. Secure Input is **not supported**. The preference persists locally and travels in settings
backups and `navigation.mimicsMacOS` in the settings file.

## Invariants

- **The sweep is synchronous, and that is deliberate.** `WindowSwitchSweep.snapshot` visits apps and
  their windows — one level, two AX reads each — where the menu walk descends a tree. A
  `Task.detached` here would buy a "Reading windows…" state nobody would ever see, and cost a
  revision counter to keep superseded sweeps from publishing.
- **A live `AXUIElement` never leaves the main actor, and never outlives the show.** The pure entry
  carries a `handle`; `WindowSwitchSession` holds the `handle → Element` table `@ObservationIgnored`
  and drops it in `reset()`, which `hidePalette` and every mode change call. So every open sweeps
  anew — `WindowSwitchCoordinator.load()`, through `PaletteCoordinator.onScreenOpening` — and a
  screen restored inside the Pop to Root window lists today's windows, not an empty snapshot.
- **Nothing in `Model/` knows about AX elements.** `WindowSwitchEntry` takes `appRank` as a number
  someone else measured, so `WindowSwitchOrder` and `WindowSwitchQuery` stay Foundation-only and the
  harness compiles the shipped sources.
- **The order is total.** `(isMinimized, appRank, appName, handle)` — so a sweep that enumerated apps
  in a different order sorts identically, and minimized windows are always one run at the end rather
  than interleaved.
- **Accessibility is gated twice**, on open and again on activate: a grant revoked while the palette
  is open must not reach `AXUIElementPerformAction`. The open gate sits in both `show()` and
  `load()`, because a restore reaches `load()` alone.
- **Activation hides with `restoreFocus: false`.** Restoring focus reactivates the displaced app,
  which races the raise and can land on the wrong window.
- **`Platform/AXWindowAccess` is the one shared AX window layer.** `minimize`, `unminimize`,
  `focus` and app candidate enumeration live there, shared with durable recovery.
  The switcher's sweep and live element table remain owned by WindowSwitcher.

## How it is put together

| Piece | Holds |
| --- | --- |
| `Model/WindowSwitchEntry.swift` | one row: handle, app, title, window presence, minimized, rank, search fields |
| `Model/WindowSwitchOrder.swift` | the MRU sort, pure and total |
| `Model/WindowSwitchPolicy.swift` | which windows the sweep offers, pure |
| `Model/WindowSwitchQuery.swift` | ranking over `SearchRelevance`, capped at 200 rows |
| `Service/WindowZOrder.swift` | the one `CGWindowList` call: per-pid front rank |
| `Service/WindowSwitchSweep.swift` | the AX sweep, and the live element table it hands back |
| `Service/WindowSwitchSession.swift` | the observable state — snapshot, filtered rows, elements, exits |
| `UI/WindowSwitchCoordinator.swift` | show, activate, the ⌘K actions, the switch, the failure reports |
| `UI/WindowSwitchScreen.swift` | the `PaletteScreen` conformance, the ⌘K menu, the two empty states |
| `UI/WindowSwitchList.swift` | the list and its row: app icon, title, app name |

## Recency without a private symbol

The MRU order comes from the window server's own front-to-back list: one
`CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)`, keeping
layer 0 — the normal window band, not the menu bar, Dock or overlay panels — and recording where each
pid first appears. Only `kCGWindowName` is permission-gated, and titles come from AX instead, so the
call needs no Screen Recording grant.

The rank is therefore **per app, not per window**: mapping a `CGWindowID` onto an `AXUIElement` needs
the private `_AXUIElementGetWindow`, and the app's own `kAXWindowsAttribute` order already gives the
windows inside one app front-to-back. [Recovery](window-recovery.md#restore-policy) resolves that
symbol in `AXWindowAccess.windowID(of:)` because a saved home must outlive its element; the
switcher keeps its per-app rank, which needs nothing private. An app with nothing on screen — everything minimized, or every
window on another Space — gets no rank at all and sorts after the ranked ones by name.

The alternative was a long-lived `NSWorkspace.didActivateApplicationNotification` observer with its
own LRU and its own lifetime. This needs neither, and it is right on the first summon after launch
rather than after the user has switched apps once.

## The sweep

`WindowSwitchSweep` walks `AXWindowAccess.candidates()` — regular-policy, non-terminated, not us —
and takes every window `WindowSwitchPolicy` accepts: a standard-subrole one, or a minimized one that
still has a minimize button. A **minimized** window is exactly what a switcher is for, and a window
on another Space reports no frame until it is raised, so requiring one would hide it.

An app that contributes no eligible windows gets exactly one app-only row, including apps that
report no windows at all. Apps with eligible windows keep just their existing window rows. The
app-only row uses the app name as its title, the same icon and per-app rank, and a unique handle in
the same live element table, with a nil window. It sorts like a non-minimized row; unranked apps
therefore sort by name after ranked rows and before minimized windows.

**A minimized window changes subrole.** Finder and Transmission report their minimized windows as
`AXDialog`, not `AXStandardWindow`, and back to `AXStandardWindow` when restored, so a subrole test
alone drops exactly the rows a switcher exists for. A sheet cannot minimize, so the minimize button
is what still tells a minimized window from a real dialog. The policy is Foundation-only, so the
harness covers the rule rather than the attribute reads.

Each element gets a 0.2 s messaging timeout, the same as the recovery sweep and the menu walk, so
one hung app cannot stall the summon.

The app icon rides on the entry as a `FileIconStamp` and its bundle URL, and the row draws it through
`EntryIconView(source: .file(stamp:))` — so `IconCache` decodes once per app however many windows it
contributes.

## Stepping with the shortcut

Pressed again while the switcher is open, its shortcut steps the selection down the list instead of
closing the palette; the first step lands on the window behind the current one. Switch Windows
Backwards opens the same list and steps up it, wrapping to the last window, so the two interleave
like ⌘Tab and ⌘⇧Tab. A step made with the chord's modifiers still held arms one `flagsChanged`
local monitor, and letting go switches to the selection, as ⌘Tab does. The first armed step's
modifiers are the ones that count, so letting go of ⇧ alone mid-walk switches nothing. A single press never arms it, so pressing once and typing still
searches; Escape hides the palette, and the next modifier change finds it gone and switches
nothing.

## Native capture lifetime

`WindowSwitchCoordinator` owns `CommandTabTap`; AppCore starts and stops the coordinator and shares
its single `SecureInputMonitor` with Hyper Key. Sleep, lock, inactive sessions and shortcut recording
cancel the gesture and stop new capture. A swallowed physical Tab press keeps a drain-only tap until
its matching release (including repeats across modifier changes); resuming reuses that same ownership.
The drain expires after five seconds if macOS never delivers the release. Termination and deinit force
teardown rather than retaining a worker. Wake/unlock/session return and recording completion reapply the
settings. Missing Accessibility and installation failure retry through the existing health ticker;
TCC changes recheck permissions. Global tap-removal notifications recover only an unhealthy owned tap
while capture is wanted; unrelated removals leave healthy capture and policy-paused drains untouched.
System timeout/user-input disable cancels the old
gesture and reenables the tap without forgetting physical press ownership. Secure Input, revoked
grants or an OS-removed tap can hide releases: pairing cannot be guaranteed on those OS-controlled
edges, after the bounded drain deadline, or at process exit. No synthetic release is posted.
No new global service owner or persisted command-enabled flags exist.

The modifying HID tap has its own run-loop thread. `CommandTabEngine` is Foundation-only and accepts
only Command+Tab with optional Shift, not Control, Option or fn. Initial downs fix ownership for the
whole press: passed downs keep passing their repeats and up; swallowed downs suppress their repeats
and up even when modifiers change. Autorepeat without an initial down cannot acquire ownership. Tagged Hyper Key and paste/text-injection synthetics
pass through. No AX window reads, main-actor waits or UI effects run in the callback. One AsyncStream
consumer delivers ordered step/repeat/release intents on main. Cancellation increments a generation,
so queued actions from a stopped, disabled or superseded tap cannot open or activate stale selections;
the coordinator also checks the current presentation identity before stepping. Local printable-key
translation is scoped to the key switcher during a native gesture and disarmed on Command release,
never global typing. The native picker identity remains until cancellation or session reset so plain
Tab can cycle without arming the custom-shortcut release monitor.

## Raising

`activate` un-minimizes if it has to, raises the window inside its app, sets `AXFrontmost`, then calls
`NSRunningApplication.activate()`. All four steps are needed and none is redundant: the raise alone
orders the window inside an app that is not frontmost, and activating alone brings the app's *own*
front window forward rather than the chosen one. Activating is also what pulls another Space forward,
so the switcher needs no Space handling of its own.

An app-only row calls `NSRunningApplication.activate()` without any window AX actions. It does not
launch or reopen the app to manufacture a window. The same permission, live-app and focus-restoration
guards apply, and Hide and Quit remain available; Minimize is absent and its shortcut does nothing.

Every step is allowed to fail quietly. What is reported is only the case the user can act on: the
window's app quit between the sweep and the ↵.

## The ⌘K menu

| Row | Does | Palette |
| --- | --- | --- |
| Switch to Window (↵) | `activate`, as above | hides |
| Minimize Window (⌃⇧M) | sets `kAXMinimized`; absent on a minimized row | stays; the row joins the minimized run |
| Hide Application (⌃⇧H) | `NSRunningApplication.hide()`, then `kAXHidden` if refused | hides |
| Quit Application (⌃⇧Q) | `NSRunningApplication.terminate()` | stays; the app's rows leave on exit |

- **Minimize marks the row instead of sweeping again.** `kAXMinimized` can still read false while
  the Dock animation runs, so a fresh sweep could leave the row where it was. A full-screen window cannot
  minimize and is skipped, so its row never claims to be minimized.
- **Quit removes rows on the app's exit, not on the request.** While rows are shown the session
  observes `DidTerminateApplicationMessage` and drops that pid's rows; `reset()` removes the
  observer. A quit refused by a save sheet therefore keeps its rows, and an app quit from anywhere
  else leaves the list too.
- **The chords are ⌃⇧, not ⌘M and ⌘H.** The app menu's Minimize and Hide take those before the
  palette sees them.
- **Hide closes the palette without restoring focus.** Restoring focus activates the app that was in
  front, and activating a hidden app unhides it.

## Wiring

- **`CommandID.switchWindows`** (`command:switch-windows`), `CommandID.switchWindowsBackwards`
  (`command:switch-windows-backwards`) and `CommandID.searchMenuItems` are all named by
  `SettingsTab.navigation.ownedCommands`, which is the whole of what moves them out of
  Settings › Commands: `LauncherItemsSection` filters on `settingsOwner == nil`, and `VisibilityStore`
  skips the `Enable Commands` category gate for a pane-owned command. None adds an
  `AppEntry.Kind`, a `HotKeyAction` case or a `VisibilityStore` category — they are plain `.command`
  entries.
- **`navigationEnabled`** (off) is the switch. `AppCore.observeFeatureSwitches` tracks it once and
  reprojects into both coordinators; each owns only its own commands and its own palette mode, so
  neither knows about the other. `AppIndex.isCommandEnabled` feeds `hotKeys.allowsAction`, so every
  shortcut goes dead with the switch, and each `show()` re-guards the flag anyway.
- **`menuSearchDisabledApps`** (empty) is the exclusion list. It ships with no seeded entries, unlike
  the clipboard's: a menu read only ever happens because the user asked for one.
- **`menuSearchShowsAppleMenu`** (off) lists the Apple menu's own items. Off by default because that
  menu is identical under every app, so it would pad every snapshot with the same ~50 rows;
  [menu-search.md](menu-search.md) owns how it is applied.
- **Both ride in the pane's own `Search Menu Bar Items` section, beside the command row itself.**
  `FeatureCommandsSection` takes `excluding: [.searchMenuItems]` and the section draws that one
  command through `FeatureCommandRow`, so a command added to `ownedCommands` later still appears
  under `Commands` without a second edit. A list of excluded apps in a box of its own read as
  belonging to the pane rather than to one command, which is what this section exists to fix;
  `DisabledApplicationsList` is the shared half — the rows and the picker — that Settings ›
  Clipboard still wraps in a `DisabledApplicationsSection` of its own.
- Both settings ride in backups. Neither grants a permission class of its own — Accessibility is
  already required for paste — unlike `snippetsEnabled`.
- **There is deliberately no "Show in launcher" switch.** The per-command checkboxes in
  `FeatureCommandsSection` already are one, and a second would be a switch over rows the pane lists.

## Testing

`Tests/WindowSwitchTests.swift` covers the pure half: the handle-derived id, the untitled-window
fallback, the name/owner split in the search fields, the MRU order and its totality under a shuffled
sweep, the minimized run at the end, which windows the sweep offers, ranking, and the 200-row cap
under both an empty and a matching query. App-only regression cases cover distinct row identities,
mixed ordering and app-name queries. The coordinator harness checks selection, activation without
window AX actions, minimize guards, and app-level Hide and Quit for app-only rows.

The harness also compiles `WindowSwitchSweep` and the shared `Platform/AXWindowAccess` without
any recovery sources, guarding their independence. It does not exercise live AX calls.
`WindowZOrder` is not compiled into the harness; AX and `CGWindowList` need manual verification,
particularly:

`CommandTabTests` covers pure recognition, repeat direction, Shift-held release, release fallback,
paired ups, unrelated modifier passthrough, synthetic filtering, generation cancellation and private
unposted tap callbacks. It exercises ordered delivery while main is blocked, timeout/user-input
recovery, revoked grants, Secure Input, failed installation, retry and teardown. The coordinator
harness uses concrete fixtures (no live AX window actions) to verify native first-press stepping,
query landing before filtering (including a reverse stale index), release without activation,
explicit screen activation, forward/reverse Tab wrapping, fresh gestures without reloading, stale
presentation cancellation, custom first-press search, recording and
feature gates. Global removal injection verifies two explicit activations without healthy-tap churn, genuine loss
recovery without prompting, replacement feedback suppression and policy-paused drains. The real-tap
harness also repeats independent gestures and palette-reset cancellation on one private installation;
the coordinator harness still uses a tap fixture rather than a real tap. `HotKeyDispatchTests` checks suppression/restoration without changing stored bindings.

Real-machine verification is still required:

- Check Mimic macOS with Navigation on: ⌘Tab selects the second window immediately, ⌘⇧Tab selects
  the last, repeats interleave, and releasing Command with Shift held leaves the picker open.
  Tab / Shift-Tab wrap, arrows navigate, and typing filters before and after release. Enter or a row
  click activates exactly once. Fresh ⌘Tab cycles the open picker without reloading; Escape cancels
  and the next invocation works. Try a quick chord while an AX app is slow. With Mimic off, verify
  custom shortcuts still open search first and activate on release only after a repeated step.
- Uncheck either window command's visibility box: native switching still works. Menu Search's
  visibility checkbox also never disables its hotkey. No per-command capability toggles exist.
- The saved window hotkeys do nothing while Mimic macOS is on; aliases, visibility and Menu Search
  stay editable. Uncheck Mimic macOS: exactly the same saved hotkeys and recorders return. Relaunch
  and backup/settings-file round trips preserve the preference and bindings.
- With no Accessibility grant, native switching passes through and startup never prompts. Explicit
  enable may prompt; grant/revoke while running and verify recovery. Failed install reports once per
  problem. In Secure Input native macOS switching remains available, not Tinycast switching.
- Sleep/wake, lock/unlock, switch user sessions, and record an unrelated shortcut: Tinycast must not
  capture Cmd-Tab while paused, and must resume afterwards. Escape/click away or changing the setting
  mid-gesture must never activate an old selection. Control/Option/fn+Command+Tab pass through.
- Enable takeover in only one running Tinycast build; competing third-party taps and the actual
  WindowServer/native switcher cannot be validated by the private-port harness.

1. A minimized window is listed last and ↵ un-minimizes it rather than doing nothing — for Finder
   and Transmission too, whose minimized windows read `AXDialog`.
2. A window on another Space is listed, and ↵ pulls that Space forward.
3. An app with several windows lists them in its own front-to-back order, under one app rank.
4. An app quit between the summon and the ↵ reports rather than failing silently.
5. Minimize moves the row into the minimized run; on a full-screen window it does nothing.
6. Hide hides the frontmost app as well as a background one, and Escape does not bring it back.
7. ⌃⇧Q on an app with unsaved work keeps its rows until the save sheet lets it exit.
8. Close all windows of a regular app: exactly one app-only row appears on the next summon and
   activates that running app without reopening a window. Check a truly windowless regular app too,
   and an app with only ineligible dialogs. Minimize is absent and ⌃⇧M does nothing; Hide and Quit
   still work. An app with eligible windows never gains an extra app-only row.
