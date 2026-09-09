
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var detectProbe =
        BotProbe.shared

    @StateObject private var dispatchProbe =
        SingleDispatchProbe.shared

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
                    Button("1. Check WDA") {
                        Task {
                            await checkWDA()
                        }
                    }

                    Button("2. Create GENERIC Session") {
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

                Section("Safety check") {
                    Button("DETECT ONLY") {
                        detectProbe
                            .detectOnly()
                    }
                    .disabled(!sessionOK)

                    Text("""
                    還是可以先用這個確認 GREEN / RED / BLUE / PURPLE。
                    不會點手機。
                    """)
                    .font(.caption)
                }

                Section("Stage 3 - One Full Dispatch") {
                    Button(
                        "RUN ONE FULL DISPATCH"
                    ) {
                        dispatchProbe
                            .runOneDispatch()
                    }
                    .disabled(!sessionOK)

                    Text("""
                    這會真的控制 Pikmin：
                    AVAILABLE → 前往探險 → 粉色 → 12隻 → GO → 搬運 X → 停止。
                    只跑一輪，不會循環。
                    """)
                    .font(.caption)
                    .foregroundStyle(.red)

                    Text(
                        savedStage3Status()
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

                Section("Last screenshots") {
                    Button("Refresh Results") {
                        loadResults()
                    }

                    if let detectionImage {
                        Text(
                            "Last detection:"
                        )
                        .font(.caption)

                        Image(
                            uiImage:
                                detectionImage
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxHeight:
                                350
                        )
                    }

                    if let finalImage {
                        Text(
                            "Screen after dispatch:"
                        )
                        .font(.caption)

                        Image(
                            uiImage:
                                finalImage
                        )
                        .resizable()
                        .scaledToFit()
                        .frame(
                            maxHeight:
                                350
                        )
                    }
                }

                Section("Current") {
                    Text(
                        dispatchProbe.status
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
                "Controller 0.3.1"
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

    private func savedStage3Status() -> String {
        UserDefaults.standard
            .string(
                forKey:
                    "stage3Status"
            )
        ?? "(none)"
    }

    private func loadResults() {
        if let data =
            try?
            Data(
                contentsOf:
                    BotProbe.resultURL
            ),
           let image =
            UIImage(
                data: data
            ) {
            detectionImage =
                image
        }

        if let data =
            try?
            Data(
                contentsOf:
                    SingleDispatchProbe
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
