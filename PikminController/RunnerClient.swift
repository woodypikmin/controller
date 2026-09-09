
import Foundation

actor RunnerClient {
    static let shared =
        RunnerClient()

    private let base =
        URL(
            string:
                "http://127.0.0.1:8200"
        )!

    func status()
        async throws
        -> String {
        try await get(
            "/status"
        )
    }

    func launchPikmin()
        async throws
        -> String {
        try await get(
            "/launch-pikmin"
        )
    }

    private func get(
        _ path: String
    ) async throws
    -> String {
        let url =
            URL(
                string:
                    path,
                relativeTo:
                    base
            )!

        var request =
            URLRequest(
                url: url
            )

        request.httpMethod =
            "GET"

        request.timeoutInterval =
            2.5

        let config =
            URLSessionConfiguration
                .ephemeral

        config.timeoutIntervalForRequest =
            2.5

        config.timeoutIntervalForResource =
            3.0

        let session =
            URLSession(
                configuration:
                    config
            )

        let (
            data,
            response
        ) =
            try await
            session.data(
                for: request
            )

        guard let http =
            response
                as?
                HTTPURLResponse,
              (
                200...299
              )
              .contains(
                http.statusCode
              )
        else {
            throw
                URLError(
                    .badServerResponse
                )
        }

        return
            String(
                data: data,
                encoding:
                    .utf8
            )
            ?? "(empty)"
    }
}
