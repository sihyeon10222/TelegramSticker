import SwiftUI
import UIKit

struct StickerSelectionFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The recognizer lives on the scroll view so empty grid spaces remain scrollable.
struct StickerDragSelection: UIViewRepresentable {
    let active: Bool
    let generation: Int
    let frames: [String: CGRect]
    let orderedIDs: [String]
    @Binding var selection: Set<String>
    let began: () -> Void
    let ended: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView {
        let view = AttachmentView()
        view.isUserInteractionEnabled = false
        view.attach = { [weak coordinator = context.coordinator] view in coordinator?.attach(view) }
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        if !active || generation != coordinator.parent.generation || orderedIDs != coordinator.parent.orderedIDs { coordinator.cancel() }
        coordinator.parent = self
        coordinator.attach(view)
        coordinator.pan.isEnabled = active
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.cancel()
        coordinator.pan.view?.removeGestureRecognizer(coordinator.pan)
    }

    final class AttachmentView: UIView {
        var attach: ((UIView) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); attach?(self) }
        override func layoutSubviews() { super.layoutSubviews(); attach?(self) }
    }

    final class HorizontalPan: UIPanGestureRecognizer {
        var origin = CGPoint.zero
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            if let touch = touches.first { origin = touch.location(in: view) }
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
            if state == .possible, let touch = touches.first {
                let point = touch.location(in: view)
                let dx = abs(point.x - origin.x), dy = abs(point.y - origin.y)
                if max(dx, dy) >= 6, dy >= dx { state = .failed; return }
            }
            super.touchesMoved(touches, with: event)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: StickerDragSelection
        weak var host: UIView?
        weak var scroll: UIScrollView?
        lazy var pan: HorizontalPan = {
            let gesture = HorizontalPan(target: self, action: #selector(handle))
            gesture.maximumNumberOfTouches = 1
            gesture.delegate = self
            return gesture
        }()
        var initialSelection = Set<String>()
        var anchorIndex: Int?
        var selecting = true
        var previous: CGPoint?
        var displayLink: CADisplayLink?
        var lastTimestamp: CFTimeInterval = 0

        init(_ parent: StickerDragSelection) { self.parent = parent }
        func attach(_ host: UIView) {
            self.host = host
            var ancestor = host.superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    guard self.scroll !== scroll else { return }
                    cancel()
                    pan.view?.removeGestureRecognizer(pan)
                    self.scroll = scroll
                    scroll.addGestureRecognizer(pan)
                    scroll.panGestureRecognizer.require(toFail: pan)
                    pan.isEnabled = parent.active
                    return
                }
                ancestor = view.superview
            }
        }
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard parent.active, let host else { return false }
            let start = host.convert(pan.origin, from: scroll)
            let velocity = pan.velocity(in: scroll)
            return abs(velocity.x) > abs(velocity.y) && parent.frames.values.contains { $0.contains(start) }
        }
        @objc func handle() {
            guard let host else { return }
            switch pan.state {
            case .began:
                initialSelection = parent.selection
                let start = host.convert(pan.origin, from: scroll)
                guard let id = parent.frames.first(where: { $0.value.contains(start) })?.key else { cancel(); return }
                guard let index = parent.orderedIDs.firstIndex(of: id) else { cancel(); return }
                anchorIndex = index
                selecting = !initialSelection.contains(id)
                previous = start
                parent.began()
                sweep(to: pan.location(in: host))
                let link = CADisplayLink(target: self, selector: #selector(tick))
                displayLink = link
                link.add(to: .main, forMode: .common)
            case .changed: sweep(to: pan.location(in: host))
            case .ended, .cancelled, .failed: finish()
            default: break
            }
        }
        func sweep(to point: CGPoint) {
            guard let anchorIndex else { return }
            // Resolve gaps and partially visible rows to the closest laid-out cell.
            guard let id = parent.frames.min(by: {
                distance(point, to: $0.value) < distance(point, to: $1.value)
            })?.key, let index = parent.orderedIDs.firstIndex(of: id) else { return }
            let range = Set(parent.orderedIDs[min(anchorIndex, index)...max(anchorIndex, index)])
            var result = initialSelection
            if selecting { result.formUnion(range) } else { result.subtract(range) }
            if result != parent.selection { parent.selection = result }
            previous = point
        }
        private func distance(_ point: CGPoint, to rect: CGRect) -> CGFloat {
            let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
            let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
            return dx * dx + dy * dy
        }
        @objc func tick(_ link: CADisplayLink) {
            guard let scroll, let host else { finish(); return }
            let elapsed = lastTimestamp == 0 ? link.duration : min(0.05, link.timestamp - lastTimestamp)
            lastTimestamp = link.timestamp
            let point = pan.location(in: scroll)
            let top = scroll.bounds.minY + scroll.adjustedContentInset.top
            let bottom = scroll.bounds.maxY - scroll.adjustedContentInset.bottom
            let edge: CGFloat = min(60, (bottom - top) / 3)
            var speed: CGFloat = 0
            if point.y < top + edge { speed = -min(1, max(0, (top + edge - point.y) / edge)) * 500 }
            else if point.y > bottom - edge { speed = min(1, max(0, (point.y - bottom + edge) / edge)) * 500 }
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let offset = min(maximum, max(minimum, scroll.contentOffset.y + speed * elapsed))
            if offset != scroll.contentOffset.y {
                scroll.contentOffset.y = offset
                scroll.layoutIfNeeded()
                sweep(to: pan.location(in: host))
            }
        }
        func finish() {
            let wasDragging = previous != nil
            displayLink?.invalidate(); displayLink = nil
            lastTimestamp = 0
            previous = nil
            initialSelection.removeAll()
            anchorIndex = nil
            if wasDragging { parent.ended() }
        }
        func cancel() {
            finish()
            pan.isEnabled = false
            pan.isEnabled = parent.active
        }
    }
}
