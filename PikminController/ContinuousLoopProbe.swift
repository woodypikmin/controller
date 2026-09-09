
import UIKit

@MainActor
final class ContinuousLoopProbe: ObservableObject {
    static let shared = ContinuousLoopProbe()

    @Published var status = "Not started"
    @Published var isRunning = false

    private var bgTask:
        UIBackgroundTaskIdentifier =
        .invalid

    private var cancelled =
        false

    private var completedDispatches =
        0

    private let pinkGrid: [
        (Double, Double)
    ] = [
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

    static var finalScreenshotURL: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent(
            "stage5_final.png"
        )
    }

    func startLoop() {
        guard !isRunning else {
            return
        }

        cancelled = false
        isRunning = true
        completedDispatches = 0

        UserDefaults.standard.set(
            "",
            forKey:
                "stage5Status"
        )

        persist(
            "START LOOP"
        )

        startFreshBackgroundTask(
            label:
                "initial"
        )

        Task {
            do {
                do {
                    try await
                        WDAClient.shared
                        .launchPikmin()
                }
                catch {
                    // Foreground transition can interrupt HTTP response.
                }

                try await sleep(
                    2.8
                )

                while !cancelled {
                    let round =
                        completedDispatches + 1

                    persist(
                        "ROUND \(round): scanning Expedition list"
                    )

                    guard let choice =
                        try await
                        findAvailableFruit(
                            round:
                                round
                        )
                    else {
                        let final =
                            try? await
                            WDAClient.shared
                            .screenshot()

                        if let final,
                           let png =
                            final.pngData() {
                            try? png.write(
                                to:
                                    Self.finalScreenshotURL,
                                options:
                                    .atomic
                            )
                        }

                        persist(
                            """
                            FINISHED
                            No safe AVAILABLE fruit found.
                            completed=\(completedDispatches)
                            """
                        )

                        isRunning = false
                        finishBackgroundTask()
                        return
                    }

                    try await
                        runOneDispatch(
                            round:
                                round,
                            fruit:
                                choice.fruit,
                            listImage:
                                choice.image
                        )

                    completedDispatches += 1

                    persist(
                        "ROUND \(round) COMPLETED. total=\(completedDispatches)"
                    )

                    if cancelled {
                        break
                    }

                    persist(
                        "Waiting for Expedition list..."
                    )

                    guard try await
                        waitForExpeditionList()
                    else {
                        throw
                            WDAError.server(
                                "After closing carrying X, Expedition list did not return."
                            )
                    }

                    try await sleep(
                        0.35
                    )

                    if cancelled {
                        break
                    }

                    // Refresh Controller foreground very briefly,
                    // renew background execution, then go back to Pikmin.
                    persist(
                        "Refreshing Controller background window..."
                    )

                    try await
                        foregroundRefresh()

                    persist(
                        "Refresh OK. Starting next round."
                    )

                    try await sleep(
                        0.65
                    )

                    // GET-only WDA health check before next loop.
                    try await
                        WDAClient.shared
                        .prepareForNextDispatch()
                }

                persist(
                    "STOPPED BY USER. completed=\(completedDispatches)"
                )

                isRunning = false
                finishBackgroundTask()
            }
            catch {
                persist(
                    "FAILED after \(completedDispatches) completed: \(error.localizedDescription)"
                )

                isRunning = false
                finishBackgroundTask()
            }
        }
    }

    func stopLoop() {
        cancelled = true

        persist(
            "STOP requested. Will stop at next safe checkpoint."
        )
    }

    // --------------------------------------------------------
    // LIST SCAN
    // --------------------------------------------------------

    private func findAvailableFruit(
        round: Int
    ) async throws
    ->
    (
        fruit: FruitCandidate,
        image: UIImage
    )? {
        let screen =
            try await
            WDAClient.shared
            .windowSize()

        var directionDown =
            true

        var reversed =
            false

        var swipes =
            0

        while !cancelled {
            let image =
                try await
                WDAClient.shared
                .screenshot()

            let result =
                await
                FruitDetector.detect(
                    in: image
                )

            persist(
                """
                ROUND \(round) SCAN
                AVAILABLE=\(result.fruits.count)
                STATUS_CARDS=\(result.cards.count)
                BLOCKED=\(result.blockedObjects.count)
                """
            )

            if let first =
                result.fruits.first {
                return (
                    first,
                    image
                )
            }

            // Search down first.
            if swipes >= 8 {
                if !reversed {
                    reversed = true
                    directionDown = false
                    swipes = 0

                    persist(
                        "ROUND \(round): no AVAILABLE below; reversing scan"
                    )
                }
                else {
                    return nil
                }
            }

            if directionDown {
                try await
                    WDAClient.shared
                    .swipe(
                        fromX:
                            Double(
                                screen.width
                            )
                            * 0.52,
                        fromY:
                            Double(
                                screen.height
                            )
                            * 0.77,
                        toX:
                            Double(
                                screen.width
                            )
                            * 0.52,
                        toY:
                            Double(
                                screen.height
                            )
                            * 0.35,
                        duration:
                            0.42
                )
            }
            else {
                try await
                    WDAClient.shared
                    .swipe(
                        fromX:
                            Double(
                                screen.width
                            )
                            * 0.52,
                        fromY:
                            Double(
                                screen.height
                            )
                            * 0.35,
                        toX:
                            Double(
                                screen.width
                            )
                            * 0.52,
                        toY:
                            Double(
                                screen.height
                            )
                            * 0.77,
                        duration:
                            0.42
                    )
            }

            swipes += 1

            try await sleep(
                0.55
            )
        }

        return nil
    }

