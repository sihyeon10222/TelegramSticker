import Foundation
import Observation

struct ReceivedPackLinks: Identifiable {
    let id = UUID()
    let links: [String]
}
@MainActor @Observable
final class PackLinkInbox {
    static let shared = PackLinkInbox()
    var received: ReceivedPackLinks?
    var error: String?
    var showFileImporter = false
    var loading = false
    func open(_ url: URL) async {
        guard url.isFileURL, !loading else { return }
        loading = true
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() }; loading = false }
        do {
            let links = try await Task.detached { try PackLinkList.read(url) }.value
            received = ReceivedPackLinks(links: links)
        } catch { self.error = "링크 목록을 열 수 없어요. Telegram 스티커 링크만 담긴 파일인지 확인해 주세요.\n" + error.localizedDescription }
    }
}

