import XCTest

final class LocalTranscriberUITests: XCTestCase {
    func testMainWindowLaunchesAndShowsEmptyState() {
        let app = XCUIApplication()
        app.launch()

        // メインウィンドウが起動し、空状態メッセージが表示される
        XCTAssertTrue(app.staticTexts["音声ファイルをドロップまたは選択して、文字起こしを開始してください"].waitForExistence(timeout: 10))
    }

    func testExportMenuAvailableAfterEmptyState() {
        let app = XCUIApplication()
        app.launch()

        // エクスポートメニューが存在する（テキスト無しのため無効状態でも存在はする）
        XCTAssertTrue(app.buttons["エクスポート"].waitForExistence(timeout: 10))
    }
}
