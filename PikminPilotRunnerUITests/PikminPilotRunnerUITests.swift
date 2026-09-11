import XCTest

final class PikminPilotRunnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapPikminCenter() throws {
        let app = XCUIApplication(bundleIdentifier: "com.nianticlabs.pikmin")
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Pikmin Bloom did not reach foreground"
        )

        sleep(2)

        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()

        sleep(2)
    }
}
