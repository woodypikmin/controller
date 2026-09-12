import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var pairing = PairingRecordStore()
    @StateObject private var loop = Stage8FullLoopController()
    @StateObject private var runnerPackage = RunnerPackageStore()

    @AppStorage("PikminPilot.RunMode") private var runMode = "5"
    @AppStorage("PikminPilot.CustomRunCount") private var customRunCount = 10
    @AppStorage("PikminPilot.PinkPikminCount") private var pinkPikminCount = 12
    @AppStorage("PikminPilot.SpeedMode") private var speedMode = "stable"

    @State private var showPairingImporter = false
    @State private var showRunnerImporter = false
    @State private var status = UserDefaults.standard.string(forKey: Stage8FullLoopController.persistedStatusKey) ?? "尚未執行"
    @State private var busy = false
    @State private var screenshotImage: UIImage?
    @State private var statusCopied = false
    @State private var showDiagnostics = false

    private var selectedTargetDispatches: Int? {
        switch runMode {
        case "1": return 1
        case "5": return 5
        case "10": return 10
        case "20": return 20
        case "custom": return max(1, customRunCount)
        default: return nil
        }
    }

    private var runGoalLabel: String {
        selectedTargetDispatches.map { "\($0) 顆" } ?? "無限循環"
    }

    private var isFastMode: Bool { speedMode == "fast" }

    private var runSummaryLabel: String {
        "\(runGoalLabel) • 每輪 \(pinkPikminCount) 隻粉紅 • \(isFastMode ? "快速" : "穩定")"
    }

    private var progressLabel: String {
        if let target = loop.targetDispatches ?? selectedTargetDispatches {
            return "\(min(loop.completedDispatches, target)) / \(target)"
        }
        return "已完成 \(loop.completedDispatches) 顆"
    }

    private var progressFraction: Double? {
        guard let target = loop.targetDispatches ?? selectedTargetDispatches, target > 0 else { return nil }
        return min(1, Double(loop.completedDispatches) / Double(target))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    runControlCard
                    liveStatusCard

                    if let screenshotImage {
                        screenshotCard(image: screenshotImage)
                    }

                    setupCard
                    diagnosticsCard
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Pikmin Pilot")
            .navigationBarTitleDisplayMode(.inline)
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
                        status = "SIGNED RUNNER OVERRIDE IMPORTED ✅ • START PILOT will prefer override"
                    } catch {
                        status = "Runner IPA 匯入失敗：\(error.localizedDescription)"
                    }
                case .failure(let error):
                    status = "Runner IPA 匯入失敗：\(error.localizedDescription)"
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "leaf.circle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pikmin Pilot")
                        .font(.title2.bold())
                    Text("Stage 10.2 • Pilot Dashboard")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                readinessBadge(
                    pairing.pairingURL != nil ? "Pairing ✓" : "Pairing !",
                    ok: pairing.pairingURL != nil
                )
                readinessBadge("LocalDevVPN 外部", ok: true)
                readinessBadge("Runner 內建", ok: runnerPackage.runnerURL != nil)
            }

            Text("先開 LocalDevVPN，再選擇搬運次數、每輪粉紅數量與速度。Runner 仍由 Pikmin Pilot 自動管理。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.green.opacity(0.16), Color.teal.opacity(0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.green.opacity(0.12), lineWidth: 1)
        )
    }

    private var runControlCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Pilot 設定", systemImage: "slider.horizontal.3")
                    .font(.headline)
                Spacer()
                Text(isFastMode ? "FAST" : "STABLE")
                    .font(.caption.bold())
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background((isFastMode ? Color.orange : Color.green).opacity(0.14), in: Capsule())
                    .foregroundStyle(isFastMode ? Color.orange : Color.green)
            }

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("搬運次數")
                            .fontWeight(.semibold)
                        Text("完成一顆並回列表 = 1 次")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("搬運次數", selection: $runMode) {
                        Text("1").tag("1")
                        Text("5").tag("5")
                        Text("10").tag("10")
                        Text("20").tag("20")
                        Text("自訂").tag("custom")
                        Text("∞").tag("infinite")
                    }
                    .labelsHidden()
                    .disabled(loop.isRunning || busy)
                }

                if runMode == "custom" {
                    Stepper(value: $customRunCount, in: 1...100) {
                        HStack {
                            Text("自訂次數")
                            Spacer()
                            Text("\(customRunCount) 顆")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                    .disabled(loop.isRunning || busy)
                }

                Divider()

                Stepper(value: $pinkPikminCount, in: 6...12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("每輪粉紅皮克敏")
                                .fontWeight(.semibold)
                            Text("每次 Run 固定使用同一數量")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(pinkPikminCount) 隻")
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(.pink)
                    }
                }
                .disabled(loop.isRunning || busy)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("速度")
                        .fontWeight(.semibold)
                    Picker("速度", selection: $speedMode) {
                        Text("穩定").tag("stable")
                        Text("快速").tag("fast")
                    }
                    .pickerStyle(.segmented)
                    .disabled(loop.isRunning || busy)
                    Text(isFastMode
                         ? "快速模式只縮短已驗證的等待與選取間隔；辨識重試與安全判定仍保留。"
                         : "穩定模式沿用目前已驗證成功的 Stage 8.2.2 節奏。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 8) {
                summaryPill(runGoalLabel, icon: "shippingbox")
                summaryPill("\(pinkPikminCount) 粉紅", icon: "leaf.fill")
                summaryPill(isFastMode ? "快速" : "穩定", icon: "speedometer")
            }

            if loop.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("進度")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(progressLabel)
                            .font(.headline.monospacedDigit())
                    }
                    if let progressFraction {
                        ProgressView(value: progressFraction)
                            .tint(.green)
                    } else {
                        ProgressView()
                            .tint(.green)
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        loop.stopAfterCurrent()
                    } label: {
                        Label("本輪後停止", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .disabled(loop.stopAfterCurrentRequested)

                    Button(role: .destructive) {
                        loop.stopNow()
                    } label: {
                        Label("立即停止", systemImage: "xmark.octagon.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("立即停止會阻止新的動作；若 pink→選取→GO→X 已送進單一 Runner session，該批次可能先完成才停止。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await startStage101Auto() }
                } label: {
                    VStack(spacing: 3) {
                        HStack {
                            if busy { ProgressView().padding(.trailing, 4) }
                            Label(busy ? "準備中…" : "START PILOT", systemImage: "play.fill")
                                .font(.headline)
                        }
                        if !busy {
                            Text(runSummaryLabel)
                                .font(.caption)
                                .opacity(0.9)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .disabled(busy || pairing.pairingURL == nil)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: Color.black.opacity(0.04), radius: 12, y: 5)
    }

    private var liveStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("目前狀態", systemImage: loop.isRunning ? "waveform.path.ecg" : "checkmark.circle")
                    .font(.headline)
                Spacer()
                if loop.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(loop.currentPhase)
                .font(.title3.bold())

            HStack {
                Text("已完成")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(loop.completedDispatches) 顆")
                    .font(.headline.monospacedDigit())
            }

            DisclosureGroup("技術紀錄 / COPY LOG") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Spacer()
                        Button {
                            copyStatusToClipboard()
                        } label: {
                            Label(statusCopied ? "COPIED" : "COPY LOG", systemImage: statusCopied ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    Text(status)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private func screenshotCard(image: UIImage) -> some View {
        DisclosureGroup("最近一次辨識畫面") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 8)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var setupCard: some View {
        DisclosureGroup("設定 / 安裝狀態") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Pairing", value: pairing.status)
                Button("匯入 RPPairing Record") { showPairingImporter = true }
                    .disabled(loop.isRunning || busy)

                Button("VALIDATE PAIRING") {
                    Task { await validatePairing() }
                }
                .disabled(loop.isRunning || busy || pairing.pairingURL == nil)

                Divider()

                LabeledContent("Runner package", value: runnerPackage.status)
                LabeledContent("Runner source", value: runnerPackage.sourceLabel)
                LabeledContent("Runner signing", value: runnerPackage.provisioningStatus)

                Text("Stage 10.2 的 6–12 粉紅與快速模式需要新版 Runner。這個開發版先用 GitHub 產出的 Stage 10.2 Runner 經既有 BAT 簽一次並更新；驗證後再把它重新內建，日常使用就不需要這一步。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("INSTALL / UPDATE EMBEDDED RUNNER") {
                    Task { await installAvailableRunner() }
                }
                .disabled(loop.isRunning || busy || pairing.pairingURL == nil || runnerPackage.runnerURL == nil)

                Button("IMPORT SIGNED RUNNER OVERRIDE") {
                    showRunnerImporter = true
                }
                .disabled(loop.isRunning || busy)

                if runnerPackage.source == .importedOverride {
                    Button("移除 Runner override", role: .destructive) {
                        try? runnerPackage.removeImportedOverride()
                        status = "Runner override 已移除；已回到內建 Runner"
                    }
                    .disabled(loop.isRunning || busy)
                }
            }
            .padding(.top, 8)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var diagnosticsCard: some View {
        DisclosureGroup(isExpanded: $showDiagnostics) {
            VStack(spacing: 10) {
                diagnosticButton("CONNECT PHONE-LOCAL RSD") { await connectRSD() }
                diagnosticButton("PHONE-LOCAL → TAKE SCREENSHOT") { await takeScreenshot() }
                diagnosticButton("PROBE PHONE-LOCAL XCTEST SERVICES") { await probeXCTestServices() }
                diagnosticButton("BOOTSTRAP PHONE-LOCAL XCTEST DTX") { await bootstrapXCTestDTX() }
                diagnosticButton("FIND INSTALLED XCTEST RUNNER") { await discoverXCTestRunner() }
                diagnosticButton("PHONE-LOCAL → LAUNCH XCTEST RUNNER") { await launchDiscoveredXCTestRunner() }
                diagnosticButton("PREPARE XCTEST SESSION METADATA") { await prepareXCTestMetadata() }
                diagnosticButton("RUN XCTEST → ACTIVATE + CENTER TAP") { await runXCTestCenterTap() }
                diagnosticButton("STAGE 8.0 → DVT AVAILABLE FRUIT TAP") { await runStage8AvailableFruitTap() }
                diagnosticButton("PHONE-LOCAL → LAUNCH PIKMIN") { await launchPikmin() }

                Button("DEBUG → START LOOP DIRECT") {
                    startStage81Loop()
                }
                .buttonStyle(.bordered)
                .disabled(busy || loop.isRunning || pairing.pairingURL == nil)
            }
            .padding(.top, 8)
        } label: {
            Label("Diagnostics", systemImage: "wrench.and.screwdriver")
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private func summaryPill(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }

    @ViewBuilder
    private func readinessBadge(_ text: String, ok: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(ok ? Color.green.opacity(0.13) : Color.orange.opacity(0.13), in: Capsule())
            .foregroundStyle(ok ? Color.green : Color.orange)
    }

    private func diagnosticButton(
        _ title: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button(title) {
            Task { await action() }
        }
        .buttonStyle(.bordered)
        .disabled(busy || loop.isRunning || pairing.pairingURL == nil)
        .frame(maxWidth: .infinity, alignment: .leading)
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
    private func installAvailableRunner() async {
        guard let pairingURL = pairing.pairingURL,
              let runnerURL = runnerPackage.runnerURL else { return }

        busy = true
        defer { busy = false }
        status = "STAGE 10.2 RUNNER BOOTSTRAP • source=\(runnerPackage.sourceLabel) • AFC upload → InstallationProxy install…"

        let engine = IDeviceEngine(pairingPath: pairingURL.path)
        let rsd = await engine.probeRSD()
        guard rsd.ok else {
            status = "STAGE 10.2 RUNNER INSTALL FAILED • RSD offline • \(rsd.message)"
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
    private func startStage101Auto() async {
        guard let url = pairing.pairingURL else { return }
        busy = true
        status = "STAGE 10.2 START • \(runSummaryLabel) • external LocalDevVPN → RSD → Runner → Stage 8.2.2 detector loop"

        let engine = IDeviceEngine(pairingPath: url.path)
        let rsd = await engine.probeRSD()
        guard rsd.ok else {
            busy = false
            status = "STAGE 10.2 WAITING FOR LOCALDEVVPN • open/connect LocalDevVPN, then press START PILOT again • \(rsd.message)"
            return
        }

        status = "STAGE 10.2 • RSD ✅ • checking installed XCTest Runner…"
        var runner = await engine.discoverXCTestRunner()
        if !runner.ok {
            if runnerPackage.source == .embedded && runnerPackage.isEmbeddedRunnerExpired {
                busy = false
                status = "STAGE 10.2 RUNNER EXPIRED • embedded free-account provisioning has expired • \(runnerPackage.provisioningStatus) • refresh package before auto-install"
                return
            }

            if let package = runnerPackage.runnerURL {
                status = "STAGE 10.2 • Runner missing → auto-installing \(runnerPackage.sourceLabel) signed IPA via AFC + InstallationProxy…"
                let install = await engine.installXCTestRunnerIPA(localPath: package.path)
                guard install.ok else {
                    busy = false
                    status = "STAGE 10.2 FAILED • phase=runner-self-install • \(install.message)"
                    return
                }
                runner = await engine.discoverXCTestRunner()
                guard runner.ok else {
                    busy = false
                    status = "STAGE 10.2 FAILED • phase=runner-post-install-verify • \(runner.message)"
                    return
                }
                status = "STAGE 10.2 • Runner auto-bootstrap ✅ • source=\(runnerPackage.sourceLabel) • RSD ✅ • starting stable Stage 8.2.2 loop…"
            } else {
                busy = false
                status = "STAGE 10.2 PACKAGING ERROR • no installed Runner and embedded signed Runner is missing from App bundle • \(runner.message)"
                return
            }
        } else {
            status = "STAGE 10.2 • Runner ✅ • RSD ✅ • starting stable Stage 8.2.2 loop…"
        }

        busy = false
        loop.start(
            pairingPath: url.path,
            targetDispatches: selectedTargetDispatches,
            pinkPikminCount: pinkPikminCount,
            fastMode: isFastMode,
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
            targetDispatches: selectedTargetDispatches,
            pinkPikminCount: pinkPikminCount,
            fastMode: isFastMode,
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
