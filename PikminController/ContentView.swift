
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @StateObject private var detectProbe =
        BotProbe.shared

    @StateObject private var stage61Probe =
        Stage61Probe.shared

@StateObject private var loopProbe =
        ContinuousLoopProbe.shared

    @State private var log =
        "Ready."

    @State private var wdaOK =
        false

    @State private var sessionOK =
        false

    @State private var finalImage:
        UIImage?

    // 0 = unlimited
    @State private var selectedLimit =
        0

    @State private var hideControllerFlash =
        true

private let loopLimits:
        [
            (
                label: String,
                value: Int
            )
        ] = [
            ("無限", 0),
            ("5 次", 5),
            ("10 次", 10),
            ("20 次", 20),
            ("50 次", 50)
        ]

    var body: some View {
        ZStack {
            NavigationStack {
                Form {
                    Section("Stage 6.1 - XCTest Probe") {
                        Button(
                            "RUN XTEST CAPABILITY PROBE"
                        ) {
                            stage61Probe
                                .run()
                        }
                        .disabled(
                            stage61Probe.isRunning ||
                            loopProbe.isRunning
                        )

                        Text(
                            stage61Probe.status
                        )
                        .font(
                            .system(
                                .caption,
                                design:
                                    .monospaced
                            )
                        )
                        .textSelection(
                            .enabled
                        )

                        DisclosureGroup(
                            "Raw probe JSON"
                        ) {
                            Text(
                                stage61Probe.rawJSON
                            )
                            .font(
                                .system(
                                    .caption2,
                                    design:
                                        .monospaced
                                )
                            )
                            .textSelection(
                                .enabled
                            )
                        }

                        Text("""
                        這版不會啟動 WDA，也不會呼叫 Stage 6.0 那個會閃退的 private launcher。
                        只檢查 XCTest/UIAutomation runtime 與 testmanagerd 是否能從普通 Controller App 看見。
                        """)
                        .font(.caption)
                    }

                    Section("Setup") {
                        Button(
                            "1. Check WDA"
                        ) {
                            Task {
                                await checkWDA()
                            }
                        }

                        Button(
                            "2. Create GENERIC Session"
                        ) {
                            Task {
                                await createSession()
                            }
                        }
                        .disabled(!wdaOK)

                        Text(
                            sessionOK
                            ? "SESSION READY"
                            : "NO SESSION"
                        )
                        .foregroundStyle(
                            sessionOK
                            ? .green
                            : .secondary
                        )
                    }

                    Section("Loop Controls") {
                        Picker(
                            "派遣次數",
                            selection:
                                $selectedLimit
                        ) {
                            ForEach(
                                loopLimits,
                                id:
                                    \.value
                            ) {
                                option in

                                Text(
                                    option.label
                                )
                                .tag(
                                    option.value
                                )
                            }
                        }

                        Toggle(
                            "隱藏 Controller 切換",
                            isOn:
                                $hideControllerFlash
                        )

                        Text(
                            hideControllerFlash
                            ? "每輪續命時用 Pikmin 截圖蓋住 Controller，並在取得背景時間後立刻切回。"
                            : "除錯模式：每輪可能會短暫看到 Controller。"
                        )
                        .font(.caption)
                    }

                    Section("Stage 5.1 - Continuous Loop") {
                        Button(
                            "START LOOP"
                        ) {
                            let limit:
                                Int? =
                                selectedLimit == 0
                                ? nil
                                : selectedLimit

                            loopProbe
                                .startLoop(
                                    maxDispatches:
                                        limit,
                                    hideControllerFlash:
                                        hideControllerFlash
                                )
                        }
                        .disabled(
                            !sessionOK ||
                            loopProbe.isRunning
                        )

                        Button(
                            "STOP"
                        ) {
                            loopProbe
                                .stopLoop()
                        }
                        .foregroundStyle(.red)
                        .disabled(
                            !loopProbe.isRunning
                        )

                        HStack {
                            Text(
                                "已完成"
                            )

                            Spacer()

                            Text(
                                "\(loopProbe.completedDispatches)"
                            )
                            .font(
                                .system(
                                    .body,
                                    design:
                                        .monospaced
                                )
                            )
                            .bold()
                        }

                        HStack {
                            Text(
                                "目標"
                            )

                            Spacer()

                            Text(
                                selectedLimit == 0
                                ? "無限"
                                : "\(selectedLimit)"
                            )
                        }

                        HStack {
                            Text(
                                "狀態"
                            )

                            Spacer()

                            Text(
                                loopProbe.isRunning
                                ? "RUNNING"
                                : "STOPPED"
                            )
                            .foregroundStyle(
                                loopProbe.isRunning
                                ? .green
                                : .secondary
                            )
                        }

                        Text(
                            savedStage5Status()
                        )
                        .font(
                            .system(
                                .caption,
                                design:
                                    .monospaced
                            )
                        )
                        .textSelection(
                            .enabled
                        )
                    }

                    Section("Safety / Debug") {
                        Button(
                            "DETECT ONLY"
                        ) {
                            detectProbe
                                .detectOnly()
                        }
                        .disabled(
                            !sessionOK ||
                            loopProbe.isRunning
                        )

                        Button(
                            "Refresh Result"
                        ) {
                            loadResults()
                        }

                        if let finalImage {
                            Image(
                                uiImage:
                                    finalImage
                            )
                            .resizable()
                            .scaledToFit()
                            .frame(
                                maxHeight:
                                    360
                            )
                        }
                    }

                    Section("Connection") {
                        Text(log)
                            .font(
                                .system(
                                    .caption,
                                    design:
                                        .monospaced
                                )
                            )
                    }
                }
                .navigationTitle(
                    "Controller 0.6.1.2.2"
                )
            }

            // Full-screen visual handoff cover.
            // It is already prepared while Controller is still backgrounded,
            // so when iOS foregrounds Controller the user sees the last Pikmin
            // frame instead of this Form.
            if loopProbe
                .isHandoffCoverVisible,
               let image =
                loopProbe
                .handoffImage {
                GeometryReader {
                    proxy in

                    Image(
                        uiImage:
                            image
                    )
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width:
                            proxy.size.width,
                        height:
                            proxy.size.height
                    )
                    .clipped()
                    .ignoresSafeArea()
                }
                .background(
                    Color.black
                        .ignoresSafeArea()
                )
                .allowsHitTesting(
                    false
                )
                .zIndex(999)
            }
        }
        .statusBarHidden(
            loopProbe
                .isHandoffCoverVisible
        )
        .onChange(
            of: scenePhase
        ) {
            _,
            phase in

            if phase ==
                .active {
                loadResults()
            }
        }
    }

    @MainActor
    private func checkWDA() async {
        do {
            try await
                WDAClient.shared
                .status()

            wdaOK =
                true

            log =
                "WDA OK"
        }
        catch {
            wdaOK =
                false

            log =
                "WDA FAILED\n\(error.localizedDescription)"
        }
    }

    @MainActor
    private func createSession() async {
        do {
            let id =
                try await
                WDAClient.shared
                .createGenericSession()

            sessionOK =
                true

            log =
                "SESSION OK\n\(id)"
        }
        catch {
            sessionOK =
                false

            log =
                "SESSION FAILED\n\(error.localizedDescription)"
        }
    }

    private func savedStage5Status()
        -> String {
        UserDefaults.standard
            .string(
                forKey:
                    "stage5Status"
            )
        ?? "(none)"
    }

    private func loadResults() {
        if let data =
            try?
            Data(
                contentsOf:
                    ContinuousLoopProbe
                    .finalScreenshotURL
            ),
           let image =
            UIImage(
                data:
                    data
            ) {
            finalImage =
                image
        }
    }
}
