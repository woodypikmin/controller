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

                Section("3. Stage 7.3.4 iOS 26 Direct HID Probe") {
                    Button("PHONE-LOCAL → LAUNCH + TAP CENTER") {
                        Task { await launchAndTapCenter() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → LAUNCH + SWIPE UP") {
                        Task { await launchAndSwipeUp() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Text("iOS 26.6.1 沒有目前 Device Hub 路線需要的 displayservice。這版只做最後的 direct-HID probe：先自動切 Pikmin 到前景，再用正確 UIScreen 座標直接送 UniversalHID，不啟動 display gate。")
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

                Section("Stage 7.3.4 測試順序") {
                    Text("1. 開 LocalDevVPN。\n2. 先在 Pikmin Bloom 停在容易驗證點擊/滑動的畫面。\n3. 回 Pikmin Pilot。\n4. 按 LAUNCH + TAP CENTER 或 LAUNCH + SWIPE UP。\n5. Pilot 會自動把 Pikmin 切到前景，等待 1.5 秒，再用 display auth gate → UniversalHID 送事件。\n6. 約 2–3 秒後看 Pikmin 畫面是否真的有反應。\n7. 回 Pilot 時把狀態文字告訴我，尤其是 surface= 後面的值。")
                }

                Section("Bot Core") {
                    Label("RPPairing / RSD / Launch：實機成功", systemImage: "checkmark.circle.fill")
                    Label("DVT Screenshot：實機成功", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.3.4：iOS 26 direct UniversalHID probe (no display gate)", systemImage: "hand.tap.fill")
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
    @MainActor private func launchAndTapCenter() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }

        let bounds = UIScreen.main.bounds
        let x = UInt16(clamping: Int(bounds.midX.rounded()))
        let y = UInt16(clamping: Int(bounds.midY.rounded()))

        let backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "PikminPilot-HID-Tap",
            expirationHandler: nil
        )
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }

        let result = await IDeviceEngine(pairingPath: url.path)
            .launchAndTapPikmin(x: x, y: y)
        status = result.message
    }

    @MainActor private func launchAndSwipeUp() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }

        let bounds = UIScreen.main.bounds
        let x = UInt16(clamping: Int(bounds.midX.rounded()))
        let y1 = UInt16(clamping: Int((bounds.height * 0.72).rounded()))
        let y2 = UInt16(clamping: Int((bounds.height * 0.30).rounded()))

        let backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "PikminPilot-HID-Swipe",
            expirationHandler: nil
        )
        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
        }

        let result = await IDeviceEngine(pairingPath: url.path)
            .launchAndDragPikmin(
                x1: x, y1: y1,
                x2: x, y2: y2
            )
        status = result.message
    }

    @MainActor private func takeScreenshot() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PikminPilot-Stage7.3.4-Screenshot.png")
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
