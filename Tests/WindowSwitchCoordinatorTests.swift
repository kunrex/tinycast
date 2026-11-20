import AppKit

@main @MainActor
struct WindowSwitchCoordinatorTests {
    static var failures = 0
    static func check(_ condition: Bool, _ message: String) {
        if !condition { failures += 1; print("FAIL: \(message)") }
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
        tap.handler?(.commit)
        DarwinNotificationToken.post(removal) // Palette hide removes its independent Escape tap.
        check(tap.installs == installs && tap.stops == stops && tap.isInstalled,
              "unrelated removal after first commit leaves capture installed")
        tap.handler?(.step(backwards: true, first: true))
        let cancellations = tap.cancellations
        DarwinNotificationToken.post(removal)
        check(tap.installs == installs && tap.stops == stops && tap.cancellations == cancellations,
              "global removal does not cancel or rebuild a healthy second gesture")
        tap.handler?(.commit)
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
        let beforeEnable = Permissions.prompts
        coordinator.setMimicsMacOS(true)
        check(
            Permissions.prompts == beforeEnable + 1 && core.hotKeys.navigationMimicsMacOS,
            "explicit enable gates permission and suppresses saved bindings")
        tap.handler?(.step(backwards: false, first: true))
        check(
            shell.opens == 2 && palette.selection == 1 && session.nativeLandingSelection == 1,
            "native first press loads and immediately selects the next window")
        palette.query = "third"
        palette.selection = session.nativeLandingSelection // RootPaletteView lands before filtering.
        coordinator.filterQuery()
        check(palette.selection == 0, "query filtering corrects the pre-filter landing")
        tap.handler?(.commit)
        check(AXWindowAccess.focuses == 1, "filtered query commits its only row")
        check(!shell.visible && AXWindowAccess.focuses == 1, "native release activates once and hides without restoring focus")
        tap.handler?(.commit)
        check(AXWindowAccess.focuses == 1, "repeated stale release cannot activate")
        tap.handler?(.step(backwards: true, first: true))
        check(palette.selection == 2, "first native reverse selects last window")
        palette.query = "third"
        palette.selection = session.nativeLandingSelection
        coordinator.filterQuery()
        check(palette.selection == 0, "reverse stale landing resets after narrowing")
        tap.handler?(.commit)
        check(AXWindowAccess.focuses == 2 && !shell.visible, "reverse query commits its only row")
        shell.hidePalette()
        coordinator.show(query: "search")
        tap.handler?(.commit)
        check(AXWindowAccess.focuses == 2 && shell.visible, "release cannot activate a closed and reopened session")
        tap.handler?(.step(backwards: false, first: true))
        tap.handler?(.cancel)
        tap.handler?(.commit)
        check(AXWindowAccess.focuses == 2, "system disable cancels commit")
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
        coordinator.prepareForTermination()
        await removalRecovery()
        print("Window switch coordinator: \(failures) failures")
        if failures > 0 { exit(1) }
    }
}
