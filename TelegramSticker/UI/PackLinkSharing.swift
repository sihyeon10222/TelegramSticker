import SwiftUI

struct PackLinkShareMenu: View {
    let links: [String]
    var title = "링크 공유"
    var body: some View {
        Menu {
            ShareLink(item: links.joined(separator: "\n")) {
                Label("Sticker Pack 링크 공유", systemImage: "link")
            }
            ShareLink(item: StickerLinkFile(text: links.joined(separator: "\n")), preview: SharePreview("Telegram 스티커 팩 링크 목록")) {
                Label("링크 목록 파일 공유", systemImage: "doc")
            }
        } label: { Label(title, systemImage: "square.and.arrow.up") }
            .disabled(links.isEmpty)
    }
}

struct PackLinksShareView: View {
    let links: [String]
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                ShareLink(item: links.joined(separator: "\n")) { Label("Sticker Pack 링크 공유", systemImage: "link") }
                ShareLink(item: StickerLinkFile(text: links.joined(separator: "\n")), preview: SharePreview("스티커 팩 링크 목록")) {
                    Label("링크 목록 파일 공유", systemImage: "doc")
                }
            }
            .navigationTitle("팩 공유").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}

