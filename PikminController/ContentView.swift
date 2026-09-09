
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

                Section("Stage 2.3 - Real Card Pairing") {
                    Button("DETECT ONLY") {
                        probe.detectOnly()
                    }
                    .disabled(!sessionOK)

                    Text("""
                    先判斷水果外面有沒有「狀態卡外框」。
                    沒外框 = AVAILABLE；只有有外框才看上方時間/完成文字。
                    """)
                    .font(.caption)

                    Button("DETECT + TAP FIRST AVAILABLE") {
                        probe.detectAndTap()
                    }
                    .disabled(!sessionOK)
                }

                Section("Result") {
                    Button("Refresh Result") {
                        loadResult()
                    }

                    Text("""
                    GREEN = AVAILABLE（普通水果）
                    RED = BUSY（完整淡粉狀態卡）
                    BLUE = COMPLETE（完整淡綠完成卡）
                    """)
                    .font(.caption)

                    Text(savedStatus())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    if let resultImage {
                        Image(uiImage: resultImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 430)
                    }
                }

                Section("Current") {
                    Text(probe.status)
                        .font(.system(.caption, design: .monospaced))
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                }
            }
            .navigationTitle("Controller 0.2.3")
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
        UserDefaults.standard.string(
            forKey: "stage2Status"
        ) ?? "(none)"
    }

    private func loadResult() {
        if let data = try? Data(contentsOf: BotProbe.resultURL),
           let image = UIImage(data: data) {
            resultImage = image
        }
    }
}
