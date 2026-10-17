#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct StickerCommandActions {
    var copy: (() -> Void)?
    var selectAll: () -> Void
}
private struct StickerCommandsKey: FocusedValueKey { typealias Value = StickerCommandActions }
extension FocusedValues {
    var stickerCommands: StickerCommandActions? {
        get { self[StickerCommandsKey.self] }
        set { self[StickerCommandsKey.self] = newValue }
    }
}

struct StickerMacCommands: Commands {
    @FocusedValue(\.stickerCommands) private var actions
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("설정…") { MacDesktopCoordinator.shared.showManagement() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .pasteboard) {
            Button("잘라내기") { UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.cut(_:)), to: nil, from: nil, for: nil) }
                .keyboardShortcut("x")
            Button("복사") {
                if MacTextResponder.current() != nil {
                    UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: nil, for: nil)
                } else { actions?.copy?() }
            }.keyboardShortcut("c")
            Button("붙여넣기") { UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.paste(_:)), to: nil, from: nil, for: nil) }
                .keyboardShortcut("v")
        }
        CommandGroup(replacing: .textEditing) {
            Button("전체 선택") {
                if MacTextResponder.current() != nil {
                    UIApplication.shared.sendAction(#selector(UIResponderStandardEditActions.selectAll(_:)), to: nil, from: nil, for: nil)
                } else { actions?.selectAll() }
            }.keyboardShortcut("a")
        }
        CommandGroup(after: .newItem) {
            Button("링크 목록 파일 열기…") { PackLinkInbox.shared.showFileImporter = true }.keyboardShortcut("o")
        }
    }
}

private enum MacTextResponder {
    @MainActor static func current() -> UIView? {
        func find(_ view: UIView) -> UIView? {
            if view.isFirstResponder, view is any UIKeyInput { return view }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).lazy.compactMap { find($0) }.first
    }
}
#endif
