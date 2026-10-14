import UIKit

/// Uses current viewport bounds on every layout pass. There are no cached
/// delegate size metrics that can outlive a host app's keyboard-height change.
@MainActor
final class StickerGridLayout: UICollectionViewLayout {
    private struct Section {
        let count: Int
        let y: CGFloat
        let height: CGFloat
    }
    private var sections: [Section] = []
    private var columns = 1
    private var itemSize = CGSize(width: 44, height: 44)
    private var contentSize = CGSize.zero
    private let spacing: CGFloat = 2
    private let sectionGap: CGFloat = 6

    override func prepare() {
        super.prepare()
        guard let view = collectionView else { return }
        let width = max(1, view.bounds.width - view.contentInset.left - view.contentInset.right)
        let height = max(1, view.bounds.height - view.contentInset.top - view.contentInset.bottom)
        let accessible = view.traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        columns = accessible ? max(1, Int((width + spacing) / 102)) :
            max(1, min(Int((width + spacing) / 46), max(7, Int((width + spacing) / 58))))
        let cellWidth = (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
        let rows = max(1, min(4, Int((height + spacing) / (44 + spacing))))
        let cellHeight = accessible ? max(44, cellWidth) : max(44, (height - CGFloat(rows - 1) * spacing) / CGFloat(rows))
        itemSize = CGSize(width: cellWidth, height: cellHeight)
        sections = []
        sections.reserveCapacity(view.numberOfSections)
        var hasItems = false
        var y: CGFloat = 0
        for section in 0..<view.numberOfSections {
            let count = view.numberOfItems(inSection: section)
            if count > 0, hasItems { y += sectionGap }
            if count > 0 { hasItems = true }
            let rows = (count + columns - 1) / columns
            let sectionHeight = CGFloat(rows) * cellHeight + CGFloat(max(0, rows - 1)) * spacing
            sections.append(Section(count: count, y: y, height: sectionHeight))
            y += sectionHeight
        }
        contentSize = CGSize(width: width, height: y)
    }

    override var collectionViewContentSize: CGSize { contentSize }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.size != collectionView?.bounds.size
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard sections.indices.contains(indexPath.section),
              (0..<sections[indexPath.section].count).contains(indexPath.item) else { return nil }
        let section = sections[indexPath.section]
        let row = indexPath.item / columns, column = indexPath.item % columns
        let attributes = UICollectionViewLayoutAttributes(forCellWith: indexPath)
        attributes.frame = CGRect(x: CGFloat(column) * (itemSize.width + spacing),
                                  y: section.y + CGFloat(row) * (itemSize.height + spacing),
                                  width: itemSize.width, height: itemSize.height)
        return attributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        // Build attributes only for intersecting rows, including during animated paging.
        // A large library does not allocate an attribute object for every sticker.
        let visible = rect.intersection(CGRect(origin: .zero, size: contentSize))
        guard !visible.isNull, !visible.isEmpty else { return [] }
        var result: [UICollectionViewLayoutAttributes] = []
        let pitch = itemSize.height + spacing
        for (index, section) in sections.enumerated() where section.count > 0 {
            guard visible.maxY > section.y, visible.minY < section.y + section.height else { continue }
            let rows = (section.count + columns - 1) / columns
            let firstRow = max(0, Int(floor((visible.minY - section.y) / pitch)))
            let lastRow = min(rows - 1, Int(floor((visible.maxY - section.y) / pitch)))
            guard firstRow <= lastRow else { continue }
            for item in (firstRow * columns)..<min(section.count, (lastRow + 1) * columns) {
                if let attributes = layoutAttributesForItem(at: IndexPath(item: item, section: index)),
                   attributes.frame.intersects(rect) { result.append(attributes) }
            }
        }
        return result
    }
}
