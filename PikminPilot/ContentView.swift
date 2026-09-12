import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var pairing = PairingRecordStore()
    @StateObject private var tunnel = PikminTunnelManager.shared
    @StateObject private var loop = Stage8FullLoopController()
    @StateObject private var runnerPackage = RunnerPackageStore()

    @State private var showPairingImporter = false
    @State private var showRunnerImporter = false
    @State private var status = UserDefaults.standard.string(forKey: Stage8FullLoopController.persistedStatusKey) ?? "尚未測試"
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

                        Text("Stage 9.1 — PHONE-LOCAL RUNNER SELF-INSTALL")
                            .font(.headline)

                        Text("保留已實機跑順的 Stage 8.2.2 完整 loop。這版新增 iPhone 本機 AFC + InstallationProxy 安裝 Runner 的路徑：先匯入一個已簽名 Runner IPA，Pikmin Pilot 自己就能安裝/更新 Runner。這是往最終單一安裝包收斂的關鍵 bootstrap。WDA 仍為 OFF。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                Section("0. Local Tunnel / Signing Diagnostics") {
                    LabeledContent("Tunnel", value: tunnel.state.rawValue)
                    LabeledContent("Provider", value: tunnel.providerBundleID)
                    LabeledContent("Interface", value: tunnel.interfaceCIDR)
                    LabeledContent("Phone peer", value: tunnel.peerCIDR)

                    Text(tunnel.detail)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button("TRY INTEGRATED TUNNEL") {
                        Task { await startIntegratedTunnel() }
                    }
                    .disabled(busy || loop.isRunning)

                    if tunnel.state == .connected || tunnel.state == .connecting {
                        Button("STOP INTEGRATED TUNNEL", role: .destructive) {
                            tunnel.stop()
                        }
                        .disabled(loop.isRunning)
                    }

                    Text("重要：把 entitlement 寫進原始碼並不代表 Sideloadly 的 provisioning profile 會授權它。若顯示 NEConfigurationErrorDomain Code=10 / permission denied，代表目前簽章沒有 Network Extension 權限；這不是 RSD/loop engine 壞掉。開發期可繼續使用 App Store LocalDevVPN，START PILOT 會自動 fallback。未來 TestFlight/正式簽章會再啟用內建 Tunnel。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("1. Pairing Record") {
                    LabeledContent("狀態", value: pairing.status)

                    Button("匯入 RPPairing Record") { showPairingImporter = true }

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

                Section("2. Runner Bootstrap / Single-Install Path") {
                    LabeledContent("Runner package", value: runnerPackage.status)

                    Button("IMPORT SIGNED RUNNER IPA") {
                        showRunnerImporter = true
                    }
                    .disabled(busy || loop.isRunning)

                    Button("PHONE-LOCAL → INSTALL / UPDATE RUNNER") {
                        Task { await installImportedRunner() }
                    }
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil || runnerPackage.runnerURL == nil)

                    if runnerPackage.runnerURL != nil {
                        Button("移除已匯入 Runner IPA", role: .destructive) {
                            try? runnerPackage.remove()
                            status = "已移除 Pikmin Pilot 內保存的 Runner IPA"
                        }
                        .disabled(loop.isRunning)
                    }

                    Text("Stage 9.1 先證明：Runner 不需要再由電腦執行安裝動作。Pikmin Pilot 會用既有 phone-local RSD，透過 AFC 上傳到 PublicStaging，再由 InstallationProxy 安裝。之後把 signed Runner 直接內嵌進最終包，就能把這個匯入步驟也消掉。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("3. Phone-local Engine") {
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

                    Button("STAGE 9.1 → START PILOT") {
                        Task { await startStage91Auto() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

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

                    Button("DEBUG → START LOOP (TUNNEL ALREADY READY)") {
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
                            Text(loop.isRunning ? "Stage 9.1 自動搬運中…" : "Pikmin Pilot 正在準備 phone-local engine…")
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

                Section("Stage 9.1 Test") {
                    Text("1. 開發期仍先開目前可用的 LocalDevVPN。\n2. Runner 已安裝的人可以直接按 START PILOT，不需要重裝。\n3. 要測新的 self-install：用新版 BAT 產生 *-SIGNED.ipa，放到 iPhone Files，按 IMPORT SIGNED RUNNER IPA，再按 PHONE-LOCAL → INSTALL / UPDATE RUNNER。\n4. START PILOT 現在會先確認 Runner；若 Runner 缺少但已匯入 signed IPA，它會自動 phone-local 安裝，再開始穩定的 Stage 8.2.2 loop。")
                }

                Section("Credits") {
                    Text("Integrated loopback tunnel behavior is based on LocalDevVPN / StosVPN by the SideStore Team and contributors (jkcoxson, Stossy11). License text is included in THIRD_PARTY_LOCALDEVVPN_LICENSE.txt. Pikmin Pilot remains a separate project and does not reuse LocalDevVPN branding.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Label("Stage 8.2.2：完整 loop 實機穩定 ✅", systemImage: "checkmark.circle.fill")
                    Label("Stage 9.0.1：Network Extension entitlement-aware + external LocalDevVPN fallback", systemImage: "network")
                    Label("Stage 9.1：AFC + InstallationProxy phone-local Runner self-install", systemImage: "shippingbox.fill")
                }
            }
            .navigationTitle("Pikmin Pilot")
            .fileImporter(
                isPresented: $showPairingImporter,
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
            .fileImporter(
                isPresented: $showRunnerImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        try runnerPackage.importIPA(from: url)
                        status = "SIGNED RUNNER IPA IMPORTED ✅ • ready for phone-local install"
                    } catch {
                        status = "Runner IPA 匯入失敗：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    status = "Runner IPA 匯入失敗：\(error.localizedDescription)"
                }
            }
        }
        .task {
            await tunnel.refresh()
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
    private func startIntegratedTunnel() async {
        busy = true
        status = "STAGE 9.1 TUNNEL • attempting embedded PacketTunnelProvider…"
        defer { busy = false }

        do {
            try await tunnel.ensureStarted()
            status = "STAGE 9.1 TUNNEL CONNECTED ✅ • provider=\(tunnel.providerBundleID) • iface=\(tunnel.interfaceCIDR) • peer=\(tunnel.peerCIDR)"
        } catch {
            await tunnel.refresh()
            let diagnostic = tunnel.diagnostics(for: error)
            if tunnel.isLikelyMissingNetworkExtensionEntitlement(error) {
                status = "STAGE 9.1 INTEGRATED TUNNEL UNAVAILABLE • signing/provisioning lacks Network Extension entitlement • \(diagnostic) • development fallback=use App Store LocalDevVPN"
            } else {
                status = "STAGE 9.1 TUNNEL FAILED • \(diagnostic) • tunnel=\(tunnel.detail)"
            }
        }
    }

    @MainActor
    private func installImportedRunner() async {
        guard let pairingURL = pairing.pairingURL,
              let runnerURL = runnerPackage.runnerURL else { return }

        busy = true
        defer { busy = false }
        status = "STAGE 9.1 RUNNER BOOTSTRAP • AFC upload → InstallationProxy install…"

        let engine = IDeviceEngine(pairingPath: pairingURL.path)
        let rsd = await engine.probeRSD()
        guard rsd.ok else {
            status = "STAGE 9.1 RUNNER INSTALL FAILED • RSD offline • \(rsd.message)"
            return
        }

        let install = await engine.installXCTestRunnerIPA(localPath: runnerURL.path)
        guard install.ok else {
            status = install.message
            return
        }

        let verify = await engine.discoverXCTestRunner()
        status = verify.ok
            ? "\(install.message) • verify=\(verify.message)"
            : "\(install.message) • POST-INSTALL VERIFY FAILED • \(verify.message)"
    }

    @MainActor
    private func startStage91Auto() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        status = "STAGE 9.1 START • tunnel → RSD → Runner preflight/self-install → stable 8.2.2 loop"

        var integratedConnected = false
        do {
            try await tunnel.ensureStarted()
            integratedConnected = true
            status = "STAGE 9.1 • integrated tunnel CONNECTED ✅ • probing RSD…"
        } catch {
            let diagnostic = tunnel.diagnostics(for: error)
            if tunnel.isLikelyMissingNetworkExtensionEntitlement(error) {
                status = "STAGE 9.1 • integrated tunnel blocked by current signing • probing existing LocalDevVPN path… • \(diagnostic)"
            } else {
                status = "STAGE 9.1 • integrated tunnel unavailable • probing existing 10.7.0.1 path… • \(diagnostic)"
            }
        }

        let engine = IDeviceEngine(pairingPath: url.path)
        let rsd = await engine.probeRSD()
        guard rsd.ok else {
            busy = false
            status = integratedConnected
                ? "STAGE 9.1 FAILED • phase=RSD-after-integrated-tunnel • \(rsd.message)"
                : "STAGE 9.1 WAITING FOR LOCAL TUNNEL • open/connect LocalDevVPN, then START PILOT again • \(rsd.message)"
            return
        }

        status = "STAGE 9.1 • RSD ✅ • checking installed XCTest Runner…"
        var runner = await engine.discoverXCTestRunner()
        if !runner.ok {
            if let imported = runnerPackage.runnerURL {
                status = "STAGE 9.1 • Runner missing → self-installing imported signed IPA via AFC + InstallationProxy…"
                let install = await engine.installXCTestRunnerIPA(localPath: imported.path)
                guard install.ok else {
                    busy = false
                    status = "STAGE 9.1 FAILED • phase=runner-self-install • \(install.message)"
                    return
                }
                runner = await engine.discoverXCTestRunner()
                guard runner.ok else {
                    busy = false
                    status = "STAGE 9.1 FAILED • phase=runner-post-install-verify • \(runner.message)"
                    return
                }
                status = "STAGE 9.1 • Runner self-install ✅ • RSD ✅ • starting stable Stage 8.2.2 loop…"
            } else {
                busy = false
                status = "STAGE 9.1 NEEDS RUNNER • no installed Runner and no signed Runner IPA imported • use IMPORT SIGNED RUNNER IPA once, then START PILOT again • \(runner.message)"
                return
            }
        } else {
            status = "STAGE 9.1 • Runner ✅ • RSD ✅ • starting stable Stage 8.2.2 loop…"
        }

        busy = false
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
