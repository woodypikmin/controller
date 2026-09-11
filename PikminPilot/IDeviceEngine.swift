import Foundation

actor IDeviceEngine {
    struct Result: Sendable {
        let ok: Bool
        let message: String
    }

    private let pairingPath: String
    private let host: String
    private let port: UInt16

    init(
        pairingPath: String,
        host: String = "10.7.0.1",
        port: UInt16 = 49152
    ) {
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
            host.withCString { hostCString in
                PPProbeRSD(path, hostCString, port, message, capacity)
            }
        }
    }

    func discoverXCTestRunner() -> Result {
        callBridge { path, message, capacity in
            host.withCString { hostCString in
                PPDiscoverPhoneLocalXCTestRunner(
                    path,
                    hostCString,
                    port,
                    message,
                    capacity
                )
            }
        }
    }

    func bootstrapXCTestDTX() -> Result {
        callBridge { path, message, capacity in
            host.withCString { hostCString in
                PPBootstrapPhoneLocalXCTestDTX(
                    path,
                    hostCString,
                    port,
                    message,
                    capacity
                )
            }
        }
    }

    func probeXCTestServices() -> Result {
        callBridge { path, message, capacity in
            host.withCString { hostCString in
                PPProbePhoneLocalXCTestServices(
                    path,
                    hostCString,
                    port,
                    message,
                    capacity
                )
            }
        }
    }

    func launchBundleID(_ bundleID: String) -> Result {
        callBridge { path, message, capacity in
            host.withCString { hostCString in
                bundleID.withCString { bundleCString in
                    PPLaunchBundleID(
                        path,
                        hostCString,
                        port,
                        bundleCString,
                        message,
                        capacity
                    )
                }
            }
        }
    }

    func launchPikmin() -> Result {
        callBridge { path, message, capacity in
            host.withCString { hostCString in
                PPLaunchPikmin(path, hostCString, port, message, capacity)
            }
        }
    }

    func takeScreenshot(outputPath: String) -> Result {
        callBridge { path, message, capacity in
            host.withCString { hostCString in
                outputPath.withCString { outputCString in
                    PPTakePhoneScreenshot(
                        path,
                        hostCString,
                        port,
                        outputCString,
                        message,
                        capacity
                    )
                }
            }
        }
    }

    private func callBridge(
        _ body: (
            UnsafePointer<CChar>,
            UnsafeMutablePointer<CChar>,
            Int
        ) -> Int32
    ) -> Result {
        let capacity = 2048
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: capacity)
        buffer.initialize(repeating: 0, count: capacity)
        defer { buffer.deallocate() }

        let code: Int32 = pairingPath.withCString { path in
            body(path, buffer, capacity)
        }

        let text = String(cString: buffer)
        return Result(
            ok: code == 0,
            message: text.isEmpty ? "idevice result code \(code)" : text
        )
    }
}
