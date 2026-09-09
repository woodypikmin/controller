
import Foundation
import UIKit

enum WDAError: LocalizedError {
    case invalidResponse
    case server(String)
    case noSession
    case invalidScreenshot

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from WDA."
        case .server(let s): return s
        case .noSession: return "Create CONTROLLER session first."
        case .invalidScreenshot: return "Could not decode screenshot."
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
        json: [String: Any]? = nil,
        timeout: TimeInterval = 15
    ) async throws -> [String: Any] {
        let url = base.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout

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
        let d = try await request(path: "status", timeout: 8)
        return String(describing: d)
    }

    private func extractSessionId(_ d: [String: Any]) -> String? {
        if let sid = d["sessionId"] as? String, !sid.isEmpty { return sid }
        if let v = d["value"] as? [String: Any],
           let sid = v["sessionId"] as? String,
           !sid.isEmpty { return sid }
        return nil
    }

    func createControllerSession() async throws -> String {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            throw WDAError.server("Controller bundle id unavailable.")
        }

        let body: [String: Any] = [
            "desiredCapabilities": [
                "bundleId": bundleId,
                "arguments": [],
                "environment": [:],
                "shouldWaitForQuiescence": false,
                "shouldUseSingletonTestManager": true
            ],
            "capabilities": [
                "alwaysMatch": [
                    "bundleId": bundleId,
                    "shouldWaitForQuiescence": false
                ],
                "firstMatch": [[:]]
            ]
        ]

        let d = try await request(
            path: "session",
            method: "POST",
            json: body,
            timeout: 60
        )

        guard let sid = extractSessionId(d) else {
            throw WDAError.server("WDA returned no sessionId: \(d)")
        }

        sessionId = sid
        return sid
    }

    func launchPikmin() async throws {
        guard let sid = sessionId else { throw WDAError.noSession }

        let body: [String: Any] = [
            "bundleId": "com.nianticlabs.pikmin",
            "arguments": [],
            "environment": [:],
            "shouldWaitForQuiescence": false
        ]

        _ = try await request(
            path: "session/\(sid)/wda/apps/launch",
            method: "POST",
            json: body,
            timeout: 30
        )
    }

    func pikminState() async throws -> String {
        guard let sid = sessionId else { throw WDAError.noSession }

        let d = try await request(
            path: "session/\(sid)/wda/apps/state",
            method: "POST",
            json: ["bundleId": "com.nianticlabs.pikmin"],
            timeout: 10
        )

        return String(describing: d)
    }

    func screenshot() async throws -> UIImage {
        let d = try await request(path: "screenshot", timeout: 15)
        guard let b64 = d["value"] as? String,
              let data = Data(base64Encoded: b64),
              let image = UIImage(data: data) else {
            throw WDAError.invalidScreenshot
        }
        return image
    }
}
