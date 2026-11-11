import XCTest

@testable import LocalTranscriber

final class SecurityScopedFileAccessTests: XCTestCase {
    private var access: SecurityScopedFileAccess!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        access = SecurityScopedFileAccess()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        access.endAllAccess()
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testBeginAccessAllowsLocalFile() throws {
        let file = tempRoot.appendingPathComponent("local.wav")
        let contents = Data("local audio".utf8)
        try contents.write(to: file)

        try access.beginAccess(url: file)

        XCTAssertEqual(try Data(contentsOf: file), contents)
        access.endAccess(url: file)
    }

    func testBeginAccessAllowsFileWhenScopeDoesNotStart() throws {
        let file = tempRoot.appendingPathComponent("local.wav")
        let contents = Data("local audio".utf8)
        try contents.write(to: file)
        var startedURLs: [URL] = []
        var stoppedURLs: [URL] = []
        access = SecurityScopedFileAccess(
            startAccessing: { url in
                startedURLs.append(url)
                return false
            },
            stopAccessing: { stoppedURLs.append($0) }
        )

        try access.beginAccess(url: file)

        XCTAssertEqual(startedURLs, [file])
        XCTAssertEqual(try Data(contentsOf: file), contents)
        access.endAccess(url: file)
        access.endAccess(url: file)
        access.endAllAccess()
        XCTAssertTrue(stoppedURLs.isEmpty)
    }

    func testBeginAccessAllowsWritingInDirectoryWhenScopeDoesNotStart() throws {
        var stoppedURLs: [URL] = []
        access = SecurityScopedFileAccess(
            startAccessing: { _ in false },
            stopAccessing: { stoppedURLs.append($0) }
        )

        try access.beginAccess(url: tempRoot)
        let export = tempRoot.appendingPathComponent("transcript.txt")
        let contents = "文字起こし結果"
        try contents.write(to: export, atomically: true, encoding: .utf8)

        XCTAssertEqual(try String(contentsOf: export, encoding: .utf8), contents)
        access.endAllAccess()
        access.endAccess(url: tempRoot)
        XCTAssertTrue(stoppedURLs.isEmpty)
    }

    func testMissingFileOnlyStopsSuccessfullyStartedScope() {
        let missing = tempRoot.appendingPathComponent("missing.wav")
        for didStart in [false, true] {
            var startedURLs: [URL] = []
            var stoppedURLs: [URL] = []
            access = SecurityScopedFileAccess(
                startAccessing: { url in
                    startedURLs.append(url)
                    return didStart
                },
                stopAccessing: { stoppedURLs.append($0) }
            )

            XCTAssertThrowsError(try access.beginAccess(url: missing)) { error in
                guard case AppError.fileNotFound = error else {
                    return XCTFail("Expected fileNotFound, got \(error)")
                }
            }

            XCTAssertEqual(startedURLs, [missing])
            let expectedStops = didStart ? [missing] : []
            XCTAssertEqual(stoppedURLs, expectedStops)
            access.endAccess(url: missing)
            access.endAllAccess()
            XCTAssertEqual(stoppedURLs, expectedStops)
        }
    }

    func testEndAccessStopsStartedScopeOnlyOnce() throws {
        var stoppedURLs: [URL] = []
        access = SecurityScopedFileAccess(
            startAccessing: { _ in true },
            stopAccessing: { stoppedURLs.append($0) }
        )

        try access.beginAccess(url: tempRoot)
        access.endAccess(url: tempRoot.appendingPathComponent("unknown.wav"))
        XCTAssertTrue(stoppedURLs.isEmpty)

        access.endAccess(url: tempRoot)
        XCTAssertEqual(stoppedURLs, [tempRoot!])
        access.endAccess(url: tempRoot)
        access.endAllAccess()
        XCTAssertEqual(stoppedURLs, [tempRoot!])
    }

    func testRepeatedAccessKeepsEachScopeResult() throws {
        var startCount = 0
        var stoppedURLs: [URL] = []
        access = SecurityScopedFileAccess(
            startAccessing: { _ in
                startCount += 1
                return startCount != 1
            },
            stopAccessing: { stoppedURLs.append($0) }
        )

        try access.beginAccess(url: tempRoot)  // スコープ不要
        try access.beginAccess(url: tempRoot)  // スコープ開始成功
        try access.beginAccess(url: tempRoot)  // 同じ URL でも開始回数分の終了が必要
        XCTAssertEqual(startCount, 3)

        access.endAccess(url: tempRoot)
        XCTAssertTrue(stoppedURLs.isEmpty)
        access.endAccess(url: tempRoot)
        XCTAssertEqual(stoppedURLs, [tempRoot!])
        access.endAllAccess()
        XCTAssertEqual(stoppedURLs, [tempRoot!, tempRoot!])
        access.endAccess(url: tempRoot)
        access.endAllAccess()
        XCTAssertEqual(stoppedURLs, [tempRoot!, tempRoot!])
    }

    func testEndAllAccessOnlyStopsStartedScopes() throws {
        let file = tempRoot.appendingPathComponent("local.wav")
        try Data("local audio".utf8).write(to: file)
        var stoppedURLs: [URL] = []
        access = SecurityScopedFileAccess(
            startAccessing: { $0 == file },
            stopAccessing: { stoppedURLs.append($0) }
        )

        try access.beginAccess(url: tempRoot)
        try access.beginAccess(url: file)
        try access.beginAccess(url: file)
        XCTAssertTrue(stoppedURLs.isEmpty)

        access.endAllAccess()
        XCTAssertEqual(stoppedURLs, [file, file])
        access.endAllAccess()
        access.endAccess(url: file)
        XCTAssertEqual(stoppedURLs, [file, file])
    }

    func testBeginAccessThrowsForMissingFile() {
        let missing = tempRoot.appendingPathComponent("missing.wav")
        XCTAssertThrowsError(try access.beginAccess(url: missing)) { error in
            guard case AppError.fileNotFound = error else {
                return XCTFail("Expected fileNotFound, got \(error)")
            }
        }
    }

    func testLastExportDirectoryBookmarkRoundTrip() throws {
        let directory = tempRoot.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = SecurityScopedFileAccess.lastExportDirectoryKey
        let originalBookmark = UserDefaults.standard.data(forKey: key)
        defer {
            if let originalBookmark {
                UserDefaults.standard.set(originalBookmark, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        access.saveLastExportDirectoryBookmark(for: directory)

        XCTAssertEqual(
            access.loadLastExportDirectory()?.standardizedFileURL,
            directory.standardizedFileURL
        )
    }

    func testEndAccessIsNoOpForUnknownURL() {
        // 開始していないURLへの endAccess はクラッシュせず何もしない
        let url = tempRoot.appendingPathComponent("not-started.wav")
        FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
        access.endAccess(url: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testEndAllAccessIsSafeWhenNothingStarted() {
        access.endAllAccess()
        // 何も開始していなくても例外を投げない
        XCTAssertTrue(true)
    }

    func testResolveBookmarkThrowsForInvalidData() {
        XCTAssertThrowsError(try access.resolveBookmark(Data()))
    }
}
