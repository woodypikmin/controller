import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var pairing = PairingRecordStore()
    @StateObject private var loop = Stage8FullLoopController()

    @State private var showImporter = false
    @State private var status = "尚未測試"
    @State private var busy = false
    @State private var screenshotImage: UIImage?
    @State private var statusCopied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Pikmin Pilot")
                            .font(.largeTitle.bold())

                        Text("Stage 8.1.3 — GO / BACKGROUND STABILITY FIX")
                            .font(.headline)

                        Text("Stage 8.0 已實機證明 DVT screenshot → card-first AVAILABLE → dynamic XCTest tap。8.1 直接串回完整 Stage 5：AVAILABLE → 前往探險 → 粉紅 → 固定 12 隻 → GO → 搬運中綠色 X → 回列表 → 下一個。全程 phone-local RSD + DVT + XCTest，不使用 WDA localhost:8100。")
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
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("狀態")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                copyStatusToClipboard()
                            } label: {
                                Label(
                                    statusCopied ? "COPIED" : "COPY STATUS",
                                    systemImage: statusCopied ? "checkmark" : "doc.on.doc"
                                )
                                .font(.caption.bold())
                            }
                            .buttonStyle(.borderless)
                        }

                        Text(status)
                            .font(.footnote.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if isBootstrapFailure {
                            Label {
                                Text("Runner 的巢狀 .xctest 已能載入。7.8.5 專門驗證 input：不再 app.launch() 重啟 Pikmin；Runner 只接受已經在背景執行的 Pikmin，使用 activate() 帶回前景，等待 4 秒後只點一次畫面正中央。")
                                    .font(.footnote)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle.fill")
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 4)

                    Button("CONNECT PHONE-LOCAL RSD") {
                        Task { await connectRSD() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → TAKE SCREENSHOT") {
                        Task { await takeScreenshot() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("PROBE PHONE-LOCAL XCTEST SERVICES") {
                        Task { await probeXCTestServices() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("BOOTSTRAP PHONE-LOCAL XCTEST DTX") {
                        Task { await bootstrapXCTestDTX() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("FIND INSTALLED XCTEST RUNNER") {
                        Task { await discoverXCTestRunner() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("PHONE-LOCAL → LAUNCH XCTEST RUNNER") {
                        Task { await launchDiscoveredXCTestRunner() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("PREPARE XCTEST SESSION METADATA") {
                        Task { await prepareXCTestMetadata() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)


                    Button("RUN XCTEST → ACTIVATE + CENTER TAP") {
                        Task { await runXCTestCenterTap() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("STAGE 8.0 → DVT AVAILABLE FRUIT TAP") {
                        Task { await runStage8AvailableFruitTap() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    Button("STAGE 8.1.3 → START FULL LOOP") {
                        startStage81Loop()
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    if loop.isRunning {
                        Button("STOP LOOP AT SAFE CHECKPOINT", role: .destructive) {
                            loop.stop()
                        }

                        LabeledContent(
                            "已完成搬運",
                            value: "\(loop.completedDispatches)"
                        )
                    }

                    Button("PHONE-LOCAL → LAUNCH PIKMIN") {
                        Task { await launchPikmin() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                    if busy || loop.isRunning {
                        HStack {
                            ProgressView()
                            Text(loop.isRunning ? "Stage 8.1.3 自動搬運中…" : "idevice 正在連線…")
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

                Section("Stage 8.1.3 GO / BACKGROUND STABILITY FIX") {
                    Text("1. 開 LocalDevVPN。\n2. 先開 Pikmin Bloom，停在『探險水果列表』；不要 force quit。\n3. 回 Pikmin Pilot → CONNECT PHONE-LOCAL RSD。\n4. 按 STAGE 8.1.3 → START FULL LOOP。\n5. card-first：BUSY / COMPLETE 永遠不點，只選 AVAILABLE。\n6. 自動：水果 → 前往探險 → 粉紅 → 固定 12 隻 → GO → 搬運中綠色 X。\n7. 回水果列表後繼續掃描下一個 AVAILABLE；找不到安全水果就正常結束。\n8. iOS 背景時間不足時會短暫把 Pikmin Pilot 帶回前景更新 background window，再 activate 原本仍在執行的 Pikmin，不 cold-launch。\n9. 要停時按 STOP LOOP AT SAFE CHECKPOINT；COPY STATUS 可複製完整 round log。")
                }

                Section("Bot Core") {
                    Label("Stage 5 card-first 水果辨識：保留", systemImage: "checkmark.circle.fill")
                    Label("粉紅 / 12 隻 / GO / X / LOOP：保留", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.2.1：phone-local DVT screenshot ✅", systemImage: "camera.fill")
                    Label("Stage 7.4：testmanagerd + dtservicehub service probe ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.5：DTX handshake bootstrap ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.6：real XCUITest Runner package + discovery ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 7.7：phone-local .xctrunner process launch ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 8.0：AVAILABLE dynamic tap 實機成功 ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 8.1.3：fresh GO frame + background renewal race fix + calibrated green-X fallback", systemImage: "arrow.triangle.2.circlepath")
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


    private var isBootstrapFailure: Bool {
        let lower = status.lowercased()
        return lower.contains("test runner failed to bootstrap")
            || lower.contains("step=execute-test-plan")
            || lower.contains("archiveStrings=")
    }

    @MainActor
    private func copyStatusToClipboard() {
        UIPasteboard.general.string = status
        statusCopied = true

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            statusCopied = false
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
        status = "PHONE-LOCAL XCTEST CENTER TAP STARTING • mode=activate-no-relaunch • Pikmin must already be running…"

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
    private func runStage8AvailableFruitTap() async {
        guard let url = pairing.pairingURL else { return }

        busy = true
        status = "STAGE 8.0 STARTING • activate → DVT screenshot → card-first detect → dynamic XCTest tap"

        let backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "PikminPilot-Stage8-AvailableFruitTap",
            expirationHandler: nil
        )

        defer {
            if backgroundTask != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTask)
            }
            busy = false
        }

        let engine = IDeviceEngine(pairingPath: url.path)

        let activate = await engine.runXCTestActivateOnly()
        guard activate.ok else {
            status = "STAGE 8.0 FAILED • phase=activate • \(activate.message)"
            return
        }

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PikminPilot-Stage8-AvailableFruit.png")
        try? FileManager.default.removeItem(at: outputURL)

        let shot = await engine.takeScreenshot(outputPath: outputURL.path)
        guard shot.ok,
              let data = try? Data(contentsOf: outputURL),
              let image = UIImage(data: data),
              let cg = image.cgImage else {
            status = "STAGE 8.0 FAILED • phase=dvt-screenshot • \(shot.message)"
            return
        }

        let detection = await FruitDetector.detect(in: image)
        screenshotImage = FruitDetector.annotated(image: image, result: detection)

        let available = detection.fruits.sorted {
            if abs($0.center.y - $1.center.y) > 12 {
                return $0.center.y < $1.center.y
            }
            return $0.center.x < $1.center.x
        }

        let busyCards = detection.cards.filter { $0.state == .busy }.count
        let completeCards = detection.cards.filter { $0.state == .complete }.count

        guard let fruit = available.first else {
            status = "STAGE 8.0 STOPPED SAFELY • no AVAILABLE fruit • busyCards=\(busyCards) • completeCards=\(completeCards) • blockedObjects=\(detection.blockedObjects.count) • no tap sent"
            return
        }

        let normalizedX = Double(fruit.center.x) / Double(cg.width)
        let normalizedY = Double(fruit.center.y) / Double(cg.height)

        guard normalizedX >= 0, normalizedX <= 1,
              normalizedY >= 0, normalizedY <= 1 else {
            status = "STAGE 8.0 FAILED • detector produced invalid normalized coordinate x=\(normalizedX) y=\(normalizedY)"
            return
        }

        status = String(
            format: "STAGE 8.0 DETECTED AVAILABLE • label=%@ • pixel=(%.1f, %.1f) • normalized=(%.5f, %.5f) • busyCards=%d • completeCards=%d • sending XCTest tap…",
            fruit.labelText,
            fruit.center.x,
            fruit.center.y,
            normalizedX,
            normalizedY,
            busyCards,
            completeCards
        )

        let tap = await engine.runXCTestTap(
            normalizedX: normalizedX,
            normalizedY: normalizedY
        )

        if tap.ok {
            status = String(
                format: "STAGE 8.0 AVAILABLE FRUIT TAP COMPLETED • card-first=PASS • label=%@ • normalized=(%.5f, %.5f) • busyCards=%d • completeCards=%d • %@",
                fruit.labelText,
                normalizedX,
                normalizedY,
                busyCards,
                completeCards,
                tap.message
            )
        } else {
            status = "STAGE 8.0 FAILED • phase=xctest-dynamic-tap • \(tap.message)"
        }
    }

    @MainActor
    private func startStage81Loop() {
        guard let url = pairing.pairingURL else { return }

        loop.start(
            pairingPath: url.path,
            onStatus: { newStatus in
                status = newStatus
            },
            onScreenshot: { image in
                screenshotImage = image
            }
        )
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
