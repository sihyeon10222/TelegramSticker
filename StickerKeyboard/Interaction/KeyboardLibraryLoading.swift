import UIKit

extension KeyboardViewController {
    @discardableResult
    func restoreInitialLibrary() -> Bool {
        // Complete restoration before exposing the first frame to a new host.
        let restored = state.restoreLibrary()
        updateCacheGeneration(state.cacheGeneration)
        if restored {
            prewarmFirstFrame()
            applySelection()
        } else if state.libraryRevision == nil { applySelection() }
        return restored
    }

    func updateCacheGeneration(_ generation: String?) {
        guard generation != displayedCacheGeneration else { return }
        displayedCacheGeneration = generation
        images.removeAll()
        Task { await GIFFrameDecoder.shared.clear(); await StickerThumbnailDecoder.shared.clear() }
    }

    func acceptLibrary(reader: LibraryReader, snapshot: LibrarySnapshot) {
        state.acceptLibrary(reader: reader, snapshot: snapshot)
        updateCacheGeneration(state.cacheGeneration)
        prewarmFirstFrame()
        applySelection()
    }

    func prewarmFirstFrame() {
        // Only the first viewport, once before presentation; never decode a whole pack here.
        // Re-entry uses the bounded process cache and keeps existing cell images.
        var covers = Array(state.packs.prefix(6))
        if case .pack(let id) = state.selection, let pack = state.packs.first(where: { $0.id == id }),
           !covers.contains(where: { $0.id == id }) { covers.append(pack) }
        for pack in covers {
            if let cover = state.prepared[pack.id]?.first { _ = images.thumbnail(for: cover, pixels: 22) }
        }
        // Complete the bounded first page before exposing it. A time cutoff left
        // the last cells blank for several frames on cold system→sticker switches.
        images.preparePosters(for: state.sections(for: state.selection).joined(), limit: 28)
    }

    func reloadLibrary(preservingStatus: String? = nil, persistentStatus: Bool = true, force: Bool = false) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        if let index = try? state.reader?.index() { updateCacheGeneration(index.cacheGeneration) }
        let currentRevision = force ? nil : state.libraryRevision
        loadTask = Task { [weak self] in
            let result = await Task.detached { () -> Result<(LibraryReader, LibrarySnapshot)?, Error> in
                Result {
                    let reader = try LibraryReader.shared()
                    let index = try reader.index()
                    guard index.libraryRevision != currentRevision else { return nil }
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
