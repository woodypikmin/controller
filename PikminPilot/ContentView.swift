import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @StateObject private var pairing = PairingRecordStore()
    @StateObject private var loop = Stage8FullLoopController()
    @StateObject private var runnerPackage = RunnerPackageStore()

    // 0 = unlimited, -1 = custom, otherwise fixed dispatch count.
    @AppStorage("PikminPilot.RunPreset") private var runPreset = 10
    @AppStorage("PikminPilot.CustomRunTarget") private var customRunTarget = 30

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
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pikmin Pilot")
                            .font(.largeTitle.bold())
                        Text("Stage 10.1 — PILOT CONTROL UI")
                            .font(.headline)
                        Text("穩定 Stage 8.2.2 automation engine 不變。本版加入執行次數、兩種停止、進度/階段顯示與 Diagnostics 收納。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section("Pilot Control") {
                    Picker("搬運次數", selection: $runPreset) {
                        Text("1 次").tag(1)
                        Text("5 次").tag(5)
                        Text("10 次").tag(10)
                        Text("20 次").tag(20)
                        Text("自訂").tag(-1)
                        Text("無限").tag(0)
                    }
                    .disabled(loop.isRunning || busy)

                    if runPreset == -1 {
                        Stepper(
                            "自訂：\(customRunTarget) 次",
                            value: $customRunTarget,
                            in: 1...200
                        )
                        .disabled(loop.isRunning || busy)
                    }

                    if loop.isRunning {
                        LabeledContent("目前階段", value: loop.currentPhase)
                        LabeledContent("已完成", value: progressText)

                        if let target = loop.targetDispatches, target > 0 {
                            ProgressView(
                                value: Double(loop.completedDispatches),
                                total: Double(target)
                            )
                        } else {
                            HStack {
                                ProgressView()
                                Text("無限模式 • completed=\(loop.completedDispatches)")
                                    .font(.footnote)
                            }
                        }

                        Button {
                            loop.stopAfterCurrent()
                        } label: {
                            Label(
                                loop.stopAfterCurrentRequested ? "已要求：這輪完成後停止" : "STOP AFTER CURRENT",
                                systemImage: "stop.circle"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(loop.stopAfterCurrentRequested || loop.immediateStopRequested)

                        Button(role: .destructive) {
                            loop.stopNow()
                        } label: {
                            Label(
                                loop.immediateStopRequested ? "STOPPING…" : "STOP NOW",
                                systemImage: "xmark.octagon.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(loop.immediateStopRequested)

                        Text("STOP NOW 會立刻阻止後續新動作。若某個 XCTest 指令已經送出，或 Runner 正在執行單一 pink→12→GO→X critical tail，已在執行中的那個指令可能要返回後才完全停止。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task { await startStage101Auto() }
                        } label: {
                            Label("START PILOT", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || pairing.pairingURL == nil)

                        Text("先開 LocalDevVPN。START 會自動 probe RSD、確認/自動安裝 embedded Runner，然後進入完整水果 loop。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if busy && !loop.isRunning {
                        HStack {
                            ProgressView()
                            Text("準備 phone-local engine…")
                                .font(.footnote)
                        }
                    }
                }

                Section("Setup") {
                    LabeledContent("LocalDevVPN", value: "外部 App（先 Connect）")
                    LabeledContent("RSD", value: "10.7.0.1:49152")
                    LabeledContent("Pairing", value: pairing.status)
                    LabeledContent("Runner", value: runnerPackage.sourceLabel)
                    LabeledContent("Runner signing", value: runnerPackage.provisioningStatus)

                    Button("匯入 RPPairing Record") {
                        showPairingImporter = true
                    }
                    .disabled(loop.isRunning)

                    if pairing.pairingURL != nil {
                        Button("VALIDATE PAIRING") {
                            Task { await validatePairing() }
                        }
                        .disabled(busy || loop.isRunning)
                    }
                }

                Section("Status") {
                    HStack {
                        Text(loop.isRunning ? "LIVE LOG" : "LAST LOG")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            copyStatusToClipboard()
                        } label: {
                            Label(
                                statusCopied ? "COPIED" : "COPY LOG",
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
                }

                if let screenshotImage {
                    Section("Latest Screenshot") {
                        Image(uiImage: screenshotImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }

                Section {
                    DisclosureGroup("Diagnostics / Advanced") {
                        VStack(alignment: .leading, spacing: 10) {
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

                            Button("INSTALL / UPDATE EMBEDDED RUNNER") {
                                Task { await installAvailableRunner() }
                            }
                            .disabled(busy || loop.isRunning || pairing.pairingURL == nil || runnerPackage.runnerURL == nil)

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

                            Button("STAGE 8.0 → AVAILABLE FRUIT TAP") {
                                Task { await runStage8AvailableFruitTap() }
                            }
                            .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                            Button("DEBUG → START LOOP DIRECTLY") {
                                startStage81Loop()
                            }
                            .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                            Button("PHONE-LOCAL → LAUNCH PIKMIN") {
                                Task { await launchPikmin() }
                            }
                            .disabled(busy || loop.isRunning || pairing.pairingURL == nil)

                            Divider()

                            Button("IMPORT SIGNED RUNNER OVERRIDE") {
                                showRunnerImporter = true
                            }
                            .disabled(busy || loop.isRunning)

                            if runnerPackage.source == .importedOverride {
                                Button("移除 Runner override", role: .destructive) {
                                    try? runnerPackage.removeImportedOverride()
                                    status = "Runner override 已移除；已回到內建 Runner"
                                }
                                .disabled(loop.isRunning)
                            }

                            if pairing.pairingURL != nil {
                                Button("移除 Pairing Record", role: .destructive) {
                                    try? pairing.remove()
                                    screenshotImage = nil
                                    status = "Pairing Record 已移除"
                                }
                                .disabled(loop.isRunning)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section("Stable Engine") {
                    Label("Card-first AVAILABLE / BUSY / COMPLETE", systemImage: "checkmark.circle.fill")
                    Label("Pink → fixed 12 → GO → green X → loop", systemImage: "checkmark.circle.fill")
                    Label("Embedded Runner phone-local auto-bootstrap", systemImage: "checkmark.circle.fill")
                    Label("Run count + safe stop + STOP NOW", systemImage: "slider.horizontal.3")
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

    private var selectedRunTarget: Int? {
        switch runPreset {
        case 0:
            return nil
        case -1:
            return max(1, customRunTarget)
        default:
            return max(1, runPreset)
        }
    }

    private var progressText: String {
        if let target = loop.targetDispatches {
            return "\(loop.completedDispatches) / \(target)"
        }
        return "\(loop.completedDispatches) / ∞"
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
        status = "STAGE 10.1 RUNNER BOOTSTRAP • source=\(runnerPackage.sourceLabel) • AFC upload → InstallationProxy install…"

        let engine = IDeviceEngine(pairingPath: pairingURL.path)
        let rsd = await engine.probeRSD()
        guard rsd.ok else {
            status = "STAGE 10.1 RUNNER INSTALL FAILED • RSD offline • \(rsd.message)"
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
        status = "STAGE 10.1 START • LocalDevVPN → RSD → embedded Runner preflight → controlled stable loop"

        let engine = IDeviceEngine(pairingPath: url.path)
        let rsd = await engine.probeRSD()
        guard rsd.ok else {
            busy = false
            status = "STAGE 10.1 WAITING FOR LOCALDEVVPN • open/connect LocalDevVPN, then press START PILOT again • \(rsd.message)"
            return
        }

        status = "STAGE 10.1 • RSD ✅ • checking installed XCTest Runner…"
        var runner = await engine.discoverXCTestRunner()
        if !runner.ok {
            if runnerPackage.source == .embedded && runnerPackage.isEmbeddedRunnerExpired {
                busy = false
                status = "STAGE 10.1 RUNNER EXPIRED • embedded free-account provisioning has expired • \(runnerPackage.provisioningStatus) • refresh package before auto-install"
                return
            }

            if let package = runnerPackage.runnerURL {
                status = "STAGE 10.1 • Runner missing → auto-installing \(runnerPackage.sourceLabel) signed IPA via AFC + InstallationProxy…"
                let install = await engine.installXCTestRunnerIPA(localPath: package.path)
                guard install.ok else {
                    busy = false
                    status = "STAGE 10.1 FAILED • phase=runner-self-install • \(install.message)"
                    return
                }
                runner = await engine.discoverXCTestRunner()
                guard runner.ok else {
                    busy = false
                    status = "STAGE 10.1 FAILED • phase=runner-post-install-verify • \(runner.message)"
                    return
                }
                status = "STAGE 10.1 • Runner auto-bootstrap ✅ • source=\(runnerPackage.sourceLabel) • RSD ✅ • starting stable Stage 8.2.2 loop…"
            } else {
                busy = false
                status = "STAGE 10.1 PACKAGING ERROR • no installed Runner and embedded signed Runner is missing from App bundle • \(runner.message)"
                return
            }
        } else {
            status = "STAGE 10.1 • Runner ✅ • RSD ✅ • starting stable Stage 8.2.2 loop…"
        }

        busy = false
        loop.start(
            pairingPath: url.path,
            targetDispatches: selectedRunTarget,
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
            targetDispatches: selectedRunTarget,
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
