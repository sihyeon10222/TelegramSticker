import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

extension UTType {
    static let stickerBridgeLinks = UTType(exportedAs: "com.sihyeon.TelegramSticker.pack-links", conformingTo: .plainText)
}

nonisolated struct StickerLinkFile: Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .stickerBridgeLinks) { Data($0.text.utf8) }
            .suggestedFileName("StickerBridge-Links.stickerlinks")
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

struct PackLinkShareMenu: View {
    let links: [String]
    var title = "링크 공유"
    var body: some View {
        Menu {
            ShareLink(item: links.joined(separator: "\n")) {
                Label("Telegram 링크 공유", systemImage: "link")
            }
            ShareLink(item: StickerLinkFile(text: links.joined(separator: "\n")), preview: SharePreview("Telegram 스티커 팩 링크 목록")) {
                Label("링크 목록 파일 공유", systemImage: "doc")
            }
        } label: { Label(title, systemImage: "square.and.arrow.up") }
            .disabled(links.isEmpty)
    }
}

struct ReceivedPackLinks: Identifiable {
    let id = UUID()
    let links: [String]
}
@MainActor @Observable
final class PackLinkInbox {
    static let shared = PackLinkInbox()
    var received: ReceivedPackLinks?
    var error: String?
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

struct ReceivedPackLinksView: View {
    let received: ReceivedPackLinks
    @State private var install = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Telegram 링크 \(received.links.count)개를 받았어요.")
                    Text("설치하면 연결한 가져오기 서버에서 스티커를 다운로드해요. 이미 설치한 팩은 유지하고 중복은 건너뛰어요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("받은 팩 설치") { install = true }
                        .disabled(ImportActivity.shared.count > 0 || LibraryWriter.shared == nil)
                        .accessibilityIdentifier("installReceivedLinks")
                }
                Section("공유받은 팩") {
                    ForEach(received.links, id: \.self) { link in
                        VStack(alignment: .leading, spacing: 4) {
                            Text((try? StickerLink.parse(link)) ?? link).font(.headline)
                            Text(link).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }
                }
            }.navigationTitle("받은 스티커 팩 링크")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
                .sheet(isPresented: $install) {
                    if let writer = LibraryWriter.shared { ImportView(writer: writer, initialLinks: received.links) }
                }
        }
    }
}
