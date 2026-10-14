import XCTest
import UIKit

/// Read-only comparison on an existing pack. Never applies optimization or reads credentials/chat.
final class PhysicalBackgroundWorkTests: XCTestCase {
    @MainActor
    func testComparisonContinuesAfterLeavingApp() throws {
        guard ProcessInfo.processInfo.environment["STICKERBRIDGE_BACKGROUND_VALIDATION"] == "1" else { throw XCTSkip("실기기 백그라운드 검사 전용") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        XCTAssertTrue(app.buttons["editPacks"].waitForExistence(timeout: 15))
        app.buttons["editPacks"].tap()
        let preferred = ["pack.telegram-dccon_real_1762389696919_by_tg_sticker_factory_bot", "pack.telegram-mellborov"]
        guard let row = preferred.map({ app.descendants(matching: .any).matching(identifier: $0).firstMatch }).first(where: { $0.exists }) else {
            throw XCTSkip("검사할 기존 Telegram 팩이 없어요. 설치 데이터는 변경하지 않았어요.")
        }
        if !row.isHittable { app.swipeUp() }
        row.tap()
        app.buttons["optimizeSelectedPacks"].tap()
        XCTAssertTrue(app.buttons["prepareOptimization"].waitForExistence(timeout: 10))
        app.buttons["prepareOptimization"].tap()
        XCUIDevice.shared.press(.home)
        // The operation must continue while foreground belongs to SpringBoard.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        let screenshot = springboard.screenshot()
        if let image = UIImage(data: screenshot.pngRepresentation)?.cgImage,
           let cropped = image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: min(300, image.height))) {
            let island = XCTAttachment(image: UIImage(cgImage: cropped))
            island.name = "Dynamic Island while background comparison runs"; island.lifetime = .keepAlways; add(island)
        }
        Thread.sleep(forTimeInterval: 5)
        app.activate()
        XCTAssertTrue(app.staticTexts["optimizationSavings"].waitForExistence(timeout: 180))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "허용하지 않아요")).firstMatch.exists)
        let returned = XCTAttachment(screenshot: app.screenshot())
        returned.name = "Comparison returned from background"; returned.lifetime = .keepAlways; add(returned)
        app.buttons["closeOptimization"].tap()
        app.buttons["editPacks"].tap()
    }
}
