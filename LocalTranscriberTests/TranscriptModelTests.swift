import XCTest
@testable import LocalTranscriber

final class TranscriptModelTests: XCTestCase {
    func testTranscriptCodableRoundTrip() throws {
        let original = Transcript(
            id: UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!,
            sourceFileName: "sample.wav",
            language: "en",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fullText: "Hello world",
            segments: [
                TranscriptSegment(
                    id: UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!,
                    startTime: 0.0,
                    endTime: 1.2,
                    text: "Hello"
                ),
                TranscriptSegment(
                    id: UUID(uuidString: "C3D4E5F6-A7B8-9012-CDEF-123456789012")!,
                    startTime: 1.2,
                    endTime: 2.4,
                    text: "world"
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Transcript.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.sourceFileName, original.sourceFileName)
        XCTAssertEqual(decoded.language, original.language)
        XCTAssertEqual(decoded.fullText, original.fullText)
        guard decoded.segments.count == original.segments.count else {
            return XCTFail("segments count mismatch: \(decoded.segments.count)")
        }
        XCTAssertEqual(decoded.segments[0].text, "Hello")
        XCTAssertEqual(decoded.segments[1].endTime, 2.4)
    }

    func testTranscriptSegmentIdentifiable() {
        let segment = TranscriptSegment(startTime: 0, endTime: 1, text: "test")
        XCTAssertNotNil(segment.id)
    }

    func testTranscriptSegmentTimestampFormatting() {
        let segment = TranscriptSegment(startTime: 3_723.456, endTime: 3_724, text: "test")

        XCTAssertEqual(segment.formattedStartTime, "01:02:03.456")
        XCTAssertEqual(segment.accessibilityStartTimestamp, "1時間2分3秒")
    }

    func testTranscriptSegmentTimestampFormattingClampsInvalidValues() {
        let invalidValues: [TimeInterval] = [
            .nan,
            .infinity,
            -.infinity,
            -1,
            Double(Int.max) / 1000 + 1
        ]

        for value in invalidValues {
            let segment = TranscriptSegment(startTime: value, endTime: value + 1, text: "test")

            XCTAssertFalse(segment.formattedStartTime.isEmpty)
            XCTAssertFalse(segment.accessibilityStartTimestamp.isEmpty)
        }
    }

    func testTranscriptSegmentTimestampFormattingClampsNonFiniteValuesToZero() {
        let invalidValues: [TimeInterval] = [.nan, .infinity, -.infinity, -1]

        for value in invalidValues {
            let segment = TranscriptSegment(startTime: value, endTime: 1, text: "test")

            XCTAssertEqual(segment.formattedStartTime, "00:00:00.000")
            XCTAssertEqual(segment.accessibilityStartTimestamp, "0秒")
        }
    }

    func testExportFormatFileExtensions() {
        XCTAssertEqual(ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(ExportFormat.srt.fileExtension, "srt")
        XCTAssertEqual(ExportFormat.vtt.fileExtension, "vtt")
    }

    func testAppDirectoriesDirectorySizeSumsRegularFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = root.appendingPathComponent("first.bin")
        let second = nested.appendingPathComponent("second.bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: first.path, contents: Data(repeating: 1, count: 12)))
        XCTAssertTrue(FileManager.default.createFile(atPath: second.path, contents: Data(repeating: 2, count: 8)))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked.bin"), withDestinationURL: first
        )

        XCTAssertEqual(AppDirectories.directorySize(of: root), 20)
    }

    func testAppDirectoriesDirectorySizeIncludesDotFilesAndHiddenDescendants() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        let hiddenNested = root.appendingPathComponent(".cache/deeper", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: hiddenNested, withIntermediateDirectories: true)

        let files = [
            (root.appendingPathComponent("visible.bin"), 5),
            (root.appendingPathComponent(".hidden.bin"), 7),
            (nested.appendingPathComponent(".hidden.bin"), 11),
            (hiddenNested.appendingPathComponent("payload.bin"), 13)
        ]
        for (url, size) in files {
            try Data(repeating: 1, count: size).write(to: url)
        }

        XCTAssertEqual(AppDirectories.directorySize(of: root), 36)
    }

    func testAppDirectoriesDirectorySizeIncludesHiddenAttributeFilesAndDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let hiddenDirectory = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: hiddenDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let hiddenFile = root.appendingPathComponent("hidden.bin")
        try Data(repeating: 1, count: 9).write(to: hiddenFile)
        try Data(repeating: 2, count: 15).write(to: hiddenDirectory.appendingPathComponent("payload.bin"))

        // ドット名ではなく、macOS の隠し属性を持つエントリも集計する。
        var values = URLResourceValues()
        values.isHidden = true
        for var url in [hiddenFile, hiddenDirectory] {
            try url.setResourceValues(values)
            XCTAssertEqual(try url.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)
        }

        XCTAssertEqual(AppDirectories.directorySize(of: root), 24)
    }

