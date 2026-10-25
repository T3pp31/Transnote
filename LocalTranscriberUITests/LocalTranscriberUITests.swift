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
        XCTAssertTrue(app.menuButtons["文字起こし結果をエクスポート"].waitForExistence(timeout: 10))
    }

    func testSettingsSheetOpensAndCloses() {
        let app = XCUIApplication()
        app.launch()

        // Given: メイン画面が起動している（設定ボタンは常に表示される）
        XCTAssertTrue(app.buttons["設定"].firstMatch.waitForExistence(timeout: 30))

        // クラッシュ復旧アラートが出ていれば破棄して閉じる（環境の残データによる）
        let discardButton = app.sheets.buttons["action-button-2"]
        if discardButton.waitForExistence(timeout: 2) {
            discardButton.tap()
        }

        // When: 設定シートを開く
        app.buttons["設定"].firstMatch.tap()
        let closeButton = app.buttons["設定を閉じる"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
        XCTAssertTrue(closeButton.isHittable)

        // Then: 閉じるボタンで設定シートが閉じる
        app.buttons["設定を閉じる"].tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))

        // 下部の閉じるボタンもスクロールせずに操作できる
        app.buttons["設定"].firstMatch.tap()
        let footerCloseButton = app.sheets.buttons["閉じる"]
        XCTAssertTrue(footerCloseButton.waitForExistence(timeout: 10))
        XCTAssertTrue(footerCloseButton.isHittable)
        footerCloseButton.tap()
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))

        // Escape キーでもシートを閉じられる
        app.buttons["設定"].firstMatch.tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 10))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(closeButton.waitForNonExistence(timeout: 3))
    }
}
