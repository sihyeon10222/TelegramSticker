import AppKit
import QuartzCore
import ImageIO
import Carbon
import ServiceManagement

private final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    var onDismiss: (() -> Void)?
    var onZoom: ((Int) -> Void)?
    var onSettings: (() -> Void)?
    func handleSettingsKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
              event.charactersIgnoringModifiers == "," else { return false }
        onSettings?()
        return true
    }
    func handleZoomKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command), !flags.contains(.control), !flags.contains(.option) else { return false }
        let key = event.charactersIgnoringModifiers ?? ""
        if ["+", "="].contains(key) || event.keyCode == 69 { onZoom?(1); return true }
        if ["-", "−"].contains(key) || event.keyCode == 78 { onZoom?(-1); return true }
        return false
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleSettingsKey(event) || handleZoomKey(event) || super.performKeyEquivalent(with: event)
    }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
}

@MainActor
@objc(StickerBridgeDesktopPlugin)
final class DesktopPlugin: NSObject, DesktopPluginProtocol, NSWindowDelegate {
    private var snapshot: (() -> [NSDictionary])?
    private var copySticker: ((String) -> String?)?
    private var openManagement: (() -> Void)?
    private var statusItem: NSStatusItem?
    private var panel: PickerPanel?
    private var pickerContent: PickerContentView?
    private var pickerSnapshot: [NSDictionary] = []
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

    func writeGIFToPasteboard(_ data: Data) throws {
        // Supply both representations on one item: image consumers read GIF bytes,
        // attachment consumers read the same animation as a real .gif file.
        let fm = FileManager.default
        let directory = try fm.url(for: .cachesDirectory, in: .userDomainMask,
                                   appropriateFor: nil, create: true)
            .appendingPathComponent("StickerBridgeClipboard", isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Sticker-\(UUID().uuidString).gif")
        try data.write(to: file, options: .atomic)
        let item = NSPasteboardItem()
        item.setString(file.absoluteString, forType: .fileURL)
        item.setPropertyList([file.path], forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        item.setData(data, forType: NSPasteboard.PasteboardType("com.compuserve.gif"))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            try? fm.removeItem(at: file)
            throw CocoaError(.fileWriteUnknown)
        }
        // Keep the current attachment after the picker closes and across app exits.
        // Only retire old exports on a later successful clipboard replacement.
        let cutoff = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        for old in (try? fm.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            guard old != file, old.pathExtension == "gif",
                  let date = try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                  date < cutoff else { continue }
            try? fm.removeItem(at: old)
        }
    }

    func start(snapshot: @escaping () -> [NSDictionary], copy: @escaping (String) -> String?, openManagement: @escaping () -> Void) {
        self.snapshot = snapshot; self.copySticker = copy; self.openManagement = openManagement
        NSApp.setActivationPolicy(.accessory)
        defaults.register(defaults: ["mac.menuVisible": true])
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
                "menu": statusItem != nil, "shortcut": shortcutLabel, "error": messages.joined(separator: "\n")]
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
        add("스티커 팝업  \(shortcutLabel)", #selector(pick))
        add("설정", #selector(manage))
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

    private var shortcutLabel: String { defaults.string(forKey: "mac.shortcutLabel") ?? "⌥⇧S" }

    func recordShortcut() {
        dismiss()
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        defer { registerHotKey(); updateMenu() }
        let alert = NSAlert()
        alert.messageText = "스티커 팝업 단축키 지정"
        alert.informativeText = "Command, Option, Control 중 하나를 포함한 단축키를 누르세요. Esc로 취소할 수 있어요."
        alert.addButton(withTitle: "저장")
        alert.addButton(withTitle: "취소")
        let field = ShortcutRecorder(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
        field.stringValue = "여기를 누르고 단축키 입력"
        field.isEditable = false; field.isSelectable = false
        field.alignment = .center; field.font = .systemFont(ofSize: 18)
        field.isBezeled = true
        alert.accessoryView = field
        alert.buttons.first?.isEnabled = false
        field.changed = { alert.buttons.first?.isEnabled = true }
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn, let candidate = field.candidate else { return }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(candidate.code, candidate.modifiers,
            EventHotKeyID(signature: 0x53425354, id: 1), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr else {
            let error = NSAlert()
            error.messageText = "이 단축키를 등록할 수 없어요."
            error.informativeText = "다른 앱에서 사용 중인지 확인하고 다른 조합을 지정해 주세요. 기존 단축키를 유지합니다."
            error.runModal()
            return
        }
        if let replacement { UnregisterEventHotKey(replacement) }
        defaults.set(Int(candidate.code), forKey: "mac.shortcutKeyCode")
        defaults.set(Int(candidate.modifiers), forKey: "mac.shortcutModifiers")
        defaults.set(field.stringValue, forKey: "mac.shortcutLabel")
    }

    private func registerHotKey() {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = handler == nil ? InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated { Unmanaged<DesktopPlugin>.fromOpaque(context).takeUnretainedValue().togglePicker() }
            return noErr
        }, 1, &event, pointer, &handler) : noErr
        let registered = RegisterEventHotKey(UInt32(defaults.object(forKey: "mac.shortcutKeyCode") as? Int ?? kVK_ANSI_S), UInt32(defaults.object(forKey: "mac.shortcutModifiers") as? Int ?? (optionKey | shiftKey)), EventHotKeyID(signature: 0x53425354, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        hotKeyError = installed == noErr && registered == noErr ? "" : "\(shortcutLabel) 단축키를 등록하지 못했어요. 다른 조합을 지정해 주세요."
    }
    private var hasLoadedSnapshot = false
    private var libraryStatus: String? = "스티커를 불러오는 중…"
    private var pendingSnapshot: [NSDictionary]?
    private var snapshotUpdate: Task<Void, Never>?
    private var snapshotUpdateID = UUID()

    func updateSnapshot(_ snapshot: [NSDictionary]) {
        let changed = !hasLoadedSnapshot || !(snapshot as NSArray).isEqual(to: pickerSnapshot)
        hasLoadedSnapshot = true
        guard changed else { return }
        if pickerSnapshot.first?["cacheGeneration"] as? String != snapshot.first?["cacheGeneration"] as? String {
            PickerMediaButton.clearPosterCache()
        }
        pickerSnapshot = snapshot
        libraryStatus = snapshot.isEmpty ? "설치한 스티커가 없어요. 앱에서 팩을 추가해 주세요." : nil
        pendingSnapshot = snapshot
        applySnapshotWhenIdle()
    }

    func setLibraryStatus(_ message: String?) {
        libraryStatus = message ?? (hasLoadedSnapshot && pickerSnapshot.isEmpty
            ? "설치한 스티커가 없어요. 앱에서 팩을 추가해 주세요." : nil)
        pickerContent?.setLibraryStatus(libraryStatus)
    }

    private func applySnapshotWhenIdle() {
        guard panel?.isVisible == true, snapshotUpdate == nil else { return }
        let id = UUID(); snapshotUpdateID = id
        snapshotUpdate = Task { [weak self] in
            guard let self else { return }
            defer { if self.snapshotUpdateID == id { self.snapshotUpdate = nil } }
            while self.pickerContent?.isInteracting == true || self.panel?.inLiveResize == true {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard self.panel?.isVisible == true else { return }
            }
            guard let pending = self.pendingSnapshot else { return }
            self.pendingSnapshot = nil
            self.pickerContent?.replacePacks(pending.compactMap(PickerPack.init))
            self.pickerContent?.setLibraryStatus(self.libraryStatus)
        }
    }

    func togglePicker() {
        if panel?.isVisible == true { dismiss(); return }
        _ = snapshot?() // Starts an asynchronous refresh while retaining the current page.
        if panel == nil {
            buildPicker(packs: pickerSnapshot.compactMap(PickerPack.init))
            pendingSnapshot = nil
        } else if let pending = pendingSnapshot {
            pendingSnapshot = nil
            pickerContent?.replacePacks(pending.compactMap(PickerPack.init))
        }
        guard let panel else { return }
        pickerContent?.setLibraryStatus(libraryStatus)
        pickerContent?.resumePreviews()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.makeKeyAndOrderFront(nil)
        installPickerMonitors()
    }

    private func buildPicker(packs: [PickerPack]) {
        let model = PickerModel(packs: packs, defaults: defaults, allowPruning: hasLoadedSnapshot)
        // Keep the compact tab row inside the content hit-testing area, without an overlaid titlebar.
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360), styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.title = "StickerBridge"
        panel.isMovableByWindowBackground = true
        panel.minSize = NSSize(width: 360, height: 260)
        panel.delegate = self
        panel.onDismiss = { [weak self] in self?.dismiss() }
        let content = PickerContentView(model: model, copy: { [weak self] id in
            guard let self else { return }
            if let error = self.copySticker?(id) { model.message = error }
            else if self.copySticker != nil { model.record(id); self.dismiss() }
        })
        pickerContent = content
        panel.onSettings = { [weak self] in self?.showManagement() }
        panel.onZoom = { [weak content] step in content?.zoom(by: step) }
        let glass = NSGlassEffectView(frame: panel.contentView!.bounds)
        glass.style = .regular
        glass.cornerRadius = 24
        glass.contentView = content
        content.frame = glass.bounds; content.autoresizingMask = [.width, .height]
        panel.contentView = glass
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            glass.wantsLayer = true; glass.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
        panel.setFrame(restoredPickerFrame(), display: false)
        self.panel = panel
    }

    private func installPickerMonitors() {
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            guard self?.pickerContent?.isTrackingTabInteraction != true else { return }
            self?.dismiss()
        }) { monitors.append(monitor) }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown], handler: { [weak self] event in
            if self?.pickerContent?.isTrackingTabInteraction == true { return event }
            if event.type == .keyDown, event.window === self?.panel {
                if self?.panel?.handleSettingsKey(event) == true || self?.panel?.handleZoomKey(event) == true { return nil }
            }
            if event.type == .keyDown && event.keyCode == 53 { self?.dismiss(); return nil }
            if event.type != .keyDown && event.window !== self?.panel { self?.dismiss() }
            return event
        }) { monitors.append(monitor) }
    }
    func windowDidMove(_ notification: Notification) { savePickerFrame() }
    func windowDidResize(_ notification: Notification) { savePickerFrame() }

