import UIKit

final class StickerCell: UICollectionViewCell {
    static let reuseID = "StickerCell"
    private let imageView = GIFPlaybackView()
    private var playbackURL: URL?
    private var configuredSticker: Sticker?
    var hasDisplayedImage: Bool { imageView.image != nil }
    var imageTask: Task<Void, Never>?
    var playbackTask: Task<Void, Never>?
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

    func configure(sticker: Sticker, image: UIImage?, copied: Bool) {
        imageTask?.cancel(); imageTask = nil
        playbackTask?.cancel(); playbackTask = nil
        imageToken = UUID()
        setCopied(copied)
        // Preserve a running frame only for the exact same file references.
        // The controller resolves/revalidates playback off-main for this token.
        if configuredSticker != sticker { playbackURL = nil }
        configuredSticker = sticker
        imageView.configure(url: playbackURL, poster: image)
        animationBadge.isHidden = !sticker.isAnimated
        accessibilityLabel = "\(sticker.detail), \(sticker.name)"
        accessibilityHint = !sticker.isAnimated ? "탭하면 PNG 이미지를 복사합니다." : "탭하면 GIF를 복사합니다. 길게 눌러 정적 PNG를 선택할 수 있습니다."
        accessibilityIdentifier = "keyboardSticker.\(sticker.id)"
    }

    func setPoster(_ image: UIImage?) { imageView.setPoster(image) }
    func setPlaybackURL(_ url: URL?) {
        playbackURL = url
        imageView.configure(url: url, poster: imageView.image)
    }
    func setPlaybackPaused(_ value: Bool) { imageView.playbackPaused = value }
    func stopPlayback() {
        imageTask?.cancel(); imageTask = nil
        playbackTask?.cancel(); playbackTask = nil
        imageView.stop()
    }
    func resumePlayback() { imageView.configure(url: playbackURL, poster: imageView.image) }

    func setCopied(_ copied: Bool) {
        copiedBadge.isHidden = !copied
        contentView.backgroundColor = copied ? .systemBlue.withAlphaComponent(0.08) : .clear
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel(); imageTask = nil
        playbackTask?.cancel(); playbackTask = nil
        imageToken = UUID()
        configuredSticker = nil
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
