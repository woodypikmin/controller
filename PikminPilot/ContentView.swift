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

                        Text("Stage 7.8 — XCTEST EXECUTE CENTER TAP")
                            .font(.headline)

                        Text("沿用已實機成功的 phone-local RSD、InstallationProxy、DTX bootstrap 與 Runner。這版把真正 XCTest lifecycle 串起來：TestConfig → testmanagerd ctrl/main → ProcessControl launch/authorize → XCTestDriverInterface → start test plan → testTapPikminCenter()。不使用 WDA localhost:8100。")
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

                    Button("PROBE PHONE-LOCAL XCTEST SERVICES") {
                        Task { await probeXCTestServices() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("BOOTSTRAP PHONE-LOCAL XCTEST DTX") {
                        Task { await bootstrapXCTestDTX() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("FIND INSTALLED XCTEST RUNNER") {
                        Task { await discoverXCTestRunner() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → LAUNCH XCTEST RUNNER") {
                        Task { await launchDiscoveredXCTestRunner() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)

                    Button("PREPARE XCTEST SESSION METADATA") {
                        Task { await prepareXCTestMetadata() }
                    }
                    .disabled(busy || pairing.pairingURL == nil)


                    Button("RUN XCTEST → PIKMIN CENTER TAP") {
                        Task { await runXCTestCenterTap() }
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

                Section("Stage 7.8 測試順序") {
                    Text("1. 開 LocalDevVPN。\n2. 先讓 Pikmin Bloom 停在正中央被點會明顯有反應的畫面。\n3. 回 Pikmin Pilot → CONNECT PHONE-LOCAL RSD。\n4. 按 RUN XCTEST → PIKMIN CENTER TAP。\n5. 不要手動切 App。Runner 應自動帶 Pikmin Bloom 到前景。\n6. 約 2 秒後觀察畫面中央是否真的被點。\n7. 測試後回 Pikmin Pilot，把最後狀態全文貼回來。\n\n理想狀態：PHONE-LOCAL XCTEST CENTER TAP COMPLETED • runner=... • pid=... • target=com.nianticlabs.pikmin")
                }

                Section("Bot Core") {
                    Label("Stage 5 card-first 水果辨識：保留", systemImage: "checkmark.circle.fill")
                    Label("粉紅 / 12 隻 / GO / X / LOOP：保留", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.2.1：phone-local DVT screenshot ✅", systemImage: "camera.fill")
                    Label("Stage 7.4：testmanagerd + dtservicehub service probe ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.5：DTX handshake bootstrap ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.6：real XCUITest Runner package + discovery ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.7：phone-local .xctrunner process launch ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.8：XCTest lifecycle + center tap", systemImage: "hand.tap.fill")
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
            .appendingPathComponent("PikminPilot-Stage7.4-Screenshot.png")
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
    private func prepareXCTestMetadata() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.prepareXCTestMetadata()
        status = result.message
    }


    @MainActor
    private func runXCTestCenterTap() async {
        guard let url = pairing.pairingURL else { return }

        busy = true
        status = "PHONE-LOCAL XCTEST CENTER TAP STARTING…"

        // Runner/Pikmin will take foreground. Keep Pikmin Pilot alive long
        // enough to maintain testmanagerd/DTX until this short test finishes.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "PikminPilot-XCTest-CenterTap",
            expirationHandler: nil
        )

        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            busy = false
        }

        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.runXCTestCenterTap()
        status = result.message
    }

    @MainActor
    private func launchDiscoveredXCTestRunner() async {
        guard let url = pairing.pairingURL else { return }

        busy = true
        defer { busy = false }

        let engine = IDeviceEngine(pairingPath: url.path)

        let discovery = await engine.discoverXCTestRunner()
        guard discovery.ok else {
            status = discovery.message
            return
        }

        // Stage 7.6 discovery format:
        // PHONE-LOCAL XCTEST RUNNER FOUND • bundle.id[ | bundle.id...] • N user apps scanned
        let parts = discovery.message.components(separatedBy: " • ")
        guard parts.count >= 2 else {
            status = "RUNNER FOUND but bundle ID parse failed • \(discovery.message)"
            return
        }

        let firstCandidate = parts[1]
            .components(separatedBy: " | ")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let bundleID = firstCandidate, !bundleID.isEmpty else {
            status = "RUNNER FOUND but bundle ID is empty • \(discovery.message)"
            return
        }

        let launch = await engine.launchBundleID(bundleID)
        status = launch.message
    }

    @MainActor
    private func discoverXCTestRunner() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.discoverXCTestRunner()
        status = result.message
    }

    @MainActor
    private func bootstrapXCTestDTX() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.bootstrapXCTestDTX()
        status = result.message
    }

    @MainActor
    private func probeXCTestServices() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        defer { busy = false }
        let engine = IDeviceEngine(pairingPath: url.path)
        let result = await engine.probeXCTestServices()
        status = result.message
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
