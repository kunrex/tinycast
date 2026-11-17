import Foundation

@main
@MainActor
struct AIProviderDiscoveryTests {
    static func main() async {
        let core = AppCore()
        await core.applyInstalledAILifecycle().value
        precondition(core.subscription.refreshes == 0 && core.installedAI.enabled.isEmpty)

        core.beginAIProviderManagement()
        await core.applyInstalledAILifecycle().value
        precondition(core.subscription.refreshes == 1)
        precondition(core.installedAI.enabled == [.codex, .claude])
        precondition(!core.settings.quickActionsEnabled)

        core.aiSettings.enabledInstalledProviders = [.claude]
        await core.applyInstalledAILifecycle().value
        precondition(core.subscription.phase == .idle)
        precondition(core.installedAI.enabled == [.claude])

        core.endAIProviderManagement()
        precondition(core.installedAI.enabled.isEmpty)
        precondition(core.installedAI.cancelled)
        core.aiSettings.enabledInstalledProviders = [.codex, .claude]
        core.beginAIProviderManagement()
        precondition(core.subscription.refreshes == 2)
        core.settings.quickActionsEnabled = true
        core.endAIProviderManagement()
        precondition(core.installedAI.enabled == [.codex, .claude])
        precondition(core.subscription.phase == .starting)
        core.settings.quickActionsEnabled = false
        await core.applyInstalledAILifecycle().value
        precondition(core.installedAI.enabled.isEmpty && core.subscription.phase == .idle)
        print("AI provider discovery tests passed")
    }
}

// Effect doubles exercise the shipped AppCore lifecycle without launching installed commands.
@MainActor
final class AppCore {
    var aiProviderManagementOpen = false
    let settings = Settings()
    let aiSettings = AISettings()
    let subscription = Subscription()
    var chatGPTSubscription: Subscription { subscription }
    let installedAI = Installed()

    final class Settings {
        var quickActionsEnabled = false
    }

    final class AISettings {
        var enabledInstalledProviders: Set<Kind> = [.codex, .claude]
    }

    enum Kind: Hashable { case codex, claude }

    final class Subscription {
        enum Phase { case idle, starting }
        var phase = Phase.idle
        var refreshes = 0
        func refresh() -> Task<Void, Never> {
            refreshes += 1
            phase = .starting
            return Task {}
        }
        func currentRefreshTask() -> Task<Void, Never> { Task {} }
        func stop() { phase = .idle }
    }

    final class Installed {
        var enabled: Set<Kind> = []
        var cancelled = false
        func ensure(enabledKinds: Set<Kind>) -> Task<Void, Never> {
            cancelled = !enabled.isEmpty && enabledKinds.isEmpty
            enabled = enabledKinds
            return Task {}
        }
    }
}