    private func savePickerFrame() {
        guard let panel, panel.isVisible else { return }
        let frame = panel.frame
        defaults.set([frame.origin.x, frame.origin.y, frame.width, frame.height], forKey: "mac.pickerFrame.v1")
    }

    private func restoredPickerFrame() -> NSRect {
        let mouseScreen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let fallback = mouseScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var frame = NSRect(x: fallback.midX - 260, y: fallback.midY - 180, width: 520, height: 360)
        if let values = defaults.array(forKey: "mac.pickerFrame.v1") as? [Double],
           values.count == 4, values.allSatisfy({ $0.isFinite }), values[2] > 0, values[3] > 0 {
            frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        }
        // Restore to the original display when available; recover windows from removed displays.
        let screen = NSScreen.screens.max { lhs, rhs in
            let a = frame.intersection(lhs.visibleFrame), b = frame.intersection(rhs.visibleFrame)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }
        let visible = screen.flatMap { frame.intersects($0.visibleFrame) ? $0.visibleFrame : nil } ?? fallback
        frame.size.width = min(max(frame.width, 360), visible.width)
        frame.size.height = min(max(frame.height, 260), visible.height)
        frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        return frame
    }

    private func dismiss() {
        snapshotUpdateID = UUID()
        snapshotUpdate?.cancel(); snapshotUpdate = nil
        savePickerFrame()
        pickerContent?.suspendPreviews()
        panel?.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor); monitors.removeAll()
    }
}

private struct PickerSticker: Identifiable {
    let id: String
    let name: String
    let thumbnail: String
    let playback: String
    let animation: String
}
private struct PickerPack: Identifiable {
    let id: String
    let title: String
    let stickers: [PickerSticker]
    init?(_ value: NSDictionary) {
        guard let id = value["id"] as? String, let title = value["title"] as? String else { return nil }
        self.id = id; self.title = title
        stickers = (value["stickers"] as? [NSDictionary] ?? []).compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return PickerSticker(id: id, name: $0["name"] as? String ?? "",
                                 thumbnail: $0["thumbnail"] as? String ?? "",
                                 playback: $0["playback"] as? String ?? "",
                                 animation: $0["animation"] as? String ?? "")
        }
    }
}
private struct PickerSection {
    let title: String?
    let stickers: [PickerSticker]
}
@MainActor
private final class PickerModel {
    private(set) var packs: [PickerPack]
    private(set) var libraryLoaded: Bool
    var selected: String = "all" { didSet { defaults.set(selected, forKey: "mac.lastPack") } }
    private(set) var recent: [String]
    var message: String? { didSet { onMessage?(message) } }
    var onMessage: ((String?) -> Void)?
    private(set) var cellTarget: CGFloat = 72
    func setCellTarget(_ size: CGFloat, persist: Bool) {
        guard size.isFinite else { return }
        cellTarget = min(144, max(36, size))
        if persist { defaults.set(Double(cellTarget), forKey: "mac.pickerCellSize.v1") }
    }
    let defaults: UserDefaults
    var choices: [String] { ["all", "recent"] + packs.map(\.id) }

    init(packs: [PickerPack], defaults: UserDefaults, allowPruning: Bool = true) {
        self.packs = packs; self.defaults = defaults; libraryLoaded = allowPruning
        let savedSize = defaults.double(forKey: "mac.pickerCellSize.v1")
        cellTarget = savedSize.isFinite && savedSize >= 36 && savedSize <= 144 ? savedSize : 72
        let available = Set(packs.flatMap(\.stickers).map(\.id))
        var seen = Set<String>()
        recent = Array((defaults.stringArray(forKey: "mac.recentStickers") ?? []).filter { (!allowPruning || available.contains($0)) && seen.insert($0).inserted }.prefix(24))
        if allowPruning { defaults.set(recent, forKey: "mac.recentStickers") }
        applyPackOrder(prune: allowPruning)
        let previous = defaults.string(forKey: "mac.lastPack") ?? "all"
        selected = !allowPruning || choices.contains(previous) ? previous : "all"
    }
    func replacePacks(_ packs: [PickerPack]) {
        self.packs = packs
        libraryLoaded = true
        applyPackOrder(prune: true)
        let available = Set(packs.flatMap(\.stickers).map(\.id))
        recent = recent.filter { available.contains($0) }
        defaults.set(recent, forKey: "mac.recentStickers")
        if !choices.contains(selected) { selected = "all" }
    }

