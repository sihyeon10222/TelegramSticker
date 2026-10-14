import XCTest

final class TelegramStickerUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    private func configuredApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        return app
    }

    @MainActor
    func testMainScreensAccessibilityDescriptionsTraitsAndTapTargets() throws {
        let app = configuredApp()
        app.launch()
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        XCTAssertTrue(app.buttons["keyboardSetup"].waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .hitRegion])
    }

    @MainActor
    func testOnboardingCanBeSkippedAndDoesNotRepeatAfterRestart() {
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "NO"]
        app.launch()
        XCTAssertTrue(app.navigationBars["StickerBridge 시작"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "First launch onboarding"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["skipOnboarding"].tap()
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["skipOnboarding"].exists)
    }

    @MainActor
    func testMultipleLinkFieldsAndBatchInstall() {
        let app = configuredApp()
        app.launchArguments += ["--import-ui-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        app.buttons["addPack"].tap()
        let first = app.textFields["packLink"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap(); first.typeText("https://t.me/addstickers/ui_fixture")
        app.buttons["addPackLink"].tap()
        XCTAssertEqual(app.textFields.count, 2)
        let second = app.textFields.element(boundBy: 1)
        second.tap(); second.typeText("https://t.me/addstickers/ui_dense_fixture")
        app.buttons["installBatch"].tap()
        let completion = NSPredicate(format: "label CONTAINS %@", "일괄 설치를 마쳤어요")
        expectation(for: completion, evaluatedWith: app.staticTexts["importMessage"])
        waitForExpectations(timeout: 40)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Multiple Telegram links installed"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["closeImport"].tap()
        let fixtureRow = app.descendants(matching: .any).matching(identifier: "pack.telegram-ui_fixture").firstMatch
        let listFrame = app.collectionViews.firstMatch.frame
        let rowHeight = fixtureRow.frame.height
        for cycle in 0..<3 {
            app.buttons["editPacks"].tap()
            XCTAssertEqual(app.buttons["editPacks"].label, "완료")
            XCTAssertEqual(app.collectionViews.firstMatch.frame, listFrame)
            XCTAssertEqual(fixtureRow.frame.height, rowHeight, accuracy: 1)
            fixtureRow.tap()
            XCTAssertTrue(app.buttons["optimizeSelectedPacks"].isEnabled)
            if cycle == 0 {
                let editing = XCTAttachment(screenshot: app.screenshot())
                editing.name = "Stable editing layout"; editing.lifetime = .keepAlways; add(editing)
            }
            app.buttons["editPacks"].tap()
            XCTAssertEqual(app.buttons["editPacks"].label, "편집")
            XCTAssertFalse(app.buttons["optimizeSelectedPacks"].exists)
            XCTAssertEqual(app.collectionViews.firstMatch.frame, listFrame)
            XCTAssertEqual(fixtureRow.frame.height, rowHeight, accuracy: 1)
        }
        app.buttons["editPacks"].tap()
        XCTAssertFalse(app.buttons["optimizeSelectedPacks"].isEnabled)
        app.descendants(matching: .any).matching(identifier: "pack.telegram-ui_fixture").firstMatch.tap()
        app.descendants(matching: .any).matching(identifier: "pack.telegram-ui_dense_fixture").firstMatch.tap()
        XCTAssertTrue(app.buttons["optimizeSelectedPacks"].isEnabled)
        app.buttons["optimizeSelectedPacks"].tap()
        XCTAssertTrue(app.buttons["prepareOptimization"].waitForExistence(timeout: 5))
        app.buttons["prepareOptimization"].tap()
        XCTAssertTrue(app.staticTexts["optimizationSavings"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "optimizationComparison").firstMatch.waitForExistence(timeout: 5))
        let zoom = app.sliders["optimizationZoom"]
        XCTAssertTrue(zoom.exists)
        zoom.adjust(toNormalizedSliderPosition: 0.5)
        let magnification = Double((zoom.value as? String ?? "").replacingOccurrences(of: "배", with: "")) ?? 0
        XCTAssertEqual(magnification, 2, accuracy: 0.2)
        let list = app.scrollViews["optimizationList"]
        list.swipeUp()
        list.swipeUp()
        XCTAssertTrue(zoom.isHittable)
        XCTAssertTrue(app.buttons["applyOptimization"].isHittable)
        XCTAssertFalse(app.buttons["다음"].exists)
        let comparison = XCTAttachment(screenshot: app.screenshot())
        comparison.name = "Scrolling comparisons with shared glass zoom"; comparison.lifetime = .keepAlways; add(comparison)
        if app.buttons["applyOptimization"].isEnabled {
            app.buttons["applyOptimization"].tap()
            let result = app.staticTexts["optimizationResult"]
            // The result is at the end of the scrollable comparison list.
            for _ in 0..<35 {
                if result.isHittable { break }
                list.swipeUp()
            }
            XCTAssertTrue(result.waitForExistence(timeout: 40))
            XCTAssertTrue(result.label.contains("개 팩 반영"))
        }
        app.buttons["closeOptimization"].tap()
        app.buttons["editPacks"].tap()
        XCTAssertFalse(app.buttons["optimizeSelectedPacks"].exists)
        let completed = XCTAttachment(screenshot: app.screenshot())
        completed.name = "Library after ending edit mode"; completed.lifetime = .keepAlways; add(completed)
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        let optimize = app.buttons["optimizeStorage"]
        if !optimize.isHittable { app.swipeUp() }
        XCTAssertTrue(optimize.waitForExistence(timeout: 5))
        optimize.tap()
        XCTAssertTrue(app.buttons["prepareOptimization"].waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testLocalImportPreviewInstallAndDelete() {
        let app = configuredApp()
        app.launchArguments += ["--import-ui-fixture"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "pack.telegram-ui_fixture").firstMatch
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        if row.exists {
            row.tap()
            app.buttons["deletePack"].tap()
            app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "팩 삭제", "deletePack")).firstMatch.tap()
        }
        app.buttons["addPack"].tap()

        let link = app.textFields["packLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()
        link.typeText("https://t.me/addstickers/ui_fixture\n")
        XCTAssertTrue(app.staticTexts["전체 2개 · 설치 대상 2개"].waitForExistence(timeout: 10))
        let preview = XCTAttachment(screenshot: app.screenshot())
        preview.name = "Local Telegram import preview"; preview.lifetime = .keepAlways; add(preview)
        app.buttons["installRemotePack"].tap()
        let success = NSPredicate(format: "label CONTAINS %@", "설치했어요")
        expectation(for: success, evaluatedWith: app.staticTexts["importMessage"])
        waitForExpectations(timeout: 15)
        app.buttons["closeImport"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "installedCopy.telegram-ui_fixture.")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["deletePack"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "팩 삭제", "deletePack")).firstMatch.tap()
    }

    @MainActor
    func testPartialImportAppearsAndRetriesMissingStickerAfterRestart() {
        let app = configuredApp()
        app.launchArguments += ["--import-ui-fixture", "--partial-import-ui-fixture"]
        app.launch()
        let packID = "telegram-ui_partial_fixture"
        let row = app.descendants(matching: .any).matching(identifier: "pack." + packID).firstMatch
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        if row.exists {
            row.tap(); app.buttons["deletePack"].tap()
            app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "팩 삭제", "deletePack")).firstMatch.tap()
        }
        app.buttons["addPack"].tap()
        let link = app.textFields["packLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap(); link.typeText("https://t.me/addstickers/ui_partial_fixture\n")
        let install = app.buttons["installRemotePack"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: install)
        waitForExpectations(timeout: 10)
        install.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "1개를 설치"), evaluatedWith: app.staticTexts["importMessage"])
        waitForExpectations(timeout: 15)
        app.buttons["closeImport"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["partial." + packID].exists)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--partial-import-ui-fixture" }
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let copy = app.buttons["installedCopy." + packID + "." + String(repeating: "a", count: 64)]
        XCTAssertTrue(copy.waitForExistence(timeout: 5)); copy.tap()
        XCTAssertFalse(app.staticTexts["installedCopyStatus"].label.contains("복사됨"))
        app.buttons["previewCopy"].tap()
        XCTAssertTrue(app.staticTexts["installedCopyStatus"].label.contains("복사됨"))
        app.buttons["retryMissingStickers"].tap()
        let ready = install.waitForExistence(timeout: 10)
        let retryScreen = XCTAttachment(screenshot: app.screenshot())
        retryScreen.name = "Retry partially installed pack"; retryScreen.lifetime = .keepAlways; add(retryScreen)
        XCTAssertTrue(ready)
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: install)
        waitForExpectations(timeout: 10)
        install.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "2개를 설치"), evaluatedWith: app.staticTexts["importMessage"])
        waitForExpectations(timeout: 15)
        app.buttons["closeImport"].tap()
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["retryMissingStickers"].exists)
        XCTAssertTrue(app.buttons["installedCopy." + packID + "." + String(repeating: "b", count: 64)].exists)
        app.buttons["deletePack"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "팩 삭제", "deletePack")).firstMatch.tap()
    }

    @MainActor
    func testDensePackUsesCompactTilesAndKeepsSharingAvailable() {
        let app = configuredApp()
        app.launchArguments += ["--import-ui-fixture"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "pack.telegram-ui_dense_fixture").firstMatch
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        if row.exists {
            row.tap(); app.buttons["deletePack"].tap()
            app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "팩 삭제", "deletePack")).firstMatch.tap()
        }
        app.buttons["addPack"].tap()
        let link = app.textFields["packLink"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap(); link.typeText("https://t.me/addstickers/ui_dense_fixture\n")
        let install = app.buttons["installRemotePack"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: install)
        waitForExpectations(timeout: 10); install.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "30개를 설치"), evaluatedWith: app.staticTexts["importMessage"])
        waitForExpectations(timeout: 15)
        app.buttons["closeImport"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let library = XCTAttachment(screenshot: app.screenshot()); library.name = "Compact pack library"; library.lifetime = .keepAlways; add(library)
        row.tap()
        let copy = app.buttons["installedCopy.telegram-ui_dense_fixture." + String(format: "%064x", 1)]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        let grid = XCTAttachment(screenshot: app.screenshot()); grid.name = "Compact thirty sticker grid"; grid.lifetime = .keepAlways; add(grid)
        // Normal-size UI run: a sticker no longer occupies a tall action card.
        XCTAssertLessThan(copy.frame.height, 100)
        copy.press(forDuration: 1)
        XCTAssertTrue(app.buttons["share.telegram-ui_dense_fixture." + String(format: "%064x", 1)].waitForExistence(timeout: 3))
        app.navigationBars.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["deletePack"].tap()
        app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "팩 삭제", "deletePack")).firstMatch.tap()
    }

    @MainActor
    func testSettingsHaveNoSampleCopyOrPrivacySectionsAndPlusOpensImportDirectly() {
        let app = configuredApp()
        app.launch()
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        app.buttons["addPack"].tap()
        XCTAssertTrue(app.textFields["packLink"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["install.basics"].exists)
        XCTAssertFalse(app.buttons["install.animations"].exists)
        app.buttons["closeImport"].tap()
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        XCTAssertTrue(app.buttons["keyboardSetup"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["copy.sample-smile"].exists)
        XCTAssertFalse(app.staticTexts["복사 연습"].exists)
        XCTAssertFalse(app.staticTexts["개인정보"].exists)
        app.buttons["keyboardSetup"].tap()
        XCTAssertTrue(app.navigationBars["키보드 설정"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["1. 키보드 추가"].exists)
    }

    @MainActor
    func testLandscapeSettingsRemainUsable() {
        let app = configuredApp()
        app.launch()
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        let button = app.buttons["keyboardSetup"]
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
        XCTAssertTrue(app.navigationBars["키보드 설정"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testInstalledPackCopyShareAndPersist() {
        let app = configuredApp()
        app.launchArguments += ["--keyboard-ui-fixture"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "pack.keyboard-ui-a").firstMatch
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let copy = app.buttons["installedCopy.keyboard-ui-a.item-1"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        let image = app.images["previewImage"]
        let previewCopy = app.buttons["previewCopy"]
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertTrue(previewCopy.waitForExistence(timeout: 5))
        expectation(for: NSPredicate { _, _ in
            image.frame.minY >= app.navigationBars.firstMatch.frame.maxY &&
            image.frame.maxY + 8 <= previewCopy.frame.minY &&
            image.frame.minX >= app.frame.minX + 16 &&
            image.frame.maxX <= app.frame.maxX - 16
        }, evaluatedWith: image)
        waitForExpectations(timeout: 5)
        app.buttons["previewClose"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: image)
        waitForExpectations(timeout: 5)
        copy.tap()
        XCTAssertTrue(previewCopy.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["installedCopyStatus"].label.contains("복사됨"))
        app.buttons["previewCopy"].tap()
        XCTAssertTrue(app.staticTexts["installedCopyStatus"].label.contains("복사됨"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Installed shared local pack"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        copy.press(forDuration: 1)
        app.buttons["share.keyboard-ui-a.item-1"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.collectionViews["activityCollectionView"].waitForExistence(timeout: 15))
        let shareScreenshot = XCTAttachment(screenshot: app.screenshot())
        shareScreenshot.name = "PNG share sheet"
        shareScreenshot.lifetime = .keepAlways
        add(shareScreenshot)
        app.terminate()
        app.launch()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
    }
    @MainActor
    func testPackUpdateAndCacheClearKeepInstalledLibrary() {
        let app = configuredApp()
        app.launchArguments += ["--import-ui-fixture"]
        app.launch()
        let row = app.descendants(matching: .any).matching(identifier: "pack.telegram-ui_fixture").firstMatch
        XCTAssertTrue(app.buttons["addPack"].waitForExistence(timeout: 10))
        if !row.exists {
            app.buttons["addPack"].tap()
            let link = app.textFields["packLink"]
            XCTAssertTrue(link.waitForExistence(timeout: 5)); link.tap(); link.typeText("https://t.me/addstickers/ui_fixture\n")
            let install = app.buttons["installRemotePack"]
            XCTAssertTrue(install.waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: install); waitForExpectations(timeout: 10)
            install.tap()
            expectation(for: NSPredicate(format: "label CONTAINS %@", "설치했어요"), evaluatedWith: app.staticTexts["importMessage"]); waitForExpectations(timeout: 15)
            app.buttons["closeImport"].tap()
        }
        let update = app.buttons["update.telegram-ui_fixture"]
        XCTAssertTrue(update.waitForExistence(timeout: 5)); update.tap()
        XCTAssertTrue(app.navigationBars["스티커 팩 업데이트"].waitForExistence(timeout: 5))
        let install = app.buttons["installRemotePack"]
        XCTAssertTrue(install.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: install); waitForExpectations(timeout: 10)
        XCTAssertEqual(install.label, "팩 업데이트"); install.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "설치했어요"), evaluatedWith: app.staticTexts["importMessage"]); waitForExpectations(timeout: 15)
        app.buttons["closeImport"].tap()
        app.descendants(matching: .any).matching(identifier: "설정").firstMatch.tap()
        let clear = app.buttons["clearCache"]
        for _ in 0..<3 where !clear.isHittable { app.swipeUp() }
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: clear); waitForExpectations(timeout: 5)
        clear.tap()
        XCTAssertTrue(app.staticTexts["캐시를 삭제했어요. 설치한 팩과 연결 설정은 유지했어요."].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "내 스티커 팩").firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }


}
