import Foundation

nonisolated enum KeyboardSelection: Equatable, Sendable {
    case all, recent, pack(String)
}

/// The extension's own container; no shared writes or Full Access requirement.
/// Atomic persistence is visible immediately to another host's extension process.
@MainActor
final class KeyboardSelectionStore {
    private let defaults: UserDefaults
    private let fileURL: URL?
    private let key = "keyboardSelection.v1"
    private var unpersistedSelection: KeyboardSelection?

    convenience init() {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.init(defaults: .standard, fileURL: root?.appendingPathComponent("Keyboard/selection-v1.json"))
    }

    init(defaults: UserDefaults, fileURL: URL? = nil) {
        self.defaults = defaults
        self.fileURL = fileURL
    }

    private struct Record: Codable { let version: Int; let value: String }

    private func decode(_ value: String) -> KeyboardSelection? {
        if value == "all" { return .all }
        if value == "recent" { return .recent }
        if value.hasPrefix("pack:"), LibraryReader.safeID(String(value.dropFirst(5))) {
            return .pack(String(value.dropFirst(5)))
        }
        return nil
    }

    var selection: KeyboardSelection {
        if let unpersistedSelection { return unpersistedSelection }
        if let fileURL, let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           values.isRegularFile == true, (values.fileSize ?? Int.max) <= 512,
           let data = try? Data(contentsOf: fileURL), data.count <= 512,
           let record = try? JSONDecoder().decode(Record.self, from: data), record.version == 1,
           let selection = decode(record.value) { return selection }
        // Migrate the previous preference on the next explicit selection.
        return defaults.string(forKey: key).flatMap(decode) ?? .all
    }

    func save(_ selection: KeyboardSelection) {
        let value: String
        switch selection {
        case .all: value = "all"
        case .recent: value = "recent"
        case .pack(let id):
            guard LibraryReader.safeID(id) else { return }
            value = "pack:" + id
        }
        defaults.set(value, forKey: key)
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(Record(version: 1, value: value)).write(to: fileURL, options: .atomic)
            unpersistedSelection = nil
        } catch {
            // Storage errors must not revert this controller's selection or crash it.
            unpersistedSelection = selection
        }
    }
}
