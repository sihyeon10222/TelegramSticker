import UIKit
import os

extension KeyboardViewController {
    func copySticker(_ sticker: Sticker, asPNG: Bool = false) {
        copyTask?.cancel()
        guard hasFullAccess else { performCopy(sticker, asPNG: asPNG); return }
        if !asPNG, let url = sticker.animationURL,
           (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 > 8 * 1024 * 1024 {
            // Release regenerable frames before a large clipboard transfer; this is not a size limit.
            playbackSuspended = true; updatePlaybackState(); images.removeAll()
            copyTask = Task { [weak self] in
                await GIFFrameDecoder.shared.clear(); await StickerThumbnailDecoder.shared.clear()
                guard let self, !Task.isCancelled else { return }
                self.performCopy(sticker, asPNG: asPNG)
                self.playbackSuspended = false; self.updatePlaybackState()
            }
        } else { performCopy(sticker, asPNG: asPNG) }
    }

    func performCopy(_ sticker: Sticker, asPNG: Bool = false) {
        let result = copier.copy(sticker, isAllowed: hasFullAccess, asPNG: asPNG)
        // Errors stay visible until the user chooses another action; ordinary feedback costs no layout space.
        guard result == .copied else {
            self.showMessage(result.message, persistent: true)
            if result == .fileUnavailable || result == .invalidPNG { reloadLibrary(preservingStatus: result.message) }
            return
        }
        state.recordCopy(sticker.id)
        if state.selection == .recent { applySelection() }
        else {
            // Copying must not rebuild the grid under a pending scroll gesture.
            for cell in collectionView.visibleCells.compactMap({ $0 as? StickerCell }) {
                cell.setCopied(cell.accessibilityIdentifier == "keyboardSticker." + sticker.id)
            }
            moreButton.menu = UIMenu(children: [clearHistoryAction(), resetOrderAction()])
        }
        showMessage("✓ 복사됨 · 채팅창에서 붙여넣기", copied: true)
    }
}
