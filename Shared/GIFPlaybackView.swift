import UIKit
import ImageIO

nonisolated struct GIFTimeline: Sendable {
    let ends: [Double]
    let loops: Int
    var duration: Double { ends.last ?? 0 }
    func frame(at elapsed: Double) -> Int {
        guard duration > 0 else { return 0 }
        if loops > 0, elapsed >= duration * Double(loops + 1) { return ends.count - 1 }
        let time = elapsed.truncatingRemainder(dividingBy: duration)
        return ends.firstIndex { $0 > time } ?? ends.count - 1
    }
}

/// One serial decoder, bounded decoded-frame cache. No array of decoded animation frames.
actor GIFFrameDecoder {
    static let shared = GIFFrameDecoder()
    private var sources: [URL: CGImageSource] = [:]
    private let frames = NSCache<NSString, CGImage>()
    init() { frames.totalCostLimit = 12 * 1024 * 1024 }
    private func source(_ url: URL) -> CGImageSource? {
        if let existing = sources[url] { return existing }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              (2...300).contains(CGImageSourceGetCount(source)),
              CGImageSourceGetStatus(source) == .statusComplete else { return nil }
        for i in 0..<CGImageSourceGetCount(source) {
            guard let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                  let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int,
                  (1...512).contains(w), (1...512).contains(h) else { return nil }
        }
        if sources.count >= 32 { sources.removeAll() }
        sources[url] = source
        return source
    }
    func timeline(_ url: URL) -> GIFTimeline? {
        guard let source = source(url) else { return nil }
        var ends: [Double] = [], time = 0.0
        for i in 0..<CGImageSourceGetCount(source) {
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            guard delay.isFinite, delay >= 0.01, delay <= 10.2 else { return nil }
            time += delay; ends.append(time)
        }
        guard time <= 10.2 else { return nil }
        let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        let loops = (props?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int ?? 0
        return GIFTimeline(ends: ends, loops: loops)
    }
    func frame(_ url: URL, index: Int, pixels: Int) -> CGImage? {
        guard !Task.isCancelled else { return nil }
        let key = "\(url.path):\(index):\(pixels)" as NSString
        if let image = frames.object(forKey: key) { return image }
        guard let source = source(url), index < CGImageSourceGetCount(source), let image = CGImageSourceCreateThumbnailAtIndex(source, index, [
            kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: pixels,
            kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary) else { return nil }
        frames.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
    func clear() { frames.removeAllObjects(); sources.removeAll() }
}

@MainActor
final class GIFPlaybackView: UIImageView {
    private var url: URL?
    private var timeline: GIFTimeline?
    private var started = CACurrentMediaTime()
    private var shown = -1
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var pixels = 96
    var playbackPaused = false
    func configure(url: URL?, poster: UIImage?, pixels: Int = 96) {
        // willDisplay can run again for an unchanged cell during host transitions.
        // Keep the current decoded frame and timeline instead of flashing the poster.
        if let url, self.url == url, self.pixels == pixels, timeline != nil || task != nil {
            if shown < 0, image == nil, let poster { image = poster }
            return
        }
        stop(); started = CACurrentMediaTime(); image = poster; self.url = url; self.pixels = pixels
        guard let url else { return }
        let generation = generation
        task = Task { [weak self] in
            let timeline = await GIFFrameDecoder.shared.timeline(url)
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            self.timeline = timeline; self.task = nil
            if self.window != nil { GIFPlaybackClock.shared.add(self) }
        }
    }
    func setPoster(_ poster: UIImage?) { if shown < 0, image == nil { image = poster } }
    func stop() {
        generation = UUID(); task?.cancel(); task = nil; timeline = nil; url = nil; shown = -1
        GIFPlaybackClock.shared.remove(self)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { GIFPlaybackClock.shared.remove(self) }
        else if timeline != nil { GIFPlaybackClock.shared.add(self) }
    }
    /// Test visibility through every clipping ancestor, including the paging viewport.
    /// A cell can still have a window while its page is hidden or translated offscreen.
    var isPlaybackVisible: Bool {
        guard let window, !bounds.isEmpty else { return false }
        var visible = convert(bounds, to: window).intersection(window.bounds)
        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01 else { return false }
            if view.clipsToBounds {
                visible = visible.intersection(view.convert(view.bounds, to: window))
            }
            guard !visible.isNull, !visible.isEmpty else { return false }
            ancestor = view.superview
        }
        return true
    }

    fileprivate func tick(_ time: Double) {
        guard !playbackPaused, isPlaybackVisible,
              let url, let timeline, task == nil else { return }
        let index = UIAccessibility.isReduceMotionEnabled ? 0 : timeline.frame(at: max(0, time - started))
        guard index != shown else { return }
        let generation = generation, pixels = pixels
        task = Task { [weak self] in
            let frame = await GIFFrameDecoder.shared.frame(url, index: index, pixels: pixels)
            guard let self, !Task.isCancelled, self.generation == generation else { return }
            if let frame { self.image = UIImage(cgImage: frame); self.shown = index }
            self.task = nil
        }
    }
}

@MainActor
private final class GIFPlaybackClock: NSObject {
    static let shared = GIFPlaybackClock()
    private let views = NSHashTable<GIFPlaybackView>.weakObjects()
    private var link: CADisplayLink?
    func add(_ view: GIFPlaybackView) {
        views.add(view)
        if link == nil {
            let link = CADisplayLink(target: self, selector: #selector(step))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 15, preferred: 15)
            link.add(to: .main, forMode: .common); self.link = link
        }
    }
    func remove(_ view: GIFPlaybackView) {
        views.remove(view)
        if views.allObjects.isEmpty { link?.invalidate(); link = nil }
    }
    @objc private func step(_ link: CADisplayLink) {
        let views = views.allObjects
        if views.isEmpty { self.link?.invalidate(); self.link = nil }
        for view in views { view.tick(link.timestamp) }
    }
}
