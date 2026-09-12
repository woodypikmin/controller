import Foundation

@MainActor
final class RunnerPackageStore: ObservableObject {
    @Published private(set) var runnerURL: URL?
    @Published private(set) var status = "尚未匯入已簽名 Runner IPA"

    private let fileName = "PikminPilotRunner-signed.ipa"

    init() {
        refresh()
    }

    var destinationURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(fileName)
    }

    func refresh() {
        let url = destinationURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            runnerURL = nil
            status = "尚未匯入已簽名 Runner IPA"
            return
        }
        runnerURL = url
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
        status = String(format: "Runner IPA 已就緒（%.2f MB）", Double(size) / 1_048_576.0)
    }

    func importIPA(from sourceURL: URL) throws {
        let granted = sourceURL.startAccessingSecurityScopedResource()
        defer { if granted { sourceURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: sourceURL)
        guard data.count > 4, data[0] == 0x50, data[1] == 0x4B else {
            throw NSError(
                domain: "PikminPilot.RunnerPackage",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "這個檔案不是有效的 IPA/ZIP"]
            )
        }
        try data.write(to: destinationURL, options: [.atomic])
        refresh()
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        refresh()
    }
}
