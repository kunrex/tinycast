import Foundation
import CoreGraphics

@main
struct WindowRecoveryTests {
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowRecoveryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("room-parking.json")
        let home = CGRect(x: 100, y: 120, width: 800, height: 600)
        let entry = RoomParkingLedger.Entry(
            windowID: 42, bundleID: "fixture.app", title: "Document", frame: home)
        // The legacy array format must remain readable without a migration.
        try JSONEncoder().encode([entry]).write(to: url)
        let ledger = RoomParkingLedger(fileURL: url)
        precondition(ledger.entry(for: 42) == entry)
        var parked = entry
        parked.frame.origin = CGPoint(x: 1999, y: 1199)
        precondition(ledger.record(parked))
        precondition(RoomParkingLedger(fileURL: url).entry(for: 42) == entry)
        precondition(WindowRecoveryPolicy.matches(windowID: 42, bundleID: "fixture.app", entry: entry))
        precondition(!WindowRecoveryPolicy.matches(windowID: nil, bundleID: "fixture.app", entry: entry))
        precondition(!WindowRecoveryPolicy.matches(windowID: 43, bundleID: "fixture.app", entry: entry))
        precondition(!WindowRecoveryPolicy.matches(windowID: 42, bundleID: "other.app", entry: entry))

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        precondition(WindowRecoveryPolicy.returnFrame(for: home, screens: [screen]) == home)
        precondition(WindowRecoveryPolicy.returnFrame(for: home, screens: []) == home)
        let overlapping = CGRect(x: -799, y: 100, width: 800, height: 600)
        precondition(WindowRecoveryPolicy.returnFrame(for: overlapping, screens: [screen]) == overlapping)
        let gone = CGRect(x: 3000, y: -1000, width: 2000, height: 1200)
        precondition(WindowRecoveryPolicy.returnFrame(for: gone, screens: [screen]) == screen)
        let smallGone = CGRect(x: 3000, y: 0, width: 801, height: 601)
        precondition(WindowRecoveryPolicy.returnFrame(for: smallGone, screens: [screen])
                     == CGRect(x: 320, y: 150, width: 801, height: 601))
        let left = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        precondition(WindowRecoveryPolicy.returnFrame(for: gone, screens: [left, screen]) == left)
        var actual = CGRect(x: 116, y: 104, width: 1000, height: 1000)
        precondition(WindowRecoveryPolicy.isReturned(actual, to: home))
        actual.origin.x += 0.1
        precondition(!WindowRecoveryPolicy.isReturned(actual, to: home))
        actual.origin = CGPoint(x: 100, y: 136.1)
        precondition(!WindowRecoveryPolicy.isReturned(actual, to: home))

        ledger.keepOnly(bundleIDs: ["fixture.app"])
        precondition(!ledger.isEmpty)
        ledger.keepOnly(bundleIDs: [])
        precondition(RoomParkingLedger(fileURL: url).isEmpty)
        precondition(ledger.record(entry))
        ledger.forget([42])
        precondition(RoomParkingLedger(fileURL: url).isEmpty)
        let unwritable = RoomParkingLedger(fileURL: directory.appendingPathComponent("missing/ledger.json"))
        precondition(!unwritable.record(entry))
        try Data("broken".utf8).write(to: url)
        precondition(RoomParkingLedger(fileURL: url).isEmpty)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        precondition(files.contains { $0.hasPrefix("room-parking.unreadable-") })
        print("WindowRecoveryTests passed (independent of WindowManagement)")
    }
}
