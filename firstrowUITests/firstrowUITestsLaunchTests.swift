//
//  firstrowUITestsLaunchTests.swift
//  firstRowUITests
//
//  Created by Jackson Dam on 19/12/2024.
//

import XCTest

final class firstRowUITestsLaunchTests: XCTestCase {
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() {
        let app = XCUIApplication()
        app.launchEnvironment["FIRSTROW_HARNESS"] = "1"
        defer { app.terminate() }
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        // First Row draws its interface with Core Animation. Capture the display
        // directly rather than asking accessibility to snapshot the layer hierarchy.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
