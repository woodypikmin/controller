
import Foundation

/// Stage 7 transport boundary.
///
/// Stage 5 bot logic must only depend on this protocol going forward.
/// WDA / Windows is no longer the product transport.
protocol PilotTransport: Sendable {
    func connect() async throws
    func launchPikmin() async throws
    func screenshot() async throws -> Data
    func tap(x: Double, y: Double) async throws
    func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double) async throws
}

enum PilotTransportError: LocalizedError {
    case pairingRecordMissing
    case embeddedEngineNotReady

    var errorDescription: String? {
        switch self {
        case .pairingRecordMissing:
            return "需要先匯入 Remote Pairing Record"
        case .embeddedEngineNotReady:
            return "Stage 7 Embedded Device Engine 尚未連接完成"
        }
    }
}

/// This is the product-side transport object.
/// Stage 7.0 deliberately does NOT silently fall back to localhost WDA.
/// That prevents us from accidentally shipping the old PC-dependent architecture.
actor EmbeddedDeviceTransport: PilotTransport {
    private let pairingRecordPath: String

    init(pairingRecordPath: String) {
        self.pairingRecordPath = pairingRecordPath
    }

    func connect() async throws {
        guard FileManager.default.fileExists(atPath: pairingRecordPath) else {
            throw PilotTransportError.pairingRecordMissing
        }

        // Stage 7.1 will bind this boundary to idevice/RPPairing/RSD.
        throw PilotTransportError.embeddedEngineNotReady
    }

    func launchPikmin() async throws {
        throw PilotTransportError.embeddedEngineNotReady
    }

    func screenshot() async throws -> Data {
        throw PilotTransportError.embeddedEngineNotReady
    }

    func tap(x: Double, y: Double) async throws {
        throw PilotTransportError.embeddedEngineNotReady
    }

    func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, duration: Double) async throws {
        throw PilotTransportError.embeddedEngineNotReady
    }
}
