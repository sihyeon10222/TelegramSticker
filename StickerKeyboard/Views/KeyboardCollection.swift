import UIKit
import os

extension KeyboardViewController {
    func selectionDescription() -> String {
        let title: String
        switch state.selection {
        case .all: title = "전체"
        case .recent: title = "최근 사용"
        case .pack(let id): title = state.packs.first(where: { $0.id == id })?.title ?? "스티커"
        }
        return "\(title) · \(state.stickers.count)개"
    }

    func updateSelectionDescription() {
        collectionView.accessibilityLabel = selectionDescription()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        (collectionView === pagingPreview ? pagingSections : visibleSections).count
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let sections = collectionView === pagingPreview ? pagingSections : visibleSections
        return sections.indices.contains(section) ? sections[section].count : 0
    }
    func sticker(at path: IndexPath, in grid: UICollectionView) -> Sticker? {
        let sections = grid === pagingPreview ? pagingSections : visibleSections
        guard sections.indices.contains(path.section), sections[path.section].indices.contains(path.item) else { return nil }
        return sections[path.section][path.item]
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StickerCell.reuseID, for: indexPath)
        if let stickerCell = cell as? StickerCell {
            guard let sticker = sticker(at: indexPath, in: collectionView) else { return cell }
            stickerCell.configure(sticker: sticker, image: images.cachedThumbnail(for: sticker), copied: collectionView === self.collectionView && sticker.id == state.lastCopiedID)
            stickerCell.setPlaybackPaused(playbackSuspended)
            let token = stickerCell.imageToken
            stickerCell.imageTask = Task { @MainActor [weak self, weak stickerCell] in
                guard let self else { return }
                let image = await self.images.thumbnailAsync(for: sticker)
                guard let stickerCell, !Task.isCancelled, stickerCell.imageToken == token else { return }
                stickerCell.setPoster(image)
            }
        }
        return cell
    }

    func updatePlaybackState() {
        // Scrolling and interactive paging must not freeze visible animations.
        // GIFPlaybackView skips clipped/hidden views; ended cells stop their decoders.
        for grid in [collectionView, pagingPreview] {
            grid.visibleCells.compactMap { $0 as? StickerCell }.forEach { $0.setPlaybackPaused(playbackSuspended) }
        }
    }
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? StickerCell)?.resumePlayback()
        if let cell = cell as? StickerCell, cell.imageTask == nil, let sticker = sticker(at: indexPath, in: collectionView) {
            let token = cell.imageToken
            cell.imageTask = Task { @MainActor [weak self, weak cell] in
                guard let self else { return }
                let image = await self.images.thumbnailAsync(for: sticker)
                guard let cell, !Task.isCancelled, cell.imageToken == token else { return }
                cell.setPoster(image)
            }
        }
        (cell as? StickerCell)?.setPlaybackPaused(playbackSuspended)
    }
    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // A reload may already have assigned the same cell to a new visible item.
        guard !collectionView.visibleCells.contains(where: { $0 === cell }) else { return }
        (cell as? StickerCell)?.stopPlayback()
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        guard collectionView === self.collectionView, let sticker = sticker(at: indexPath, in: collectionView) else { return }
        copySticker(sticker)
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemAt indexPath: IndexPath,
                        point: CGPoint) -> UIContextMenuConfiguration? {
        guard collectionView === self.collectionView, let sticker = sticker(at: indexPath, in: collectionView), sticker.animationURL != nil else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [UIAction(title: "GIF로 복사", image: UIImage(systemName: "play.rectangle")) { _ in
                self?.copySticker(sticker)
            }, UIAction(title: "정적 PNG로 복사", image: UIImage(systemName: "photo")) { _ in
                self?.copySticker(sticker, asPNG: true)
            }])
        }
    }
}