    func sections(for id: String) -> [PickerSection] {
        if id == "all" { return packs.map { PickerSection(title: $0.title, stickers: $0.stickers) } }
        if id == "recent" {
            let all = Dictionary(packs.flatMap(\.stickers).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return [PickerSection(title: nil, stickers: recent.compactMap { all[$0] })]
        }
        return [PickerSection(title: nil, stickers: packs.first { $0.id == id }?.stickers ?? [])]
    }
    func record(_ id: String) {
        recent.removeAll { $0 == id }; recent.insert(id, at: 0)
        defaults.set(Array(recent.prefix(24)), forKey: "mac.recentStickers")
    }
    func clearRecent() {
        recent = []
        defaults.removeObject(forKey: "mac.recentStickers")
        defaults.removeObject(forKey: "mac.pickerScroll.v1.recent")
    }
    @discardableResult
    func movePack(_ id: String, to index: Int) -> Bool {
        guard let from = packs.firstIndex(where: { $0.id == id }), packs.indices.contains(index) else { return false }
        guard from != index else { return true }
        let pack = packs.remove(at: from)
        packs.insert(pack, at: index)
        defaults.set(packs.map(\.id), forKey: "mac.pickerPackOrder.v1")
        return true
    }
    private func applyPackOrder(prune: Bool) {
        guard let saved = defaults.stringArray(forKey: "mac.pickerPackOrder.v1") else { return }
        let ranks = Dictionary(saved.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { min($0, $1) })
        packs = packs.enumerated().sorted {
            let lhs = ranks[$0.element.id] ?? Int.max, rhs = ranks[$1.element.id] ?? Int.max
            return lhs == rhs ? $0.offset < $1.offset : lhs < rhs
        }.map(\.element)
        if prune { defaults.set(packs.map(\.id), forKey: "mac.pickerPackOrder.v1") }
    }
}

private enum PickerLayout {
    static let stickerSpacing: CGFloat = 2
}

/// AppKit-only UI: Catalyst's SwiftUI image cannot host macOS NSHostingView.
@MainActor
private final class PickerContentView: NSView, NSMenuDelegate {
    private let model: PickerModel
    private let copy: (String) -> Void
    private let tabs = PickerPackTabStrip(frame: .zero)
    private let tabScroll = NSScrollView()
    private let viewport = PickerViewport()
    private let gestures = PickerSwipeHandler()
    private var tabObserver: NSObjectProtocol?
    private let message = NSTextField(wrappingLabelWithString: "")
    private var current: PickerPageView!
    private var incoming: PickerPageView?
    private var incomingID: String?
    private var incomingStep = 0
    private var dragging = false
    private var settling = false
    private var transitionToken = 0
    private var settlementCommits = false
    private var needsRevealTab = true
    private var dragConsumed: CGFloat = 0
    private var pinching = false
    private var pinchStart: CGFloat = 72
    private var pinchScale: CGFloat = 1
    private var reorderingPacks = false
    private var packOrderChanged = false
    private var trackingRecentMenu = false

