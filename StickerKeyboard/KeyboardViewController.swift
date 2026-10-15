import UIKit
import os

final class KeyboardViewController: UIInputViewController,
                                    UICollectionViewDataSource,
                                    UICollectionViewDelegate, UIGestureRecognizerDelegate {
    private let performance = OSSignposter(subsystem: "com.sihyeon.TelegramSticker.StickerKeyboard", category: "PointsOfInterest")
    private var stickers: [SampleSticker] = []
    private var packs: [PackManifestV1] = []
    private var libraryPacks: [PackManifestV1] = []
    private var prepared: [String: [SampleSticker]] = [:]
    private var byStickerID: [String: SampleSticker] = [:]
    private var tabSignature: [String] = []
    private var cacheGeneration: String?
    private var playbackSuspended = false
    private var reader: LibraryReader?
    private var canPruneHistory = false
    private typealias Selection = KeyboardSelection
    private var selection = Selection.all
    private let selectionStore = KeyboardSelectionStore()
    private static var cachedLibrary: (LibraryReader, LibrarySnapshot)?
    private var libraryRevision: String?
    private var dragSession: PackDragSession?
    private var dragDisplayLink: CADisplayLink?
    private lazy var dragProxy = PackDragScrollProxy(owner: self)
    private let recent = RecentStickerStore()
    private let packOrder = KeyboardPackOrderStore()
    private let packTabs = UIStackView()
    private lazy var packSwipe = UIPanGestureRecognizer(target: self, action: #selector(handlePackSwipe(_:)))
    private let tabScroll = PackTabScrollView()
    private let toast = UIView()
    private var lastCopiedID: String?
    private var libraryNote: String?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var presentationActive = false
    private var pagingGeneration = 0
    private let images = SampleStickerImages(maximumPixelSize: 160)
    private let copier = StickerCopyService()
    private let statusLabel = UILabel()
    private let emptyLabel = UILabel()
    private let nextKeyboardButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let gridViewport = UIView()
    private let pagingPreview = UICollectionView(frame: .zero, collectionViewLayout: StickerGridLayout())
    private var visibleSections: [[SampleSticker]] = []
    private var pagingSections: [[SampleSticker]] = []
    private var pagingTarget: Selection?
    private var pagingDirection: CGFloat = 0
    private var pageAnimator: UIViewPropertyAnimator?
    private var settlingSelection: Selection?
    private var needsRevealSelectedTab = true
    private var lastTabViewportWidth: CGFloat = 0
    private var moreWidth: NSLayoutConstraint?
    private let outerInset: CGFloat = 4
    private var committingPage = false
    private let collectionView = UICollectionView(frame: .zero,
                                                  collectionViewLayout: StickerGridLayout())
    private var previousFullAccess: Bool?
    private var resetStatusTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var tabHeight: NSLayoutConstraint?
    private var globeHeight: NSLayoutConstraint?
    private var keyboardHeight: NSLayoutConstraint?

    override func loadView() {
        let keyboard = UIInputView(frame: CGRect(x: 0, y: 0, width: 0, height: preferredKeyboardHeight), inputViewStyle: .keyboard)
        keyboard.allowsSelfSizing = true
        keyboard.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        keyboard.clipsToBounds = true
        inputView = keyboard
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // A nonzero backing keeps transparent sticker margins interactive in the hosted keyboard.
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.01)
        view.isOpaque = false
        view.clipsToBounds = true
        view.accessibilityIdentifier = "keyboardSurface"
        selection = selectionStore.selection
        // One documented height request. Keep UIInputView's native sizing;
        // overriding fitting/intrinsic size as well causes a second negotiation.
        let keyboardHeight = view.heightAnchor.constraint(equalToConstant: preferredKeyboardHeight)
        keyboardHeight.priority = UILayoutPriority(999)
        keyboardHeight.isActive = true
        self.keyboardHeight = keyboardHeight

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        // The keyboard has its own non-overlapping controls, so host scroll-edge blur is inappropriate.
        collectionView.topEdgeEffect.isHidden = true
        collectionView.bottomEdgeEffect.isHidden = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.alwaysBounceVertical = true
        collectionView.delaysContentTouches = false
        collectionView.canCancelContentTouches = true
        // The grid only scrolls vertically. Do not let an initial sideways component lock out Y movement.
        collectionView.isDirectionalLockEnabled = false
        collectionView.alwaysBounceHorizontal = false
        collectionView.bouncesHorizontally = false
        collectionView.contentInset.bottom = 0
        collectionView.verticalScrollIndicatorInsets.bottom = 0
        collectionView.accessibilityIdentifier = "stickerGrid"
        collectionView.accessibilityLabel = "스티커"
        collectionView.register(StickerCell.self, forCellWithReuseIdentifier: StickerCell.reuseID)
        packSwipe.maximumNumberOfTouches = 1
        packSwipe.delegate = self
        gridViewport.addGestureRecognizer(packSwipe)
        // A clear horizontal swipe changes tabs; diagonals let UIKit's vertical scrolling start.
        collectionView.panGestureRecognizer.require(toFail: packSwipe)
        emptyLabel.isHidden = true
        emptyLabel.text = "최근 사용한 스티커가 없어요. 전체에서 스티커를 복사해 보세요."
        emptyLabel.font = .preferredFont(forTextStyle: .body)
        emptyLabel.adjustsFontForContentSizeCategory = true
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .secondaryLabel
        collectionView.backgroundView = emptyLabel

        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        statusLabel.accessibilityIdentifier = "keyboardCopyStatus"

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "globe")
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        nextKeyboardButton.configuration = configuration
        nextKeyboardButton.accessibilityLabel = "다음 키보드"
        nextKeyboardButton.accessibilityHint = "길게 누르면 키보드 목록을 표시합니다."
        nextKeyboardButton.accessibilityIdentifier = "nextKeyboard"
        // This single system action handles tap and long press. Do not add a second advance action.
        nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)),
                                     for: .allTouchEvents)
        globeHeight = nextKeyboardButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        updateSwitchKey()

        tabScroll.showsHorizontalScrollIndicator = false
        tabScroll.delaysContentTouches = false
        tabScroll.canCancelContentTouches = true
        tabScroll.contentInsetAdjustmentBehavior = .never
        tabScroll.topEdgeEffect.isHidden = true
        tabScroll.bottomEdgeEffect.isHidden = true
        tabScroll.leftEdgeEffect.isHidden = true
        tabScroll.rightEdgeEffect.isHidden = true
        tabScroll.accessibilityIdentifier = "keyboardPackStrip"
        packTabs.axis = .horizontal
        packTabs.spacing = 2
        packTabs.translatesAutoresizingMaskIntoConstraints = false
        tabScroll.addSubview(packTabs)
        let reorder = UILongPressGestureRecognizer(target: self, action: #selector(handlePackDrag(_:)))
        reorder.minimumPressDuration = 0.35
        reorder.delegate = self
        reorder.cancelsTouchesInView = true
        packTabs.addGestureRecognizer(reorder)
        let tabsHeight = tabScroll.heightAnchor.constraint(equalToConstant: 32)
        tabHeight = tabsHeight
        NSLayoutConstraint.activate([
            packTabs.leadingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.leadingAnchor),
            packTabs.trailingAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.trailingAnchor),
            packTabs.topAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.topAnchor),
            packTabs.bottomAnchor.constraint(equalTo: tabScroll.contentLayoutGuide.bottomAnchor),
            packTabs.heightAnchor.constraint(equalTo: tabScroll.frameLayoutGuide.heightAnchor),
            tabsHeight
        ])
        var moreConfiguration = UIButton.Configuration.plain()
        moreConfiguration.image = UIImage(systemName: "ellipsis", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
        moreConfiguration.contentInsets = .zero
        moreButton.configuration = moreConfiguration
        moreButton.accessibilityLabel = "키보드 관리"
        moreButton.accessibilityIdentifier = "keyboardManage"
        moreButton.showsMenuAsPrimaryAction = true
        moreWidth = moreButton.widthAnchor.constraint(equalToConstant: 36)
        moreWidth?.isActive = true
        let topBar = UIStackView(arrangedSubviews: [tabScroll, moreButton, nextKeyboardButton])
        topBar.axis = .horizontal
        topBar.spacing = 2
        nextKeyboardButton.setContentHuggingPriority(.required, for: .horizontal)
        gridViewport.clipsToBounds = true
        gridViewport.backgroundColor = .clear
        pagingPreview.backgroundColor = .clear
        pagingPreview.dataSource = self; pagingPreview.delegate = self
        pagingPreview.isUserInteractionEnabled = false; pagingPreview.isAccessibilityElement = false
        pagingPreview.accessibilityElementsHidden = true
        pagingPreview.topEdgeEffect.isHidden = true; pagingPreview.bottomEdgeEffect.isHidden = true
        pagingPreview.showsVerticalScrollIndicator = false
        pagingPreview.contentInsetAdjustmentBehavior = .never
        pagingPreview.contentInset = collectionView.contentInset
        pagingPreview.register(StickerCell.self, forCellWithReuseIdentifier: StickerCell.reuseID)
        pagingPreview.isHidden = true
        for grid in [collectionView, pagingPreview] {
            grid.translatesAutoresizingMaskIntoConstraints = false
            gridViewport.addSubview(grid)
            NSLayoutConstraint.activate([
                grid.topAnchor.constraint(equalTo: gridViewport.topAnchor), grid.bottomAnchor.constraint(equalTo: gridViewport.bottomAnchor),
                grid.leadingAnchor.constraint(equalTo: gridViewport.leadingAnchor), grid.trailingAnchor.constraint(equalTo: gridViewport.trailingAnchor)
            ])
        }
        let stack = UIStackView(arrangedSubviews: [topBar, gridViewport])
        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: outerInset),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: outerInset),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -outerInset),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        toast.backgroundColor = .secondarySystemBackground
        toast.layer.cornerRadius = 12
        toast.isHidden = true
        toast.isUserInteractionEnabled = false
        toast.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        toast.addSubview(statusLabel)
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: -8),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: collectionView.leadingAnchor, constant: 8),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: collectionView.trailingAnchor, constant: -8),
            statusLabel.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -12),
            statusLabel.topAnchor.constraint(equalTo: toast.topAnchor, constant: 8),
            statusLabel.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -8)
        ])

        // Only the root requests a height. The grid fills the size UIKit assigns it.
        updateContentMetrics()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitVerticalSizeClass.self]) {
            (controller: KeyboardViewController, _: UITraitCollection) in
            controller.updateContentMetrics()
            controller.collectionView.collectionViewLayout.invalidateLayout()
        }
        refreshPermission()
        _ = restoreInitialLibrary()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let epoch = UserDefaults(suiteName: LibraryReader.appGroup)?.string(forKey: "appResetEpoch"),
           UserDefaults.standard.string(forKey: "appliedResetEpoch") != epoch {
            recent.clear(); packOrder.reset(); selectionStore.save(.all); selection = .all
            UserDefaults.standard.set(epoch, forKey: "appliedResetEpoch")
        }
        presentationActive = true
        loadGeneration += 1
        loadTask?.cancel()
        copyTask?.cancel()
        // Finish restoration before this controller can draw in a new host/field.
        // A retained controller may be older than another controller in this process.
        UIView.performWithoutAnimation {
            cancelPaging()
            needsRevealSelectedTab = true
            updateContentMetrics()
            let selectionChanged = selection != selectionStore.selection
            selection = selectionStore.selection
            let historyChanged = recent.reload()
            let orderChanged = packOrder.reload()
            if !restoreInitialLibrary(), selectionChanged || historyChanged || orderChanged {
                let byID = Dictionary(uniqueKeysWithValues: libraryPacks.map { ($0.id, $0) })
                packs = packOrder.orderedIDs(available: libraryPacks.map(\.id), prune: canPruneHistory).compactMap { byID[$0] }
                reconcileSelection()
                prewarmFirstFrame()
                applySelection()
            }
            prewarmFirstFrame()
            collectionView.setContentOffset(.zero, animated: false)
            refreshPermission(resetStatus: true)
            collectionView.visibleCells.forEach { $0.isHighlighted = false }
            packTabs.arrangedSubviews.compactMap { $0 as? UIButton }.forEach { $0.isHighlighted = false }
            view.layoutIfNeeded()
            collectionView.layoutIfNeeded()
        }
        playbackSuspended = false
        updatePlaybackState()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateSwitchKey()
        refreshPermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        revealSelectedTabIfNeeded()
    }

    private func revealSelectedTabIfNeeded() {
        guard tabScroll.bounds.width > 0 else { return }
        if tabScroll.bounds.width != lastTabViewportWidth {
            lastTabViewportWidth = tabScroll.bounds.width
            needsRevealSelectedTab = true
        }
        guard needsRevealSelectedTab,
              let button = packTabs.arrangedSubviews.first(where: { $0.accessibilityIdentifier == selectionIdentifier() }),
              button.bounds.width > 0 else { return }
        needsRevealSelectedTab = false
        let rect = button.convert(button.bounds, to: tabScroll)
        let minimum = tabScroll.contentOffset.x + 4
        let maximum = tabScroll.contentOffset.x + tabScroll.bounds.width - 4
        if rect.minX < minimum || rect.maxX > maximum {
            let offset = max(0, min(tabScroll.contentSize.width - tabScroll.bounds.width,
                                   rect.midX - tabScroll.bounds.width / 2))
            tabScroll.setContentOffset(CGPoint(x: offset, y: 0), animated: false)
        }
    }

    private func updateSwitchKey() {
        let needed = needsInputModeSwitchKey
        moreWidth?.constant = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 44 : 36
        let height: CGFloat = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 56 : (needed ? 44 : 32)
        guard nextKeyboardButton.isHidden == needed || tabHeight?.constant != height || globeHeight?.isActive != needed else { return }
        UIView.performWithoutAnimation {
            globeHeight?.isActive = needed
            nextKeyboardButton.isHidden = !needed
            tabHeight?.constant = height
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        finishPackDrag(commit: false)
        cancelPaging()
        collectionView.collectionViewLayout.invalidateLayout()
        pagingPreview.collectionViewLayout.invalidateLayout()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        presentationActive = false
        loadGeneration += 1
        playbackSuspended = true
        updatePlaybackState()
        copyTask?.cancel()
        collectionView.setContentOffset(collectionView.contentOffset, animated: false)
        tabScroll.setContentOffset(tabScroll.contentOffset, animated: false)
        cancelPaging()
        resetStatusTask?.cancel()
        loadTask?.cancel()
        finishPackDrag(commit: false)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        images.removeAll()
        playbackSuspended = true
        updatePlaybackState()
        Task { await GIFFrameDecoder.shared.clear(); await StickerThumbnailDecoder.shared.clear() }
    }

    private var preferredKeyboardHeight: CGFloat {
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            ? 380 : (traitCollection.verticalSizeClass == .compact ? 200 : 240)
    }

    private func updateContentMetrics() {
        if keyboardHeight?.constant != preferredKeyboardHeight {
            keyboardHeight?.constant = preferredKeyboardHeight
        }
        images.setMaximumPixelSize(traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 256 : 160)
        updateSwitchKey()
        collectionView.collectionViewLayout.invalidateLayout()
        pagingPreview.collectionViewLayout.invalidateLayout()
    }

    private func refreshPermission(resetStatus: Bool = false) {
        let allowed = hasFullAccess
        if allowed { KeyboardAccessReceipt.recordAllowed() }
        guard resetStatus || previousFullAccess != allowed else { return }
        let event = allowed ? KeyboardAccessReceipt.allowedNotification : KeyboardAccessReceipt.deniedNotification
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: event as CFString), nil, nil, true)
        previousFullAccess = allowed
        resetStatusTask?.cancel()
        lastCopiedID = nil
        collectionView.visibleCells.compactMap { $0 as? StickerCell }.forEach { $0.setCopied(false) }
        showIdleStatus()
    }

    private func showIdleStatus() {
        toast.isHidden = true
        statusLabel.text = nil
    }

    private func showMessage(_ message: String, copied: Bool = false, persistent: Bool = false) {
        resetStatusTask?.cancel()
        statusLabel.text = message
        statusLabel.textColor = copied ? .label : .secondaryLabel
        toast.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: message)
        guard !persistent else { return }
        resetStatusTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            self?.lastCopiedID = nil
            self?.collectionView.visibleCells.compactMap { $0 as? StickerCell }.forEach { $0.setCopied(false) }
            self?.showIdleStatus()
        }
    }

    @discardableResult
    private func restoreInitialLibrary() -> Bool {
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

    private func updateCacheGeneration(_ generation: String?) {
        guard generation != cacheGeneration else { return }
        cacheGeneration = generation
        images.removeAll()
        Task { await GIFFrameDecoder.shared.clear(); await StickerThumbnailDecoder.shared.clear() }
    }

    private func reconcileSelection() {
        if case .pack(let id) = selection, !packs.contains(where: { $0.id == id }), canPruneHistory {
            selection = .all
            selectionStore.save(selection)
        }
    }

    private func prewarmFirstFrame() {
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

    private func acceptLibrary(reader: LibraryReader, snapshot: LibrarySnapshot) {
        Self.cachedLibrary = (reader, snapshot)
        self.reader = reader
        libraryRevision = snapshot.revision
        updateCacheGeneration(snapshot.cacheGeneration)
        libraryPacks = snapshot.packs
        prepared = Dictionary(uniqueKeysWithValues: snapshot.packs.map { pack in
            (pack.id, pack.stickers.compactMap { record -> SampleSticker? in
                guard let png = snapshot.files[record.pngPath], let thumb = snapshot.files[record.thumbnailPath] else { return nil }
                return SampleSticker(id: pack.id + "." + record.id, name: record.name, detail: pack.title, imageURL: png, thumbnailURL: thumb,
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

    private func reloadLibrary(preservingStatus: String? = nil, persistentStatus: Bool = true, force: Bool = false) {
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

    private func applySelection() {
        let interval = performance.beginInterval("Pack Selection")
        defer { performance.endInterval("Pack Selection", interval) }
        UIView.performWithoutAnimation { renderSelection() }
    }

    private func renderSelection() {
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

    private func selectionIdentifier() -> String {
        switch selection { case .all: "packTab.all"; case .recent: "packTab.recent"; case .pack(let id): "packTab." + id }
    }

    private func selectList(_ id: Selection, persist: Bool = true) {
        if !committingPage { cancelPaging() }
        if persist { selectionStore.save(id) }
        needsRevealSelectedTab = true
        guard selection != id else { view.setNeedsLayout(); return }
        selection = id
        resetStatusTask?.cancel()
        lastCopiedID = nil
        applySelection()
        collectionView.setContentOffset(.zero, animated: false)
        showIdleStatus()
    }

    private func sections(for selection: Selection) -> [[SampleSticker]] {
        switch selection {
        case .all: return packs.compactMap { pack in
            let items = prepared[pack.id] ?? []; return items.isEmpty ? nil : items
        }
        case .recent: return [recent.ids.compactMap { byStickerID[$0] }]
        case .pack(let id): return [prepared[id] ?? []]
        }
    }

    private func adjacentSelection(direction: CGFloat) -> Selection? {
        let choices: [Selection] = [.all, .recent] + packs.map { .pack($0.id) }
        guard let current = choices.firstIndex(of: selection) else { return nil }
        let next = current + (direction < 0 ? 1 : -1)
        return choices.indices.contains(next) ? choices[next] : nil
    }

    private func preparePage(direction: CGFloat) {
        let target = adjacentSelection(direction: direction)
        guard target != pagingTarget || direction != pagingDirection else { return }
        pagingDirection = direction; pagingTarget = target
        pagingSections = target.map { sections(for: $0) } ?? []
        pagingPreview.isHidden = target == nil
        pagingPreview.contentOffset = .zero
        pagingPreview.reloadData(); pagingPreview.layoutIfNeeded()
    }

    private func cancelPaging() {
        pagingGeneration += 1
        let animator = pageAnimator
        pageAnimator = nil
        if animator?.state == .active { animator?.stopAnimation(true) }
        collectionView.layer.removeAllAnimations(); pagingPreview.layer.removeAllAnimations()
        collectionView.transform = .identity; pagingPreview.transform = .identity
        if let target = settlingSelection {
            settlingSelection = nil
            committingPage = true
            // The intent was persisted on release. Never overwrite a newer host's selection here.
            selectList(target, persist: false)
            collectionView.layoutIfNeeded()
            committingPage = false
        }
        pagingPreview.alpha = 1; pagingPreview.isHidden = true
        pagingTarget = nil; pagingDirection = 0; pagingSections = []
        pagingPreview.reloadData()
        updatePlaybackState()
    }

    @objc private func handlePackSwipe(_ gesture: UIPanGestureRecognizer) {
        guard presentationActive else { cancelPaging(); return }
        let width = max(1, gridViewport.bounds.width)
        let distance = gesture.translation(in: gridViewport).x
        switch gesture.state {
        case .began:
            cancelPaging(); showIdleStatus()
            preparePage(direction: gesture.velocity(in: gridViewport).x < 0 ? -1 : 1)
            updatePlaybackState()
        case .changed:
            let direction: CGFloat = distance < 0 ? -1 : 1
            preparePage(direction: direction)
            let offset = pagingTarget == nil ? distance * 0.22 : min(width, max(-width, distance))
            collectionView.transform = CGAffineTransform(translationX: offset, y: 0)
            pagingPreview.transform = CGAffineTransform(translationX: offset - direction * width, y: 0)
        case .ended, .cancelled, .failed:
            let speed = gesture.velocity(in: gridViewport).x
            let commit = gesture.state == .ended && pagingTarget != nil &&
                (abs(distance) >= max(44, width * 0.22) || (abs(distance) >= 20 && abs(speed) >= 350))
            let target = pagingTarget, direction = pagingDirection
            let generation = pagingGeneration
            if commit, let target {
                settlingSelection = target
                selectionStore.save(target)
            }
            let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.16
            let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut) {
                self.collectionView.transform = commit ? CGAffineTransform(translationX: direction * width, y: 0) : .identity
                self.pagingPreview.transform = commit ? .identity : CGAffineTransform(translationX: -direction * width, y: 0)
            }
            animator.isUserInteractionEnabled = true
            animator.isInterruptible = true
            animator.addCompletion { [weak self] _ in
                guard let self, self.presentationActive, self.pagingGeneration == generation else { return }
                self.cancelPaging()
            }
            pageAnimator = animator
            animator.startAnimation()
        default: break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === packSwipe {
            let velocity = packSwipe.velocity(in: gridViewport)
            return dragSession == nil && abs(velocity.x) > 2 * abs(velocity.y)
        }
        let point = gestureRecognizer.location(in: packTabs)
        return packTabs.arrangedSubviews.compactMap { $0 as? PackTabButton }
            .contains { $0.packID != nil && $0.frame.contains(point) }
    }

    @objc private func handlePackDrag(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let point = gesture.location(in: packTabs)
            guard let button = packTabs.arrangedSubviews.compactMap({ $0 as? PackTabButton })
                .first(where: { $0.packID != nil && $0.frame.contains(point) }),
                  let id = button.packID,
                  let preview = button.snapshotView(afterScreenUpdates: false) else { return }
            resetStatusTask?.cancel()
            showIdleStatus()
            preview.frame = button.convert(button.bounds, to: tabScroll)
            preview.isUserInteractionEnabled = false
            preview.layer.cornerRadius = 12
            preview.backgroundColor = .tertiarySystemFill
            tabScroll.addSubview(preview)
            button.alpha = 0.15
            tabScroll.isScrollEnabled = false
            dragSession = PackDragSession(id: id, button: button, preview: preview, originalPacks: packs,
                viewportX: gesture.location(in: tabScroll).x - tabScroll.bounds.minX)
            let link = CADisplayLink(target: dragProxy, selector: #selector(PackDragScrollProxy.step(_:)))
            link.add(to: .main, forMode: .common)
            dragDisplayLink = link
        case .changed:
            guard let session = dragSession else { return }
            session.viewportX = gesture.location(in: tabScroll).x - tabScroll.bounds.minX
            updatePackDragPosition()
        case .ended: finishPackDrag(commit: true)
        case .cancelled, .failed: finishPackDrag(commit: false)
        default: break
        }
    }

    fileprivate func stepPackDrag(_ link: CADisplayLink) {
        guard let session = dragSession else { return }
        let edge: CGFloat = 30
        let width = tabScroll.bounds.width
        let velocity: CGFloat
        if session.viewportX < edge { velocity = -180 * min(1, (edge - session.viewportX) / edge) }
        else if session.viewportX > width - edge { velocity = 180 * min(1, (session.viewportX - width + edge) / edge) }
        else { return }
        let maximum = max(0, tabScroll.contentSize.width - width)
        let offset = min(maximum, max(0, tabScroll.contentOffset.x + velocity * min(link.duration, 1 / 30)))
        guard offset != tabScroll.contentOffset.x else { return }
        tabScroll.contentOffset.x = offset
        updatePackDragPosition()
    }

    private func updatePackDragPosition() {
        guard let session = dragSession else { return }
        let x = tabScroll.bounds.minX + session.viewportX
        session.preview.center.x = min(tabScroll.bounds.maxX - session.preview.bounds.width / 2,
            max(tabScroll.bounds.minX + session.preview.bounds.width / 2, x))
        let point = tabScroll.convert(CGPoint(x: x, y: tabScroll.bounds.midY), to: packTabs)
        let buttons = packTabs.arrangedSubviews.compactMap { $0 as? PackTabButton }.filter { $0.packID != nil }
        guard let closest = buttons.min(by: { abs($0.center.x - point.x) < abs($1.center.x - point.x) }),
              closest !== session.button,
              let source = packs.firstIndex(where: { $0.id == session.id }),
              let target = packs.firstIndex(where: { $0.id == closest.packID }) else { return }
        let pack = packs.remove(at: source)
        packs.insert(pack, at: target)
        packTabs.removeArrangedSubview(session.button)
        packTabs.insertArrangedSubview(session.button, at: target + 2)
        // Keep the gesture's view and tab hierarchy intact while the finger moves.
        if UIAccessibility.isReduceMotionEnabled { tabScroll.layoutIfNeeded() }
        else { UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.tabScroll.layoutIfNeeded()
        } }
    }

    private func finishPackDrag(commit: Bool) {
        dragDisplayLink?.invalidate()
        dragDisplayLink = nil
        guard let session = dragSession else { return }
        dragSession = nil
        session.preview.removeFromSuperview()
        session.button.alpha = 1
        tabScroll.isScrollEnabled = true
        let changed = packs.map(\.id) != session.originalPacks.map(\.id)
        if commit, changed, packOrder.reorder(packs.map(\.id), available: session.originalPacks.map(\.id)) {
            applySelection()
            showMessage("키보드 팩 순서를 변경했어요.")
        } else {
            packs = session.originalPacks
            applySelection()
        }
    }

    private func clearHistoryAction() -> UIAction {
        UIAction(title: "최근 사용 내역 비우기", image: UIImage(systemName: "trash"),
                 attributes: recent.ids.isEmpty ? [.destructive, .disabled] : .destructive) { [weak self] _ in
            guard let self else { return }
            self.recent.clear()
            self.lastCopiedID = nil
            self.applySelection()
            self.showMessage("최근 사용 내역을 비웠어요.")
        }
    }

    private func resetOrderAction() -> UIAction {
        UIAction(title: "앱의 팩 순서로 되돌리기", image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
            self?.packOrder.reset()
            self?.reloadLibrary(preservingStatus: "앱의 팩 순서로 되돌렸어요.", persistentStatus: false, force: true)
        }
    }

    private func movePack(_ id: String, offset: Int) {
        guard packOrder.move(id, offset: offset, available: packs.map(\.id)) else { return }
        let byID = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0) })
        packs = packOrder.orderedIDs(available: packs.map(\.id)).compactMap { byID[$0] }
        applySelection()
        showMessage("키보드 팩 순서를 변경했어요.")
    }

    private func selectionDescription() -> String {
        let title: String
        switch selection {
        case .all: title = "전체"
        case .recent: title = "최근 사용"
        case .pack(let id): title = packs.first(where: { $0.id == id })?.title ?? "스티커"
        }
        return "\(title) · \(stickers.count)개"
    }

    private func updateSelectionDescription() {
        collectionView.accessibilityLabel = selectionDescription()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        (collectionView === pagingPreview ? pagingSections : visibleSections).count
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let sections = collectionView === pagingPreview ? pagingSections : visibleSections
        return sections.indices.contains(section) ? sections[section].count : 0
    }
    private func sticker(at path: IndexPath, in grid: UICollectionView) -> SampleSticker? {
        let sections = grid === pagingPreview ? pagingSections : visibleSections
        guard sections.indices.contains(path.section), sections[path.section].indices.contains(path.item) else { return nil }
        return sections[path.section][path.item]
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: StickerCell.reuseID, for: indexPath)
        if let stickerCell = cell as? StickerCell {
            guard let sticker = sticker(at: indexPath, in: collectionView) else { return cell }
            stickerCell.configure(sticker: sticker, image: images.cachedThumbnail(for: sticker), copied: collectionView === self.collectionView && sticker.id == lastCopiedID)
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

    private func updatePlaybackState() {
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

    private func copySticker(_ sticker: SampleSticker, asPNG: Bool = false) {
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

    private func performCopy(_ sticker: SampleSticker, asPNG: Bool = false) {
        let result = copier.copy(sticker, isAllowed: hasFullAccess, asPNG: asPNG)
        // Errors stay visible until the user chooses another action; ordinary feedback costs no layout space.
        guard result == .copied else {
            self.showMessage(result.message, persistent: true)
            if result == .fileUnavailable || result == .invalidPNG { reloadLibrary(preservingStatus: result.message) }
            return
        }
        recent.record(sticker.id)
        lastCopiedID = sticker.id
        if selection == .recent { applySelection() }
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

private final class StickerCell: UICollectionViewCell {
    static let reuseID = "StickerCell"
    private let imageView = GIFPlaybackView()
    private var playbackURL: URL?
    var imageTask: Task<Void, Never>?
    private(set) var imageToken = UUID()
    private let animationBadge = UILabel()
    private let copiedBadge = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 8
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        copiedBadge.tintColor = .systemGreen
        copiedBadge.backgroundColor = .systemBackground
        copiedBadge.layer.cornerRadius = 8
        copiedBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copiedBadge)
        animationBadge.text = "GIF"
        animationBadge.font = .systemFont(ofSize: 8, weight: .semibold)
        animationBadge.textColor = .secondaryLabel
        animationBadge.backgroundColor = .secondarySystemBackground
        animationBadge.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(animationBadge)
        NSLayoutConstraint.activate([
            copiedBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            copiedBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -3),
            copiedBadge.widthAnchor.constraint(equalToConstant: 16),
            copiedBadge.heightAnchor.constraint(equalToConstant: 16),
            animationBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),
            animationBadge.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 1),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 1),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -1),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -1)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }

    func configure(sticker: SampleSticker, image: UIImage?, copied: Bool) {
        imageTask?.cancel(); imageTask = nil
        imageToken = UUID()
        setCopied(copied)
        playbackURL = sticker.playbackURL
        imageView.configure(url: playbackURL, poster: image)
        animationBadge.isHidden = sticker.animationURL == nil
        accessibilityLabel = "\(sticker.detail), \(sticker.name)"
        accessibilityHint = sticker.animationURL == nil ? "탭하면 PNG 이미지를 복사합니다." : "탭하면 GIF를 복사합니다. 길게 눌러 정적 PNG를 선택할 수 있습니다."
        accessibilityIdentifier = "keyboardSticker.\(sticker.id)"
    }

    func setPoster(_ image: UIImage?) { imageView.setPoster(image) }
    func setPlaybackPaused(_ value: Bool) { imageView.playbackPaused = value }
    func stopPlayback() { imageTask?.cancel(); imageTask = nil; imageView.stop() }
    func resumePlayback() { imageView.configure(url: playbackURL, poster: imageView.image) }

    func setCopied(_ copied: Bool) {
        copiedBadge.isHidden = !copied
        contentView.backgroundColor = copied ? .systemBlue.withAlphaComponent(0.08) : .clear
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil
        imageToken = UUID()
        playbackURL = nil
        imageView.stop(); imageView.image = nil
    }

    override var isHighlighted: Bool {
        didSet {
            contentView.alpha = isHighlighted ? 0.6 : 1
            contentView.transform = isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
        }
    }
}

private final class PackTabButton: UIButton {
    var packID: String?
}

@MainActor
private final class PackDragSession {
    let id: String
    let button: PackTabButton
    let preview: UIView
    let originalPacks: [PackManifestV1]
    var viewportX: CGFloat
    init(id: String, button: PackTabButton, preview: UIView, originalPacks: [PackManifestV1], viewportX: CGFloat) {
        self.id = id; self.button = button; self.preview = preview
        self.originalPacks = originalPacks; self.viewportX = viewportX
    }
}

@MainActor
private final class PackDragScrollProxy: NSObject {
    weak var owner: KeyboardViewController?
    init(owner: KeyboardViewController) { self.owner = owner }
    @objc func step(_ link: CADisplayLink) { owner?.stepPackDrag(link) }
}

private final class PackTabScrollView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { view is UIControl || super.touchesShouldCancel(in: view) }
}
