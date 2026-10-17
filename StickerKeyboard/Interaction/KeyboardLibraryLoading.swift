import UIKit

extension KeyboardViewController {
    @discardableResult
    func restoreInitialLibrary() -> Bool {
        // Complete restoration before exposing the first frame to a new host.
        let restored = state.restoreLibrary()
        updateCacheGeneration(state.cacheGeneration)
        if restored {
            applySelection()
        } else if state.libraryRevision == nil { applySelection() }
        return restored
    }

    func updateCacheGeneration(_ generation: String?) {
        guard generation != displayedCacheGeneration else { return }
        displayedCacheGeneration = generation
        guard state.shouldInvalidateImageCache(for: generation) else { return }
        images.removeAll()
        Task { await GIFFrameDecoder.shared.clear(); await StickerThumbnailDecoder.shared.clear() }
    }

    func acceptLibrary(reader: LibraryReader, snapshot: LibrarySnapshot) {
        state.saveScrollOffset(Double(collectionView.contentOffset.y))
        state.acceptLibrary(reader: reader, snapshot: snapshot)
        updateCacheGeneration(state.cacheGeneration)
        applySelection()
        pendingScrollRestoration = true
        restoreScrollPositionIfNeeded()
    }

    func prepareVisiblePosters() {
        let visibleTabs = tabScroll.bounds
        for button in packTabs.arrangedSubviews.compactMap({ $0 as? PackTabButton }) {
            guard button.convert(button.bounds, to: tabScroll).intersects(visibleTabs),
                  let id = button.packID, let cover = state.prepared[id]?.first else { continue }
            button.configuration?.image = images.thumbnail(for: cover, pixels: 22)?.withRenderingMode(.alwaysOriginal)
        }
        // Restore the viewport first. Decode only missing posters on that screen,
        // never the beginning of every pack or the library above the saved offset.
        prepareGridPosters(in: collectionView)
    }

    func prepareGridPosters(in grid: UICollectionView) {
        for path in grid.indexPathsForVisibleItems {
            guard let sticker = sticker(at: path, in: grid),
                  let cell = grid.cellForItem(at: path) as? StickerCell else { continue }
            cell.setPoster(images.thumbnail(for: sticker))
        }
    }

    func reloadLibrary(preservingStatus: String? = nil, persistentStatus: Bool = true, force: Bool = false) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let currentRevision = force ? nil : state.libraryRevision
        let currentCacheGeneration = state.cacheGeneration
        loadTask = Task { [weak self] in
            let result = await Task.detached { () -> Result<(LibraryReader, LibrarySnapshot)?, Error> in
                Result {
                    let reader = try LibraryReader.shared()
                    let index = try reader.index()
                    guard index.libraryRevision != currentRevision || index.cacheGeneration != currentCacheGeneration else { return nil }
                    return (reader, try reader.snapshot())
                }
            }.value
            guard let self, !Task.isCancelled, self.presentationActive, generation == self.loadGeneration else { return }
            // Do not replace a tab hierarchy while the user's finger is dragging it.
            guard self.dragSession == nil else { return }
            switch result {
            case .success(let loaded):
                if let (reader, snapshot) = loaded {
                    self.cancelPaging()
                    self.acceptLibrary(reader: reader, snapshot: snapshot)
                }
            case .failure:
                // Keep the already-rendered list on a transient read failure.
                self.state.reportReloadFailure()
                if preservingStatus == nil { self.showMessage(self.state.libraryNote!) }
            }
            if let preservingStatus { self.showMessage(preservingStatus, persistent: persistentStatus) }
        }
    }

}
