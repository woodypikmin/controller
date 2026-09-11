import Foundation

actor IDeviceEngine {
    struct Result: Sendable {
        let ok: Bool
        let message: String
    }

    private let pairingPath: String
    private let host: String
    private let port: UInt16

    init(pairingPath: String, host: String = "10.7.0.1", port: UInt16 = 49152) {
        self.pairingPath = pairingPath
        self.host = host
        self.port = port
    }

    func validatePairing() -> Result {
        callBridge { path, message, capacity in
            PPValidateRPPairingFile(path, message, capacity)
        }
    }

    func probeRSD() -> Result {
        callBridge { path, message, capacity in
            host.withCString { PPProbeRSD(path, $0, port, message, capacity) }
        }
    }

    func launchPikmin() -> Result {
        callBridge { path, message, capacity in
            host.withCString { PPLaunchPikmin(path, $0, port, message, capacity) }
        }
    }

    func takeScreenshot(outputPath: String) -> Result {
        callBridge { path, message, capacity in
            host.withCString { hostCString in
                outputPath.withCString { outputCString in
                    PPTakePhoneScreenshot(path, hostCString, port, outputCString, message, capacity)
                }
            }
        }
    }

    func tap(x: UInt16, y: UInt16) -> Result {
        callBridge { path, message, capacity in
            host.withCString {
                PPPhoneTap(path, $0, port, x, y, message, capacity)
            }
        }
    }

    func drag(x1: UInt16, y1: UInt16, x2: UInt16, y2: UInt16) -> Result {
        callBridge { path, message, capacity in
            host.withCString {
                PPPhoneDrag(path, $0, port, x1, y1, x2, y2, message, capacity)
            }
        }
    }

    private func callBridge(
        _ body: (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>, Int) -> Int32
    ) -> Result {
        let capacity = 4096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        defer { buffer.deallocate() }

        let code: Int32 = pairingPath.withCString { body($0, buffer, capacity) }
        let text = String(cString: buffer)
        return Result(ok: code == 0, message: text.isEmpty ? "idevice result code \(code)" : text)
    }
}
