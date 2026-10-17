#if targetEnvironment(macCatalyst)
import UIKit
import SwiftUI

@MainActor
final class MacDesktopCoordinator {
    static let shared = MacDesktopCoordinator()
    private var bundle: Bundle?
    private var plugin: DesktopPluginProtocol?
    private var stickers: [String: Sticker] = [:]
    private var library: LibraryModel?

    func start() {
        guard plugin == nil, let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("StickerBridgeDesktop.bundle"),
              let bundle = Bundle(url: url), bundle.load(),
              let type = bundle.principalClass as? NSObject.Type,
              let plugin = type.init() as? DesktopPluginProtocol else { return }
        self.bundle = bundle
        self.plugin = plugin
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
    }

    private func snapshot() -> [NSDictionary] {
        // Recreate from published manifests so every opening sees current revisions.
        let library = LibraryModel()
        self.library = library
        stickers.removeAll()
        return library.packs.map { pack in
            let items = library.stickers(in: pack).map { sticker -> NSDictionary in
                stickers[sticker.id] = sticker
                return ["id": sticker.id, "name": sticker.name,
                        "thumbnail": sticker.thumbnailURL?.path ?? ""]
            }
            return ["id": pack.id, "title": pack.title, "stickers": items]
        }
    }
    func showManagement() { plugin?.showManagement() }
    func togglePicker() { plugin?.togglePicker() }
    var settings: NSDictionary { plugin?.settings() ?? ["error": "맥 백그라운드 모듈을 불러오지 못했어요."] }
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
            Button("스티커 복사 열기 ⌥⇧S") { MacDesktopCoordinator.shared.togglePicker() }
            Text("Dock에 표시하지 않고 대기합니다. 아이콘을 숨겨도 ⌥⇧S 또는 Finder에서 앱을 열어 접근할 수 있어요.")
                .font(.footnote).foregroundStyle(.secondary)
            if let message = values["error"] as? String, !message.isEmpty { Text(message).foregroundStyle(.orange) }
        }
        .onAppear { reload() }
    }
    private func reload() { values = MacDesktopCoordinator.shared.settings }
}
#endif
