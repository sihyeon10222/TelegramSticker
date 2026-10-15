import Foundation

nonisolated enum StickerLink {
    static func parse(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = URLComponents(string: value), c.scheme?.lowercased() == "https",
              ["t.me", "telegram.me"].contains(c.host?.lowercased() ?? ""),
              c.user == nil, c.password == nil, c.port == nil, c.query == nil, c.fragment == nil else {
            throw StickerImportError.invalidLink
        }
        var path = c.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        let pieces = path.split(separator: "/", omittingEmptySubsequences: false)
        guard pieces.count == 3, pieces[0].isEmpty, pieces[1] == "addstickers",
              validName(String(pieces[2])) else { throw StickerImportError.invalidLink }
        return String(pieces[2]).lowercased()
    }
    static func validName(_ name: String) -> Bool {
        name.range(of: "^[A-Za-z0-9_]{1,64}$", options: .regularExpression) != nil
    }
}
