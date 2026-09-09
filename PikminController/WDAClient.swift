
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
            return "No WDA session."
        case .invalidScreenshot:
            return "Could not decode screenshot."
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
        timeout: TimeInterval = 8
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

    func status() async throws -> [String: Any] {
        try await request(path: "status", timeout: 8)
    }

    private func extractSessionId(_ dict: [String: Any]) -> String? {
        if let sid = dict["sessionId"] as? String, !sid.isEmpty {
            return sid
        }

        if let value = dict["value"] as? [String: Any],
           let sid = value["sessionId"] as? String,
           !sid.isEmpty {
            return sid
        }

        return nil
    }

    func createSession(bundleId: String) async throws -> String {
        // Keep JSONWP desiredCapabilities because raw WDA supports it directly.
        // Also send an empty W3C capabilities object for newer builds.
        let payload: [String: Any] = [
            "desiredCapabilities": [
                "bundleId": bundleId,
                "arguments": [],
                "environment": [:],
                "shouldWaitForQuiescence": false,
                "shouldUseSingletonTestManager": true
            ],
            "capabilities": [:]
        ]

        let dict = try await request(
            path: "session",
            method: "POST",
            json: payload,
            timeout: 60
        )

        guard let sid = extractSessionId(dict) else {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted])
            let text = String(data: data, encoding: .utf8) ?? "\(dict)"
            throw WDAError.server("No sessionId in response:\n\(text)")
        }

        sessionId = sid
        return sid
    }

    func createControllerSession() async throws -> String {
        guard let id = Bundle.main.bundleIdentifier else {
            throw WDAError.server("Controller bundle identifier is unavailable.")
        }
        return try await createSession(bundleId: id)
    }

    func createPikminSession() async throws -> String {
        try await createSession(bundleId: "com.nianticlabs.pikmin")
    }

    func screenshot() async throws -> UIImage {
        let dict = try await request(path: "screenshot", timeout: 15)

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

        let body: [String: Any] = ["x": x, "y": y]

        do {
            _ = try await request(
                path: "session/\(sid)/wda/tap",
                method: "POST",
                json: body,
                timeout: 15
            )
        } catch {
            _ = try await request(
                path: "session/\(sid)/wda/tap/0",
                method: "POST",
                json: body,
                timeout: 15
            )
        }
    }
}
