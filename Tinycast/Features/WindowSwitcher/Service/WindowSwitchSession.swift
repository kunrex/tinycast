import AppKit

@MainActor
@Observable
final class WindowSwitchSession {
    private(set) var snapshot: [WindowSwitchEntry] = []
    /// The rows the list reads: ranked once per query change, so one keystroke ranks once.
    private(set) var filtered: [WindowSwitchEntry] = []

    private(set) var identity = UUID()
    var nativeLandingSelection = 0
    @ObservationIgnored var onReset: (() -> Void)?
    private var query = ""
    /// Live AX handles, so they are never observed and never outlive the show.
    @ObservationIgnored private var elements: [Int: WindowSwitchSweep.Element] = [:]
    /// Held only while rows are shown, so an app that quits takes its rows with it.
    @ObservationIgnored private var terminationToken: NotificationCenter.ObservationToken?

    func present(_ snapshot: WindowSwitchSweep.Snapshot) {
        self.snapshot = WindowSwitchOrder.sorted(snapshot.entries)
        elements = snapshot.elements
        observeTerminations()
        applyQuery()
    }

    func element(for handle: Int) -> WindowSwitchSweep.Element? { elements[handle] }

    func reset() {
        onReset?()
        identity = UUID()
        nativeLandingSelection = 0
        if let terminationToken {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationToken)
        }
        terminationToken = nil
        snapshot = []
        filtered = []
        elements = [:]
        query = ""
    }

    @discardableResult
    func filter(_ query: String) -> Bool {
        let changed = self.query != query
        if changed { nativeLandingSelection = 0 }
        self.query = query
        applyQuery()
        return changed
    }

    func markMinimized(_ handle: Int) {
        guard let index = snapshot.firstIndex(where: { $0.handle == handle }),
            snapshot[index].hasWindow else { return }
        var entries = snapshot
        entries[index].isMinimized = true
        snapshot = WindowSwitchOrder.sorted(entries)
        applyQuery()
    }

    private func observeTerminations() {
        guard terminationToken == nil else { return }
        terminationToken = NSWorkspace.shared.notificationCenter.addObserver(
            of: NSWorkspace.shared, for: NSWorkspace.DidTerminateApplicationMessage.self
        ) { [weak self] in self?.removeWindows(of: $0.application.processIdentifier) }
    }

    private func removeWindows(of pid: pid_t) {
        let gone = Set(elements.compactMap { $0.value.app.processIdentifier == pid ? $0.key : nil })
        guard !gone.isEmpty else { return }
        for handle in gone { elements[handle] = nil }
        snapshot.removeAll { gone.contains($0.handle) }
        applyQuery()
    }

    private func applyQuery() {
        filtered = WindowSwitchQuery.rank(
            snapshot, for: query.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
