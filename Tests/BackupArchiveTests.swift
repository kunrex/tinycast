import AppleArchive
import Foundation
import System

/// Compiles the shipped bundle and archive layer, so a `.tinycast` can't quietly change shape.
@main
@MainActor
struct BackupArchiveTests {
    static var failures = 0

    static func check(_ description: String, _ condition: @autoclosure () -> Bool) {
        if condition() {
            print("PASS  \(description)")
        } else {
            print("FAIL  \(description)")
            failures += 1
        }
    }

    /// UUID-suffixed, per docs/testing.md: harnesses run in parallel against the real system.
    static func scratch() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("backup-archive-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func main() {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }

        roundTrip(in: root)
        clipboardLines(in: root)
        legacyNotesArchives(in: root)
        noAbsolutePathsEscape(in: root)
        formatGuard(in: root)
        rejectsGarbage(in: root)
        refusesTraversal(in: root)
        refusesSymbolicLinks(in: root)
        categoriesAreComplete()
        staging()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Round trip

    static func roundTrip(in root: URL) {
        let source = root.appendingPathComponent("seal")
        let bundle = BackupBundle(root: source)
        try? bundle.prepare(BackupCategory.all)

        // A binary blob, so a wrong keyset or a text-only path shows up as corruption.
        let png = Data((0..<200_000).map { UInt8($0 % 251) })
        try? bundle.write(png, to: bundle.clipboardImagesDirectory.appendingPathComponent("a.png"))
        _ = try? bundle.writeDocument(
            title: "Café — snippet/with:separators", extension: "md", contents: "héllo\nwörld",
            in: bundle.snippetsDirectory)
        try? bundle.write(Data(), to: bundle.snippetsDirectory.appendingPathComponent("empty.md"))
        let manifest = BackupManifest(
            appVersion: "1.2.3", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            counts: ["clipboard": 1, "snippets": 2])
        try? bundle.writeManifest(manifest)

        let archive = root.appendingPathComponent("out.tinycast")
        let opened = root.appendingPathComponent("open")
        do {
            try BackupArchive.seal(directory: source, into: archive)
            try BackupArchive.open(file: archive, into: opened)
        } catch {
            check("seal and open succeed (\(error))", false)
            return
        }

        let reopened = BackupBundle(root: opened)
        check(
            "a binary blob survives the round trip",
            (try? Data(
                contentsOf: reopened.clipboardImagesDirectory.appendingPathComponent("a.png")))
                == png)
        let snippets = reopened.documents(in: reopened.snippetsDirectory, extension: "md")
        let document = snippets.first { $0.contents == "héllo\nwörld" }
        check("a snippet with separators and non-ASCII survives", document != nil)
        check(
            "a title's path separators never become directories",
            document.map { !$0.name.contains("/") } ?? false)
        check("a zero-byte file survives", snippets.contains { $0.contents == "" })
        let decoded = try? reopened.readManifest()
        check("the manifest round trips", decoded == manifest)
        check("an absent category reads as absent", decoded?.categories == [.clipboard, .snippets])
        check("a present category keeps its count", decoded?.count(.clipboard) == 1)
        check("an absent category counts zero", decoded?.count(.learning) == 0)
        check(
            "preparing all supported categories creates no Notes directory",
            !FileManager.default.fileExists(atPath: source.appendingPathComponent("notes").path))

        // Ownership must not travel: the extract belongs to whoever opened it.
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: reopened.clipboardImagesDirectory.appendingPathComponent("a.png").path)
        check(
            "the extracted file is owned by the current user",
            (attributes?[.ownerAccountID] as? NSNumber)?.uint32Value == getuid())
    }

    // MARK: - Legacy compatibility for Notes Removal

