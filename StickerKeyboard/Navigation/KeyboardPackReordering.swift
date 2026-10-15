import UIKit
import os

extension KeyboardViewController {
    @objc func handlePackDrag(_ gesture: UILongPressGestureRecognizer) {
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

    func stepPackDrag(_ link: CADisplayLink) {
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

    func updatePackDragPosition() {
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

    func finishPackDrag(commit: Bool) {
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

    func clearHistoryAction() -> UIAction {
        UIAction(title: "최근 사용 내역 비우기", image: UIImage(systemName: "trash"),
                 attributes: recent.ids.isEmpty ? [.destructive, .disabled] : .destructive) { [weak self] _ in
            guard let self else { return }
            self.recent.clear()
            self.lastCopiedID = nil
            self.applySelection()
            self.showMessage("최근 사용 내역을 비웠어요.")
        }
    }

    func resetOrderAction() -> UIAction {
        UIAction(title: "앱의 팩 순서로 되돌리기", image: UIImage(systemName: "arrow.counterclockwise")) { [weak self] _ in
            self?.packOrder.reset()
            self?.reloadLibrary(preservingStatus: "앱의 팩 순서로 되돌렸어요.", persistentStatus: false, force: true)
        }
    }

    func movePack(_ id: String, offset: Int) {
        guard packOrder.move(id, offset: offset, available: packs.map(\.id)) else { return }
        let byID = Dictionary(uniqueKeysWithValues: packs.map { ($0.id, $0) })
        packs = packOrder.orderedIDs(available: packs.map(\.id)).compactMap { byID[$0] }
        applySelection()
        showMessage("키보드 팩 순서를 변경했어요.")
    }
}
