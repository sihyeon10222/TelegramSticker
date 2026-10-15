import UIKit
import os

extension KeyboardViewController {
    func applySelection() {
        let interval = performance.beginInterval("Pack Selection")
        defer { performance.endInterval("Pack Selection", interval) }
        UIView.performWithoutAnimation { renderSelection() }
    }

    func renderSelection() {
        state.prepareSelection()
        emptyLabel.text = state.libraryNote ?? (state.selection == .recent
            ? "최근 사용한 스티커가 없어요. 전체에서 스티커를 복사해 보세요."
            : "설치한 스티커가 없어요. 앱에서 Telegram 팩을 추가해 주세요.")
        emptyLabel.isHidden = !state.stickers.isEmpty
        let nextSections = state.sections(for: state.selection)
        updateSelectionDescription()
        if nextSections != visibleSections {
            visibleSections = nextSections
            collectionView.reloadData()
        }
        collectionView.visibleCells.compactMap { $0 as? StickerCell }.forEach {
            $0.setCopied($0.accessibilityIdentifier == state.lastCopiedID.map { "keyboardSticker." + $0 })
        }
        let signature = state.packs.map { pack in
            pack.id + ":" + pack.title + ":" + (state.prepared[pack.id]?.first?.thumbnailURL?.path ?? "")
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
            + state.packs.map { (.pack($0.id), $0.title, nil) }
        moreButton.menu = UIMenu(title: "팩 탭을 길게 잡고 드래그해 순서를 바꾸세요.", children: [
            clearHistoryAction(), resetOrderAction()
        ])
        for (id, title, symbol) in choices {
            let button = PackTabButton(type: .system)
            var config = UIButton.Configuration.plain()
            config.cornerStyle = .fixed
            config.background.cornerRadius = 10
            config.background.backgroundColor = id == state.selection ? .systemBlue.withAlphaComponent(0.12) : .clear
            config.background.strokeColor = id == state.selection ? .systemBlue.withAlphaComponent(0.35) : .clear
            config.background.strokeWidth = id == state.selection ? 1 : 0
            config.baseForegroundColor = id == state.selection ? .systemBlue : .secondaryLabel
            config.contentInsets = NSDirectionalEdgeInsets(top: 3, leading: 3, bottom: 3, trailing: 3)
            if let symbol {
                config.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
            } else { config.image = UIImage(systemName: "square.stack") }
            button.configuration = config
            if case .pack(let packID) = id, let cover = state.prepared[packID]?.first {
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
            button.accessibilityTraits = id == state.selection ? [.button, .selected] : .button
            packTabs.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: packTabs.heightAnchor, constant: 4).isActive = true
        }
        needsRevealSelectedTab = true
        view.setNeedsLayout()
    }
}
