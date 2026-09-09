
import Foundation
import UIKit

@MainActor
final class WDASelfStartProbe: ObservableObject {
    static let shared = WDASelfStartProbe()

    @Published var status =
        "Not tested"

    @Published var isRunning =
        false

    @Published var lastSuccess =
        false

    private var bgTask:
        UIBackgroundTaskIdentifier =
        .invalid

    func checkLocalWDA() {
        guard !isRunning else {
            return
        }

        isRunning = true

        Task {
            let alive =
                await quickStatusProbe()

            if alive {
                status =
                    """
                    WDA IS ALREADY RUNNING
                    localhost:8100 answers.

                    This is NOT a valid self-start test yet.
                    Stop the current WDA first, then run SELF-START TEST.
                    """
            }
            else {
                status =
                    """
                    WDA IS DOWN
                    localhost:8100 does not answer.

                    Good — SELF-START TEST can now prove whether iPhone can launch it by itself.
                    """
            }

            lastSuccess =
                alive

            isRunning =
                false
        }
    }

    func selfStartTest(
        bundleId: String
    ) {
        guard !isRunning else {
            return
        }

        let clean =
            bundleId
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )

        guard !clean.isEmpty else {
            status =
                "Enter the WDA Runner bundle id."

            return
        }

        isRunning =
            true

        lastSuccess =
            false

        status =
            "Checking localhost:8100 before test..."

        startBackgroundTask()

        Task {
            // First make sure WDA is actually down.
            if await quickStatusProbe() {
                status =
                    """
                    TEST NOT STARTED:
                    WDA is already answering on localhost:8100.

                    We need WDA DOWN first, otherwise this cannot prove self-start.
                    """

                finish()
                return
            }

            var installKnown:
                ObjCBool =
                false

            let installed =
                PrivateAppLauncher
                .isApplicationInstalled(
                    clean,
                    known:
                        &installKnown
                )

            if installKnown.boolValue {
                status =
                    """
                    WDA down.
                    Private LaunchServices can inspect installed apps.
                    WDA bundle installed=\(installed)
                    bundle=\(clean)

                    Sending local launch request...
                    """
            }
            else {
                status =
                    """
                    WDA down.
                    iOS did not expose applicationIsInstalled to this app.
                    Will still try direct local launch.

                    bundle=\(clean)
                    """
            }

            let requested =
                PrivateAppLauncher
                .openApplication(
                    withBundleIdentifier:
                        clean
                )

            if !requested {
                status +=
                    """

                    RESULT:
                    Private launch API refused/unavailable.
                    WDA was NOT started.
                    """

                finish()
                return
            }

            status +=
                """

                Launch request submitted.
                Waiting up to ~20 seconds for localhost:8100...
                """

            // Launching another app backgrounds Controller.
            // beginBackgroundTask keeps this diagnostic alive long enough
            // to watch whether WDA's HTTP server appears.
            for second in 1...40 {
                if await quickStatusProbe() {
                    lastSuccess =
                        true

                    status =
                        """
                        SUCCESS — STAGE 6A PASSED

                        WDA started from the iPhone itself.
                        localhost:8100 is answering.

                        bundle:
                        \(clean)

                        Windows was not used to start this WDA process.
                        """

                    finish()
                    return
                }

                if second % 4 == 0 {
                    status =
                        """
                        Launch request accepted.
                        Waiting for WDA HTTP server...
                        elapsed≈\(second / 2)s
                        """
                }

                try? await
                    Task.sleep(
                        nanoseconds:
                            500_000_000
                    )
            }

            status =
                """
                STAGE 6A FAILED

                The WDA Runner launch request was submitted,
                but localhost:8100 never came up.

                This strongly suggests that merely opening the installed
                .xctrunner app is not enough to start its XCTest/WDA server.

                bundle:
                \(clean)
                """

            finish()
        }
    }

    // --------------------------------------------------------
    // Deliberately tiny /status probe.
    //
    // Do not use WDAClient.status() here because Stage 4.3 retries are
    // intentionally long. Stage 6 needs fast "up/down" polling.
    // --------------------------------------------------------

    private func quickStatusProbe()
        async -> Bool {
        guard let url =
            URL(
                string:
                    "http://127.0.0.1:8100/status"
            )
        else {
            return false
        }

        var req =
            URLRequest(
                url: url
            )

        req.httpMethod =
            "GET"

        req.timeoutInterval =
            0.9

        req.cachePolicy =
            .reloadIgnoringLocalCacheData

        let config =
            URLSessionConfiguration
                .ephemeral

        config.timeoutIntervalForRequest =
            0.9

        config.timeoutIntervalForResource =
            1.1

        let session =
            URLSession(
                configuration:
                    config
            )

        do {
            let (
                _,
                response
            ) =
                try await
                session.data(
                    for: req
                )

            guard let http =
                response
                as?
                HTTPURLResponse
            else {
                return false
            }

            return (
                200...299
            )
            .contains(
                http.statusCode
            )
        }
        catch {
            return false
        }
    }

    private func startBackgroundTask() {
        finishBackgroundTask()

        bgTask =
            UIApplication.shared
            .beginBackgroundTask(
                withName:
                    "Stage6-WDA-SelfStart"
            ) {
                [weak self] in

                self?.status =
                    """
                    TEST INTERRUPTED:
                    iOS expired Controller's diagnostic background time.
                    """

                self?
                    .finish()
            }
    }

    private func finish() {
        isRunning =
            false

        finishBackgroundTask()
    }

    private func finishBackgroundTask() {
        if bgTask !=
            .invalid {
            UIApplication.shared
                .endBackgroundTask(
                    bgTask
                )

            bgTask =
                .invalid
        }
    }
}
