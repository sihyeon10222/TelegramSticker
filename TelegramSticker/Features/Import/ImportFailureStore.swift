import Foundation
import Observation

actor ImportFailureStore {
    static let shared = ImportFailureStore()
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ImportFailures")
    func load(name: String) -> [ImportFailure] {
        guard StickerLink.validName(name), let data = try? Data(contentsOf: root.appendingPathComponent(name + ".json")) else { return [] }
        return (try? JSONDecoder().decode([ImportFailure].self, from: data)) ?? []
    }
    func save(name: String, failures: [ImportFailure]) throws {
        guard StickerLink.validName(name) else { throw StickerImportError.invalidLink }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(failures).write(to: root.appendingPathComponent(name + ".json"), options: .atomic)
    }
}
