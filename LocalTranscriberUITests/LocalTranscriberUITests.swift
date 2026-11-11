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

    func testUpdateCheckMenuRemainsEnabledWithoutMainWindow() {
        let app = XCUIApplication()
        // 起動時の更新通知がメニュー操作を妨げないよう、既存の設定キーを使う。
        app.launchArguments = ["-updateCheckEnabled", "NO", "-AppleLanguages", "(ja)"]
        app.launch()

        let settingsButton = app.buttons["設定"].firstMatch
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 30))
        let discardButton = app.sheets.buttons["action-button-2"]
        if discardButton.waitForExistence(timeout: 2) {
            discardButton.tap()
        }
        let mainWindow = app.windows.firstMatch
        let transcriptionMenu = app.menuBars.menuBarItems["文字起こし"]
        let updateItem = app.menuItems["アップデートを確認…"]
        let openFileItem = app.menuItems["ファイルを開く…"]

        // 通常時は、アプリ全体の操作もウィンドウ固有の操作も有効。
        transcriptionMenu.click()
        XCTAssertTrue(updateItem.waitForExistence(timeout: 5))
        XCTAssertTrue(updateItem.isEnabled)
        XCTAssertTrue(openFileItem.isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        // 設定シートを操作中でも更新確認は利用できる。
        settingsButton.tap()
        let closeSettingsButton = app.buttons["設定を閉じる"]
        XCTAssertTrue(closeSettingsButton.waitForExistence(timeout: 10))
        transcriptionMenu.click()
        XCTAssertTrue(updateItem.waitForExistence(timeout: 5))
        XCTAssertTrue(updateItem.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        closeSettingsButton.tap()
        XCTAssertTrue(closeSettingsButton.waitForNonExistence(timeout: 3))

        // 全ウィンドウを閉じて FocusedValue が無くなっても、更新確認だけは有効。
        mainWindow.typeKey("w", modifierFlags: [.command])
        XCTAssertTrue(mainWindow.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 0)
        transcriptionMenu.click()
        XCTAssertTrue(updateItem.waitForExistence(timeout: 5))
        XCTAssertTrue(updateItem.isEnabled)
        XCTAssertFalse(openFileItem.isEnabled)
        app.typeKey(.escape, modifierFlags: [])
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
