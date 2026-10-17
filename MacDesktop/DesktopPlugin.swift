import AppKit
import SwiftUI
import Carbon
import ServiceManagement

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

@MainActor
@objc(StickerBridgeDesktopPlugin)
final class DesktopPlugin: NSObject, DesktopPluginProtocol {
    private var snapshot: (() -> [NSDictionary])?
    private var copySticker: ((String) -> String?)?
    private var openManagement: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var panel: PickerPanel?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var hotKeyError = ""
    private var loginError = ""
    private let defaults = UserDefaults.standard
    private var isLoginLaunch: Bool {
        NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func start(snapshot: @escaping () -> [NSDictionary], copy: @escaping (String) -> String?, openManagement: @escaping () -> Void) {
        self.snapshot = snapshot; self.copySticker = copy; self.openManagement = openManagement
        NSApp.setActivationPolicy(.accessory)
        registerHotKey()
        updateMenu()
        if defaults.object(forKey: "mac.loginConfigured") == nil {
            defaults.set(true, forKey: "mac.loginConfigured")
            setLoginEnabled(true)
        }
        let login = isLoginLaunch
        // UIKit owns management windows; never replace its application delegate.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didBecomeMainNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let window = note.object as? NSWindow, !(window is NSPanel), login,
                      !self.managementRequested else { return }
                window.orderOut(nil)
            }
        })
        if login {
            DispatchQueue.main.async { NSApp.windows.filter { !($0 is NSPanel) }.forEach { $0.orderOut(nil) } }
        }
        // Finder reopen is delivered by AppKit even while no UIKit window is visible.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(reopen(_:reply:)), forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEReopenApplication))
    }
    private var managementRequested = false
    @objc private func reopen(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) { showManagement() }
    func showManagement() {
        managementRequested = true
        dismiss()
        openManagement?()
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
    func settings() -> NSDictionary {
        var messages = [hotKeyError, loginError].filter { !$0.isEmpty }
        if SMAppService.mainApp.status == .requiresApproval { messages.append("로그인 실행을 허용하려면 시스템 설정 → 일반 → 로그인 항목에서 StickerBridge를 허용해 주세요.") }
        return ["login": SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval,
                "menu": statusItem != nil, "error": messages.joined(separator: "\n")]
    }
    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = ""
        } catch { loginError = "로그인 실행 설정 실패: \(error.localizedDescription)" }
        updateMenu()
    }
    func setMenuVisible(_ visible: Bool) { defaults.set(visible, forKey: "mac.menuVisible"); updateMenu() }
    private func updateMenu() {
        let visible = defaults.object(forKey: "mac.menuVisible") as? Bool ?? true
        if !visible && hotKeyError.isEmpty {
            if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
            statusItem = nil; return
        }
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            statusItem?.button?.image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: "StickerBridge")
        }
        let menu = NSMenu()
        func add(_ title: String, _ selector: Selector, checked: Bool? = nil) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            item.target = self
            if let checked { item.state = checked ? .on : .off }
            menu.addItem(item)
        }
        add("스티커 복사  ⌥⇧S", #selector(pick))
        add("앱 열기", #selector(manage))
        menu.addItem(.separator())
        add("로그인 시 실행", #selector(toggleLogin), checked: SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval)
        add("메뉴 막대 아이콘 표시", #selector(toggleMenu), checked: visible)
        add("종료", #selector(quit))
        statusItem?.menu = menu
    }
    @objc private func pick() { togglePicker() }
    @objc private func manage() { showManagement() }
    @objc private func toggleLogin() { setLoginEnabled(!(SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval)) }
    @objc private func toggleMenu() { setMenuVisible(!(defaults.object(forKey: "mac.menuVisible") as? Bool ?? true)) }
    @objc private func quit() { NSApp.terminate(nil) }

    private func registerHotKey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<DesktopPlugin>.fromOpaque(context).takeUnretainedValue().togglePicker() }
            return noErr
        }, 1, &event, pointer, &handler)
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey | shiftKey), EventHotKeyID(signature: 0x53425354, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if installed != noErr || registered != noErr { hotKeyError = "⌥⇧S 단축키를 등록하지 못했어요. 다른 앱의 단축키 설정을 확인해 주세요." }
    }
    func togglePicker() {
        if panel?.isVisible == true { dismiss(); return }
        let packs = (snapshot?() ?? []).compactMap(PickerPack.init)
        let model = PickerModel(packs: packs, defaults: defaults)
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        let content = NSHostingView(rootView: PickerView(model: model, copy: { [weak self] id in
            guard let self else { return }
            if let error = self.copySticker?(id) { model.message = error }
            else if self.copySticker != nil { model.record(id); self.dismiss() }
        }, settings: { [weak self] in self?.showManagement() }))
        let glass = NSGlassEffectView(frame: panel.contentView!.bounds)
        glass.cornerRadius = 24
        glass.contentView = content
        content.frame = glass.bounds; content.autoresizingMask = [.width, .height]
        panel.contentView = glass
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            glass.wantsLayer = true; glass.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        if let rect = screen?.visibleFrame { panel.setFrameOrigin(NSPoint(x: rect.midX - 260, y: rect.midY - 180)) }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.dismiss() }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 { self?.dismiss(); return nil }
            if event.type != .keyDown && event.window !== self?.panel { self?.dismiss() }
            return event
        }) { monitors.append(monitor) }
    }
    private func dismiss() {
        panel?.orderOut(nil); panel = nil
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
    }
}

