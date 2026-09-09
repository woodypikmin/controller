
import UIKit

@MainActor
final class MultiDispatchProbe: ObservableObject {
    static let shared = MultiDispatchProbe()

    @Published var status = "Not started"

    private var bgTask:
        UIBackgroundTaskIdentifier =
        .invalid

    private var cancelled =
        false

    // Pikmin Bloom keeps the color filter selected between dispatches.
    // If we tap the pink filter again on dispatch #2, it can toggle it OFF.
    private var pinkFilterActive =
        false

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
            "stage4_final.png"
        )
    }

    func runTwoDispatches() {
        cancelled = false
        pinkFilterActive = false

        UserDefaults.standard.set(
            "",
            forKey: "stage4Status"
        )

        persist(
            "START: 2-dispatch test"
        )

        bgTask =
            UIApplication.shared
            .beginBackgroundTask(
                withName:
                    "PikminTwoDispatchTest"
            ) {
                [weak self] in

                self?.persist(
                    "FAILED: iOS background task expired during 2-dispatch test"
                )

                self?
                    .finishBackgroundTask()
            }

        Task {
            do {
                do {
                    try await
                        WDAClient.shared
                        .launchPikmin()
                }
                catch {
                    // Foreground switch can interrupt final HTTP response.
                }

                try await sleep(
                    3.0
                )

                for dispatchIndex in 1...2 {
                    if cancelled {
                        throw
                            WDAError.server(
                                "Cancelled."
                            )
                    }

                    persist(
                        "DISPATCH \(dispatchIndex)/2: scanning list"
                    )

                    guard let choice =
                        try await
                        findAvailableFruit(
                            dispatchIndex:
                                dispatchIndex
                        )
                    else {
                        throw
                            WDAError.server(
                                "No safe AVAILABLE fruit found for dispatch \(dispatchIndex)."
                            )
                    }

                    try await
                        runOneDispatch(
                            dispatchIndex:
                                dispatchIndex,
                            fruit:
                                choice.fruit,
                            listImage:
                                choice.image
                        )

                    persist(
                        "DISPATCH \(dispatchIndex)/2: completed"
                    )

                    if dispatchIndex < 2 {
                        persist(
                            "Waiting for Expedition list to return..."
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
                            0.7
                        )
                    }
                }

                let final =
                    try await
                    WDAClient.shared
                    .screenshot()

                if let png =
                    final.pngData() {
                    try png.write(
                        to:
                            Self.finalScreenshotURL,
                        options:
                            .atomic
                    )
                }

                persist(
                    """
                    SUCCESS: TWO FULL DISPATCHES COMPLETED
                    1/2 -> X -> list -> 2/2 -> X

                    Test intentionally stops here.
                    """
                )

                finishBackgroundTask()
            }
            catch {
                persist(
                    "FAILED: \(error.localizedDescription)"
                )

                finishBackgroundTask()
            }
        }
    }

    func cancel() {
        cancelled = true

        persist(
            "STOP requested. Bot will stop at the next safe check."
        )
    }

    // --------------------------------------------------------
    // LIST SCAN
    // --------------------------------------------------------

    private func findAvailableFruit(
        dispatchIndex: Int
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

        while true {
            if cancelled {
                return nil
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

            persist(
                """
                DISPATCH \(dispatchIndex)/2 SCAN
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

            // No available fruit on current viewport.
            if swipes >= 8 {
                if !reversed {
                    reversed = true
                    directionDown = false
                    swipes = 0

                    persist(
                        "No AVAILABLE below; reversing list scan."
                    )
                }
                else {
                    return nil
                }
            }

            // Finger up = list moves down.
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
                0.65
            )
        }
    }

    // --------------------------------------------------------
    // ONE DISPATCH
    // --------------------------------------------------------

    private func runOneDispatch(
        dispatchIndex: Int,
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
            "DISPATCH \(dispatchIndex)/2: tap AVAILABLE"
        )

        try await
            normalizedTap(
                pixel:
                    fruit.center,
                image:
                    listImage
            )

        try await sleep(
            0.9
        )

        // 前往探險
        persist(
            "DISPATCH \(dispatchIndex)/2: 前往探險"
        )

        guard let expedition =
            try await
            waitForPoint(
                attempts: 18,
                delay: 0.40,
                detector:
                    ImageAutomationDetector
                    .detectExpeditionButton
            )
        else {
            throw
                WDAError.server(
                    "Dispatch \(dispatchIndex): could not detect 前往探險."
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
            0.9
        )

        // Pink filter
        persist(
            "DISPATCH \(dispatchIndex)/2: pink filter"
        )

        let screen =
            try await
            WDAClient.shared
            .windowSize()

        // IMPORTANT:
        // Pikmin Bloom preserves the selected color filter after dispatch.
        // Once pink is selected, do NOT tap it again on the next dispatch,
        // because that can toggle the filter off.
        if !pinkFilterActive {
            var pinkFound:
                (
                    point: CGPoint,
                    image: UIImage
                )?

            for attempt in 0...4 {
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
                            * 0.86,
                        fromY:
                            Double(
                                screen.height
                            )
                            * 0.432,
                        toX:
                            Double(
                                screen.width
                            )
                            * 0.48,
                        toY:
                            Double(
                                screen.height
                            )
                            * 0.432,
                        duration:
                            0.35
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
                        "Dispatch \(dispatchIndex): pink filter not found."
                    )
            }

            try await
                normalizedTap(
                    pixel:
                        pink.point,
                    image:
                        pink.image
                )

            pinkFilterActive =
                true

            persist(
                "DISPATCH \(dispatchIndex)/2: pink filter selected"
            )

            try await sleep(
                0.65
            )
        }
        else {
            persist(
                "DISPATCH \(dispatchIndex)/2: pink filter already active; skip re-tap"
            )

            // Let the Pikmin grid finish settling after entering this page.
            try await sleep(
                0.55
            )
        }

        // Select 12
        persist(
            "DISPATCH \(dispatchIndex)/2: select 12"
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
                0.11
            )
        }

        try await sleep(
            0.45
        )

        // GO
        persist(
            "DISPATCH \(dispatchIndex)/2: GO"
        )

        guard let go =
            try await
            waitForPoint(
                attempts: 14,
                delay: 0.35,
                detector:
                    ImageAutomationDetector
                    .detectActiveGO
            )
        else {
            throw
                WDAError.server(
                    "Dispatch \(dispatchIndex): active GO not detected."
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
            0.8
        )

        // Carrying X
        persist(
            "DISPATCH \(dispatchIndex)/2: wait carrying X"
        )

        guard let close =
            try await
            waitForPoint(
                attempts: 50,
                delay: 0.40,
                detector:
                    ImageAutomationDetector
                    .detectCarryingClose
            )
        else {
            throw
                WDAError.server(
                    "Dispatch \(dispatchIndex): carrying X not detected."
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
            "DISPATCH \(dispatchIndex)/2: X closed"
        )

        try await sleep(
            0.8
        )
    }

    // --------------------------------------------------------
    // RETURN-TO-LIST
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

            // Any of these is strong evidence that we're back on list:
            // safe fruit, BUSY/COMPLETE/PARTIAL card, blocked object.
            if !result.fruits.isEmpty ||
                !result.cards.isEmpty ||
                !result.blockedObjects.isEmpty {
                return true
            }

            try await sleep(
                0.45
            )
        }

        return false
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
            Double(pixel.x)
            /
            Double(cg.width)
            *
            Double(screen.width)

        let y =
            Double(pixel.y)
            /
            Double(cg.height)
            *
            Double(screen.height)

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
        try await Task.sleep(
            nanoseconds:
                UInt64(
                    seconds
                    * 1_000_000_000
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
                "stage4Status"
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
