import UIKit
import os

extension KeyboardViewController {
    func beginPresentationPreparation() {
        guard !preparingPresentation else { return }
        preparingPresentation = true
        let cachedLibrary = state.libraryForReload != nil
        firstPosterInterval = performance.beginInterval("Keyboard First Poster", id: performance.makeSignpostID(),
            "cachedLibrary=\(cachedLibrary)")
    }

    func finishFirstPosterMeasurement(outcome: String) {
        guard let interval = firstPosterInterval else { return }
        performance.endInterval("Keyboard First Poster", interval, "outcome=\(outcome, privacy: .public)")
        firstPosterInterval = nil
    }

    func recordFirstPoster(in cell: StickerCell) {
        guard firstPosterInterval != nil, presentationActive, cell.hasDisplayedImage,
              collectionView.visibleCells.contains(where: { $0 === cell }) else { return }
        finishFirstPosterMeasurement(outcome: "visibleCellImageAssigned")
    }

    @discardableResult
    func restoreInitialLibrary() -> Bool {
        let interval = performance.beginInterval("Initial Library Restore", id: performance.makeSignpostID())
        defer { performance.endInterval("Initial Library Restore", interval) }
        let restored = state.restoreLibrary()
        updateCacheGeneration(state.cacheGeneration)
        if restored || state.libraryRevision == nil { applySelection() }
        return restored
    }

    func updateCacheGeneration(_ generation: String?) {
        guard generation != displayedCacheGeneration else { return }
        displayedCacheGeneration = generation
        guard state.shouldInvalidateImageCache(for: generation) else { return }
        images.removeAll()
        Task { await GIFFrameDecoder.shared.clear(); await StickerThumbnailDecoder.shared.clear() }
    }

    func acceptLibrary(_ contents: LibraryContents) {
        let previousSelection = state.selection
        let previousOffset = Double(collectionView.contentOffset.y)
        let shouldSaveOffset = state.libraryRevision != nil && !pendingScrollRestoration
        let changed = state.acceptLibrary(contents)
        // The first off-main check usually confirms the library already shown.
        // Keep its cells, GIF playback and scroll position intact in that case.
        guard changed else { return }
        // An initial loading surface has no meaningful offset to persist.
        if shouldSaveOffset {
            state.saveScrollOffset(previousOffset, for: previousSelection)
        }
        updateCacheGeneration(state.cacheGeneration)
        applySelection()
        if state.stickerCount == 0 { finishFirstPosterMeasurement(outcome: "emptySelection") }
        pendingScrollRestoration = true
        restoreScrollPositionIfNeeded()
    }

    func prepareFirstPresentationPosters() {
        guard preparingPresentation, state.libraryRevision != nil,
              collectionView.bounds.width > 0, collectionView.bounds.height >= 44 else { return }
        // Repeat for the actual viewport until appearance completes: restoration
        // and host layout can replace the first set of cells. On later appearances
        // NSCache may have evicted posters even while the library stays in memory.
        let paths = collectionView.indexPathsForVisibleItems.sorted().prefix(64)
        guard !paths.isEmpty || state.stickerCount == 0 else { return }
        let interval = performance.beginInterval("Presentation Posters", id: performance.makeSignpostID())
        defer { performance.endInterval("Presentation Posters", interval) }
        let missingPosters = paths.compactMap { path -> Sticker? in
            guard let cell = collectionView.cellForItem(at: path) as? StickerCell,
                  !cell.hasDisplayedImage else { return nil }
            return sticker(at: path, in: collectionView)
        }
        images.preparePosters(for: missingPosters, limit: 64)
        for path in paths {
            guard let cell = collectionView.cellForItem(at: path) as? StickerCell,
                  let sticker = sticker(at: path, in: collectionView) else { continue }
            if !cell.hasDisplayedImage, let poster = images.cachedThumbnail(for: sticker) {
                cell.imageTask?.cancel(); cell.imageTask = nil
                cell.setPoster(poster)
            }
            recordFirstPoster(in: cell)
        }
        if state.stickerCount == 0 { finishFirstPosterMeasurement(outcome: "emptySelection") }
        for button in packTabs.arrangedSubviews.compactMap({ $0 as? PackTabButton })
            .filter({ $0.convert($0.bounds, to: tabScroll).intersects(tabScroll.bounds) }).prefix(24) {
            guard !button.posterReady, let id = button.packID,
                  let cover = state.prepared[id]?.first,
                  let poster = images.thumbnail(for: cover, pixels: 22) else { continue }
            button.posterTask?.cancel(); button.posterTask = nil
            button.configuration?.image = poster.withRenderingMode(.alwaysOriginal)
            button.posterReady = true
        }
    }

    func prepareVisibleTabPosters() {
        guard presentationActive, tabScroll.bounds.width > 0 else { return }
        for button in packTabs.arrangedSubviews.compactMap({ $0 as? PackTabButton }) {
            guard button.convert(button.bounds, to: tabScroll).intersects(tabScroll.bounds) else {
                button.posterTask?.cancel(); button.posterTask = nil
                continue
            }
            guard !button.posterReady, button.posterTask == nil,
                  let id = button.packID, let cover = state.prepared[id]?.first else { continue }
            if let cached = images.cachedThumbnail(for: cover, pixels: 22) {
                button.configuration?.image = cached.withRenderingMode(.alwaysOriginal)
                button.posterReady = true
                continue
            }
            button.posterTask = Task { @MainActor [weak self, weak button] in
                guard let self else { return }
                let image = await self.images.thumbnailAsync(for: cover, pixels: 22)
                guard let button, !Task.isCancelled, self.presentationActive,
                      button.superview === self.packTabs else { return }
                if let image { button.configuration?.image = image.withRenderingMode(.alwaysOriginal) }
                button.posterReady = true
                button.posterTask = nil
            }
        }
    }

    func applyPendingLibraryIfPossible() {
        guard presentationActive, dragSession == nil, pagingTarget == nil, pageAnimator == nil,
              packSwipe.state != .began, packSwipe.state != .changed,
              let pending = pendingLibrary, pending.generation == loadGeneration else { return }
        pendingLibrary = nil
        acceptLibrary(pending.contents)
        if let message = pending.status { showMessage(message, persistent: pending.persistent) }
    }

    func reloadLibrary(preservingStatus: String? = nil, persistentStatus: Bool = true, force: Bool = false) {
        if loadTask != nil, !force {
            if let preservingStatus { showMessage(preservingStatus, persistent: persistentStatus) }
            return
        }
        loadTask?.cancel()
        loadGeneration += 1
        pendingLibrary = nil
        let generation = loadGeneration
        let initialLibrary = state.libraryForReload
        loadTask = Task { [weak self] in
            let result: Result<LibraryContents, Error>
            do { result = .success(try await LibrarySnapshotLoader.shared.loadShared(force: force, reusing: initialLibrary)) }
            catch { result = .failure(error) }
            guard let self else { return }
            defer { if self.loadGeneration == generation { self.loadTask = nil } }
            guard !Task.isCancelled, self.presentationActive, generation == self.loadGeneration else { return }
            switch result {
            case .success(let contents):
                self.pendingLibrary = PendingLibrary(contents: contents, generation: generation,
                    status: preservingStatus, persistent: persistentStatus)
                self.applyPendingLibraryIfPossible()
            case .failure:
                self.state.reportReloadFailure()
                if self.state.libraryRevision == nil { self.applySelection() }
                self.finishFirstPosterMeasurement(outcome: "libraryReadFailed")
                self.showMessage(preservingStatus ?? self.state.libraryNote!, persistent: persistentStatus)
            }
        }
    }
}
