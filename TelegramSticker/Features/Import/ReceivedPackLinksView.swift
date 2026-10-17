import SwiftUI

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
                .toolbar { AppModalCloseToolbar { dismiss() } }
                .sheet(isPresented: $install) {
                    if let writer = LibraryWriter.shared { ImportView(writer: writer, initialLinks: received.links) }
                }
        }
    }
}
