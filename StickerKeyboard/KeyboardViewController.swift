import UIKit
import os

final class KeyboardViewController: UIInputViewController,
                                    UICollectionViewDataSource,
                                    UICollectionViewDelegate, UIGestureRecognizerDelegate {
    let state = KeyboardState()
    let performance = OSSignposter(subsystem: "com.sihyeon.TelegramSticker.StickerKeyboard", category: "PointsOfInterest")
    var displayedCacheGeneration: String?
    var tabSignature: [String] = []
    var playbackSuspended = false
    typealias Selection = KeyboardSelection
    var dragSession: PackDragSession?
    var dragDisplayLink: CADisplayLink?
    lazy var dragProxy = PackDragScrollProxy(owner: self)
    let packTabs = UIStackView()
    lazy var packSwipe = UIPanGestureRecognizer(target: self, action: #selector(handlePackSwipe(_:)))
    let tabScroll = PackTabScrollView()
    let toast = UIView()
    var loadTask: Task<Void, Never>?
    var loadGeneration = 0
    var presentationActive = false
    var pagingGeneration = 0
    let images = StickerImages(maximumPixelSize: 160)
    let copier = StickerCopyService()
    let statusLabel = UILabel()
    let emptyLabel = UILabel()
    let nextKeyboardButton = UIButton(type: .system)
    let moreButton = UIButton(type: .system)
    let gridViewport = UIView()
    let pagingPreview = UICollectionView(frame: .zero, collectionViewLayout: StickerGridLayout())
    var visibleSections: [[Sticker]] = []
    var pagingSections: [[Sticker]] = []
    var pagingTarget: Selection?
    var pagingDirection: CGFloat = 0
    var pageAnimator: UIViewPropertyAnimator?
    var settlingSelection: Selection?
    var needsRevealSelectedTab = true
    var lastTabViewportWidth: CGFloat = 0
    var moreWidth: NSLayoutConstraint?
    let outerInset: CGFloat = 4
    var committingPage = false
    let collectionView = UICollectionView(frame: .zero,
                                                  collectionViewLayout: StickerGridLayout())
    var previousFullAccess: Bool?
    var resetStatusTask: Task<Void, Never>?
    var copyTask: Task<Void, Never>?
    var tabHeight: NSLayoutConstraint?
    var globeHeight: NSLayoutConstraint?
    var keyboardHeight: NSLayoutConstraint?

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
        state.restoreSelection()
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
        state.applyAppResetIfNeeded()
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
            let preferencesChanged = state.reloadPreferences()
            if !restoreInitialLibrary(), preferencesChanged {
                state.restorePackOrder()
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

    func revealSelectedTabIfNeeded() {
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

    func updateSwitchKey() {
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

    var preferredKeyboardHeight: CGFloat {
        traitCollection.preferredContentSizeCategory.isAccessibilityCategory
            ? 380 : (traitCollection.verticalSizeClass == .compact ? 200 : 240)
    }

    func updateContentMetrics() {
        if keyboardHeight?.constant != preferredKeyboardHeight {
            keyboardHeight?.constant = preferredKeyboardHeight
        }
        images.setMaximumPixelSize(traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? 256 : 160)
        updateSwitchKey()
        collectionView.collectionViewLayout.invalidateLayout()
        pagingPreview.collectionViewLayout.invalidateLayout()
    }
}
