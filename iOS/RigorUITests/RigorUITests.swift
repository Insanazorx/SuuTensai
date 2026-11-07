import XCTest

final class RigorUITests: XCTestCase {
    @MainActor
    private func launch(source: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if let source { app.launchEnvironment["RIGOR_TEST_SOURCE"] = source }
        app.launch()
        XCTAssertTrue(app.textViews["rigor.editor"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    func testScrollableSymbolsInsertExactlyTheRequestedCharacters() throws {
        let app = launch(source: "")
        let editor = app.textViews["rigor.editor"]
        editor.tap()
        let strip = app.scrollViews["rigor.symbols"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        let symbols = ["{", "}", "(", ")", "->", "=>", "<", ">", ":"]
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "rigor.symbol.")).count, symbols.count)
        var expected = ""
        for (index, symbol) in symbols.enumerated() {
            let button = app.buttons["rigor.symbol.\(index)"]
            if !button.isHittable { strip.swipeLeft() }
            XCTAssertTrue(button.isHittable, "Sembol kaydırarak erişilebilir olmalı: \(symbol)")
            button.tap()
            expected += symbol
            XCTAssertEqual(editor.value as? String, expected)
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Kaydırılabilir semboller"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testLandscapeKeepsEditorAndLiveResultUsableWithKeyboard() throws {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        let orientation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        let rotated = XCTWaiter.wait(for: [orientation], timeout: 10)
        if rotated != .completed, ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4" {
            throw XCTSkip("Kapalı iPhone Duo simülatör ekranı yatay dönüşü uygulamıyor; bu test dönebilen iPhone/simülatör gerektirir.")
        }
        XCTAssertEqual(rotated, .completed)
        let editor = app.textViews["rigor.editor"]
        editor.tap()
        XCTAssertTrue(app.scrollViews["rigor.symbols"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(editor.frame.height, 70)
        XCTAssertTrue(editor.isHittable)
        XCTAssertTrue(app.staticTexts["rigor.status"].isHittable)
        editor.typeText("// yatay mod\n")
        XCTAssertTrue((editor.value as? String)?.contains("// yatay mod") == true)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Yatay editör ve checker"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.orientation = .portrait
    }
}
