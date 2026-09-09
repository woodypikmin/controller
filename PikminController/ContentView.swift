
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

                    Text(wdaOK ? "WDA: READY" : "WDA: NOT CHECKED")
                        .foregroundStyle(wdaOK ? .green : .secondary)
                }

                Section("2. Session diagnostics") {
                    Button("Create CONTROLLER Session") {
                        Task { await createControllerSession() }
                    }
                    .disabled(!wdaOK)

                    Text("先按這個。它不會切去 Pikmin，用來確認 WDA session 本身正常。")
                        .font(.caption)

                    Button("Create PIKMIN Session (wait up to 60s)") {
                        Task { await createPikminSession() }
                    }
                    .disabled(!wdaOK)

                    Text("這個可能會把 Pikmin Bloom 拉到前景。")
                        .font(.caption)
                }

                Section("3. Screenshot") {
                    Button("Get Screenshot") {
                        Task { await getScreenshot() }
                    }
                    .disabled(!wdaOK)

                    if let screenshot {
                        Image(uiImage: screenshot)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 320)
                    }
                }

                Section("Log") {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Pikmin Controller 0.1.1")
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
            log = "WDA FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func createControllerSession() async {
        log = "Creating CONTROLLER session...\nWait up to 60 seconds."

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
    private func createPikminSession() async {
        log = "Creating PIKMIN session...\nWait up to 60 seconds.\nIf Pikmin opens, that is important."

        do {
            let sid = try await WDAClient.shared.createPikminSession()
            sessionOK = true
            log = "PIKMIN SESSION OK\n\(sid)"
        } catch {
            sessionOK = false
            log = "PIKMIN SESSION FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func getScreenshot() async {
        do {
            screenshot = try await WDAClient.shared.screenshot()
            log = "SCREENSHOT OK"
        } catch {
            log = "SCREENSHOT FAILED\n\(error.localizedDescription)"
        }
    }
}
