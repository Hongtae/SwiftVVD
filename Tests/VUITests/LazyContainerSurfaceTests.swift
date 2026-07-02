import XCTest
@testable import VUI

final class LazyContainerSurfaceTests: XCTestCase {
    func testPinnedScrollableViewsExposeExpectedRawValues() {
        XCTAssertEqual(PinnedScrollableViews.sectionHeaders.rawValue, 1)
        XCTAssertEqual(PinnedScrollableViews.sectionFooters.rawValue, 2)
        XCTAssertEqual(PinnedScrollableViews([.sectionHeaders, .sectionFooters]).rawValue, 3)
    }

    func testGridItemSurfaceStoresSizeSpacingAndAlignment() {
        let fixed = GridItem(.fixed(24), spacing: 6, alignment: .topLeading)
        XCTAssertEqual(fixed.size, .fixed(24))
        XCTAssertEqual(fixed.spacing, 6)
        XCTAssertEqual(fixed.alignment, .topLeading)

        let flexible = GridItem()
        XCTAssertEqual(flexible.size, .flexible(minimum: 10, maximum: .infinity))
        XCTAssertNil(flexible.spacing)
        XCTAssertNil(flexible.alignment)
    }

    func testLazyStackInitializersStorePinnedViews() {
        let vStack = LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
            EmptyView()
        }
        XCTAssertEqual(vStack.pinnedViews, [.sectionHeaders])
        XCTAssertEqual(vStack.tree.content.root.pinnedViews, [.sectionHeaders])
        XCTAssertEqual(vStack.tree.content.root.base.alignment, .leading)
        XCTAssertEqual(vStack.tree.content.root.base.spacing, 4)

        let hStack = LazyHStack(alignment: .top, spacing: 5, pinnedViews: [.sectionFooters]) {
            EmptyView()
        }
        XCTAssertEqual(hStack.pinnedViews, [.sectionFooters])
        XCTAssertEqual(hStack.tree.content.root.pinnedViews, [.sectionFooters])
        XCTAssertEqual(hStack.tree.content.root.base.alignment, .top)
        XCTAssertEqual(hStack.tree.content.root.base.spacing, 5)
    }

    func testLazyGridInitializersStorePinnedViews() {
        let columns = [GridItem(.fixed(20), spacing: 3, alignment: .topLeading)]
        let vGrid = LazyVGrid(columns: columns, alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
            EmptyView()
        }
        XCTAssertEqual(vGrid.pinnedViews, [.sectionHeaders])
        XCTAssertEqual(vGrid.tree.content.root.columns, columns)
        XCTAssertEqual(vGrid.tree.content.root.alignment, .leading)
        XCTAssertEqual(vGrid.tree.content.root.spacing, 4)
        XCTAssertEqual(vGrid.tree.content.root.pinnedViews, [.sectionHeaders])

        let rows = [GridItem(.fixed(12), spacing: 2, alignment: .bottomTrailing)]
        let hGrid = LazyHGrid(rows: rows, alignment: .bottom, spacing: 5, pinnedViews: [.sectionFooters]) {
            EmptyView()
        }
        XCTAssertEqual(hGrid.pinnedViews, [.sectionFooters])
        XCTAssertEqual(hGrid.tree.content.root.rows, rows)
        XCTAssertEqual(hGrid.tree.content.root.alignment, .bottom)
        XCTAssertEqual(hGrid.tree.content.root.spacing, 5)
        XCTAssertEqual(hGrid.tree.content.root.pinnedViews, [.sectionFooters])
    }

    func testLazyContainersUseResettableLazyLayoutRootStorage() {
        let vStack = LazyVStack { EmptyView() }
        let hStack = LazyHStack { EmptyView() }
        let vGrid = LazyVGrid(columns: [GridItem(.fixed(8))]) { EmptyView() }
        let hGrid = LazyHGrid(rows: [GridItem(.fixed(8))]) { EmptyView() }

        XCTAssertTrue(type(of: vStack.tree.content.root) == LazyVStackLayout.self)
        XCTAssertTrue(type(of: hStack.tree.content.root) == LazyHStackLayout.self)
        XCTAssertTrue(type(of: vGrid.tree.content.root) == LazyVGridLayout.self)
        XCTAssertTrue(type(of: hGrid.tree.content.root) == LazyHGridLayout.self)
    }
}
