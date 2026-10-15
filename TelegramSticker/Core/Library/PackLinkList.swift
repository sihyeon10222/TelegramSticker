import Foundation
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    nonisolated static let stickerBridgeLinks = UTType(exportedAs: "com.sihyeon.TelegramSticker.pack-links", conformingTo: .plainText)
}

nonisolated struct StickerLinkFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .stickerBridgeLinks) { Data($0.text.utf8) }
            .suggestedFileName("LinkList.stickerlinks")
    }
}

nonisolated enum PackLinkList {
    static func links(for packs: [PackManifestV1]) -> [String] {
        var seen = Set<String>()
        return packs.compactMap { pack in
            guard let name = pack.telegramName, StickerLink.validName(name) else { return nil }
            let normalized = name.lowercased()
            guard seen.insert(normalized).inserted else { return nil }
            return "https://t.me/addstickers/" + normalized
        }
    }
    static func split(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }
    static func read(_ url: URL) throws -> [String] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 2 * 1024 * 1024 + 1) ?? Data()
        guard data.count <= 2 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw StickerImportError.invalidLink }
        var seen = Set<String>()
        let result = try split(text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))).compactMap { value -> String? in
            let name = try StickerLink.parse(value)
            return seen.insert(name).inserted ? "https://t.me/addstickers/" + name : nil
        }
        guard !result.isEmpty else { throw StickerImportError.invalidLink }
        return result
    }
}

