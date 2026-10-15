import Foundation
import Observation
import CryptoKit

nonisolated struct RemoteGallery: Codable, Sendable {
    struct Pack: Codable, Sendable { let name: String; let link: String }
    let schemaVersion: Int
    let revision: String
    let packs: [Pack]
    func validate() throws {
        let hash = SHA256.hash(data: Data(packs.map(\.name).joined(separator: "\n").utf8))
            .map { String(format: "%02x", $0) }.joined()
        guard schemaVersion == 1, packs.count <= 200, revision == hash,
              Set(packs.map(\.name)).count == packs.count,
              packs.allSatisfy({ StickerLink.validName($0.name) && $0.name == $0.name.lowercased() &&
                  $0.link == "https://t.me/addstickers/" + $0.name }) else { throw StickerImportError.invalidResponse }
    }
}
