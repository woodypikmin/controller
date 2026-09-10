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
                        Text("Pikmin Pilot")
                            .font(.largeTitle.bold())

                        Text("Stage 7.2.1 — Phone-local DVT Screenshot Probe")
                            .font(.headline)

                        Text("沿用已實機成功的 RPPairing → LocalDevVPN → RSD。這版改用 iOS 17+ DVT RemoteServer screenshot over RSD；沒有 WDA localhost:8100 fallback。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("1. Pairing Record") {
                    LabeledContent("狀態", value: pairing.status)

                    Button("匯入 RPPairing Record") { showImporter = true }

                    Button("VALIDATE WITH IDEVICE") {
                        Task { await validatePairing() }
                    }
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

                    Button("CONNECT PHONE-LOCAL RSD") {
                        Task { await connectRSD() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → TAKE SCREENSHOT") {
                        Task { await takeScreenshot() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → LAUNCH PIKMIN") {
                        Task { await launchPikmin() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    if busy {
                        HStack {
                            ProgressView()
                            Text("idevice 正在連線…")
                        }
                    }
                }

                if let screenshotImage {
                    Section("Phone-local Screenshot") {
                        Image(uiImage: screenshotImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("看到這張圖 = DVT Screenshot → RSD → phone-local tunnel 已經成功。因為按鈕是在 Pikmin Pilot 內按的，這個 probe 正常會先截到目前 iPhone 畫面。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Stage 7.2.1 測試順序") {
                    Text("1. 先開 LocalDevVPN。\n2. CONNECT PHONE-LOCAL RSD。\n3. PHONE-LOCAL → TAKE SCREENSHOT。\n4. 如果畫面成功顯示在 App 裡，把結果截圖給我。\n5. Tap / Swipe 下一版接 phone-local HID；不使用 WDA。")
                }

                Section("Bot Core") {
                    Label("Stage 5 card-first 水果辨識：保留", systemImage: "checkmark.circle.fill")
                    Label("粉紅 / 12 隻 / GO / X / LOOP：保留", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.2.1：phone-local DVT screenshot", systemImage: "camera.fill")
                    Label("下一關：phone-local HID tap/swipe", systemImage: "hand.tap.fill")
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

    @MainActor
    private func validatePairing() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.validatePairing()
        status = result.message
    }

    @MainActor
    private func connectRSD() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.probeRSD()
        status = result.message
    }

    @MainActor
    private func takeScreenshot() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PikminPilot-Stage7.2.1-Screenshot.png")
        try? FileManager.default.removeItem(at: outputURL)

        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.takeScreenshot(outputPath: outputURL.path)
        status = result.message

        if result.ok,
           let data = try? Data(contentsOf: outputURL),
           let image = UIImage(data: data) {
            screenshotImage = image
        } else {
            screenshotImage = nil
            if result.ok {
                status = "Screenshot bytes received, but UIKit could not decode image"
            }
        }
    }

    @MainActor
    private func launchPikmin() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.launchPikmin()
        status = result.message
    }
}
