#if targetEnvironment(macCatalyst)
import UIKit
import SwiftUI

@MainActor
final class MacDesktopCoordinator {
    static let shared = MacDesktopCoordinator()
    private var bundle: Bundle?
    private var plugin: DesktopPluginProtocol?
    private var stickers: [String: Sticker] = [:]
    private var refreshTask: Task<Void, Never>?
    private var snapshotRevision: String?
    private var snapshotGeneration: String?
    private var snapshotWarnings: [String] = []
    private var cachedSnapshot: [NSDictionary] = []

    func start() {
        guard plugin == nil, let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("StickerBridgeDesktop.bundle"),
              let bundle = Bundle(url: url), bundle.load(),
              let type = bundle.principalClass as? NSObject.Type,
              let plugin = type.init() as? DesktopPluginProtocol else { return }
        self.bundle = bundle
        self.plugin = plugin
        StickerCopyService.macGIFWriter = { data in try plugin.writeGIFToPasteboard(data) }
        plugin.start(snapshot: { [weak self] in self?.snapshot() ?? [] }, copy: { [weak self] id in
            guard let sticker = self?.stickers[id] else { return "스티커 파일을 찾을 수 없어요." }
            let result = StickerCopyService().copy(sticker, isAllowed: true)
            return result == .copied ? nil : result.message
        }, openManagement: {
            DispatchQueue.main.async {
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                UIApplication.shared.requestSceneSessionActivation(scene?.session, userActivity: nil, options: nil)
                NotificationCenter.default.post(name: .macOpenManagement, object: nil)
            }
        })
        refreshSnapshot()
    }

    /// AppKit's synchronous callback returns prepared memory, never filesystem work.
    private func snapshot() -> [NSDictionary] {
        refreshSnapshot()
        return cachedSnapshot
    }

    private func refreshSnapshot() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            defer { refreshTask = nil }
            do {
                let contents = try await LibrarySnapshotLoader.shared.loadShared()
                let snapshot = contents.snapshot
                plugin?.setLibraryStatus(snapshot.warnings.first)
                guard snapshotRevision != snapshot.revision || snapshotGeneration != snapshot.cacheGeneration
                    || snapshotWarnings != snapshot.warnings else { return }
                let prepared = await Task.detached(priority: .userInitiated) {
                    let values: [NSDictionary] = snapshot.packs.map { pack in
                        let items: [NSDictionary] = (contents.stickers[pack.id] ?? []).map { sticker in
                            ["id": sticker.id, "name": sticker.name,
                             "thumbnail": sticker.thumbnailURL?.path ?? "",
                             "playback": sticker.playbackURL?.path ?? "",
                             "animation": sticker.animationURL?.path ?? ""]
                        }
                        return ["id": pack.id, "title": pack.title, "stickers": items,
                                "cacheGeneration": snapshot.cacheGeneration ?? ""]
                    }
                    return DesktopSnapshot(values: values, stickers: contents.byStickerID)
                }.value
                guard !Task.isCancelled else { return }
                stickers = prepared.stickers
                cachedSnapshot = prepared.values
                snapshotRevision = snapshot.revision
                snapshotGeneration = snapshot.cacheGeneration
                snapshotWarnings = snapshot.warnings
                plugin?.updateSnapshot(prepared.values)
                plugin?.setLibraryStatus(snapshot.warnings.first)
            } catch {
                plugin?.setLibraryStatus("공유 목록을 갱신하지 못했어요. 메인 앱에서 확인해 주세요.")
            }
        }
    }

    // These Foundation dictionaries are built once off-main and never mutated.
    nonisolated private struct DesktopSnapshot: @unchecked Sendable {
        let values: [NSDictionary]
        let stickers: [String: Sticker]
    }
    func showManagement() { plugin?.showManagement() }
    func togglePicker() { plugin?.togglePicker() }
    var settings: NSDictionary { plugin?.settings() ?? ["error": "맥 백그라운드 모듈을 불러오지 못했어요."] }
    func recordShortcut() { plugin?.recordShortcut() }
    func setLogin(_ enabled: Bool) { plugin?.setLoginEnabled(enabled) }
    func setMenu(_ visible: Bool) { plugin?.setMenuVisible(visible) }
}

extension Notification.Name { static let macOpenManagement = Notification.Name("macOpenManagement") }

struct MacDesktopSettings: View {
    @State private var values: NSDictionary = [:]
    var body: some View {
        Section("맥 백그라운드") {
            Toggle("로그인 시 실행", isOn: Binding(get: { values["login"] as? Bool ?? false }, set: {
                MacDesktopCoordinator.shared.setLogin($0); reload()
            }))
            Toggle("메뉴 막대 아이콘 표시", isOn: Binding(get: { values["menu"] as? Bool ?? true }, set: {
                MacDesktopCoordinator.shared.setMenu($0); reload()
            }))
            Button("스티커 팝업 열기") { MacDesktopCoordinator.shared.togglePicker() }
            HStack {
                Text("스티커 팝업 단축키")
                Spacer()
                Button(values["shortcut"] as? String ?? "⌥⇧S") {
                    MacDesktopCoordinator.shared.recordShortcut(); reload()
                }.accessibilityLabel("스티커 팝업 단축키 변경")
            }
            Text("단축키를 눌러 변경할 수 있어요. Dock에 표시하지 않고 대기하며, 지정한 단축키 또는 Finder에서 앱을 열어 접근할 수 있어요.")
                .font(.footnote).foregroundStyle(.secondary)
            if let message = values["error"] as? String, !message.isEmpty { Text(message).foregroundStyle(.orange) }
        }
        .onAppear { reload() }
    }
    private func reload() { values = MacDesktopCoordinator.shared.settings }
}
#endif
