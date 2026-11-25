import AppKit

@main @MainActor
struct WindowSwitchCoordinatorTests {
    static var failures = 0
    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: \(message)") }
    }
    static func hasMonitor(_ name: String, in coordinator: WindowSwitchCoordinator) -> Bool {
        Mirror(reflecting: coordinator).children.contains {
            $0.label == name && !Mirror(reflecting: $0.value).children.isEmpty
        }
    }

    static func appOnlyRows() {
        let settings = AppSettings()
        let core = AppCore()
        let session = WindowSwitchSession()
        let palette = PaletteState()
        let shell = PaletteCoordinator(palette: palette, session: session)
        let coordinator = WindowSwitchCoordinator(
            settings: settings, appIndex: AppIndex(), session: session,
            palette: palette, paletteCoordinator: shell, core: core)
        core.windowSwitchCoordinator = coordinator
        let screen = WindowSwitchScreen(session: session, core: core)
        let app = NSRunningApplication.current
        let appEntry = WindowSwitchEntry(handle: 1, hasWindow: false)
        let snapshot = WindowSwitchSweep.Snapshot(
            entries: [WindowSwitchEntry(handle: 0), appEntry, WindowSwitchEntry(handle: 2)],
            elements: [0: .init(), 1: .init(window: nil), 2: .init()])
        shell.showPalette(mode: .switchWindows)
        session.present(snapshot)
        coordinator.show()
        check(palette.selection == 1, "shortcut stepping can select an app-only row between windows")
        check(screen.actions(at: 1)?.items.count == 3,
              "app-only actions contain activation, hide and quit but no minimize")
        check(screen.actions(at: 0)?.items.count == 4, "window rows retain minimize")
        let minimizes = AXWindowAccess.minimizes
        coordinator.minimize(appEntry)
        _ = screen.perform(.minimizeWindow, at: 1)
        coordinator.minimize(WindowSwitchEntry(handle: 1))
        session.markMinimized(1)
        check(AXWindowAccess.minimizes == minimizes && !session.snapshot[1].isMinimized,
              "app rows cannot minimize even through shortcuts, stale entries or session updates")
        let terminations = app.terminations
        coordinator.quitApplication(appEntry)
        check(app.terminations == terminations + 1 && session.filtered.count == 3,
              "quit targets the app and keeps rows until termination")
        let focuses = AXWindowAccess.focuses
        let unminimizes = AXWindowAccess.unminimizes
        let activations = app.activations
        screen.activate(at: 1)
        check(app.activations == activations + 1 && AXWindowAccess.focuses == focuses
              && AXWindowAccess.unminimizes == unminimizes,
              "app-only activation activates the running app without window AX actions")
        check(!shell.visible && shell.lastRestoreFocus == false && session.snapshot.isEmpty,
              "app activation hides without restoring focus and drops live handles")
        shell.showPalette(mode: .switchWindows)
        session.present(snapshot)
        let hides = app.hides
        coordinator.hideApplication(appEntry)
        check(app.hides == hides + 1 && !shell.visible && shell.lastRestoreFocus == false,
              "hide remains available for app-only rows without restoring focus")
        shell.showPalette(mode: .switchWindows)
        session.present(snapshot)
        screen.activate(at: 2)
        check(AXWindowAccess.focuses == focuses + 1 && app.activations == activations + 1,
              "existing window activation still raises its window")
        coordinator.prepareForTermination()
    }

    static func removalRecovery() async {
        let settings = AppSettings()
        settings.navigationMimicsMacOS = true
        let core = AppCore()
        let session = WindowSwitchSession()
        let palette = PaletteState()
        let shell = PaletteCoordinator(palette: palette, session: session)
        let coordinator = WindowSwitchCoordinator(
            settings: settings, appIndex: AppIndex(), session: session,
            palette: palette, paletteCoordinator: shell, core: core)
        shell.onOpen = { coordinator.load() }
        coordinator.start()
        let tap = CommandTabTap.current!
        let removal = "com.apple.coregraphics.eventTapRemoved"
        let focuses = AXWindowAccess.focuses
        let installs = tap.installs
        let stops = tap.stops
        tap.handler?(.step(backwards: false, first: true))
        tap.handler?(.release)
        coordinator.activate(session.filtered[palette.selection]) // Existing Enter/row action.
        DarwinNotificationToken.post(removal) // Palette hide removes its independent Escape tap.
        check(tap.installs == installs && tap.stops == stops && tap.isInstalled,
              "unrelated removal after first commit leaves capture installed")
        tap.handler?(.step(backwards: true, first: true))
        let cancellations = tap.cancellations
        DarwinNotificationToken.post(removal)
        check(tap.installs == installs && tap.stops == stops && tap.cancellations == cancellations,
              "global removal does not cancel or rebuild a healthy second gesture")
        tap.handler?(.release)
        coordinator.activate(session.filtered[palette.selection])
        check(AXWindowAccess.focuses == focuses + 2 && !shell.visible,
              "second invocation commits after unrelated global removals")
        let prompts = Permissions.prompts
        tap.isInstalled = false
        DarwinNotificationToken.post(removal)
        check(tap.isInstalled && tap.installs == installs + 1 && tap.stops == stops + 1,
              "genuinely lost or disabled tap recovers")
        DarwinNotificationToken.post(removal) // The replacement's own removal notification.
        check(tap.installs == installs + 1 && tap.stops == stops + 1,
              "replacement cannot feed back into another rebuild")
        for gate in 0..<5 {
            settings.navigationEnabled = gate != 0
            settings.navigationMimicsMacOS = gate != 1
            core.hotKeys.recordingAction = gate == 2 ? 1 : nil
            core.secureInput.isActive = gate == 3
            if gate == 4 {
                NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: nil)
                try? await Task.sleep(for: .milliseconds(30))
            }
            tap.draining = true
            tap.isInstalled = true
            coordinator.applyNativeSwitching()
            let before = (tap.installs, tap.stops, tap.cancellations)
            DarwinNotificationToken.post(removal)
            check(tap.installs == before.0 && tap.stops == before.1 && tap.cancellations == before.2,
                  "policy-inactive healthy drain is untouched for gate \(gate)")
            tap.isInstalled = false
            DarwinNotificationToken.post(removal)
            check(tap.installs == before.0 && tap.stops == before.1,
                  "policy-inactive missing tap is not recovered for gate \(gate)")
        }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        try? await Task.sleep(for: .milliseconds(30))
        tap.draining = false
        Permissions.trusted = false
        tap.isInstalled = false
        DarwinNotificationToken.post(removal)
        check(!tap.isInstalled && Permissions.prompts == prompts,
              "recovery with revoked permission never prompts or installs")
        Permissions.trusted = true
        coordinator.healthCheck()
        check(tap.isInstalled && Permissions.prompts == prompts,
              "permission recovery uses passive health retry")
        coordinator.prepareForTermination()
    }

    static func main() async {
        let settings = AppSettings()
        let core = AppCore()
        let session = WindowSwitchSession()
        let palette = PaletteState()
        let shell = PaletteCoordinator(palette: palette, session: session)
        let coordinator = WindowSwitchCoordinator(
            settings: settings, appIndex: AppIndex(), session: session,
            palette: palette, paletteCoordinator: shell, core: core)
        shell.onOpen = { coordinator.load() }
        coordinator.start()
        let tap = CommandTabTap.current!
        check(
            tap.handler == nil && Permissions.prompts == 0,
            "passive startup without mimic captures nothing and prompts nothing")
        coordinator.show()
        check(
            shell.opens == 1 && palette.selection == 0 && AXWindowAccess.focuses == 0,
            "custom first press opens searchable list without stepping or committing")
        coordinator.show()
        check(palette.selection == 1, "custom repeat still steps")
        shell.hidePalette()
        core.windowSwitchCoordinator = coordinator
        let screen = WindowSwitchScreen(session: session, core: core)
        let beforeEnable = Permissions.prompts
        coordinator.setMimicsMacOS(true)
        check(
            Permissions.prompts == beforeEnable + 1 && core.hotKeys.navigationMimicsMacOS,
            "explicit enable gates permission and suppresses saved bindings")
        tap.handler?(.step(backwards: false, first: true))
        check(
            shell.opens == 2 && palette.selection == 1 && session.nativeLandingSelection == 1,
            "native first press loads and immediately selects the next window")
        check(hasMonitor("nativeSearchMonitor", in: coordinator), "native gesture arms Command translation")
        palette.query = "third"
        palette.selection = session.nativeLandingSelection // RootPaletteView lands before filtering.
        coordinator.filterQuery()
        check(palette.selection == 0, "query filtering corrects the pre-filter landing")
        tap.handler?(.release)
        check(shell.visible && AXWindowAccess.focuses == 0, "release keeps filtered picker open without activation")
        check(!hasMonitor("nativeSearchMonitor", in: coordinator), "release disarms Command translation")
        check(screen.tab(at: palette.selection, backwards: false) && palette.selection == 0,
              "Tab wraps within filtered query after release")
        check(screen.tab(at: palette.selection, backwards: true) && palette.selection == 0,
              "Shift-Tab wraps within filtered query")
        screen.activate(at: palette.selection) // RootPaletteView's Enter handler calls this.
        check(!shell.visible && AXWindowAccess.focuses == 1, "explicit selection activates once and hides")
        tap.handler?(.release)
        check(AXWindowAccess.focuses == 1 && !coordinator.cycleNativePicker(backwards: false),
              "reset clears native picker routing and stale release cannot activate")
        tap.handler?(.step(backwards: true, first: true))
        check(palette.selection == 2, "first native reverse selects last window")
        palette.query = "third"
        palette.selection = session.nativeLandingSelection
        coordinator.filterQuery()
        check(palette.selection == 0, "reverse stale landing resets after narrowing")
        tap.handler?(.release)
        check(AXWindowAccess.focuses == 1 && shell.visible, "reverse release leaves narrowed picker open")
        palette.query = ""
        coordinator.filterQuery()
        check(screen.tab(at: palette.selection, backwards: true) && palette.selection == 2,
              "Shift-Tab wraps backwards after clearing query")
        check(screen.tab(at: palette.selection, backwards: false) && palette.selection == 0,
              "Tab wraps forwards")
        check(!hasMonitor("releaseMonitor", in: coordinator), "plain Tab never arms release activation")
        let opens = shell.opens
        let cancellations = tap.cancellations
        tap.handler?(.step(backwards: false, first: true))
        check(palette.selection == 1 && shell.opens == opens && tap.cancellations == cancellations,
              "fresh Command-Tab cycles current picker without reload or cancellation")
        tap.handler?(.release)
        coordinator.activate(session.filtered[palette.selection])
        check(AXWindowAccess.focuses == 2 && !shell.visible, "row action activates exactly once")
        tap.handler?(.step(backwards: false, first: true))
        shell.hidePalette() // Escape/click-away uses the same reset.
        check(!coordinator.cycleNativePicker(backwards: false), "cancel clears native Tab routing")
        coordinator.show(query: "search")
        tap.handler?(.release)
        check(AXWindowAccess.focuses == 2 && shell.visible, "release cannot activate a closed and reopened session")
        check(!screen.tab(at: palette.selection, backwards: false), "ordinary search does not claim Tab")
        tap.handler?(.step(backwards: false, first: true))
        tap.handler?(.cancel)
        tap.handler?(.release)
        check(AXWindowAccess.focuses == 2 && !coordinator.cycleNativePicker(backwards: false),
              "system disable clears native picker routing without activation")
        core.hotKeys.recordingAction = 1
        coordinator.applyNativeSwitching()
        check(
            tap.handler == nil && core.hotKeys.navigationMimicsMacOS,
            "recording stops capture without restoring saved bindings")
        core.hotKeys.recordingAction = nil
        coordinator.applyNativeSwitching()
        check(tap.handler != nil, "recording exit restores native capture")
        core.secureInput.isActive = true
        coordinator.applyNativeSwitching()
        check(tap.handler == nil, "Secure Input stops native capture")
        core.secureInput.isActive = false
        settings.navigationEnabled = false
        coordinator.applyEnabled()
        check(
            tap.handler == nil && !core.hotKeys.navigationMimicsMacOS,
            "Navigation master disables native capture and suppression")
        settings.navigationEnabled = true
        tap.fails = true
        coordinator.applyEnabled()
        check(
            core.hotKeys.navigationMimicsMacOS && !core.messages.isEmpty,
            "failed takeover reports and keeps saved shortcuts suppressed")
        coordinator.setMimicsMacOS(false)
        check(!core.hotKeys.navigationMimicsMacOS && tap.handler == nil, "mimic off restores saved shortcut routes")
        shell.hidePalette()
        let focuses = AXWindowAccess.focuses
        NSEvent.holdForTest(.command)
        coordinator.show()
        NSEvent.releaseForTest()
        check(shell.visible && AXWindowAccess.focuses == focuses,
              "custom first press and release still leaves search open")
        NSEvent.holdForTest(.command)
        coordinator.show()
        check(hasMonitor("releaseMonitor", in: coordinator), "custom repeat arms release activation")
        NSEvent.releaseForTest()
        check(!shell.visible && AXWindowAccess.focuses == focuses + 1,
              "custom repeated shortcut still activates once on release")
        coordinator.prepareForTermination()
        await removalRecovery()
        appOnlyRows()
        print("Window switch coordinator: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
