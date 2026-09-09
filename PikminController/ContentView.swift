
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var probe = BotProbe.shared

    @State private var log = "Ready."
    @State private var wdaOK = false
    @State private var sessionOK = false
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

                Section("Stage 2 - On-device detection") {
                    Button("DETECT ONLY") {
                        probe.detectOnly()
                    }
                    .disabled(!sessionOK)

                    Text("""
                    會叫出 Pikmin，4 秒後由 Controller 在背景截圖並直接在 iPhone 內辨識。
                    不會點任何水果。
                    """)
                    .font(.caption)

                    Button("DETECT + TAP FIRST AVAILABLE") {
                        probe.detectAndTap()
                    }
                    .disabled(!sessionOK)

                    Text("""
                    只有確認 DETECT ONLY 正確後才按。
                    它會真的點第一顆判定為 AVAILABLE 的水果。
                    """)
                    .font(.caption)
                    .foregroundStyle(.red)
                }

                Section("Detection result") {
                    Button("Refresh Result") {
                        loadResult()
                    }

                    Text(savedStatus())
                        .font(.system(.caption, design: .monospaced))

                    Text("GREEN = AVAILABLE   RED = BUSY   BLUE = COMPLETE")
                        .font(.caption)

                    if let resultImage {
                        Image(uiImage: resultImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 420)
                    }
                }

                Section("Current") {
                    Text(probe.status)
                        .font(.system(.caption, design: .monospaced))
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .navigationTitle("Controller 0.2.0")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    loadResult()
                }
            }
        }
    }

    @MainActor
    private func checkWDA() async {
        do {
            try await WDAClient.shared.status()
            wdaOK = true
            log = "WDA OK"
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
            log = "SESSION OK\n\(id)"
        } catch {
            sessionOK = false
            log = "SESSION FAILED\n\(error.localizedDescription)"
        }
    }

    private func savedStatus() -> String {
        UserDefaults.standard.string(forKey: "stage2Status") ?? "(none)"
    }

    private func loadResult() {
        if let data = try? Data(contentsOf: BotProbe.resultURL),
           let image = UIImage(data: data) {
            resultImage = image
        }
    }
}
