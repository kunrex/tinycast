import Foundation

extension AppCore {
    func beginAIProviderManagement() {
        aiProviderManagementOpen = true
        applyInstalledAILifecycle()
    }

    func endAIProviderManagement() {
        aiProviderManagementOpen = false
        applyInstalledAILifecycle()
    }

    @discardableResult
    func applyInstalledAILifecycle() -> Task<Void, Never> {
        let enabledKinds =
            settings.quickActionsEnabled || aiProviderManagementOpen
            ? aiSettings.enabledInstalledProviders : []
        var tasks: [Task<Void, Never>] = []
        if enabledKinds.contains(.codex) {
            tasks.append(
                chatGPTSubscription.phase == .idle
                    ? chatGPTSubscription.refresh()
                    : chatGPTSubscription.currentRefreshTask())
        } else {
            chatGPTSubscription.stop()
        }
        tasks.append(installedAI.ensure(enabledKinds: enabledKinds))
        return Task { for task in tasks { await task.value } }
    }
}
