import XCTest

/// Requires StickerBridge to be enabled beforehand. Does not change keyboard/security settings.
final class KeyboardUITests: XCTestCase {
    @MainActor
    func testKeyboardControlsGridAndPackManagement() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-b").firstMatch.waitForExistence(timeout: 15))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        let practice = app.textFields["keyboardPractice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5)); practice.tap()
        let manage = app.buttons["keyboardManage"]
        try returnToStickerKeyboard(app)
        let grid = app.collectionViews["stickerGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        let surface = app.otherElements["keyboardSurface"].firstMatch
        if surface.exists {
            print("Keyboard geometry: surface=\(surface.frame), tabs=\(app.scrollViews["keyboardPackStrip"].frame), grid=\(grid.frame)")
        }
        XCTAssertGreaterThanOrEqual(manage.frame.height, 32)
        XCTAssertFalse(app.staticTexts["keyboardSelectedPack"].exists)
        let basics = app.buttons["packTab.keyboard-ui-a"]
        let lights = app.buttons["packTab.keyboard-ui-b"]
        XCTAssertTrue(basics.exists); XCTAssertTrue(lights.exists)
        basics.tap()
        let cell = grid.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(cell.frame.width, 44)
        XCTAssertLessThan(cell.frame.width, 80)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Actual custom keyboard without footer"; screenshot.lifetime = .keepAlways; add(screenshot)
        // Normalize any order retained by an earlier run.
        manage.tap(); app.buttons["앱의 팩 순서로 되돌리기"].tap()
        XCTAssertTrue(basics.waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in basics.frame.minX < lights.frame.minX }, evaluatedWith: basics)
        waitForExpectations(timeout: 5)
        let source = basics.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destination = lights.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        source.press(forDuration: 0.5, thenDragTo: destination)
        XCTAssertTrue(lights.waitForExistence(timeout: 5))
        XCTAssertLessThan(lights.frame.minX, basics.frame.minX)
        XCTAssertTrue(basics.isSelected)
        // This writes only a self-authored test image, and never reads clipboard contents.
        cell.tap()
        let status = app.staticTexts["keyboardCopyStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 3))
        if status.label.contains("복사됨") {
            app.buttons["packTab.recent"].tap()
            XCTAssertTrue(app.buttons["packTab.recent"].isSelected)
            let recentCount = grid.cells.count
            // Switch through the system globe and return: the selected list must not reset to all/samples.
            let globe = app.buttons["Next keyboard"].firstMatch
            if globe.exists {
                globe.tap()
                expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: manage)
                waitForExpectations(timeout: 5)
                try returnToStickerKeyboard(app)
                XCTAssertTrue(app.buttons["packTab.recent"].isSelected)
                XCTAssertEqual(grid.cells.count, recentCount)
            }
            manage.tap()
            app.buttons["최근 사용 내역 비우기"].tap()
            XCTAssertTrue(app.staticTexts["최근 사용한 스티커가 없어요. 전체에서 스티커를 복사해 보세요."].waitForExistence(timeout: 5))
            app.terminate(); app.launch()
            app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
            XCTAssertTrue(practice.waitForExistence(timeout: 5)); practice.tap()
            try returnToStickerKeyboard(app)
            XCTAssertTrue(app.buttons["packTab.recent"].isSelected)
            XCTAssertEqual(grid.cells.count, 0)
            XCTAssertLessThan(lights.frame.minX, basics.frame.minX)
            XCTAssertFalse(app.buttons["packTab.all"].isSelected)
        } else {
            XCTAssertTrue(status.label.contains("전체 접근"))
        }
        manage.tap(); app.buttons["앱의 팩 순서로 되돌리기"].tap()
        app.buttons["packTab.all"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        let dense = XCTAttachment(screenshot: app.screenshot())
        dense.name = "Actual keyboard full grid idle"; dense.lifetime = .keepAlways; add(dense)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(grid.frame.height, 80)
        XCTAssertGreaterThanOrEqual(grid.cells.firstMatch.frame.width, 44)
        XCTAssertLessThan(grid.cells.firstMatch.frame.width, 80)
        // Exercise a tab after rotation and wait for its transient feedback to finish before capturing.
        app.buttons["packTab.keyboard-ui-b"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        let landscape = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscape.name = "Actual keyboard landscape"; landscape.lifetime = .keepAlways; add(landscape)
    }

    @MainActor
    func testRepeatedKeyboardSwitchesRestoreRecentList() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        let practice = app.textFields["keyboardPractice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5)); practice.tap()
        try returnToStickerKeyboard(app)
        app.buttons["packTab.keyboard-ui-a"].tap()
        let grid = app.collectionViews["stickerGrid"]
        for index in 1...2 {
            grid.cells["keyboardSticker.keyboard-ui-a.item-\(index)"].tap()
            XCTAssertTrue(app.staticTexts["keyboardCopyStatus"].label.contains("복사됨"))
        }
        app.buttons["packTab.recent"].tap()
        let count = grid.cells.count
        XCTAssertGreaterThanOrEqual(count, 2)
        for iteration in 0..<5 {
            print("Keyboard transition cycle \(iteration) begins")
            app.buttons["Next keyboard"].firstMatch.tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["keyboardManage"])
            waitForExpectations(timeout: 5)
            try returnToStickerKeyboard(app)
            XCTAssertTrue(app.buttons["packTab.recent"].isSelected)
            XCTAssertEqual(app.collectionViews["stickerGrid"].cells.count, count)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "Keyboard return \(iteration)"; shot.lifetime = .keepAlways; add(shot)
        }
    }

    @MainActor
    func testBothSelectedPacksScrollToEndAndBackWithoutCountToast() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-b").firstMatch.waitForExistence(timeout: 15))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        app.textFields["keyboardPractice"].tap()
        try returnToStickerKeyboard(app)
        let grid = app.collectionViews["stickerGrid"]
        for (pack, count) in [("keyboard-ui-a", 60), ("keyboard-ui-b", 45)] {
            app.buttons["packTab." + pack].tap()
            XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
            let first = grid.cells["keyboardSticker." + pack + ".item-1"]
            let last = grid.cells["keyboardSticker." + pack + ".item-\(count)"]
            XCTAssertTrue(first.isHittable)
            if pack == "keyboard-ui-b" { XCTAssertTrue(first.label.contains("테스트 팩 B")) }
            for _ in 0..<8 where !last.isHittable { grid.swipeUp(velocity: .slow) }
            XCTAssertTrue(last.isHittable, "Selected pack must scroll to its final sticker")
            XCTAssertFalse(first.isHittable)
            for _ in 0..<8 where !first.isHittable { grid.swipeDown(velocity: .slow) }
            XCTAssertTrue(first.isHittable, "Selected pack must scroll back to its first sticker")
            if pack == "keyboard-ui-b" {
                first.press(forDuration: 0.8)
                let png = app.buttons["정적 PNG로 복사"]
                XCTAssertTrue(png.waitForExistence(timeout: 3)); png.tap()
                XCTAssertTrue(app.staticTexts["keyboardCopyStatus"].label.contains("복사됨"))
            }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Compact scrollable \(pack)"; screenshot.lifetime = .keepAlways; add(screenshot)
        }
        app.buttons["packTab.recent"].tap()
        XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
        app.buttons["packTab.all"].tap()
        XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
    }

    @MainActor
    func testDiagonalSwipesScrollStaticAndGIFPacks() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-b").firstMatch.waitForExistence(timeout: 15))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        app.textFields["keyboardPractice"].tap()
        try returnToStickerKeyboard(app)
        let grid = app.collectionViews["stickerGrid"]
        for pack in ["keyboard-ui-a", "keyboard-ui-b"] {
            for (startX, endX) in [(0.70, 0.35), (0.20, 0.55), (0.30, 0.45), (0.65, 0.50)] {
                app.buttons["packTab.all"].tap()
                app.buttons["packTab." + pack].tap()
                let marker = grid.cells["keyboardSticker." + pack + ".item-15"]
                XCTAssertTrue(marker.exists)
                let originalY = marker.frame.minY
                let start = grid.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.80))
                let end = grid.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.35))
                start.press(forDuration: 0.01, thenDragTo: end, withVelocity: XCUIGestureVelocity(rawValue: 250), thenHoldForDuration: 0.15)
                XCTAssertTrue(marker.exists)
                let scrolledY = marker.frame.minY
                print("Diagonal \(pack) \(startX)→\(endX): \(originalY)→\(scrolledY)")
                XCTAssertLessThan(scrolledY, originalY - 20, "Diagonal movement must scroll vertically")
                XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists, "A swipe must not copy a sticker")
                XCTAssertFalse(app.buttons["정적 PNG로 복사"].exists, "A swipe must not open the GIF menu")
                end.press(forDuration: 0.01, thenDragTo: start, withVelocity: XCUIGestureVelocity(rawValue: 250), thenHoldForDuration: 0.15)
                XCTAssertGreaterThan(marker.frame.minY, scrolledY + 20, "Reverse diagonal must scroll back")
                XCTAssertTrue(app.buttons["packTab." + pack].isSelected)
            }
            // This transparent image margin was a dead touch region with a completely clear backing.
            grid.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.80)).tap()
            XCTAssertTrue(app.staticTexts["keyboardCopyStatus"].label.contains("복사됨"))
        }
    }

    @MainActor
    func testHorizontalSwipesSelectAdjacentPacksWithoutCopying() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-b").firstMatch.waitForExistence(timeout: 15))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        app.textFields["keyboardPractice"].tap()
        try returnToStickerKeyboard(app)
        app.buttons["keyboardManage"].tap()
        app.buttons["앱의 팩 순서로 되돌리기"].tap()
        let a = app.buttons["packTab.keyboard-ui-a"]
        XCTAssertTrue(a.waitForExistence(timeout: 5)); a.tap()
        let grid = app.collectionViews["stickerGrid"]
        let right = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5))
        let left = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.20, dy: 0.5))
        right.press(forDuration: 0.01, thenDragTo: left, withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.05)
        XCTAssertTrue(app.buttons["packTab.keyboard-ui-b"].isSelected)
        XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
        left.press(forDuration: 0.01, thenDragTo: right, withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.05)
        XCTAssertTrue(a.isSelected)
        XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
        app.buttons["packTab.all"].tap()
        left.press(forDuration: 0.01, thenDragTo: right, withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.05)
        XCTAssertTrue(app.buttons["packTab.all"].isSelected, "First tab must not wrap around")
        right.press(forDuration: 0.01, thenDragTo: left, withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.05)
        XCTAssertTrue(app.buttons["packTab.recent"].isSelected)
        // The middle of a sparse recent list must receive swipes too, even without an image there.
        left.press(forDuration: 0.01, thenDragTo: right, withVelocity: XCUIGestureVelocity(rawValue: 400), thenHoldForDuration: 0.05)
        XCTAssertTrue(app.buttons["packTab.all"].isSelected)
    }

    @MainActor
    func testVisibleGIFCellsAnimateAndPackChangesStayResponsive() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-b").firstMatch.waitForExistence(timeout: 20))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        let practice = app.textFields["keyboardPractice"]
        XCTAssertTrue(practice.waitForExistence(timeout: 5)); practice.tap()
        try returnToStickerKeyboard(app)
        let a = app.buttons["packTab.keyboard-ui-a"], b = app.buttons["packTab.keyboard-ui-b"]
        b.tap()
        let cell = app.collectionViews["stickerGrid"].cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        let cellFrame = cell.frame
        func frameData() throws -> Data {
            let shot = app.screenshot().image
            let cg = try XCTUnwrap(shot.cgImage)
            let scale = CGFloat(cg.width) / shot.size.width
            let rect = CGRect(x: cellFrame.minX * scale, y: cellFrame.minY * scale,
                              width: cellFrame.width * scale, height: cellFrame.height * scale).integral
            let crop = try XCTUnwrap(cg.cropping(to: rect))
            return try XCTUnwrap(UIImage(cgImage: crop).pngData())
        }
        var frames = Set<Data>()
        for _ in 0..<5 {
            frames.insert(try frameData())
            Thread.sleep(forTimeInterval: 0.17)
        }
        XCTAssertGreaterThan(frames.count, 1, "Visible GIF thumbnail must change without tapping/copying.")
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.name = "Animated GIF keyboard grid"; screenshot.lifetime = .keepAlways; add(screenshot)
        // Actual selection intervals are recorded by OSSignposter; XCTest tap includes automation overhead.
        for _ in 0..<12 { a.tap(); XCTAssertTrue(a.isSelected); b.tap(); XCTAssertTrue(b.isSelected) }
        XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
    }

    @MainActor
    func testSevenColumnsFourRowsSeparatePacksAndCancelledSwipe() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-b").firstMatch.waitForExistence(timeout: 20))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        app.textFields["keyboardPractice"].tap()
        try returnToStickerKeyboard(app)
        app.buttons["keyboardManage"].tap(); app.buttons["앱의 팩 순서로 되돌리기"].tap()
        app.buttons["packTab.keyboard-ui-a"].tap()
        let grid = app.collectionViews["stickerGrid"]
        let first = grid.cells["keyboardSticker.keyboard-ui-a.item-1"]
        let seventh = grid.cells["keyboardSticker.keyboard-ui-a.item-7"]
        let eighth = grid.cells["keyboardSticker.keyboard-ui-a.item-8"]
        let twentyEighth = grid.cells["keyboardSticker.keyboard-ui-a.item-28"]
        XCTAssertEqual(first.frame.minY, seventh.frame.minY, accuracy: 1)
        XCTAssertGreaterThan(eighth.frame.minY, first.frame.minY)
        XCTAssertTrue(twentyEighth.isHittable)
        XCTAssertLessThanOrEqual(twentyEighth.frame.maxY, grid.frame.maxY + 2)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        XCTAssertEqual(twentyEighth.frame.maxY, grid.frame.maxY, accuracy: 2, "Four rows should fill the owned viewport without a footer gap")
        let surface = app.otherElements["keyboardSurface"].firstMatch
        if surface.exists {
            print("Compact keyboard geometry: surface=\(surface.frame), tabs=\(app.scrollViews["keyboardPackStrip"].frame), grid=\(grid.frame)")
            XCTAssertEqual(grid.frame.maxY, surface.frame.maxY, accuracy: 1, "Do not reserve the system keyboard band twice")
        }
        let dense = XCTAttachment(screenshot: app.screenshot()); dense.name = "Seven by four keyboard"; dense.lifetime = .keepAlways; add(dense)
        app.buttons["packTab.all"].tap()
        let lastA = grid.cells["keyboardSticker.keyboard-ui-a.item-60"]
        let firstB = grid.cells["keyboardSticker.keyboard-ui-b.item-1"]
        for _ in 0..<8 where !firstB.isHittable { grid.swipeUp(velocity: .slow) }
        XCTAssertTrue(firstB.isHittable)
        // Stop swipe inertia and position both sides of the section boundary inside the viewport.
        for _ in 0..<4 {
            grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30)).press(forDuration: 0.05,
                thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65)), withVelocity: .slow, thenHoldForDuration: 0.5)
            if lastA.isHittable && firstB.isHittable { break }
        }
        XCTAssertTrue(lastA.waitForExistence(timeout: 3))
        XCTAssertEqual(firstB.frame.minX, grid.frame.minX, accuracy: 1)
        XCTAssertGreaterThanOrEqual(firstB.frame.minY, lastA.frame.maxY + 5)
        let grouped = XCTAttachment(screenshot: app.screenshot()); grouped.name = "All packs start on separate rows"; grouped.lifetime = .keepAlways; add(grouped)
        let from = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.70, dy: 0.5))
        let short = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: short, withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(app.buttons["packTab.all"].isSelected, "Short drag must settle back to current page")
        XCTAssertFalse(app.staticTexts["keyboardCopyStatus"].exists)
    }

    @MainActor
    func testDirectOpenAndSystemKeyboardReturnUseSameContentGeometry() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "--keyboard-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-b").firstMatch.waitForExistence(timeout: 20))
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        app.textFields["keyboardPractice"].tap()
        try returnToStickerKeyboard(app)
        app.buttons["packTab.keyboard-ui-a"].tap()

        func checkGeometry(_ phase: String) {
            let surface = app.otherElements["keyboardSurface"].firstMatch
            let strip = app.scrollViews["keyboardPackStrip"]
            let grid = app.collectionViews["stickerGrid"]
            XCTAssertTrue(surface.waitForExistence(timeout: 5))
            XCTAssertTrue(grid.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(grid.frame.height, 180)
            print("Keyboard presentation \(phase): surface=\(surface.frame), strip=\(strip.frame), grid=\(grid.frame)")
            XCTAssertEqual(strip.frame.minY - surface.frame.minY, 4, accuracy: 1)
            XCTAssertEqual(grid.frame.maxY, surface.frame.maxY, accuracy: 1)
            XCTAssertTrue(app.buttons["packTab.keyboard-ui-a"].isSelected)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Keyboard presentation " + phase
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        checkGeometry("initial")
        for i in 0..<2 {
            let globe = app.buttons["Next keyboard"].firstMatch
            XCTAssertTrue(globe.exists)
            globe.tap()
            expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["keyboardManage"])
            waitForExpectations(timeout: 5)
            try returnToStickerKeyboard(app)
            checkGeometry("system return \(i)")
        }
        app.terminate()
        app.launch()
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        app.textFields["keyboardPractice"].tap()
        XCTAssertTrue(app.buttons["keyboardManage"].waitForExistence(timeout: 5))
        checkGeometry("direct reopen")
    }

    @MainActor
    private func returnToStickerKeyboard(_ app: XCUIApplication) throws {
        if app.buttons["keyboardManage"].waitForExistence(timeout: 1) { return }
        let globe = app.buttons["Next keyboard"].firstMatch
        XCTAssertTrue(globe.waitForExistence(timeout: 5))
        globe.press(forDuration: 0.8)
        // A short globe tap may toggle only the two most recent languages, so choose explicitly.
        let choice = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "StickerBridge")).firstMatch
        if choice.waitForExistence(timeout: 3) { choice.tap() }
        else {
            let label = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "StickerBridge")).firstMatch
            XCTAssertTrue(label.waitForExistence(timeout: 3)); label.tap()
        }
        XCTAssertTrue(app.buttons["keyboardManage"].waitForExistence(timeout: 5))
    }

}
