import UIKit
import Testing
@testable import TelegramSticker

@MainActor
struct StickerGridLayoutTests {
    @Test func oneCollectionRecalculatesFourRowsAcrossHostHeightChanges() throws {
        let source = GridDataSource(counts: [60, 45])
        let layout = StickerGridLayout()
        let grid = UICollectionView(frame: .zero, collectionViewLayout: layout)
        grid.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        grid.dataSource = source
        grid.contentInsetAdjustmentBehavior = .never
        grid.reloadData()
        for height in [218.0, 202.0, 194.0, 182.0, 218.0, 202.0] {
            grid.frame = CGRect(x: 0, y: 0, width: 385, height: height)
            grid.layoutIfNeeded()
            let first = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)))
            let seventh = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 6, section: 0)))
            let eighth = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 7, section: 0)))
            let last = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 27, section: 0)))
            #expect(first.frame.minY == seventh.frame.minY)
            #expect(eighth.frame.minY > first.frame.maxY)
            #expect(abs(last.frame.maxY - height) < 0.001)
            #expect((layout.layoutAttributesForElements(in: grid.bounds) ?? []).count == 28)
            #expect(first.frame.height >= 44)
        }
        let lastA = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 59, section: 0)))
        let firstB = try #require(layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 1)))
        #expect(firstB.frame.minX == 0)
        #expect(abs(firstB.frame.minY - lastA.frame.maxY - 6) < 0.001)
    }

    @Test func narrowShortAndEmptyViewportsRemainValidAndScrollable() throws {
        let source = GridDataSource(counts: [1000, 1000])
        let layout = StickerGridLayout()
        let grid = UICollectionView(frame: CGRect(x: 0, y: 0, width: 320, height: 140), collectionViewLayout: layout)
        grid.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        grid.dataSource = source; grid.reloadData(); grid.layoutIfNeeded()
        let visible = try #require(layout.layoutAttributesForElements(in: grid.bounds))
        #expect(visible.count == 21) // 7 columns, 3 complete rows.
        #expect(visible.allSatisfy { grid.bounds.contains($0.frame) })
        #expect(layout.collectionViewContentSize.height > 140)
        grid.bounds.origin.y = 2000
        let scrolled = try #require(layout.layoutAttributesForElements(in: grid.bounds))
        #expect(!scrolled.isEmpty && scrolled.count <= 30)
        #expect(scrolled.allSatisfy { $0.frame.intersects(grid.bounds) })
        source.counts = [0]
        grid.reloadData(); grid.layoutIfNeeded()
        #expect(layout.collectionViewContentSize.height == 0)
        #expect(layout.layoutAttributesForElements(in: grid.bounds)?.isEmpty == true)
    }
}

@MainActor
private final class GridDataSource: NSObject, UICollectionViewDataSource {
    var counts: [Int]
    init(counts: [Int]) { self.counts = counts }
    func numberOfSections(in collectionView: UICollectionView) -> Int { counts.count }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { counts[section] }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
    }
}
