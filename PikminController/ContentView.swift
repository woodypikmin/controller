
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

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

                    Text(wdaOK ? "WDA READY" : "WDA NOT CHECKED")
                        .foregroundStyle(wdaOK ? .green : .secondary)
                }

                Section("2. Generic session") {
                    Button("Create GENERIC WDA Session") {
                        Task { await createGenericSession() }
                    }
                    .disabled(!wdaOK)

                    Text("""
                    這次不指定任何 bundleId，
                    所以 WDA 不會把 Controller 自己重開。
                    """)
                    .font(.caption)

                    Text(sessionOK ? "SESSION READY" : "NO SESSION")
                        .foregroundStyle(sessionOK ? .green : .secondary)
                }

                Section("3. Verify session") {
                    Button("Get Active App Info") {
                        Task { await activeInfo() }
                    }
                    .disabled(!sessionOK)
                }

                Section("4. Launch Pikmin") {
                    Button("LAUNCH PIKMIN") {
                        Task { await launchPikmin() }
                    }
                    .disabled(!sessionOK)

                    Text("""
                    如果按下後 Pikmin Bloom 跳到前景，
                    就算 Controller 被切到背景也算這一步成功。
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
                            .frame(maxHeight: 280)
                    }
                }

                Section("Persisted diagnostics") {
                    Button("Refresh Saved Result") {
                        refreshPersisted()
                    }

                    Text(savedDiagnosticText())
                        .font(.system(.caption, design: .monospaced))
                }

                Section("Log") {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Controller 0.1.3")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    if WDAClientSync.restorePossible {
                        sessionOK = true
                    }
                    refreshPersisted()
                }
            }
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
    private func createGenericSession() async {
        log = "Creating GENERIC session..."

        do {
            let id = try await WDAClient.shared.createGenericSession()
            sessionOK = true
            log = "GENERIC SESSION OK\n\(id)"
        } catch {
            sessionOK = false
            log = "GENERIC SESSION FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func activeInfo() async {
        do {
            log = "ACTIVE APP\n" + (try await WDAClient.shared.activeAppInfo())
        } catch {
            log = "ACTIVE APP FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func launchPikmin() async {
        log = "Launch command sent. Watch what the PHONE does."

        do {
            try await WDAClient.shared.launchPikmin()
            log = "WDA returned HTTP success for Pikmin launch."
        } catch {
            log = """
            Launch request ended with:
            \(error.localizedDescription)

            If Pikmin opened anyway, the launch itself succeeded.
            """
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

    private func refreshPersisted() {
        if UserDefaults.standard.string(forKey: "lastWDASessionId") != nil {
            sessionOK = true
        }
    }

    private func savedDiagnosticText() -> String {
        let defaults = UserDefaults.standard
        let sid = defaults.string(forKey: "lastWDASessionId") ?? "(none)"
        let sent = defaults.double(forKey: "pikminLaunchSentAt")
        let got200 = defaults.bool(forKey: "pikminLaunchGotHTTP200")

        var parts = [
            "saved session: \(sid)",
            "launch HTTP 200: \(got200)"
        ]

        if sent > 0 {
            parts.append("launch request timestamp: \(sent)")
        } else {
            parts.append("launch request: not sent")
        }

        return parts.joined(separator: "\n")
    }
}

// Tiny synchronous helper only for restoring UI state.
enum WDAClientSync {
    static var restorePossible: Bool {
        let value = UserDefaults.standard.string(forKey: "lastWDASessionId")
        return !(value ?? "").isEmpty
    }
}
