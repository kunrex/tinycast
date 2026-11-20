# Durable window recovery

`Features/WindowRecovery/` restores windows parked by older versions of Tinycast. It is permanent
recovery capability, not a one-release migration or an active window-placement feature. Navigation's
[window switcher](navigation.md) remains independent.

Adapted from [Rooms](https://github.com/saragordic/rooms) by Sara Gordić, with her permission and
under its MIT licence; [NOTICE.md](../../NOTICE.md) retains the attribution and licence.

## Ownership and persistence

`AppCore` owns `RoomParkingLedger` at the active-bundle `AppPaths.applicationSupport()` location,
`room-parking.json`, with its existing schema. `AppCore.start()` and `prepareForTermination()` call
`WindowRecoveryRunner.returnParkedWindows` synchronously. There is no independent background task,
feature switch, or scheduler. Recovery never creates new parked windows.

The ledger preserves the first saved home for each window. Unreadable JSON is moved aside as
`room-parking.unreadable-<uuid>.json`, not discarded. Neither the ledger nor these unreadable copies
belong in settings backups or removal migrations; they are this Mac's recovery state.

## Restore policy

- Accessibility must already be granted; recovery does not prompt for it.
- `WindowRecoverySweep` includes hidden apps' and minimized windows, excludes full-screen windows,
  and uses bounded AX reads. It never hides or unhides an application.
- A saved window matches by window-server ID **and** bundle ID, never by title alone.
  `AXWindowAccess.windowID(of:)` resolves `_AXUIElementGetWindow` dynamically. If unavailable,
  unmatched entries remain; Navigation needs no private symbol for its per-app recency.
- A saved frame overlapping a current display is retained. Otherwise the return policy fits and
  centres it on the first available display. `AXScreens` filters displays with valid UUIDs and orders
  recovery frames left-to-right.
- The restore-only writer unminimizes the window when needed and writes size, position, then size.
  It rolls back size if positioning fails, retries a displaced origin, and handles non-resizable
  windows without placement-command anchoring or tiling geometry.
- `AXEnhancedUserInterface` is temporarily suppressed for restoration and restored afterwards;
  it is never suppressed while VoiceOver is running.
- Only a confirmed return, within 16 pt of the home origin on each axis, permits forgetting an entry.
  Size equality is not required. Running but unresponsive apps keep their entries for the next pass;
  entries for apps that have quit are pruned after a trusted recovery pass.

## Coordinate space

`Platform/AXGeometry` snapshots the primary display's height once per pass. Cocoa rectangles grow
upward; AX rectangles grow downward. `flip` uses `anchorHeight - rect.maxY`, preserving width and
height. `AXScreens` converts visible frames through that same snapshot so secondary displays and
left-to-right ordering use consistent AX coordinates.

## Verification

`Tests/WindowRecoveryTests.swift` compiles every shipped recovery source and its platform helpers
without the retired placement subsystem. Temporary ledgers cover legacy decoding, first-home
preservation, write refusal, pruning, unreadable-file preservation, display fallback, ID + bundle
matching and origin-only confirmation. Platform services compile but do not act on live windows.

Manual checks belong in [testing.md](../testing.md#durable-window-recovery): use only the Debug
channel and a controlled legacy ledger, verify restoration on launch and quit, retained entries for
unresponsive apps, and display-disconnection fallback. Do not delete recovery files while testing
preference cleanup.
