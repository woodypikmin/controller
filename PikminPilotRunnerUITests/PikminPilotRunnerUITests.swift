import XCTest

final class PikminPilotRunnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTapPikminCenter() throws {
        let app = XCUIApplication(bundleIdentifier: "com.nianticlabs.pikmin")

        // Stage 7.8.5 proof mode: the user prepares Pikmin Bloom first and then
        // switches to Pikmin Pilot. We deliberately refuse to call launch(),
        // because XCUIApplication.launch() terminates/relaunches the target and
        // hides whether the center tap itself actually worked.
        let initialState = app.state
        switch initialState {
        case .runningForeground, .runningBackground, .runningBackgroundSuspended:
            break
        default:
            XCTFail("Pikmin Bloom is not already running (state=\(initialState.rawValue)). Refusing to relaunch it during the center-tap proof test.")
            return
        }

        // Bring the existing Pikmin process to the foreground without a normal
        // launch/restart cycle.
        app.activate()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Pikmin Bloom did not reach foreground after activate()"
        )

        // Make the tap visually distinguishable from foreground activation:
        // Pikmin sits untouched for four seconds, then receives exactly one
        // normalized center tap.
        sleep(4)

        app.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()

        // If tap() cannot be dispatched XCTest fails here; reaching the end of
        // the test plus a completed test plan is our transport-level proof.
        XCTAssertEqual(
            app.state,
            .runningForeground,
            "Pikmin Bloom left the foreground immediately after center tap"
        )

        sleep(2)
    }
}