    // --------------------------------------------------------
    // ONE FULL DISPATCH
    // --------------------------------------------------------

    private func runOneDispatch(
        round: Int,
        fruit: FruitCandidate,
        listImage: UIImage
    ) async throws {
        if cancelled {
            throw
                WDAError.server(
                    "Cancelled."
                )
        }

        persist(
            "ROUND \(round): tap AVAILABLE"
        )

        try await
            normalizedTap(
                pixel:
                    fruit.center,
                image:
                    listImage
            )

        try await sleep(
            0.85
        )

        // 前往探險
        persist(
            "ROUND \(round): 前往探險"
        )

        guard let expedition =
            try await
            waitForPoint(
                attempts: 18,
                delay: 0.38,
                detector:
                    ImageAutomationDetector
                    .detectExpeditionButton
            )
        else {
            throw
                WDAError.server(
                    "Round \(round): 前往探險 not detected."
                )
        }

        try await
            normalizedTap(
                pixel:
                    expedition.point,
                image:
                    expedition.image
            )

        try await sleep(
            0.85
        )

        // Pink filter
        persist(
            "ROUND \(round): selection page settling"
        )

        try await sleep(
            1.15
        )

        let screen =
            try await
            WDAClient.shared
            .windowSize()

        persist(
            "ROUND \(round): force filter swipe"
        )

        // Force one swipe EVERY round.
        try await
            WDAClient.shared
            .swipe(
                fromX:
                    Double(
                        screen.width
                    )
                    * 0.88,
                fromY:
                    Double(
                        screen.height
                    )
                    * 0.432,
                toX:
                    Double(
                        screen.width
                    )
                    * 0.43,
                toY:
                    Double(
                        screen.height
                    )
                    * 0.432,
                duration:
                    0.38
            )

        try await sleep(
            0.62
        )

        var pinkFound:
            (
                point: CGPoint,
                image: UIImage
            )?

        for attempt in 0...4 {
            if cancelled {
                throw
                    WDAError.server(
                        "Cancelled."
                    )
            }

            let image =
                try await
                WDAClient.shared
                .screenshot()

            if let pink =
                ImageAutomationDetector
                .detectPinkFilter(
                    in: image
                ) {
                pinkFound =
                    (
                        pink,
                        image
                    )

                break
            }

            if attempt == 4 {
                break
            }

            try await
                WDAClient.shared
                .swipe(
                    fromX:
                        Double(
                            screen.width
                        )
                        * 0.88,
                    fromY:
                        Double(
                            screen.height
                        )
                        * 0.432,
                    toX:
                        Double(
                            screen.width
                        )
                        * 0.43,
                    toY:
                        Double(
                            screen.height
                        )
                        * 0.432,
                    duration:
                        0.38
                )

            try await sleep(
                0.55
            )
        }

        guard let pink =
            pinkFound
        else {
            throw
                WDAError.server(
                    "Round \(round): pink filter not detected."
                )
        }

        persist(
            "ROUND \(round): tap pink circle"
        )

        try await
            normalizedTap(
                pixel:
                    pink.point,
                image:
                    pink.image
            )

        try await sleep(
            0.85
        )

        // Select 12
        persist(
            "ROUND \(round): select 12"
        )

        for (
            nx,
            ny
        ) in pinkGrid {
            if cancelled {
                throw
                    WDAError.server(
                        "Cancelled."
                    )
            }

            try await
                WDAClient.shared
                .tap(
                    x:
                        Double(
                            screen.width
                        )
                        * nx,
                    y:
                        Double(
                            screen.height
                        )
                        * ny
                )

            try await sleep(
                0.10
            )
        }

        try await sleep(
            0.42
        )

        // GO
        persist(
            "ROUND \(round): GO"
        )

        guard let go =
            try await
            waitForPoint(
                attempts: 14,
                delay: 0.34,
                detector:
                    ImageAutomationDetector
                    .detectActiveGO
            )
        else {
            throw
                WDAError.server(
                    "Round \(round): active GO not detected."
                )
        }

        try await
            normalizedTap(
                pixel:
                    go.point,
                image:
                    go.image
            )

        try await sleep(
            0.75
        )

        // Carrying X
        persist(
            "ROUND \(round): wait carrying X"
        )

        guard let close =
            try await
            waitForPoint(
                attempts: 50,
                delay: 0.38,
                detector:
                    ImageAutomationDetector
                    .detectCarryingClose
            )
        else {
            throw
                WDAError.server(
                    "Round \(round): carrying X not detected."
                )
        }

        try await
            normalizedTap(
                pixel:
                    close.point,
                image:
                    close.image
            )

        persist(
            "ROUND \(round): X closed"
        )

        try await sleep(
            0.70
        )
    }