    func testAppDirectoriesDirectorySizeReturnsZeroForEmptyAndMissingDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertEqual(AppDirectories.directorySize(of: root), 0)
        XCTAssertEqual(AppDirectories.directorySize(of: root.appendingPathComponent("missing", isDirectory: true)), 0)
    }

    func testAppDirectoriesClearDirectoryReturnsResultAndPreservesDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent("file.bin").path, contents: Data("x".utf8))
        FileManager.default.createFile(atPath: root.appendingPathComponent(".hidden").path, contents: Data("x".utf8))

        XCTAssertTrue(AppDirectories.clearDirectory(root))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        XCTAssertEqual(AppDirectories.directorySize(of: root), 0)
        XCTAssertFalse(AppDirectories.clearDirectory(
            FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        ))

        defer { try? FileManager.default.removeItem(at: root) }
    }

    func testAppDirectoriesClearDirectoryReturnsFalseWhenRemovingEntryFails() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lockedFile = root.appendingPathComponent("locked.bin")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do {
                if fileManager.fileExists(atPath: lockedFile.path) {
                    try fileManager.setAttributes([.immutable: false], ofItemAtPath: lockedFile.path)
                }
                try fileManager.removeItem(at: root)
            } catch {
                XCTFail("一時ディレクトリの後片付けに失敗しました: \(error)")
            }
        }

        let content = Data("locked".utf8)
        try content.write(to: lockedFile)
        // macOS のロック属性で、一覧取得は成功してもエントリの削除だけが失敗する状態を作る。
        try fileManager.setAttributes([.immutable: true], ofItemAtPath: lockedFile.path)
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), ["locked.bin"])
        XCTAssertThrowsError(try fileManager.removeItem(at: lockedFile))

        XCTAssertFalse(AppDirectories.clearDirectory(root))
        XCTAssertTrue(fileManager.fileExists(atPath: root.path))
        XCTAssertEqual(try Data(contentsOf: lockedFile), content)
    }

    func testTranscriptRejectsUnsupportedSchemaVersion() throws {
        let json = """
        {
          "id": "\(UUID().uuidString)",
          "sourceFileName": "sample.wav",
          "createdAt": "2026-01-01T00:00:00Z",
          "fullText": "hello",
          "segments": [],
          "schemaVersion": 999
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertThrowsError(try decoder.decode(Transcript.self, from: data))
    }
    // MARK: - AppConfig / AppSettings (#245)

    func testAppConfigDefaultValues() {
        let config = AppConfig()
        XCTAssertFalse(config.supportedExtensions.isEmpty)
        XCTAssertFalse(config.models.isEmpty)
        XCTAssertFalse(config.languages.isEmpty)
        XCTAssertFalse(config.defaultModelID.isEmpty)
        XCTAssertEqual(config.modelsDirectoryName, "Models")
    }

    func testLargeV3ModelNamesMatchConfiguredVariants() throws {
        let appBundle = Bundle(for: MainWindowViewModel.self)
        let config = AppConfig(bundle: appBundle)
        let expectedModels: [(id: String, displayName: String, variant: String)] = [
            ("large-v3-compressed", "Large v3 (compressed)", "large-v3-v20240930_626MB"),
            ("large-v3-turbo", "Large v3 Turbo", "large-v3-v20240930_turbo")
        ]

        for expected in expectedModels {
            let model = try XCTUnwrap(config.models.first { $0.id == expected.id })
            XCTAssertEqual(model.displayName, expected.displayName, expected.id)
            XCTAssertEqual(model.whisperKitModelName, expected.variant, expected.id)

            // 実行環境の優先言語に依存せず、設定画面が使う日英両方の表示名を検証する。
            for language in ["ja", "en"] {
                let localizationURL = try XCTUnwrap(
                    appBundle.url(forResource: language, withExtension: "lproj")
                )
                let localizationBundle = try XCTUnwrap(Bundle(url: localizationURL))
                XCTAssertEqual(
                    localizationBundle.localizedString(forKey: "model.\(model.id)", value: nil, table: nil),
                    expected.displayName,
                    "\(model.id) (\(language))"
                )
            }
        }
    }

    func testAppConfigCustomInit() {
        let config = AppConfig(
            supportedExtensions: ["wav"],
            defaultModelID: "tiny",
            defaultLanguageID: "en",
            modelsDirectoryName: "Models",
            models: [ModelOption(id: "tiny", displayName: "Tiny", whisperKitModelName: "tiny")],
            languages: [LanguageOption(id: "en", displayName: "English")],
            updateCheckEnabled: true,
            githubReleasesAPIURL: URL(string: "https://api.github.com/repos/T3pp31/Transnote/releases/latest")!,
            updateDownloadFallbackURL: URL(string: "https://github.com/T3pp31/Transnote")!,
            updateDMGAssetName: "Transnote.dmg"
        )
        XCTAssertEqual(config.supportedExtensions, ["wav"])
        XCTAssertEqual(config.defaultModelID, "tiny")
        XCTAssertEqual(config.models.count, 1)
    }

    @MainActor
    func testAppSettingsSharedHasValidSelection() {
        let settings = AppSettings.shared
        XCTAssertFalse(settings.models.isEmpty)
        XCTAssertFalse(settings.languages.isEmpty)
        XCTAssertNotNil(settings.selectedModel)
        XCTAssertNotNil(settings.selectedLanguage)
    }

    @MainActor
    func testAppSettingsSelectionFallbackPriority() throws {
        let suiteName = "AppSettingsSelectionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let models = [
            ModelOption(id: "tiny", displayName: "Tiny", whisperKitModelName: "tiny"),
            ModelOption(id: "base", displayName: "Base", whisperKitModelName: "base"),
            ModelOption(id: "small", displayName: "Small", whisperKitModelName: "small")
        ]
        // 先頭は既定言語 auto とは異なる値にし、配列順でのフォールバックを検証する。
        let languages = [
            LanguageOption(id: "ja", displayName: "Japanese"),
            LanguageOption(id: "auto", displayName: "Auto"),
            LanguageOption(id: "en", displayName: "English")
        ]
        let defaultCases: [(model: String, language: String, fallbackModel: String, fallbackLanguage: String)] = [
            ("base", "auto", "base", "auto"),
            ("large-v3", "fr", "tiny", "ja"),
            ("", "", "tiny", "ja")
        ]
        let savedModelIDs: [String?] = [nil, "removed-model", "small"]
        let savedLanguageIDs: [String?] = [nil, "removed-language", "en"]

        for defaultCase in defaultCases {
            let config = AppConfig(
                supportedExtensions: ["wav"],
                defaultModelID: defaultCase.model,
                defaultLanguageID: defaultCase.language,
                modelsDirectoryName: "Models",
                models: models,
                languages: languages,
                updateCheckEnabled: true,
                githubReleasesAPIURL: URL(string: "https://api.github.com/repos/T3pp31/Transnote/releases/latest")!,
                updateDownloadFallbackURL: URL(string: "https://github.com/T3pp31/Transnote")!,
                updateDMGAssetName: "Transnote.dmg"
            )

            for savedModelID in savedModelIDs {
                for savedLanguageID in savedLanguageIDs {
                    defaults.set(savedModelID, forKey: "selectedModelID")
                    defaults.set(savedLanguageID, forKey: "selectedLanguageID")
                    let settings = AppSettings(config: config, defaults: defaults)
                    let expectedModelID = savedModelID == "small" ? "small" : defaultCase.fallbackModel
                    let expectedLanguageID = savedLanguageID == "en" ? "en" : defaultCase.fallbackLanguage
                    let context = "defaults=\(defaultCase.model)/\(defaultCase.language), "
                        + "saved=\(savedModelID ?? "nil")/\(savedLanguageID ?? "nil")"

                    XCTAssertEqual(settings.selectedModelID, expectedModelID, context)
                    XCTAssertEqual(settings.selectedLanguageID, expectedLanguageID, context)
                    XCTAssertEqual(settings.selectedModel, models.first { $0.id == expectedModelID }, context)
                    XCTAssertEqual(settings.selectedLanguage, languages.first { $0.id == expectedLanguageID }, context)
                }
            }
        }
    }

    // MARK: - History store (#213)

    func testHistoryStoreSaveAndRecent() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(historyRoot: root)

        let transcript = Transcript(
            sourceFileName: "meeting.wav",
            language: "ja",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            fullText: "こんにちは",
            segments: [TranscriptSegment(startTime: 0, endTime: 1, text: "こんにちは")]
        )

        try store.save(transcript)
        let recent = store.recent()

        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.sourceFileName, "meeting.wav")
        XCTAssertEqual(recent.first?.fullText, "こんにちは")
    }

    func testHistoryStoreSearchLimitsByCreationDateInsteadOfModificationDate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(historyRoot: root)
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let older = Transcript(sourceFileName: "older.wav", createdAt: baseDate, fullText: "needle")
        let middle = Transcript(
            sourceFileName: "middle.wav", createdAt: baseDate.addingTimeInterval(100), fullText: "needle"
        )
        let newest = Transcript(
            sourceFileName: "newest.wav", createdAt: baseDate.addingTimeInterval(200), fullText: "needle"
        )

        // 古い履歴の再保存を模し、作成日時と逆順の更新日時を明示して走査順を固定する。
        for (transcript, offset) in [(older, 600.0), (middle, 500.0), (newest, 400.0)] {
            try store.save(transcript)
            try FileManager.default.setAttributes(
                [.modificationDate: baseDate.addingTimeInterval(offset)],
                ofItemAtPath: root.appendingPathComponent("\(transcript.id.uuidString).json").path
            )
        }

        XCTAssertEqual(store.search(query: "needle", limit: 1).map(\.id), [newest.id])
        XCTAssertEqual(store.search(query: "needle", limit: 2).map(\.id), [newest.id, middle.id])
        XCTAssertEqual(store.search(query: "needle", limit: 10).map(\.id), [newest.id, middle.id, older.id])
        XCTAssertEqual(store.search(query: "needle", limit: 2).map(\.id), store.recent(limit: 2).map(\.id))
    }

    func testHistoryStoreSearchMatchesTextAndFileNameAndSkipsInvalidJSON() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(historyRoot: root)
        XCTAssertTrue(store.search(query: "needle").isEmpty)

        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let textMatch = Transcript(sourceFileName: "meeting.wav", createdAt: baseDate, fullText: "A Needle appears")
        let fileNameMatch = Transcript(
            sourceFileName: "NEEDLE-recording.wav", createdAt: baseDate.addingTimeInterval(100), fullText: "other text"
        )
        let nonMatch = Transcript(
            sourceFileName: "unrelated.wav", createdAt: baseDate.addingTimeInterval(200), fullText: "other text"
        )
        for transcript in [textMatch, fileNameMatch, nonMatch] {
            try store.save(transcript)
        }
        try Data("not valid JSON".utf8).write(to: root.appendingPathComponent("broken.json"))

        XCTAssertEqual(store.search(query: "nEeDlE", limit: 10).map(\.id), [fileNameMatch.id, textMatch.id])
        XCTAssertEqual(store.search(query: "nEeDlE", limit: 1).map(\.id), [fileNameMatch.id])
        XCTAssertTrue(store.search(query: "absent").isEmpty)
        XCTAssertTrue(store.search(query: "needle", limit: 0).isEmpty)
        XCTAssertEqual(store.search(query: "", limit: 2).map(\.id), [nonMatch.id, fileNameMatch.id])
    }

    func testHistoryStoreDelete() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = HistoryStore(historyRoot: root)

        let transcript = Transcript(sourceFileName: "a.wav", fullText: "hello")
        try store.save(transcript)
        store.delete(transcript)

        XCTAssertTrue(store.recent().isEmpty)

    }
}