    static func legacyNotesArchives(in root: URL) {
        let settings = Data("""
            {
              "settings": {
                "notesEnabled": true,
                "notesRendersMarkdown": false,
                "notesShowsFormattingBar": true,
                "notesShowsInMenuBar": true,
                "clipboardEnabled": false,
                "clipboardRetentionDays": 30,
                "fileSearchEnabled": true,
                "compactBarCommands": ["command:search-emoji", "command:show-notes"]
              }
            }
            """.utf8)
        let document = Data("# User document\nDo not delete or rewrite.\n".utf8)
        let supported: Set<BackupCategory> = [.configuration, .clipboard, .snippets, .learning]
        let payloads: [String: Data] = [
            "clipboard/items.jsonl": Data("{\"kind\":\"text\",\"text\":\"Keep clipboard\"}\n".utf8),
            "clipboard/images/keep.png": Data([0x89, 0x50, 0x4E, 0x47, 0, 0xFF]),
            "snippets/Keep.md": Data("# Supported snippet\nKeep these bytes.\n".utf8),
            "learning/ranking.json": Data("{\"keep\": 3}\n".utf8)
        ]
        for notesOnly in [false, true] {
            let name = notesOnly ? "legacy-notes-only" : "legacy-mixed"
            let source = root.appendingPathComponent(name)
            let bundle = BackupBundle(root: source)
            let counts = notesOnly
                ? "\"notes\": 1"
                : "\"configuration\": 1, \"clipboard\": 2, \"snippets\": 3, \"learning\": 0, \"notes\": 1"
            let manifest = Data("""
                {"format": 1, "appVersion": "1.0", "createdAt": "2025-01-01T00:00:00Z",
                 "counts": {\(counts)}}
                """.utf8)
            let archive = root.appendingPathComponent("\(name).tinycast")
            let destination = root.appendingPathComponent("\(name)-opened")
            let noteURL = source.appendingPathComponent("notes/Keep.md")
            do {
                try bundle.prepare([])
                try FileManager.default.createDirectory(
                    at: noteURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try document.write(to: noteURL)
                try manifest.write(to: bundle.manifestURL)
                if !notesOnly {
                    try settings.write(to: bundle.settingsURL)
                    for (path, bytes) in payloads {
                        let url = source.appendingPathComponent(path)
                        try FileManager.default.createDirectory(
                            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try bytes.write(to: url)
                    }
                }
                try BackupArchive.seal(directory: source, into: archive)
                try BackupArchive.open(file: archive, into: destination)
                let reopened = BackupBundle(root: destination)
                let decoded = try reopened.readManifest()
                check("BASELINE: \(name) remains readable as format 1", decoded.format == 1)
                check("BASELINE: \(name) retains legacy Notes counts", decoded.counts["notes"] == 1)
                let extractedDocument = try Data(
                    contentsOf: destination.appendingPathComponent("notes/Keep.md"))
                let sourceDocument = try Data(contentsOf: noteURL)
                check(
                    "BASELINE: \(name) extraction preserves the user document bytes",
                    extractedDocument == document)
                check(
                    "BASELINE: \(name) leaves the source document untouched",
                    sourceDocument == document)
                if !notesOnly {
                    for (path, bytes) in payloads {
                        check("BASELINE: supported payload \(path) survives legacy mixed extraction",
                            (try? Data(contentsOf: destination.appendingPathComponent(path))) == bytes)
                    }
                    // Byte preservation is not a SettingsBackup decode/apply check.
                    let extractedSettings = try Data(contentsOf: reopened.settingsURL)
                    check(
                        "BASELINE: legacy Notes and supported settings survive extraction unchanged",
                        extractedSettings == settings)
                    check(
                        "BASELINE: supported category counts survive alongside Notes",
                        decoded.count(.clipboard) == 2 && decoded.count(.snippets) == 3
                            && decoded.count(.learning) == 0)
                }
                check(
                    "\(name) offers only supported import categories",
                    decoded.categories == (notesOnly ? [] : supported))
            } catch {
                check("BASELINE: \(name) fixture opens (\(error))", false)
            }
        }
    }

    // MARK: - Clipboard

    static func clipboardLines(in root: URL) {
        let bundle = BackupBundle(root: root.appendingPathComponent("clips"))
        try? bundle.prepare([.clipboard])
        let items = [
            BackupClipboardItem(
                kind: .text, text: "one\ntwo\nthree", imageName: nil,
                createdAt: Date(timeIntervalSince1970: 10), sourceBundleID: "com.apple.Safari",
                pinnedAt: nil),
            BackupClipboardItem(
                kind: .text, text: "carriage\r\nreturn", imageName: nil,
                createdAt: Date(timeIntervalSince1970: 20), sourceBundleID: nil,
                pinnedAt: Date(timeIntervalSince1970: 25)),
            BackupClipboardItem(
                kind: .image, text: nil, imageName: "b.png",
                createdAt: Date(timeIntervalSince1970: 30), sourceBundleID: nil, pinnedAt: nil)
        ]
        if let writer = try? bundle.clipboardWriter() {
            for item in items { try? writer.write(item) }
        }

        check("every clip round trips through JSONL", Array(bundle.clipboardItems()) == items)

        // The invariant the line splitting rests on: a newline in a clip is escaped, never raw.
        let raw = (try? Data(contentsOf: bundle.clipboardItemsURL)) ?? Data()
        check(
            "one line per clip, whatever the clip contains",
            raw.split(separator: 0x0A, omittingEmptySubsequences: true).count == items.count)
    }

    /// The analogue of SettingsBackupTests's `snippetsEnabled` check: this file leaves the Mac.
    static func noAbsolutePathsEscape(in root: URL) {
        let bundle = BackupBundle(root: root.appendingPathComponent("paths"))
        try? bundle.prepare([.clipboard])
        let item = BackupClipboardItem(
            kind: .image, text: nil, imageName: "c.png", createdAt: Date(), sourceBundleID: nil,
            pinnedAt: nil)
        if let writer = try? bundle.clipboardWriter() { try? writer.write(item) }
        let raw = (try? Data(contentsOf: bundle.clipboardItemsURL)) ?? Data()
        let text = String(bytes: raw, encoding: .utf8) ?? ""
        check("no home directory leaks into the file", !text.contains("/Users"))
        check("no image path leaks into the file", !text.contains("/Library"))
    }

    // MARK: - Guards

    static func formatGuard(in root: URL) {
        for offset in [-1, 1] {
            let bundle = BackupBundle(root: root.appendingPathComponent("format\(offset)"))
            try? bundle.prepare([])
            var manifest = BackupManifest(appVersion: "1", createdAt: Date(), counts: [:])
            manifest.format = BackupManifest.currentFormat + offset
            try? bundle.writeManifest(manifest)
            do {
                _ = try bundle.readManifest()
                check("a format of \(manifest.format) is refused", false)
            } catch {
                check(
                    "a format of \(manifest.format) is refused by the same error",
                    error == .unsupportedFormat(found: manifest.format))
                check(
                    "the refusal names the format it found",
                    error.errorDescription?.contains("\(manifest.format)") == true)
            }
        }
    }

    static func rejectsGarbage(in root: URL) {
        let file = root.appendingPathComponent("garbage.tinycast")
        try? Data("not an archive".utf8).write(to: file)
        let into = root.appendingPathComponent("garbage-out")
        do {
            try BackupArchive.open(file: file, into: into)
            check("a non-archive is refused", false)
        } catch {
            check("a non-archive is refused", true)
        }

        let empty = BackupBundle(root: root.appendingPathComponent("empty"))
        try? empty.prepare([])
        do {
            _ = try empty.readManifest()
            check("a bundle with no manifest is refused", false)
        } catch {
            check("a bundle with no manifest is refused", error == .unreadable)
        }
    }

    /// A hostile archive must not write outside the directory the caller chose.
    static func refusesTraversal(in root: URL) {
        // Header-by-header: `writeDirectoryContents` refuses to emit the `..` path we need here.
        let archive = root.appendingPathComponent("evil.tinycast")
        let payload = Data("escaped".utf8)
        guard
            let destination = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600)),
            let compressor = ArchiveByteStream.compressionStream(
                using: .lzfse, writingTo: destination)
        else {
            check("the traversal fixture can be built", false)
            return
        }
        do {
            try ArchiveStream.withEncodeStream(writingTo: compressor) { encoder in
                let header = ArchiveHeader()
                header.append(
                    .uint(
                        key: ArchiveHeader.FieldKey("TYP"),
                        value: UInt64(ArchiveHeader.EntryType.regularFile.rawValue)))
                header.append(
                    .string(key: ArchiveHeader.FieldKey("PAT"), value: "../escape.txt"))
                header.append(.uint(key: ArchiveHeader.FieldKey("MOD"), value: 0o644))
                header.append(
                    .blob(key: ArchiveHeader.FieldKey("DAT"), size: UInt64(payload.count)))
                try encoder.writeHeader(header)
                try payload.withUnsafeBytes { buffer in
                    try encoder.writeBlob(key: ArchiveHeader.FieldKey("DAT"), from: buffer)
                }
            }
            try compressor.close()
            try destination.close()
        } catch {
            check("the traversal fixture can be built (\(error))", false)
            return
        }

        let into = root.appendingPathComponent("evil-out", isDirectory: true)
        try? BackupArchive.open(file: archive, into: into)
        let escaped = root.appendingPathComponent("escape.txt")
        check(
            "an entry naming `..` never lands outside the destination",
            !FileManager.default.fileExists(atPath: escaped.path))
    }

