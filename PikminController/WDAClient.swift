
import Foundation
import UIKit

enum WDAError: LocalizedError {
    case invalidResponse
    case server(String)
    case noSession
    case invalidScreenshot

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from WDA."
        case .server(let text):
            return text
        case .noSession:
            return "No WDA session. Create a Pikmin session first."
        case .invalidScreenshot:
            return "Could not decode WDA screenshot."
        }
    }
}

actor WDAClient {
    static let shared = WDAClient()

    private let base = URL(string: "http://127.0.0.1:8100")!
    private(set) var sessionId: String?

    private func request(
        path: String,
        method: String = "GET",
        json: [String: Any]? = nil
    ) async throws -> [String: Any] {
        let url = base.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 8

        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }

        let (data, response) = try await URLSession.shared.data(for: req)

        guard let http = response as? HTTPURLResponse else {
            throw WDAError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WDAError.server(text)
        }

        let obj = try JSONSerialization.jsonObject(with: data)

        guard let dict = obj as? [String: Any] else {
            throw WDAError.invalidResponse
        }

        return dict
    }

    func status() async throws -> String {
        let dict = try await request(path: "status")
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
        return String(data: data, encoding: .utf8) ?? "WDA OK"
    }

    func createPikminSession() async throws -> String {
        // Try W3C capabilities first.
        let payload: [String: Any] = [
            "capabilities": [
                "alwaysMatch": [
                    "bundleId": "com.nianticlabs.pikmin",
                    "shouldWaitForQuiescence": false
                ],
                "firstMatch": [[:]]
            ],
            // Older WDA builds may still inspect desiredCapabilities.
            "desiredCapabilities": [
                "bundleId": "com.nianticlabs.pikmin",
                "shouldWaitForQuiescence": false
            ]
        ]

        let dict = try await request(
            path: "session",
            method: "POST",
            json: payload
        )

        var found: String?

        if let sid = dict["sessionId"] as? String {
            found = sid
        }

        if found == nil,
           let value = dict["value"] as? [String: Any],
           let sid = value["sessionId"] as? String {
            found = sid
        }

        guard let sid = found else {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            let text = String(data: data, encoding: .utf8) ?? "\(dict)"
            throw WDAError.server("Session created but sessionId was not found:\n\(text)")
        }

        sessionId = sid
        return sid
    }

    func screenshot() async throws -> UIImage {
        let dict = try await request(path: "screenshot")

        guard let value = dict["value"] as? String,
              let data = Data(base64Encoded: value),
              let image = UIImage(data: data) else {
            throw WDAError.invalidScreenshot
        }

        return image
    }

    func tap(x: Double, y: Double) async throws {
        guard let sid = sessionId else {
            throw WDAError.noSession
        }

        let body: [String: Any] = [
            "x": x,
            "y": y
        ]

        // Current WDA route.
        do {
            _ = try await request(
                path: "session/\(sid)/wda/tap",
                method: "POST",
                json: body
            )
            return
        } catch {
            // Compatibility fallback used by older WDA clients.
            _ = try await request(
                path: "session/\(sid)/wda/tap/0",
                method: "POST",
                json: body
            )
        }
    }

    func swipe(
        fromX: Double,
        fromY: Double,
        toX: Double,
        toY: Double,
        duration: Double = 0.4
    ) async throws {
        guard let sid = sessionId else {
            throw WDAError.noSession
        }

        let body: [String: Any] = [
            "fromX": fromX,
            "fromY": fromY,
            "toX": toX,
            "toY": toY,
            "duration": duration
        ]

        _ = try await request(
            path: "session/\(sid)/wda/dragfromtoforduration",
            method: "POST",
            json: body
        )
    }
}