    init(model: PickerModel, copy: @escaping (String) -> Void) {
        self.model = model; self.copy = copy
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
        tabs.orientation = .horizontal; tabs.spacing = 6
        tabs.onBeginDrag = { [weak self] in self?.beginPackReordering() }
        tabs.onEndDrag = { [weak self] in self?.endPackReordering() }
        tabs.onMovePack = { [weak self] id, index in
            guard let self else { return false }
            let previous = self.model.packs.map(\.id)
            guard self.model.movePack(id, to: index) else { return false }
            self.packOrderChanged = previous != self.model.packs.map(\.id)
            return true
        }
        tabScroll.drawsBackground = false; tabScroll.hasHorizontalScroller = false
        tabScroll.documentView = tabs
        tabs.translatesAutoresizingMaskIntoConstraints = false
        viewport.wantsLayer = true; viewport.layer?.masksToBounds = true
        message.font = .systemFont(ofSize: 11); message.textColor = .systemRed
        let stack = NSStackView(views: [tabScroll, viewport, message])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PickerLayout.stickerSpacing),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PickerLayout.stickerSpacing),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: PickerLayout.stickerSpacing),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -PickerLayout.stickerSpacing),
            tabScroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            tabScroll.heightAnchor.constraint(equalToConstant: 40),
            tabs.heightAnchor.constraint(equalTo: tabScroll.contentView.heightAnchor),
            tabs.leadingAnchor.constraint(equalTo: tabScroll.contentView.leadingAnchor),
            tabs.topAnchor.constraint(equalTo: tabScroll.contentView.topAnchor),
            viewport.widthAnchor.constraint(equalTo: stack.widthAnchor),
            viewport.heightAnchor.constraint(greaterThanOrEqualToConstant: 80),
            message.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        model.onMessage = { [weak self] text in
            self?.message.stringValue = text ?? ""; self?.message.isHidden = text == nil
        }
        message.isHidden = true
        current = makePage(id: model.selected)
        viewport.addSubview(current)
        gestures.onDrag = { [weak self] offset in self?.dragPage(offset: offset) }
        gestures.onEndDrag = { [weak self] offset, velocity, cancelled in self?.endDrag(offset: offset, velocity: velocity, cancelled: cancelled) }
        gestures.onChangePack = { [weak self] step in self?.changePack(by: step) }
        gestures.onVerticalScroll = { [weak self] event in self?.current.scrollVertically(with: event) }
        viewport.onScrollEvent = { [weak self] event in self?.gestures.scrollWheel(with: event) }
        viewport.onSwipeEvent = { [weak self] event in self?.gestures.swipe(with: event) }
        viewport.onMagnifyEvent = { [weak self] event in self?.magnify(with: event) }
        tabScroll.contentView.postsBoundsChangedNotifications = true
        tabObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: tabScroll.contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTabPreviews() }
        }
        buildTabs()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let tabObserver { NotificationCenter.default.removeObserver(tabObserver) } }
    override func layout() {
        super.layout()
        if current.frame.size != viewport.bounds.size {
            // Resizing cancels an unfinished turn and preserves the selected pack.
            transitionToken += 1
            current.layer?.removeAllAnimations()
            incoming?.removeFromSuperview(); incoming = nil; incomingID = nil
            dragging = false; settling = false
            current.frame = viewport.bounds
            current.setZooming(pinching)
        }
        if !dragging && !settling { current.frame = viewport.bounds }
        current.layoutSubtreeIfNeeded()
        current.updatePreviews()
        updateTabPreviews()
        if needsRevealTab && tabScroll.bounds.width > 0 {
            tabs.layoutSubtreeIfNeeded()
            revealSelectedTab(); needsRevealTab = false
        }
    }
    var isTrackingTabInteraction: Bool { reorderingPacks || trackingRecentMenu }
    var isInteracting: Bool { dragging || settling || pinching || isTrackingTabInteraction }

    private func beginPackReordering() {
        interruptSettlement()
        reorderingPacks = true; packOrderChanged = false
        needsRevealTab = false
        current.setZooming(true)
        tabs.arrangedSubviews.forEach { ($0 as? PickerMediaButton)?.setPlaybackSuspended(true) }
    }
    private func endPackReordering() {
        let tabOrigin = tabScroll.contentView.bounds.origin
        reorderingPacks = false
        if packOrderChanged {
            packOrderChanged = false
            for view in tabs.arrangedSubviews { tabs.removeArrangedSubview(view); view.removeFromSuperview() }
            buildTabs()
            if model.selected == "all" { reloadCurrentPage() }
        }
        if window?.isVisible == true {
            resumePreviews()
            needsRevealTab = false
            tabs.layoutSubtreeIfNeeded()
            tabScroll.contentView.scroll(to: tabOrigin)
            tabScroll.reflectScrolledClipView(tabScroll.contentView)
        }
    }
    private func reloadCurrentPage() {
        current.stopPreviews(); current.removeFromSuperview()
        current = makePage(id: model.selected)
        viewport.addSubview(current)
        needsLayout = true
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first?.isEnabled = !model.recent.isEmpty
    }
    func menuWillOpen(_ menu: NSMenu) {
        trackingRecentMenu = true
        interruptSettlement()
    }
    func menuDidClose(_ menu: NSMenu) { trackingRecentMenu = false }
    @objc private func clearRecentStickers(_ sender: NSMenuItem) {
        interruptSettlement()
        let showingRecent = model.selected == "recent"
        if showingRecent { current.stopPreviews(); current.removeFromSuperview() }
        model.clearRecent()
        if showingRecent {
            current = makePage(id: "recent")
            viewport.addSubview(current)
            needsLayout = true
        }
    }

    func setLibraryStatus(_ text: String?) { model.message = text }

    func replacePacks(_ packs: [PickerPack]) {
        interruptSettlement()
        current.stopPreviews()
        current.removeFromSuperview()
        incoming?.stopPreviews(); incoming?.removeFromSuperview(); incoming = nil; incomingID = nil
        model.replacePacks(packs)
        for view in tabs.arrangedSubviews { tabs.removeArrangedSubview(view); view.removeFromSuperview() }
        current = makePage(id: model.selected)
        viewport.addSubview(current)
        buildTabs()
        resumePreviews()
    }

    func suspendPreviews() {
        interruptSettlement()
        current.saveScrollPosition()
        current.setZooming(true)
        tabs.arrangedSubviews.forEach { ($0 as? PickerMediaButton)?.setPlaybackSuspended(true) }
    }
    func resumePreviews() {
        if model.selected == "recent", current.stickerIDs != model.sections(for: "recent").flatMap(\.stickers).map(\.id) {
            current.removeFromSuperview()
            current = makePage(id: model.selected)
            viewport.addSubview(current)
        }
        current.setZooming(false)
        tabs.arrangedSubviews.forEach { ($0 as? PickerMediaButton)?.setPlaybackSuspended(false) }
        needsRevealTab = true
        needsLayout = true
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            model.setCellTarget(model.cellTarget, persist: true)
            current?.stopPreviews(); incoming?.stopPreviews()
        }
        super.viewWillMove(toWindow: newWindow)
    }
    @objc private func zoomOut() { zoom(by: -1) }
    @objc private func zoomIn() { zoom(by: 1) }
    func zoom(by step: Int) {
        interruptSettlement()
        pinching = false
        current.setZooming(false)
        applyCellTarget(model.cellTarget * pow(1.15, CGFloat(step)), persist: true)
    }
    override func magnify(with event: NSEvent) {
        if !pinching {
            interruptSettlement()
            pinching = true; pinchStart = model.cellTarget; pinchScale = 1
            current.setZooming(true)
        }
        pinchScale = min(144 / pinchStart, max(36 / pinchStart, pinchScale * max(0.1, 1 + event.magnification)))
        let ending = event.phase.contains(.ended) || event.phase.contains(.cancelled) || event.phase.isEmpty
        applyCellTarget(event.phase.contains(.cancelled) ? pinchStart : pinchStart * pinchScale, persist: ending)
        if ending { pinching = false; current.setZooming(false) }
    }
    private func applyCellTarget(_ size: CGFloat, persist: Bool) {
        model.setCellTarget(size, persist: persist)
        current.setCellTarget(model.cellTarget)
        incoming?.setCellTarget(model.cellTarget)
    }
    private func makePage(id: String) -> PickerPageView {
        let emptyMessage = !model.libraryLoaded ? "" : id == "recent"
            ? "최근 사용한 스티커가 없어요. 전체에서 스티커를 복사해 보세요."
            : "앱에서 스티커 팩을 추가해 주세요."
        let page = PickerPageView(sections: model.sections(for: id), emptyMessage: emptyMessage, copy: copy)
        page.setCellTarget(model.cellTarget)
        page.frame = viewport.bounds
        page.pendingScrollOffset = model.defaults.double(forKey: "mac.pickerScroll.v1." + id)
        page.onScrollPosition = { [weak model] offset in
            guard let model, model.libraryLoaded else { return }
            model.defaults.set(Double(offset), forKey: "mac.pickerScroll.v1." + id)
        }
        page.onMagnifyEvent = { [weak self] event in self?.magnify(with: event) }
        page.onScrollEvent = { [weak self] event in self?.gestures.scrollWheel(with: event) }
        page.onSwipeEvent = { [weak self] event in self?.gestures.swipe(with: event) }
        return page
    }
    private func changePack(by step: Int) {
        interruptSettlement()
        guard let index = model.choices.firstIndex(of: model.selected),
              model.choices.indices.contains(index + step) else { return }
        selectPack(id: model.choices[index + step])
    }
    private func prepareIncoming(step: Int, suspendPlayback: Bool = false) -> Bool {
        guard let index = model.choices.firstIndex(of: model.selected),
              model.choices.indices.contains(index + step) else { return false }
        let id = model.choices[index + step]
        if incomingID != id {
            incoming?.removeFromSuperview()
            incoming = makePage(id: id); incomingID = id; incomingStep = step
            if let incoming {
                incoming.setZooming(suspendPlayback)
                incoming.frame.origin.x = CGFloat(step) * viewport.bounds.width
                viewport.addSubview(incoming)
                incoming.layoutSubtreeIfNeeded(); incoming.updatePreviews()
            }
        }
        return true
    }
    private func dragPage(offset: CGFloat) {
        interruptSettlement()
        if !dragging { dragConsumed = 0 }
        dragging = true
        let width = max(1, viewport.bounds.width)
        var residual = offset - dragConsumed
        // Consume complete pages while contact continues; preserve the remaining
        // displacement so the next page follows the same continuous gesture.
        while abs(residual) >= width {
            let step = residual < 0 ? 1 : -1
            guard prepareIncoming(step: step), let next = incoming, let id = incomingID else { break }
            current.stopPreviews(); current.removeFromSuperview()
            current = next; current.frame = viewport.bounds
            model.selected = id; model.message = nil
            incoming = nil; incomingID = nil
            dragConsumed -= CGFloat(step) * width
            residual = offset - dragConsumed
            updateTabs()
        }
        let step = residual < 0 ? 1 : -1
        let available = prepareIncoming(step: step)
        let movement = available ? max(-width, min(width, residual)) : residual * 0.55 * width / (width + 0.55 * abs(residual))
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        current.frame.origin.x = reduced ? 0 : movement
        if available { incoming?.frame.origin.x = reduced ? CGFloat(step) * width : movement + CGFloat(step) * width }
        else { incoming?.removeFromSuperview(); incoming = nil; incomingID = nil }
    }
    private func endDrag(offset: CGFloat, velocity: CGFloat, cancelled: Bool) {
        guard !settling else { return }
        let residual = offset - dragConsumed
        dragging = false; dragConsumed = 0
        let step = residual < 0 ? 1 : -1
        let projected = residual + velocity * 0.18
        let commit = !cancelled && projected * CGFloat(-step) > viewport.bounds.width * 0.28
        if commit, prepareIncoming(step: step) { settle(commit: true, velocity: velocity) }
        else { settle(commit: false, velocity: velocity) }
    }
    private func selectPack(id: String, viaTab: Bool = false) {
        interruptSettlement()
        guard id != model.selected,
              let old = model.choices.firstIndex(of: model.selected), let new = model.choices.firstIndex(of: id) else { return }
        let distance = abs(new - old)
        if viaTab, distance > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // Traverse each intervening pack without a spring stop at every page.
            let duration = max(0.024, min(0.07, 0.42 / Double(distance - 1)))
            advanceTabSelection(to: id, duration: duration)
            return
        }
        incoming?.removeFromSuperview()
        incoming = makePage(id: id); incomingID = id; incomingStep = new > old ? 1 : -1
        incoming!.frame.origin.x = CGFloat(incomingStep) * viewport.bounds.width
        viewport.addSubview(incoming!)
        incoming!.layoutSubtreeIfNeeded(); incoming!.updatePreviews()
        settle(commit: true, duration: viaTab ? 0.18 : nil)
    }
    private func advanceTabSelection(to id: String, duration: TimeInterval) {
        guard let old = model.choices.firstIndex(of: model.selected),
              let new = model.choices.firstIndex(of: id), old != new,
              prepareIncoming(step: new > old ? 1 : -1, suspendPlayback: true) else { return }
        current.setZooming(true)
        incoming?.setZooming(true)
        let last = abs(new - old) == 1
        settle(commit: true, duration: last ? 0.14 : duration, continuation: last ? nil : { [weak self] in
            self?.advanceTabSelection(to: id, duration: duration)
        })
    }
    private func interruptSettlement() {
        guard settling else { return }
        transitionToken += 1
        current.layer?.removeAllAnimations()
        incoming?.layer?.removeAllAnimations()
        if settlementCommits, let incoming, let id = incomingID {
            current.stopPreviews(); current.removeFromSuperview()
            current = incoming
            model.selected = id; model.message = nil
            updateTabs()
        } else { incoming?.stopPreviews(); incoming?.removeFromSuperview() }
        incoming = nil; incomingID = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            current.animator().setFrameOrigin(.zero)
        }
        current.frame = viewport.bounds
        current.setZooming(false)
        settling = false; dragging = false
    }
    private func settle(commit: Bool, velocity: CGFloat = 0, duration: TimeInterval? = nil, continuation: (() -> Void)? = nil) {
        settlementCommits = commit
        settling = true
        transitionToken += 1
        let token = transitionToken
        let width = viewport.bounds.width
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let finish: () -> Void = { [weak self] in
            guard let self, token == self.transitionToken else { return }
            if commit, let incoming = self.incoming, let id = self.incomingID {
                self.current.stopPreviews(); self.current.removeFromSuperview()
                self.current = incoming
                self.model.selected = id; self.model.message = nil
                self.updateTabs()
            } else { self.incoming?.stopPreviews(); self.incoming?.removeFromSuperview() }
            self.incoming = nil; self.incomingID = nil
            self.current.frame = self.viewport.bounds
            if continuation == nil { self.current.setZooming(false) }
            self.current.updatePreviews()
            self.settling = false; self.dragging = false
            continuation?()
        }
        if reduced { finish(); return }
        // Clicks pass intermediate pages at constant speed; swipes retain their release spring.
        let destination = commit ? -CGFloat(incomingStep) * width : 0
        let start = current.frame.origin.x
        let animation: CABasicAnimation
        if let duration {
            animation = CABasicAnimation(keyPath: "position.x")
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: continuation == nil ? .easeOut : .linear)
        } else {
            let spring = CASpringAnimation(keyPath: "position.x")
            spring.mass = 1; spring.stiffness = 300; spring.damping = 34
            let remaining = destination - start
            spring.initialVelocity = abs(remaining) > 1 ? max(-20, min(20, velocity / remaining)) : 0
            spring.duration = spring.settlingDuration
            animation = spring
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let currentPosition = current.layer?.position.x ?? 0
        let incomingPosition = incoming?.layer?.position.x ?? 0
        current.setFrameOrigin(NSPoint(x: destination, y: 0))
        incoming?.setFrameOrigin(NSPoint(x: destination + CGFloat(incomingStep) * width, y: 0))
        CATransaction.commit()
        animation.fromValue = currentPosition
        animation.toValue = currentPosition + destination - start
        current.layer?.add(animation, forKey: "pageSpring")
        if let incoming {
            let next = animation.copy() as! CABasicAnimation
            next.fromValue = incomingPosition
            next.toValue = incomingPosition + destination - start
            incoming.layer?.add(next, forKey: "pageSpring")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration) {
            MainActor.assumeIsolated { finish() }
        }
    }
    private func buildTabs() {
        for (id, label, symbol) in [("all", "전체", "square.grid.2x2"), ("recent", "최근 사용", "clock")] {
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!, target: self, action: #selector(selectTab(_:)))
            configureTab(button, id: id, label: label)
            if id == "recent" {
                let menu = NSMenu()
                menu.autoenablesItems = false; menu.delegate = self
                let clear = NSMenuItem(title: "최근 사용 내역 지우기", action: #selector(clearRecentStickers(_:)), keyEquivalent: "")
                clear.target = self
                clear.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
                menu.addItem(clear)
                button.menu = menu
            }
        }
        for pack in model.packs {
            let button = PickerPackTabButton(sticker: pack.stickers.first, target: self, action: #selector(selectTab(_:)))
            button.tabStrip = tabs
            configureTab(button, id: pack.id, label: pack.title)
        }
        updateTabs()
    }
    private func configureTab(_ button: NSButton, id: String, label: String) {
        button.identifier = NSUserInterfaceItemIdentifier(id)
        button.toolTip = label; button.setAccessibilityLabel(label)
        button.isBordered = false; button.wantsLayer = true
        button.layer?.cornerRadius = 10
        tabs.addArrangedSubview(button)
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
    }
    private func updateTabs() {
        for button in tabs.arrangedSubviews.compactMap({ $0 as? NSButton }) {
            let selected = button.identifier?.rawValue == model.selected
            button.state = selected ? .on : .off
            button.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
            button.layer?.backgroundColor = selected ? NSColor.controlAccentColor.withAlphaComponent(0.14).cgColor : nil
            button.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
            button.layer?.borderWidth = selected ? 1 : 0
        }
        needsRevealTab = true; needsLayout = true
    }
    private func updateTabPreviews() {
        guard window != nil else { return }
        let visible = tabScroll.documentVisibleRect
        for button in tabs.arrangedSubviews.compactMap({ $0 as? PickerMediaButton }) {
            button.setPreviewVisible(button.frame.intersects(visible))
        }
    }
    private func revealSelectedTab() {
        if let selected = tabs.arrangedSubviews.first(where: { $0.identifier?.rawValue == model.selected }) {
            tabs.scrollToVisible(selected.frame.insetBy(dx: -6, dy: 0))
        }
    }
    @objc private func selectTab(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue { selectPack(id: id, viaTab: true) }
    }
}

/// NSImageView plays GIF frame timing natively; clicks continue to the enclosing button.
private final class PickerPreviewImage: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
// Separate serial lanes keep PNG posters responsive while GIF files are read.
private actor PickerMediaLoader {
    static let posters = PickerMediaLoader()
    static let animations = PickerMediaLoader()
    func data(_ path: String) -> Data? {
        guard !Task.isCancelled else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: path))
    }
    func poster(_ path: String) -> CGImage? {
        guard !Task.isCancelled, !path.isEmpty,
              let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 160,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }
}

