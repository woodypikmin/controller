
import XCTest
import Network
import Foundation

final class RunnerServiceTests: XCTestCase {
    private var server: RunnerHTTPServer?

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    func testRunnerService() throws {
        let server = try RunnerHTTPServer()
        self.server = server
        server.start()

        // Keep the XCTest runner alive. The bot logic will gradually move
        // into this process in later stages.
        let keepAlive = expectation(
            description: "Pikmin Runner service stays alive"
        )

        // Intentionally long-lived development service.
        wait(
            for: [keepAlive],
            timeout: 60 * 60 * 12
        )
    }
}

final class RunnerHTTPServer {
    private let listener: NWListener
    private let queue = DispatchQueue(
        label: "PikminRunner.HTTP"
    )

    init() throws {
        listener = try NWListener(
            using: .tcp,
            on: NWEndpoint.Port(
                rawValue: 8200
            )!
        )
    }

    func start() {
        listener.stateUpdateHandler = {
            state in

            switch state {
            case .ready:
                print(
                    "PIKMIN_RUNNER_READY http://127.0.0.1:8200"
                )

            case .failed(
                let error
            ):
                print(
                    "PIKMIN_RUNNER_FAILED \(error)"
                )

            default:
                break
            }
        }

        listener.newConnectionHandler = {
            [weak self]
            connection in

            self?.handle(
                connection
            )
        }

        listener.start(
            queue: queue
        )
    }

    private func handle(
        _ connection: NWConnection
    ) {
        connection.start(
            queue: queue
        )

        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 16_384
        ) {
            [weak self]
            data,
            _,
            _,
            error in

            guard error == nil,
                  let data,
                  let request =
                    String(
                        data: data,
                        encoding: .utf8
                    )
            else {
                connection.cancel()
                return
            }

            self?.route(
                request,
                connection:
                    connection
            )
        }
    }

    private func route(
        _ request: String,
        connection: NWConnection
    ) {
        let firstLine =
            request
            .split(
                separator: "\n",
                maxSplits: 1
            )
            .first
            .map(
                String.init
            )
            ?? ""

        let parts =
            firstLine
            .split(
                separator: " "
            )

        let path =
            parts.count >= 2
            ? String(
                parts[1]
            )
            : "/"

        switch path {
        case "/status":
            sendJSON(
                """
                {"ready":true,"service":"PikminRunner","port":8200,"runtime":"XCUITest"}
                """,
                connection:
                    connection
            )

        case "/launch-pikmin",
             "/activate-pikmin":
            // Reply first. Activating Pikmin may change foreground state.
            sendJSON(
                """
                {"ok":true,"action":"activate-pikmin"}
                """,
                connection:
                    connection
            )

            DispatchQueue.main.asyncAfter(
                deadline:
                    .now()
                    + 0.12
            ) {
                let pikmin =
                    XCUIApplication(
                        bundleIdentifier:
                            "com.nianticlabs.pikmin"
                    )

                if pikmin.state ==
                    .notRunning {
                    pikmin.launch()
                }
                else {
                    pikmin.activate()
                }
            }

        default:
            sendJSON(
                """
                {"ready":true,"endpoints":["/status","/launch-pikmin"]}
                """,
                connection:
                    connection,
                status:
                    "200 OK"
            )
        }
    }

    private func sendJSON(
        _ body: String,
        connection: NWConnection,
        status: String =
            "200 OK"
    ) {
        let bytes =
            body.data(
                using: .utf8
            )
            ?? Data()

        let header =
            """
            HTTP/1.1 \(status)\r
            Content-Type: application/json\r
            Content-Length: \(bytes.count)\r
            Connection: close\r
            \r

            """

        var response =
            Data(
                header.utf8
            )

        response.append(
            bytes
        )

        connection.send(
            content: response,
            completion:
                .contentProcessed {
                    _ in

                    connection.cancel()
                }
        )
    }
}
