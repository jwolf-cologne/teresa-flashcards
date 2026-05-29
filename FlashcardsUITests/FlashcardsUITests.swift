//
//  FlashcardsUITests.swift
//  FlashcardsUITests
//
//  Created by Jens Wolf on 25.05.26.
//

import XCTest

final class FlashcardsUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testAIPaywallDoesNotShowLoadingPricePlaceholder() throws {
        let app = XCUIApplication()
        app.launchArguments.append("UITEST_SKIP_INTRO")
        app.launchArguments.append("UITEST_FORCE_AI_UNLOCK_BUTTON")
        app.launch()

        app.buttons["settingsButton"].tap()

        let unlockButton = app.buttons["unlockAIButton"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 5))
        unlockButton.tap()

        let paywallTitles = [
            app.staticTexts["KI-Funktionen freischalten"],
            app.staticTexts["Unlock AI Features"]
        ]
        XCTAssertTrue(paywallTitles.contains { $0.waitForExistence(timeout: 3) })
        XCTAssertFalse(app.buttons.containing(NSPredicate(format: "label CONTAINS[c] %@", "Loading price")).element.exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