@MainActor
private class PickerMediaButton: NSButton {
    private let preview = PickerPreviewImage()
    private var sticker: PickerSticker?
    private var suspended = false
    private var loading: Task<Void, Never>?
    private var previewVisible = false
    private var mediaLoaded = false
    private static let posters = NSCache<NSString, NSImage>()
    static func clearPosterCache() { posters.removeAllObjects() }

    init(sticker: PickerSticker?, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target; self.action = action
        title = ""; isBordered = false
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        preview.frame = .zero
        addSubview(preview)
        if let sticker { configure(sticker: sticker) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layout() {
        super.layout()
        preview.frame = NSRect(x: 1, y: 1, width: max(0, bounds.width - 2), height: max(0, bounds.height - 2))
    }
    func configure(sticker: PickerSticker) {
        guard self.sticker?.id != sticker.id else { return }
        setPreviewVisible(false)
        self.sticker = sticker
        mediaLoaded = false
        preview.image = Self.posters.object(forKey: sticker.thumbnail as NSString)
        identifier = NSUserInterfaceItemIdentifier(sticker.id)
        toolTip = sticker.name; setAccessibilityLabel(sticker.name)
    }
    private var posterTask: Task<Void, Never>?
    private func loadPosterIfNeeded() {
        guard preview.image == nil, posterTask == nil, let sticker else { return }
        posterTask = Task { [weak self] in
            let image = await PickerMediaLoader.posters.poster(sticker.thumbnail)
            guard let self, !Task.isCancelled, self.sticker?.id == sticker.id else { return }
            self.posterTask = nil
            guard let image else { return }
            let poster = NSImage(cgImage: image, size: .zero)
            Self.posters.totalCostLimit = 8 * 1024 * 1024
            Self.posters.setObject(poster, forKey: sticker.thumbnail as NSString, cost: image.bytesPerRow * image.height)
            if !self.mediaLoaded { self.preview.image = poster }
        }
    }
    func setPlaybackSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        preview.animates = previewVisible && !suspended
        if value { loading?.cancel(); loading = nil }
        else { loadAnimationIfNeeded() }
    }
    func setPreviewVisible(_ visible: Bool) {
        guard previewVisible != visible else { return }
        previewVisible = visible
        loading?.cancel(); loading = nil
        preview.animates = visible && !suspended
        if !visible { posterTask?.cancel(); posterTask = nil; return }
        loadPosterIfNeeded()
        loadAnimationIfNeeded()
    }
    private func loadAnimationIfNeeded() {
        guard previewVisible, !suspended, !mediaLoaded, loading == nil, let sticker else { return }
        let paths = [sticker.playback, sticker.animation].filter { !$0.isEmpty }
        guard !paths.isEmpty else { return }
        loading = Task { [weak self] in
            for path in paths {
                let data = await PickerMediaLoader.animations.data(path)
                guard !Task.isCancelled, let self, self.previewVisible, !self.suspended,
                      self.sticker?.id == sticker.id else { return }
                if let data, let image = NSImage(data: data) {
                    self.mediaLoaded = true
                    self.preview.image = image
                    self.preview.animates = true
                    self.loading = nil
                    return
                }
            }
            self?.loading = nil
        }
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { setPreviewVisible(false) }
        super.viewWillMove(toWindow: newWindow)
    }
}

/// Only pack tabs participate; the all/recent controls keep their fixed positions.
@MainActor
private final class PickerPackTabStrip: NSStackView {
    static let pasteboardType = NSPasteboard.PasteboardType("com.sihyeon.TelegramSticker.picker-pack")
    var onBeginDrag: (() -> Void)?
    var onEndDrag: (() -> Void)?
    var onMovePack: ((String, Int) -> Bool)?
    private var insertionX: CGFloat? { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([Self.pasteboardType])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let x = insertionX else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: NSRect(x: x - 1, y: 3, width: 2, height: max(0, bounds.height - 6)),
                     xRadius: 1, yRadius: 1).fill()
    }
    private func source(for sender: NSDraggingInfo) -> PickerPackTabButton? {
        guard let source = sender.draggingSource as? PickerPackTabButton, source.tabStrip === self,
              let id = source.identifier?.rawValue,
              sender.draggingPasteboard.string(forType: Self.pasteboardType) == id,
              sender.draggingSourceOperationMask.contains(.move) else { return nil }
        return source
    }
    private func insertion(for sender: NSDraggingInfo, source: PickerPackTabButton) -> Int {
        let point = convert(sender.draggingLocation, from: nil)
        let others = arrangedSubviews.compactMap { $0 as? PickerPackTabButton }.filter { $0 !== source }
        let index = others.firstIndex(where: { point.x < $0.frame.midX }) ?? others.count
        if index < others.count { insertionX = others[index].frame.minX - spacing / 2 }
        else { insertionX = (others.last ?? source).frame.maxX + spacing / 2 }
        return index
    }
    private func updateDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let source = source(for: sender) else { insertionX = nil; return [] }
        if let scroll = enclosingScrollView {
            let clip = scroll.contentView
            let point = convert(sender.draggingLocation, from: nil)
            let visible = visibleRect
            let delta: CGFloat = point.x < visible.minX + 22 ? -12 : point.x > visible.maxX - 22 ? 12 : 0
            let x = min(max(0, clip.bounds.minX + delta), max(0, bounds.width - clip.bounds.width))
            if x != clip.bounds.minX {
                clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
                scroll.reflectScrolledClipView(clip)
            }
        }
        _ = insertion(for: sender, source: source)
        return .move
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrop(sender) }
    override func wantsPeriodicDraggingUpdates() -> Bool { true }
    override func draggingExited(_ sender: NSDraggingInfo?) { insertionX = nil }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { source(for: sender) != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { insertionX = nil }
        guard let source = source(for: sender), let id = source.identifier?.rawValue,
              visibleRect.contains(convert(sender.draggingLocation, from: nil)) else { return false }
        return onMovePack?(id, insertion(for: sender, source: source)) ?? false
    }
    func finishDragging() {
        insertionX = nil
        onEndDrag?()
    }
}

