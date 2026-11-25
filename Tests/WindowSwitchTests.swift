import Foundation

@main
@MainActor
struct WindowSwitchTests {
    static var failures = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func entry(
        _ handle: Int, app: String = "Safari", title: String = "Window",
        minimized: Bool = false, hasWindow: Bool = true, rank: Int = 0
    ) -> WindowSwitchEntry {
        WindowSwitchEntry(
            handle: handle, appName: app, bundleID: "com.example.\(app.lowercased())",
            iconURL: nil, iconStamp: 0, title: title, isMinimized: minimized,
            hasWindow: hasWindow, appRank: rank)
    }

    static func main() {
        identity()
        appOnlyEntries()
        displayTitle()
        searchMapping()
        ordering()
        orderingIsTotal()
        switchable()
        ranking()
        rankingLimit()

        print(failures == 0 ? "Window switch tests passed" : "\(failures) window switch tests failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func identity() {
        expect(entry(7).id == "7", "the id is the handle, which is unique inside one sweep")
    }

    static func appOnlyEntries() {
        let app = entry(3, app: "Preview", title: "", hasWindow: false, rank: .max)
        let anotherInstance = entry(4, app: "Preview", title: "", hasWindow: false, rank: .max)
        let windows = [
            entry(0, app: "Safari", rank: 0),
            entry(1, app: "Safari", rank: 0),
            entry(2, app: "Mail", minimized: true, rank: 1)
        ]
        expect(app.id != anotherInstance.id, "app instances with the same name have distinct handles")
        expect(!windows.contains { $0.id == app.id }, "app and window identities do not collide")
        expect(app.displayTitle == "Preview", "an app-only row displays the app name")
        expect(!app.isMinimized && !app.hasWindow, "an app-only row has no minimized window")
        let sorted = WindowSwitchOrder.sorted([app, anotherInstance] + windows.reversed())
        expect(sorted.map(\.handle) == [0, 1, 3, 4, 2],
               "app rows use the existing rank/name order before minimized windows")
        expect(WindowSwitchOrder.sorted(sorted.reversed()) == sorted,
               "mixed app/window ordering remains total")
        expect(WindowSwitchQuery.rank(sorted, for: "").map(\.id) == sorted.map(\.id),
               "an empty query preserves mixed row identities and order")
        expect(WindowSwitchQuery.rank(sorted, for: "Preview").map(\.id) == [app.id, anotherInstance.id],
               "app-only rows match their name and retain instance order")
        expect(WindowSwitchQuery.rank(sorted, for: "Safari").map(\.handle) == [0, 1],
               "existing windows remain independently searchable")
    }

    static func displayTitle() {
        expect(entry(0, title: "Notes.md").displayTitle == "Notes.md", "a titled window shows it")
        expect(
            entry(0, app: "Preview", title: "").displayTitle == "Preview",
            "an untitled window reads as its app rather than as a blank row")
        expect(
            entry(0, app: "Preview", title: "   ").displayTitle == "Preview",
            "a whitespace-only title is no title")
    }

    static func searchMapping() {
        let aliases = entry(0, app: "Safari", title: "Inbox").searchFields().aliases
        expect(
            aliases.contains { $0.text == "Inbox" && $0.role == .name },
            "the window title is the name a query matches")
        expect(
            aliases.contains { $0.text == "Safari" && $0.role == .owner },
            "the app rides as owner: every window of one app shares it")
    }

    static func ordering() {
        let sorted = WindowSwitchOrder.sorted([
            entry(0, app: "Mail", rank: 2),
            entry(1, app: "Safari", minimized: true, rank: 0),
            entry(2, app: "Safari", rank: 0),
            entry(3, app: "Safari", rank: 0),
            entry(4, app: "Zed", rank: .max)
        ])
        expect(
            sorted.map(\.handle) == [2, 3, 0, 4, 1],
            "front app first, then by rank, unranked next, minimized last: \(sorted.map(\.handle))")
    }

    static func orderingIsTotal() {
        let entries = (0..<12).map {
            entry($0, app: ["Mail", "Safari", "Zed"][$0 % 3], minimized: $0 % 4 == 0, rank: $0 % 3)
        }
        let once = WindowSwitchOrder.sorted(entries)
        let twice = WindowSwitchOrder.sorted(entries.reversed())
        expect(
            once.map(\.handle) == twice.map(\.handle),
            "the order is total, so a shuffled sweep sorts identically")
        expect(
            once.map(\.handle).sorted() == entries.map(\.handle).sorted(),
            "sorting drops nothing")
        let split = once.firstIndex(where: \.isMinimized) ?? once.count
        expect(
            once[split...].allSatisfy(\.isMinimized),
            "minimized windows form one run at the end, never interleaved")
    }

    static func switchable() {
        expect(
            WindowSwitchPolicy.isSwitchable(
                isStandardWindow: true, isMinimized: false, canMinimize: true),
            "a standard window is offered")
        expect(
            WindowSwitchPolicy.isSwitchable(
                isStandardWindow: true, isMinimized: true, canMinimize: true),
            "a minimized window that still reports its subrole is offered")
        expect(
            WindowSwitchPolicy.isSwitchable(
                isStandardWindow: false, isMinimized: true, canMinimize: true),
            "a minimized window reading AXDialog is offered, which is Finder and Transmission")
        expect(
            !WindowSwitchPolicy.isSwitchable(
                isStandardWindow: false, isMinimized: false, canMinimize: true),
            "a sheet is no window to switch to")
        expect(
            !WindowSwitchPolicy.isSwitchable(
                isStandardWindow: false, isMinimized: true, canMinimize: false),
            "a dialog cannot minimize, so it is never read as a minimized window")
    }

    static func ranking() {
        let entries = [
            entry(0, app: "Mail", title: "Drafts"),
            entry(1, app: "Safari", title: "Inbox"),
            entry(2, app: "Safari", title: "Inbox archive")
        ]
        expect(
            WindowSwitchQuery.rank(entries, for: "").map(\.handle) == [0, 1, 2],
            "an empty query keeps the order it was handed")
        expect(
            WindowSwitchQuery.rank(entries, for: "Inbox").first?.handle == 1,
            "the exact title beats the one that only starts with it")
        expect(
            WindowSwitchQuery.rank(entries, for: "Safari").map(\.handle) == [1, 2],
            "the app name matches every one of its windows, in the order given")
        expect(
            WindowSwitchQuery.rank(entries, for: "zzz").isEmpty,
            "a query nothing matches ranks nothing")
    }

    static func rankingLimit() {
        let entries = (0..<(WindowSwitchQuery.resultLimit + 50)).map {
            entry($0, app: "Safari", title: "Tab \($0)")
        }
        expect(
            WindowSwitchQuery.rank(entries, for: "").count == WindowSwitchQuery.resultLimit,
            "an empty query is capped too, so a huge sweep never builds a huge list")
        expect(
            WindowSwitchQuery.rank(entries, for: "Tab").count == WindowSwitchQuery.resultLimit,
            "the cap holds under a query every row matches")
    }
}
