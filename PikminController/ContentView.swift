
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var detectProbe =
        BotProbe.shared

    @StateObject private var singleProbe =
        SingleDispatchProbe.shared

    @StateObject private var multiProbe =
        MultiDispatchProbe.shared

    @State private var log =
        "Ready."

    @State private var wdaOK =
        false

    @State private var sessionOK =
        false

    @State private var detectionImage:
        UIImage?

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

                Section("Stage 4.4 - Two Dispatch Test") {
                    Button(
                        "RUN TWO DISPATCHES"
                    ) {
                        multiProbe
                            .runTwoDispatches()
                    }
                    .disabled(!sessionOK)

                    Text("""
                    會真的跑兩次：
                    第一輪完成後，Controller 會自動短暫回到前景取得新的背景時間，再自動切回 Pikmin 跑第二輪。你不需要手動切 App。
                    """)
                    .font(.caption)
                    .foregroundStyle(.red)

                    Button(
                        "STOP"
                    ) {
                        multiProbe.cancel()
                    }
                    .foregroundStyle(.red)

                    Text(
                        savedStage4Status()
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
                        multiProbe.status
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
                "Controller 0.4.4"
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

    private func savedStage4Status()
        -> String {
        UserDefaults.standard
            .string(
                forKey:
                    "stage4Status"
            )
        ?? "(none)"
    }

    private func loadResults() {
        if let data =
            try?
            Data(
                contentsOf:
                    MultiDispatchProbe
                    .finalScreenshotURL
            ),
           let image =
            UIImage(
                data: data
            ) {
            finalImage =
                image
        }
    }
}