@MainActor
private final class PickerPackTabButton: PickerMediaButton, NSDraggingSource {
    weak var tabStrip: PickerPackTabStrip?
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, let window, let tabStrip, let id = identifier?.rawValue else {
            super.mouseDown(with: event); return
        }
        highlight(true)
        defer { highlight(false) }
        let start = event.locationInWindow
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
                                          inMode: .eventTracking, dequeue: true) {
            guard self.window === window, window.isVisible else { return }
            if next.type == .leftMouseUp {
                if bounds.contains(convert(next.locationInWindow, from: nil)) { performClick(nil) }
                return
            }
            let point = next.locationInWindow
            guard hypot(point.x - start.x, point.y - start.y) >= 4 else { continue }
            highlight(false)
            let image = NSImage(size: bounds.size)
            if let bitmap = bitmapImageRepForCachingDisplay(in: bounds) {
                cacheDisplay(in: bounds, to: bitmap)
                image.addRepresentation(bitmap)
            }
            let item = NSPasteboardItem()
            item.setString(id, forType: PickerPackTabStrip.pasteboardType)
            let draggingItem = NSDraggingItem(pasteboardWriter: item)
            draggingItem.setDraggingFrame(bounds, contents: image)
            tabStrip.onBeginDrag?()
            alphaValue = 0.35
            beginDraggingSession(with: [draggingItem], event: event, source: self)
            return
        }
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }
    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        alphaValue = 1
        tabStrip?.finishDragging()
    }
}

