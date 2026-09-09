
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
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WDAError.server(text)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        guard let dict = object as? [String: Any] else {
            throw WDAError.invalidResponse
        }

        return dict
    }

    private func sessionId(from response: [String: Any]) -> String? {
        if let id = response["sessionId"] as? String, !id.isEmpty {
            return id
        }

        if let value = response["value"] as? [String: Any] {
            if let id = value["sessionId"] as? String, !id.isEmpty {
                return id
            }
        }

        return nil
    }

    func status() async throws -> String {
        let value = try await request(path: "status", timeout: 8)
        return String(describing: value)
    }

    func createGenericSession() async throws -> String {
        // This mirrors SideTap's current session creation:
        // POST /session {"capabilities":{"alwaysMatch":{}}}
        //
        // No bundleId = do NOT relaunch Pikmin Controller.
        let body: [String: Any] = [
            "capabilities": [
                "alwaysMatch": [:]
            ]
        ]

        let response = try await request(
            path: "session",
            method: "POST",
            json: body,
            timeout: 30
        )

        guard let id = sessionId(from: response) else {
            throw WDAError.server("No sessionId returned: \(response)")
        }

        sessionId = id
        UserDefaults.standard.set(id, forKey: "lastWDASessionId")
        return id
    }

    func restoreSavedSession() -> String? {
        if let current = sessionId {
            return current
        }

        if let saved = UserDefaults.standard.string(forKey: "lastWDASessionId"),
           !saved.isEmpty {
            sessionId = saved
            return saved
        }

        return nil
    }

    func activeAppInfo() async throws -> String {
        guard let id = sessionId ?? restoreSavedSession() else {
            throw WDAError.noSession
        }

        let response = try await request(
            path: "session/\(id)/wda/activeAppInfo",
            timeout: 10
        )

        return String(describing: response)
    }

    func launchPikmin() async throws {
        guard let id = sessionId ?? restoreSavedSession() else {
            throw WDAError.noSession
        }

        // Write this BEFORE sending the launch request. If iOS backgrounds
        // Controller immediately, we can still tell the request was sent.
        UserDefaults.standard.set(
            Date().timeIntervalSince1970,
            forKey: "pikminLaunchSentAt"
        )

        _ = try await request(
            path: "session/\(id)/wda/apps/launch",
            method: "POST",
            json: [
                "bundleId": "com.nianticlabs.pikmin"
            ],
            timeout: 20
        )

        UserDefaults.standard.set(
            true,
            forKey: "pikminLaunchGotHTTP200"
        )
    }

    func screenshot() async throws -> UIImage {
        let response = try await request(
            path: "screenshot",
            timeout: 15
        )

        guard let b64 = response["value"] as? String,
              let data = Data(base64Encoded: b64),
              let image = UIImage(data: data) else {
            throw WDAError.invalidScreenshot
        }

        return image
    }
}
