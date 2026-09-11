import SwiftUI
import UIKit

@MainActor
final class Stage8FullLoopController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var completedDispatches = 0

    private var cancelled = false
    private var worker: Task<Void, Never>?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var backgroundGeneration: UInt64 = 0
    private var renewalInProgress = false
    private var logLines: [String] = []

    private var statusSink: ((String) -> Void)?
    private var screenshotSink: ((UIImage) -> Void)?

    func start(
        pairingPath: String,
        onStatus: @escaping (String) -> Void,
        onScreenshot: @escaping (UIImage) -> Void
    ) {
        guard !isRunning else { return }

        cancelled = false
        completedDispatches = 0
        logLines.removeAll(keepingCapacity: true)
        statusSink = onStatus
        screenshotSink = onScreenshot
        isRunning = true

        beginBackgroundWindow(label: "initial")
        emit("STAGE 8.1.3 FULL LOOP START • GO/background stability fix • WDA=OFF")

        worker = Task { [weak self] in
            guard let self else { return }
            await self.run(pairingPath: pairingPath)
        }
    }

    func stop() {
        guard isRunning else { return }
        cancelled = true
        emit("STOP requested • will stop at the next safe checkpoint")
    }

    private func finish() {
        // Invalidate any queued expiration callback before ending the task.
        backgroundGeneration &+= 1
        renewalInProgress = false
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        isRunning = false
        worker = nil
    }

    private func beginBackgroundWindow(label: String) {
        // Every background window has a generation token. iOS can deliver an
        // expiration callback while we are replacing an old window; callbacks
        // from superseded windows must never cancel the new loop.
        backgroundGeneration &+= 1
        let generation = backgroundGeneration

        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }

        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "PikminPilot-Stage8.1.3-\(label)",
            expirationHandler: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    guard generation == self.backgroundGeneration else {
                        self.emit("BACKGROUND stale expiration ignored • generation=\(generation)")
                        return
                    }
                    if self.renewalInProgress {
                        self.emit("BACKGROUND expiration arrived during renewal • deferred")
                        return
                    }
                    self.cancelled = true
                    self.emit("BACKGROUND WINDOW EXPIRED • stop requested")
                }
            }
        )
    }

    private func emit(_ line: String) {
        logLines.append(line)
        if logLines.count > 220 {
            logLines.removeFirst(logLines.count - 220)
        }
        statusSink?(logLines.joined(separator: "\n"))
    }

    private func pause(_ seconds: Double) async {
        let ns = UInt64(max(0, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: ns)
    }

    private func run(pairingPath: String) async {
        let engine = IDeviceEngine(pairingPath: pairingPath)

        do {
            let activate = await engine.runXCTestActivateOnly()
            guard activate.ok else {
                throw LoopError("phase=initial-activate • \(activate.message)")
            }
            emit("Pikmin activate ✅")
            await pause(0.45)

            while !cancelled {
                let round = completedDispatches + 1
                emit("ROUND \(round) • scanning Expedition list")

                guard let choice = try await findAvailableFruit(
                    engine: engine,
                    round: round
                ) else {
                    emit("FINISHED • no safe AVAILABLE fruit found • completed=\(completedDispatches)")
                    finish()
                    return
                }

                try await runOneDispatch(
                    engine: engine,
                    round: round,
                    fruit: choice.fruit,
                    listImage: choice.image
                )

                completedDispatches += 1
                emit("ROUND \(round) COMPLETED ✅ • total=\(completedDispatches)")

                if cancelled { break }

                guard try await waitForExpeditionList(engine: engine, attempts: 20) else {
                    throw LoopError("Round \(round): Expedition list did not return after green X")
                }

                if cancelled { break }

                // iOS gives a finite background execution window. Renew it
                // between completed dispatches by briefly foregrounding Pilot,
                // then immediately re-activate the already-running game.
                try await refreshBackgroundWindow(
                    engine: engine,
                    reason: "between-rounds"
                )

                await pause(0.35)
            }

            emit("STOPPED BY USER • completed=\(completedDispatches)")
            finish()
        } catch {
            if cancelled && error.localizedDescription == "cancelled" {
                emit("STOPPED BY USER • completed=\(completedDispatches)")
            } else {
                emit("FAILED • completed=\(completedDispatches) • \(error.localizedDescription)")
            }
            finish()
        }
    }

    // MARK: - Fruit list scan (Stage 5 card-first semantics)

    private func findAvailableFruit(
        engine: IDeviceEngine,
        round: Int
    ) async throws -> (fruit: FruitCandidate, image: UIImage)? {
        var directionDown = true
        var reversed = false
        var swipes = 0

        while !cancelled {
            try await ensureBackgroundBudget(engine: engine, stage: "fruit-scan")

            let image = try await capture(engine: engine, tag: "fruit-list")
            let result = await FruitDetector.detect(in: image)
            screenshotSink?(FruitDetector.annotated(image: image, result: result))

            let available = result.fruits.sorted {
                if abs($0.center.y - $1.center.y) > 12 {
                    return $0.center.y < $1.center.y
                }
                return $0.center.x < $1.center.x
            }

            let busyCards = result.cards.filter { $0.state == .busy }.count
            let completeCards = result.cards.filter { $0.state == .complete }.count

            emit(
                "ROUND \(round) SCAN • AVAILABLE=\(available.count) • BUSY=\(busyCards) • COMPLETE=\(completeCards) • BLOCKED=\(result.blockedObjects.count)"
            )

            if let first = available.first {
                emit("ROUND \(round) • card-first AVAILABLE selected • label=\(first.labelText)")
                return (first, image)
            }

            if swipes >= 8 {
                if !reversed {
                    reversed = true
                    directionDown = false
                    swipes = 0
                    emit("ROUND \(round) • no AVAILABLE below; reversing list scan")
                } else {
                    return nil
                }
            }

            if directionDown {
                try await swipe(
                    engine: engine,
                    fromX: 0.52,
                    fromY: 0.77,
                    toX: 0.52,
                    toY: 0.35,
                    duration: 0.42,
                    stage: "fruit-list-down"
                )
            } else {
                try await swipe(
                    engine: engine,
                    fromX: 0.52,
                    fromY: 0.35,
                    toX: 0.52,
                    toY: 0.77,
                    duration: 0.42,
                    stage: "fruit-list-up"
                )
            }

            swipes += 1
            await pause(0.55)
        }

        return nil
    }

    // MARK: - One complete Stage 5 dispatch

    private func runOneDispatch(
        engine: IDeviceEngine,
        round: Int,
        fruit: FruitCandidate,
        listImage: UIImage
    ) async throws {
        try checkCancelled()

        emit("ROUND \(round) • tap AVAILABLE")
        try await tap(
            engine: engine,
            pixel: fruit.center,
            image: listImage,
            stage: "available-fruit"
        )
        await pause(0.85)

        emit("ROUND \(round) • detect 前往探險")
        guard let expedition = try await waitForPoint(
            engine: engine,
            attempts: 18,
            delay: 0.38,
            stage: "expedition-button",
            detector: ImageAutomationDetector.detectExpeditionButton
        ) else {
            throw LoopError("Round \(round): 前往探險 not detected")
        }

        try await tap(
            engine: engine,
            pixel: expedition.point,
            image: expedition.image,
            stage: "expedition-button"
        )
        await pause(2.0)

        emit("ROUND \(round) • force pink-filter row swipe")
        try await swipe(
            engine: engine,
            fromX: 0.88,
            fromY: 0.432,
            toX: 0.43,
            toY: 0.432,
            duration: 0.38,
            stage: "pink-filter-row"
        )
        await pause(0.62)

        var pinkFound: (point: CGPoint, image: UIImage)?
        for attempt in 0...4 {
            try checkCancelled()
            try await ensureBackgroundBudget(engine: engine, stage: "pink-filter")

            let image = try await capture(engine: engine, tag: "pink-filter")
            screenshotSink?(image)
            if let point = ImageAutomationDetector.detectPinkFilter(in: image) {
                pinkFound = (point, image)
                break
            }

            if attempt < 4 {
                try await swipe(
                    engine: engine,
                    fromX: 0.88,
                    fromY: 0.432,
                    toX: 0.43,
                    toY: 0.432,
                    duration: 0.38,
                    stage: "pink-filter-retry"
                )
                await pause(0.55)
            }
        }

        guard let pink = pinkFound else {
            throw LoopError("Round \(round): pink filter not detected")
        }

        emit("ROUND \(round) • tap pink filter")
        try await tap(
            engine: engine,
            pixel: pink.point,
            image: pink.image,
            stage: "pink-filter"
        )
        await pause(0.85)

        try checkCancelled()
        try await ensureBackgroundBudget(engine: engine, stage: "select12")
        emit("ROUND \(round) • select fixed 12 pink Pikmin")
        let select12 = await engine.runXCTestSelectPink12()
        guard select12.ok else {
            throw LoopError("phase=select12 • \(select12.message)")
        }
        emit("ROUND \(round) • select12 XCTest completed")
        await pause(0.42)

        // IMPORTANT: renew BEFORE taking the GO screenshot. Stage 8.1.1/8.1.2
        // detected GO first and then briefly foregrounded Pilot. That made the
        // saved GO frame/coordinate stale and also exposed a race where the old
        // background-task expiration callback could cancel the new loop.
        // Refresh first, re-activate the existing game, then detect GO again on
        // the actual post-renewal frame that will be tapped.
        try await ensureBackgroundBudget(
            engine: engine,
            stage: "post-select12-pre-GO",
            minimumRemaining: 27.0
        )
        try checkCancelled()

        emit("ROUND \(round) • detect active GO on fresh post-renewal frame")
        guard let go = try await waitForPoint(
            engine: engine,
            attempts: 14,
            delay: 0.34,
            stage: "active-go",
            detector: ImageAutomationDetector.detectActiveGO
        ) else {
            throw LoopError("Round \(round): active GO not detected")
        }

        if let cg = go.image.cgImage {
            let nx = Double(go.point.x) / Double(cg.width)
            let ny = Double(go.point.y) / Double(cg.height)
            emit(String(format: "ROUND %d • active GO detected • normalized=(%.4f,%.4f)", round, nx, ny))
        }

        // Do not foreground Pilot between GO detection and the GO tap. The
        // point above belongs to this exact frame.
        try await tap(
            engine: engine,
            pixel: go.point,
            image: go.image,
            stage: "GO",
            allowBackgroundRenewal: false
        )
        emit("ROUND \(round) • GO tap dispatch completed")
        await pause(0.90)

        emit("ROUND \(round) • wait carrying green X")
        guard let close = try await waitForCarryingClose(
            engine: engine,
            round: round
        ) else {
            throw LoopError("Round \(round): carrying green X not detected (strict+broad)")
        }

        try await tap(
            engine: engine,
            pixel: close.point,
            image: close.image,
            stage: "carrying-green-x",
            allowBackgroundRenewal: false
        )
        emit("ROUND \(round) • green X closed • detector=\(close.mode)")
        await pause(0.80)
    }

    // MARK: - Detection / input helpers

    private func waitForCarryingClose(
        engine: IDeviceEngine,
        round: Int
    ) async throws -> (point: CGPoint, image: UIImage, mode: String)? {
        // Critical section: DO NOT foreground Pilot here. We just tapped GO and
        // must leave Pikmin untouched until the carrying overlay appears.
        // Try the visual detectors briefly, then use the coordinate measured
        // from the user's real 942x2048 carrying screenshot.
        for index in 0..<8 {
            try checkCancelled()

            let image = try await capture(engine: engine, tag: "carrying-green-x")
            screenshotSink?(image)

            if let point = ImageAutomationDetector.detectCarryingClose(in: image) {
                return (point, image, "strict")
            }

            if index >= 2,
               let point = ImageAutomationDetector.detectCarryingCloseBroad(in: image) {
                emit("ROUND \(round) • carrying green X found by broad ROI")
                return (point, image, "broad")
            }

            if index >= 4 {
                let fixedPoint = CGPoint(
                    x: Double(image.cgImage?.width ?? 1) * 0.0971,
                    y: Double(image.cgImage?.height ?? 1) * 0.9144
                )
                emit("ROUND \(round) • green X visual miss → calibrated fallback x=0.0971 y=0.9144")
                return (fixedPoint, image, "fixed@0.0971,0.9144")
            }

            if index == 0 || index == 2 {
                emit("ROUND \(round) • carrying green X scan attempt \(index + 1)/8")
            }
            await pause(0.34)
        }
        return nil
    }

    private func waitForPoint(
        engine: IDeviceEngine,
        attempts: Int,
        delay: Double,
        stage: String,
        detector: (UIImage) -> CGPoint?
    ) async throws -> (point: CGPoint, image: UIImage)? {
        for index in 0..<attempts {
            try checkCancelled()
            if index % 4 == 0 {
                try await ensureBackgroundBudget(engine: engine, stage: stage)
            }

            let image = try await capture(engine: engine, tag: stage)
            screenshotSink?(image)
            if let point = detector(image) {
                return (point, image)
            }
            await pause(delay)
        }
        return nil
    }

    private func waitForExpeditionList(
        engine: IDeviceEngine,
        attempts: Int
    ) async throws -> Bool {
        for index in 0..<attempts {
            try checkCancelled()
            if index % 4 == 0 {
                try await ensureBackgroundBudget(engine: engine, stage: "return-list")
            }

            let image = try await capture(engine: engine, tag: "return-list")
            let result = await FruitDetector.detect(in: image)
            screenshotSink?(FruitDetector.annotated(image: image, result: result))

            if !result.fruits.isEmpty ||
                !result.cards.isEmpty ||
                !result.blockedObjects.isEmpty {
                return true
            }
            await pause(0.40)
        }
        return false
    }

    private func capture(
        engine: IDeviceEngine,
        tag: String
    ) async throws -> UIImage {
        let safeTag = tag.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PikminPilot-Stage8.1.3-\(safeTag).png")
        try? FileManager.default.removeItem(at: url)

        let result = await engine.takeScreenshot(outputPath: url.path)
        guard result.ok else {
            throw LoopError("phase=dvt-screenshot/\(tag) • \(result.message)")
        }
        guard
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data),
            image.cgImage != nil
        else {
            throw LoopError("phase=dvt-screenshot/\(tag) • UIKit decode failed")
        }
        return image
    }

    private func tap(
        engine: IDeviceEngine,
        pixel: CGPoint,
        image: UIImage,
        stage: String,
        allowBackgroundRenewal: Bool = true
    ) async throws {
        try checkCancelled()
        if allowBackgroundRenewal {
            try await ensureBackgroundBudget(engine: engine, stage: stage)
        }

        guard let cg = image.cgImage else {
            throw LoopError("phase=\(stage) • screenshot has no CGImage")
        }
        let x = Double(pixel.x) / Double(cg.width)
        let y = Double(pixel.y) / Double(cg.height)
        guard (0...1).contains(x), (0...1).contains(y) else {
            throw LoopError("phase=\(stage) • invalid normalized tap (\(x),\(y))")
        }

        let result = await engine.runXCTestTap(normalizedX: x, normalizedY: y)
        guard result.ok else {
            throw LoopError("phase=\(stage)-tap • \(result.message)")
        }
    }

    private func swipe(
        engine: IDeviceEngine,
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        duration: Double,
        stage: String
    ) async throws {
        try checkCancelled()
        try await ensureBackgroundBudget(engine: engine, stage: stage)

        let result = await engine.runXCTestSwipe(
            fromX: fromX,
            fromY: fromY,
            toX: toX,
            toY: toY,
            duration: duration
        )
        guard result.ok else {
            throw LoopError("phase=\(stage)-swipe • \(result.message)")
        }
    }

    // MARK: - iOS finite-background renewal

    private func ensureBackgroundBudget(
        engine: IDeviceEngine,
        stage: String,
        minimumRemaining: Double = 12.0
    ) async throws {
        guard UIApplication.shared.applicationState != .active else { return }

        let remaining = UIApplication.shared.backgroundTimeRemaining
        if remaining.isFinite && remaining < minimumRemaining {
            emit(String(format: "BACKGROUND %.1fs left • renewing at %@", remaining, stage))
            try await refreshBackgroundWindow(engine: engine, reason: stage)
        }
    }

    private func refreshBackgroundWindow(
        engine: IDeviceEngine,
        reason: String
    ) async throws {
        try checkCancelled()
        renewalInProgress = true
        defer { renewalInProgress = false }
        emit("BACKGROUND renewal begin • reason=\(reason)")

        guard let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty else {
            throw LoopError("Pilot bundle identifier unavailable for background renewal")
        }

        // Capture the current game frame for diagnostics immediately before the
        // renewal. The target itself is never terminated or relaunched.
        if let freeze = try? await capture(engine: engine, tag: "refresh-\(reason)") {
            screenshotSink?(freeze)
        }

        let foregroundPilot = await engine.launchBundleID(bundleID)
        guard foregroundPilot.ok else {
            throw LoopError("phase=background-refresh-pilot • \(foregroundPilot.message)")
        }

        var active = false
        for _ in 0..<60 {
            if UIApplication.shared.applicationState == .active {
                active = true
                break
            }
            await pause(0.05)
        }
        guard active else {
            throw LoopError("phase=background-refresh • Pikmin Pilot did not return foreground")
        }

        beginBackgroundWindow(label: "renew-\(reason)")

        let reactivate = await engine.runXCTestActivateOnly()
        guard reactivate.ok else {
            throw LoopError("phase=background-refresh-pikmin • \(reactivate.message)")
        }

        emit("BACKGROUND renewed ✅ • Pikmin re-activated without relaunch")
        await pause(0.30)
    }

    private func checkCancelled() throws {
        if cancelled {
            throw LoopError("cancelled")
        }
    }
}

private struct LoopError: LocalizedError {
    let detail: String

    init(_ detail: String) {
        self.detail = detail
    }

    var errorDescription: String? { detail }
}
