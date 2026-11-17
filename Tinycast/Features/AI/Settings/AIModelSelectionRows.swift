import SwiftUI

struct AIModelSelectionRows<ModelLabel: View, EffortLabel: View>: View {
    @Environment(AISettingsStore.self) private var settings

    let selection: AIModelSelection?
    /// Offers `nil` as a choice of its own, for a caller whose empty selection means another route.
    var inheritedTitle: String?
    /// For a caller whose instructions the on-device model would never receive.
    var excludesOnDevice = false
    let select: (AIModelSelection?) -> Void
    @ViewBuilder let modelLabel: () -> ModelLabel
    @ViewBuilder let effortLabel: () -> EffortLabel

    var body: some View {
        if modelGroups.isEmpty {
            Label("No AI provider configured", systemImage: "sparkles")
                .foregroundStyle(.secondary)
        } else {
            Picker(selection: modelBinding) {
                if let inheritedTitle {
                    Text(inheritedTitle).tag(AIModelSelection?.none)
                    Divider()
                }
                ForEach(modelGroups) { group in
                    Section(group.title) {
                        ForEach(group.options) { option in
                            Text(option.title).tag(Optional(option.selection))
                        }
                    }
                }
            } label: {
                modelLabel()
            }
            if !efforts.isEmpty {
                Picker(selection: effortBinding) {
                    ForEach(efforts) { effort in
                        Text(effort.title).tag(effort.id)
                    }
                } label: {
                    effortLabel()
                }
            }
        }
    }

    private var modelGroups: [AIModelOptionGroup] {
        let groups = AIModelOption.availableGroups(
            settings: settings)
        return excludesOnDevice ? groups.filter { $0.source != .appleIntelligence } : groups
    }

    private var efforts: [AIEffort] {
        AIModelOption.efforts(for: selection, settings: settings)
    }

    private var modelBinding: Binding<AIModelSelection?> {
        Binding(
            get: { selection?.withEffort(nil) },
            set: { value in
                select(
                    value.map {
                        AIModelOption.withDefaultEffort(
                            $0, settings: settings)
                    })
            })
    }

    private var effortBinding: Binding<String> {
        Binding(
            get: { selection?.effort ?? "" },
            set: { effort in
                guard let selection else { return }
                select(selection.withEffort(effort))
            })
    }
}
