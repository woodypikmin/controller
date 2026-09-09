
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
        case .noSession: return "Create GENERIC session first."
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
            throw WDAError.server(
                String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            )
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw WDAError.invalidResponse
        }
        return dict
    }

    private func extractSessionId(_ d: [String: Any]) -> String? {
        if let id = d["sessionId"] as? String, !id.isEmpty { return id }
        if let v = d["value"] as? [String: Any],
           let id = v["sessionId"] as? String,
           !id.isEmpty { return id }
        return nil
    }

    func status() async throws -> String {
        String(describing: try await request(path: "status", timeout: 8))
    }

    func createGenericSession() async throws -> String {
        let d = try await request(
            path: "session",
            method: "POST",
            json: [
                "capabilities": [
                    "alwaysMatch": [:]
                ]
            ],
            timeout: 30
        )

        guard let id = extractSessionId(d) else {
            throw WDAError.server("No sessionId: \(d)")
        }

        sessionId = id
        UserDefaults.standard.set(id, forKey: "lastWDASessionId")
        return id
    }

    private func ensureSession() throws -> String {
        if let id = sessionId { return id }

        if let saved = UserDefaults.standard.string(forKey: "lastWDASessionId"),
           !saved.isEmpty {
            sessionId = saved
            return saved
        }

        throw WDAError.noSession
    }

    func launchPikmin() async throws {
        let id = try ensureSession()

        _ = try await request(
            path: "session/\(id)/wda/apps/launch",
            method: "POST",
            json: ["bundleId": "com.nianticlabs.pikmin"],
            timeout: 20
        )
    }

    func screenshotData() async throws -> Data {
        let d = try await request(path: "screenshot", timeout: 15)

        guard let b64 = d["value"] as? String,
              let data = Data(base64Encoded: b64) else {
            throw WDAError.invalidScreenshot
        }

        return data
    }

    func screenshot() async throws -> UIImage {
        let data = try await screenshotData()

        guard let image = UIImage(data: data) else {
            throw WDAError.invalidScreenshot
        }

        return image
    }
}
