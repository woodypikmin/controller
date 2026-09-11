import XCTest

final class PikminPilotRunnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPilotCommand() throws {
        let env = ProcessInfo.processInfo.environment
        let command = env["PIKMIN_PILOT_COMMAND"] ?? "center"
        let app = XCUIApplication(bundleIdentifier: "com.nianticlabs.pikmin")

        // Never cold-launch the game in Stage 8. The user (or later the bot
        // bootstrap) leaves Pikmin Bloom alive; XCTest only re-activates the
        // existing process and dispatches coordinates.
        switch app.state {
        case .runningForeground, .runningBackground, .runningBackgroundSuspended:
            break
        default:
            XCTFail("Pikmin Bloom is not already running (state=\(app.state.rawValue)); refusing to relaunch")
            return
        }

        app.activate()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "Pikmin Bloom did not reach foreground after activate()"
        )

        if command == "activate" {
            // Stage 8 phase A: leave the target foreground so Pikmin Pilot's
            // background task can take a DVT screenshot of the real game.
            sleep(1)
            return
        }

        let x: Double
        let y: Double

        if command == "tap" {
            guard
                let sx = env["PIKMIN_PILOT_X"],
                let sy = env["PIKMIN_PILOT_Y"],
                let parsedX = Double(sx),
                let parsedY = Double(sy),
                parsedX >= 0, parsedX <= 1,
                parsedY >= 0, parsedY <= 1
            else {
                XCTFail("Invalid PIKMIN_PILOT_X/Y environment")
                return
            }
            x = parsedX
            y = parsedY
        } else {
            // Retains the Stage 7.8.5 proof button.
            x = 0.5
            y = 0.5
        }

        app.coordinate(
            withNormalizedOffset: CGVector(dx: x, dy: y)
        ).tap()

        XCTAssertEqual(
            app.state,
            .runningForeground,
            "Pikmin Bloom left foreground immediately after tap"
        )

        sleep(1)
    }
}