/// A lightweight document owns geometry; only viewport cells exist as AppKit controls.
private final class PickerGridDocument: NSView {
    override var isFlipped: Bool { true }
}
@MainActor
private final class PickerPageView: NSScrollView {
    var pendingScrollOffset: Double?
    var onScrollPosition: ((CGFloat) -> Void)?
    var onScrollEvent: ((NSEvent) -> Void)?
    var onSwipeEvent: ((NSEvent) -> Void)?
    var onMagnifyEvent: ((NSEvent) -> Void)?
    override func magnify(with event: NSEvent) { onMagnifyEvent?(event) }
    override func scrollWheel(with event: NSEvent) { onScrollEvent?(event) }
    override func swipe(with event: NSEvent) { onSwipeEvent?(event) }
    private var scrollResume: Task<Void, Never>?
    private var scrolling = false
    func scrollVertically(with event: NSEvent) {
        scrolling = true
        scrollResume?.cancel()
        cells.values.forEach { $0.setPlaybackSuspended(true) }
        super.scrollWheel(with: event)
        scrollResume = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(140))
            guard !Task.isCancelled, let self else { return }
            self.scrolling = false
            self.onScrollPosition?(self.contentView.bounds.minY)
            self.updatePreviews()
        }
    }
    private struct SectionLayout {
        let section: Int
        let start: Int
        let count: Int
        let headerY: CGFloat
        let cellsY: CGFloat
        let bottom: CGFloat
    }
    private let sections: [PickerSection]
    private let stickers: [PickerSticker]
    var stickerIDs: [String] { stickers.map(\.id) }
    private let copy: (String) -> Void
    private let document = PickerGridDocument()
    private var cells: [Int: PickerMediaButton] = [:]
    private var headers: [Int: NSTextField] = [:]
    private var spare: [PickerMediaButton] = []
    private var geometry: [SectionLayout] = []
    private var columns = 0
    private var cellSide: CGFloat = 68
    private let gap = PickerLayout.stickerSpacing
    private var cellTarget: CGFloat = 72
    private var zooming = false
    private var measuredWidth: CGFloat = -1
    private var contentHeight: CGFloat = 0
    private var updating = false
    private var suspended = false
    private var observer: NSObjectProtocol?

    init(sections: [PickerSection], emptyMessage: String, copy: @escaping (String) -> Void) {
        self.sections = sections; self.stickers = sections.flatMap(\.stickers); self.copy = copy
        super.init(frame: .zero)
        wantsLayer = true
        drawsBackground = false; hasVerticalScroller = true; autohidesScrollers = true
        scrollerStyle = .overlay
        documentView = document
        if stickers.isEmpty {
            let label = NSTextField(wrappingLabelWithString: emptyMessage)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: 8, width: 300, height: 48)
            label.autoresizingMask = [.width]
            document.addSubview(label)
        }
        contentView.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updatePreviews()
                if self.pendingScrollOffset == nil, !self.scrolling { self.onScrollPosition?(self.contentView.bounds.minY) }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    override func layout() {
        super.layout()
        if let offset = pendingScrollOffset, contentView.bounds.width > 1, contentView.bounds.height > 1 {
            measure()
            pendingScrollOffset = nil
            let y = offset.isFinite ? min(max(0, offset), max(0, contentHeight - contentView.bounds.height)) : 0
            contentView.scroll(to: NSPoint(x: 0, y: y))
            reflectScrolledClipView(contentView)
        }
        updatePreviews()
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updatePreviews() }
    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        suspended = true
        cells.values.forEach { $0.setPlaybackSuspended(true) }
    }
    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        suspended = false
        cells.values.forEach { $0.setPlaybackSuspended(zooming) }
        updatePreviews()
    }
    func saveScrollPosition() {
        if pendingScrollOffset == nil { onScrollPosition?(contentView.bounds.minY) }
    }
    func stopPreviews() {
        saveScrollPosition()
        scrollResume?.cancel()
        cells.values.forEach { $0.setPreviewVisible(false) }
    }
    func setZooming(_ value: Bool) {
        zooming = value
        cells.values.forEach { $0.setPlaybackSuspended(value || suspended || scrolling) }
        if !value { updatePreviews() }
    }
    func setCellTarget(_ value: CGFloat) {
        guard cellTarget != value else { return }
        let nextColumns = max(1, Int(ceil((max(1, contentView.bounds.width) + gap) / (value + gap))))
        if nextColumns == columns { cellTarget = value; return }
        // Preserve the first visible sticker and its position within the viewport.
        let visible = documentVisibleRect
        let anchor = cells.filter { $0.value.frame.intersects(visible) }.min { $0.key < $1.key }
        let offset = anchor.map { $0.value.frame.minY - visible.minY } ?? 0
        cellTarget = value
        measuredWidth = -1
        measure()
        if let anchor, let layout = geometry.first(where: { anchor.key >= $0.start && anchor.key < $0.start + $0.count }) {
            let row = (anchor.key - layout.start) / columns
            let y = layout.cellsY + CGFloat(row) * (cellSide + gap) - offset
            contentView.scroll(to: NSPoint(x: 0, y: min(max(0, y), max(0, contentHeight - contentView.bounds.height))))
            reflectScrolledClipView(contentView)
        }
        updatePreviews()
    }
    private func measure() {
        let width = max(1, contentView.bounds.width)
        guard measuredWidth != width else {
            let height = max(contentHeight, contentView.bounds.height)
            if document.frame.height != height { document.setFrameSize(NSSize(width: width, height: height)) }
            return
        }
        measuredWidth = width
        columns = max(1, Int(ceil((width + gap) / (cellTarget + gap))))
        cellSide = floor((width - CGFloat(columns - 1) * gap) / CGFloat(columns))
        geometry.removeAll(keepingCapacity: true)
        var y: CGFloat = 0
        var start = 0
        for (index, section) in sections.enumerated() {
            guard !section.stickers.isEmpty else { continue }
            if !geometry.isEmpty { y += 6 }
            let headerY = y
            if section.title != nil { y += 20 }
            let cellsY = y
            let rows = (section.stickers.count + columns - 1) / columns
            y += CGFloat(rows) * (cellSide + gap) - gap
            geometry.append(SectionLayout(section: index, start: start, count: section.stickers.count,
                                          headerY: headerY, cellsY: cellsY, bottom: y))
            start += section.stickers.count
        }
        contentHeight = y
        document.setFrameSize(NSSize(width: width, height: max(y, contentView.bounds.height)))
    }
    func updatePreviews() {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        measure()
        guard window != nil else { return }
        let visible = documentVisibleRect.insetBy(dx: 0, dy: -(cellSide + gap))
        var desired: [Int: NSRect] = [:]
        var desiredHeaders: [Int: NSRect] = [:]
        for layout in geometry where layout.bottom >= visible.minY && layout.headerY <= visible.maxY {
            if sections[layout.section].title != nil && layout.cellsY >= visible.minY {
                desiredHeaders[layout.section] = NSRect(x: 0, y: layout.headerY, width: measuredWidth, height: 18)
            }
            let firstRow = max(0, Int(floor((visible.minY - layout.cellsY) / (cellSide + gap))))
            let lastRow = min((layout.count - 1) / columns, Int(floor((visible.maxY - layout.cellsY) / (cellSide + gap))))
            guard firstRow <= lastRow else { continue }
            for row in firstRow...lastRow {
                for col in 0..<columns {
                    let local = row * columns + col
                    guard local < layout.count else { break }
                    desired[layout.start + local] = NSRect(x: CGFloat(col) * (cellSide + gap),
                        y: layout.cellsY + CGFloat(row) * (cellSide + gap), width: cellSide, height: cellSide)
                }
            }
        }
        for id in Array(cells.keys) where desired[id] == nil {
            if let button = cells.removeValue(forKey: id) {
                button.setPreviewVisible(false); button.removeFromSuperview()
                if spare.count < 24 { spare.append(button) }
            }
        }
        for (id, frame) in desired {
            let button: PickerMediaButton
            if let existing = cells[id] { button = existing }
            else {
                button = spare.popLast() ?? PickerMediaButton(sticker: nil, target: self, action: #selector(copySelected(_:)))
                button.configure(sticker: stickers[id]); cells[id] = button; document.addSubview(button)
            }
            button.frame = frame
            button.setPlaybackSuspended(suspended || zooming || scrolling)
            button.setPreviewVisible(true)
        }
        for id in Array(headers.keys) where desiredHeaders[id] == nil {
            headers.removeValue(forKey: id)?.removeFromSuperview()
        }
        for (id, frame) in desiredHeaders {
            let label: NSTextField
            if let existing = headers[id] { label = existing }
            else {
                label = NSTextField(labelWithString: sections[id].title ?? "")
                label.font = .boldSystemFont(ofSize: 12); label.textColor = .secondaryLabelColor
                label.lineBreakMode = .byTruncatingTail
                headers[id] = label; document.addSubview(label)
            }
            label.frame = frame
        }
    }
    @objc private func copySelected(_ sender: NSButton) {
        if let id = sender.identifier?.rawValue { copy(id) }
    }
}

