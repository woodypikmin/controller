
import UIKit

@MainActor
final class BotProbe: ObservableObject {
    static let shared = BotProbe()

    @Published var status = "Ready"
    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    static var resultURL: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("stage2_1_detection.png")
    }

    func detectOnly() {
        run(tapFirstAvailable: false)
    }

    func detectAndTap() {
        run(tapFirstAvailable: true)
    }

    private func run(tapFirstAvailable: Bool) {
        status = tapFirstAvailable
            ? "Launching Pikmin; OCR + detect + tap first AVAILABLE"
            : "Launching Pikmin; OCR + detect only"

        UserDefaults.standard.set("", forKey: "stage2Status")

        bgTask = UIApplication.shared.beginBackgroundTask(
            withName: "PikminStage2_1"
        ) { [weak self] in
            UserDefaults.standard.set(
                "FAILED: iOS expired background task",
                forKey: "stage2Status"
            )
            self?.finishBackgroundTask()
        }

        Task {
            do {
                try await WDAClient.shared.launchPikmin()
            } catch {
                // Continue; launch may still have occurred.
            }

            try? await Task.sleep(nanoseconds: 4_000_000_000)

            do {
                let image = try await WDAClient.shared.screenshot()
                let fruits = await FruitDetector.detect(in: image)

                let annotated = FruitDetector.annotated(
                    image: image,
                    fruits: fruits
                )

                if let png = annotated.pngData() {
                    try png.write(
                        to: Self.resultURL,
                        options: .atomic
                    )
                }

                let available = fruits.filter { $0.state == .available }
                let busy = fruits.filter { $0.state == .busy }
                let complete = fruits.filter { $0.state == .complete }
                let blocked = fruits.filter { $0.state == .blocked }

                var text = """
                OCR CARD DETECTION OK
                available=\(available.count)
                busy=\(busy.count)
                complete=\(complete.count)
                blocked=\(blocked.count)

                """

                for (index, fruit) in fruits.enumerated() {
                    let cleanText = fruit.cardText
                        .replacingOccurrences(of: "\n", with: " ")

                    text += """
                    #\(index + 1) \(fruit.state.rawValue)
                    OCR: \(cleanText)
                    framePinkRows=\(fruit.pinkFrameRows)
                    frameMintRows=\(fruit.mintFrameRows)
                    pikminLeft=\(String(format: "%.3f", fruit.pikminLeftScore))

                    """
                }

                if tapFirstAvailable,
                   let first = available.first {
                    let screen = try await WDAClient.shared.windowSize()

                    guard let cg = image.cgImage else {
                        throw WDAError.invalidScreenshot
                    }

                    let x = Double(first.center.x)
                        / Double(cg.width)
                        * Double(screen.width)

                    let y = Double(first.center.y)
                        / Double(cg.height)
                        * Double(screen.height)

                    try await WDAClient.shared.tap(x: x, y: y)

                    text += """
                    TAP SENT
                    x=\(String(format: "%.1f", x))
                    y=\(String(format: "%.1f", y))
                    """
                }

                UserDefaults.standard.set(
                    text,
                    forKey: "stage2Status"
                )

                await MainActor.run {
                    self.status = text
                    self.finishBackgroundTask()
                }

            } catch {
                let text = "FAILED: \(error.localizedDescription)"

                UserDefaults.standard.set(
                    text,
                    forKey: "stage2Status"
                )

                await MainActor.run {
                    self.status = text
                    self.finishBackgroundTask()
                }
            }
        }
    }

    private func finishBackgroundTask() {
        if bgTask != .invalid {
            UIApplication.shared.endBackgroundTask(bgTask)
            bgTask = .invalid
        }
    }
}
