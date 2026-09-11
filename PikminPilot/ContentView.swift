import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var pairing = PairingRecordStore()
    @State private var showImporter = false
    @State private var status = "尚未測試"
    @State private var busy = false
    @State private var screenshotImage: UIImage?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Pikmin Pilot").font(.largeTitle.bold())
                        Text("Stage 7.3.1 — Phone-local CoreDevice HID")
                            .font(.headline)
                        Text("Screenshot 已實機成功。這版新增 UniversalHID Tap / Drag；每次觸控前都會先建立 display media auth gate。沒有 WDA localhost:8100 fallback。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("1. Pairing Record") {
                    LabeledContent("狀態", value: pairing.status)
                    Button("匯入 RPPairing Record") { showImporter = true }
                    Button("VALIDATE WITH IDEVICE") { Task { await validatePairing() } }
                        .disabled(busy || pairing.pairingURL == nil)
                    if pairing.pairingURL != nil {
                        Button("移除 Pairing Record", role: .destructive) {
                            try? pairing.remove()
                            screenshotImage = nil
                            status = "Pairing Record 已移除"
                        }
                    }
                }

                Section("2. Phone-local Engine") {
                    LabeledContent("目標", value: "10.7.0.1:49152")
                    LabeledContent("狀態", value: status)

                    Button("CONNECT PHONE-LOCAL RSD") { Task { await connectRSD() } }
                        .disabled(busy || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → TAKE SCREENSHOT") { Task { await takeScreenshot() } }
                        .disabled(busy || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → LAUNCH PIKMIN") { Task { await launchPikmin() } }
                        .disabled(busy || pairing.pairingURL == nil)

                    if busy {
                        HStack { ProgressView(); Text("phone-local engine 正在工作…") }
                    }
                }

                Section("3. Stage 7.3.1 HID Test") {
                    Button("PHONE-LOCAL → TAP CENTER") {
                        Task { await tapCenter() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → SWIPE UP") {
                        Task { await swipeUp() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Text("TAP CENTER = 正中央 (32768,32768)。SWIPE UP = 從畫面中央偏下往中央偏上拖約 0.6 秒。請先把 Pikmin Bloom 留在一個容易看出反應的畫面再測。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let screenshotImage {
                    Section("Phone-local Screenshot") {
                        Image(uiImage: screenshotImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Section("Stage 7.3.1 測試順序") {
                    Text("1. 開 LocalDevVPN。\n2. CONNECT PHONE-LOCAL RSD。\n3. LAUNCH PIKMIN。\n4. 切到 Pikmin Bloom，停在可看出滑動/點擊的畫面。\n5. 回 Pikmin Pilot 按 TAP CENTER 或 SWIPE UP。\n6. Pikmin Pilot 會透過 phone-local RSD → display auth gate → UniversalHID 送事件。\n7. 告訴我遊戲是否真的有被點/滑，以及狀態文字。")
                }

                Section("Bot Core") {
                    Label("RPPairing / RSD / Launch：實機成功", systemImage: "checkmark.circle.fill")
                    Label("DVT Screenshot：實機成功", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.3.1：UniversalHID tap/swipe probe", systemImage: "hand.tap.fill")
                    Label("下一關：把 Stage 5 card-first + 12 粉紅 + GO + X + LOOP 搬入", systemImage: "arrow.forward.circle")
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
                        screenshotImage = nil
                        status = "Pairing Record 已匯入，請 Validate"
                    } catch {
                        status = "匯入失敗：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    status = "匯入失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor private func withEngine(_ operation: @escaping (IDeviceEngine) async -> IDeviceEngine.Result) async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let result = await operation(IDeviceEngine(pairingPath: url.path))
        status = result.message
    }

    @MainActor private func validatePairing() async { await withEngine { await $0.validatePairing() } }
    @MainActor private func connectRSD() async { await withEngine { await $0.probeRSD() } }
    @MainActor private func launchPikmin() async { await withEngine { await $0.launchPikmin() } }
    @MainActor private func tapCenter() async { await withEngine { await $0.tap(x: 32768, y: 32768) } }

    @MainActor private func swipeUp() async {
        await withEngine {
            await $0.drag(x1: 32768, y1: 48000, x2: 32768, y2: 18000)
        }
    }

    @MainActor private func takeScreenshot() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PikminPilot-Stage7.3.1-Screenshot.png")
        try? FileManager.default.removeItem(at: outputURL)
        let result = await IDeviceEngine(pairingPath: url.path).takeScreenshot(outputPath: outputURL.path)
        status = result.message
        if result.ok,
           let data = try? Data(contentsOf: outputURL),
           let image = UIImage(data: data) {
            screenshotImage = image
        } else if result.ok {
            screenshotImage = nil
            status = "Screenshot bytes received, but UIKit could not decode image"
        }
    }
}
