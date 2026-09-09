
import Foundation
import Combine

@MainActor
final class Stage61Probe: ObservableObject {
    static let shared = Stage61Probe()

    @Published var status =
        "Not tested"

    @Published var isRunning =
        false

    @Published var rawJSON =
        ""

    func run() {
        guard !isRunning else {
            return
        }

        isRunning =
            true

        status =
            "Running local XCTest/testmanagerd capability probe..."

        Task {
            let result =
                XCTestCapabilityProbe
                    .run()

            let dictionary =
                result as NSDictionary

            rawJSON =
                prettyJSON(
                    dictionary
                )

            status =
                summarize(
                    dictionary
                )

            isRunning =
                false
        }
    }

    private func bool(
        _ dictionary: NSDictionary,
        _ key: String
    ) -> Bool {
        return (
            dictionary[
                key
            ]
            as?
            NSNumber
        )?
        .boolValue
        ?? false
    }

    private func dict(
        _ dictionary: NSDictionary,
        _ key: String
    ) -> NSDictionary {
        return (
            dictionary[
                key
            ]
            as?
            NSDictionary
        )
        ?? [:]
    }

    private func summarize(
        _ result: NSDictionary
    ) -> String {
        let xctest =
            dict(
                result,
                "XCTestFramework"
            )

        let core =
            dict(
                result,
                "XCTestCore"
            )

        let automation =
            dict(
                result,
                "XCTAutomationSupport"
            )

        let bootstrap =
            dict(
                result,
                "XCTTargetBootstrap"
            )

        let classes =
            dict(
                result,
                "classes"
            )

        let services =
            dict(
                result,
                "machServices"
            )

        func classPresent(
            _ name: String
        ) -> Bool {
            let item =
                classes[
                    name
                ]
                as?
                NSDictionary
                ?? [:]

            return bool(
                item,
                "present"
            )
        }

        func serviceLine(
            _ name: String
        ) -> String {
            let item =
                services[
                    name
                ]
                as?
                NSDictionary
                ?? [:]

            let ok =
                bool(
                    item,
                    "success"
                )

            let code =
                (
                    item[
                        "returnCode"
                    ]
                    as?
                    NSNumber
                )?
                .intValue
                ?? -9999

            let desc =
                item[
                    "description"
                ]
                as?
                String
                ?? ""

            return "\(ok ? "YES" : "NO") | rc=\(code) | \(desc)"
        }

        let frameworkLoaded =
            bool(
                xctest,
                "dlopenSuccess"
            )

        let testmanagerVisible =
            [
                "com.apple.testmanagerd",
                "com.apple.testmanagerd.control",
                "com.apple.testmanagerd.runner",
                "com.apple.dt.testmanagerd.remote"
            ]
            .contains {
                name in

                let item =
                    services[
                        name
                    ]
                    as?
                    NSDictionary
                    ?? [:]

                return bool(
                    item,
                    "success"
                )
            }

        var verdict =
            ""

        if frameworkLoaded &&
            classPresent(
                "XCUIApplication"
            ) &&
            testmanagerVisible {
            verdict =
                """
                RESULT: VERY INTERESTING
                XCTest/UIAutomation runtime loaded AND at least one testmanagerd service is visible.
                Next experiment can attempt a real XCTest control-session handshake.
                """
        }
        else if frameworkLoaded &&
            classPresent(
                "XCUIApplication"
            ) {
            verdict =
                """
                RESULT: PARTIAL
                XCTest/UIAutomation runtime is visible, but testmanagerd is not directly reachable from this normal app sandbox.
                Next experiment should focus on whether a runner process can host the control session instead.
                """
        }
        else {
            verdict =
                """
                RESULT: NORMAL APP CONTEXT IS MISSING XCODE TEST RUNTIME
                The Controller process cannot directly see/load enough of XCTest to become a UI-test host by itself.
                This points toward moving the bot into the signed .xctrunner rather than making Controller create the session.
                """
        }

        return """
        STAGE 6.1 PROBE COMPLETE

        XCTest.framework dlopen: \(frameworkLoaded ? "YES" : "NO")
        XCTestCore dlopen: \(bool(core, "dlopenSuccess") ? "YES" : "NO")
        XCTAutomationSupport: \(bool(automation, "dlopenSuccess") ? "YES" : "NO")
        XCTTargetBootstrap: \(bool(bootstrap, "dlopenSuccess") ? "YES" : "NO")

        XCTestCase: \(classPresent("XCTestCase") ? "YES" : "NO")
        XCTestDriver: \(classPresent("XCTestDriver") ? "YES" : "NO")
        XCTestConfiguration: \(classPresent("XCTestConfiguration") ? "YES" : "NO")
        XCUIApplication: \(classPresent("XCUIApplication") ? "YES" : "NO")
        XCUIDevice: \(classPresent("XCUIDevice") ? "YES" : "NO")
        XCTRunnerDaemonSession: \(classPresent("XCTRunnerDaemonSession") ? "YES" : "NO")

        testmanagerd:
        \(serviceLine("com.apple.testmanagerd"))

        testmanagerd.control:
        \(serviceLine("com.apple.testmanagerd.control"))

        testmanagerd.runner:
        \(serviceLine("com.apple.testmanagerd.runner"))

        dt.testmanagerd.remote:
        \(serviceLine("com.apple.dt.testmanagerd.remote"))

        \(verdict)
        """
    }

    private func prettyJSON(
        _ dictionary: NSDictionary
    ) -> String {
        guard JSONSerialization
            .isValidJSONObject(
                dictionary
            ),
              let data =
            try?
            JSONSerialization.data(
                withJSONObject:
                    dictionary,
                options: [
                    .prettyPrinted,
                    .sortedKeys
                ]
            )
        else {
            return
                dictionary.description
        }

        return
            String(
                data: data,
                encoding:
                    .utf8
            )
            ?? dictionary.description
    }
}