    /// A link entry names no `..` at all, and reading through it would leave the extract.
    static func refusesSymbolicLinks(in root: URL) {
        let archive = root.appendingPathComponent("linked.tinycast")
        guard
            let destination = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o600)),
            let compressor = ArchiveByteStream.compressionStream(
                using: .lzfse, writingTo: destination)
        else {
            check("the symlink fixture can be built", false)
            return
        }
        do {
            try ArchiveStream.withEncodeStream(writingTo: compressor) { encoder in
                let header = ArchiveHeader()
                // 76 is `L`; the Swift overlay names no symbolic-link case to spell it with.
                header.append(.uint(key: ArchiveHeader.FieldKey("TYP"), value: 76))
                header.append(.string(key: ArchiveHeader.FieldKey("PAT"), value: "notes"))
                header.append(
                    .string(key: ArchiveHeader.FieldKey("LNK"), value: root.path))
                header.append(.uint(key: ArchiveHeader.FieldKey("MOD"), value: 0o777))
                try encoder.writeHeader(header)
            }
            try compressor.close()
            try destination.close()
        } catch {
            check("the symlink fixture can be built (\(error))", false)
            return
        }

        let into = root.appendingPathComponent("linked-out", isDirectory: true)
        do {
            try BackupArchive.open(file: archive, into: into)
            check("an archive carrying a symlink is refused", false)
        } catch {
            check(
                "an archive carrying a symlink is refused",
                error as? BackupArchive.ArchiveError == .cannotRead)
        }
    }

    // MARK: - Declarations

    /// The tripwire for adding a case and forgetting the layout or the picker.
    static func categoriesAreComplete() {
        var subpaths: Set<String> = []
        for category in BackupCategory.allCases {
            let descriptor = category.descriptor
            check("\(category.rawValue) has a label", !descriptor.label.isEmpty)
            check("\(category.rawValue) has a symbol", !descriptor.symbol.isEmpty)
            if !descriptor.subpath.isEmpty {
                check(
                    "\(category.rawValue)'s subpath is its own",
                    subpaths.insert(descriptor.subpath)
                        .inserted)
            }
        }
        check("every case is offered", BackupCategory.all.count == BackupCategory.allCases.count)
        check(
            "ordering follows declaration order",
            BackupCategory.ordered(BackupCategory.all) == BackupCategory.allCases)
    }

    static func staging() {
        let base = scratch()
        defer { try? FileManager.default.removeItem(at: base) }
        guard let staging = try? BackupStaging(base: base) else {
            check("staging is created on init", false)
            return
        }
        check(
            "staging is created on init",
            FileManager.default.fileExists(atPath: staging.root.path))
        staging.discard()
        check(
            "discard removes the tree",
            !FileManager.default.fileExists(atPath: staging.root.path))
        staging.discard()
        check("discard is idempotent", true)
    }
}
