
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

                Section("Stage 2.1 - Card OCR") {
                    Button("DETECT ONLY") {
                        probe.detectOnly()
                    }
                    .disabled(!sessionOK)

                    Text("""
                    COMPLETE / BUSY 改成讀整張卡片文字。
                    不再用紅蘋果、桃子的顏色判斷 BUSY。
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
                    GREEN = AVAILABLE
                    RED = BUSY (讀到時間)
                    BLUE = COMPLETE (讀到完成/領取)
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
            .navigationTitle("Controller 0.2.1")
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
