
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var probe = BackgroundProbe.shared

    @State private var log = "Ready."
    @State private var wdaOK = false
    @State private var sessionOK = false
    @State private var screenshot: UIImage?
    @State private var resultImage: UIImage?

    var body: some View {
        NavigationStack {
            Form {
                Section("Setup") {
                    Button("1. Check WDA") {
                        Task { await checkWDA() }
                    }

                    Button("2. Create GENERIC Session") {
                        Task { await createSession() }
                    }
                    .disabled(!wdaOK)

                    Text(sessionOK ? "SESSION READY" : "NO SESSION")
                        .foregroundStyle(sessionOK ? .green : .secondary)
                }

                Section("Background execution test") {
                    Button("TEST: launch Pikmin + screenshot after 5 sec") {
                        probe.run(delaySeconds: 5)
                    }
                    .disabled(!sessionOK)

                    Button("TEST: launch Pikmin + screenshot after 20 sec") {
                        probe.run(delaySeconds: 20)
                    }
                    .disabled(!sessionOK)

                    Text("""
                    按下後不要自己切回 Controller。
                    讓 Pikmin 留在前景至少超過測試秒數，
                    然後再手動回 Controller 看結果。
                    """)
                    .font(.caption)
                }

                Section("Saved background result") {
                    Button("Refresh Result") {
                        loadProbeResult()
                    }

                    Text(BackgroundProbe.savedStatus())
                        .font(.system(.caption, design: .monospaced))

                    if let resultImage {
                        Text("Screenshot captured by background Controller:")
                            .font(.caption)

                        Image(uiImage: resultImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 330)
                    }
                }

                Section("Log") {
                    Text(probe.state)
                        .font(.system(.caption, design: .monospaced))

                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Controller 0.1.4")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    loadProbeResult()
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
    private func createSession() async {
        do {
            let id = try await WDAClient.shared.createGenericSession()
            sessionOK = true
            log = "GENERIC SESSION OK\n\(id)"
        } catch {
            sessionOK = false
            log = "SESSION FAILED\n\(error.localizedDescription)"
        }
    }

    private func loadProbeResult() {
        let url = BackgroundProbe.resultURL

        if let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            resultImage = image
        } else {
            resultImage = nil
        }
    }
}
