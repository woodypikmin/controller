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

                        Text("Stage 7.8 — XCTest Session Metadata")
                            .font(.headline)

                        Text("Stage 7.6 已實機確認 InstallationProxy 能找到已簽名安裝的 .xctrunner。這版會重新查 Runner bundle ID，接著用已成功的 phone-local CoreDevice AppService 直接啟動它。這一步只驗證 Runner process 可被手機端啟動；下一版再把 DTX session 和這個 Runner process 接起來執行 center tap。")
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
                    Text("1. Runner 已安裝而且 Stage 7.7 已顯示 LAUNCH SENT，所以 Runner 不必重裝。\n2. 只更新 Stage 7.8 主 App。\n3. 開 LocalDevVPN → CONNECT PHONE-LOCAL RSD。\n4. 按 PREPARE XCTEST SESSION METADATA。\n5. 成功會顯示 PHONE-LOCAL XCTEST METADATA READY，後面包含 runnerID / runnerPath / runnerContainer / testBundleURL / targetPath。\n6. 把整段狀態貼給我；下一版直接用這些真實路徑產生 .xctestconfiguration 並接 start test plan。")
                }

                Section("Bot Core") {
                    Label("Stage 5 card-first 水果辨識：保留", systemImage: "checkmark.circle.fill")
                    Label("粉紅 / 12 隻 / GO / X / LOOP：保留", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.2.1：phone-local DVT screenshot ✅", systemImage: "camera.fill")
                    Label("Stage 7.4：testmanagerd + dtservicehub service probe ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.5：DTX handshake bootstrap ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.6：real XCUITest Runner package + discovery ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.7：phone-local .xctrunner process launch ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.8：XCTest session metadata", systemImage: "doc.text.magnifyingglass")
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
