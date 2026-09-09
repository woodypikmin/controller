
import Foundation
import AVFoundation

@MainActor
final class BackgroundAudioKeeper {
    static let shared = BackgroundAudioKeeper()

    private var player: AVAudioPlayer?

    private init() {}

    func start() throws {
        let session = AVAudioSession.sharedInstance()

        try session.setCategory(
            .playback,
            mode: .default,
            options: [
                .mixWithOthers
            ]
        )

        try session.setActive(true)

        let url = try makeNearSilentWAVIfNeeded()

        let p = try AVAudioPlayer(
            contentsOf: url
        )

        p.numberOfLoops = -1
        p.volume = 1.0
        p.prepareToPlay()

        guard p.play() else {
            throw WDAError.server(
                "Background audio keeper could not start."
            )
        }

        player = p
    }

    func stop() {
        player?.stop()
        player = nil

        try? AVAudioSession
            .sharedInstance()
            .setActive(
                false,
                options: [
                    .notifyOthersOnDeactivation
                ]
            )
    }

    var isRunning: Bool {
        player?.isPlaying == true
    }

    private func makeNearSilentWAVIfNeeded()
        throws -> URL {
        let dir =
            FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            )[0]

        let url =
            dir.appendingPathComponent(
                "near_silent_loop.wav"
            )

        if FileManager.default
            .fileExists(
                atPath: url.path
            ) {
            return url
        }

        let sampleRate: UInt32 = 8000
        let seconds: UInt32 = 1
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16

        let sampleCount =
            Int(
                sampleRate * seconds
            )

        // Extremely tiny alternating PCM signal.
        // It is effectively inaudible but is real audio, not an empty file.
        var pcm =
            Data(
                capacity:
                    sampleCount * 2
            )

        for i in 0..<sampleCount {
            var sample:
                Int16 =
                i % 2 == 0
                ? 1
                : -1

            withUnsafeBytes(
                of: &sample
            ) {
                pcm.append(
                    contentsOf: $0
                )
            }
        }

        let byteRate =
            sampleRate *
            UInt32(channels) *
            UInt32(bitsPerSample / 8)

        let blockAlign =
            channels *
            (bitsPerSample / 8)

        let dataSize =
            UInt32(
                pcm.count
            )

        let riffSize =
            36 + dataSize

        var wav = Data()

        func appendASCII(
            _ s: String
        ) {
            wav.append(
                s.data(
                    using: .ascii
                )!
            )
        }

        func appendUInt16(
            _ value: UInt16
        ) {
            var v =
                value.littleEndian

            withUnsafeBytes(
                of: &v
            ) {
                wav.append(
                    contentsOf: $0
                )
            }
        }

        func appendUInt32(
            _ value: UInt32
        ) {
            var v =
                value.littleEndian

            withUnsafeBytes(
                of: &v
            ) {
                wav.append(
                    contentsOf: $0
                )
            }
        }

        appendASCII("RIFF")
        appendUInt32(riffSize)
        appendASCII("WAVE")

        appendASCII("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(channels)
        appendUInt32(sampleRate)
        appendUInt32(byteRate)
        appendUInt16(blockAlign)
        appendUInt16(bitsPerSample)

        appendASCII("data")
        appendUInt32(dataSize)
        wav.append(pcm)

        try wav.write(
            to: url,
            options: .atomic
        )

        return url
    }
}