/// Tracks horizontal displacement through finger lift; vertical scrolling stays native.
@MainActor
private final class PickerSwipeHandler {
    var onVerticalScroll: ((NSEvent) -> Void)?
    var onDrag: ((CGFloat) -> Void)?
    var onEndDrag: ((CGFloat, CGFloat, Bool) -> Void)?
    var onChangePack: ((Int) -> Void)?
    private enum Axis { case horizontal, vertical }
    private var axis: Axis?
    private var horizontal: CGFloat = 0
    private var vertical: CGFloat = 0
    private var finished = false
    private var lastEventTime: TimeInterval = 0
    private var releaseVelocity: CGFloat = 0
    private var lastMotionTime: TimeInterval = 0
    private var lastTurnTime: TimeInterval = -.infinity
    private var wheelEnd: DispatchWorkItem?
    private var routingVertical = false

    private func scrollVertically(_ event: NSEvent) {
        guard !routingVertical else { return }
        routingVertical = true
        defer { routingVertical = false }
        onVerticalScroll?(event)
    }
    func scrollWheel(with event: NSEvent) {
        guard !routingVertical else { return }
        let phased = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) || (!phased && event.timestamp - lastEventTime > 0.25) {
            axis = nil; horizontal = 0; vertical = 0; finished = false
            releaseVelocity = 0; lastMotionTime = event.timestamp
        }
        let interval = event.timestamp - lastMotionTime
        if event.momentumPhase.isEmpty, abs(event.scrollingDeltaX) > 0.01 {
            let sample = event.scrollingDeltaX / CGFloat(max(1.0 / 120, min(0.05, interval)))
            releaseVelocity = interval > 0.08 ? sample : releaseVelocity * 0.25 + sample * 0.75
            lastMotionTime = event.timestamp
        } else if event.timestamp - lastMotionTime > 0.08 { releaseVelocity = 0 }
        lastEventTime = event.timestamp
        if !event.momentumPhase.isEmpty {
            if axis != .horizontal { scrollVertically(event) }
            return
        }
        horizontal += event.scrollingDeltaX
        vertical += event.scrollingDeltaY
        if axis == nil, max(abs(horizontal), abs(vertical)) > 6 {
            axis = abs(horizontal) > abs(vertical) * 0.85 ? .horizontal : .vertical
        }
        guard axis == .horizontal else { scrollVertically(event); return }
        if !finished { onDrag?(horizontal) }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            finish(cancelled: event.phase.contains(.cancelled))
        } else if !phased {
            wheelEnd?.cancel()
            let end = DispatchWorkItem { [weak self] in self?.finish(cancelled: false) }
            wheelEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: end)
        }
    }
    private func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true; lastTurnTime = lastEventTime
        wheelEnd?.cancel(); wheelEnd = nil
        onEndDrag?(horizontal, releaseVelocity, cancelled)
    }
    func swipe(with event: NSEvent) {
        guard event.deltaX != 0 else { return }
        guard event.timestamp - lastTurnTime > 0.06 else { return }
        lastTurnTime = event.timestamp
        onChangePack?(event.deltaX > 0 ? -1 : 1)
    }
}

/// A stationary event surface keeps gesture tracking stable as pages slide under the pointer.
private final class PickerViewport: NSView {
    var onScrollEvent: ((NSEvent) -> Void)?
    var onSwipeEvent: ((NSEvent) -> Void)?
    var onMagnifyEvent: ((NSEvent) -> Void)?
    override func magnify(with event: NSEvent) { onMagnifyEvent?(event) }
    override func scrollWheel(with event: NSEvent) { onScrollEvent?(event) }
    override func swipe(with event: NSEvent) { onSwipeEvent?(event) }
}


@MainActor
private final class ShortcutRecorder: NSTextField {
    var candidate: (code: UInt32, modifiers: UInt32)?
    var changed: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        return capture(event)
    }
    override func keyDown(with event: NSEvent) {
        if !capture(event) { super.keyDown(with: event) }
    }
    private func capture(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { NSApp.abortModal(); return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .option, .control]).isEmpty,
              ![36, 48, 76].contains(event.keyCode),
              let key = event.characters(byApplyingModifiers: [])?.uppercased(), !key.isEmpty else { return false }
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        candidate = (UInt32(event.keyCode), modifiers)
        stringValue = label + (event.keyCode == 49 ? "Space" : key)
        changed?()
        return true
    }
}
