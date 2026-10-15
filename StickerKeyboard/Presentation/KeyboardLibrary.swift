import UIKit
import os

extension KeyboardViewController {
    @discardableResult
    func restoreInitialLibrary() -> Bool {
        // Never draw an old/default list and replace it from an appearance Task.
        do {
            let reader = try self.reader ?? LibraryReader.shared()
            let index = try reader.index()
            if index.libraryRevision == libraryRevision, canPruneHistory {
                updateCacheGeneration(index.cacheGeneration)
                return false
            }
            let snapshot: LibrarySnapshot
            if let (_, cached) = Self.cachedLibrary, cached.revision == index.libraryRevision,
               cached.cacheGeneration == index.cacheGeneration, cached.warnings.isEmpty {
                snapshot = cached
            } else { snapshot = try reader.snapshot() }
            acceptLibrary(reader: reader, snapshot: snapshot)
            return true
        } catch {
            // A transient read must not replace an already usable keyboard with an empty/default UI.
            canPruneHistory = false
            libraryNote = "공유 목록을 열 수 없어요. 메인 앱에서 설치된 팩을 확인해 주세요."
            if libraryRevision == nil { applySelection() }
            return false
        }
    }

    func updateCacheGeneration(_ generation: String?) {
        guard generation != cacheGeneration else { return }
        cacheGeneration = generation
        images.removeAll()
        Task { await GIFFrameDecoder.shared.clear(); await StickerThumbnailDecoder.shared.clear() }
    }

    func reconcileSelection() {
        if case .pack(let id) = selection, !packs.contains(where: { $0.id == id }), canPruneHistory {
            selection = .all
            selectionStore.save(selection)
        }
    }

    func prewarmFirstFrame() {
        // Only the first viewport, once before presentation; never decode a whole pack here.
        // Re-entry uses the bounded process cache and keeps existing cell images.
        var covers = Array(packs.prefix(6))
        if case .pack(let id) = selection, let pack = packs.first(where: { $0.id == id }),
           !covers.contains(where: { $0.id == id }) { covers.append(pack) }
        for pack in covers {
            if let cover = prepared[pack.id]?.first { _ = images.thumbnail(for: cover, pixels: 22) }
        }
        // Complete the bounded first page before exposing it. A time cutoff left
        // the last cells blank for several frames on cold system→sticker switches.
        images.preparePosters(for: sections(for: selection).joined(), limit: 28)
    }

    func acceptLibrary(reader: LibraryReader, snapshot: LibrarySnapshot) {
        Self.cachedLibrary = (reader, snapshot)
        self.reader = reader
        libraryRevision = snapshot.revision
        updateCacheGeneration(snapshot.cacheGeneration)
        libraryPacks = snapshot.packs
        prepared = Dictionary(uniqueKeysWithValues: snapshot.packs.map { pack in
            (pack.id, pack.stickers.compactMap { record -> Sticker? in
                guard let png = snapshot.files[record.pngPath], let thumb = snapshot.files[record.thumbnailPath] else { return nil }
                return Sticker(id: pack.id + "." + record.id, name: record.name, detail: pack.title, imageURL: png, thumbnailURL: thumb,
                    animationURL: record.animationPath.flatMap { snapshot.files[$0] }, playbackURL: record.playbackPath.flatMap { snapshot.files[$0] })
            })
        })
        byStickerID = Dictionary(uniqueKeysWithValues: prepared.values.flatMap { $0 }.map { ($0.id, $0) })
        canPruneHistory = snapshot.warnings.isEmpty
        let byID = Dictionary(uniqueKeysWithValues: snapshot.packs.map { ($0.id, $0) })
        packs = packOrder.orderedIDs(available: snapshot.packs.map(\.id), prune: snapshot.warnings.isEmpty)
            .compactMap { byID[$0] }
        libraryNote = snapshot.warnings.first
        if packs.isEmpty { libraryNote = snapshot.warnings.first ?? "설치한 스티커가 없어요. 앱에서 Telegram 팩을 추가해 주세요." }
        reconcileSelection()
        prewarmFirstFrame()
        applySelection()
    }