private struct PickerSticker: Identifiable {
    let id: String; let name: String; let thumbnail: String
}
private struct PickerPack: Identifiable {
    let id: String; let title: String; let stickers: [PickerSticker]
    init?(_ value: NSDictionary) {
        guard let id = value["id"] as? String, let title = value["title"] as? String else { return nil }
        self.id = id; self.title = title
        stickers = (value["stickers"] as? [NSDictionary] ?? []).compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return PickerSticker(id: id, name: $0["name"] as? String ?? "", thumbnail: $0["thumbnail"] as? String ?? "")
        }
    }
}
@MainActor @Observable
private final class PickerModel {
    let packs: [PickerPack]
    var selected: String = "recent" { didSet { defaults.set(selected, forKey: "mac.lastPack") } }
    var recent: [String]
    var message: String?
    let defaults: UserDefaults
    init(packs: [PickerPack], defaults: UserDefaults) {
        self.packs = packs; self.defaults = defaults
        let available = Set(packs.flatMap(\.stickers).map(\.id))
        var seen = Set<String>()
        recent = Array((defaults.stringArray(forKey: "mac.recentStickers") ?? []).filter { available.contains($0) && seen.insert($0).inserted }.prefix(24))
        defaults.set(recent, forKey: "mac.recentStickers")
        let previous = defaults.string(forKey: "mac.lastPack") ?? "recent"
        selected = previous == "recent" || packs.contains(where: { $0.id == previous }) ? previous : "recent"
    }
    var visible: [PickerSticker] {
        if selected == "recent" {
            let all = Dictionary(packs.flatMap(\.stickers).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return recent.compactMap { all[$0] }
        }
        return packs.first { $0.id == selected }?.stickers ?? []
    }
    func record(_ id: String) { recent.removeAll { $0 == id }; recent.insert(id, at: 0); defaults.set(Array(recent.prefix(24)), forKey: "mac.recentStickers") }
}
private struct PickerView: View {
    @Bindable var model: PickerModel
    let copy: (String) -> Void
    let settings: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("StickerBridge").font(.headline)
                Spacer()
                Text("⌥⇧S").font(.caption).foregroundStyle(.secondary)
                Button(action: settings) { Image(systemName: "gearshape") }.buttonStyle(.plain).help("설정 열기")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    tab("최근", id: "recent")
                    ForEach(model.packs) { pack in tab(pack.title, id: pack.id) }
                }
            }.scrollIndicators(.hidden)
            if model.visible.isEmpty {
                Spacer()
                Text(model.packs.isEmpty ? "앱에서 스티커 팩을 추가해 주세요." : "최근 복사한 스티커가 없어요. 팩을 선택해 주세요.")
                    .foregroundStyle(.secondary).multilineTextAlignment(.center)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 8)], spacing: 8) {
                        ForEach(model.visible) { sticker in
                            Button { copy(sticker.id) } label: {
                                Thumbnail(path: sticker.thumbnail).frame(width: 68, height: 68).frame(maxWidth: .infinity)
                            }.buttonStyle(.plain).help(sticker.name).accessibilityLabel(sticker.name)
                        }
                    }
                }
            }
            if let message = model.message { Text(message).font(.caption).foregroundStyle(.red) }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func tab(_ title: String, id: String) -> some View {
        Button { model.selected = id; model.message = nil } label: {
            Text(title).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 6)
                .background(model.selected == id ? Color.accentColor.opacity(0.22) : Color.clear, in: Capsule())
        }.buttonStyle(.plain)
    }
}
private struct Thumbnail: View {
    let path: String
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }.task(id: path) {
            let url = URL(fileURLWithPath: path)
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
