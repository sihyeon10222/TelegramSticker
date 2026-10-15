import UIKit
import os

extension KeyboardViewController {
    func selectionIdentifier() -> String {
        switch state.selection { case .all: "packTab.all"; case .recent: "packTab.recent"; case .pack(let id): "packTab." + id }
    }

    func selectList(_ id: Selection, persist: Bool = true) {
        if !committingPage { cancelPaging() }
        if persist { state.persistSelection(id) }
        needsRevealSelectedTab = true
        guard state.selection != id else { view.setNeedsLayout(); return }
        state.select(id, persist: false)
        resetStatusTask?.cancel()
        state.clearCopiedSticker()
        applySelection()
        collectionView.setContentOffset(.zero, animated: false)
        showIdleStatus()
    }

    func adjacentSelection(direction: CGFloat) -> Selection? {
        let choices: [Selection] = [.all, .recent] + state.packs.map { .pack($0.id) }
        guard let current = choices.firstIndex(of: state.selection) else { return nil }
        let next = current + (direction < 0 ? 1 : -1)
        return choices.indices.contains(next) ? choices[next] : nil
    }

    func preparePage(direction: CGFloat) {
        let target = adjacentSelection(direction: direction)
        guard target != pagingTarget || direction != pagingDirection else { return }
        pagingDirection = direction; pagingTarget = target
        pagingSections = target.map { state.sections(for: $0) } ?? []
        pagingPreview.isHidden = target == nil
        pagingPreview.contentOffset = .zero
        pagingPreview.reloadData(); pagingPreview.layoutIfNeeded()
    }

    func cancelPaging() {
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

    @objc func handlePackSwipe(_ gesture: UIPanGestureRecognizer) {
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
                state.persistSelection(target)
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
}