    func reloadLibrary(preservingStatus: String? = nil, persistentStatus: Bool = true, force: Bool = false) {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        if let index = try? reader?.index() { updateCacheGeneration(index.cacheGeneration) }
        let currentRevision = force ? nil : libraryRevision
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
                self.libraryNote = "공유 목록을 갱신하지 못했어요. 메인 앱에서 확인해 주세요."
                if preservingStatus == nil { self.showMessage(self.libraryNote!) }
            }
            if let preservingStatus { self.showMessage(preservingStatus, persistent: persistentStatus) }
        }
    }

    func applySelection() {
        let interval = performance.beginInterval("Pack Selection")
        defer { performance.endInterval("Pack Selection", interval) }
        UIView.performWithoutAnimation { renderSelection() }
    }

    func renderSelection() {
        let all = packs.flatMap { prepared[$0.id] ?? [] }
        // A failed shared read is not evidence that installed stickers have been deleted.
        if canPruneHistory { recent.prune(available: Set(all.map(\.id))) }
        switch selection {
        case .all: stickers = all
        case .recent:
            stickers = recent.ids.compactMap { byStickerID[$0] }
        case .pack(let id): stickers = prepared[id] ?? []
        }
        emptyLabel.text = libraryNote ?? (selection == .recent
            ? "최근 사용한 스티커가 없어요. 전체에서 스티커를 복사해 보세요."
            : "설치한 스티커가 없어요. 앱에서 Telegram 팩을 추가해 주세요.")
        emptyLabel.isHidden = !stickers.isEmpty
        let nextSections = sections(for: selection)
        updateSelectionDescription()
        if nextSections != visibleSections {
            visibleSections = nextSections
            collectionView.reloadData()
        }
        collectionView.visibleCells.compactMap { $0 as? StickerCell }.forEach {
            $0.setCopied($0.accessibilityIdentifier == lastCopiedID.map { "keyboardSticker." + $0 })
        }
        let signature = packs.map { pack in
            pack.id + ":" + pack.title + ":" + (prepared[pack.id]?.first?.thumbnailURL?.path ?? "")
        }
        if tabSignature == signature, !packTabs.arrangedSubviews.isEmpty {
            for button in packTabs.arrangedSubviews.compactMap({ $0 as? UIButton }) {
                let selected = button.accessibilityIdentifier == (selectionIdentifier())
                var config = button.configuration
                config?.background.backgroundColor = selected ? .systemBlue.withAlphaComponent(0.12) : .clear
                config?.background.strokeColor = selected ? .systemBlue.withAlphaComponent(0.35) : .clear
                config?.background.strokeWidth = selected ? 1 : 0
                config?.baseForegroundColor = selected ? .systemBlue : .secondaryLabel
                button.configuration = config
                button.accessibilityTraits = selected ? [.button, .selected] : .button
                if selected { needsRevealSelectedTab = true }
            }
            moreButton.menu = UIMenu(children: [clearHistoryAction(), resetOrderAction()])
            view.setNeedsLayout()
            return
        }
        tabSignature = signature
        for child in packTabs.arrangedSubviews { packTabs.removeArrangedSubview(child); child.removeFromSuperview() }
        let choices: [(Selection, String, String?)] = [(.all, "전체", "square.grid.2x2"),
                                                        (.recent, "최근 사용", "clock")]
            + packs.map { (.pack($0.id), $0.title, nil) }
        moreButton.menu = UIMenu(title: "팩 탭을 길게 잡고 드래그해 순서를 바꾸세요.", children: [
            clearHistoryAction(), resetOrderAction()
        ])
        for (id, title, symbol) in choices {
            let button = PackTabButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.cornerStyle = .fixed
            config.background.cornerRadius = 10
            config.background.backgroundColor = id == selection ? .systemBlue.withAlphaComponent(0.12) : .clear
            config.background.strokeColor = id == selection ? .systemBlue.withAlphaComponent(0.35) : .clear
            config.background.strokeWidth = id == selection ? 1 : 0
            config.baseForegroundColor = id == selection ? .systemBlue : .secondaryLabel
            config.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            if let symbol {
                config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
            } else { config.image = UIImage(systemName: "square.stack") }
            button.configuration = config
            if case .pack(let packID) = id, let cover = prepared[packID]?.first {
                if let image = images.cachedThumbnail(for: cover, pixels: 22) {
                    button.configuration?.image = image.withRenderingMode(.alwaysOriginal)
                }
                Task { @MainActor [weak self, weak button] in
                    guard let self else { return }
                    let image = await self.images.thumbnailAsync(for: cover, pixels: 22)
                    guard let button, !Task.isCancelled, button.packID == packID,
                          button.superview === self.packTabs else { return }
                    var config = button.configuration
                    config?.image = image?.withRenderingMode(.alwaysOriginal)
                    button.configuration = config
                }
            }
            button.accessibilityLabel = title
            button.accessibilityHint = id == .recent
                ? "탭해 최근 스티커를 엽니다. 길게 눌러 최근 사용 내역을 비울 수 있습니다."
                : "탭해 팩을 선택합니다. 길게 잡고 좌우로 드래그해 순서를 변경합니다."
            button.addAction(UIAction { [weak self] _ in
                self?.selectList(id)
            }, for: .touchUpInside)
            switch id {
            case .all: button.accessibilityIdentifier = "packTab.all"
            case .recent: button.accessibilityIdentifier = "packTab.recent"
            case .pack(let packID): button.accessibilityIdentifier = "packTab.\(packID)"
            }
            switch id {
            case .recent:
                button.menu = UIMenu(title: "최근 사용", children: [clearHistoryAction()])
            case .pack(let packID):
                button.packID = packID
                // VoiceOver has equivalent explicit actions; ordinary long press is reserved for dragging.
                button.accessibilityCustomActions = [
                    UIAccessibilityCustomAction(name: "왼쪽으로 이동") { [weak self] _ in
                        self?.movePack(packID, offset: -1); return true
                    },
                    UIAccessibilityCustomAction(name: "오른쪽으로 이동") { [weak self] _ in
                        self?.movePack(packID, offset: 1); return true
                    }
                ]
            case .all:
                button.menu = UIMenu(title: "키보드 팩 순서", children: [resetOrderAction()])
            }
            button.accessibilityTraits = id == selection ? [.button, .selected] : .button
            packTabs.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: packTabs.heightAnchor, constant: 4).isActive = true
        }
        needsRevealSelectedTab = true
        view.setNeedsLayout()
    }
}
