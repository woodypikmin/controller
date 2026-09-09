
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase)
    private var scenePhase

    @StateObject private var detectProbe =
        BotProbe.shared

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

    var body: some View {
        NavigationStack {
            Form {
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

                Section("Safety") {
                    Button(
                        "DETECT ONLY"
                    ) {
                        detectProbe
                            .detectOnly()
                    }
                    .disabled(!sessionOK)
                }

                Section("Stage 5 - Continuous Loop") {
                    Button(
                        "START LOOP"
                    ) {
                        loopProbe
                            .startLoop()
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

                    Text("""
                    會持續派遣。
                    每輪完成後 Controller 只會短暫閃一下，再自動回 Pikmin。
                    沒有安全的 AVAILABLE 時自動停止。
                    """)
                    .font(.caption)

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

                Section("Result") {
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
                                380
                        )
                    }
                }

                Section("Current") {
                    Text(
                        loopProbe.status
                    )
                    .font(
                        .system(
                            .caption,
                            design:
                                .monospaced
                        )
                    )

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
                "Controller 0.5.0"
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
