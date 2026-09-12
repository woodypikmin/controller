import Foundation

@MainActor
final class RunnerPackageStore: ObservableObject {
    enum Source: String {
        case embedded = "embedded"
        case importedOverride = "imported-override"
    }

    @Published private(set) var runnerURL: URL?
    @Published private(set) var source: Source?
    @Published private(set) var status = "找不到 Runner IPA"

    private let importedFileName = "PikminPilotRunner-signed-override.ipa"
    private let embeddedResourceName = "PikminPilotEmbeddedRunner"
    private let embeddedResourceExtension = "ipa"

    init() {
        refresh()
    }

    var importedURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(importedFileName)
    }

    var embeddedURL: URL? {
        Bundle.main.url(
            forResource: embeddedResourceName,
            withExtension: embeddedResourceExtension
        )
    }

    var sourceLabel: String {
        switch source {
        case .embedded: return "embedded"
        case .importedOverride: return "imported override"
        case .none: return "none"
        }
    }

    func refresh() {
        // Development override wins so we can test a newly signed Runner without
        // rebuilding the whole host app. Normal users never need this path.
        if FileManager.default.fileExists(atPath: importedURL.path) {
            runnerURL = importedURL
            source = .importedOverride
            status = sizeStatus(prefix: "Runner override 已就緒", url: importedURL)
            return
        }

        if let embedded = embeddedURL,
           FileManager.default.fileExists(atPath: embedded.path) {
            runnerURL = embedded
            source = .embedded
            status = sizeStatus(prefix: "內建 Signed Runner 已就緒", url: embedded)
            return
        }

        runnerURL = nil
        source = nil
        status = "內建 Runner 缺失（build/package error）"
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
        try data.write(to: importedURL, options: [.atomic])
        refresh()
    }

    func removeImportedOverride() throws {
        if FileManager.default.fileExists(atPath: importedURL.path) {
            try FileManager.default.removeItem(at: importedURL)
        }
        refresh()
    }

    private func sizeStatus(prefix: String, url: URL) -> String {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.int64Value ?? 0
        return String(format: "%@（%.2f MB）", prefix, Double(size) / 1_048_576.0)
    }
}
