import UIKit
import os

extension KeyboardViewController {
    func selectionIdentifier() -> String {
        switch state.selection { case .all: "packTab.all"; case .recent: "packTab.recent"; case .pack(let id): "packTab." + id }
    }

    func selectList(_ id: Selection, persist: Bool = true, preservingPage: Bool = false) {
        if !committingPage { cancelPaging() }
        if persist { state.persistSelection(id) }
        needsRevealSelectedTab = true
        guard state.selection != id else { view.setNeedsLayout(); return }
        if !preservingPage { state.saveScrollOffset(Double(collectionView.contentOffset.y)) }
        state.select(id, persist: false)
        resetStatusTask?.cancel()
        state.clearCopiedSticker()
        applySelection()
        if !preservingPage {
            pendingScrollRestoration = true
            restoreScrollPositionIfNeeded()
        }
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
        // Prepare outside the viewport before exposing the destination page.
        pagingPreview.transform = CGAffineTransform(translationX: -direction * max(1, gridViewport.bounds.width), y: 0)
        pagingPreview.reloadData()
        // Measure without creating the top-of-pack cells before restoring Y.
        pagingPreview.collectionViewLayout.prepare()
        let maximum = max(0, pagingPreview.collectionViewLayout.collectionViewContentSize.height - pagingPreview.bounds.height)
        pagingPreview.contentOffset = CGPoint(x: 0, y: min(CGFloat(target.map { state.scrollOffset(for: $0) } ?? 0), maximum))
        pagingPreview.layoutIfNeeded()
        // Cell tasks decode missing posters off the main thread. Never read and
        // decode the whole destination viewport inside a pan event.
        pagingPreview.isHidden = target == nil
    }

    func cancelPaging() {
        pagingGeneration += 1
        let animator = pageAnimator
        pageAnimator = nil
        if animator?.state == .active { animator?.stopAnimation(true) }
        UIView.performWithoutAnimation {
            collectionView.layer.removeAllAnimations(); pagingPreview.layer.removeAllAnimations()
            if let target = settlingSelection {
                settlingSelection = nil
                // Promote the actual page the user has been watching. Reloading
                // into a different collection discarded its cells and GIF frames.
                state.saveScrollOffset(Double(collectionView.contentOffset.y))
                let outgoing = collectionView
                collectionView = pagingPreview
                pagingPreview = outgoing
                visibleSections = pagingSections
                pagingSections = []
                pagingPreview.backgroundView = nil
                collectionView.backgroundView = emptyLabel
                collectionView.isUserInteractionEnabled = true
                collectionView.accessibilityElementsHidden = false
                collectionView.accessibilityIdentifier = "stickerGrid"
                collectionView.showsVerticalScrollIndicator = true
                pagingPreview.isUserInteractionEnabled = false
                pagingPreview.accessibilityElementsHidden = true
                pagingPreview.accessibilityIdentifier = nil
                pagingPreview.showsVerticalScrollIndicator = false
                committingPage = true
                // Persisted on release; do not overwrite a newer host's selection.
                selectList(target, persist: false, preservingPage: true)
                committingPage = false
            }
            collectionView.transform = .identity
            pagingPreview.transform = .identity
            pagingPreview.alpha = 1; pagingPreview.isHidden = true
            pagingTarget = nil; pagingDirection = 0; pagingSections = []
            pagingPreview.reloadData()
        }
        updatePlaybackState()
        applyPendingLibraryIfPossible()
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
            let offset = pagingTarget == nil ? distance * 0.55 * width / (width + 0.55 * abs(distance)) : min(width, max(-width, distance))
            collectionView.transform = CGAffineTransform(translationX: offset, y: 0)
            pagingPreview.transform = CGAffineTransform(translationX: offset - direction * width, y: 0)
        case .ended, .cancelled, .failed:
            let speed = gesture.velocity(in: gridViewport).x
            let direction = pagingDirection
            // Project the release momentum, so a flick completes and a deliberate
            // reversal can cancel even after dragging beyond the distance threshold.
            let projected = distance + speed * 0.18
            let commit = gesture.state == .ended && pagingTarget != nil &&
                projected * direction > width * 0.28
            let target = pagingTarget
            let generation = pagingGeneration
            if commit, let target {
                settlingSelection = target
                state.persistSelection(target)
            }
            let destination = commit ? direction * width : 0
            let remaining = destination - collectionView.transform.tx
            let velocity = abs(remaining) > 1 ? max(-20, min(20, speed / remaining)) : 0
            let timing = UISpringTimingParameters(mass: 1, stiffness: 300, damping: 34,
                                                  initialVelocity: CGVector(dx: velocity, dy: 0))
            let animator = UIViewPropertyAnimator(duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.55,
                                                   timingParameters: timing)
            animator.addAnimations {
                self.collectionView.transform = CGAffineTransform(translationX: destination, y: 0)
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
            return dragSession == nil && abs(velocity.x) > abs(velocity.y) * 0.85
        }
        let point = gestureRecognizer.location(in: packTabs)
        return packTabs.arrangedSubviews.compactMap { $0 as? PackTabButton }
            .contains { $0.packID != nil && $0.frame.contains(point) }
    }
}
