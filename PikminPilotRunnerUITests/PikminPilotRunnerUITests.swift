import XCTest
import Darwin

final class PikminPilotRunnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPilotCommand() throws {
        let env = ProcessInfo.processInfo.environment
        let command = env["PIKMIN_PILOT_COMMAND"] ?? "center"
        let app = XCUIApplication(bundleIdentifier: "com.nianticlabs.pikmin")

        // Stage 8.x never cold-launches Pikmin Bloom. The game must already be
        // alive; commands only re-activate the existing process and inject UI
        // actions. This preserves the user's current game state.
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
            sleep(1)
            return
        }

        if command == "select12" {
            // Exact Stage 5 fixed 12-pink-Pikmin grid, normalized from the
            // proven 868x1836 reference screen. Keep this as one XCTest plan
            // so 12 selections do not require 12 host-side DTX sessions.
            let points: [(Double, Double)] = [
                (112.0 / 868.0,  950.0 / 1836.0),
                (272.0 / 868.0,  950.0 / 1836.0),
                (427.0 / 868.0,  950.0 / 1836.0),
                (583.0 / 868.0,  950.0 / 1836.0),
                (737.0 / 868.0,  950.0 / 1836.0),
                (112.0 / 868.0, 1215.0 / 1836.0),
                (272.0 / 868.0, 1215.0 / 1836.0),
                (427.0 / 868.0, 1215.0 / 1836.0),
                (583.0 / 868.0, 1215.0 / 1836.0),
                (737.0 / 868.0, 1215.0 / 1836.0),
                (112.0 / 868.0, 1470.0 / 1836.0),
                (272.0 / 868.0, 1470.0 / 1836.0),
            ]

            for (x, y) in points {
                app.coordinate(
                    withNormalizedOffset: CGVector(dx: x, dy: y)
                ).tap()
                usleep(100_000)
            }

            XCTAssertEqual(app.state, .runningForeground)
            usleep(250_000)
            return
        }

        guard
            let sx = env["PIKMIN_PILOT_X"],
            let sy = env["PIKMIN_PILOT_Y"],
            let x = Double(sx),
            let y = Double(sy),
            x >= 0, x <= 1,
            y >= 0, y <= 1
        else {
            XCTFail("Invalid PIKMIN_PILOT_X/Y environment")
            return
        }

        if command == "swipe" {
            guard
                let sx2 = env["PIKMIN_PILOT_X2"],
                let sy2 = env["PIKMIN_PILOT_Y2"],
                let sd = env["PIKMIN_PILOT_DURATION"],
                let x2 = Double(sx2),
                let y2 = Double(sy2),
                let duration = Double(sd),
                x2 >= 0, x2 <= 1,
                y2 >= 0, y2 <= 1,
                duration >= 0, duration <= 5
            else {
                XCTFail("Invalid swipe environment")
                return
            }

            let start = app.coordinate(
                withNormalizedOffset: CGVector(dx: x, dy: y)
            )
            let end = app.coordinate(
                withNormalizedOffset: CGVector(dx: x2, dy: y2)
            )

            // XCTest's basic drag API treats forDuration as the initial press
            // hold, not the whole swipe duration. Keep the hold short so the
            // game sees a swipe instead of a long-press; retain duration only
            // as a small settling hint after the drag.
            start.press(forDuration: 0.05, thenDragTo: end)
            XCTAssertEqual(app.state, .runningForeground)
            usleep(200_000)
            return
        }

        let tapX: Double
        let tapY: Double
        if command == "tap" {
            tapX = x
            tapY = y
        } else {
            // Retains the Stage 7.8.5 proof command.
            tapX = 0.5
            tapY = 0.5
        }

        app.coordinate(
            withNormalizedOffset: CGVector(dx: tapX, dy: tapY)
        ).tap()

        XCTAssertEqual(
            app.state,
            .runningForeground,
            "Pikmin Bloom left foreground immediately after tap"
        )

        usleep(250_000)
    }
}
