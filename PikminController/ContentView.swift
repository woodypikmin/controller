
import SwiftUI

struct ContentView: View {
    @State private var log = "Ready."
    @State private var wdaOK = false
    @State private var sessionOK = false
    @State private var screenshot: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section("1. WDA") {
                    Button("Check WDA") {
                        Task { await checkWDA() }
                    }
                    Text(wdaOK ? "READY" : "NOT READY")
                        .foregroundStyle(wdaOK ? .green : .secondary)
                }

                Section("2. Create session") {
                    Button("Create CONTROLLER Session") {
                        Task { await controllerSession() }
                    }
                    .disabled(!wdaOK)

                    Text(sessionOK ? "SESSION READY" : "NO SESSION")
                        .foregroundStyle(sessionOK ? .green : .secondary)
                }

                Section("3. Pikmin launch test") {
                    Button("CHECK Pikmin State") {
                        Task { await state() }
                    }
                    .disabled(!sessionOK)

                    Button("LAUNCH PIKMIN THROUGH WDA") {
                        Task { await launch() }
                    }
                    .disabled(!sessionOK)

                    Text("""
                    按 LAUNCH 後如果 Controller 被切到背景、Pikmin 跳到前景，
                    就算 Controller 沒收到最後 HTTP response，也算這一步成功。
                    """)
                    .font(.caption)
                }

                Section("Screenshot") {
                    Button("Get WDA Screenshot") {
                        Task { await shot() }
                    }
                    .disabled(!wdaOK)

                    if let screenshot {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 300)
                    }
                }

                Section("Log") {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Controller 0.1.2")
        }
    }

    @MainActor
    private func checkWDA() async {
        do {
            log = try await WDAClient.shared.status()
            wdaOK = true
        } catch {
            wdaOK = false
            log = "WDA FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func controllerSession() async {
        log = "Creating Controller session..."
        do {
            let sid = try await WDAClient.shared.createControllerSession()
            sessionOK = true
            log = "CONTROLLER SESSION OK\n\(sid)"
        } catch {
            sessionOK = false
            log = "CONTROLLER SESSION FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func state() async {
        do {
            log = "PIKMIN STATE\n" + (try await WDAClient.shared.pikminState())
        } catch {
            log = "STATE FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func launch() async {
        log = "Sending WDA launch command for Pikmin..."
        do {
            try await WDAClient.shared.launchPikmin()
            log = "WDA says Pikmin launch command succeeded."
        } catch {
            log = "LAUNCH request ended with:\n\(error.localizedDescription)\n\nIf Pikmin opened anyway, report that as SUCCESS."
        }
    }

    @MainActor
    private func shot() async {
        do {
            screenshot = try await WDAClient.shared.screenshot()
            log = "SCREENSHOT OK"
        } catch {
            log = "SCREENSHOT FAILED\n\(error.localizedDescription)"
        }
    }
}
