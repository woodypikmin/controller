
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var pairing = PairingRecordStore()

    @State private var showImporter = false
    @State private var engineStatus = "尚未連線"
    @State private var isTestingEngine = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pikmin Pilot")
                            .font(.largeTitle.bold())

                        Text("Stage 7 — No-PC Runtime")
                            .font(.headline)

                        Text("成品方向：iPhone 內直接建立 Remote Pairing / RSD transport，不再依賴 Windows CMD 或 WDA localhost。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("Pairing") {
                    LabeledContent("狀態", value: pairing.status)

                    Button("匯入 Pairing Record") {
                        showImporter = true
                    }

                    if pairing.pairingURL != nil {
                        Button("移除 Pairing Record", role: .destructive) {
                            try? pairing.remove()
                        }
                    }
                }

                Section("Embedded Device Engine") {
                    LabeledContent("狀態", value: engineStatus)

                    Button {
                        Task {
                            await testEmbeddedEngine()
                        }
                    } label: {
                        if isTestingEngine {
                            HStack {
                                ProgressView()
                                Text("連線中…")
                            }
                        } else {
                            Text("TEST PHONE-LOCAL ENGINE")
                        }
                    }
                    .disabled(isTestingEngine || pairing.pairingURL == nil)

                    Text("這個按鈕不會偷偷連 127.0.0.1:8100。Stage 7 後續只允許手機端 embedded transport。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Bot Core") {
                    Label("水果辨識：保留 Stage 5", systemImage: "checkmark.circle.fill")
                    Label("粉紅篩選 / 12 隻 / GO / X：保留 Stage 5", systemImage: "checkmark.circle.fill")
                    Label("連續 LOOP：保留 Stage 5", systemImage: "checkmark.circle.fill")
                    Label("手機端 transport：Stage 7.1 接線中", systemImage: "hammer.fill")
                }

                Section("成品目標") {
                    Text("安裝 Pikmin Pilot → 首次匯入 pairing → 之後直接按 RUN。平常執行不接 Windows。")
                }
            }
            .navigationTitle("Pikmin Pilot")
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data, .propertyList, .xml],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try pairing.importRecord(from: url)
                        engineStatus = "Pairing Record 已載入"
                    } catch {
                        engineStatus = "匯入失敗：\(error.localizedDescription)"
                    }

                case .failure(let error):
                    engineStatus = "匯入失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func testEmbeddedEngine() async {
        guard let url = pairing.pairingURL else {
            engineStatus = "缺少 Pairing Record"
            return
        }

        isTestingEngine = true
        defer { isTestingEngine = false }

        let transport = EmbeddedDeviceTransport(pairingRecordPath: url.path)

        do {
            try await transport.connect()
            engineStatus = "PHONE-LOCAL ENGINE ONLINE"
        } catch {
            engineStatus = error.localizedDescription
        }
    }
}