    // --------------------------------------------------------
    // RETURN TO LIST
    // --------------------------------------------------------

    private func waitForExpeditionList()
        async throws
        -> Bool {
        for _ in 0..<18 {
            if cancelled {
                return false
            }

            let image =
                try await
                WDAClient.shared
                .screenshot()

            let result =
                await
                FruitDetector.detect(
                    in: image
                )

            if !result.fruits.isEmpty ||
                !result.cards.isEmpty ||
                !result.blockedObjects.isEmpty {
                return true
            }

            try await sleep(
                0.40
            )
        }

        return false
    }

    // --------------------------------------------------------
    // FOREGROUND REFRESH
    // --------------------------------------------------------

    private func foregroundRefresh()
        async throws {
        guard let controllerBundle =
            Bundle.main.bundleIdentifier,
              !controllerBundle.isEmpty
        else {
            throw
                WDAError.server(
                    "Controller bundle identifier unavailable."
                )
        }

        do {
            try await
                WDAClient.shared
                .activateApp(
                    bundleId:
                        controllerBundle
                )
        }
        catch {
            // Foreground transition can interrupt response.
        }

        var active =
            false

        // Check quickly; don't leave Controller visible for long.
        for _ in 0..<12 {
            if UIApplication.shared
                .applicationState ==
                .active {
                active =
                    true
                break
            }

            try await sleep(
                0.05
            )
        }

        guard active else {
            throw
                WDAError.server(
                    "Controller could not return foreground automatically."
                )
        }

        // Fresh background window while Controller is active.
        startFreshBackgroundTask(
            label:
                "round-\(completedDispatches + 1)"
        )

        // User asked for as little visible flash as possible.
        // Keep Controller foreground only ~0.20-0.25 sec.
        try await sleep(
            0.20
        )

        do {
            try await
                WDAClient.shared
                .launchPikmin()
        }
        catch {
            // App switch may interrupt final HTTP response.
        }

        try await sleep(
            0.55
        )
    }

    private func startFreshBackgroundTask(
        label: String
    ) {
        finishBackgroundTask()

        bgTask =
            UIApplication.shared
            .beginBackgroundTask(
                withName:
                    "PikminLoop-\(label)"
            ) {
                [weak self] in

                self?.persist(
                    "BACKGROUND TOKEN EXPIRED (\(label))"
                )

                self?
                    .finishBackgroundTask()
            }
    }

    // --------------------------------------------------------
    // HELPERS
    // --------------------------------------------------------

    private func normalizedTap(
        pixel: CGPoint,
        image: UIImage
    ) async throws {
        guard let cg =
            image.cgImage
        else {
            throw
                WDAError
                .invalidScreenshot
        }

        let screen =
            try await
            WDAClient.shared
            .windowSize()

        let x =
            Double(
                pixel.x
            )
            /
            Double(
                cg.width
            )
            *
            Double(
                screen.width
            )

        let y =
            Double(
                pixel.y
            )
            /
            Double(
                cg.height
            )
            *
            Double(
                screen.height
            )

        try await
            WDAClient.shared
            .tap(
                x: x,
                y: y
            )
    }

    private func waitForPoint(
        attempts: Int,
        delay: Double,
        detector:
            @escaping
            (UIImage) -> CGPoint?
    ) async throws
    ->
    (
        point: CGPoint,
        image: UIImage
    )? {
        for _ in 0..<attempts {
            if cancelled {
                return nil
            }

            let image =
                try await
                WDAClient.shared
                .screenshot()

            if let point =
                detector(
                    image
                ) {
                return (
                    point,
                    image
                )
            }

            try await sleep(
                delay
            )
        }

        return nil
    }

    private func sleep(
        _ seconds: Double
    ) async throws {
        try await
            Task.sleep(
                nanoseconds:
                    UInt64(
                        seconds
                        *
                        1_000_000_000
                    )
            )
    }

    private func persist(
        _ text: String
    ) {
        status =
            text

        UserDefaults.standard.set(
            text,
            forKey:
                "stage5Status"
        )
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
