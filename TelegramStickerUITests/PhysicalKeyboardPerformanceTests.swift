import XCTest

/// Explicit physical-device opt-in. Does not install fixtures, change packs, copy, or read text/clipboard.
final class PhysicalKeyboardPerformanceTests: XCTestCase {
    /// Uses only this app's empty practice field. Never opens a chat or changes installed packs.
    @MainActor
    func testInstalledKeyboardPresentationAcrossSystemSwitches() throws {
        guard ProcessInfo.processInfo.environment["STICKERBRIDGE_KEYBOARD_PRESENTATION"] == "1" else {
            throw XCTSkip("실기기 표시 검사 시에만 명시적으로 실행합니다.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        func openPractice() {
            app.launch()
            XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 15))
            app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
            let practice = app.textFields["keyboardPractice"]
            XCTAssertTrue(practice.waitForExistence(timeout: 5))
            practice.tap()
        }
        func selectKeyboard() {
            let manage = app.buttons["keyboardManage"]
            if manage.waitForExistence(timeout: 1), manage.isHittable { return }
            let globe = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5))
            globe.press(forDuration: 0.8)
            let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "StickerBridge")).firstMatch
            if choice.waitForExistence(timeout: 2) { choice.tap() }
            else {
                let row = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "StickerBridge")).firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 3)); row.tap()
            }
            XCTAssertTrue(manage.waitForExistence(timeout: 5))
            XCTAssertTrue(manage.isHittable)
        }
        openPractice()
        selectKeyboard()
        let originalSelection = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "packTab."))
            .allElementsBoundByIndex.first { $0.isSelected }?.identifier
        var baseline: CGRect?
        func verify(_ phase: String) {
            let root = app.otherElements["keyboardSurface"].firstMatch
            let strip = app.scrollViews["keyboardPackStrip"]
            let grid = app.collectionViews["stickerGrid"]
            XCTAssertTrue(grid.waitForExistence(timeout: 5))
            XCTAssertTrue(grid.isHittable)
            let frame = root.frame
            print("Physical presentation \(phase): root=\(frame), strip=\(strip.frame), grid=\(grid.frame)")
            XCTAssertGreaterThan(grid.frame.height, 180)
            XCTAssertEqual(strip.frame.minY - frame.minY, 4, accuracy: 1)
            XCTAssertEqual(grid.frame.maxY, frame.maxY, accuracy: 1)
            if let baseline { XCTAssertEqual(frame.minY, baseline.minY, accuracy: 1); XCTAssertEqual(frame.height, baseline.height, accuracy: 1) }
            else { baseline = frame }
            if let originalSelection { XCTAssertTrue(app.buttons[originalSelection].isSelected) }
            let image = XCTAttachment(screenshot: app.screenshot())
            image.name = "Physical presentation " + phase; image.lifetime = .keepAlways; add(image)
        }
        verify("initial")
        for index in 0..<4 {
            app.buttons["Next keyboard"].firstMatch.tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["keyboardManage"])
            waitForExpectations(timeout: 5)
            selectKeyboard()
            verify("return \(index)")
        }
        app.terminate()
        openPractice()
        XCTAssertTrue(app.buttons["keyboardManage"].waitForExistence(timeout: 5))
        verify("direct reopen")
    }

    @MainActor
    func testInstalledKeyboardPackSwitchWorkload() throws {
        guard ProcessInfo.processInfo.environment["STICKERBRIDGE_KEYBOARD_PERFORMANCE"] == "1" else {
            throw XCTSkip("실기기 성능 측정 시에만 명시적으로 실행합니다.")
        }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 15))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        let practice = app.textFields["keyboardPractice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5)); practice.tap()
        let manage = app.buttons["keyboardManage"]
        if !manage.waitForExistence(timeout: 2) {
            let globe = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(globe.waitForExistence(timeout: 5)); globe.press(forDuration: 0.8)
            let row = app.cells.matching(NSPredicate(format: "label CONTAINS %@", "StickerBridge")).firstMatch
            if row.waitForExistence(timeout: 3) { row.tap() }
            else { app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "StickerBridge")).firstMatch.tap() }
        }
        XCTAssertTrue(manage.waitForExistence(timeout: 8))
        let choices = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "packTab.")).allElementsBoundByIndex
        XCTAssertGreaterThanOrEqual(choices.count, 3)
        let original = choices.first { $0.isSelected }?.identifier
        defer { if let original, app.buttons[original].exists { app.buttons[original].tap() } }
        print("StickerBridge physical performance workload ready")
        for _ in 0..<25 {
            for button in choices.prefix(4) {
                if button.isHittable { button.tap(); XCTAssertTrue(button.isSelected) }
            }
        }
        XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
        print("StickerBridge physical performance workload complete")
    }
}
