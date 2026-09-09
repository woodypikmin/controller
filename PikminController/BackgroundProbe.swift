
import Foundation
import UIKit

@MainActor
final class BackgroundProbe: ObservableObject {
    static let shared = BackgroundProbe()

    @Published var state = "Not started"

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    func run(delaySeconds: Int) {
        state = "Launching Pikmin; background probe scheduled in \(delaySeconds)s"

        UserDefaults.standard.set(false, forKey: "bgProbeSuccess")
        UserDefaults.standard.set("scheduled", forKey: "bgProbeStatus")
        UserDefaults.standard.set(delaySeconds, forKey: "bgProbeDelay")

        backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "PikminBackgroundProbe"
        ) { [weak self] in
            UserDefaults.standard.set(
                "iOS expired the background task",
                forKey: "bgProbeStatus"
            )
            self?.endBackgroundTask()
        }

        Task {
            do {
                try await WDAClient.shared.launchPikmin()

                UserDefaults.standard.set(
                    "Pikmin launch returned; waiting in background",
                    forKey: "bgProbeStatus"
                )
            } catch {
                // Pikmin may still open even when Controller is backgrounded
                // before URLSession receives the final response.
                UserDefaults.standard.set(
                    "launch request ended: \(error.localizedDescription)",
                    forKey: "bgProbeStatus"
                )
            }

            do {
                try await Task.sleep(
                    nanoseconds: UInt64(delaySeconds) * 1_000_000_000
                )

                let data = try await WDAClient.shared.screenshotData()

                let url = Self.resultURL
                try data.write(to: url, options: .atomic)

                UserDefaults.standard.set(true, forKey: "bgProbeSuccess")
                UserDefaults.standard.set(
                    "SUCCESS: screenshot captured while Controller was backgrounded",
                    forKey: "bgProbeStatus"
                )
                UserDefaults.standard.set(
                    Date().timeIntervalSince1970,
                    forKey: "bgProbeCompletedAt"
                )
            } catch {
                UserDefaults.standard.set(false, forKey: "bgProbeSuccess")
                UserDefaults.standard.set(
                    "FAILED: \(error.localizedDescription)",
                    forKey: "bgProbeStatus"
                )
            }

            await MainActor.run {
                self.state = UserDefaults.standard.string(
                    forKey: "bgProbeStatus"
                ) ?? "Finished"

                self.endBackgroundTask()
            }
        }
    }

    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    static var resultURL: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("background_probe.png")
    }

    static func savedStatus() -> String {
        let d = UserDefaults.standard
        let status = d.string(forKey: "bgProbeStatus") ?? "none"
        let delay = d.integer(forKey: "bgProbeDelay")
        let success = d.bool(forKey: "bgProbeSuccess")

        return """
        delay: \(delay)s
        success: \(success)
        status: \(status)
        """
    }
}
