
import SwiftUI

struct ContentView: View {
    @State private var log = "Ready."
    @State private var wdaOK = false
    @State private var sessionOK = false
    @State private var screenshot: UIImage?

    @State private var tapX = "201"
    @State private var tapY = "437"

    var body: some View {
        NavigationStack {
            Form {
                Section("WDA") {
                    HStack {
                        Text("Local WDA")
                        Spacer()
                        Text(wdaOK ? "READY" : "NOT CHECKED")
                            .foregroundStyle(wdaOK ? .green : .secondary)
                    }

                    Button("1. Check WDA on 127.0.0.1:8100") {
                        Task {
                            await checkWDA()
                        }
                    }

                    Button("2. Create Pikmin Session") {
                        Task {
                            await createSession()
                        }
                    }
                    .disabled(!wdaOK)

                    HStack {
                        Text("Pikmin session")
                        Spacer()
                        Text(sessionOK ? "READY" : "NO")
                            .foregroundStyle(sessionOK ? .green : .secondary)
                    }
                }

                Section("Screenshot") {
                    Button("Get iPhone Screenshot Through WDA") {
                        Task {
                            await getScreenshot()
                        }
                    }
                    .disabled(!wdaOK)

                    if let screenshot {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 340)
                    }
                }

                Section("Real Tap Test") {
                    Text("Enter a SAFE coordinate. This sends a real touch to the active app.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("x", text: $tapX)
                            .keyboardType(.decimalPad)
                        TextField("y", text: $tapY)
                            .keyboardType(.decimalPad)
                    }

                    Button("SEND ONE TAP") {
                        Task {
                            await sendTap()
                        }
                    }
                    .disabled(!sessionOK)
                }

                Section("Swipe Test") {
                    Button("Swipe Up Once") {
                        Task {
                            await sendSwipe()
                        }
                    }
                    .disabled(!sessionOK)
                }

                Section("Log") {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Pikmin Controller")
        }
    }

    @MainActor
    private func checkWDA() async {
        do {
            let result = try await WDAClient.shared.status()
            wdaOK = true
            log = "WDA OK\n\(result)"
        } catch {
            wdaOK = false
            sessionOK = false
            log = "WDA check FAILED:\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func createSession() async {
        do {
            let sid = try await WDAClient.shared.createPikminSession()
            sessionOK = true
            log = "Pikmin WDA session READY\n\(sid)"
        } catch {
            sessionOK = false
            log = "Create session FAILED:\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func getScreenshot() async {
        do {
            screenshot = try await WDAClient.shared.screenshot()
            log = "Screenshot OK"
        } catch {
            log = "Screenshot FAILED:\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendTap() async {
        guard let x = Double(tapX),
              let y = Double(tapY) else {
            log = "Invalid x/y."
            return
        }

        do {
            try await WDAClient.shared.tap(x: x, y: y)
            log = "Tap sent: \(x), \(y)"
        } catch {
            log = "Tap FAILED:\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func sendSwipe() async {
        do {
            // Coordinates are WDA screen points, matching the 402x874 device dimensions
            // observed in the user's current setup.
            try await WDAClient.shared.swipe(
                fromX: 201,
                fromY: 680,
                toX: 201,
                toY: 320,
                duration: 0.45
            )
            log = "Swipe sent."
        } catch {
            log = "Swipe FAILED:\n\(error.localizedDescription)"
        }
    }
}
