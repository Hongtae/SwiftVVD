import XCTest
@testable import VUI

private func withCurrentTestSubgraph<R>(
    _ host: GraphHost,
    _ body: () throws -> R
) rethrows -> R {
    try host.data.withCurrent {
        try AGSubgraph.withCurrent(host.data.rootSubgraph, body)
    }
}

private struct LazyFixedItemView: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("LazyFixedItemView._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 1, height: 1))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

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

    func testLazyLayoutRoleHierarchyMatchesSampledSurface() {
        let vStackLayout = LazyVStackLayout(
            base: _VStackLayout(alignment: .trailing, spacing: 7),
            pinnedViews: [.sectionHeaders]
        )
        let hStackLayout = LazyHStackLayout(
            base: _HStackLayout(alignment: .bottom, spacing: 9),
            pinnedViews: [.sectionFooters]
        )
        let vGridLayout = LazyVGridLayout(
            columns: [GridItem(.fixed(18), spacing: 2)],
            alignment: .leading,
            spacing: 4,
            pinnedViews: [.sectionHeaders]
        )
        let hGridLayout = LazyHGridLayout(
            rows: [GridItem(.fixed(12), spacing: 3)],
            alignment: .top,
            spacing: 5,
            pinnedViews: [.sectionFooters]
        )

        assertLazyHVStack(vStackLayout, baseType: _VStackLayout.self)
        assertLazyHVStack(hStackLayout, baseType: _HStackLayout.self)
        assertHVGrid(vGridLayout)
        assertHVGrid(hGridLayout)

        XCTAssertEqual(vStackLayout.pinnedViews, [.sectionHeaders])
        XCTAssertEqual(hStackLayout.pinnedViews, [.sectionFooters])
        XCTAssertEqual(vGridLayout.pinnedViews, [.sectionHeaders])
        XCTAssertEqual(hGridLayout.pinnedViews, [.sectionFooters])
        XCTAssertEqual(vGridLayout.columns, [GridItem(.fixed(18), spacing: 2)])
        XCTAssertEqual(hGridLayout.rows, [GridItem(.fixed(12), spacing: 3)])
        XCTAssertEqual(LazyHStackLayout.layoutProperties.axes, .horizontal)
        XCTAssertEqual(LazyVStackLayout.layoutProperties.axes, .vertical)
        XCTAssertEqual(LazyHStackLayout.layoutProperties.multipleViewAxes, .horizontal)
        XCTAssertEqual(LazyVStackLayout.layoutProperties.multipleViewAxes, .vertical)
        XCTAssertEqual(LazyVGridLayout.layoutProperties.axes, .vertical)
        XCTAssertEqual(LazyHGridLayout.layoutProperties.axes, .horizontal)
        XCTAssertEqual(
            LazyVGridLayout.layoutProperties.multipleViewAxes,
            [.horizontal, .vertical]
        )
        XCTAssertEqual(
            LazyHGridLayout.layoutProperties.multipleViewAxes,
            [.horizontal, .vertical]
        )
        XCTAssertEqual(vGridLayout.headerAnchor, .leading)
        XCTAssertEqual(vGridLayout.footerAnchor, .leading)
        XCTAssertEqual(hGridLayout.headerAnchor, .top)
        XCTAssertEqual(hGridLayout.footerAnchor, .top)
        XCTAssertTrue(LazyVStackLayout.AnimatableData.self == EmptyAnimatableData.self)
        XCTAssertTrue(LazyHStackLayout.AnimatableData.self == EmptyAnimatableData.self)
        XCTAssertTrue(LazyVGridLayout.AnimatableData.self == EmptyAnimatableData.self)
        XCTAssertTrue(LazyHGridLayout.AnimatableData.self == EmptyAnimatableData.self)
    }

    func testLazyStackWitnessSurfaceExposesMinorGeometryRoutes() {
        let vStackLayout = LazyVStackLayout(
            base: _VStackLayout(alignment: .leading, spacing: 7),
            pinnedViews: [.sectionHeaders]
        )
        let hStackLayout = LazyHStackLayout(
            base: _HStackLayout(alignment: .bottom, spacing: 9),
            pinnedViews: [.sectionFooters]
        )
        let vGridLayout = LazyVGridLayout(
            columns: [GridItem(.fixed(18), spacing: 2)],
            alignment: .leading,
            spacing: 4,
            pinnedViews: [.sectionHeaders]
        )
        let hGridLayout = LazyHGridLayout(
            rows: [GridItem(.fixed(12), spacing: 3)],
            alignment: .top,
            spacing: 5,
            pinnedViews: [.sectionFooters]
        )

        XCTAssertTrue(LazyVStackLayout.MinorGeometry.self == CGFloat.self)
        XCTAssertTrue(LazyHStackLayout.MinorGeometry.self == CGFloat.self)
        XCTAssertTrue(LazyVGridLayout.MinorGeometry.self == [HVGridGeometry].self)
        XCTAssertTrue(LazyHGridLayout.MinorGeometry.self == [HVGridGeometry].self)

        assertLazyStackWitnessSurface(vStackLayout)
        assertLazyStackWitnessSurface(hStackLayout)
        assertLazyStackWitnessSurface(vGridLayout)
        assertLazyStackWitnessSurface(hGridLayout)

        let geometry = HVGridGeometry(position: 3, size: 5, anchor: .bottomTrailing)
        XCTAssertEqual(geometry.position, 3)
        XCTAssertEqual(geometry.size, 5)
        XCTAssertEqual(geometry.anchor, .bottomTrailing)
        XCTAssertEqual(geometry, HVGridGeometry(position: 3, size: 5, anchor: .bottomTrailing))

        XCTAssertEqual(LazyVStackLayout.majorAxis, .vertical)
        XCTAssertEqual(LazyHStackLayout.majorAxis, .horizontal)
        XCTAssertEqual(LazyVGridLayout.majorAxis, .vertical)
        XCTAssertEqual(LazyHGridLayout.majorAxis, .horizontal)
        XCTAssertEqual(vGridLayout.minorAxisAnchor, 0)
        XCTAssertEqual(hGridLayout.minorAxisAnchor, 0)
        XCTAssertEqual(
            LazyVGridLayout(
                columns: [GridItem(.fixed(18))],
                alignment: .center,
                spacing: nil,
                pinnedViews: []
            ).minorAxisAnchor,
            0.5
        )
        XCTAssertEqual(
            LazyVGridLayout(
                columns: [GridItem(.fixed(18))],
                alignment: .trailing,
                spacing: nil,
                pinnedViews: []
            ).minorAxisAnchor,
            1
        )
        XCTAssertEqual(
            LazyHGridLayout(
                rows: [GridItem(.fixed(12))],
                alignment: .bottom,
                spacing: nil,
                pinnedViews: []
            ).minorAxisAnchor,
            1
        )
        XCTAssertEqual(
            LazyHGridLayout(
                rows: [GridItem(.fixed(12))],
                alignment: .firstTextBaseline,
                spacing: nil,
                pinnedViews: []
            ).minorAxisAnchor,
            1
        )
    }

    func testLazyHVStackUsesAlignmentAnchorAndEmitsOnlyFirstMinorGroupSubview() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 0)
            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let first = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(
                    graph: graph,
                    id: _ViewList_ID(implicitID: 0)
                ),
                index: 0
            )
            let second = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(
                    graph: graph,
                    id: _ViewList_ID(implicitID: 1)
                ),
                index: 1
            )

            let horizontal = LazyHStackLayout(
                base: _HStackLayout(alignment: .bottom, spacing: 7),
                pinnedViews: []
            )
            XCTAssertEqual(horizontal.headerAnchor, .bottom)
            XCTAssertEqual(horizontal.footerAnchor, .bottom)

            var horizontalEmissions: [
                (index: Int, point: CGPoint, proposal: _ProposedSize, anchor: UnitPoint)
            ] = []
            horizontal.place(
                subviews: [first, second],
                length: 1,
                minorGeometry: 33
            ) { subview, point, proposal, anchor in
                horizontalEmissions.append(
                    (subview.index, point, proposal, anchor)
                )
            }

            XCTAssertEqual(horizontalEmissions.count, 1)
            XCTAssertEqual(horizontalEmissions[0].index, 0)
            XCTAssertEqual(horizontalEmissions[0].point, .zero)
            XCTAssertEqual(
                horizontalEmissions[0].proposal,
                _ProposedSize(width: nil, height: 33)
            )
            XCTAssertEqual(horizontalEmissions[0].anchor, .bottom)

            let vertical = LazyVStackLayout(
                base: _VStackLayout(alignment: .trailing, spacing: 9),
                pinnedViews: []
            )
            XCTAssertEqual(vertical.headerAnchor, .trailing)
            XCTAssertEqual(vertical.footerAnchor, .trailing)

            var verticalEmissions: [
                (index: Int, point: CGPoint, proposal: _ProposedSize, anchor: UnitPoint)
            ] = []
            vertical.place(
                subviews: [first, second],
                length: 1,
                minorGeometry: 44
            ) { subview, point, proposal, anchor in
                verticalEmissions.append(
                    (subview.index, point, proposal, anchor)
                )
            }

            XCTAssertEqual(verticalEmissions.count, 1)
            XCTAssertEqual(verticalEmissions[0].index, 0)
            XCTAssertEqual(verticalEmissions[0].point, .zero)
            XCTAssertEqual(
                verticalEmissions[0].proposal,
                _ProposedSize(width: 44, height: nil)
            )
            XCTAssertEqual(verticalEmissions[0].anchor, .trailing)
        }
    }

    func testLazyHVStackFlexibleMinorSizeReadsOnlyFirstSubviewIdealCrossAxis() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 11, height: 12),
                CGSize(width: 21, height: 22),
                CGSize(width: 31, height: 32),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(
                    graph: graph,
                    sizes: sizes
                )
            )
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let subviews = cache.subviews(context: context)
            let horizontal = LazyHStackLayout(
                base: _HStackLayout(),
                pinnedViews: []
            )

            XCTAssertEqual(
                horizontal.flexibleMinorSize(subviews: subviews),
                sizes[0].height
            )
            XCTAssertEqual(cache.items.count, 1)
            XCTAssertNotNil(
                cache.items[
                    _ViewList_ID(implicitID: 0).canonicalID
                ]
            )

            cache.items.removeAll()
            cache.lru.invalidate()

            let vertical = LazyVStackLayout(
                base: _VStackLayout(),
                pinnedViews: []
            )
            XCTAssertEqual(
                vertical.flexibleMinorSize(subviews: subviews),
                sizes[0].width
            )
            XCTAssertEqual(cache.items.count, 1)

            let empty = makeLazyCache(
                host: host,
                implicitID: 100,
                list: EmptyViewList()
            ).cache
            empty.items.removeAll()
            empty.lru.invalidate()
            XCTAssertEqual(
                vertical.flexibleMinorSize(
                    subviews: empty.subviews(context: context)
                ),
                0
            )
            XCTAssertTrue(empty.items.isEmpty)
        }
    }

    func testLazyStackSizeThatFitsUsesTwoGroupEstimateWithoutEagerMaterialization() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 12, height: 10),
                CGSize(width: 18, height: 20),
                CGSize(width: 99, height: 30),
                CGSize(width: 99, height: 40),
                CGSize(width: 99, height: 50),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(
                    graph: graph,
                    sizes: sizes
                )
            )
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let sizeContext = _LazyLayout_SizeAndSpacingContext(
                ruleContext: context,
                environment: graph.makeInput(value: EnvironmentValues()),
                containerSize: OptionalAttribute(
                    graph.makeInput(
                        value: ViewSize(width: 25, height: 100)
                    )
                )
            )
            let subviews = cache.subviews(context: context)
            let vertical = LazyVStackLayout(
                base: _VStackLayout(spacing: 4),
                pinnedViews: []
            )

            let measured = vertical.sizeThatFits(
                proposedSize: ProposedViewSize(width: 25, height: 400),
                subviews: subviews,
                context: sizeContext,
                cache: _LazyStack_Cache<LazyVStackLayout>()
            )

            // The first two rows contribute 10 + (20 + 4). The remaining
            // three rows use the sampled 15-point length and 4-point spacing.
            XCTAssertEqual(measured, CGSize(width: 25, height: 91))
            XCTAssertEqual(cache.items.count, 2)
            XCTAssertNotNil(
                cache.items[
                    _ViewList_ID(implicitID: 0)
                        .elementID(at: 0)
                        .canonicalID
                ]
            )
            XCTAssertNotNil(
                cache.items[
                    _ViewList_ID(implicitID: 0)
                        .elementID(at: 1)
                        .canonicalID
                ]
            )
            XCTAssertNil(
                cache.items[
                    _ViewList_ID(implicitID: 0)
                        .elementID(at: 2)
                        .canonicalID
                ]
            )

            cache.items.removeAll()
            cache.lru.invalidate()
            let retainedEstimate = vertical.sizeThatFits(
                proposedSize: ProposedViewSize(width: 25, height: 400),
                subviews: subviews,
                context: sizeContext,
                cache: _LazyStack_Cache<LazyVStackLayout>(
                    containerLength: 100,
                    estimations: EstimationCache(
                        lengthToCount: [100: 1],
                        spacingToCount: [4: 1]
                    )
                )
            )
            XCTAssertEqual(
                retainedEstimate,
                CGSize(width: 25, height: 516)
            )
            XCTAssertTrue(cache.items.isEmpty)

            let resetEstimate = vertical.sizeThatFits(
                proposedSize: ProposedViewSize(width: 25, height: 400),
                subviews: subviews,
                context: sizeContext,
                cache: _LazyStack_Cache<LazyVStackLayout>(
                    containerLength: 90,
                    estimations: EstimationCache(
                        lengthToCount: [100: 1],
                        spacingToCount: [4: 1]
                    )
                )
            )
            XCTAssertEqual(resetEstimate, CGSize(width: 25, height: 91))
            XCTAssertEqual(cache.items.count, 2)
        }
    }

    func testHVGridMinorGeometryExpandsGridItemsIntoTrackGeometry() {
        let layout = LazyVGridLayout(
            columns: [
                GridItem(.fixed(20), spacing: 4, alignment: .topLeading),
                GridItem(.flexible(minimum: 10, maximum: 40), spacing: 6, alignment: .bottomTrailing),
                GridItem(.adaptive(minimum: 12, maximum: 18), alignment: .trailing),
            ],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )

        var size = CGFloat(100)
        let geometry = layout.minorGeometry(updatingSize: &size)

        XCTAssertEqual(size, 100)
        XCTAssertEqual(geometry.count, 4)
        XCTAssertEqual(
            geometry.data,
            [
                HVGridGeometry(position: 0, size: 20, anchor: .topLeading),
                HVGridGeometry(position: 24, size: 35, anchor: .bottomTrailing),
                HVGridGeometry(position: 65, size: 13.5, anchor: .trailing),
                HVGridGeometry(position: 86.5, size: 13.5, anchor: .trailing),
            ]
        )

        let hLayout = LazyHGridLayout(
            rows: [GridItem(.fixed(14), alignment: .bottom)],
            alignment: .top,
            spacing: nil,
            pinnedViews: []
        )
        var hSize = CGFloat(14)
        XCTAssertEqual(
            hLayout.minorGeometry(updatingSize: &hSize).data,
            [HVGridGeometry(position: 0, size: 14, anchor: .bottom)]
        )
    }

    func testHVGridMinorGeometryPreservesRawValuesAndFullAlignment() {
        let layout = LazyVGridLayout(
            columns: [
                GridItem(.fixed(-5), spacing: -3, alignment: .topTrailing),
                GridItem(.fixed(10), alignment: .bottomLeading),
            ],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )

        var size = CGFloat(20)
        let geometry = layout.minorGeometry(updatingSize: &size)

        XCTAssertEqual(size, 20)
        XCTAssertEqual(
            geometry.data,
            [
                HVGridGeometry(position: 0, size: -5, anchor: .topTrailing),
                HVGridGeometry(position: -8, size: 10, anchor: .bottomLeading),
            ]
        )

        let adaptive = LazyVGridLayout(
            columns: [
                GridItem(
                    .adaptive(minimum: 10, maximum: -2),
                    spacing: 8
                ),
            ],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )
        var adaptiveSize = CGFloat(30)
        XCTAssertEqual(
            adaptive.minorGeometry(updatingSize: &adaptiveSize).data,
            [
                HVGridGeometry(position: 0, size: -2, anchor: .leading),
                HVGridGeometry(position: 6, size: -2, anchor: .leading),
            ]
        )
        XCTAssertEqual(adaptiveSize, 30)
    }

    func testHVGridMinorGeometryRejectsEmptyAndNonfiniteInputsWithoutMutation() {
        let empty = LazyVGridLayout(
            columns: [],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )
        var emptySize = CGFloat(17)
        let emptyGeometry = empty.minorGeometry(updatingSize: &emptySize)
        XCTAssertEqual(emptyGeometry.count, 0)
        XCTAssertTrue(emptyGeometry.data.isEmpty)
        XCTAssertEqual(emptySize, 17)

        let nonempty = LazyVGridLayout(
            columns: [GridItem(.fixed(10))],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )
        var infiniteSize = CGFloat.infinity
        let infiniteGeometry = nonempty.minorGeometry(updatingSize: &infiniteSize)
        XCTAssertEqual(infiniteGeometry.count, 0)
        XCTAssertTrue(infiniteGeometry.data.isEmpty)
        XCTAssertEqual(infiniteSize, .infinity)
    }

    func testHVGridMinorGeometryAlignsTracksInsideRequestedMinorSize() {
        let layout = LazyVGridLayout(
            columns: [
                GridItem(.fixed(10), spacing: 5),
                GridItem(.fixed(15)),
            ],
            alignment: .center,
            spacing: nil,
            pinnedViews: []
        )

        var size = CGFloat(40)
        let geometry = layout.minorGeometry(updatingSize: &size)

        XCTAssertEqual(size, 40)
        XCTAssertEqual(
            geometry.data,
            [
                HVGridGeometry(position: 5, size: 10, anchor: .center),
                HVGridGeometry(position: 20, size: 15, anchor: .center),
            ]
        )
    }

    func testHVGridNilGridItemSpacingDefaultsToEight() {
        let vLayout = LazyVGridLayout(
            columns: [
                GridItem(.fixed(10)),
                GridItem(.fixed(10)),
            ],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )
        var vSize = CGFloat(28)
        XCTAssertEqual(
            vLayout.minorGeometry(updatingSize: &vSize).data,
            [
                HVGridGeometry(position: 0, size: 10, anchor: .leading),
                HVGridGeometry(position: 18, size: 10, anchor: .leading),
            ]
        )
        XCTAssertEqual(vSize, 28)

        let adaptiveLayout = LazyVGridLayout(
            columns: [
                GridItem(.adaptive(minimum: 10, maximum: 10)),
            ],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )
        var adaptiveSize = CGFloat(46)
        XCTAssertEqual(
            adaptiveLayout.minorGeometry(updatingSize: &adaptiveSize).data,
            [
                HVGridGeometry(position: 0, size: 10, anchor: .leading),
                HVGridGeometry(position: 18, size: 10, anchor: .leading),
                HVGridGeometry(position: 36, size: 10, anchor: .leading),
            ]
        )
        XCTAssertEqual(adaptiveSize, 46)

        let explicitZeroLayout = LazyVGridLayout(
            columns: [
                GridItem(.fixed(10), spacing: 0),
                GridItem(.fixed(10)),
            ],
            alignment: .leading,
            spacing: nil,
            pinnedViews: []
        )
        var explicitZeroSize = CGFloat(20)
        XCTAssertEqual(
            explicitZeroLayout.minorGeometry(updatingSize: &explicitZeroSize).data,
            [
                HVGridGeometry(position: 0, size: 10, anchor: .leading),
                HVGridGeometry(position: 10, size: 10, anchor: .leading),
            ]
        )
        XCTAssertEqual(explicitZeroSize, 20)

        let hLayout = LazyHGridLayout(
            rows: [
                GridItem(.fixed(10)),
                GridItem(.fixed(10)),
            ],
            alignment: .top,
            spacing: nil,
            pinnedViews: []
        )
        var hSize = CGFloat(28)
        XCTAssertEqual(
            hLayout.minorGeometry(updatingSize: &hSize).data,
            [
                HVGridGeometry(position: 0, size: 10, anchor: .top),
                HVGridGeometry(position: 18, size: 10, anchor: .top),
            ]
        )
        XCTAssertEqual(hSize, 28)
    }

    func testHVGridFlexibleMinorSizeMeasuresOneIdealSubviewPerDeclaredTrack() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 11, height: 12),
                CGSize(width: 21, height: 22),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(
                    graph: graph,
                    sizes: sizes
                )
            )
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let subviews = cache.subviews(context: context)
            let horizontal = LazyHGridLayout(
                rows: [
                    GridItem(.fixed(1), spacing: 4),
                    GridItem(.flexible(minimum: 1, maximum: 2)),
                    GridItem(.adaptive(minimum: 1, maximum: 3)),
                ],
                alignment: .top,
                spacing: nil,
                pinnedViews: []
            )
            XCTAssertEqual(
                horizontal.flexibleMinorSize(subviews: subviews),
                12 + 4 + 22 + Spacing.defaultValue.width
            )
            XCTAssertEqual(cache.items.count, 2)

            cache.items.removeAll()
            cache.lru.invalidate()

            let vertical = LazyVGridLayout(
                columns: [
                    GridItem(.fixed(1), spacing: 3),
                    GridItem(.flexible(minimum: 1, maximum: 2)),
                ],
                alignment: .leading,
                spacing: nil,
                pinnedViews: []
            )
            XCTAssertEqual(
                vertical.flexibleMinorSize(subviews: subviews),
                11 + 3 + 21
            )
            XCTAssertEqual(cache.items.count, 2)

            cache.items.removeAll()
            cache.lru.invalidate()

            let noTracks = LazyHGridLayout(
                rows: [],
                alignment: .top,
                spacing: nil,
                pinnedViews: []
            )
            XCTAssertEqual(
                noTracks.flexibleMinorSize(subviews: subviews),
                0
            )
            XCTAssertTrue(cache.items.isEmpty)
        }
    }

    func testHVGridLengthAndPlacementUseMinorGeometryTracks() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstItem, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, secondItem, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            firstItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        XCTAssertEqual(proposal.width, 30)
                        XCTAssertNil(proposal.height)
                        return CGSize(width: proposal.width ?? 0, height: 40)
                    }
                )))
            )
            secondItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        XCTAssertEqual(proposal.width, 50)
                        XCTAssertNil(proposal.height)
                        return CGSize(width: proposal.width ?? 0, height: 55)
                    }
                )))
            )

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = [
                _LazyLayout_Subview(
                    cache: cache,
                    context: context,
                    data: makeLazyData(graph: graph, id: _ViewList_ID(implicitID: 1)),
                    index: 0
                ),
                _LazyLayout_Subview(
                    cache: cache,
                    context: context,
                    data: makeLazyData(graph: graph, id: _ViewList_ID(implicitID: 2)),
                    index: 1
                ),
            ]
            let minorGeometry = [
                HVGridGeometry(position: 0, size: 30, anchor: .leading),
                HVGridGeometry(position: 30, size: 50, anchor: .trailing),
            ]
            let layout = LazyVGridLayout(
                columns: [GridItem(.fixed(30)), GridItem(.fixed(50))],
                alignment: .leading,
                spacing: 7,
                pinnedViews: []
            )

            let measured = layout.lengthAndSpacing(
                subviews: subviews,
                predecessors: subviews,
                minorGeometry: minorGeometry
            )
            XCTAssertEqual(measured.length, 55)
            XCTAssertEqual(measured.spacing, 7)

            var placements: [(_LazyLayout_Subview, CGPoint, _ProposedSize, UnitPoint)] = []
            layout.place(
                subviews: subviews,
                length: 80,
                minorGeometry: minorGeometry
            ) { subview, point, proposal, anchor in
                placements.append((subview, point, proposal, anchor))
            }

            XCTAssertEqual(placements.map(\.0.index), [0, 1])
            XCTAssertEqual(placements.map(\.1), [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0)])
            XCTAssertEqual(
                placements.map(\.2),
                [_ProposedSize(width: 30, height: 80), _ProposedSize(width: 50, height: 80)]
            )
            XCTAssertEqual(placements.map(\.3), [.leading, .trailing])

            let hLayout = LazyHGridLayout(
                rows: [GridItem(.fixed(30))],
                alignment: .top,
                spacing: nil,
                pinnedViews: []
            )
            var hPlacements: [(_LazyLayout_Subview, CGPoint, _ProposedSize, UnitPoint)] = []
            hLayout.place(
                subviews: [subviews[0]],
                length: 70,
                minorGeometry: [HVGridGeometry(position: 12, size: 30, anchor: .top)]
            ) { subview, point, proposal, anchor in
                hPlacements.append((subview, point, proposal, anchor))
            }

            XCTAssertEqual(hPlacements.map(\.0.index), [0])
            XCTAssertEqual(hPlacements.map(\.1), [CGPoint(x: 0, y: 12)])
            XCTAssertEqual(hPlacements.map(\.2), [_ProposedSize(width: 70, height: 30)])
            XCTAssertEqual(hPlacements.map(\.3), [.top])
        }
    }

    func testLazyGridSectionBoundariesUseFullMinorSpanPlacement() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph

            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            let header = makeRegion([CGSize(width: 120, height: 30)])
            let content = makeRegion(Array(repeating: CGSize(width: 60, height: 50), count: 4))
            let footer = makeRegion([CGSize(width: 120, height: 24)])
            let list: any ViewList = _ViewList_Section(
                id: 9,
                base: _ViewList_Group(lists: [header, content, footer])
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVGridLayout(
                columns: [
                    GridItem(.fixed(60), spacing: 0),
                    GridItem(.fixed(60), spacing: 0),
                ],
                alignment: .leading,
                spacing: 0,
                pinnedViews: []
            )
            var minorSize = CGFloat(120)
            let minorGeometry = layout.minorGeometry(updatingSize: &minorSize)
            var stackCache = _LazyStack_Cache<LazyVGridLayout>()

            let placements = stackCache.place(
                stack: layout,
                subviews: subviews,
                from: 0,
                position: 0,
                visible: CGFloat(0)..<CGFloat(200),
                visibleLength: 100,
                containerLength: 200,
                minor: MinorProperties(
                    count: minorGeometry.count,
                    size: minorSize,
                    geometry: minorGeometry.data
                )
            )

            let placedByIndex = Dictionary(uniqueKeysWithValues: placements.subviews.map { ($0.index, $0) })
            let placedHeader = try XCTUnwrap(placedByIndex[0])
            let firstBody = try XCTUnwrap(placedByIndex[1])
            let secondBody = try XCTUnwrap(placedByIndex[2])
            let thirdBody = try XCTUnwrap(placedByIndex[3])
            let fourthBody = try XCTUnwrap(placedByIndex[4])
            let placedFooter = try XCTUnwrap(placedByIndex[5])

            XCTAssertEqual(placements.subviews.map(\.index), [0, 1, 2, 3, 4, 5])
            XCTAssertEqual(placedHeader.placement.anchorPosition, .zero)
            XCTAssertEqual(placedHeader.placement.anchor, .topLeading)
            XCTAssertEqual(placedHeader.placement.proposedSize.width, 120)
            XCTAssertEqual(placedHeader.frame, CGRect(x: 0, y: 0, width: 120, height: 30))

            XCTAssertEqual(firstBody.placement.anchorPosition, CGPoint(x: 0, y: 30))
            XCTAssertEqual(secondBody.placement.anchorPosition, CGPoint(x: 60, y: 30))
            XCTAssertEqual(thirdBody.placement.anchorPosition, CGPoint(x: 0, y: 80))
            XCTAssertEqual(fourthBody.placement.anchorPosition, CGPoint(x: 60, y: 80))
            XCTAssertEqual(placedFooter.placement.anchorPosition, CGPoint(x: 0, y: 130))
            XCTAssertEqual(placedFooter.placement.anchor, .topLeading)
            XCTAssertEqual(placedFooter.placement.proposedSize.width, 120)
            XCTAssertEqual(placedFooter.frame, CGRect(x: 0, y: 130, width: 120, height: 24))
            XCTAssertEqual(stackCache.placedIndices, 0..<6)
            XCTAssertEqual(stackCache.placedExtent, CGFloat(0)..<CGFloat(154))

            let horizontalHeader = makeRegion([CGSize(width: 30, height: 120)])
            let horizontalContent = makeRegion(Array(repeating: CGSize(width: 50, height: 60), count: 4))
            let horizontalFooter = makeRegion([CGSize(width: 24, height: 120)])
            let horizontalList: any ViewList = _ViewList_Section(
                id: 10,
                base: _ViewList_Group(lists: [horizontalHeader, horizontalContent, horizontalFooter])
            )
            let (horizontalCache, _, _) = makeLazyCache(host: host, implicitID: 199, list: horizontalList)
            horizontalCache.items.removeAll()
            horizontalCache.lru.invalidate()

            let horizontalSubviews = horizontalCache.subviews(context: context)
            let horizontalLayout = LazyHGridLayout(
                rows: [
                    GridItem(.fixed(60), spacing: 0),
                    GridItem(.fixed(60), spacing: 0),
                ],
                alignment: .top,
                spacing: 0,
                pinnedViews: []
            )
            var horizontalMinorSize = CGFloat(120)
            let horizontalMinorGeometry = horizontalLayout.minorGeometry(updatingSize: &horizontalMinorSize)
            var horizontalStackCache = _LazyStack_Cache<LazyHGridLayout>()

            let horizontalPlacements = horizontalStackCache.place(
                stack: horizontalLayout,
                subviews: horizontalSubviews,
                from: 0,
                position: 0,
                visible: CGFloat(0)..<CGFloat(200),
                visibleLength: 100,
                containerLength: 200,
                minor: MinorProperties(
                    count: horizontalMinorGeometry.count,
                    size: horizontalMinorSize,
                    geometry: horizontalMinorGeometry.data
                )
            )

            let horizontalByIndex = Dictionary(uniqueKeysWithValues: horizontalPlacements.subviews.map { ($0.index, $0) })
            let placedHorizontalHeader = try XCTUnwrap(horizontalByIndex[0])
            let firstHorizontalBody = try XCTUnwrap(horizontalByIndex[1])
            let secondHorizontalBody = try XCTUnwrap(horizontalByIndex[2])
            let thirdHorizontalBody = try XCTUnwrap(horizontalByIndex[3])
            let fourthHorizontalBody = try XCTUnwrap(horizontalByIndex[4])
            let placedHorizontalFooter = try XCTUnwrap(horizontalByIndex[5])

            XCTAssertEqual(horizontalPlacements.subviews.map(\.index), [0, 1, 2, 3, 4, 5])
            XCTAssertEqual(placedHorizontalHeader.placement.anchorPosition, .zero)
            XCTAssertEqual(placedHorizontalHeader.placement.anchor, .topLeading)
            XCTAssertEqual(placedHorizontalHeader.placement.proposedSize.height, 120)
            XCTAssertEqual(placedHorizontalHeader.frame, CGRect(x: 0, y: 0, width: 30, height: 120))

            XCTAssertEqual(firstHorizontalBody.placement.anchorPosition, CGPoint(x: 30, y: 0))
            XCTAssertEqual(secondHorizontalBody.placement.anchorPosition, CGPoint(x: 30, y: 60))
            XCTAssertEqual(thirdHorizontalBody.placement.anchorPosition, CGPoint(x: 80, y: 0))
            XCTAssertEqual(fourthHorizontalBody.placement.anchorPosition, CGPoint(x: 80, y: 60))
            XCTAssertEqual(placedHorizontalFooter.placement.anchorPosition, CGPoint(x: 130, y: 0))
            XCTAssertEqual(placedHorizontalFooter.placement.anchor, .topLeading)
            XCTAssertEqual(placedHorizontalFooter.placement.proposedSize.height, 120)
            XCTAssertEqual(placedHorizontalFooter.frame, CGRect(x: 130, y: 0, width: 24, height: 120))
            XCTAssertEqual(horizontalStackCache.placedIndices, 0..<6)
            XCTAssertEqual(horizontalStackCache.placedExtent, CGFloat(0)..<CGFloat(154))
        }
    }

    func testLazyLayoutPrefetchResultAdvanceToSomeMatchesSampledSurface() {
        XCTAssertEqual(_LazyLayout_PrefetchResult.none.rawValue, 0)
        XCTAssertEqual(_LazyLayout_PrefetchResult.some.rawValue, 1)
        XCTAssertEqual(_LazyLayout_PrefetchResult.all.rawValue, 2)

        var none = _LazyLayout_PrefetchResult.none
        XCTAssertFalse(none.advanceToSome())
        XCTAssertEqual(none, .some)

        var some = _LazyLayout_PrefetchResult.some
        XCTAssertTrue(some.advanceToSome())
        XCTAssertEqual(some, .some)

        var all = _LazyLayout_PrefetchResult.all
        XCTAssertTrue(all.advanceToSome())
        XCTAssertEqual(all, .all)
    }

    func testScrollPrefetchStateStorageAndCommitMatchesSampledSurface() {
        let first = ScrollPrefetchState(deadline: 11)
        let second = ScrollPrefetchState(deadline: 12)
        XCTAssertEqual(first.deadline, 11)
        XCTAssertEqual(first.edges, [])
        XCTAssertNotEqual(first.id, second.id)

        var propertyList = PropertyList()
        XCTAssertNil(propertyList[ScrollPrefetchState.self].attribute)

        let host = GraphHost()
        host.data.withCurrent {
            let graph = host.data.graph
            let stateAttribute = graph.makeInput(value: first)
            propertyList[ScrollPrefetchState.self] = OptionalAttribute(stateAttribute)
            XCTAssertEqual(
                propertyList[ScrollPrefetchState.self].attribute?.identifier,
                stateAttribute.identifier
            )

            var committed = ScrollPrefetchState(deadline: 77)
            committed.edges = .vertical
            Update.begin()
            committed.commit(to: stateAttribute.asWeak())
            XCTAssertEqual(Update.queuedActionReasons, [.scrollPrefetch])
            XCTAssertEqual(stateAttribute.value.id, first.id)
            Update.end()

            let current = stateAttribute.value
            XCTAssertEqual(current.id, committed.id)
            XCTAssertEqual(current.deadline, 77)
            XCTAssertEqual(current.edges, .vertical)
            XCTAssertFalse(host.hasPendingTransactions)
        }
    }

    func testLazyLayoutPrivateCarrierStorageMatchesFieldMetadataSlice() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, item, _) = makeLazyCache(host: host)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let transform = _ViewList_SublistTransform()
            let cacheSection = LazyLayoutCacheSection(id: 4, isHeader: true)

            let properties = _LazyLayout_Properties(
                axes: [.vertical],
                multipleViewAxes: [.horizontal]
            )
            XCTAssertEqual(properties.axes, [.vertical])
            XCTAssertEqual(properties.multipleViewAxes, [.horizontal])

            let environment = graph.makeInput(value: EnvironmentValues())
            let containerSize = graph.makeInput(
                value: ViewSize(CGSize(width: 31, height: 37))
            )
            var sizeContext = _LazyLayout_SizeAndSpacingContext(
                ruleContext: context,
                owner: context.attribute,
                environment: environment,
                containerSize: OptionalAttribute(containerSize)
            )
            XCTAssertEqual(sizeContext.ruleContext, context)
            XCTAssertEqual(sizeContext.baseContext.owner, context.attribute)
            XCTAssertEqual(sizeContext.containerSize, CGSize(width: 31, height: 37))

            let replacementContext = AnyRuleContext(
                attribute: graph.makeInput(value: "replacement").identifier
            )
            sizeContext.update(replacementContext)
            XCTAssertEqual(sizeContext.ruleContext, replacementContext)

            let placementContext = _LazyLayout_PlacementContext(
                base: sizeContext,
                position: CGPoint(x: 7, y: 11),
                size: ViewSize(CGSize(width: 13, height: 17)),
                transform: ViewTransform(),
                layoutDirection: .rightToLeft,
                pinnedViews: [.sectionHeaders],
                isAccessibilityEnabled: true
            )
            XCTAssertEqual(placementContext.base.ruleContext, replacementContext)
            XCTAssertEqual(placementContext.position, CGPoint(x: 7, y: 11))
            XCTAssertEqual(placementContext.size, CGSize(width: 13, height: 17))
            XCTAssertEqual(placementContext.pinnedViews, [.sectionHeaders])
            XCTAssertEqual(placementContext.geometry.viewSize, CGSize(width: 13, height: 17))
            XCTAssertTrue(placementContext.geometry.isAccessibilityEnabled)
            XCTAssertEqual(placementContext.containerSize, CGSize(width: 31, height: 37))
            XCTAssertEqual(placementContext.contentInsets, EdgeInsets())
            XCTAssertEqual(placementContext.containingScrollGeometry.contentOffset, .zero)
            XCTAssertEqual(
                placementContext.containingScrollGeometry.contentSize,
                CGSize(width: 13, height: 17)
            )
            XCTAssertEqual(
                placementContext.containingScrollGeometry.containerSize,
                CGSize(width: 13, height: 17)
            )
            XCTAssertEqual(
                placementContext.nearestScrollGeometry,
                placementContext.containingScrollGeometry
            )
            XCTAssertEqual(
                placementContext.nearestVisibleRect,
                CGRect(x: 0, y: 0, width: 13, height: 17)
            )
            XCTAssertEqual(
                placementContext.unadjustedVisibleRect,
                CGRect(x: 0, y: 0, width: 13, height: 17)
            )
            XCTAssertEqual(
                placementContext.containingVisibleRect,
                CGRect(x: 0, y: 0, width: 13, height: 17)
            )
            XCTAssertEqual(
                placementContext.clampedVisibleRect,
                CGRect(x: 0, y: 0, width: 13, height: 17)
            )
            XCTAssertFalse(placementContext.allowsTranslations)

            let estimatedContext = _LazyLayout_EstimatedPlacementContext(
                base: placementContext
            )
            XCTAssertEqual(estimatedContext.base.position, CGPoint(x: 7, y: 11))

            let section = _LazyLayout_Section(
                base: _ViewList_Section(),
                transform: transform,
                cache: cache,
                context: context,
                baseIndex: 7
            )
            XCTAssertTrue(section.cache === cache)
            XCTAssertEqual(section.baseIndex, 7)
            XCTAssertEqual(_LazyLayout_Section.ID(id: 11), _LazyLayout_Section.ID(id: 11))

            let subviews = _LazyLayout_Subviews(
                cache: cache,
                context: context,
                node: .list(EmptyViewList() as any ViewList, nil),
                transform: transform,
                section: cacheSection,
                baseIndex: 3
            )
            XCTAssertTrue(subviews.cache === cache)
            XCTAssertEqual(subviews.section, cacheSection)
            XCTAssertEqual(subviews.baseIndex, 3)

            let sectionNode = _LazyLayout_Subviews.Node.section(section)
            if case let .section(storedSection) = sectionNode {
                XCTAssertTrue(storedSection.cache === cache)
                XCTAssertEqual(storedSection.baseIndex, 7)
            } else {
                XCTFail("Expected section node")
            }

            let subviewsNode = _LazyLayout_Subviews.Node.subviews(subviews)
            if case let .subviews(storedSubviews) = subviewsNode {
                XCTAssertTrue(storedSubviews.cache === cache)
                XCTAssertEqual(storedSubviews.baseIndex, 3)
            } else {
                XCTFail("Expected subviews node")
            }

            let lazySubview = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(graph: graph, id: _ViewList_ID(implicitID: 64)),
                index: 8
            )
            let placedSubview = _LazyLayout_PlacedSubview(
                item: item,
                placement: _Placement(proposedSize: CGSize(width: 12, height: 16)),
                index: 5
            )
            let placements = _LazyLayout_Placements(
                subviews: [placedSubview],
                validRect: CGRect(x: 1, y: 2, width: 3, height: 4),
                invalidSize: true,
                translation: CGSize(width: 9, height: 10),
                wasCancelled: true
            )
            XCTAssertTrue(placements.subviews[0].item === item)
            XCTAssertEqual(placements.validRect, CGRect(x: 1, y: 2, width: 3, height: 4))
            XCTAssertTrue(placements.invalidSize)
            XCTAssertEqual(placements.translation, CGSize(width: 9, height: 10))
            XCTAssertTrue(placements.wasCancelled)

            let estimated = _LazyLayout_EstimatedPlacements(index: 5, subviews: [placedSubview])
            XCTAssertEqual(estimated.index, 5)
            XCTAssertTrue(estimated.subviews[0].item === item)

            let proposedSubview = _LazyLayout_ProposedSubview(
                item: item,
                proposal: _ProposedSize(width: 21, height: 22),
                index: 6
            )
            let proposedSizes = _LazyLayout_ProposedSizes(subviews: [proposedSubview])
            XCTAssertTrue(proposedSizes.subviews[0].item === item)
            XCTAssertEqual(proposedSizes.subviews[0].proposal, _ProposedSize(width: 21, height: 22))
            XCTAssertEqual(proposedSizes.subviews[0].index, 6)

            let gridGeometry = HVGridGeometry(position: 23, size: 29, anchor: .topTrailing)
            XCTAssertEqual(gridGeometry.position, 23)
            XCTAssertEqual(gridGeometry.size, 29)
            XCTAssertEqual(gridGeometry.anchor, .topTrailing)

            let minorProperties = MinorProperties<LazyVStackLayout>(
                count: 2,
                size: 41,
                geometry: 41
            )
            XCTAssertEqual(minorProperties.count, 2)
            XCTAssertEqual(minorProperties.size, 41)
            XCTAssertEqual(minorProperties.geometry, 41)

            let placementProperties = PlacementProperties<LazyVStackLayout>(
                minor: minorProperties,
                visible: CGFloat(3)..<CGFloat(19),
                resetEstimates: true,
                estimatesChanged: true,
                visibleLength: 16,
                containerLength: 120
            )
            XCTAssertEqual(placementProperties.minor.count, 2)
            XCTAssertEqual(placementProperties.visible.lowerBound, 3)
            XCTAssertEqual(placementProperties.visible.upperBound, 19)
            XCTAssertTrue(placementProperties.resetEstimates)
            XCTAssertTrue(placementProperties.estimatesChanged)
            XCTAssertEqual(placementProperties.visibleLength, 16)
            XCTAssertEqual(placementProperties.containerLength, 120)

            let estimations = EstimationCache(
                lengthToCount: [12: 2],
                spacingToCount: [4: 1],
                zeroIndices: IndexSet(integer: 9)
            )
            XCTAssertEqual(estimations.lengthToCount[12], 2)
            XCTAssertEqual(estimations.spacingToCount[4], 1)
            XCTAssertTrue(estimations.zeroIndices.contains(9))

            var mutableEstimations = EstimationCache()
            mutableEstimations.add(length: 10, spacing: 2, count: 3)
            mutableEstimations.add(length: 20, spacing: nil, count: 1)
            XCTAssertEqual(mutableEstimations.lengthToCount[10], 3)
            XCTAssertEqual(mutableEstimations.lengthToCount[20], 1)
            XCTAssertEqual(mutableEstimations.spacingToCount[2], 3)
            XCTAssertEqual(mutableEstimations.average.length, 12.5)
            XCTAssertEqual(mutableEstimations.average.spacing, 2)

            var mergedEstimations = estimations
            mergedEstimations.merge(
                EstimationCache(
                    lengthToCount: [12: 3, 18: 4],
                    spacingToCount: [4: 2, 6: 1],
                    zeroIndices: IndexSet(integer: 11)
                )
            )
            XCTAssertEqual(mergedEstimations.lengthToCount, [12: 5, 18: 4])
            XCTAssertEqual(mergedEstimations.spacingToCount, [4: 3, 6: 1])
            XCTAssertEqual(mergedEstimations.zeroIndices, IndexSet([9, 11]))

            var cappedEstimations = EstimationCache()
            for value in 0..<26 {
                cappedEstimations.add(
                    length: CGFloat(value),
                    spacing: CGFloat(value + 100),
                    count: value + 1
                )
            }
            XCTAssertEqual(cappedEstimations.lengthToCount.count, 25)
            XCTAssertEqual(cappedEstimations.spacingToCount.count, 25)
            XCTAssertNil(cappedEstimations.lengthToCount[0])
            XCTAssertNil(cappedEstimations.spacingToCount[100])

            var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                minor: minorProperties,
                endIndex: 12,
                placedIndices: 2..<8,
                placedExtent: CGFloat(5)..<CGFloat(40),
                visibleExtent: CGFloat(6)..<CGFloat(30),
                visibleLength: 24,
                containerLength: 120,
                estimations: estimations
            )
            XCTAssertEqual(stackCache.minor?.count, 2)
            XCTAssertEqual(stackCache.endIndex, 12)
            XCTAssertEqual(stackCache.placedIndices, 2..<8)
            XCTAssertEqual(stackCache.placedExtent, CGFloat(5)..<CGFloat(40))
            XCTAssertEqual(stackCache.visibleExtent, CGFloat(6)..<CGFloat(30))
            XCTAssertEqual(stackCache.visibleLength, 24)
            XCTAssertEqual(stackCache.containerLength, 120)
            XCTAssertEqual(stackCache.estimations.lengthToCount[12], 2)
            stackCache.resetEstimates()
            XCTAssertEqual(stackCache.minor?.count, 2)
            XCTAssertTrue(stackCache.estimations.lengthToCount.isEmpty)
            stackCache.reset()
            XCTAssertNil(stackCache.minor)
            XCTAssertNil(stackCache.endIndex)
            XCTAssertTrue(stackCache.placedIndices.isEmpty)
            XCTAssertTrue(stackCache.placedExtent.isEmpty)
            XCTAssertTrue(stackCache.visibleExtent.isEmpty)
            XCTAssertEqual(stackCache.visibleLength, 24)
            XCTAssertEqual(stackCache.containerLength, 120)

            let stackPlacement = StackPlacement(
                stack: LazyVStackLayout(base: _VStackLayout(), pinnedViews: [.sectionHeaders]),
                axis: .vertical,
                minor: minorProperties,
                visible: CGFloat(5)..<CGFloat(35),
                pinnedViews: [.sectionHeaders],
                queriedIndex: 6,
                index: 7,
                skipFirst: true,
                position: 13,
                stoppingCondition: .index(11),
                currentSubviews: [lazySubview],
                lastSubviews: [lazySubview],
                pendingHeader: lazySubview,
                placedSubviews: [placedSubview],
                placedIndex: (min: 1, max: 5),
                placedPosition: (min: 2, max: 29),
                placedQuery: (min: 4, max: 31),
                wasCancelled: true,
                estimations: estimations
            )
            XCTAssertEqual(stackPlacement.stack.pinnedViews, [.sectionHeaders])
            XCTAssertEqual(stackPlacement.axis, .vertical)
            XCTAssertEqual(stackPlacement.minor.geometry, 41)
            XCTAssertEqual(stackPlacement.visible.lowerBound, 5)
            XCTAssertEqual(stackPlacement.visible.upperBound, 35)
            XCTAssertEqual(stackPlacement.pinnedViews, [.sectionHeaders])
            XCTAssertEqual(stackPlacement.queriedIndex, 6)
            XCTAssertEqual(stackPlacement.index, 7)
            XCTAssertTrue(stackPlacement.skipFirst)
            XCTAssertEqual(stackPlacement.position, 13)
            XCTAssertEqual(stackPlacement.stoppingCondition, .index(11))
            XCTAssertEqual(stackPlacement.currentSubviews[0].index, 8)
            XCTAssertEqual(stackPlacement.lastSubviews?[0].index, 8)
            XCTAssertEqual(stackPlacement.pendingHeader?.index, 8)
            XCTAssertTrue(stackPlacement.placedSubviews[0].item === item)
            XCTAssertEqual(stackPlacement.placedIndex.min, 1)
            XCTAssertEqual(stackPlacement.placedIndex.max, 5)
            XCTAssertEqual(stackPlacement.placedPosition.min, 2)
            XCTAssertEqual(stackPlacement.placedPosition.max, 29)
            XCTAssertEqual(stackPlacement.placedQuery.min, 4)
            XCTAssertEqual(stackPlacement.placedQuery.max, 31)
            XCTAssertTrue(stackPlacement.wasCancelled)
            XCTAssertEqual(stackPlacement.estimations.lengthToCount[12], 2)

            let namespaceValues: [any LazyLayoutNamespace] = [
                cache,
                properties,
                sizeContext,
                placementContext,
                estimatedContext,
                section,
                subviews,
                placedSubview,
                placements,
                proposedSubview,
                proposedSizes,
                estimated,
                gridGeometry,
                stackCache,
                minorProperties,
                placementProperties,
                estimations,
                stackPlacement,
            ]
            XCTAssertEqual(namespaceValues.count, 18)
        }
    }

    func testLazyPlacementContextResolvesScrollGeometryRTLAndAccessibilityOutset() {
        var accessibilityGeometry = ScrollGeometry(
            contentOffset: CGPoint(x: 20, y: 30),
            contentSize: CGSize(width: 300, height: 400),
            contentInsets: EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4),
            containerSize: CGSize(width: 40, height: 50)
        )
        accessibilityGeometry.outsetForAX(limit: CGSize(width: 100, height: 120))
        XCTAssertEqual(accessibilityGeometry.contentOffset, .zero)
        XCTAssertEqual(accessibilityGeometry.containerSize, CGSize(width: 80, height: 90))
        XCTAssertEqual(
            accessibilityGeometry.visibleRect,
            CGRect(x: 0, y: 0, width: 80, height: 90)
        )
        XCTAssertEqual(
            accessibilityGeometry.contentInsets,
            EdgeInsets(top: 1, leading: 2, bottom: 3, trailing: 4)
        )

        let host = GraphHost()
        host.data.withCurrent {
            let graph = host.data.graph
            let ruleContext = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let base = _LazyLayout_SizeAndSpacingContext(
                ruleContext: ruleContext,
                environment: graph.makeInput(value: EnvironmentValues()),
                containerSize: OptionalAttribute(
                    graph.makeInput(value: ViewSize(width: 31, height: 37))
                )
            )
            let containingInsets = EdgeInsets(
                top: 1,
                leading: 2,
                bottom: 3,
                trailing: 4
            )
            let nearestInsets = EdgeInsets(
                top: 5,
                leading: 6,
                bottom: 7,
                trailing: 8
            )
            var transform = ViewTransform()
            transform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: CGPoint(x: 10, y: 20),
                    contentSize: CGSize(width: 500, height: 600),
                    contentInsets: containingInsets,
                    containerSize: CGSize(width: 30, height: 40)
                ),
                isClipped: true
            )
            transform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: CGPoint(x: 60, y: 70),
                    contentSize: CGSize(width: 700, height: 800),
                    contentInsets: nearestInsets,
                    containerSize: CGSize(width: 20, height: 25)
                ),
                isClipped: true
            )

            let context = _LazyLayout_PlacementContext(
                base: base,
                size: ViewSize(width: 200, height: 150),
                transform: transform,
                layoutDirection: .rightToLeft,
                isAccessibilityEnabled: true
            )

            XCTAssertEqual(context.geometry.viewSize, CGSize(width: 200, height: 150))
            XCTAssertTrue(context.geometry.isAccessibilityEnabled)
            XCTAssertEqual(
                context.containingScrollGeometry.contentOffset,
                CGPoint(x: 160, y: 20)
            )
            XCTAssertEqual(
                context.containingScrollGeometry.visibleRect,
                CGRect(x: 160, y: 20, width: 30, height: 40)
            )
            XCTAssertEqual(
                context.nearestScrollGeometry.contentOffset,
                CGPoint(x: 120, y: 70)
            )
            XCTAssertEqual(
                context.nearestVisibleRect,
                CGRect(x: 120, y: 70, width: 20, height: 25)
            )
            XCTAssertEqual(context.unadjustedVisibleRect, context.containingScrollGeometry.visibleRect)
            XCTAssertEqual(context.contentInsets, nearestInsets)
            XCTAssertEqual(context.containerSize, CGSize(width: 31, height: 37))
            XCTAssertEqual(
                context.containingVisibleRect,
                CGRect(x: 130, y: 0, width: 60, height: 100)
            )
            XCTAssertEqual(
                context.clampedVisibleRect,
                CGRect(x: 130, y: 0, width: 60, height: 100)
            )
            XCTAssertTrue(context.allowsTranslations)
        }
    }

    func testLazyStackTransitionPlacementUsesLastSafeNearestMotionVector() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99)

            func placedSubview(
                id: Int,
                size: CGSize,
                at position: CGPoint
            ) -> _LazyLayout_PlacedSubview {
                let item = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: id
                ).item
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(size))
                    )
                )
                return _LazyLayout_PlacedSubview(
                    item: item,
                    placement: _Placement(
                        proposedSize: size,
                        anchoring: .topLeading,
                        at: position
                    ),
                    index: id
                )
            }

            let target = placedSubview(
                id: 1,
                size: CGSize(width: 20, height: 20),
                at: CGPoint(x: 0, y: 200)
            )
            let rejectedCloserMatch = placedSubview(
                id: 2,
                size: CGSize(width: 10, height: 10),
                at: CGPoint(x: 0, y: 225)
            )
            let selectedMatch = placedSubview(
                id: 3,
                size: CGSize(width: 10, height: 10),
                at: CGPoint(x: 0, y: 260)
            )
            let firstDuplicateDestination = placedSubview(
                id: 3,
                size: CGSize(width: 20, height: 20),
                at: CGPoint(x: 0, y: 150)
            )
            let overlappingDestination = placedSubview(
                id: 2,
                size: CGSize(width: 10, height: 10),
                at: CGPoint(x: 0, y: 25)
            )
            let lastDuplicateDestination = placedSubview(
                id: 3,
                size: CGSize(width: 30, height: 30),
                at: CGPoint(x: 0, y: 170)
            )
            let source = [target, rejectedCloserMatch, selectedMatch]
            let destination = [
                firstDuplicateDestination,
                overlappingDestination,
                lastDuplicateDestination,
            ]

            let ruleContext = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let base = _LazyLayout_SizeAndSpacingContext(
                ruleContext: ruleContext,
                environment: graph.makeInput(value: EnvironmentValues())
            )
            let placementContext = _LazyLayout_PlacementContext(
                base: base,
                size: ViewSize(width: 100, height: 100)
            )
            let subviews = cache.subviews(context: ruleContext)
            let layout = LazyVStackLayout(base: _VStackLayout(), pinnedViews: [])
            let stackCache = _LazyStack_Cache<LazyVStackLayout>()

            XCTAssertEqual(
                layout.initialPlacement(
                    newIndex: 0,
                    newPlacedSubviews: source,
                    oldPlacedSubviews: destination,
                    wasInsertedToSubviews: true,
                    context: placementContext,
                    subviews: subviews,
                    cache: stackCache
                ),
                target.placement
            )
            XCTAssertEqual(
                layout.finalPlacement(
                    oldIndex: 0,
                    oldPlacedSubviews: source,
                    newPlacedSubviews: destination,
                    wasRemovedFromSubviews: true,
                    context: placementContext,
                    subviews: subviews,
                    cache: stackCache
                ),
                target.placement
            )

            let initial = layout.initialPlacement(
                newIndex: 0,
                newPlacedSubviews: source,
                oldPlacedSubviews: destination,
                wasInsertedToSubviews: false,
                context: placementContext,
                subviews: subviews,
                cache: stackCache
            )
            XCTAssertEqual(initial.anchorPosition, CGPoint(x: 0, y: 110))
            XCTAssertEqual(initial.proposedSize_, _ProposedSize(width: 60, height: 60))

            let final = layout.finalPlacement(
                oldIndex: 0,
                oldPlacedSubviews: source,
                newPlacedSubviews: destination,
                wasRemovedFromSubviews: false,
                context: placementContext,
                subviews: subviews,
                cache: stackCache
            )
            XCTAssertEqual(final.anchorPosition, CGPoint(x: 0, y: 110))
            XCTAssertEqual(final.proposedSize_, _ProposedSize(width: 60, height: 60))
        }
    }

    func testLazyStackTransitionPlacementUsesForwardExternalFallback() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, targetItem, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, unmatchedItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            targetItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(
                    graph.makeInput(
                        value: LayoutComputer.fixed(CGSize(width: 10, height: 10))
                    )
                )
            )
            unmatchedItem.outputs = targetItem.outputs

            let target = _LazyLayout_PlacedSubview(
                item: targetItem,
                placement: _Placement(
                    proposedSize: CGSize(width: 10, height: 10),
                    anchoring: .center,
                    at: CGPoint(x: 5, y: 5)
                ),
                index: 0
            )
            let unmatched = _LazyLayout_PlacedSubview(
                item: unmatchedItem,
                placement: _Placement(
                    proposedSize: CGSize(width: 10, height: 10),
                    anchoring: .center,
                    at: CGPoint(x: 5, y: 50)
                ),
                index: 1
            )
            var transform = ViewTransform()
            transform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 10),
                    contentSize: CGSize(width: 100, height: 200),
                    containerSize: CGSize(width: 100, height: 20)
                ),
                isClipped: true
            )
            let ruleContext = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let placementContext = _LazyLayout_PlacementContext(
                base: _LazyLayout_SizeAndSpacingContext(
                    ruleContext: ruleContext,
                    environment: graph.makeInput(value: EnvironmentValues())
                ),
                size: ViewSize(width: 100, height: 100),
                transform: transform
            )
            let subviews = cache.subviews(context: ruleContext)
            let layout = LazyVStackLayout(base: _VStackLayout(), pinnedViews: [])
            let stackCache = _LazyStack_Cache<LazyVStackLayout>()

            let initial = layout.initialPlacement(
                newIndex: 0,
                newPlacedSubviews: [target],
                oldPlacedSubviews: [unmatched],
                wasInsertedToSubviews: false,
                context: placementContext,
                subviews: subviews,
                cache: stackCache
            )
            XCTAssertEqual(initial.anchor, .center)
            XCTAssertEqual(initial.anchorPosition, CGPoint(x: 5, y: 55))
            XCTAssertEqual(initial.proposedSize_, target.placement.proposedSize_)

            let final = layout.finalPlacement(
                oldIndex: 0,
                oldPlacedSubviews: [target],
                newPlacedSubviews: [unmatched],
                wasRemovedFromSubviews: false,
                context: placementContext,
                subviews: subviews,
                cache: stackCache
            )
            XCTAssertEqual(final.anchor, .center)
            XCTAssertEqual(final.anchorPosition, CGPoint(x: 5, y: 55))
            XCTAssertEqual(final.proposedSize_, target.placement.proposedSize_)
        }
    }

    func testLazyStackTransitionPlacementUsesNearbyFullIdentityWithinEstimatedWindow() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = Array(
                repeating: CGSize(width: 10, height: 10),
                count: 6
            )
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(
                    graph: graph,
                    sizes: sizes
                )
            )
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()

            let ruleContext = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let subviews = cache.subviews(context: ruleContext)
            var from = 3
            var target: _LazyLayout_PlacedSubview?
            XCTAssertFalse(subviews.apply(from: &from) { index, subview, stop in
                target = subview.place(
                    at: _Placement(
                        proposedSize: CGSize(width: 10, height: 10),
                        anchoring: .center,
                        at: CGPoint(x: 5, y: 300)
                    )
                )
                XCTAssertEqual(index, 3)
                stop = true
            })
            let targetPlacedSubview = try XCTUnwrap(target)
            let unmatchedItem = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 100,
                list: list
            ).item
            unmatchedItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(
                    graph.makeInput(
                        value: LayoutComputer.fixed(CGSize(width: 10, height: 10))
                    )
                )
            )
            let unmatched = _LazyLayout_PlacedSubview(
                item: unmatchedItem,
                placement: _Placement(
                    proposedSize: CGSize(width: 10, height: 10),
                    anchoring: .topLeading,
                    at: .zero
                ),
                index: 100
            )
            let placementContext = _LazyLayout_PlacementContext(
                base: _LazyLayout_SizeAndSpacingContext(
                    ruleContext: ruleContext,
                    environment: graph.makeInput(value: EnvironmentValues())
                ),
                size: ViewSize(width: 100, height: 100)
            )
            let layout = LazyVStackLayout(base: _VStackLayout(spacing: 0), pinnedViews: [])
            let estimates = EstimationCache(
                lengthToCount: [10: 1],
                spacingToCount: [0: 1]
            )
            let wideCache = _LazyStack_Cache<LazyVStackLayout>(
                minor: MinorProperties(count: 1, size: 100, geometry: 100),
                visibleLength: 100,
                estimations: estimates
            )
            var identityScanFrom = 0
            var matchingIndex: Int?
            XCTAssertFalse(subviews.apply(
                from: &identityScanFrom,
                style: _ViewList_IteratorStyle(value: 2)
            ) { index, subview, stop in
                if subview.id == targetPlacedSubview.id {
                    matchingIndex = index
                    stop = true
                }
            })
            XCTAssertEqual(matchingIndex, 3)
            XCTAssertEqual(
                layout.boundingRect(
                    at: 3,
                    subviews: subviews,
                    context: placementContext,
                    cache: wideCache
                ),
                CGRect(x: 0, y: 30, width: 100, height: 10)
            )

            let nearby = layout.initialPlacement(
                newIndex: 0,
                newPlacedSubviews: [targetPlacedSubview],
                oldPlacedSubviews: [unmatched],
                wasInsertedToSubviews: false,
                context: placementContext,
                subviews: subviews,
                cache: wideCache
            )
            XCTAssertEqual(nearby.anchor, .center)
            XCTAssertEqual(nearby.anchorPosition, CGPoint(x: 50, y: 35))

            let outsideWindow = layout.initialPlacement(
                newIndex: 0,
                newPlacedSubviews: [targetPlacedSubview],
                oldPlacedSubviews: [unmatched],
                wasInsertedToSubviews: false,
                context: placementContext,
                subviews: subviews,
                cache: _LazyStack_Cache<LazyVStackLayout>(
                    minor: MinorProperties(count: 1, size: 100, geometry: 100),
                    visibleLength: 20,
                    estimations: estimates
                )
            )
            XCTAssertEqual(outsideWindow.anchor, .center)
            XCTAssertEqual(outsideWindow.anchorPosition, CGPoint(x: 5, y: 310))
        }
    }

    func testLazyLayoutSubviewsApplyTraversesCacheViewList() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let list = BaseViewList(elements: CountingViewListElements(count: 3))
            let (cache, _, _) = makeLazyCache(host: host, list: list)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)

            XCTAssertEqual(subviews.estimatedCount(), 3)

            var from = 1
            var indices: [Int] = []
            XCTAssertTrue(subviews.apply(from: &from) { index, subview, _ in
                XCTAssertEqual(index, subview.index)
                indices.append(subview.index)
            })
            XCTAssertEqual(indices, [1, 2])

            XCTAssertEqual(subviews.id(at: 2)?.canonicalID.index, 2)

            var nodeFrom = 0
            var nodeCounts: [Int] = []
            XCTAssertTrue(subviews.applyNodes(from: &nodeFrom) { _, node, _ in
                guard case .subviews(let child) = node else {
                    XCTFail("Expected subviews node")
                    return
                }
                nodeCounts.append(child.estimatedCount())
            })
            XCTAssertEqual(nodeCounts, [3])
        }
    }

    func testStackPlacementHelpersFollowDisassemblySlice() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, item, _) = makeLazyCache(host: host)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subview = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(graph: graph, id: _ViewList_ID(implicitID: 61)),
                index: 4
            )
            let placedSubview = _LazyLayout_PlacedSubview(
                item: item,
                placement: _Placement(proposedSize: CGSize(width: 11, height: 17)),
                index: 4
            )
            let minor = MinorProperties<LazyVStackLayout>(
                count: 3,
                size: 40,
                geometry: 40
            )
            var placement = StackPlacement(
                stack: LazyVStackLayout(base: _VStackLayout(), pinnedViews: []),
                axis: .vertical,
                minor: minor,
                visible: CGFloat(10)..<CGFloat(30),
                queriedIndex: nil,
                index: 2,
                position: 12,
                stoppingCondition: .position(20),
                currentSubviews: [subview],
                lastSubviews: [subview],
                pendingHeader: subview,
                placedSubviews: [placedSubview],
                placedIndex: (min: 1, max: 4),
                placedPosition: (min: 10, max: 70),
                placedQuery: (min: 12, max: 72),
                wasCancelled: true,
                estimations: EstimationCache(
                    lengthToCount: [10: 1],
                    spacingToCount: [2: 1],
                    zeroIndices: IndexSet(integer: 4)
                )
            )

            XCTAssertTrue(placement.isVisible(length: 4))
            placement.position = 30
            XCTAssertTrue(placement.isVisible(length: 0))
            placement.position = 31
            XCTAssertFalse(placement.isVisible(length: 0))

            placement.position = 12
            placement.queriedIndex = 3
            XCTAssertTrue(placement.isVisible(length: 0))
            placement.queriedIndex = 5
            XCTAssertFalse(placement.isVisible(length: 0))
            placement.queriedIndex = 1
            XCTAssertFalse(placement.isVisible(length: 0))

            placement.queriedIndex = nil
            placement.position = 19
            XCTAssertFalse(placement.shouldStop())
            placement.position = 20
            XCTAssertTrue(placement.shouldStop())

            placement.stoppingCondition = .index(4)
            placement.index = 4
            XCTAssertFalse(placement.shouldStop())
            placement.index = 5
            XCTAssertTrue(placement.shouldStop())

            placement.stoppingCondition = .never
            placement.index = Int.max
            XCTAssertFalse(placement.shouldStop())

            placement.index = 2
            placement.position = 12
            placement.placedIndex = (min: Int.max, max: Int.min)
            placement.placedPosition = (min: .infinity, max: -.infinity)
            placement.placedQuery = (min: .infinity, max: -.infinity)
            placement.addVisibleSubview(length: 6, spacing: 2)
            XCTAssertEqual(placement.placedIndex.min, 2)
            XCTAssertEqual(placement.placedIndex.max, 4)
            XCTAssertEqual(placement.placedPosition.min, 10)
            XCTAssertEqual(placement.placedPosition.max, 18)
            XCTAssertEqual(placement.placedQuery.min, .infinity)
            XCTAssertEqual(placement.placedQuery.max, -.infinity)

            placement.queriedIndex = 3
            placement.placedQuery = (min: .infinity, max: -.infinity)
            placement.addVisibleSubview(length: 6, spacing: 2)
            XCTAssertEqual(placement.placedQuery.min, 12)
            XCTAssertEqual(placement.placedQuery.max, 18)

            placement.queriedIndex = 5
            placement.placedQuery = (min: .infinity, max: -.infinity)
            placement.addVisibleSubview(length: 6, spacing: 2)
            XCTAssertEqual(placement.placedQuery.min, .infinity)
            XCTAssertEqual(placement.placedQuery.max, -.infinity)

            XCTAssertEqual(
                placement.placedBounds(minorAxis: 1...5),
                CGRect(x: 1, y: 10, width: 4, height: 8)
            )
            XCTAssertEqual(placement.placedExtent, CGFloat(10)...CGFloat(18))

            placement.axis = .horizontal
            XCTAssertEqual(
                placement.placedBounds(minorAxis: 1...5),
                CGRect(x: 10, y: 1, width: 8, height: 4)
            )
            XCTAssertEqual(
                placement.placedBounds(minorAxis: 9),
                CGRect(x: 10, y: 0, width: 8, height: 9)
            )

            placement.placedPosition = (min: 8, max: 8)
            XCTAssertTrue(placement.placedBounds(minorAxis: 9).isNull)

            placement.queriedIndex = 6
            placement.reset(
                index: 9,
                position: 44,
                stoppingCondition: .index(11),
                skipFirst: true
            )
            XCTAssertEqual(placement.queriedIndex, 6)
            XCTAssertEqual(placement.index, 9)
            XCTAssertTrue(placement.skipFirst)
            XCTAssertEqual(placement.position, 44)
            XCTAssertEqual(placement.stoppingCondition, .index(11))
            XCTAssertTrue(placement.currentSubviews.isEmpty)
            XCTAssertNil(placement.lastSubviews)
            XCTAssertNil(placement.pendingHeader)
            XCTAssertTrue(placement.placedSubviews.isEmpty)
            XCTAssertEqual(placement.placedIndex.min, Int.max)
            XCTAssertEqual(placement.placedIndex.max, Int.min)
            XCTAssertEqual(placement.placedPosition.min, .infinity)
            XCTAssertEqual(placement.placedPosition.max, -.infinity)
            XCTAssertEqual(placement.placedQuery.min, .infinity)
            XCTAssertEqual(placement.placedQuery.max, -.infinity)
            XCTAssertFalse(placement.wasCancelled)
            XCTAssertTrue(placement.estimations.lengthToCount.isEmpty)
            XCTAssertTrue(placement.estimations.spacingToCount.isEmpty)
            XCTAssertTrue(placement.estimations.zeroIndices.isEmpty)
            XCTAssertTrue(placement.placedBounds(minorAxis: 0...40).isNull)
            XCTAssertEqual(placement.placedExtent, CGFloat(44)...CGFloat(44))
            XCTAssertFalse(placement.shouldStop())

            placement.index = 11
            XCTAssertFalse(placement.shouldStop())
            placement.index = 12
            XCTAssertTrue(placement.shouldStop())
        }
    }

    func testStackPlacementPlaceBodyFlushesMinorGroupAndEmitsPlacedSubviews() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstItem, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, secondItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            firstItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        XCTAssertEqual(proposal.width, 30)
                        XCTAssertNil(proposal.height)
                        return CGSize(width: proposal.width ?? 0, height: 40)
                    }
                )))
            )
            secondItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        XCTAssertEqual(proposal.width, 50)
                        XCTAssertNil(proposal.height)
                        return CGSize(width: proposal.width ?? 0, height: 55)
                    }
                )))
            )

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let firstSubview = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(graph: graph, id: _ViewList_ID(implicitID: 1)),
                index: 0
            )
            let secondSubview = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(graph: graph, id: _ViewList_ID(implicitID: 2)),
                index: 1
            )
            let layout = LazyVGridLayout(
                columns: [GridItem(.fixed(30)), GridItem(.fixed(50))],
                alignment: .leading,
                spacing: 7,
                pinnedViews: []
            )
            var placement = StackPlacement(
                stack: layout,
                axis: .vertical,
                minor: MinorProperties(
                    count: 2,
                    size: 80,
                    geometry: [
                        HVGridGeometry(position: 0, size: 30, anchor: .leading),
                        HVGridGeometry(position: 30, size: 50, anchor: .trailing),
                    ]
                ),
                visible: CGFloat(0)..<CGFloat(120),
                index: 0,
                position: 10,
                placedIndex: (min: Int.max, max: Int.min),
                placedPosition: (min: .infinity, max: -.infinity),
                placedQuery: (min: .infinity, max: -.infinity),
                estimations: EstimationCache(zeroIndices: IndexSet(integer: 0))
            )

            XCTAssertFalse(placement.placeBody(subview: firstSubview))
            XCTAssertEqual(placement.currentSubviews.map(\.index), [0])
            XCTAssertTrue(placement.placedSubviews.isEmpty)

            XCTAssertTrue(placement.placeBody(subview: secondSubview))
            XCTAssertTrue(placement.currentSubviews.isEmpty)
            XCTAssertEqual(placement.lastSubviews?.map(\.index), [0, 1])
            XCTAssertEqual(placement.placedSubviews.map(\.index), [0, 1])
            XCTAssertEqual(placement.placedIndex.min, 0)
            XCTAssertEqual(placement.placedIndex.max, 1)
            XCTAssertEqual(placement.placedPosition.min, 10)
            XCTAssertEqual(placement.placedPosition.max, 65)
            XCTAssertEqual(placement.position, 65)
            XCTAssertEqual(placement.index, 2)
            XCTAssertEqual(placement.estimations.lengthToCount[55], 1)
            XCTAssertEqual(placement.estimations.spacingToCount[0], 1)
            XCTAssertFalse(placement.estimations.zeroIndices.contains(0))

            let firstPlacement = try XCTUnwrap(firstItem.pendingPlacement)
            XCTAssertEqual(
                firstPlacement,
                _Placement(
                    proposedSize: CGSize(width: 30, height: 55),
                    anchoring: .leading,
                    at: CGPoint(x: 0, y: 10)
                )
            )
            let secondPlacement = try XCTUnwrap(secondItem.pendingPlacement)
            XCTAssertEqual(
                secondPlacement,
                _Placement(
                    proposedSize: CGSize(width: 50, height: 55),
                    anchoring: .trailing,
                    at: CGPoint(x: 30, y: 10)
                )
            )
        }
    }

    func testStackPlacementPlaceTraversesSubviewNodesAndFlushesTail() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 20, height: 30),
                CGSize(width: 25, height: 40),
                CGSize(width: 30, height: 50),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes)
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .center, spacing: 5),
                pinnedViews: []
            )
            var placement = StackPlacement(
                stack: layout,
                axis: .vertical,
                minor: MinorProperties(count: 1, size: 80, geometry: 80),
                visible: CGFloat(0)..<CGFloat(160),
                index: 0,
                position: 7,
                placedIndex: (min: Int.max, max: Int.min),
                placedPosition: (min: .infinity, max: -.infinity),
                placedQuery: (min: .infinity, max: -.infinity)
            )

            XCTAssertTrue(placement.place(subviews: subviews))
            XCTAssertTrue(placement.currentSubviews.isEmpty)
            XCTAssertEqual(placement.lastSubviews?.map(\.index), [2])
            XCTAssertEqual(placement.placedSubviews.map(\.index), [0, 1, 2])
            XCTAssertEqual(placement.placedIndex.min, 0)
            XCTAssertEqual(placement.placedIndex.max, 2)
            XCTAssertEqual(placement.placedPosition.min, 7)
            XCTAssertEqual(placement.placedPosition.max, 137)
            XCTAssertEqual(placement.position, 137)
            XCTAssertEqual(placement.index, 3)
            XCTAssertEqual(placement.estimations.lengthToCount[30], 1)
            XCTAssertEqual(placement.estimations.lengthToCount[40], 1)
            XCTAssertEqual(placement.estimations.lengthToCount[50], 1)
            XCTAssertEqual(placement.estimations.spacingToCount[0], 1)
            XCTAssertEqual(placement.estimations.spacingToCount[5], 2)

            for index in sizes.indices {
                let id = _ViewList_ID(implicitID: 0).elementID(at: index)
                let item = try XCTUnwrap(cache.items[id.canonicalID])
                let itemPlacement = try XCTUnwrap(item.pendingPlacement)
                XCTAssertEqual(itemPlacement.proposedSize, CGSize(width: 80, height: 10))
                XCTAssertEqual(itemPlacement.anchor, .center)
            }
            XCTAssertEqual(
                cache.items[_ViewList_ID(implicitID: 0).elementID(at: 0).canonicalID]?.pendingPlacement?.anchorPosition,
                CGPoint(x: 0, y: 7)
            )
            XCTAssertEqual(
                cache.items[_ViewList_ID(implicitID: 0).elementID(at: 1).canonicalID]?.pendingPlacement?.anchorPosition,
                CGPoint(x: 0, y: 42)
            )
            XCTAssertEqual(
                cache.items[_ViewList_ID(implicitID: 0).elementID(at: 2).canonicalID]?.pendingPlacement?.anchorPosition,
                CGPoint(x: 0, y: 87)
            )
        }
    }

    func testStackPlacementExactPlaceResetsSkipsFirstAndReportsStop() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 20, height: 30),
                CGSize(width: 25, height: 40),
                CGSize(width: 30, height: 50),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes)
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 0),
                pinnedViews: []
            )
            var placement = StackPlacement(
                stack: layout,
                axis: .vertical,
                minor: MinorProperties(count: 1, size: 80, geometry: 80),
                visible: CGFloat(0)..<CGFloat(160),
                index: 99,
                skipFirst: true,
                position: 44,
                stoppingCondition: .position(45),
                placedIndex: (min: 4, max: 9),
                placedPosition: (min: 11, max: 12),
                placedQuery: (min: 13, max: 14)
            )

            XCTAssertTrue(placement.place(
                subviews: subviews,
                from: 1,
                position: 7,
                stopping: .never,
                style: _ViewList_IteratorStyle()
            ))
            XCTAssertFalse(placement.skipFirst)
            XCTAssertEqual(placement.placedSubviews.map(\.index), [1, 2])
            XCTAssertEqual(placement.lastSubviews?.map(\.index), [2])
            XCTAssertEqual(placement.placedIndex.min, 1)
            XCTAssertEqual(placement.placedIndex.max, 2)
            XCTAssertEqual(placement.placedPosition.min, 7)
            XCTAssertEqual(placement.placedPosition.max, 97)
            XCTAssertEqual(placement.position, 97)
            XCTAssertEqual(placement.index, 3)
            XCTAssertNil(placement.estimations.lengthToCount[30])
            XCTAssertEqual(placement.estimations.lengthToCount[40], 1)
            XCTAssertEqual(placement.estimations.lengthToCount[50], 1)
            XCTAssertEqual(placement.estimations.spacingToCount[0], 2)

            var stoppedPlacement = StackPlacement(
                stack: layout,
                axis: .vertical,
                minor: MinorProperties(count: 1, size: 80, geometry: 80),
                visible: CGFloat(0)..<CGFloat(160),
                placedIndex: (min: Int.max, max: Int.min),
                placedPosition: (min: .infinity, max: -.infinity),
                placedQuery: (min: .infinity, max: -.infinity)
            )
            XCTAssertFalse(stoppedPlacement.place(
                subviews: subviews,
                from: 0,
                position: 7,
                stopping: .index(0),
                style: _ViewList_IteratorStyle()
            ))
            XCTAssertEqual(stoppedPlacement.placedSubviews.map(\.index), [0])
            XCTAssertEqual(stoppedPlacement.placedPosition.min, 7)
            XCTAssertEqual(stoppedPlacement.placedPosition.max, 37)
            XCTAssertEqual(stoppedPlacement.position, 37)
            XCTAssertEqual(stoppedPlacement.index, 1)
        }
    }

    func testStackPlacementSectionNodeFlushesPendingGroupAndReadsEmptyRegions() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 20, height: 30),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes)
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            var from = 0
            var pending: _LazyLayout_Subview?
            _ = subviews.apply(from: &from) { _, subview, stop in
                pending = subview
                stop = true
            }
            let pendingSubview = try XCTUnwrap(pending)

            let transform = _ViewList_SublistTransform()
            let section = _LazyLayout_Section(
                base: _ViewList_Section(),
                transform: transform,
                cache: cache,
                context: context,
                baseIndex: 1
            )
            XCTAssertEqual(section.header.section, LazyLayoutCacheSection(id: 0, isHeader: true))
            XCTAssertEqual(section.content.section, LazyLayoutCacheSection(id: 0))
            XCTAssertEqual(section.footer.section, LazyLayoutCacheSection(id: 0, isFooter: true))

            let sectionSubviews = _LazyLayout_Subviews(
                cache: cache,
                context: context,
                node: .section(_ViewList_Section()),
                transform: transform,
                baseIndex: 1
            )
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 0),
                pinnedViews: []
            )
            var placement = StackPlacement(
                stack: layout,
                axis: .vertical,
                minor: MinorProperties(count: 1, size: 80, geometry: 80),
                visible: CGFloat(0)..<CGFloat(100),
                index: 0,
                position: 7,
                currentSubviews: [pendingSubview],
                placedIndex: (min: Int.max, max: Int.min),
                placedPosition: (min: .infinity, max: -.infinity),
                placedQuery: (min: .infinity, max: -.infinity)
            )

            XCTAssertTrue(placement.place(subviews: sectionSubviews))
            XCTAssertTrue(placement.currentSubviews.isEmpty)
            XCTAssertEqual(placement.lastSubviews?.map(\.index), [0])
            XCTAssertEqual(placement.placedSubviews.map(\.index), [0])
            XCTAssertEqual(placement.placedPosition.min, 7)
            XCTAssertEqual(placement.placedPosition.max, 37)
            XCTAssertEqual(placement.position, 37)
            XCTAssertEqual(placement.index, 1)
        }
    }

    func testStackPlacementSectionNodeStartsInsideContentReplaysBoundaryHeader() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            let header = makeRegion([CGSize(width: 20, height: 10)])
            let content = makeRegion([
                CGSize(width: 20, height: 20),
                CGSize(width: 25, height: 30),
                CGSize(width: 30, height: 40),
            ])
            let footer = makeRegion([CGSize(width: 35, height: 50)])
            let list: any ViewList = _ViewList_Section(
                id: 7,
                base: _ViewList_Group(lists: [header, content, footer])
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVGridLayout(
                columns: [GridItem(.fixed(20), spacing: 0), GridItem(.fixed(30), spacing: 0)],
                alignment: .leading,
                spacing: 0,
                pinnedViews: []
            )
            var placement = StackPlacement(
                stack: layout,
                axis: .vertical,
                minor: MinorProperties(
                    count: 2,
                    size: 50,
                    geometry: [
                        HVGridGeometry(position: 0, size: 20, anchor: .leading),
                        HVGridGeometry(position: 20, size: 30, anchor: .leading),
                    ]
                ),
                visible: CGFloat(0)..<CGFloat(300),
                placedIndex: (min: Int.max, max: Int.min),
                placedPosition: (min: .infinity, max: -.infinity),
                placedQuery: (min: .infinity, max: -.infinity)
            )

            XCTAssertTrue(placement.place(
                subviews: subviews,
                from: 3,
                position: 100,
                stopping: .never,
                style: _ViewList_IteratorStyle()
            ))
            XCTAssertFalse(placement.skipFirst)
            XCTAssertEqual(placement.placedSubviews.map(\.index), [0, 3, 4])
            XCTAssertEqual(placement.placedSubviews.map(\.item.section), [
                LazyLayoutCacheSection(id: 7, isHeader: true),
                LazyLayoutCacheSection(id: 7),
                LazyLayoutCacheSection(id: 7, isFooter: true),
            ])
            XCTAssertEqual(placement.position, 200)
            XCTAssertEqual(placement.index, 5)

            let bodyItem = try XCTUnwrap(placement.placedSubviews.first { $0.index == 3 }?.item)
            XCTAssertEqual(
                bodyItem.pendingPlacement?.anchorPosition,
                CGPoint(x: 0, y: 110)
            )
            let footerItem = try XCTUnwrap(placement.placedSubviews.first { $0.index == 4 }?.item)
            XCTAssertEqual(
                footerItem.pendingPlacement?.anchorPosition,
                CGPoint(x: 0, y: 150)
            )
        }
    }

    func testLazyLayoutSectionMaterializesStoredRegionsWithBaseIndexOffsets() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            let header = makeRegion([CGSize(width: 20, height: 10)])
            let content = makeRegion([
                CGSize(width: 20, height: 20),
                CGSize(width: 20, height: 30),
            ])
            let footer = makeRegion([CGSize(width: 20, height: 40)])
            let viewSection = _ViewList_Section(
                id: 7,
                base: _ViewList_Group(lists: [header, content, footer])
            )

            XCTAssertEqual(viewSection.count(style: _ViewList_IteratorStyle()), 4)
            XCTAssertEqual(viewSection.estimatedCount(style: _ViewList_IteratorStyle()), 4)

            let (cache, _, _) = makeLazyCache(host: host)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let section = _LazyLayout_Section(
                base: viewSection,
                transform: _ViewList_SublistTransform(),
                cache: cache,
                context: context,
                baseIndex: 10
            )

            XCTAssertEqual(section.header.baseIndex, 10)
            XCTAssertEqual(section.content.baseIndex, 11)
            XCTAssertEqual(section.footer.baseIndex, 13)

            var headerFrom = 0
            var headerItems: [(Int, LazyLayoutCacheSection)] = []
            var headerIDs: [_ViewList_ID] = []
            XCTAssertTrue(section.header.apply(from: &headerFrom) { _, subview, _ in
                headerItems.append((subview.index, subview.data.section))
                headerIDs.append(subview.data.id)
            })
            XCTAssertEqual(headerItems.map(\.0), [10])
            XCTAssertEqual(headerItems.map(\.1), [LazyLayoutCacheSection(id: 7, isHeader: true)])
            XCTAssertEqual(headerIDs.map(\._index), [0])
            XCTAssertTrue(headerIDs.allSatisfy(\.explicitIDs.isEmpty))

            var contentFrom = 0
            var contentItems: [(Int, LazyLayoutCacheSection)] = []
            var contentIDs: [_ViewList_ID] = []
            XCTAssertTrue(section.content.apply(from: &contentFrom) { _, subview, _ in
                contentItems.append((subview.index, subview.data.section))
                contentIDs.append(subview.data.id)
            })
            XCTAssertEqual(contentItems.map(\.0), [11, 12])
            XCTAssertEqual(contentItems.map(\.1), [
                LazyLayoutCacheSection(id: 7),
                LazyLayoutCacheSection(id: 7),
            ])
            XCTAssertEqual(contentIDs.map(\._index), [0, 1])
            XCTAssertTrue(contentIDs.allSatisfy(\.explicitIDs.isEmpty))

            var footerFrom = 0
            var footerItems: [(Int, LazyLayoutCacheSection)] = []
            var footerIDs: [_ViewList_ID] = []
            XCTAssertTrue(section.footer.apply(from: &footerFrom) { _, subview, _ in
                footerItems.append((subview.index, subview.data.section))
                footerIDs.append(subview.data.id)
            })
            XCTAssertEqual(footerItems.map(\.0), [13])
            XCTAssertEqual(footerItems.map(\.1), [LazyLayoutCacheSection(id: 7, isFooter: true)])
            XCTAssertEqual(footerIDs.map(\._index), [0])
            XCTAssertTrue(footerIDs.allSatisfy(\.explicitIDs.isEmpty))
        }
    }

    func testLazyLayoutSectionRegionSubviewIDsPreserveDirectTransformOrder() {
        let host = GraphHost()

        func firstID(in subviews: _LazyLayout_Subviews) -> _ViewList_ID? {
            var result: _ViewList_ID?
            var from = 0
            _ = subviews.apply(from: &from) { _, subview, stop in
                result = subview.data.id
                stop = true
            }
            return result
        }

        host.data.withCurrent {
            let graph = host.data.graph
            let sections = TupleView((
                Section {
                    Text("Row")
                        .id("row-id")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                }
                .id("section-id"),
                Text("Tail")
            ))
            let sectionsAttr = graph.makeInput(value: sections)
            var inputs = makeViewListInputs(graph: graph)
            inputs.formUnion(viewListOptions: .requiresSections)
            let outputs = type(of: sections)._makeViewList(
                view: _GraphValue(_attribute: sectionsAttr),
                inputs: inputs
            )
            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("section-list TupleView should produce a dynamic section-aware list")
                return
            }

            let (cache, _, _) = makeLazyCache(host: host, list: listAttr.value)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)

            guard let section = lazyLayoutSections(in: subviews).first else {
                XCTFail("expected a lazy section node")
                return
            }

            let headerID = firstID(in: section.header)
            let contentID = firstID(in: section.content)
            let footerID = firstID(in: section.footer)

            guard let headerID,
                  let contentID,
                  let footerID else {
                XCTFail("expected header/content/footer IDs")
                return
            }
            XCTAssertEqual(contentID.explicitIDs.count, 3)
            XCTAssertEqual(contentID.explicitIDs[0].id, AnyHashable("row-id"))
            XCTAssertTrue(contentID.explicitIDs[1].id.base is UniqueID)
            XCTAssertEqual(contentID.explicitIDs[2].id, AnyHashable("section-id"))
            XCTAssertEqual(contentID.explicitIDs.map(\.isUnary), [true, false, false])
            XCTAssertEqual(headerID.explicitIDs, Array(contentID.explicitIDs.suffix(1)))
            XCTAssertEqual(footerID.explicitIDs, Array(contentID.explicitIDs.suffix(1)))
        }
    }

    func testLazyLayoutSectionNodesPreserveDirectRowAndSectionIDs() {
        let host = GraphHost()

        func firstID(in subviews: _LazyLayout_Subviews) -> _ViewList_ID? {
            var result: _ViewList_ID?
            var from = 0
            _ = subviews.apply(from: &from) { _, subview, stop in
                result = subview.data.id
                stop = true
            }
            return result
        }

        host.data.withCurrent {
            let graph = host.data.graph
            let sections = TupleView((
                Section {
                    Text("Row A")
                        .id("row-a")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                }
                .id("section-a"),
                Section {
                    Text("Row B")
                        .id("row-b")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
                .id("section-b")
            ))
            let sectionsAttr = graph.makeInput(value: sections)
            var inputs = makeViewListInputs(graph: graph)
            inputs.formUnion(viewListOptions: .requiresSections)
            let outputs = type(of: sections)._makeViewList(
                view: _GraphValue(_attribute: sectionsAttr),
                inputs: inputs
            )
            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("section-list TupleView should produce a dynamic section-aware list")
                return
            }

            let (cache, _, _) = makeLazyCache(host: host, list: listAttr.value)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)

            var rowIDs: [_ViewList_ID] = []
            for section in lazyLayoutSections(in: subviews) {
                if let id = firstID(in: section.content) {
                    rowIDs.append(id)
                }
            }

            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [3, 3])
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[0].id.base as? String }, ["row-a", "row-b"])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[1].id.base is UniqueID })
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[2].id.base as? String }, ["section-a", "section-b"])
            XCTAssertNotEqual(rowIDs[0].explicitIDs[1].id, rowIDs[1].explicitIDs[1].id)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true, false, false,
                true, false, false,
            ])
        }
    }

    func testLazyLayoutSectionNodesUseGeneratedCanonicalRowID() {
        let host = GraphHost()

        func firstID(in subviews: _LazyLayout_Subviews) -> _ViewList_ID? {
            var result: _ViewList_ID?
            var from = 0
            _ = subviews.apply(from: &from) { _, subview, stop in
                result = subview.data.id
                stop = true
            }
            return result
        }

        host.data.withCurrent {
            let graph = host.data.graph
            let sections = TupleView((
                Section {
                    Text("Row A")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                }
                .id("section-a"),
                Section {
                    Text("Row B")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
                .id("section-b")
            ))
            let sectionsAttr = graph.makeInput(value: sections)
            var inputs = makeViewListInputs(graph: graph)
            inputs.formUnion(viewListOptions: .requiresSections)
            let outputs = type(of: sections)._makeViewList(
                view: _GraphValue(_attribute: sectionsAttr),
                inputs: inputs
            )
            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("section-list TupleView should produce a dynamic section-aware list")
                return
            }

            let (cache, _, _) = makeLazyCache(host: host, list: listAttr.value)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)

            var headerIDs: [_ViewList_ID] = []
            var rowIDs: [_ViewList_ID] = []
            var footerIDs: [_ViewList_ID] = []
            for section in lazyLayoutSections(in: subviews) {
                guard let headerID = firstID(in: section.header),
                      let id = firstID(in: section.content) else {
                    continue
                }
                headerIDs.append(headerID)
                rowIDs.append(id)
                if let footerID = firstID(in: section.footer) {
                    footerIDs.append(footerID)
                }
            }

            XCTAssertEqual(headerIDs.count, 2)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(footerIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [2, 2])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[1].id.base as? String }, ["section-a", "section-b"])
            XCTAssertEqual(
                headerIDs.map { $0.explicitIDs },
                rowIDs.map { Array($0.explicitIDs.suffix(1)) }
            )
            XCTAssertEqual(
                footerIDs.map { $0.explicitIDs },
                rowIDs.map { Array($0.explicitIDs.suffix(1)) }
            )
            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[0].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[0].reuseID,
                rowIDs[1].explicitIDs[0].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[0].owner, rowIDs[1].explicitIDs[0].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true, false,
                true, false,
            ])
            XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowGeneratedIDs)
        }
    }

    func testLazyLayoutPlainSectionNodesKeepOnlyGeneratedRowID() {
        let host = GraphHost()

        func firstID(in subviews: _LazyLayout_Subviews) -> _ViewList_ID? {
            var result: _ViewList_ID?
            var from = 0
            _ = subviews.apply(from: &from) { _, subview, stop in
                result = subview.data.id
                stop = true
            }
            return result
        }

        host.data.withCurrent {
            let graph = host.data.graph
            let sections = TupleView((
                Section {
                    Text("Row A")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                },
                Section {
                    Text("Row B")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
            ))
            let sectionsAttr = graph.makeInput(value: sections)
            var inputs = makeViewListInputs(graph: graph)
            inputs.formUnion(viewListOptions: .requiresSections)
            let outputs = type(of: sections)._makeViewList(
                view: _GraphValue(_attribute: sectionsAttr),
                inputs: inputs
            )
            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("section-list TupleView should produce a dynamic section-aware list")
                return
            }

            let (cache, _, _) = makeLazyCache(host: host, list: listAttr.value)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)

            var headerIDs: [_ViewList_ID] = []
            var rowIDs: [_ViewList_ID] = []
            var footerIDs: [_ViewList_ID] = []
            for section in lazyLayoutSections(in: subviews) {
                guard let headerID = firstID(in: section.header),
                      let id = firstID(in: section.content) else {
                    continue
                }
                headerIDs.append(headerID)
                rowIDs.append(id)
                if let footerID = firstID(in: section.footer) {
                    footerIDs.append(footerID)
                }
            }

            XCTAssertEqual(headerIDs.count, 2)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(footerIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [1, 1])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })
            XCTAssertTrue(headerIDs.allSatisfy(\.explicitIDs.isEmpty))
            XCTAssertTrue(footerIDs.allSatisfy(\.explicitIDs.isEmpty))
            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[0].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[0].reuseID,
                rowIDs[1].explicitIDs[0].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[0].owner, rowIDs[1].explicitIDs[0].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true,
                true,
            ])
            XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowGeneratedIDs)
        }
    }

    func testLazyLayoutSectionNodesFlattenNestedSectionContentIDStack() {
        let host = GraphHost()

        func ids(in subviews: _LazyLayout_Subviews) -> [_ViewList_ID] {
            var result: [_ViewList_ID] = []
            var from = 0
            _ = subviews.apply(from: &from) { _, subview, _ in
                result.append(subview.data.id)
            }
            return result
        }

        host.data.withCurrent {
            let graph = host.data.graph
            let sections = TupleView((
                Section {
                    Section {
                        Text("Nested Row")
                            .id("nested-row")
                    } header: {
                        Text("Nested Header")
                    } footer: {
                        Text("Nested Footer")
                    }
                    .id("nested-section")

                    Text("Outer Row")
                        .id("outer-row")
                } header: {
                    Text("Outer Header")
                } footer: {
                    Text("Outer Footer")
                }
                .id("outer-section"),
                Text("Tail")
            ))
            let sectionsAttr = graph.makeInput(value: sections)
            var inputs = makeViewListInputs(graph: graph)
            inputs.formUnion(viewListOptions: .requiresSections)
            let outputs = type(of: sections)._makeViewList(
                view: _GraphValue(_attribute: sectionsAttr),
                inputs: inputs
            )
            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("section-list TupleView should produce a dynamic section-aware list")
                return
            }

            let (cache, _, _) = makeLazyCache(host: host, list: listAttr.value)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)

            guard let section = lazyLayoutSections(in: subviews).first else {
                XCTFail("expected a lazy section node")
                return
            }

            let headerIDs = ids(in: section.header)
            let contentIDs = ids(in: section.content)
            let footerIDs = ids(in: section.footer)

            XCTAssertEqual(headerIDs.count, 1)
            XCTAssertEqual(footerIDs.count, 1)
            XCTAssertEqual(contentIDs.count, 4)
            var skippedFrom = 2
            var skippedContentIDs: [_ViewList_ID] = []
            _ = section.content.apply(from: &skippedFrom) { _, subview, _ in
                skippedContentIDs.append(subview.data.id)
            }
            XCTAssertEqual(skippedContentIDs, Array(contentIDs.dropFirst(2)))
            guard let headerID = headerIDs.first,
                  let footerID = footerIDs.first,
                  contentIDs.count == 4 else {
                return
            }

            XCTAssertEqual(headerID.explicitIDs.count, 1)
            XCTAssertEqual(headerID.explicitIDs[0].id, AnyHashable("outer-section"))
            XCTAssertFalse(headerID.explicitIDs[0].isUnary)
            XCTAssertEqual(footerID.explicitIDs, headerID.explicitIDs)

            let nestedHeader = contentIDs[0].explicitIDs
            let nestedRow = contentIDs[1].explicitIDs
            let nestedFooter = contentIDs[2].explicitIDs
            let outerRow = contentIDs[3].explicitIDs

            XCTAssertEqual(nestedHeader.count, 3)
            XCTAssertEqual(nestedHeader[0].id, AnyHashable("nested-section"))
            XCTAssertFalse(nestedHeader[0].isUnary)
            XCTAssertTrue(nestedHeader[1].id.base is UniqueID)
            XCTAssertFalse(nestedHeader[1].isUnary)
            XCTAssertEqual(nestedHeader[2].id, AnyHashable("outer-section"))
            XCTAssertFalse(nestedHeader[2].isUnary)
            XCTAssertEqual(nestedFooter, nestedHeader)

            XCTAssertEqual(nestedRow.count, 5)
            XCTAssertEqual(nestedRow[0].id, AnyHashable("nested-row"))
            XCTAssertTrue(nestedRow[0].isUnary)
            XCTAssertTrue(nestedRow[1].id.base is UniqueID)
            XCTAssertFalse(nestedRow[1].isUnary)
            XCTAssertEqual(nestedRow[2].id, AnyHashable("nested-section"))
            XCTAssertFalse(nestedRow[2].isUnary)
            XCTAssertEqual(nestedRow[3].id, nestedHeader[1].id)
            XCTAssertEqual(nestedRow[3].owner, nestedHeader[1].owner)
            XCTAssertEqual(nestedRow[3].reuseID, nestedHeader[1].reuseID)
            XCTAssertFalse(nestedRow[3].isUnary)
            XCTAssertEqual(nestedRow[4].id, AnyHashable("outer-section"))
            XCTAssertFalse(nestedRow[4].isUnary)

            XCTAssertEqual(outerRow.count, 3)
            XCTAssertEqual(outerRow[0].id, AnyHashable("outer-row"))
            XCTAssertTrue(outerRow[0].isUnary)
            XCTAssertEqual(outerRow[1].id, nestedHeader[1].id)
            XCTAssertEqual(outerRow[1].owner, nestedHeader[1].owner)
            XCTAssertEqual(outerRow[1].reuseID, nestedHeader[1].reuseID)
            XCTAssertFalse(outerRow[1].isUnary)
            XCTAssertEqual(outerRow[2].id, AnyHashable("outer-section"))
            XCTAssertFalse(outerRow[2].isUnary)
            XCTAssertNotEqual(nestedRow[1].id, nestedHeader[1].id)
        }
    }

    func testGroupSectionsAccumulatorBuildsExplicitAndImplicitConfigurations() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionCollectionRecorder()

        withCurrentTestSubgraph(host) {
            let root = Group(sections: TupleView((
                Section {
                    Text("Row")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                },
                Text("Tail")
            ))) { sections in
                SectionCollectionCaptureView(recorder: recorder, collection: sections)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .staticList = outputs.views else {
                XCTFail("Group(sections:) should preserve the transformed content output kind")
                return
            }

            XCTAssertEqual(recorder.sectionCount, 2)
            XCTAssertEqual(recorder.regionCounts, [
                SectionCollectionRecorder.RegionCounts(header: 1, content: 1, footer: 1),
                SectionCollectionRecorder.RegionCounts(header: 0, content: 1, footer: 0),
            ])
        }
    }

    func testGroupSectionsAccumulatorPropagatesContainerValues() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionContainerValuesRecorder()

        withCurrentTestSubgraph(host) {
            let root = Group(sections: TupleView((
                Section {
                    Text("Row")
                        .containerValue(\.lazySectionProbeValue, "row")
                } header: {
                    Text("Header")
                        .containerValue(\.lazySectionProbeValue, "header")
                } footer: {
                    Text("Footer")
                        .containerValue(\.lazySectionProbeValue, "footer")
                }
                .containerValue(\.lazySectionProbeValue, "section"),
                Text("Tail")
                    .containerValue(\.lazySectionProbeValue, "tail")
            ))) { sections in
                SectionContainerValuesCaptureView(recorder: recorder, collection: sections)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .staticList = outputs.views else {
                XCTFail("Group(sections:) should preserve the transformed content output kind")
                return
            }

            XCTAssertEqual(recorder.snapshots, [
                SectionContainerValuesRecorder.Snapshot(
                    section: "section",
                    header: "header",
                    content: "row",
                    footer: "footer"
                ),
                SectionContainerValuesRecorder.Snapshot(
                    section: "default",
                    header: "none",
                    content: "tail",
                    footer: "none"
                ),
            ])
        }
    }

    func testSectionAccumulatorRoutesEmptySectionTraitsToNativeOwners() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph

            func traits(_ value: String) -> ViewTraitCollection {
                var traits = ViewTraitCollection()
                traits[SectionAccumulatorProbeTraitKey.self] = value
                return traits
            }

            func entry(_ list: any ViewList) -> (
                list: any ViewList,
                attribute: Attribute<any ViewList>
            ) {
                (list, graph.makeInput(value: list))
            }

            func section(
                id: UInt32,
                rowCount: Int,
                trait: String
            ) -> any ViewList {
                let lists: [(
                    list: any ViewList,
                    attribute: Attribute<any ViewList>
                )]
                if rowCount == 0 {
                    lists = []
                } else {
                    lists = [
                        entry(EmptyViewList()),
                        entry(
                            BaseViewList(
                                elements: CountingViewListElements(
                                    count: rowCount
                                )
                            )
                        ),
                        entry(EmptyViewList()),
                    ]
                }
                return _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: lists),
                    traits: traits(trait),
                    isHierarchical: false
                )
            }

            let source: any ViewList = _ViewList_Group(
                lists: [
                    entry(section(id: 10, rowCount: 0, trait: "leading")),
                    entry(section(id: 11, rowCount: 1, trait: "first")),
                    entry(section(id: 12, rowCount: 0, trait: "trailing")),
                    entry(section(id: 13, rowCount: 1, trait: "second")),
                ]
            )
            let sourceAttribute = graph.makeInput(value: source)
            var accumulator = SectionAccumulator(
                contentSubgraph: nil,
                options: [],
                accumulationStrategy: .chunked
            )

            accumulator.formResult(
                from: source,
                listAttribute: sourceAttribute
            )

            XCTAssertEqual(accumulator.items.count, 2)
            XCTAssertEqual(
                accumulator.items[0].traits.map {
                    $0[SectionAccumulatorProbeTraitKey.self]
                },
                ["leading", "first", "trailing"]
            )
            XCTAssertEqual(
                accumulator.items[1].traits.map {
                    $0[SectionAccumulatorProbeTraitKey.self]
                },
                ["second"]
            )
            XCTAssertEqual(accumulator.items.map(\.count), [1, 1])
            XCTAssertEqual(accumulator.items.map(\.start), [0, 0])
            XCTAssertTrue(
                accumulator.items.allSatisfy {
                    $0.list is _ViewList_Section
                }
            )
            XCTAssertTrue(accumulator.pendingEmptySectionTraits.isEmpty)
            XCTAssertEqual(accumulator.viewCount, 2)
            XCTAssertEqual(accumulator.lastExplicitSectionEnd, 2)
        }
    }

    func testSectionAccumulatorDoesNotMaterializeAnEmptyImplicitItem() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let emptySection: any ViewList = _ViewList_Section()
            let source: any ViewList = _ViewList_Group(
                lists: [
                    (
                        emptySection,
                        graph.makeInput(value: emptySection)
                    )
                ]
            )
            let sourceAttribute = graph.makeInput(value: source)
            var accumulator = SectionAccumulator(
                contentSubgraph: nil,
                options: [],
                accumulationStrategy: .chunked
            )

            accumulator.formResult(
                from: source,
                listAttribute: sourceAttribute
            )

            XCTAssertTrue(accumulator.items.isEmpty)
            XCTAssertEqual(accumulator.viewCount, 0)
            XCTAssertEqual(accumulator.lastExplicitSectionEnd, 0)
        }
    }

    func testSectionAccumulatorKeepsUnsectionedNestedListAsOneChunk() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let first: any ViewList = BaseViewList(
                elements: CountingViewListElements(count: 1),
                implicitID: 4,
                traitKeys: ViewTraitKeys(),
                traits: ViewTraitCollection()
            )
            let second: any ViewList = BaseViewList(
                elements: CountingViewListElements(count: 2),
                implicitID: 8,
                traitKeys: ViewTraitKeys(),
                traits: ViewTraitCollection()
            )
            let nested: any ViewList = _ViewList_Group(
                lists: [
                    (first, graph.makeInput(value: first)),
                    (second, graph.makeInput(value: second)),
                ]
            )
            let nestedAttribute = graph.makeInput(value: nested)
            let source: any ViewList = SectionAccumulatorNestedList(
                base: nested,
                attribute: nestedAttribute
            )
            let sourceAttribute = graph.makeInput(value: source)
            var accumulator = SectionAccumulator(
                contentSubgraph: nil,
                options: [],
                accumulationStrategy: .chunked
            )

            accumulator.formResult(
                from: source,
                listAttribute: sourceAttribute
            )

            XCTAssertEqual(accumulator.items.count, 1)
            XCTAssertEqual(accumulator.items[0].count, 3)
            XCTAssertEqual(accumulator.items[0].ids.chunks.count, 1)
            XCTAssertEqual(accumulator.items[0].ids.chunks[0].count, 3)
            XCTAssertEqual(accumulator.items[0].ids.chunks[0].lowerBound, 0)
            XCTAssertEqual(accumulator.viewCount, 3)
        }
    }

    func testGroupSectionsSubviewIDsPreserveBaseViewListIDAndExplicitRowID() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = Group(sections: Section {
                Text("Row")
                    .id("row-id")
            } header: {
                Text("Header")
            } footer: {
                Text("Footer")
            }
            .id("section-id")) { sections in
                SectionIDCaptureView(recorder: recorder, collection: sections)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .staticList = outputs.views else {
                XCTFail("Group(sections:) should preserve the transformed content output kind")
                return
            }

            guard let snapshot = recorder.snapshots.first else {
                XCTFail("expected a captured section ID snapshot")
                return
            }
            XCTAssertEqual(recorder.snapshots.count, 1)
            XCTAssertEqual(snapshot.sectionIDMirrorLabels, ["base"])
            XCTAssertTrue(snapshot.sectionIDBase is UInt32)
            XCTAssertEqual(snapshot.rowIDMirrorLabels, ["base"])
            guard let rowID = snapshot.rowID else {
                XCTFail("expected a captured row _ViewList_ID")
                return
            }
            guard let headerID = snapshot.headerID,
                  let footerID = snapshot.footerID else {
                XCTFail("expected captured header/footer _ViewList_ID values")
                return
            }
            XCTAssertEqual(rowID.allExplicitIDs.compactMap { $0.base as? String }, [
                "row-id",
                "section-id",
            ])
            XCTAssertEqual(rowID.explicitIDs.count, 3)
            XCTAssertEqual(rowID.explicitIDs[0].id, AnyHashable("row-id"))
            XCTAssertTrue(rowID.explicitIDs[1].id.base is UniqueID)
            XCTAssertEqual(rowID.explicitIDs[2].id, AnyHashable("section-id"))
            XCTAssertEqual(
                rowID.explicitIDs[0].reuseID,
                Int(bitPattern: ObjectIdentifier(Text.self))
            )
            XCTAssertNotEqual(rowID.explicitIDs[2].reuseID, 0)
            XCTAssertEqual(rowID.explicitIDs.map(\.isUnary), [true, false, false])
            XCTAssertTrue(rowID.explicitIDs.allSatisfy { $0.owner != nil })
            XCTAssertNotEqual(rowID.explicitIDs[0].owner, rowID.explicitIDs[1].owner)
            XCTAssertEqual(rowID.canonicalID.explicitID, AnyHashable("row-id"))
            XCTAssertEqual(headerID.explicitIDs, Array(rowID.explicitIDs.suffix(1)))
            XCTAssertEqual(footerID.explicitIDs, Array(rowID.explicitIDs.suffix(1)))
            XCTAssertEqual(headerID.explicitIDs.map(\.isUnary), [false])
            XCTAssertEqual(footerID.explicitIDs.map(\.isUnary), [false])
            XCTAssertFalse(headerID.explicitIDs.contains { $0.id == AnyHashable("row-id") })
            XCTAssertFalse(footerID.explicitIDs.contains { $0.id == AnyHashable("row-id") })
        }
    }

    func testGroupSectionsSubviewIDsInstallGeneratedUniqueIDLanesWithoutRowID() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = Group(sections: Section {
                Text("Row")
            } header: {
                Text("Header")
            } footer: {
                Text("Footer")
            }
            .id("section-id")) { sections in
                SectionIDCaptureView(recorder: recorder, collection: sections)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .staticList = outputs.views else {
                XCTFail("Group(sections:) should preserve the transformed content output kind")
                return
            }

            guard let rowID = recorder.snapshots.first?.rowID else {
                XCTFail("expected a captured row _ViewList_ID")
                return
            }
            guard let headerID = recorder.snapshots.first?.headerID,
                  let footerID = recorder.snapshots.first?.footerID else {
                XCTFail("expected captured header/footer _ViewList_ID values")
                return
            }

            XCTAssertEqual(rowID.explicitIDs.count, 2)
            XCTAssertTrue(rowID.explicitIDs[0].id.base is UniqueID)
            XCTAssertEqual(rowID.explicitIDs[1].id, AnyHashable("section-id"))
            XCTAssertEqual(rowID.explicitIDs.map(\.isUnary), [true, false])
            XCTAssertTrue(rowID.explicitIDs.allSatisfy { $0.owner != nil })
            XCTAssertEqual(rowID.canonicalID.explicitID, rowID.explicitIDs[0].id)
            XCTAssertEqual(headerID.explicitIDs, Array(rowID.explicitIDs.suffix(1)))
            XCTAssertEqual(footerID.explicitIDs, Array(rowID.explicitIDs.suffix(1)))
            XCTAssertEqual(headerID.explicitIDs.map(\.isUnary), [false])
            XCTAssertEqual(footerID.explicitIDs.map(\.isUnary), [false])
        }
    }

    func testGroupSectionsSubviewIDsPreserveDirectTransformOrderAcrossSections() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = Group(sections: TupleView((
                Section {
                    Text("Row A")
                        .id("row-a")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                }
                .id("section-a"),
                Section {
                    Text("Row B")
                        .id("row-b")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
                .id("section-b")
            ))) { sections in
                SectionIDCaptureView(recorder: recorder, collection: sections)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .staticList = outputs.views else {
                XCTFail("Group(sections:) should preserve the transformed content output kind")
                return
            }

            let rowIDs = recorder.snapshots.compactMap(\.rowID)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [3, 3])
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[0].id.base as? String }, ["row-a", "row-b"])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[1].id.base is UniqueID })
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[2].id.base as? String }, ["section-a", "section-b"])

            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[1].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[1].reuseID,
                rowIDs[1].explicitIDs[1].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[1].owner, rowIDs[1].explicitIDs[1].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true, false, false,
                true, false, false,
            ])
        }
    }

    func testGroupSectionsGeneratedOnlySubviewIDsUseDirectCanonicalRows() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = Group(sections: TupleView((
                Section {
                    Text("Row A")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                }
                .id("section-a"),
                Section {
                    Text("Row B")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
                .id("section-b")
            ))) { sections in
                SectionIDCaptureView(recorder: recorder, collection: sections)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .staticList = outputs.views else {
                XCTFail("Group(sections:) should preserve the transformed content output kind")
                return
            }

            let rowIDs = recorder.snapshots.compactMap(\.rowID)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [2, 2])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[1].id.base as? String }, ["section-a", "section-b"])

            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[0].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[0].reuseID,
                rowIDs[1].explicitIDs[0].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[0].owner, rowIDs[1].explicitIDs[0].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true, false,
                true, false,
            ])
            XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowGeneratedIDs)
        }
    }

    func testGroupSectionsPlainSubviewIDsKeepOnlyRowTransforms() {
        let host = GraphHost()
        let graph = host.data.graph

        withCurrentTestSubgraph(host) {
            do {
                let recorder = SectionIDRecorder()
                let root = Group(sections: TupleView((
                    Section {
                        Text("Row A")
                            .id("row-a")
                    } header: {
                        Text("Header A")
                    } footer: {
                        Text("Footer A")
                    },
                    Section {
                        Text("Row B")
                            .id("row-b")
                    } header: {
                        Text("Header B")
                    } footer: {
                        Text("Footer B")
                    }
                ))) { sections in
                    SectionIDCaptureView(recorder: recorder, collection: sections)
                }

                let rootAttr = graph.makeInput(value: root)
                let outputs = type(of: root)._makeViewList(
                    view: _GraphValue(_attribute: rootAttr),
                    inputs: makeViewListInputs(graph: graph)
                )

                guard case .staticList = outputs.views else {
                    XCTFail("Group(sections:) should preserve the transformed content output kind")
                    return
                }

                let rowIDs = recorder.snapshots.compactMap(\.rowID)
                XCTAssertEqual(rowIDs.count, 2)
                XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [2, 2])
                XCTAssertEqual(rowIDs.map { $0.explicitIDs[0].id.base as? String }, ["row-a", "row-b"])
                XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[1].id.base is UniqueID })
                XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                    true, false,
                    true, false,
                ])
                XCTAssertNotEqual(rowIDs[0].explicitIDs[1].id, rowIDs[1].explicitIDs[1].id)
            }

            do {
                let recorder = SectionIDRecorder()
                let root = Group(sections: TupleView((
                    Section {
                        Text("Row A")
                    } header: {
                        Text("Header A")
                    } footer: {
                        Text("Footer A")
                    },
                    Section {
                        Text("Row B")
                    } header: {
                        Text("Header B")
                    } footer: {
                        Text("Footer B")
                    }
                ))) { sections in
                    SectionIDCaptureView(recorder: recorder, collection: sections)
                }

                let rootAttr = graph.makeInput(value: root)
                let outputs = type(of: root)._makeViewList(
                    view: _GraphValue(_attribute: rootAttr),
                    inputs: makeViewListInputs(graph: graph)
                )

                guard case .staticList = outputs.views else {
                    XCTFail("Group(sections:) should preserve the transformed content output kind")
                    return
                }

                let rowIDs = recorder.snapshots.compactMap(\.rowID)
                XCTAssertEqual(rowIDs.count, 2)
                XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [1, 1])
                XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })
                XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                    true,
                    true,
                ])
                XCTAssertNotEqual(rowIDs[0].explicitIDs[0].id, rowIDs[1].explicitIDs[0].id)
                XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowIDs.map { $0.explicitIDs[0].id })
            }
        }
    }

    func testSectionDirectIDShapeExtendsAcrossThreeSections() {
        // ASSERTIONS sectionStaticTransformOutputKindObserved
        let host = GraphHost()
        let graph = host.data.graph

        withCurrentTestSubgraph(host) {
            do {
                let recorder = SectionIDRecorder()
                let root = Group(sections: TupleView((
                    Section {
                        Text("Row A")
                            .id("row-a")
                    } header: {
                        Text("Header A")
                    } footer: {
                        Text("Footer A")
                    },
                    Section {
                        Text("Row B")
                            .id("row-b")
                    } header: {
                        Text("Header B")
                    } footer: {
                        Text("Footer B")
                    },
                    Section {
                        Text("Row C")
                            .id("row-c")
                    } header: {
                        Text("Header C")
                    } footer: {
                        Text("Footer C")
                    }
                ))) { sections in
                    SectionIDCaptureView(recorder: recorder, collection: sections)
                }

                materializeViewList(root, graph: graph)

                let rowIDs = recorder.snapshots.compactMap(\.rowID)
                XCTAssertEqual(rowIDs.count, 3)
                XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [2, 2, 2])
                XCTAssertEqual(rowIDs.map { $0.explicitIDs[0].id.base as? String }, ["row-a", "row-b", "row-c"])
                XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[1].id.base is UniqueID })
                XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                    true, false,
                    true, false,
                    true, false,
                ])
                XCTAssertEqual(Set(rowIDs.map { $0.explicitIDs[1].id }).count, 3)
            }

            do {
                let recorder = SectionIDRecorder()
                let root = Group(sections: TupleView((
                    Section {
                        Text("Row A")
                    } header: {
                        Text("Header A")
                    } footer: {
                        Text("Footer A")
                    }
                    .id("section-a"),
                    Section {
                        Text("Row B")
                    } header: {
                        Text("Header B")
                    } footer: {
                        Text("Footer B")
                    }
                    .id("section-b"),
                    Section {
                        Text("Row C")
                    } header: {
                        Text("Header C")
                    } footer: {
                        Text("Footer C")
                    }
                    .id("section-c")
                ))) { sections in
                    SectionIDCaptureView(recorder: recorder, collection: sections)
                }

                materializeViewList(root, graph: graph)

                let rowIDs = recorder.snapshots.compactMap(\.rowID)
                XCTAssertEqual(rowIDs.count, 3)
                XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [2, 2, 2])
                XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })
                XCTAssertEqual(rowIDs.map { $0.explicitIDs[1].id.base as? String }, ["section-a", "section-b", "section-c"])
                XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                    true, false,
                    true, false,
                    true, false,
                ])
                XCTAssertEqual(Set(rowIDs.map { $0.explicitIDs[0].id }).count, 3)
                XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowIDs.map { $0.explicitIDs[0].id })
            }

            do {
                let recorder = SectionIDRecorder()
                let root = ForEach(sections: TupleView((
                    Section {
                        Text("Row A")
                    } header: {
                        Text("Header A")
                    } footer: {
                        Text("Footer A")
                    },
                    Section {
                        Text("Row B")
                    } header: {
                        Text("Header B")
                    } footer: {
                        Text("Footer B")
                    },
                    Section {
                        Text("Row C")
                    } header: {
                        Text("Header C")
                    } footer: {
                        Text("Footer C")
                    }
                ))) { section in
                    SectionConfigurationIDCaptureView(recorder: recorder, section: section)
                }

                materializeViewList(root, graph: graph)

                let rowIDs = recorder.snapshots.compactMap(\.rowID)
                XCTAssertEqual(rowIDs.count, 3)
                XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [1, 1, 1])
                XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })
                XCTAssertTrue(rowIDs.flatMap(\.explicitIDs).allSatisfy(\.isUnary))
                XCTAssertEqual(Set(rowIDs.map { $0.explicitIDs[0].id }).count, 3)
                XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowIDs.map { $0.explicitIDs[0].id })
            }

            do {
                let recorder = SectionIDRecorder()
                let root = ForEach(sections: TupleView((
                    Section {
                        Text("Row A")
                            .id("row-a")
                    } header: {
                        Text("Header A")
                    } footer: {
                        Text("Footer A")
                    }
                    .id("section-a"),
                    Section {
                        Text("Row B")
                            .id("row-b")
                    } header: {
                        Text("Header B")
                    } footer: {
                        Text("Footer B")
                    }
                    .id("section-b"),
                    Section {
                        Text("Row C")
                            .id("row-c")
                    } header: {
                        Text("Header C")
                    } footer: {
                        Text("Footer C")
                    }
                    .id("section-c")
                ))) { section in
                    SectionConfigurationIDCaptureView(recorder: recorder, section: section)
                }

                materializeViewList(root, graph: graph)

                let rowIDs = recorder.snapshots.compactMap(\.rowID)
                XCTAssertEqual(rowIDs.count, 3)
                XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [3, 3, 3])
                XCTAssertEqual(rowIDs.map { $0.explicitIDs[0].id.base as? String }, ["row-a", "row-b", "row-c"])
                XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[1].id.base is UniqueID })
                XCTAssertEqual(rowIDs.map { $0.explicitIDs[2].id.base as? String }, ["section-a", "section-b", "section-c"])
                XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                    true, false, false,
                    true, false, false,
                    true, false, false,
                ])
                XCTAssertEqual(Set(rowIDs.map { $0.explicitIDs[1].id }).count, 3)
            }
        }
    }

    func testNestedSectionSubviewIDsFlattenIntoOuterContentRegion() {
        // ASSERTIONS sectionStaticTransformOutputKindObserved
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = Group(sections: Section {
                Section {
                    Text("Nested Row")
                        .id("nested-row")
                } header: {
                    Text("Nested Header")
                } footer: {
                    Text("Nested Footer")
                }
                .id("nested-section")

                Text("Outer Row")
                    .id("outer-row")
            } header: {
                Text("Outer Header")
            } footer: {
                Text("Outer Footer")
            }
            .id("outer-section")) { sections in
                SectionIDCaptureView(recorder: recorder, collection: sections)
            }

            materializeViewList(root, graph: graph)

            guard let snapshot = recorder.snapshots.first else {
                XCTFail("expected one captured nested section snapshot")
                return
            }
            XCTAssertEqual(recorder.snapshots.count, 1)
            XCTAssertEqual(snapshot.contentIDs.count, 4)

            guard let headerID = snapshot.headerID,
                  let footerID = snapshot.footerID else {
                XCTFail("expected outer header/footer IDs")
                return
            }
            let contentIDs = snapshot.contentIDs
            XCTAssertEqual(headerID.explicitIDs.count, 1)
            XCTAssertEqual(headerID.explicitIDs[0].id, AnyHashable("outer-section"))
            XCTAssertFalse(headerID.explicitIDs[0].isUnary)
            XCTAssertEqual(footerID.explicitIDs, headerID.explicitIDs)

            let nestedHeader = contentIDs[0].explicitIDs
            let nestedRow = contentIDs[1].explicitIDs
            let nestedFooter = contentIDs[2].explicitIDs
            let outerRow = contentIDs[3].explicitIDs

            XCTAssertEqual(nestedHeader.count, 3)
            XCTAssertEqual(nestedHeader[0].id, AnyHashable("nested-section"))
            XCTAssertFalse(nestedHeader[0].isUnary)
            XCTAssertTrue(nestedHeader[1].id.base is UniqueID)
            XCTAssertFalse(nestedHeader[1].isUnary)
            XCTAssertEqual(nestedHeader[2].id, AnyHashable("outer-section"))
            XCTAssertFalse(nestedHeader[2].isUnary)
            XCTAssertEqual(nestedFooter, nestedHeader)

            XCTAssertEqual(nestedRow.count, 5)
            XCTAssertEqual(nestedRow[0].id, AnyHashable("nested-row"))
            XCTAssertTrue(nestedRow[0].isUnary)
            XCTAssertTrue(nestedRow[1].id.base is UniqueID)
            XCTAssertFalse(nestedRow[1].isUnary)
            XCTAssertEqual(nestedRow[2].id, AnyHashable("nested-section"))
            XCTAssertFalse(nestedRow[2].isUnary)
            XCTAssertEqual(nestedRow[3].id, nestedHeader[1].id)
            XCTAssertEqual(nestedRow[3].owner, nestedHeader[1].owner)
            XCTAssertEqual(nestedRow[3].reuseID, nestedHeader[1].reuseID)
            XCTAssertFalse(nestedRow[3].isUnary)
            XCTAssertEqual(nestedRow[4].id, AnyHashable("outer-section"))
            XCTAssertFalse(nestedRow[4].isUnary)

            XCTAssertEqual(outerRow.count, 3)
            XCTAssertEqual(outerRow[0].id, AnyHashable("outer-row"))
            XCTAssertTrue(outerRow[0].isUnary)
            XCTAssertEqual(outerRow[1].id, nestedHeader[1].id)
            XCTAssertEqual(outerRow[1].owner, nestedHeader[1].owner)
            XCTAssertEqual(outerRow[1].reuseID, nestedHeader[1].reuseID)
            XCTAssertFalse(outerRow[1].isUnary)
            XCTAssertEqual(outerRow[2].id, AnyHashable("outer-section"))
            XCTAssertFalse(outerRow[2].isUnary)

            XCTAssertNotEqual(nestedRow[1].id, nestedHeader[1].id)
            XCTAssertNotEqual(nestedRow[1].owner, nestedHeader[1].owner)
        }
    }

    func testForEachSectionsBuildsContentFromSectionConfigurations() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionCollectionRecorder()

        withCurrentTestSubgraph(host) {
            let root = ForEach(sections: TupleView((
                Section {
                    Text("Row")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                },
                Text("Tail")
            ))) { section in
                SectionConfigurationCaptureView(recorder: recorder, section: section)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("ForEach(sections:) should route through a dynamic section collection list")
                return
            }

            materializeAllItems(in: listAttr)
            XCTAssertEqual(listAttr.value.count(style: _ViewList_IteratorStyle()), 2)
            XCTAssertEqual(recorder.sectionCount, 2)
            XCTAssertEqual(recorder.regionCounts, [
                SectionCollectionRecorder.RegionCounts(header: 1, content: 1, footer: 1),
                SectionCollectionRecorder.RegionCounts(header: 0, content: 1, footer: 0),
            ])
        }
    }

    func testForEachSectionsPropagatesContainerValuesToContentClosure() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionContainerValuesRecorder()

        withCurrentTestSubgraph(host) {
            let root = ForEach(sections: TupleView((
                Section {
                    Text("Row")
                        .containerValue(\.lazySectionProbeValue, "row")
                } header: {
                    Text("Header")
                        .containerValue(\.lazySectionProbeValue, "header")
                } footer: {
                    Text("Footer")
                        .containerValue(\.lazySectionProbeValue, "footer")
                }
                .containerValue(\.lazySectionProbeValue, "section"),
                Text("Tail")
                    .containerValue(\.lazySectionProbeValue, "tail")
            ))) { section in
                SectionConfigurationValuesCaptureView(recorder: recorder, section: section)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("ForEach(sections:) should route through a dynamic section collection list")
                return
            }

            materializeAllItems(in: listAttr)
            XCTAssertEqual(listAttr.value.count(style: _ViewList_IteratorStyle()), 2)
            XCTAssertEqual(recorder.snapshots, [
                SectionContainerValuesRecorder.Snapshot(
                    section: "section",
                    header: "header",
                    content: "row",
                    footer: "footer"
                ),
                SectionContainerValuesRecorder.Snapshot(
                    section: "default",
                    header: "none",
                    content: "tail",
                    footer: "none"
                ),
            ])
        }
    }

    func testForEachSectionsSubviewIDsForwardDirectTransformOrder() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = ForEach(sections: TupleView((
                Section {
                    Text("Row A")
                        .id("row-a")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                }
                .id("section-a"),
                Section {
                    Text("Row B")
                        .id("row-b")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
                .id("section-b")
            ))) { section in
                SectionConfigurationIDCaptureView(recorder: recorder, section: section)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("ForEach(sections:) should route through a dynamic section collection list")
                return
            }

            materializeAllItems(in: listAttr)
            let rowIDs = recorder.snapshots.compactMap(\.rowID)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [3, 3])
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[0].id.base as? String }, ["row-a", "row-b"])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[1].id.base is UniqueID })
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[2].id.base as? String }, ["section-a", "section-b"])

            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[1].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[1].reuseID,
                rowIDs[1].explicitIDs[1].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[1].owner, rowIDs[1].explicitIDs[1].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true, false, false,
                true, false, false,
            ])
        }
    }

    func testForEachSectionsGeneratedOnlySubviewIDsForwardCanonicalRows() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = ForEach(sections: TupleView((
                Section {
                    Text("Row A")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                }
                .id("section-a"),
                Section {
                    Text("Row B")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
                .id("section-b")
            ))) { section in
                SectionConfigurationIDCaptureView(recorder: recorder, section: section)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("ForEach(sections:) should route through a dynamic section collection list")
                return
            }

            materializeAllItems(in: listAttr)
            let rowIDs = recorder.snapshots.compactMap(\.rowID)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [2, 2])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[1].id.base as? String }, ["section-a", "section-b"])

            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[0].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[0].reuseID,
                rowIDs[1].explicitIDs[0].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[0].owner, rowIDs[1].explicitIDs[0].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true, false,
                true, false,
            ])
            XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowGeneratedIDs)
        }
    }

    func testForEachSectionsPlainSubviewIDsForwardOnlyRowTransforms() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = ForEach(sections: TupleView((
                Section {
                    Text("Row A")
                        .id("row-a")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                },
                Section {
                    Text("Row B")
                        .id("row-b")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
            ))) { section in
                SectionConfigurationIDCaptureView(recorder: recorder, section: section)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("ForEach(sections:) should route through a dynamic section collection list")
                return
            }

            materializeAllItems(in: listAttr)
            let rowIDs = recorder.snapshots.compactMap(\.rowID)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [2, 2])
            XCTAssertEqual(rowIDs.map { $0.explicitIDs[0].id.base as? String }, ["row-a", "row-b"])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[1].id.base is UniqueID })
            XCTAssertTrue(rowIDs.flatMap(\.explicitIDs).allSatisfy { $0.id.base as? String != "section-a" })
            XCTAssertTrue(rowIDs.flatMap(\.explicitIDs).allSatisfy { $0.id.base as? String != "section-b" })

            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[1].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[1].reuseID,
                rowIDs[1].explicitIDs[1].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[1].owner, rowIDs[1].explicitIDs[1].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true, false,
                true, false,
            ])
        }
    }

    func testForEachSectionsPlainGeneratedOnlySubviewIDsForwardCanonicalRows() {
        let host = GraphHost()
        let graph = host.data.graph
        let recorder = SectionIDRecorder()

        withCurrentTestSubgraph(host) {
            let root = ForEach(sections: TupleView((
                Section {
                    Text("Row A")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                },
                Section {
                    Text("Row B")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
            ))) { section in
                SectionConfigurationIDCaptureView(recorder: recorder, section: section)
            }

            let rootAttr = graph.makeInput(value: root)
            let outputs = type(of: root)._makeViewList(
                view: _GraphValue(_attribute: rootAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("ForEach(sections:) should route through a dynamic section collection list")
                return
            }

            materializeAllItems(in: listAttr)
            let rowIDs = recorder.snapshots.compactMap(\.rowID)
            XCTAssertEqual(rowIDs.count, 2)
            XCTAssertEqual(rowIDs.map { $0.explicitIDs.count }, [1, 1])
            XCTAssertTrue(rowIDs.allSatisfy { $0.explicitIDs[0].id.base is UniqueID })

            let rowGeneratedIDs = rowIDs.map { $0.explicitIDs[0].id }
            XCTAssertNotEqual(rowGeneratedIDs[0], rowGeneratedIDs[1])
            XCTAssertEqual(
                rowIDs[0].explicitIDs[0].reuseID,
                rowIDs[1].explicitIDs[0].reuseID
            )
            XCTAssertNotEqual(rowIDs[0].explicitIDs[0].owner, rowIDs[1].explicitIDs[0].owner)
            XCTAssertEqual(rowIDs.flatMap { $0.explicitIDs.map(\.isUnary) }, [
                true,
                true,
            ])
            XCTAssertEqual(rowIDs.map { $0.canonicalID.explicitID }, rowGeneratedIDs)
        }
    }

    func testLazyLayoutRootPropagatesSectionListOptionsToContent() {
        let host = GraphHost()
        let recorder = ViewListOptionsRecorder()

        host.data.withCurrent {
            let graph = host.data.graph
            let tree = _VariadicView.Tree(
                root: LazyVStackLayout(
                    base: _VStackLayout(alignment: .center, spacing: nil),
                    pinnedViews: []
                ),
                content: ViewListOptionsCaptureView(recorder: recorder)
            )
            let treeAttr = graph.makeInput(value: tree)
            _ = type(of: tree)._makeView(
                view: _GraphValue(_attribute: treeAttr),
                inputs: makeViewInputs(graph: graph)
            )
            XCTAssertEqual(
                recorder.options.intersection(.requiresSections),
                .requiresSections
            )
        }
    }

    func testSectionListVariadicChildrenExposeCanonicalImplicitIDs() {
        let host = GraphHost()
        let recorder = SectionListVariadicIDRecorder()

        withCurrentTestSubgraph(host) {
            let graph = host.data.graph
            let tree = _VariadicView.Tree(
                SectionListVariadicIDCaptureRoot(recorder: recorder)
            ) {
                Section {
                    Text("Row A")
                } header: {
                    Text("Header A")
                } footer: {
                    Text("Footer A")
                }

                Section {
                    Text("Row B")
                } header: {
                    Text("Header B")
                } footer: {
                    Text("Footer B")
                }
            }
            let treeAttr = graph.makeInput(value: tree)
            _ = type(of: tree)._makeViewList(
                view: _GraphValue(_attribute: treeAttr),
                inputs: makeViewListInputs(graph: graph)
            )

            XCTAssertEqual(recorder.ids.count, 6)
            XCTAssertEqual(
                [0, 2, 3, 5].compactMap {
                    (recorder.ids[$0].base as? _ViewList_ID.Canonical)?.implicitID
                },
                [0, 1, 2, 3]
            )
            XCTAssertTrue(recorder.ids[1].base is UniqueID)
            XCTAssertTrue(recorder.ids[4].base is UniqueID)
        }
    }

    func testTupleViewSectionListOptionsSurfaceDirectSectionNodes() {
        let host = GraphHost()
        let graph = host.data.graph

        withCurrentTestSubgraph(host) {
            let tuple = TupleView((
                Section {
                    Text("Row")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                },
                Text("Tail")
            ))
            let tupleAttr = graph.makeInput(value: tuple)
            var inputs = makeViewListInputs(graph: graph)
            inputs.formUnion(viewListOptions: .requiresSections)
            let outputs = type(of: tuple)._makeViewList(
                view: _GraphValue(_attribute: tupleAttr),
                inputs: inputs
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("section-list TupleView should produce a dynamic section-aware list")
                return
            }

            guard let group = listAttr.value as? _ViewList_Group else {
                XCTFail("TupleView should preserve the native group envelope")
                return
            }

            var from = 0
            var nodes: [_ViewList_Node] = []
            _ = group.applyNodes(
                from: &from,
                style: _ViewList_IteratorStyle(),
                transform: _ViewList_TemporarySublistTransform()
            ) { _, _, node, _ in
                nodes.append(node)
                return true
            }

            XCTAssertEqual(nodes.count, 2)
            guard case .section(let section) = nodes.first else {
                XCTFail("first TupleView child should be surfaced as a section node")
                return
            }
            XCTAssertEqual(section.header?.list.count(style: _ViewList_IteratorStyle()), 1)
            XCTAssertEqual(section.content?.list.count(style: _ViewList_IteratorStyle()), 1)
            XCTAssertEqual(section.footer?.list.count(style: _ViewList_IteratorStyle()), 1)
            guard case .sublist(let tail)? = nodes.dropFirst().first else {
                XCTFail("non-section TupleView child should remain a sublist")
                return
            }
            XCTAssertEqual(tail.count, 1)
        }
    }

    func testLazyLayoutSubviewsApplyNodesSurfacesSectionNodes() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let tuple = TupleView((
                Section {
                    Text("Row")
                } header: {
                    Text("Header")
                } footer: {
                    Text("Footer")
                },
                Text("Tail")
            ))
            let tupleAttr = graph.makeInput(value: tuple)
            var inputs = makeViewListInputs(graph: graph)
            inputs.formUnion(viewListOptions: .requiresSections)
            let outputs = type(of: tuple)._makeViewList(
                view: _GraphValue(_attribute: tupleAttr),
                inputs: inputs
            )

            guard case .dynamicList(let listAttr, _) = outputs.views else {
                XCTFail("section-list TupleView should produce a dynamic section-aware list")
                return
            }

            let (cache, _, _) = makeLazyCache(host: host, list: listAttr.value)
            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)

            var observed: [SectionCollectionRecorder.RegionCounts] = []
            for node in flattenedLazyLayoutNodes(in: subviews) {
                switch node {
                case .section(let section):
                    observed.append(SectionCollectionRecorder.RegionCounts(
                        header: section.header.estimatedCount(),
                        content: section.content.estimatedCount(),
                        footer: section.footer.estimatedCount()
                    ))
                case .subviews(let child):
                    observed.append(SectionCollectionRecorder.RegionCounts(
                        header: 0,
                        content: child.estimatedCount(),
                        footer: 0
                    ))
                }
            }
            XCTAssertEqual(observed, [
                SectionCollectionRecorder.RegionCounts(header: 1, content: 1, footer: 1),
                SectionCollectionRecorder.RegionCounts(header: 0, content: 1, footer: 0),
            ])
        }
    }

    func testStackPlacementMeasureBackwardsRewindsGroupedSubviews() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 20, height: 30),
                CGSize(width: 25, height: 40),
                CGSize(width: 30, height: 50),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes)
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            var from = 0
            var groups: [[_LazyLayout_Subview]] = []
            XCTAssertTrue(subviews.apply(from: &from) { _, subview, _ in
                groups.append([subview])
            })
            XCTAssertEqual(groups.map { $0.map(\.index) }, [[0], [1], [2]])

            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 5),
                pinnedViews: []
            )
            var placement = StackPlacement(
                stack: layout,
                axis: .vertical,
                minor: MinorProperties(count: 1, size: 80, geometry: 80),
                visible: CGFloat(0)..<CGFloat(160),
                index: 42,
                position: -10,
                stoppingCondition: .index(42),
                currentSubviews: groups[1],
                lastSubviews: groups[2],
                placedSubviews: [
                    _LazyLayout_PlacedSubview(
                        item: cache.item(data: makeLazyData(graph: graph, id: _ViewList_ID(implicitID: 10))),
                        placement: _Placement(proposedSize: CGSize(width: 1, height: 1)),
                        index: 10
                    ),
                ],
                placedIndex: (min: 10, max: 10),
                placedPosition: (min: 20, max: 21),
                placedQuery: (min: 22, max: 23),
                wasCancelled: true,
                estimations: EstimationCache(lengthToCount: [99: 1])
            )

            placement.measureBackwards(
                subviews: groups,
                lastIndex: 3,
                lastPosition: 137,
                atStart: true,
                atEnd: true,
                allowBeforeFirst: true
            )

            XCTAssertFalse(placement.skipFirst)
            XCTAssertTrue(placement.currentSubviews.isEmpty)
            XCTAssertEqual(placement.lastSubviews?.map(\.index), [0])
            XCTAssertTrue(placement.placedSubviews.isEmpty)
            XCTAssertEqual(placement.placedIndex.min, Int.max)
            XCTAssertEqual(placement.placedIndex.max, Int.min)
            XCTAssertEqual(placement.placedPosition.min, CGFloat.infinity)
            XCTAssertEqual(placement.placedPosition.max, -CGFloat.infinity)
            XCTAssertEqual(placement.placedQuery.min, CGFloat.infinity)
            XCTAssertEqual(placement.placedQuery.max, -CGFloat.infinity)
            XCTAssertFalse(placement.wasCancelled)
            XCTAssertTrue(placement.estimations.lengthToCount.isEmpty)
            XCTAssertEqual(placement.index, 0)
            XCTAssertEqual(placement.position, 7)
        }
    }

    func testLazyStackCacheResolveIndexAndPositionUsesEstimateAndBackwardsMeasurement() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 20, height: 30),
                CGSize(width: 25, height: 40),
                CGSize(width: 30, height: 50),
                CGSize(width: 35, height: 60),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes)
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 5),
                pinnedViews: []
            )
            var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                estimations: EstimationCache(
                    lengthToCount: [25: 1],
                    spacingToCount: [0: 1]
                )
            )

            let resolved = stackCache.resolveIndexAndPosition(
                stack: layout,
                subviews: subviews,
                visible: CGFloat(70)..<CGFloat(180),
                minor: MinorProperties(count: 1, size: 80, geometry: 80)
            )

            XCTAssertEqual(resolved.index, 1)
            XCTAssertEqual(resolved.position, 30)
            XCTAssertEqual(stackCache.minor?.count, 1)
            XCTAssertEqual(stackCache.visibleExtent, CGFloat(70)..<CGFloat(180))
            XCTAssertEqual(stackCache.estimations.lengthToCount[25], 1)
            XCTAssertEqual(stackCache.estimations.spacingToCount[0], 1)
        }
    }

    func testLazyStackCacheResolveIndexAndPositionTraversesSectionNodes() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            let header = makeRegion([CGSize(width: 20, height: 30)])
            let content = makeRegion([
                CGSize(width: 25, height: 40),
                CGSize(width: 30, height: 50),
            ])
            let footer = makeRegion([CGSize(width: 35, height: 60)])
            let list: any ViewList = _ViewList_Section(
                id: 7,
                base: _ViewList_Group(lists: [header, content, footer])
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 5),
                pinnedViews: []
            )
            var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                estimations: EstimationCache(
                    lengthToCount: [25: 1],
                    spacingToCount: [0: 1]
                )
            )

            let resolved = stackCache.resolveIndexAndPosition(
                stack: layout,
                subviews: subviews,
                visible: CGFloat(70)..<CGFloat(180),
                minor: MinorProperties(count: 1, size: 80, geometry: 80)
            )

            XCTAssertEqual(resolved.index, 1)
            XCTAssertEqual(resolved.position, 30)
            XCTAssertEqual(stackCache.minor?.count, 1)
            XCTAssertEqual(stackCache.visibleExtent, CGFloat(70)..<CGFloat(180))
            XCTAssertEqual(stackCache.estimations.lengthToCount[25], 1)
            XCTAssertEqual(stackCache.estimations.spacingToCount[0], 1)
        }
    }

    func testLazyStackCacheResolveIndexAndPositionTraversesNestedSectionNodes() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            let nestedHeader = makeRegion([CGSize(width: 25, height: 40)])
            let nestedContent = makeRegion([CGSize(width: 30, height: 50)])
            let nestedFooter = makeRegion([CGSize(width: 35, height: 60)])
            let nestedSectionList: any ViewList = _ViewList_Section(
                id: 8,
                base: _ViewList_Group(lists: [nestedHeader, nestedContent, nestedFooter])
            )
            let nestedSection = (
                list: nestedSectionList,
                attribute: graph.makeInput(value: nestedSectionList)
            )

            let outerHeader = makeRegion([CGSize(width: 20, height: 30)])
            let outerFooter = makeRegion([CGSize(width: 40, height: 70)])
            let list: any ViewList = _ViewList_Section(
                id: 7,
                base: _ViewList_Group(lists: [outerHeader, nestedSection, outerFooter])
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 5),
                pinnedViews: []
            )
            var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                estimations: EstimationCache(
                    lengthToCount: [25: 1],
                    spacingToCount: [0: 1]
                )
            )

            let resolved = stackCache.resolveIndexAndPosition(
                stack: layout,
                subviews: subviews,
                visible: CGFloat(90)..<CGFloat(220),
                minor: MinorProperties(count: 1, size: 80, geometry: 80)
            )

            XCTAssertEqual(resolved.index, 2)
            XCTAssertEqual(resolved.position, 75)
        }
    }

    func testLazyStackCacheResolveIndexAndPositionTraversesMultipleSections() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerHeight: CGFloat,
                contentHeights: [CGFloat],
                footerHeight: CGFloat
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion([CGSize(width: 20, height: headerHeight)])
                let content = makeRegion(contentHeights.map { CGSize(width: 20, height: $0) })
                let footer = makeRegion([CGSize(width: 20, height: footerHeight)])
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let section0 = makeSection(
                id: 0,
                headerHeight: 30,
                contentHeights: [40, 50],
                footerHeight: 20
            )
            let section1 = makeSection(
                id: 1,
                headerHeight: 30,
                contentHeights: [35, 45],
                footerHeight: 25
            )
            let section2 = makeSection(
                id: 2,
                headerHeight: 30,
                contentHeights: [50, 40],
                footerHeight: 20
            )
            let section3 = makeSection(
                id: 3,
                headerHeight: 30,
                contentHeights: [60, 30],
                footerHeight: 35
            )
            let list: any ViewList = _ViewList_Group(lists: [section0, section1, section2, section3])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 0),
                pinnedViews: []
            )
            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyVStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [25: 1],
                        spacingToCount: [0: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 120),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (65, 1, 30),
                (120, 3, 120),
                (140, 4, 140),
                (170, 5, 170),
                (205, 6, 205),
                (250, 7, 250),
                (260, 7, 250),
                (275, 8, 275),
                (305, 9, 305),
                (355, 10, 355),
                (395, 11, 395),
                (405, 11, 395),
                (415, 12, 415),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 120),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionTraversesHorizontalMultipleSections() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerWidth: CGFloat,
                contentWidths: [CGFloat],
                footerWidth: CGFloat
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion([CGSize(width: headerWidth, height: 20)])
                let content = makeRegion(contentWidths.map { CGSize(width: $0, height: 20) })
                let footer = makeRegion([CGSize(width: footerWidth, height: 20)])
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let section0 = makeSection(
                id: 0,
                headerWidth: 30,
                contentWidths: [40, 50],
                footerWidth: 20
            )
            let section1 = makeSection(
                id: 1,
                headerWidth: 30,
                contentWidths: [35, 45],
                footerWidth: 25
            )
            let section2 = makeSection(
                id: 2,
                headerWidth: 30,
                contentWidths: [50, 40],
                footerWidth: 20
            )
            let section3 = makeSection(
                id: 3,
                headerWidth: 30,
                contentWidths: [60, 30],
                footerWidth: 35
            )
            let list: any ViewList = _ViewList_Group(lists: [section0, section1, section2, section3])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyHStackLayout(
                base: _HStackLayout(alignment: .top, spacing: 0),
                pinnedViews: []
            )
            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyHStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyHStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [25: 1],
                        spacingToCount: [0: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 120),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (65, 1, 30),
                (120, 3, 120),
                (140, 4, 140),
                (170, 5, 170),
                (205, 6, 205),
                (250, 7, 250),
                (260, 7, 250),
                (275, 8, 275),
                (305, 9, 305),
                (355, 10, 355),
                (395, 11, 395),
                (405, 11, 395),
                (415, 12, 415),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 120),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesSpacingAcrossSections() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerHeight: CGFloat,
                contentHeights: [CGFloat],
                footerHeight: CGFloat
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion([CGSize(width: 20, height: headerHeight)])
                let content = makeRegion(contentHeights.map { CGSize(width: 20, height: $0) })
                let footer = makeRegion([CGSize(width: 20, height: footerHeight)])
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let section0 = makeSection(
                id: 0,
                headerHeight: 30,
                contentHeights: [40, 50],
                footerHeight: 20
            )
            let section1 = makeSection(
                id: 1,
                headerHeight: 30,
                contentHeights: [35, 45],
                footerHeight: 25
            )
            let section2 = makeSection(
                id: 2,
                headerHeight: 30,
                contentHeights: [50, 40],
                footerHeight: 20
            )
            let list: any ViewList = _ViewList_Group(lists: [section0, section1, section2])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 7),
                pinnedViews: []
            )
            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyVStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [25: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 120),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (72, 1, 30),
                (141, 3, 134),
                (168, 4, 161),
                (205, 5, 198),
                (247, 6, 240),
                (299, 7, 292),
                (320, 7, 292),
                (331, 8, 324),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 120),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesHorizontalSpacingAcrossSections() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerWidth: CGFloat,
                contentWidths: [CGFloat],
                footerWidth: CGFloat
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion([CGSize(width: headerWidth, height: 20)])
                let content = makeRegion(contentWidths.map { CGSize(width: $0, height: 20) })
                let footer = makeRegion([CGSize(width: footerWidth, height: 20)])
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let section0 = makeSection(
                id: 0,
                headerWidth: 30,
                contentWidths: [40, 50],
                footerWidth: 20
            )
            let section1 = makeSection(
                id: 1,
                headerWidth: 30,
                contentWidths: [35, 45],
                footerWidth: 25
            )
            let section2 = makeSection(
                id: 2,
                headerWidth: 30,
                contentWidths: [50, 40],
                footerWidth: 20
            )
            let list: any ViewList = _ViewList_Group(lists: [section0, section1, section2])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyHStackLayout(
                base: _HStackLayout(alignment: .top, spacing: 7),
                pinnedViews: []
            )
            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyHStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyHStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [25: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 120),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (72, 1, 30),
                (141, 3, 134),
                (168, 4, 161),
                (205, 5, 198),
                (247, 6, 240),
                (299, 7, 292),
                (320, 7, 292),
                (331, 8, 324),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 120),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionSkipsEmptySectionRegionsInSpacingStream() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerHeights: [CGFloat],
                contentHeights: [CGFloat],
                footerHeights: [CGFloat]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion(headerHeights.map { CGSize(width: 20, height: $0) })
                let content = makeRegion(contentHeights.map { CGSize(width: 20, height: $0) })
                let footer = makeRegion(footerHeights.map { CGSize(width: 20, height: $0) })
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let sectionA = makeSection(
                id: 10,
                headerHeights: [],
                contentHeights: [40, 30],
                footerHeights: [20]
            )
            let sectionB = makeSection(
                id: 20,
                headerHeights: [25],
                contentHeights: [],
                footerHeights: [20]
            )
            let sectionC = makeSection(
                id: 30,
                headerHeights: [30],
                contentHeights: [35],
                footerHeights: []
            )
            let emptySection = makeSection(
                id: 35,
                headerHeights: [],
                contentHeights: [],
                footerHeights: []
            )
            let sectionD = makeSection(
                id: 40,
                headerHeights: [],
                contentHeights: [45],
                footerHeights: []
            )
            let list: any ViewList = _ViewList_Group(lists: [sectionA, sectionB, sectionC, emptySection, sectionD])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyVStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [25: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 40),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (47, 1, 40),
                (84, 2, 77),
                (111, 3, 104),
                (143, 4, 136),
                (170, 5, 163),
                (207, 6, 200),
                (249, 7, 242),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 40),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionSkipsEmptySectionRegionsInHorizontalSpacingStream() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerWidths: [CGFloat],
                contentWidths: [CGFloat],
                footerWidths: [CGFloat]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion(headerWidths.map { CGSize(width: $0, height: 20) })
                let content = makeRegion(contentWidths.map { CGSize(width: $0, height: 20) })
                let footer = makeRegion(footerWidths.map { CGSize(width: $0, height: 20) })
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let sectionA = makeSection(
                id: 10,
                headerWidths: [],
                contentWidths: [40, 30],
                footerWidths: [20]
            )
            let sectionB = makeSection(
                id: 20,
                headerWidths: [25],
                contentWidths: [],
                footerWidths: [20]
            )
            let sectionC = makeSection(
                id: 30,
                headerWidths: [30],
                contentWidths: [35],
                footerWidths: []
            )
            let emptySection = makeSection(
                id: 35,
                headerWidths: [],
                contentWidths: [],
                footerWidths: []
            )
            let sectionD = makeSection(
                id: 40,
                headerWidths: [],
                contentWidths: [45],
                footerWidths: []
            )
            let list: any ViewList = _ViewList_Group(lists: [sectionA, sectionB, sectionC, emptySection, sectionD])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyHStackLayout(
                base: _HStackLayout(alignment: .top, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyHStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyHStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [25: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 40),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (47, 1, 40),
                (84, 2, 77),
                (111, 3, 104),
                (143, 4, 136),
                (170, 5, 163),
                (207, 6, 200),
                (249, 7, 242),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 40),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesMultiItemSectionRegionSpacingPrefix() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerHeights: [CGFloat],
                contentHeights: [CGFloat],
                footerHeights: [CGFloat]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion(headerHeights.map { CGSize(width: 20, height: $0) })
                let content = makeRegion(contentHeights.map { CGSize(width: 20, height: $0) })
                let footer = makeRegion(footerHeights.map { CGSize(width: 20, height: $0) })
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let sectionA = makeSection(
                id: 10,
                headerHeights: [10, 15],
                contentHeights: [20, 25],
                footerHeights: [12, 18]
            )
            let sectionB = makeSection(
                id: 20,
                headerHeights: [14],
                contentHeights: [22],
                footerHeights: [16, 10]
            )
            let list: any ViewList = _ViewList_Group(lists: [sectionA, sectionB])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyVStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [20: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 50),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (17, 1, 10),
                (39, 2, 32),
                (66, 3, 59),
                (98, 4, 91),
                (117, 5, 110),
                (142, 6, 135),
                (163, 7, 156),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 50),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesHorizontalMultiItemSectionRegionSpacingPrefix() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func makeSection(
                id: UInt32,
                headerWidths: [CGFloat],
                contentWidths: [CGFloat],
                footerWidths: [CGFloat]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let header = makeRegion(headerWidths.map { CGSize(width: $0, height: 20) })
                let content = makeRegion(contentWidths.map { CGSize(width: $0, height: 20) })
                let footer = makeRegion(footerWidths.map { CGSize(width: $0, height: 20) })
                let sectionList: any ViewList = _ViewList_Section(
                    id: id,
                    base: _ViewList_Group(lists: [header, content, footer])
                )
                return (sectionList, graph.makeInput(value: sectionList))
            }

            let sectionA = makeSection(
                id: 10,
                headerWidths: [10, 15],
                contentWidths: [20, 25],
                footerWidths: [12, 18]
            )
            let sectionB = makeSection(
                id: 20,
                headerWidths: [14],
                contentWidths: [22],
                footerWidths: [16, 10]
            )
            let list: any ViewList = _ViewList_Group(lists: [sectionA, sectionB])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyHStackLayout(
                base: _HStackLayout(alignment: .top, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyHStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyHStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [20: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 50),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (17, 1, 10),
                (39, 2, 32),
                (66, 3, 59),
                (98, 4, 91),
                (117, 5, 110),
                (142, 6, 135),
                (163, 7, 156),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 50),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesNestedSectionSpacingStream() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            let a0 = makeRegion([CGSize(width: 20, height: 20)])
            let a1 = makeRegion([CGSize(width: 20, height: 25)])
            let nestedHeader = makeRegion([CGSize(width: 20, height: 15)])
            let nestedContent = makeRegion([CGSize(width: 20, height: 30)])
            let nestedFooter = makeRegion([CGSize(width: 20, height: 10)])
            let nestedSectionList: any ViewList = _ViewList_Section(
                id: 11,
                base: _ViewList_Group(lists: [nestedHeader, nestedContent, nestedFooter])
            )
            let nestedSection = (
                list: nestedSectionList,
                attribute: graph.makeInput(value: nestedSectionList)
            )

            let outerHeader = makeRegion([CGSize(width: 20, height: 12)])
            let outerContentList: any ViewList = _ViewList_Group(lists: [a0, nestedSection, a1])
            let outerContent = (
                list: outerContentList,
                attribute: graph.makeInput(value: outerContentList)
            )
            let outerFooter = makeRegion([CGSize(width: 20, height: 18)])
            let outerSectionList: any ViewList = _ViewList_Section(
                id: 10,
                base: _ViewList_Group(lists: [outerHeader, outerContent, outerFooter])
            )
            let outerSection = (
                list: outerSectionList,
                attribute: graph.makeInput(value: outerSectionList)
            )

            let secondHeader = makeRegion([CGSize(width: 20, height: 14)])
            let secondContent = makeRegion([CGSize(width: 20, height: 22)])
            let secondFooter = makeRegion([CGSize(width: 20, height: 16)])
            let secondSectionList: any ViewList = _ViewList_Section(
                id: 20,
                base: _ViewList_Group(lists: [secondHeader, secondContent, secondFooter])
            )
            let secondSection = (
                list: secondSectionList,
                attribute: graph.makeInput(value: secondSectionList)
            )

            let list: any ViewList = _ViewList_Group(lists: [outerSection, secondSection])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyVStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [20: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 80),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (19, 1, 12),
                (46, 2, 39),
                (68, 3, 61),
                (105, 4, 98),
                (122, 5, 115),
                (154, 6, 147),
                (179, 7, 172),
                (200, 8, 193),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 80),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesHorizontalNestedSectionSpacingStream() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            let a0 = makeRegion([CGSize(width: 20, height: 20)])
            let a1 = makeRegion([CGSize(width: 25, height: 20)])
            let nestedHeader = makeRegion([CGSize(width: 15, height: 20)])
            let nestedContent = makeRegion([CGSize(width: 30, height: 20)])
            let nestedFooter = makeRegion([CGSize(width: 10, height: 20)])
            let nestedSectionList: any ViewList = _ViewList_Section(
                id: 11,
                base: _ViewList_Group(lists: [nestedHeader, nestedContent, nestedFooter])
            )
            let nestedSection = (
                list: nestedSectionList,
                attribute: graph.makeInput(value: nestedSectionList)
            )

            let outerHeader = makeRegion([CGSize(width: 12, height: 20)])
            let outerContentList: any ViewList = _ViewList_Group(lists: [a0, nestedSection, a1])
            let outerContent = (
                list: outerContentList,
                attribute: graph.makeInput(value: outerContentList)
            )
            let outerFooter = makeRegion([CGSize(width: 18, height: 20)])
            let outerSectionList: any ViewList = _ViewList_Section(
                id: 10,
                base: _ViewList_Group(lists: [outerHeader, outerContent, outerFooter])
            )
            let outerSection = (
                list: outerSectionList,
                attribute: graph.makeInput(value: outerSectionList)
            )

            let secondHeader = makeRegion([CGSize(width: 14, height: 20)])
            let secondContent = makeRegion([CGSize(width: 22, height: 20)])
            let secondFooter = makeRegion([CGSize(width: 16, height: 20)])
            let secondSectionList: any ViewList = _ViewList_Section(
                id: 20,
                base: _ViewList_Group(lists: [secondHeader, secondContent, secondFooter])
            )
            let secondSection = (
                list: secondSectionList,
                attribute: graph.makeInput(value: secondSectionList)
            )

            let list: any ViewList = _ViewList_Group(lists: [outerSection, secondSection])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyHStackLayout(
                base: _HStackLayout(alignment: .top, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyHStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyHStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [20: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 80),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (19, 1, 12),
                (46, 2, 39),
                (68, 3, 61),
                (105, 4, 98),
                (122, 5, 115),
                (154, 6, 147),
                (179, 7, 172),
                (200, 8, 193),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 80),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesMixedSectionSpacingStream() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func major(_ length: CGFloat) -> CGSize {
                CGSize(width: 20, height: length)
            }

            let nestedHeader = makeRegion([major(14), major(16)])
            let nestedContent = makeRegion([])
            let nestedFooter = makeRegion([major(11)])
            let nestedSectionList: any ViewList = _ViewList_Section(
                id: 11,
                base: _ViewList_Group(lists: [nestedHeader, nestedContent, nestedFooter])
            )
            let nestedSection = (
                list: nestedSectionList,
                attribute: graph.makeInput(value: nestedSectionList)
            )

            let aHeader = makeRegion([major(10), major(12)])
            let a0 = makeRegion([major(20)])
            let a1 = makeRegion([major(18)])
            let aContentList: any ViewList = _ViewList_Group(lists: [a0, nestedSection, a1])
            let aContent = (
                list: aContentList,
                attribute: graph.makeInput(value: aContentList)
            )
            let aFooter = makeRegion([])
            let sectionAList: any ViewList = _ViewList_Section(
                id: 10,
                base: _ViewList_Group(lists: [aHeader, aContent, aFooter])
            )
            let sectionA = (
                list: sectionAList,
                attribute: graph.makeInput(value: sectionAList)
            )

            let sectionBList: any ViewList = _ViewList_Section(
                id: 20,
                base: _ViewList_Group(lists: [makeRegion([]), makeRegion([]), makeRegion([])])
            )
            let sectionB = (
                list: sectionBList,
                attribute: graph.makeInput(value: sectionBList)
            )

            let cHeader = makeRegion([])
            let cContent = makeRegion([major(22), major(13)])
            let cFooter = makeRegion([major(15), major(10)])
            let sectionCList: any ViewList = _ViewList_Section(
                id: 30,
                base: _ViewList_Group(lists: [cHeader, cContent, cFooter])
            )
            let sectionC = (
                list: sectionCList,
                attribute: graph.makeInput(value: sectionCList)
            )

            let dHeader = makeRegion([major(14)])
            let dContent = makeRegion([major(20)])
            let dFooter = makeRegion([])
            let sectionDList: any ViewList = _ViewList_Section(
                id: 40,
                base: _ViewList_Group(lists: [dHeader, dContent, dFooter])
            )
            let sectionD = (
                list: sectionDList,
                attribute: graph.makeInput(value: sectionDList)
            )

            let eHeader = makeRegion([major(16)])
            let eContent = makeRegion([major(22)])
            let eFooter = makeRegion([major(18)])
            let sectionEList: any ViewList = _ViewList_Section(
                id: 50,
                base: _ViewList_Group(lists: [eHeader, eContent, eFooter])
            )
            let sectionE = (
                list: sectionEList,
                attribute: graph.makeInput(value: sectionEList)
            )

            let list: any ViewList = _ViewList_Group(lists: [sectionA, sectionB, sectionC, sectionD, sectionE])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyVStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [20: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 70),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (17, 1, 10),
                (36, 2, 29),
                (63, 3, 56),
                (84, 4, 77),
                (107, 5, 100),
                (125, 6, 118),
                (150, 7, 143),
                (179, 8, 172),
                (199, 9, 192),
                (221, 10, 214),
                (238, 11, 231),
                (259, 12, 252),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 70),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCacheResolveIndexAndPositionPreservesHorizontalMixedSectionSpacingStream() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func makeRegion(
                _ sizes: [CGSize]
            ) -> (list: any ViewList, attribute: Attribute<any ViewList>) {
                let list: any ViewList = BaseViewList(
                    elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes),
                    implicitID: Int(graph.makeInput(value: UniqueID()).identifier.rawValue)
                )
                return (list, graph.makeInput(value: list))
            }

            func major(_ length: CGFloat) -> CGSize {
                CGSize(width: length, height: 20)
            }

            let nestedHeader = makeRegion([major(14), major(16)])
            let nestedContent = makeRegion([])
            let nestedFooter = makeRegion([major(11)])
            let nestedSectionList: any ViewList = _ViewList_Section(
                id: 11,
                base: _ViewList_Group(lists: [nestedHeader, nestedContent, nestedFooter])
            )
            let nestedSection = (
                list: nestedSectionList,
                attribute: graph.makeInput(value: nestedSectionList)
            )

            let aHeader = makeRegion([major(10), major(12)])
            let a0 = makeRegion([major(20)])
            let a1 = makeRegion([major(18)])
            let aContentList: any ViewList = _ViewList_Group(lists: [a0, nestedSection, a1])
            let aContent = (
                list: aContentList,
                attribute: graph.makeInput(value: aContentList)
            )
            let aFooter = makeRegion([])
            let sectionAList: any ViewList = _ViewList_Section(
                id: 10,
                base: _ViewList_Group(lists: [aHeader, aContent, aFooter])
            )
            let sectionA = (
                list: sectionAList,
                attribute: graph.makeInput(value: sectionAList)
            )

            let sectionBList: any ViewList = _ViewList_Section(
                id: 20,
                base: _ViewList_Group(lists: [makeRegion([]), makeRegion([]), makeRegion([])])
            )
            let sectionB = (
                list: sectionBList,
                attribute: graph.makeInput(value: sectionBList)
            )

            let cHeader = makeRegion([])
            let cContent = makeRegion([major(22), major(13)])
            let cFooter = makeRegion([major(15), major(10)])
            let sectionCList: any ViewList = _ViewList_Section(
                id: 30,
                base: _ViewList_Group(lists: [cHeader, cContent, cFooter])
            )
            let sectionC = (
                list: sectionCList,
                attribute: graph.makeInput(value: sectionCList)
            )

            let dHeader = makeRegion([major(14)])
            let dContent = makeRegion([major(20)])
            let dFooter = makeRegion([])
            let sectionDList: any ViewList = _ViewList_Section(
                id: 40,
                base: _ViewList_Group(lists: [dHeader, dContent, dFooter])
            )
            let sectionD = (
                list: sectionDList,
                attribute: graph.makeInput(value: sectionDList)
            )

            let eHeader = makeRegion([major(16)])
            let eContent = makeRegion([major(22)])
            let eFooter = makeRegion([major(18)])
            let sectionEList: any ViewList = _ViewList_Section(
                id: 50,
                base: _ViewList_Group(lists: [eHeader, eContent, eFooter])
            )
            let sectionE = (
                list: sectionEList,
                attribute: graph.makeInput(value: sectionEList)
            )

            let list: any ViewList = _ViewList_Group(lists: [sectionA, sectionB, sectionC, sectionD, sectionE])
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyHStackLayout(
                base: _HStackLayout(alignment: .top, spacing: 7),
                pinnedViews: []
            )

            func resolve(_ lowerBound: CGFloat) -> (index: Int, position: CGFloat, cache: _LazyStack_Cache<LazyHStackLayout>) {
                var stackCache = _LazyStack_Cache<LazyHStackLayout>(
                    estimations: EstimationCache(
                        lengthToCount: [20: 1],
                        spacingToCount: [7: 1]
                    )
                )
                let resolved = stackCache.resolveIndexAndPosition(
                    stack: layout,
                    subviews: subviews,
                    visible: lowerBound..<(lowerBound + 70),
                    minor: MinorProperties(count: 1, size: 180, geometry: 180)
                )
                return (resolved.index, resolved.position, stackCache)
            }

            let cases: [(lowerBound: CGFloat, index: Int, position: CGFloat)] = [
                (0, 0, 0),
                (17, 1, 10),
                (36, 2, 29),
                (63, 3, 56),
                (84, 4, 77),
                (107, 5, 100),
                (125, 6, 118),
                (150, 7, 143),
                (179, 8, 172),
                (199, 9, 192),
                (221, 10, 214),
                (238, 11, 231),
                (259, 12, 252),
            ]

            for testCase in cases {
                let resolved = resolve(testCase.lowerBound)
                XCTAssertEqual(resolved.index, testCase.index, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.position, testCase.position, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(resolved.cache.minor?.count, 1, "lowerBound \(testCase.lowerBound)")
                XCTAssertEqual(
                    resolved.cache.visibleExtent,
                    testCase.lowerBound..<(testCase.lowerBound + 70),
                    "lowerBound \(testCase.lowerBound)"
                )
            }
        }
    }

    func testLazyStackCachePlaceDelegatesToStackPlacementAndWritesPlacedState() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 20, height: 30),
                CGSize(width: 25, height: 40),
                CGSize(width: 30, height: 50),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes)
            )
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 99, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .center, spacing: 5),
                pinnedViews: []
            )
            var stackCache = _LazyStack_Cache<LazyVStackLayout>(
                estimations: EstimationCache(lengthToCount: [12: 2])
            )

            let placements = stackCache.place(
                stack: layout,
                subviews: subviews,
                from: 0,
                position: 7,
                visible: CGFloat(0)..<CGFloat(160),
                visibleLength: 160,
                containerLength: 220,
                minor: MinorProperties(count: 1, size: 80, geometry: 80)
            )

            XCTAssertEqual(placements.subviews.map(\.index), [0, 1, 2])
            XCTAssertEqual(placements.validRect, CGRect(x: 0, y: 7, width: 80, height: 130))
            XCTAssertFalse(placements.invalidSize)
            XCTAssertEqual(placements.translation, .zero)
            XCTAssertFalse(placements.wasCancelled)
            XCTAssertEqual(stackCache.minor?.count, 1)
            XCTAssertEqual(stackCache.endIndex, 3)
            XCTAssertEqual(stackCache.placedIndices, 0..<3)
            XCTAssertEqual(stackCache.placedExtent, CGFloat(7)..<CGFloat(137))
            XCTAssertEqual(stackCache.visibleExtent, CGFloat(0)..<CGFloat(160))
            XCTAssertEqual(stackCache.visibleLength, 160)
            XCTAssertEqual(stackCache.containerLength, 220)
            XCTAssertNil(stackCache.estimations.lengthToCount[12])
            XCTAssertEqual(stackCache.estimations.lengthToCount[30], 1)
            XCTAssertEqual(stackCache.estimations.lengthToCount[40], 1)
            XCTAssertEqual(stackCache.estimations.lengthToCount[50], 1)
            XCTAssertEqual(stackCache.estimations.spacingToCount[0], 1)
            XCTAssertEqual(stackCache.estimations.spacingToCount[5], 2)
        }
    }

    func testLazyLayoutSubviewsApplyMaterializesSelectedElement() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 11, height: 12),
                CGSize(width: 21, height: 22),
                CGSize(width: 31, height: 32),
            ]
            let list = BaseViewList(
                elements: IndexedLayoutViewListElements(graph: graph, sizes: sizes)
            )
            let (cache, _, _) = makeLazyCache(host: host, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            var from = 2
            var proposed: _LazyLayout_ProposedSubview?

            XCTAssertFalse(subviews.apply(from: &from) { index, subview, stop in
                proposed = subview.proposeSize(ProposedViewSize(width: 44, height: nil))
                XCTAssertEqual(index, 2)
                XCTAssertEqual(subview.index, 2)
                stop = true
            })

            let resolved = try XCTUnwrap(proposed)
            let layout = try XCTUnwrap(resolved.item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(resolved.index, 2)
            XCTAssertEqual(resolved.item.id.canonicalID.index, 2)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), sizes[2])
            XCTAssertEqual(
                resolved.item.pendingPlacement,
                _Placement(proposedSize: CGSize(width: 44, height: 10))
            )
        }
    }

    func testLazyLayoutSubviewsApplyPreservesSkippedSegmentIndex() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 12, height: 13),
                CGSize(width: 22, height: 23),
                CGSize(width: 32, height: 33),
            ]
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(host: host, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let context = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let subviews = cache.subviews(context: context)
            var from = 2
            var proposed: _LazyLayout_ProposedSubview?

            XCTAssertFalse(subviews.apply(from: &from) { index, subview, stop in
                proposed = subview.proposeSize(ProposedViewSize(width: nil, height: 45))
                XCTAssertEqual(index, 2)
                XCTAssertEqual(subview.index, 2)
                stop = true
            })

            let resolved = try XCTUnwrap(proposed)
            let layout = try XCTUnwrap(resolved.item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(resolved.index, 2)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), sizes[2])
        }
    }

    func testLazyStackProposeSizesUsesStrideStartAndAxisProposal() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 10, height: 11),
                CGSize(width: 20, height: 21),
                CGSize(width: 30, height: 31),
                CGSize(width: 40, height: 41),
            ]
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(host: host, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let ruleContext = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let context = _LazyLayout_SizeAndSpacingContext(
                ruleContext: ruleContext,
                environment: graph.makeInput(value: EnvironmentValues())
            )
            let subviews = cache.subviews(context: ruleContext)

            let hCache = _LazyStack_Cache<LazyHStackLayout>(
                minor: MinorProperties(count: 2, size: 33, geometry: 33)
            )
            let hLayout = LazyHStackLayout(base: _HStackLayout(), pinnedViews: [])
            let hPlacementContext = _LazyLayout_PlacementContext(
                base: context,
                size: ViewSize(width: 90, height: 33)
            )
            var hProposed = _LazyLayout_ProposedSizes()
            hLayout.proposeSizes(
                at: 5,
                subviews: subviews,
                context: hPlacementContext,
                cache: hCache,
                in: &hProposed
            )

            let hSubview = try XCTUnwrap(hProposed.subviews.first)
            let hLayoutComputer = try XCTUnwrap(hSubview.item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(hProposed.subviews.count, 1)
            XCTAssertEqual(hSubview.index, 2)
            XCTAssertEqual(hSubview.proposal, _ProposedSize(width: nil, height: 33))
            XCTAssertEqual(hLayoutComputer.sizeThatFits(.unspecified), sizes[2])
            XCTAssertEqual(
                hSubview.item.pendingPlacement,
                _Placement(proposedSize: CGSize(width: 10, height: 33))
            )

            let vCache = _LazyStack_Cache<LazyVStackLayout>(
                minor: MinorProperties(count: 2, size: 44, geometry: 44)
            )
            let vLayout = LazyVStackLayout(base: _VStackLayout(), pinnedViews: [])
            let vPlacementContext = _LazyLayout_PlacementContext(
                base: context,
                size: ViewSize(width: 44, height: 90)
            )
            var vProposed = _LazyLayout_ProposedSizes()
            vLayout.proposeSizes(
                at: 7,
                subviews: subviews,
                context: vPlacementContext,
                cache: vCache,
                in: &vProposed
            )

            let vSubview = try XCTUnwrap(vProposed.subviews.first)
            let vLayoutComputer = try XCTUnwrap(vSubview.item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(vProposed.subviews.count, 1)
            XCTAssertEqual(vSubview.index, 3)
            XCTAssertEqual(vSubview.proposal, _ProposedSize(width: 44, height: nil))
            XCTAssertEqual(vLayoutComputer.sizeThatFits(.unspecified), sizes[3])
            XCTAssertEqual(
                vSubview.item.pendingPlacement,
                _Placement(proposedSize: CGSize(width: 44, height: 10))
            )
        }
    }

    func testLazyStackProposeSizesAppliesViewportWindowGateBeforeMaterialization() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = (0..<80).map { index in
                CGSize(width: 10 + CGFloat(index), height: 20 + CGFloat(index))
            }
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(host: host, list: list)
            cache.items.removeAll()
            cache.lru.invalidate()

            let ruleContext = AnyRuleContext(attribute: graph.makeInput(value: ()).identifier)
            let context = _LazyLayout_SizeAndSpacingContext(
                ruleContext: ruleContext,
                environment: graph.makeInput(value: EnvironmentValues())
            )
            let subviews = cache.subviews(context: ruleContext)
            let layout = LazyVStackLayout(base: _VStackLayout(), pinnedViews: [])

            let placementContext = _LazyLayout_PlacementContext(
                base: context,
                size: ViewSize(width: 44, height: 100)
            )
            let passingCache = _LazyStack_Cache<LazyVStackLayout>(visibleLength: 100)
            var passing = _LazyLayout_ProposedSizes()
            layout.proposeSizes(
                at: 75,
                subviews: subviews,
                context: placementContext,
                cache: passingCache,
                in: &passing
            )
            let passingSubview = try XCTUnwrap(passing.subviews.first)
            XCTAssertEqual(passing.subviews.count, 1)
            XCTAssertEqual(passingSubview.index, 75)
            XCTAssertEqual(passingSubview.proposal, _ProposedSize(width: 44, height: nil))

            cache.items.removeAll()
            cache.lru.invalidate()

            let blockedCache = _LazyStack_Cache<LazyVStackLayout>(visibleLength: 100)
            var blocked = _LazyLayout_ProposedSizes()
            layout.proposeSizes(
                at: 76,
                subviews: subviews,
                context: placementContext,
                cache: blockedCache,
                in: &blocked
            )
            XCTAssertTrue(blocked.subviews.isEmpty)
            XCTAssertTrue(cache.items.isEmpty)
        }
    }

    func testLazyCacheItemAnimationRemovalQueuesSingleItemPhaseMutationAtZeroCount() {
        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        let placement = _Placement(proposedSize: CGSize(width: 10, height: 20))
        let pendingPlacement = _Placement(proposedSize: CGSize(width: 30, height: 40))
        host.data.withCurrent {
            item.displayIndex = 4
            item.prefetchPhase = .pendingDisplay
            item.placement = placement
            item.pendingPlacement = pendingPlacement
            item.commitSeed = UInt32.max
            item.removedSeed = 0
            item.removalTransactionSeed = 1
            item.willAnimateRemoval = false
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 1,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )
        }

        item.animationWasAdded()
        item.animationWasAdded()
        XCTAssertEqual(item.animationCount, 2)

        _ = item.animationWasRemoved()
        XCTAssertEqual(item.animationCount, 1)
        XCTAssertFalse(host.hasPendingTransactions)

        _ = item.animationWasRemoved()
        XCTAssertEqual(item.animationCount, 0)
        XCTAssertTrue(host.hasPendingTransactions)

        host.flushTransactions()
        XCTAssertFalse(host.hasPendingTransactions)
        host.data.withCurrent {
            XCTAssertNil(item.displayIndex)
            XCTAssertNil(item.placement)
            XCTAssertEqual(item.pendingPlacement, pendingPlacement)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
            XCTAssertTrue(state.value.isRemoved)
            XCTAssertTrue(cache.item(for: item.id.canonicalID) === item)
        }
    }

    func testLazyTransactionPublishesAnimationListenerAndStoresLastState() {
        let host = GraphHost()

        host.data.withCurrent {
            let (_, item, state) = makeLazyCache(host: host)
            let graph = host.data.graph
            let transaction = graph.makeInput(value: Transaction(animation: .linear(duration: 0.25)))
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 7,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: true
                )
            )
            let lazyTransaction = graph.makeStatefulRule(
                LazyTransaction(
                    transaction: transaction,
                    state: state,
                    item: item
                )
            )

            let output = lazyTransaction.value
            XCTAssertNotNil(output.animationListener)
            XCTAssertEqual(output.animation, .linear(duration: 0.25))

            graph.mutateStatefulRule(lazyTransaction.identifier, as: LazyTransaction.self) { rule in
                XCTAssertEqual(rule.lastPhase, .didDisappear)
                XCTAssertEqual(rule.lastResetDelta, 7)
                XCTAssertFalse(rule.isRemoved)
            }

            output.animationListener?.animationWasAdded()
            XCTAssertEqual(item.animationCount, 1)
        }
    }

    func testLazyTransactionRemovableCallbacksOwnRemovalFlag() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let transaction = graph.makeInput(value: Transaction())
            let state = graph.makeInput(value: LazyLayoutCacheItem.State())
            let lazyTransaction = graph.makeStatefulRule(
                LazyTransaction(
                    transaction: transaction,
                    state: state,
                    item: nil
                )
            )

            LazyTransaction.willRemove(attribute: lazyTransaction.identifier)
            graph.mutateStatefulRule(lazyTransaction.identifier, as: LazyTransaction.self) { rule in
                XCTAssertTrue(rule.isRemoved)
            }

            LazyTransaction.didReinsert(attribute: lazyTransaction.identifier)
            graph.mutateStatefulRule(lazyTransaction.identifier, as: LazyTransaction.self) { rule in
                XCTAssertFalse(rule.isRemoved)
            }
        }
    }

    func testLazyTransactionCarriesRemovableAttributeMarker() {
        assertRemovableAttribute(LazyTransaction.self)
    }

    func testLazyViewPhaseAddsSecondaryPhaseResetDeltaAndRemovalBit() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            var basePhase = _GraphInputs.Phase()
            basePhase.resetSeed = 3
            var secondaryPhase = _GraphInputs.Phase()
            secondaryPhase.resetSeed = 4
            let base = graph.makeInput(value: basePhase)
            let secondary = graph.makeInput(value: secondaryPhase)
            let state = graph.makeInput(
                value: LazyLayoutCacheItem.State(
                    resetDelta: 5,
                    phase: .didDisappear,
                    enableTransitions: false,
                    isRemoved: false
                )
            )
            let lazyPhase = graph.makeRule(
                LazyViewPhase(
                    _phase1: base,
                    _phase2: secondary,
                    _state: state
                )
            )

            let output = lazyPhase.value
            XCTAssertEqual(output.resetSeed, 12)
            XCTAssertTrue(output.isBeingRemoved)
        }
    }

    func testLazyLayoutViewCacheNewItemInstallsLazyViewPhaseForChildInputs() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, _, _) = makeLazyCache(host: host)
            cache.items.removeAll()
            cache.lru.invalidate()

            var basePhase = _GraphInputs.Phase()
            basePhase.resetSeed = 6
            cache.inputs.base.phase.setValue(basePhase)

            let elements = PhaseCapturingElements()
            let data = makeLazyData(
                graph: graph,
                id: _ViewList_ID(implicitID: 900).elementID(at: 0),
                elements: _ViewList_SubgraphElements(base: elements)
            )
            let item = cache.item(data: data)

            var state = item._state.value
            state.resetDelta = 4
            state.phase = .didDisappear
            item._state.setValue(state)

            guard let childPhase = elements.capturedPhase else {
                XCTFail("expected child phase attribute to be captured")
                return
            }
            let output = childPhase.value
            // This fixture passes the base phase through the element inputs, so
            // the child observes base + element + item reset deltas.
            XCTAssertEqual(output.resetSeed, 16)
            XCTAssertTrue(output.isBeingRemoved)
        }
    }

    func testLazyLayoutViewCacheLRUAndPlacementSeedOrdering() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, first, _) = makeLazyCache(host: host, implicitID: 1, reuseIdentifier: 4)
            let (_, second, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: 4
            )
            cache.lru.transactionSeed = 20
            first.insertionTransactionSeed = 18
            first.placementSeed = 10
            first.usedSeed = 20
            second.insertionTransactionSeed = 18
            second.placementSeed = 10
            second.usedSeed = 10

            XCTAssertTrue(
                cache.reusedItem(
                    for: _ViewList_ID(implicitID: 99).canonicalID,
                    reuseIdentifier: 4,
                    transitionType: nil
                ) === second
            )
            XCTAssertEqual(cache.lru.usedSeed, 1)

            let placement = _Placement(proposedSize: CGSize(width: 11, height: 13))
            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(item: first, placement: placement, index: 0),
            ], to: cache)
            XCTAssertEqual(cache.placementSeed, 1)
            XCTAssertEqual(first.placementSeed, 10)
            XCTAssertEqual(first.commitSeed, 1)
            XCTAssertEqual(first.placement, placement)
        }
    }

    func testLazyLayoutViewCacheLRUUpdatedItemsCachesSortedCandidatesUntilInvalidated() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, first, _) = makeLazyCache(host: host, implicitID: 1, reuseIdentifier: 4)
            let (_, second, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: 4
            )
            first.usedSeed = 20
            second.usedSeed = 10

            let firstPass = cache.lru.updatedItems(Array(cache.items.values))
            XCTAssertEqual(firstPass.map(\.id.index), [2, 1])
            XCTAssertEqual(cache.lru.usedSeed, 1)

            first.usedSeed = 0
            second.usedSeed = 30
            let cachedPass = cache.lru.updatedItems(Array(cache.items.values))
            XCTAssertEqual(cachedPass.map(\.id.index), [2, 1])
            XCTAssertEqual(cache.lru.usedSeed, 1)

            cache.lru.invalidate()
            let refreshedPass = cache.lru.updatedItems(Array(cache.items.values))
            XCTAssertEqual(refreshedPass.map(\.id.index), [1, 2])
            XCTAssertEqual(cache.lru.usedSeed, 2)
        }
    }

    func testLazyLayoutViewCacheResetInitializesLRUAndPlacementSeeds() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, first, _) = makeLazyCache(host: host, implicitID: 1, reuseIdentifier: 4)
            let (_, second, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: 4
            )
            first.usedSeed = 20
            second.usedSeed = 10
            XCTAssertEqual(cache.lru.maxIdle, 16)
            _ = cache.lru.updatedItems(Array(cache.items.values))
            cache.lru.transactionSeed = 44
            cache.lru.maxIdle = 7
            cache.commitSeed = 33
            cache.placementSeed = 34

            cache.reset()

            XCTAssertEqual(cache.lru.lastTransactionID, TransactionID())
            XCTAssertEqual(cache.lru.transactionSeed, 1)
            XCTAssertEqual(cache.lru.usedSeed, 1)
            XCTAssertEqual(cache.lru.maxIdle, 7)
            XCTAssertEqual(cache.commitSeed, 1)
            XCTAssertEqual(cache.placementSeed, 1)

            first.usedSeed = 0
            second.usedSeed = 30
            let refreshed = cache.lru.updatedItems(Array(cache.items.values))
            XCTAssertEqual(refreshed.map(\.id.index), [1, 2])
            XCTAssertEqual(cache.lru.usedSeed, 2)
        }
    }

    func testConcreteLazyLayoutViewCacheResetRestoresInitialCacheBeforeBaseSeeds() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let layout = graph.makeInput(value: LazyVStackLayout(
                base: _VStackLayout(),
                pinnedViews: []
            ))
            let cacheState = graph.makeInput(value: _LazyStack_Cache<LazyVStackLayout>(
                endIndex: 10,
                placedIndices: 2..<4,
                visibleLength: 40
            ))
            let cache = _LazyLayoutViewCache(
                layout: layout,
                cacheState: cacheState.value,
                viewGraph: host,
                parentSubgraph: AGSubgraph(),
                inputs: makeViewInputs(graph: graph),
                outputs: _ViewOutputs(),
                list: graph.makeInput(value: EmptyViewList() as any ViewList),
                layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                nearestScrollableAxes: graph.makeInput(value: Axis.Set.vertical),
                placedSubviews: graph.makeInput(value: []),
                prefetchSignal: graph.makeInput(value: ()),
                scrollPosition: OptionalAttribute(),
                accessibilityEnabled: graph.makeInput(value: false)
            )

            cache.reset()
            XCTAssertNil(cache.cacheState.endIndex)
            XCTAssertTrue(cache.cacheState.placedIndices.isEmpty)
            XCTAssertEqual(cache.cacheState.visibleLength, .infinity)
            XCTAssertEqual(cache.lru.usedSeed, 1)
            XCTAssertEqual(cache.lru.transactionSeed, 1)
            XCTAssertEqual(cache.commitSeed, 1)
            XCTAssertEqual(cache.placementSeed, 1)
        }
    }

    func testLazyLayoutViewCacheSubviewsAdvancesLRUTransactionSeedOnTransactionChange() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let source = graph.makeInput(value: 1)
            let derived = graph.makeRule { source.value }
            XCTAssertEqual(derived.value, 1)

            let context = AnyRuleContext(attribute: derived.identifier)
            let initialTransactionID = TransactionID(context: context)
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)
            cache.lru.lastTransactionID = initialTransactionID
            cache.lru.transactionSeed = 7

            _ = cache.subviews(context: context)
            XCTAssertEqual(cache.lru.lastTransactionID, initialTransactionID)
            XCTAssertEqual(cache.lru.transactionSeed, 7)

            source.setValue(2)
            XCTAssertEqual(derived.value, 2)
            let changedTransactionID = TransactionID(context: context)
            XCTAssertNotEqual(changedTransactionID, initialTransactionID)

            _ = cache.subviews(context: context)
            XCTAssertEqual(cache.lru.lastTransactionID, changedTransactionID)
            XCTAssertEqual(cache.lru.transactionSeed, 8)

            _ = cache.subviews(context: context)
            XCTAssertEqual(cache.lru.lastTransactionID, changedTransactionID)
            XCTAssertEqual(cache.lru.transactionSeed, 8)
        }
    }

    func testUpdateViewCacheResetsOnPhaseSeedChangeAndInvalidatesOnDestroy() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let phase = graph.makeInput(value: _GraphInputs.Phase())
            let (cache, item, _) = makeLazyCache(host: host, implicitID: 1)
            let update = graph.makeStatefulRule(UpdateViewCache(_phase: phase, cache: cache))

            XCTAssertTrue(update.value === cache)
            cache.lru.transactionSeed = 44
            cache.commitSeed = 33
            cache.placementSeed = 34

            var removalOnly = _GraphInputs.Phase()
            removalOnly.isBeingRemoved = true
            phase.setValue(removalOnly)
            _ = update.value
            XCTAssertEqual(cache.lru.transactionSeed, 44)
            XCTAssertEqual(cache.commitSeed, 33)
            XCTAssertEqual(cache.placementSeed, 34)

            var changedSeed = removalOnly
            changedSeed.resetSeed = 2
            phase.setValue(changedSeed)
            _ = update.value
            XCTAssertEqual(cache.lru.transactionSeed, 1)
            XCTAssertEqual(cache.commitSeed, 1)
            XCTAssertEqual(cache.placementSeed, 1)

            graph.removeNode(update.identifier)
            XCTAssertTrue(cache.items.isEmpty)
            XCTAssertFalse(AGSubgraphIsValid(item.subgraph))
        }
    }

    func testLazyLayoutViewCacheInvalidateClearsCachedItemsAndSubgraphs() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, firstItem, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, secondItem, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            _ = cache.lru.updatedItems(Array(cache.items.values))

            XCTAssertEqual(cache.items.count, 2)
            XCTAssertNotNil(cache.lru.items)
            XCTAssertTrue(AGSubgraphIsValid(firstItem.subgraph))
            XCTAssertTrue(AGSubgraphIsValid(secondItem.subgraph))

            cache.invalidate()

            XCTAssertTrue(cache.items.isEmpty)
            XCTAssertNil(cache.lru.items)
            XCTAssertFalse(AGSubgraphIsValid(firstItem.subgraph))
            XCTAssertFalse(AGSubgraphIsValid(secondItem.subgraph))
            XCTAssertNil(cache.item(for: firstItem.subgraph))
            XCTAssertNil(cache.item(for: secondItem.subgraph))
        }
    }

    func testLazyLayoutViewCacheInvalidateSizeUsesSeedTTLAndAnimatedTransaction() {
        let host = GraphHost()
        var evaluations = 0
        var dependent: Attribute<Int>!
        var layoutComputer: Attribute<LayoutComputer>!
        let (cache, _, _) = host.data.withCurrent {
            makeLazyCache(host: host, implicitID: 1)
        }

        host.data.withCurrent {
            let graph = host.data.graph
            var computer = LayoutComputer.fixed(CGSize(width: 10, height: 12))
            computer.seed = 7
            layoutComputer = graph.makeInput(value: computer)
            dependent = graph.makeRule {
                _ = layoutComputer.value
                evaluations += 1
                return evaluations
            }

            XCTAssertEqual(dependent.value, 1)

            cache.invalidateSize(
                layoutComputer: layoutComputer,
                animation: .linear(duration: 0.1)
            )
            XCTAssertEqual(cache.invalidationSeed, 7)
            XCTAssertEqual(cache.invalidationTTL, 1)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(dependent.value, 2)

            cache.invalidateSize(
                layoutComputer: layoutComputer,
                animation: .linear(duration: 0.1)
            )
            XCTAssertEqual(cache.invalidationSeed, 7)
            XCTAssertEqual(cache.invalidationTTL, 0)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            cache.invalidateSize(
                layoutComputer: layoutComputer,
                animation: .linear(duration: 0.1)
            )
            XCTAssertEqual(cache.invalidationSeed, 7)
            XCTAssertEqual(cache.invalidationTTL, 0)
            XCTAssertFalse(host.hasPendingTransactions)
        }
    }

    func testLazyLayoutViewCacheInvalidateSizeNilAnimationEnqueuesInvalidationAction() {
        let host = GraphHost()
        var evaluations = 0
        var dependent: Attribute<Int>!
        let (cache, _, _) = host.data.withCurrent {
            makeLazyCache(host: host, implicitID: 1)
        }

        host.data.withCurrent {
            let graph = host.data.graph
            var computer = LayoutComputer.fixed(CGSize(width: 21, height: 23))
            computer.seed = 11
            let layoutComputer = graph.makeInput(value: computer)
            dependent = graph.makeRule {
                _ = layoutComputer.value
                evaluations += 1
                return evaluations
            }

            XCTAssertEqual(dependent.value, 1)
            Update.ensure {
                cache.invalidateSize(layoutComputer: layoutComputer, animation: nil)
                XCTAssertEqual(cache.invalidationSeed, 11)
                XCTAssertEqual(cache.invalidationTTL, 1)
            }
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(dependent.value, 2)
        }
    }

    func testLazyLayoutViewCacheInvalidateSizeReopensTTLAfterPlacementSeedReevaluation() {
        let host = GraphHost()
        var evaluations = 0
        var dependent: Attribute<Int>!
        var layoutComputer: Attribute<LayoutComputer>!
        let (cache, item, _) = host.data.withCurrent {
            makeLazyCache(host: host, implicitID: 1)
        }

        host.data.withCurrent {
            let graph = host.data.graph
            layoutComputer = graph.makeRule {
                testLayoutComputer(
                    sizeThatFits: { _ in CGSize(width: 10, height: 12) },
                    seed: Int(cache.placementSeed)
                )
            }
            dependent = graph.makeRule {
                _ = layoutComputer.value
                evaluations += 1
                return evaluations
            }

            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: item,
                    placement: _Placement(proposedSize: CGSize(width: 10, height: 12)),
                    index: 0
                ),
            ], to: cache)
            XCTAssertEqual(cache.placementSeed, 1)

            cache.invalidateSize(
                layoutComputer: layoutComputer,
                animation: .linear(duration: 0.1)
            )
            XCTAssertEqual(cache.invalidationSeed, 1)
            XCTAssertEqual(cache.invalidationTTL, 1)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(dependent.value, 1)
            XCTAssertEqual(layoutComputer.value.seed, Int(cache.placementSeed))

            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: item,
                    placement: _Placement(proposedSize: CGSize(width: 12, height: 12)),
                    index: 0
                ),
            ], to: cache)
            XCTAssertEqual(cache.placementSeed, 2)

            cache.invalidateSize(
                layoutComputer: layoutComputer,
                animation: .linear(duration: 0.1)
            )
            XCTAssertEqual(cache.invalidationSeed, 1)
            XCTAssertEqual(cache.invalidationTTL, 0)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(dependent.value, 2)
            XCTAssertEqual(layoutComputer.value.seed, Int(cache.placementSeed))

            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: item,
                    placement: _Placement(proposedSize: CGSize(width: 14, height: 12)),
                    index: 0
                ),
            ], to: cache)
            XCTAssertEqual(cache.placementSeed, 3)

            cache.invalidateSize(
                layoutComputer: layoutComputer,
                animation: .linear(duration: 0.1)
            )
            XCTAssertEqual(cache.invalidationSeed, 2)
            XCTAssertEqual(cache.invalidationTTL, 1)
            XCTAssertTrue(host.hasPendingTransactions)
        }
    }

    func testLazyLayoutViewCacheCommitPlacedSubviewsMarksDisplayIndexesAndLRUUseGeneration() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, first, _) = makeLazyCache(host: host, implicitID: 1, reuseIdentifier: 4)
            let (_, second, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: 4
            )
            _ = cache.lru.updatedItems(Array(cache.items.values))

            first.pendingPlacement = _Placement(proposedSize: CGSize(width: 1, height: 2))
            second.pendingPlacement = _Placement(proposedSize: CGSize(width: 3, height: 4))

            let firstPlacement = _Placement(proposedSize: CGSize(width: 11, height: 13))
            let secondPlacement = _Placement(proposedSize: CGSize(width: 17, height: 19))
            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(item: first, placement: firstPlacement, index: 20),
                _LazyLayout_PlacedSubview(item: second, placement: secondPlacement, index: 21),
            ], to: cache)

            XCTAssertEqual(cache.placementSeed, 1)
            XCTAssertEqual(first.displayIndex, 0)
            XCTAssertEqual(second.displayIndex, 1)
            XCTAssertEqual(first.usedSeed, cache.lru.usedSeed)
            XCTAssertEqual(second.usedSeed, cache.lru.usedSeed)
            XCTAssertEqual(first.commitSeed, cache.placementSeed)
            XCTAssertEqual(second.commitSeed, cache.placementSeed)
            XCTAssertEqual(first.placement, firstPlacement)
            XCTAssertEqual(second.placement, secondPlacement)
            XCTAssertEqual(
                first.pendingPlacement,
                _Placement(proposedSize: CGSize(width: 1, height: 2))
            )
            XCTAssertEqual(
                second.pendingPlacement,
                _Placement(proposedSize: CGSize(width: 3, height: 4))
            )
            XCTAssertEqual(cache.placedIndices.min, 20)
            XCTAssertEqual(cache.placedIndices.max, 21)
        }
    }

    func testLazyLayoutViewCacheCommitCollapsesDuplicateItemsWithinGeneration() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host)
            let first = _Placement(
                proposedSize: CGSize(width: 10, height: 12)
            )
            let duplicate = _Placement(
                proposedSize: CGSize(width: 20, height: 22)
            )

            let output = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: item,
                    placement: first,
                    index: 4
                ),
                _LazyLayout_PlacedSubview(
                    item: item,
                    placement: duplicate,
                    index: 5
                ),
            ], to: cache)

            XCTAssertEqual(output.count, 1)
            XCTAssertEqual(output[0].placement, first)
            XCTAssertEqual(item.placement, first)
            XCTAssertEqual(item.displayIndex, 0)
            XCTAssertTrue(item.hasWarned)
        }
    }

    func testLazyLayoutViewCacheCommitSeparatesDisplayedAndTransitionTargets() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let list = EditingViewList(edit: .removed)
            let listAttribute = graph.makeInput(value: list as any ViewList)
            let cache = PlacementRecordingLazyLayoutViewCache(
                viewGraph: host,
                parentSubgraph: AGSubgraph(),
                inputs: makeViewInputs(graph: graph),
                outputs: _ViewOutputs(),
                list: listAttribute,
                layoutDirection: graph.makeInput(value: .leftToRight),
                nearestScrollableAxes: graph.makeInput(value: Axis.Set()),
                placedSubviews: graph.makeInput(value: []),
                prefetchSignal: graph.makeInput(value: ()),
                scrollPosition: OptionalAttribute(),
                accessibilityEnabled: graph.makeInput(value: false)
            )
            let (_, outgoing, outgoingState) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 1,
                list: list
            )
            let (_, incoming, incomingState) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                list: list
            )

            cache.isFirstCommit = false
            outgoing.displayIndex = 0
            outgoing.transitionType = Int.self
            outgoingState.setValue(
                LazyLayoutCacheItem.State(phase: .identity)
            )
            incoming.displayIndex = nil
            incomingState.setValue(
                LazyLayoutCacheItem.State(
                    phase: .willAppear,
                    enableTransitions: true
                )
            )

            let previous = _Placement(
                proposedSize: CGSize(width: 30, height: 32),
                at: CGPoint(x: 3, y: 4)
            )
            let incomingTarget = _Placement(
                proposedSize: CGSize(width: 40, height: 42),
                at: CGPoint(x: 5, y: 6)
            )
            let incomingInitial = _Placement(
                proposedSize: CGSize(width: 50, height: 52),
                at: CGPoint(x: 7, y: 8)
            )
            let outgoingFinal = _Placement(
                proposedSize: CGSize(width: 60, height: 62),
                at: CGPoint(x: 9, y: 10)
            )
            cache.initialResult = incomingInitial
            cache.finalResult = outgoingFinal
            outgoing.placement = previous

            let output = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: incoming,
                    placement: incomingTarget,
                    index: 1
                ),
            ], to: cache, from: [
                _LazyLayout_PlacedSubview(
                    item: outgoing,
                    placement: previous,
                    index: 0
                ),
            ])

            XCTAssertEqual(cache.initialCallCount, 1)
            XCTAssertEqual(cache.finalCallCount, 1)
            XCTAssertTrue(cache.lastWasInsertedToSubviews)
            XCTAssertTrue(cache.lastWasRemovedFromSubviews)
            XCTAssertEqual(incoming.placement, incomingTarget)
            XCTAssertEqual(outgoing.placement, outgoingFinal)
            XCTAssertEqual(
                output.first { $0.item === incoming }?.placement,
                incomingInitial
            )
            XCTAssertEqual(
                output.first { $0.item === outgoing }?.placement,
                previous
            )
            XCTAssertTrue(outgoing.willEnableTransitions)
            XCTAssertTrue(outgoing.willAnimateRemoval)
            XCTAssertEqual(outgoing.removedSeed, cache.placementSeed)
        }
    }

    func testLazyLayoutViewCacheCommitUpdatesPlacedIndexDensityByContainingSize() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, first, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, second, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            let placement = _Placement(
                proposedSize: CGSize(width: 10, height: 12)
            )

            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: first,
                    placement: placement,
                    index: 10
                ),
                _LazyLayout_PlacedSubview(
                    item: second,
                    placement: placement,
                    index: 14
                ),
            ], to: cache, containingSize: CGSize(width: 100, height: 80))
            XCTAssertEqual(cache.averagePlacedCount.value, 4)
            XCTAssertEqual(cache.averagePlacedCount.count, 1)

            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: first,
                    placement: placement,
                    index: 20
                ),
                _LazyLayout_PlacedSubview(
                    item: second,
                    placement: placement,
                    index: 22
                ),
            ], to: cache, containingSize: CGSize(width: 100, height: 80))
            XCTAssertEqual(cache.averagePlacedCount.value, 3)
            XCTAssertEqual(cache.averagePlacedCount.count, 2)

            _ = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: first,
                    placement: placement,
                    index: 30
                ),
                _LazyLayout_PlacedSubview(
                    item: second,
                    placement: placement,
                    index: 35
                ),
            ], to: cache, containingSize: CGSize(width: 120, height: 80))
            XCTAssertEqual(cache.averagePlacedCount.value, 5)
            XCTAssertEqual(cache.averagePlacedCount.count, 1)
        }
    }

    func testLazyLayoutViewCacheScrollCommitClearsStalePlacementDirectly() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, state) = makeLazyCache(
                host: host,
                supportsPrefetching: true
            )
            var transaction = Transaction()
            transaction.fromScrollView = true
            cache.inputs.base.transaction.setValue(transaction)
            cache.lru.transactionSeed = 17
            item.displayIndex = 0
            item.placement = _Placement(
                proposedSize: CGSize(width: 10, height: 12)
            )
            state.setValue(
                LazyLayoutCacheItem.State(phase: .identity)
            )

            let output = commitPlacedSubviews(
                [],
                to: cache,
                from: [
                    _LazyLayout_PlacedSubview(
                        item: item,
                        placement: try! XCTUnwrap(item.placement),
                        index: 0
                    ),
                ]
            )

            XCTAssertTrue(output.isEmpty)
            XCTAssertNil(item.displayIndex)
            XCTAssertNil(item.placement)
            XCTAssertEqual(item.prefetchPhase, .pendingRemoval)
            XCTAssertEqual(item.removalTransactionSeed, 17)
            XCTAssertFalse(host.hasPendingTransactions)
        }
    }

    func testLazyLayoutViewCacheReuseSkipsDisplayedCandidates() {
        let host = GraphHost()

        host.data.withCurrent {
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, displayed, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                reuseIdentifier: targetID.reuseIdentifier
            )
            let (_, reusable, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            displayed.insertionTransactionSeed = 18
            displayed.placementSeed = 10
            displayed.usedSeed = 1
            displayed.displayIndex = 0
            displayed.prefetchPhase = .pendingDisplay
            reusable.insertionTransactionSeed = 18
            reusable.placementSeed = 10
            reusable.usedSeed = 10

            XCTAssertTrue(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                ) === reusable
            )

            cache.items.removeValue(forKey: reusable.id.canonicalID)
            cache.lru.invalidate()
            XCTAssertNil(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                )
            )
        }
    }

    func testLazyLayoutViewCacheReuseAllowsPendingRemovalCandidates() {
        let host = GraphHost()

        host.data.withCurrent {
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, pendingRemoval, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                reuseIdentifier: targetID.reuseIdentifier
            )
            let (_, reusable, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            pendingRemoval.insertionTransactionSeed = 18
            pendingRemoval.placementSeed = 10
            pendingRemoval.usedSeed = 1
            pendingRemoval.prefetchPhase = .pendingRemoval
            reusable.insertionTransactionSeed = 18
            reusable.placementSeed = 10
            reusable.usedSeed = 10

            XCTAssertTrue(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                ) === pendingRemoval
            )

            cache.items.removeValue(forKey: pendingRemoval.id.canonicalID)
            cache.lru.invalidate()
            XCTAssertTrue(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                ) === reusable
            )
        }
    }

    func testLazyLayoutViewCacheReuseSkipsTransitionTypeMismatch() {
        let host = GraphHost()

        host.data.withCurrent {
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, mismatched, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                reuseIdentifier: targetID.reuseIdentifier
            )
            let (_, reusable, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            mismatched.insertionTransactionSeed = 18
            mismatched.placementSeed = 10
            mismatched.usedSeed = 1
            mismatched.transitionType = OpacityTransition.self
            reusable.insertionTransactionSeed = 18
            reusable.placementSeed = 10
            reusable.usedSeed = 10
            reusable.transitionType = IdentityTransition.self

            XCTAssertTrue(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: IdentityTransition.self
                ) === reusable
            )

            cache.items.removeValue(forKey: reusable.id.canonicalID)
            cache.lru.invalidate()
            XCTAssertNil(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: IdentityTransition.self
                )
            )
        }
    }

    func testLazyLayoutViewCacheReuseSkipsFreshCandidates() {
        let host = GraphHost()

        host.data.withCurrent {
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, fresh, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                reuseIdentifier: targetID.reuseIdentifier
            )
            let (_, reusable, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            fresh.insertionTransactionSeed = 20
            fresh.placementSeed = 10
            fresh.usedSeed = 1
            reusable.insertionTransactionSeed = 18
            reusable.placementSeed = 10
            reusable.usedSeed = 10

            XCTAssertTrue(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                ) === reusable
            )

            cache.items.removeValue(forKey: reusable.id.canonicalID)
            cache.lru.invalidate()
            XCTAssertNil(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                )
            )
        }
    }

    func testLazyLayoutViewCacheReuseSkipsCurrentSeedCandidates() {
        let host = GraphHost()

        host.data.withCurrent {
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, currentSeed, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                reuseIdentifier: targetID.reuseIdentifier
            )
            let (_, reusable, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            cache.placementSeed = 20
            currentSeed.insertionTransactionSeed = 18
            currentSeed.placementSeed = 20
            currentSeed.usedSeed = 1
            reusable.insertionTransactionSeed = 18
            reusable.placementSeed = 10
            reusable.usedSeed = 10

            XCTAssertTrue(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                ) === reusable
            )

            cache.items.removeValue(forKey: reusable.id.canonicalID)
            cache.lru.invalidate()
            XCTAssertNil(
                cache.reusedItem(
                    for: targetID.canonicalID,
                    reuseIdentifier: targetID.reuseIdentifier,
                    transitionType: nil
                )
            )
        }
    }

    func testLazyLayoutViewCacheUpdateItemPhaseSkipsInvalidSubgraph() {
        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        let placement = _Placement(proposedSize: CGSize(width: 10, height: 12))
        let pendingPlacement = _Placement(proposedSize: CGSize(width: 30, height: 32))
        host.data.withCurrent {
            item.placement = placement
            item.pendingPlacement = pendingPlacement
            item.willAnimateRemoval = true
            item.removedSeed = 0
            item.removalTransactionSeed = 1
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 4,
                    phase: .identity,
                    enableTransitions: false,
                    isRemoved: false
                )
            )
            item.subgraph.invalidate()
            cache.updateItemPhase(item)

            XCTAssertEqual(item.placement, placement)
            XCTAssertEqual(item.pendingPlacement, pendingPlacement)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 4,
                    phase: .identity,
                    enableTransitions: false,
                    isRemoved: false
                )
            )
        }
    }

    func testLazyLayoutViewCacheUpdateItemPhaseSameSeedResetsNonIdentityPhaseOnly() {
        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        let placement = _Placement(proposedSize: CGSize(width: 14, height: 16))
        let pendingPlacement = _Placement(proposedSize: CGSize(width: 18, height: 20))
        host.data.withCurrent {
            cache.placementSeed = 7
            item.commitSeed = 7
            item.placement = placement
            item.pendingPlacement = pendingPlacement
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 5,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: true
                )
            )

            cache.updateItemPhase(item)

            XCTAssertEqual(item.placement, placement)
            XCTAssertEqual(item.pendingPlacement, pendingPlacement)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 5,
                    phase: .identity,
                    enableTransitions: true,
                    isRemoved: true
                )
            )

            cache.updateItemPhase(item)
            XCTAssertEqual(item.placement, placement)
            XCTAssertEqual(item.pendingPlacement, pendingPlacement)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 5,
                    phase: .identity,
                    enableTransitions: true,
                    isRemoved: true
                )
            )
        }
    }

    func testLazyLayoutViewCacheUpdateItemPhaseStaleIdentityWithDisplayIndexMarksDisappearing() {
        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        let placement = _Placement(proposedSize: CGSize(width: 21, height: 23))
        let pendingPlacement = _Placement(proposedSize: CGSize(width: 25, height: 27))
        host.data.withCurrent {
            cache.placementSeed = 8
            item.commitSeed = 7
            item.displayIndex = 3
            item.placement = placement
            item.pendingPlacement = pendingPlacement
            item.willEnableTransitions = true
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 6,
                    phase: .identity,
                    enableTransitions: false,
                    isRemoved: false
                )
            )

            cache.updateItemPhase(item)

            XCTAssertEqual(item.displayIndex, 3)
            XCTAssertEqual(item.placement, placement)
            XCTAssertEqual(item.pendingPlacement, pendingPlacement)
            XCTAssertFalse(item.willEnableTransitions)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 6,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )
        }
    }

    func testLazyLayoutViewCacheUpdateItemPhaseActiveAnimationLeavesStateAndPlacements() {
        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        let placement = _Placement(proposedSize: CGSize(width: 22, height: 24))
        let pendingPlacement = _Placement(proposedSize: CGSize(width: 26, height: 28))
        host.data.withCurrent {
            cache.placementSeed = 9
            item.commitSeed = 8
            item.animationCount = 1
            item.placement = placement
            item.pendingPlacement = pendingPlacement
            item.removedSeed = 0
            item.removalTransactionSeed = 1
            item.willAnimateRemoval = true
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 6,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )

            cache.updateItemPhase(item)

            XCTAssertEqual(item.placement, placement)
            XCTAssertEqual(item.pendingPlacement, pendingPlacement)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 6,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )
        }
    }

    func testLazyLayoutViewCacheDidDisappearStaleItemQueuesPhaseWithoutRestampingRemovalSeed() {

        let host = GraphHost()
        let (cache, placed, stale, state) = host.data.withCurrent {
            let (cache, placed, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (_, stale, state) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            return (cache, placed, stale, state)
        }

        host.data.withCurrent {
            cache.lru.transactionSeed = 30
            cache.lru.maxIdle = 2
            cache.placementSeed = 9
            placed.commitSeed = 9
            stale.commitSeed = 8
            stale.removalTransactionSeed = 30
            stale.prefetchPhase = .pendingDisplay
            let stalePlacement = _Placement(
                proposedSize: CGSize(width: 20, height: 24)
            )
            stale.displayIndex = 0
            stale.placement = stalePlacement
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 6,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )

            let output = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: placed,
                    placement: _Placement(proposedSize: CGSize(width: 10, height: 12)),
                    index: 4
                ),
            ], to: cache, from: [
                _LazyLayout_PlacedSubview(
                    item: stale,
                    placement: stalePlacement,
                    index: 5
                ),
            ])

            XCTAssertEqual(cache.placedIndices.min, 4)
            XCTAssertEqual(cache.placedIndices.max, 4)
            XCTAssertEqual(output.count, 2)
            XCTAssertTrue(output.contains { $0.item === stale })
            XCTAssertEqual(stale.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(stale.removalTransactionSeed, 30)
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertNil(stale.displayIndex)
            XCTAssertNil(stale.placement)
            XCTAssertEqual(stale.prefetchPhase, .pendingRemoval)
            XCTAssertTrue(state.value.isRemoved)

            cache.lru.transactionSeed = 31
            cache.updatePrefetchPhases()
            XCTAssertEqual(stale.prefetchPhase, .pendingRemoval)

            cache.lru.transactionSeed = 33
            cache.updatePrefetchPhases()
            XCTAssertEqual(stale.prefetchPhase, .notPrefetching)
        }
    }

    func testLazyLayoutViewCacheSecondPlacedCommitPromotesWillAppearThroughPhaseMutation() {
        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host)
        }
        let placedSubview = _LazyLayout_PlacedSubview(
            item: item,
            placement: _Placement(proposedSize: CGSize(width: 18, height: 20)),
            index: 0
        )

        host.data.withCurrent {
            cache.placementSeed = 4
            item.commitSeed = 3
            item.displayIndex = nil
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 2,
                    phase: .willAppear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )

            let firstOutput = commitPlacedSubviews([placedSubview], to: cache)

            XCTAssertFalse(cache.isFirstCommit)
            XCTAssertFalse(host.hasPendingTransactions)
            XCTAssertEqual(state.value.phase, .willAppear)

            _ = commitPlacedSubviews(
                [placedSubview],
                to: cache,
                from: firstOutput
            )

            XCTAssertTrue(host.hasPendingTransactions)
            XCTAssertEqual(state.value.phase, .willAppear)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(item.commitSeed, cache.placementSeed)
            XCTAssertEqual(state.value.phase, .identity)
            XCTAssertTrue(state.value.enableTransitions)
            XCTAssertFalse(state.value.isRemoved)
        }
    }

    func testLazyLayoutViewCacheCancelledPlacementKeepsFirstCommitState() {
        let host = GraphHost()
        let (cache, item, _) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        host.data.withCurrent {
            _ = commitPlacedSubviews(
                [
                    _LazyLayout_PlacedSubview(
                        item: item,
                        placement: _Placement(
                            proposedSize: CGSize(width: 18, height: 20)
                        ),
                        index: 0
                    ),
                ],
                to: cache,
                wasCancelled: true
            )

            XCTAssertTrue(cache.isFirstCommit)
        }
    }

    func testLazyLayoutViewCacheCommitDoesNotSpecialCaseSourcePresentStaleItems() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let recorder = ViewListEditRecorder()
            let list = SegmentedLayoutViewList(
                graph: graph,
                sizes: [
                    CGSize(width: 10, height: 11),
                    CGSize(width: 20, height: 21),
                    CGSize(width: 30, height: 31),
                ]
            )
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                supportsPrefetching: true,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            cache.lru.transactionSeed = 8
            cache.placementSeed = 1

            let retainedID = _ViewList_ID(implicitID: 0).elementID(at: 0)
            let visibleID = _ViewList_ID(implicitID: 1).elementID(at: 1)
            let editingList = EditingViewList(
                edit: nil,
                recorder: recorder,
                sourceIDs: [retainedID]
            )
            let retained = cache.item(
                data: makeLazyData(
                    graph: graph,
                    id: retainedID,
                    list: editingList
                )
            )
            let visible = cache.item(data: makeLazyData(graph: graph, id: visibleID, list: list))
            let retainedState = retained._state
            retainedState.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 3,
                    phase: .identity,
                    enableTransitions: false,
                    isRemoved: false
                )
            )
            retained.displayIndex = 0
            retained.placement = _Placement(proposedSize: CGSize(width: 10, height: 11))
            retained.placementSeed = 1
            retained.commitSeed = 1
            retained.insertionTransactionSeed = 1
            cache.collect()
            recorder.ids.removeAll()
            recorder.transactionIDs.removeAll()

            XCTAssertEqual(retained.parentingPhase, .inserted)
            XCTAssertTrue(retained.subgraph.parent === cache.parentSubgraph)

            let oldPlacement = try! XCTUnwrap(retained.placement)
            let output = commitPlacedSubviews([
                _LazyLayout_PlacedSubview(
                    item: visible,
                    placement: _Placement(proposedSize: CGSize(width: 20, height: 21)),
                    index: 1
                ),
            ], to: cache, from: [
                _LazyLayout_PlacedSubview(
                    item: retained,
                    placement: oldPlacement,
                    index: 0
                ),
            ])

            XCTAssertEqual(retained.parentingPhase, .inserted)
            XCTAssertEqual(retained.prefetchPhase, .notPrefetching)
            XCTAssertTrue(retained.willAnimateRemoval)
            XCTAssertEqual(retained.removedSeed, cache.placementSeed)
            XCTAssertTrue(output.contains { $0.item === retained })
            XCTAssertEqual(recorder.ids, [retained.id])
            XCTAssertEqual(recorder.firstOffsetCallCount, 0)
            XCTAssertTrue(host.hasPendingTransactions)
            XCTAssertEqual(retainedState.value.phase, .identity)
        }
    }

    func testLazyLayoutViewCacheCollectKeepsEveryOwnedItemAndEvictsOnlyExpiredItems() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, recentlyUsed, _) = makeLazyCache(
                host: host,
                implicitID: 1
            )
            let (_, currentlyPlaced, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            let (_, animating, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 3
            )
            let (_, prefetchedThisCommit, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 4
            )
            let (_, pendingRemoval, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 5
            )
            let (_, expired, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 6
            )
            let retainedItems = [
                recentlyUsed,
                currentlyPlaced,
                animating,
                prefetchedThisCommit,
                pendingRemoval,
            ]

            cache.placementSeed = 17
            cache.commitSeed = 13
            cache.lru.maxIdle = 0
            cache.lru.invalidate()
            _ = cache.lru.updatedItems(Array(cache.items.values))

            for item in retainedItems + [expired] {
                item.usedSeed = 0
                item.placementSeed = 0
                item.animationCount = 0
                item.prefetchSeed = 0
                item.prefetchPhase = .notPrefetching
            }
            recentlyUsed.usedSeed = cache.lru.usedSeed
            currentlyPlaced.placementSeed = cache.placementSeed
            animating.animationCount = 1
            prefetchedThisCommit.prefetchSeed = cache.commitSeed
            pendingRemoval.prefetchPhase = .pendingRemoval

            XCTAssertNotNil(cache.lru.items)
            cache.collect()

            for item in retainedItems {
                XCTAssertTrue(cache.item(for: item.id.canonicalID) === item)
                XCTAssertTrue(AGSubgraphIsValid(item.subgraph))
            }
            XCTAssertNil(cache.item(for: expired.id.canonicalID))
            XCTAssertFalse(AGSubgraphIsValid(expired.subgraph))
            XCTAssertNil(cache.lru.items)
        }
    }

    func testLazyLayoutViewCacheUpdateItemPhaseStaleWillAppearLeavesStateAndPlacements() {
        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        let placement = _Placement(proposedSize: CGSize(width: 32, height: 34))
        let pendingPlacement = _Placement(proposedSize: CGSize(width: 36, height: 38))
        host.data.withCurrent {
            cache.placementSeed = 11
            item.commitSeed = 10
            item.animationCount = 0
            item.placement = placement
            item.pendingPlacement = pendingPlacement
            item.removedSeed = 0
            item.removalTransactionSeed = 1
            item.willAnimateRemoval = true
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 7,
                    phase: .willAppear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )

            cache.updateItemPhase(item)

            XCTAssertEqual(item.placement, placement)
            XCTAssertEqual(item.pendingPlacement, pendingPlacement)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 7,
                    phase: .willAppear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )
        }
    }

    func testLazyLayoutViewCacheUpdateItemPhasesTraversesCachedItems() {
        let host = GraphHost()

        let (cache, sameSeedItem, sameSeedState, displayedItem, displayedState) = host.data.withCurrent {
            let first = makeLazyCache(host: host)
            let second = makeLazyCache(host: host, cache: first.cache, implicitID: 2)
            return (first.cache, first.item, first.state, second.item, second.state)
        }

        host.data.withCurrent {
            cache.placementSeed = 15
            sameSeedItem.commitSeed = 15
            sameSeedState.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 2,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: true
                )
            )

            displayedItem.commitSeed = 14
            displayedItem.displayIndex = 3
            displayedItem.willEnableTransitions = true
            displayedState.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 4,
                    phase: .identity,
                    enableTransitions: false,
                    isRemoved: false
                )
            )

            cache.updateItemPhases()

            XCTAssertEqual(
                sameSeedState.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 2,
                    phase: .identity,
                    enableTransitions: true,
                    isRemoved: true
                )
            )
            XCTAssertEqual(displayedItem.displayIndex, 3)
            XCTAssertFalse(displayedItem.willEnableTransitions)
            XCTAssertEqual(
                displayedState.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 4,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )
        }
    }

    func testLazyLayoutViewCacheItemDataReturnsExistingAndRefreshesMetadata() {
        let host = GraphHost()

        host.data.withCurrent {
            let id = _ViewList_ID(implicitID: 1)
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                reuseIdentifier: id.reuseIdentifier
            )
            var traits = ViewTraitCollection()
            traits[ZIndexTraitKey.self] = 7

            let data = makeLazyData(graph: host.data.graph, id: id, traits: traits)
            let returned = cache.item(data: data)

            XCTAssertTrue(returned === item)
            XCTAssertEqual(item.zIndex, 7)
            XCTAssertEqual(item.reuseIdentifier, id.reuseIdentifier)
            XCTAssertTrue(cache.item(for: id.canonicalID) === item)
        }
    }

    func testLazyLayoutViewCacheItemForSubgraphUsesItemIdentity() {
        let host = GraphHost()

        host.data.withCurrent {
            let id = _ViewList_ID(implicitID: 1)
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: id.index,
                reuseIdentifier: id.reuseIdentifier
            )

            XCTAssertTrue(cache.item(for: item.subgraph) === item)
            XCTAssertEqual(cache.item(for: item.subgraph)?.id.canonicalID, id.canonicalID)
            XCTAssertNil(cache.item(for: AGSubgraph()))
        }
    }

    func testLazyCacheItemBeginPrefetchingSkipsDisplayedItem() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host)
            let placement = _Placement(proposedSize: CGSize(width: 11, height: 13))
            cache.commitSeed = 9
            item.displayIndex = 4
            item.prefetchSeed = 5
            item.prefetchPhase = .pendingDisplay
            item.placement = placement

            item.beginPrefetching(at: ProposedViewSize(width: 20, height: 30))

            XCTAssertEqual(item.prefetchSeed, 5)
            XCTAssertEqual(item.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(item.placement, placement)
        }
    }

    func testLazyCacheItemBeginPrefetchingCopiesCacheSeedAndCapability() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host)
            cache.commitSeed = 17
            item.displayIndex = nil
            item.prefetchSeed = 3
            item.prefetchPhase = .pendingDisplay

            item.beginPrefetching(at: ProposedViewSize(width: 20, height: 30))

            XCTAssertEqual(item.prefetchSeed, 17)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
            XCTAssertEqual(item.placement, _Placement(proposedSize: CGSize(width: 20, height: 30)))
        }
    }

    func testLazyLayoutViewCachePrefetchCapabilityUsesHookAndRendererGate() {

        let host = GraphHost()

        host.data.withCurrent {
            let (baseCache, _, _) = makeLazyCache(host: host, implicitID: 1)
            XCTAssertFalse(baseCache.supportsPrefetching)
            XCTAssertFalse(baseCache.supportsViewHierarchyPrefetching)

            let (prefetchCache, item, _) = makeLazyCache(
                host: host,
                implicitID: 2,
                supportsPrefetching: true
            )
            XCTAssertTrue(prefetchCache.supportsPrefetching)
            XCTAssertTrue(prefetchCache.supportsViewHierarchyPrefetching)

            prefetchCache.inputs[UsingGraphicsRenderer.self] = true
            XCTAssertFalse(prefetchCache.supportsViewHierarchyPrefetching)

            prefetchCache.inputs[UsingGraphicsRenderer.self] = false
            XCTAssertTrue(prefetchCache.supportsViewHierarchyPrefetching)
            prefetchCache.commitSeed = 41
            item.displayIndex = nil
            item.prefetchPhase = .pendingDisplay
            item.beginPrefetching(at: ProposedViewSize(width: 20, height: 30))
            XCTAssertEqual(item.prefetchSeed, 41)
            XCTAssertEqual(item.prefetchPhase, .prefetching)
        }
    }

    func testConcreteLazyLayoutViewCachePrefetchCapabilityUsesParentSubgraphAndAxis() {

        let host = GraphHost()

        host.data.withCurrent {
            let vertical = makeConcreteLazyGridCache(
                host: host,
                layout: LazyVGridLayout(
                    columns: [GridItem(.fixed(12))],
                    alignment: .center,
                    spacing: nil,
                    pinnedViews: []
                ),
                nearestScrollableAxes: .vertical
            )
            XCTAssertTrue(vertical.supportsPrefetching)
            XCTAssertTrue(vertical.supportsViewHierarchyPrefetching)

            let axisMismatch = makeConcreteLazyGridCache(
                host: host,
                layout: LazyVGridLayout(
                    columns: [GridItem(.fixed(12))],
                    alignment: .center,
                    spacing: nil,
                    pinnedViews: []
                ),
                nearestScrollableAxes: .horizontal
            )
            XCTAssertFalse(axisMismatch.supportsPrefetching)
            XCTAssertFalse(axisMismatch.supportsViewHierarchyPrefetching)

            let horizontal = makeConcreteLazyGridCache(
                host: host,
                layout: LazyHGridLayout(
                    rows: [GridItem(.fixed(12))],
                    alignment: .center,
                    spacing: nil,
                    pinnedViews: []
                ),
                nearestScrollableAxes: .horizontal
            )
            XCTAssertTrue(horizontal.supportsPrefetching)
            horizontal.parentSubgraph.invalidate()
            XCTAssertFalse(horizontal.supportsPrefetching)
            XCTAssertFalse(horizontal.supportsViewHierarchyPrefetching)
        }
    }

    func testLazyLayoutViewCachePrefetchOutputsHarvestDisplayListOnly() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, displayItem, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, ordinaryItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            let (_, staleDisplayItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 3
            )

            cache.commitSeed = 12
            displayItem.prefetchSeed = 12
            ordinaryItem.prefetchSeed = 12
            staleDisplayItem.prefetchSeed = 11

            let displayNode = graph.makeInput(value: DisplayList())
            let staleDisplayNode = graph.makeInput(value: DisplayList())
            let ordinaryNode = graph.makeInput(value: ["ordinary"])

            var displayPreferences = PreferencesOutputs()
            displayPreferences.append(DisplayList.Key.self, node: displayNode.identifier)
            displayPreferences.append(
                LazyContainerOrdinaryPreferenceKey.self,
                node: ordinaryNode.identifier
            )
            displayItem.outputs = _ViewOutputs(preferences: displayPreferences)

            var ordinaryPreferences = PreferencesOutputs()
            ordinaryPreferences.append(
                LazyContainerOrdinaryPreferenceKey.self,
                node: ordinaryNode.identifier
            )
            ordinaryItem.outputs = _ViewOutputs(preferences: ordinaryPreferences)

            var stalePreferences = PreferencesOutputs()
            stalePreferences.append(DisplayList.Key.self, node: staleDisplayNode.identifier)
            staleDisplayItem.outputs = _ViewOutputs(preferences: stalePreferences)

            XCTAssertEqual(cache.prefetchOutputs(), .some)

            let outputs = cache.prefetchDisplayListOutputs()

            XCTAssertEqual(outputs.count, 1)
            XCTAssertEqual(
                outputs[0].preferences.values(for: DisplayList.Key.self),
                [displayNode.identifier]
            )
            XCTAssertTrue(
                outputs[0]
                    .preferences
                    .values(for: LazyContainerOrdinaryPreferenceKey.self)
                    .isEmpty
            )

            let secondDisplayNode = graph.makeInput(value: DisplayList())
            var secondPreferences = PreferencesOutputs()
            secondPreferences.append(DisplayList.Key.self, node: secondDisplayNode.identifier)
            ordinaryItem.outputs = _ViewOutputs(preferences: secondPreferences)

            XCTAssertEqual(cache.prefetchOutputs(), .some)
        }
    }

    func testLazyLayoutViewCacheSignalPrefetchInvalidatesPrefetchSignalDependents() {
        let host = GraphHost()
        var evaluations = 0
        var dependent: Attribute<Int>!
        let (cache, _, _) = host.data.withCurrent {
            makeLazyCache(host: host)
        }

        host.data.withCurrent {
            let graph = host.data.graph
            dependent = graph.makeRule {
                _ = cache._prefetchSignal.value
                evaluations += 1
                return evaluations
            }

            XCTAssertEqual(dependent.value, 1)
        }

        Update.ensure {
            cache.signalPrefetch()
            XCTAssertEqual(evaluations, 1)
        }

        host.data.withCurrent {
            XCTAssertEqual(dependent.value, 2)
        }
    }

    func testLazyLayoutSubviewBeginPrefetchingRoutesThroughCacheItemLookup() {
        let host = GraphHost()

        host.data.withCurrent {
            let id = _ViewList_ID(implicitID: 41)
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: id.index,
                reuseIdentifier: id.reuseIdentifier
            )
            cache.commitSeed = 29
            var traits = ViewTraitCollection()
            traits[ZIndexTraitKey.self] = 12
            let data = makeLazyData(graph: host.data.graph, id: id, traits: traits)
            let context = AnyRuleContext(
                attribute: host.data.graph.makeInput(value: ()).identifier
            )
            let subview = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: data,
                index: 6
            )

            subview.beginPrefetching(at: ProposedViewSize(width: 44, height: 55))

            XCTAssertTrue(cache.item(for: id.canonicalID) === item)
            XCTAssertEqual(item.zIndex, 12)
            XCTAssertEqual(item.prefetchSeed, 29)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
            XCTAssertEqual(item.placement, _Placement(proposedSize: CGSize(width: 44, height: 55)))
        }
    }

    func testLazyLayoutSubviewProposeAndPlaceRouteThroughCacheItemLookup() {
        let host = GraphHost()

        host.data.withCurrent {
            let id = _ViewList_ID(implicitID: 42)
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: id.index,
                reuseIdentifier: id.reuseIdentifier
            )
            var traits = ViewTraitCollection()
            traits[ZIndexTraitKey.self] = 15
            let data = makeLazyData(graph: host.data.graph, id: id, traits: traits)
            let context = AnyRuleContext(
                attribute: host.data.graph.makeInput(value: ()).identifier
            )
            let subview = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: data,
                index: 8
            )

            let proposed = subview.proposeSize(ProposedViewSize(width: 24, height: 36))

            XCTAssertTrue(proposed.item === item)
            XCTAssertEqual(proposed.proposal, _ProposedSize(width: 24, height: 36))
            XCTAssertEqual(proposed.index, 8)
            XCTAssertEqual(item.zIndex, 15)
            XCTAssertEqual(
                item.pendingPlacement,
                _Placement(proposedSize: CGSize(width: 24, height: 36))
            )

            let placement = _Placement(
                proposedSize: CGSize(width: 40, height: 50),
                anchoring: .center,
                at: CGPoint(x: 3, y: 4)
            )
            let placed = subview.place(at: placement)

            XCTAssertTrue(placed.item === item)
            XCTAssertEqual(placed.placement, placement)
            XCTAssertEqual(placed.index, 8)
            XCTAssertEqual(item.pendingPlacement, placement)
            XCTAssertTrue(cache.item(for: id.canonicalID) === item)
        }
    }

    func testLazyLayoutSubviewProjectsRoleSectionTraitsAndExplicitContextLayout() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let id = _ViewList_ID(implicitID: 45)
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: id.index,
                reuseIdentifier: id.reuseIdentifier
            )
            let layoutAttribute = graph.makeInput(
                value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        CGSize(
                            width: proposal.width ?? 22,
                            height: proposal.height ?? 33
                        )
                    },
                    spacing: ViewSpacing(
                        top: 3,
                        leading: 5,
                        bottom: 7,
                        trailing: 11
                    ).spacing,
                    priority: 6,
                    explicitAlignment: { _, _ in 9 }
                )
            )
            item.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(layoutAttribute)
            )

            var traits = ViewTraitCollection()
            traits[ZIndexTraitKey.self] = 12
            traits[_LayoutTrait<LazySubviewTestLayoutValueKey>.self] = 27
            let owner = graph.makeInput(value: ())
            let context = AnyRuleContext(attribute: owner.identifier)
            let subview = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(
                    graph: graph,
                    id: id,
                    traits: traits,
                    section: LazyLayoutCacheSection(
                        id: 71,
                        isHeader: true,
                        isFooter: true
                    )
                ),
                index: 4
            )

            XCTAssertEqual(subview.kind, .header)
            XCTAssertEqual(subview.sectionID, 71)
            XCTAssertEqual(subview[ZIndexTraitKey.self], 12)
            XCTAssertEqual(subview[LazySubviewTestLayoutValueKey.self], 27)

            let layout = subview.layout
            XCTAssertEqual(layout.context.attribute, owner.identifier)
            XCTAssertNotEqual(layout.context.attribute, layoutAttribute.identifier)
            XCTAssertEqual(layout.size(in: .unspecified), CGSize(width: 22, height: 33))
            XCTAssertEqual(layout.idealSize(), CGSize(width: 22, height: 33))
            XCTAssertEqual(layout.layoutPriority, 6)
            XCTAssertEqual(
                layout.lengthThatFits(
                    _ProposedSize(width: 40, height: nil),
                    in: .horizontal
                ),
                40
            )
            XCTAssertEqual(layout.spacing(), layoutAttribute.value.spacing())
            XCTAssertEqual(
                layout.explicitAlignment(
                    HorizontalAlignment.leading.key,
                    at: ViewSize(width: 40, height: 33)
                ),
                9
            )
            XCTAssertFalse(layout.ignoresAutomaticPadding)
            XCTAssertFalse(layout.requiresSpacingProjection)

            let footer = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(
                    graph: graph,
                    id: id,
                    section: LazyLayoutCacheSection(
                        id: 72,
                        isFooter: true
                    )
                ),
                index: 4
            )
            XCTAssertEqual(footer.kind, .footer)
            XCTAssertEqual(footer.sectionID, 72)

            let normal = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(graph: graph, id: id),
                index: 4
            )
            XCTAssertEqual(normal.kind, .normal)
            XCTAssertNil(normal.sectionID)
        }
    }

    func testLazyLayoutSubviewLengthAndSpacingUsesLayoutAndPredecessorSpacing() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let currentID = _ViewList_ID(implicitID: 43)
            let predecessorID = _ViewList_ID(implicitID: 44)
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: currentID.index,
                reuseIdentifier: currentID.reuseIdentifier
            )
            let (_, predecessorItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: predecessorID.index,
                reuseIdentifier: predecessorID.reuseIdentifier
            )

            item.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        CGSize(
                            width: proposal.width ?? 100,
                            height: proposal.height ?? 200
                        )
                    },
                    spacing: ViewSpacing(top: 5, leading: 11, bottom: nil, trailing: nil).spacing
                )))
            )
            predecessorItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                    sizeThatFits: { _ in CGSize(width: 1, height: 2) },
                    spacing: ViewSpacing(top: nil, leading: nil, bottom: 7, trailing: 3).spacing
                )))
            )

            let context = AnyRuleContext(
                attribute: graph.makeInput(value: ()).identifier
            )
            let current = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(graph: graph, id: currentID),
                index: 9
            )
            let predecessor = _LazyLayout_Subview(
                cache: cache,
                context: context,
                data: makeLazyData(graph: graph, id: predecessorID),
                index: 8
            )

            let noPredecessor = current.lengthAndSpacing(
                size: ProposedViewSize(width: 24, height: 36),
                axis: .vertical,
                predecessor: nil,
                uniformSpacing: nil
            )
            XCTAssertEqual(noPredecessor.length, 36)
            XCTAssertEqual(noPredecessor.spacing, 0)

            let uniform = current.lengthAndSpacing(
                size: ProposedViewSize(width: 24, height: 36),
                axis: .vertical,
                predecessor: predecessor,
                uniformSpacing: 13
            )
            XCTAssertEqual(uniform.length, 36)
            XCTAssertEqual(uniform.spacing, 13)

            let vertical = current.lengthAndSpacing(
                size: ProposedViewSize(width: 24, height: 36),
                axis: .vertical,
                predecessor: predecessor,
                uniformSpacing: nil
            )
            XCTAssertEqual(vertical.length, 36)
            // Default edge distances select the larger side rather than
            // summing predecessor and successor values.
            XCTAssertEqual(vertical.spacing, 7)

            let horizontal = current.lengthAndSpacing(
                size: ProposedViewSize(width: 24, height: 36),
                axis: .horizontal,
                predecessor: predecessor,
                uniformSpacing: nil
            )
            XCTAssertEqual(horizontal.length, 24)
            XCTAssertEqual(horizontal.spacing, 11)
            XCTAssertTrue(cache.item(for: currentID.canonicalID) === item)
            XCTAssertTrue(cache.item(for: predecessorID.canonicalID) === predecessorItem)
        }
    }

    func testLazyLayoutPlacedSubviewComputedSurfaceUsesCacheItemAndPlacement() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let id = _ViewList_ID(implicitID: 45)
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: id.index,
                reuseIdentifier: id.reuseIdentifier
            )
            item.section = LazyLayoutCacheSection(id: 7, isHeader: true)
            item.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                    sizeThatFits: { proposal in
                        proposal.fixingUnspecifiedDimensions()
                    }
                )))
            )

            let placement = _Placement(
                proposedSize: CGSize(width: 20, height: 12),
                anchoring: .center,
                at: CGPoint(x: 50, y: 40)
            )
            let placed = _LazyLayout_PlacedSubview(
                item: item,
                placement: placement,
                index: 11
            )

            XCTAssertEqual(placed.id, id)
            XCTAssertEqual(placed.size, CGSize(width: 20, height: 12))
            XCTAssertEqual(placed.origin, CGPoint(x: 40, y: 34))
            XCTAssertEqual(placed.frame, CGRect(x: 40, y: 34, width: 20, height: 12))
            XCTAssertEqual(placed.index, 11)
            XCTAssertTrue(placed.isHeader)
            XCTAssertFalse(placed.isFooter)
            XCTAssertTrue(placed.matches(.sectionHeaders))
            XCTAssertFalse(placed.matches(.sectionFooters))
            XCTAssertTrue(placed.matches([.sectionHeaders, .sectionFooters]))
            XCTAssertEqual(
                placed.accessibilityContext,
                AccessibilitySectionContext(id: 7, isHeader: true, isFooter: false)
            )

            item.section = LazyLayoutCacheSection(isFooter: true)
            XCTAssertFalse(placed.isHeader)
            XCTAssertTrue(placed.isFooter)
            XCTAssertFalse(placed.matches(.sectionHeaders))
            XCTAssertTrue(placed.matches(.sectionFooters))
            XCTAssertEqual(
                placed.accessibilityContext,
                AccessibilitySectionContext(id: 0, isHeader: false, isFooter: true)
            )
            XCTAssertTrue(cache.item(for: id.canonicalID) === item)
        }
    }

    func testLazyLayoutPlacedSubviewsPinSectionHeadersAndFootersWithinSectionBounds() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, header, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, body, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, footer, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            header.section = LazyLayoutCacheSection(id: 77, isHeader: true)
            body.section = LazyLayoutCacheSection(id: 77)
            footer.section = LazyLayoutCacheSection(id: 77, isFooter: true)
            installSize(CGSize(width: 80, height: 40), on: header)
            installSize(CGSize(width: 80, height: 100), on: body)
            installSize(CGSize(width: 80, height: 30), on: footer)

            var placed = [
                _LazyLayout_PlacedSubview(
                    item: header,
                    placement: _Placement(
                        proposedSize: CGSize(width: 80, height: 40),
                        at: CGPoint(x: 0, y: 0)
                    ),
                    index: 0
                ),
                _LazyLayout_PlacedSubview(
                    item: body,
                    placement: _Placement(
                        proposedSize: CGSize(width: 80, height: 100),
                        at: CGPoint(x: 0, y: 40)
                    ),
                    index: 1
                ),
                _LazyLayout_PlacedSubview(
                    item: footer,
                    placement: _Placement(
                        proposedSize: CGSize(width: 80, height: 30),
                        at: CGPoint(x: 0, y: 140)
                    ),
                    index: 2
                ),
            ]

            placed.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 50),
                    contentSize: CGSize(width: 80, height: 170),
                    containerSize: CGSize(width: 80, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: [.sectionHeaders, .sectionFooters]
            )

            XCTAssertEqual(placed[0].placement.anchorPosition, CGPoint(x: 0, y: 50))
            XCTAssertEqual(placed[1].placement.anchorPosition, CGPoint(x: 0, y: 40))
            XCTAssertEqual(placed[2].placement.anchorPosition, CGPoint(x: 0, y: 100))
            XCTAssertEqual(placed[0].frame, CGRect(x: 0, y: 50, width: 80, height: 40))
            XCTAssertEqual(placed[2].frame, CGRect(x: 0, y: 100, width: 80, height: 30))
        }
    }

    func testLazyLayoutPlacedSubviewsPinSectionBoundsStayAxisSeparated() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, header, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, body, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, footer, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            header.section = LazyLayoutCacheSection(id: 77, isHeader: true)
            body.section = LazyLayoutCacheSection(id: 77)
            footer.section = LazyLayoutCacheSection(id: 77, isFooter: true)
            installSize(CGSize(width: 20, height: 40), on: header)
            installSize(CGSize(width: 80, height: 100), on: body)
            installSize(CGSize(width: 20, height: 30), on: footer)

            var placed = [
                _LazyLayout_PlacedSubview(
                    item: header,
                    placement: _Placement(
                        proposedSize: CGSize(width: 20, height: 40),
                        at: CGPoint(x: 0, y: 0)
                    ),
                    index: 0
                ),
                _LazyLayout_PlacedSubview(
                    item: body,
                    placement: _Placement(
                        proposedSize: CGSize(width: 80, height: 100),
                        at: CGPoint(x: 0, y: 40)
                    ),
                    index: 1
                ),
                _LazyLayout_PlacedSubview(
                    item: footer,
                    placement: _Placement(
                        proposedSize: CGSize(width: 20, height: 30),
                        at: CGPoint(x: 60, y: 140)
                    ),
                    index: 2
                ),
            ]

            placed.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 20, y: 50),
                    contentSize: CGSize(width: 80, height: 170),
                    containerSize: CGSize(width: 60, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: [.horizontal, .vertical],
                pinnedViews: [.sectionHeaders, .sectionFooters]
            )

            XCTAssertEqual(placed[0].placement.anchorPosition, CGPoint(x: 20, y: 50))
            XCTAssertEqual(placed[1].placement.anchorPosition, CGPoint(x: 0, y: 40))
            XCTAssertEqual(placed[2].placement.anchorPosition, CGPoint(x: 60, y: 100))
            XCTAssertEqual(placed[0].frame, CGRect(x: 20, y: 50, width: 20, height: 40))
            XCTAssertEqual(placed[2].frame, CGRect(x: 60, y: 100, width: 20, height: 30))
        }
    }

    func testLazyLayoutPinnedSectionHeaderContinuesPastFooterWithoutNextHeader() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, header, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, body, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, footer, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            header.section = LazyLayoutCacheSection(id: 77, isHeader: true)
            body.section = LazyLayoutCacheSection(id: 77)
            footer.section = LazyLayoutCacheSection(id: 77, isFooter: true)
            installSize(CGSize(width: 80, height: 40), on: header)
            installSize(CGSize(width: 80, height: 100), on: body)
            installSize(CGSize(width: 80, height: 30), on: footer)

            var placed = [
                _LazyLayout_PlacedSubview(
                    item: header,
                    placement: _Placement(
                        proposedSize: CGSize(width: 80, height: 40),
                        at: CGPoint(x: 0, y: 0)
                    ),
                    index: 0
                ),
                _LazyLayout_PlacedSubview(
                    item: body,
                    placement: _Placement(
                        proposedSize: CGSize(width: 80, height: 100),
                        at: CGPoint(x: 0, y: 40)
                    ),
                    index: 1
                ),
                _LazyLayout_PlacedSubview(
                    item: footer,
                    placement: _Placement(
                        proposedSize: CGSize(width: 80, height: 30),
                        at: CGPoint(x: 0, y: 140)
                    ),
                    index: 2
                ),
            ]

            placed.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 250),
                    contentSize: CGSize(width: 80, height: 500),
                    containerSize: CGSize(width: 80, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: [.sectionHeaders, .sectionFooters]
            )

            XCTAssertEqual(placed[0].placement.anchorPosition, CGPoint(x: 0, y: 250))
            XCTAssertEqual(placed[1].placement.anchorPosition, CGPoint(x: 0, y: 40))
            XCTAssertEqual(placed[2].placement.anchorPosition, CGPoint(x: 0, y: 140))
        }
    }

    func testLazyLayoutPinnedSectionHeaderDropsWhenNextHeaderPinsToTop() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstHeader, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, firstBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, secondHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)
            let (_, secondBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 4)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            firstHeader.section = LazyLayoutCacheSection(id: 10, isHeader: true)
            firstBody.section = LazyLayoutCacheSection(id: 10)
            secondHeader.section = LazyLayoutCacheSection(id: 20, isHeader: true)
            secondBody.section = LazyLayoutCacheSection(id: 20)
            installSize(CGSize(width: 80, height: 30), on: firstHeader)
            installSize(CGSize(width: 80, height: 100), on: firstBody)
            installSize(CGSize(width: 80, height: 30), on: secondHeader)
            installSize(CGSize(width: 80, height: 200), on: secondBody)

            func makePlaced() -> [_LazyLayout_PlacedSubview] {
                [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 100),
                            at: CGPoint(x: 0, y: 30)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 130)
                        ),
                        index: 2
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 200),
                            at: CGPoint(x: 0, y: 160)
                        ),
                        index: 3
                    ),
                ]
            }

            var beforeCollision = makePlaced()
            beforeCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 129),
                    contentSize: CGSize(width: 80, height: 360),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertTrue(beforeCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(beforeCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                beforeCollision.first { $0.item === firstHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 129)
            )
            XCTAssertEqual(
                beforeCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 130)
            )

            var atCollision = makePlaced()
            atCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 130),
                    contentSize: CGSize(width: 80, height: 360),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(atCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(atCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                atCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 130)
            )
        }
    }

    func testLazyLayoutHorizontalPinnedSectionHeaderDropsWhenNextHeaderPinsToLeadingEdge() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstHeader, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, firstBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, secondHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)
            let (_, secondBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 4)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            firstHeader.section = LazyLayoutCacheSection(id: 10, isHeader: true)
            firstBody.section = LazyLayoutCacheSection(id: 10)
            secondHeader.section = LazyLayoutCacheSection(id: 20, isHeader: true)
            secondBody.section = LazyLayoutCacheSection(id: 20)
            installSize(CGSize(width: 30, height: 80), on: firstHeader)
            installSize(CGSize(width: 100, height: 80), on: firstBody)
            installSize(CGSize(width: 30, height: 80), on: secondHeader)
            installSize(CGSize(width: 200, height: 80), on: secondBody)

            func makePlaced() -> [_LazyLayout_PlacedSubview] {
                [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 100, height: 80),
                            at: CGPoint(x: 30, y: 0)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 130, y: 0)
                        ),
                        index: 2
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 200, height: 80),
                            at: CGPoint(x: 160, y: 0)
                        ),
                        index: 3
                    ),
                ]
            }

            var beforeCollision = makePlaced()
            beforeCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 129, y: 0),
                    contentSize: CGSize(width: 360, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertTrue(beforeCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(beforeCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                beforeCollision.first { $0.item === firstHeader }?.placement.anchorPosition,
                CGPoint(x: 129, y: 0)
            )
            XCTAssertEqual(
                beforeCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 130, y: 0)
            )

            var atCollision = makePlaced()
            atCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 130, y: 0),
                    contentSize: CGSize(width: 360, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(atCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(atCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                atCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 130, y: 0)
            )
        }
    }

    func testLazyLayoutMiddlePinnedSectionHeaderPushesBeforeNextHeaderPins() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstHeader, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, firstBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, secondHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)
            let (_, secondBody0, _) = makeLazyCache(host: host, cache: cache, implicitID: 4)
            let (_, secondBody1, _) = makeLazyCache(host: host, cache: cache, implicitID: 5)
            let (_, secondBody2, _) = makeLazyCache(host: host, cache: cache, implicitID: 6)
            let (_, secondBody3, _) = makeLazyCache(host: host, cache: cache, implicitID: 7)
            let (_, thirdHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 8)
            let (_, thirdBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 9)
            let secondBodies = [secondBody0, secondBody1, secondBody2, secondBody3]

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            firstHeader.section = LazyLayoutCacheSection(id: 10, isHeader: true)
            firstBody.section = LazyLayoutCacheSection(id: 10)
            secondHeader.section = LazyLayoutCacheSection(id: 20, isHeader: true)
            for body in secondBodies {
                body.section = LazyLayoutCacheSection(id: 20)
            }
            thirdHeader.section = LazyLayoutCacheSection(id: 30, isHeader: true)
            thirdBody.section = LazyLayoutCacheSection(id: 30)
            installSize(CGSize(width: 80, height: 30), on: firstHeader)
            installSize(CGSize(width: 80, height: 100), on: firstBody)
            installSize(CGSize(width: 80, height: 30), on: secondHeader)
            for body in secondBodies {
                installSize(CGSize(width: 80, height: 50), on: body)
            }
            installSize(CGSize(width: 80, height: 30), on: thirdHeader)
            installSize(CGSize(width: 80, height: 100), on: thirdBody)

            func makePlaced() -> [_LazyLayout_PlacedSubview] {
                [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 100),
                            at: CGPoint(x: 0, y: 30)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 130)
                        ),
                        index: 2
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody0,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 50),
                            at: CGPoint(x: 0, y: 160)
                        ),
                        index: 3
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody1,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 50),
                            at: CGPoint(x: 0, y: 210)
                        ),
                        index: 4
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody2,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 50),
                            at: CGPoint(x: 0, y: 260)
                        ),
                        index: 5
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody3,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 50),
                            at: CGPoint(x: 0, y: 310)
                        ),
                        index: 6
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 360)
                        ),
                        index: 7
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 100),
                            at: CGPoint(x: 0, y: 390)
                        ),
                        index: 8
                    ),
                ]
            }

            var firstCollision = makePlaced()
            firstCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 130),
                    contentSize: CGSize(width: 80, height: 490),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(firstCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(firstCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                firstCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 130)
            )

            var beforePush = makePlaced()
            beforePush.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 300),
                    contentSize: CGSize(width: 80, height: 490),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(beforePush.contains { $0.item === firstHeader })
            XCTAssertTrue(beforePush.contains { $0.item === secondHeader })
            XCTAssertTrue(beforePush.contains { $0.item === thirdHeader })
            XCTAssertEqual(
                beforePush.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 300)
            )
            XCTAssertEqual(
                beforePush.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 360)
            )

            var pushed = makePlaced()
            pushed.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 359),
                    contentSize: CGSize(width: 80, height: 490),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(pushed.contains { $0.item === firstHeader })
            XCTAssertTrue(pushed.contains { $0.item === secondHeader })
            XCTAssertTrue(pushed.contains { $0.item === thirdHeader })
            XCTAssertEqual(
                pushed.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 330)
            )
            XCTAssertEqual(
                pushed.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 360)
            )

            var atSecondCollision = makePlaced()
            atSecondCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 360),
                    contentSize: CGSize(width: 80, height: 490),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(atSecondCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(atSecondCollision.contains { $0.item === secondHeader })
            XCTAssertTrue(atSecondCollision.contains { $0.item === thirdHeader })
            XCTAssertEqual(
                atSecondCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 330)
            )
            XCTAssertEqual(
                atSecondCollision.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 360)
            )
        }
    }

    func testLazyLayoutShortMiddlePinnedSectionHeadersUseNaturalAndOffscreenPositions() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstHeader, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, firstBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, secondHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)
            let (_, secondBody0, _) = makeLazyCache(host: host, cache: cache, implicitID: 4)
            let (_, secondBody1, _) = makeLazyCache(host: host, cache: cache, implicitID: 5)
            let (_, thirdHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 6)
            let (_, thirdBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 7)
            let secondBodies = [secondBody0, secondBody1]

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            firstHeader.section = LazyLayoutCacheSection(id: 10, isHeader: true)
            firstBody.section = LazyLayoutCacheSection(id: 10)
            secondHeader.section = LazyLayoutCacheSection(id: 20, isHeader: true)
            for body in secondBodies {
                body.section = LazyLayoutCacheSection(id: 20)
            }
            thirdHeader.section = LazyLayoutCacheSection(id: 30, isHeader: true)
            thirdBody.section = LazyLayoutCacheSection(id: 30)
            installSize(CGSize(width: 80, height: 30), on: firstHeader)
            installSize(CGSize(width: 80, height: 100), on: firstBody)
            installSize(CGSize(width: 80, height: 30), on: secondHeader)
            for body in secondBodies {
                installSize(CGSize(width: 80, height: 50), on: body)
            }
            installSize(CGSize(width: 80, height: 30), on: thirdHeader)
            installSize(CGSize(width: 80, height: 100), on: thirdBody)

            func makePlaced() -> [_LazyLayout_PlacedSubview] {
                [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 100),
                            at: CGPoint(x: 0, y: 30)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 130)
                        ),
                        index: 2
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody0,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 50),
                            at: CGPoint(x: 0, y: 160)
                        ),
                        index: 3
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody1,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 50),
                            at: CGPoint(x: 0, y: 210)
                        ),
                        index: 4
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 260)
                        ),
                        index: 5
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 100),
                            at: CGPoint(x: 0, y: 290)
                        ),
                        index: 6
                    ),
                ]
            }

            func pinned(at offset: CGFloat) -> [_LazyLayout_PlacedSubview] {
                var placed = makePlaced()
                placed.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: CGPoint(x: 0, y: offset),
                        contentSize: CGSize(width: 80, height: 390),
                        containerSize: CGSize(width: 80, height: 120)
                    ),
                    layoutDirection: .leftToRight,
                    axes: .vertical,
                    pinnedViews: .sectionHeaders
                )
                return placed
            }

            let atFirstCollision = pinned(at: 130)
            XCTAssertFalse(atFirstCollision.contains { $0.item === firstHeader })
            XCTAssertEqual(
                atFirstCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 130)
            )

            let afterMiddleNatural = pinned(at: 131)
            XCTAssertFalse(afterMiddleNatural.contains { $0.item === firstHeader })
            XCTAssertEqual(
                afterMiddleNatural.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 130)
            )
            XCTAssertEqual(
                afterMiddleNatural.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 260)
            )

            let atMiddleTrailingEdge = pinned(at: 160)
            XCTAssertEqual(
                atMiddleTrailingEdge.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 130)
            )
            XCTAssertEqual(
                atMiddleTrailingEdge.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 260)
            )

            let afterMiddleTrailingEdge = pinned(at: 161)
            XCTAssertEqual(
                afterMiddleTrailingEdge.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: -30)
            )
            XCTAssertEqual(
                afterMiddleTrailingEdge.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 260)
            )

            let beforeThirdCollision = pinned(at: 259)
            XCTAssertEqual(
                beforeThirdCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: -30)
            )
            XCTAssertEqual(
                beforeThirdCollision.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 260)
            )

            let atThirdCollision = pinned(at: 260)
            XCTAssertFalse(atThirdCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                atThirdCollision.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 260)
            )

            let afterLastNatural = pinned(at: 280)
            XCTAssertEqual(
                afterLastNatural.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 260)
            )

            let afterLastTrailingEdge = pinned(at: 291)
            XCTAssertEqual(
                afterLastTrailingEdge.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: -30)
            )
        }
    }

    func testLazyLayoutHorizontalMiddlePinnedSectionHeaderPushesBeforeNextHeaderPins() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstHeader, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, firstBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, secondHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)
            let (_, secondBody0, _) = makeLazyCache(host: host, cache: cache, implicitID: 4)
            let (_, secondBody1, _) = makeLazyCache(host: host, cache: cache, implicitID: 5)
            let (_, secondBody2, _) = makeLazyCache(host: host, cache: cache, implicitID: 6)
            let (_, secondBody3, _) = makeLazyCache(host: host, cache: cache, implicitID: 7)
            let (_, thirdHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 8)
            let (_, thirdBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 9)
            let secondBodies = [secondBody0, secondBody1, secondBody2, secondBody3]

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            firstHeader.section = LazyLayoutCacheSection(id: 10, isHeader: true)
            firstBody.section = LazyLayoutCacheSection(id: 10)
            secondHeader.section = LazyLayoutCacheSection(id: 20, isHeader: true)
            for body in secondBodies {
                body.section = LazyLayoutCacheSection(id: 20)
            }
            thirdHeader.section = LazyLayoutCacheSection(id: 30, isHeader: true)
            thirdBody.section = LazyLayoutCacheSection(id: 30)
            installSize(CGSize(width: 30, height: 80), on: firstHeader)
            installSize(CGSize(width: 100, height: 80), on: firstBody)
            installSize(CGSize(width: 30, height: 80), on: secondHeader)
            for body in secondBodies {
                installSize(CGSize(width: 50, height: 80), on: body)
            }
            installSize(CGSize(width: 30, height: 80), on: thirdHeader)
            installSize(CGSize(width: 100, height: 80), on: thirdBody)

            func makePlaced() -> [_LazyLayout_PlacedSubview] {
                [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 100, height: 80),
                            at: CGPoint(x: 30, y: 0)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 130, y: 0)
                        ),
                        index: 2
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody0,
                        placement: _Placement(
                            proposedSize: CGSize(width: 50, height: 80),
                            at: CGPoint(x: 160, y: 0)
                        ),
                        index: 3
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody1,
                        placement: _Placement(
                            proposedSize: CGSize(width: 50, height: 80),
                            at: CGPoint(x: 210, y: 0)
                        ),
                        index: 4
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody2,
                        placement: _Placement(
                            proposedSize: CGSize(width: 50, height: 80),
                            at: CGPoint(x: 260, y: 0)
                        ),
                        index: 5
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody3,
                        placement: _Placement(
                            proposedSize: CGSize(width: 50, height: 80),
                            at: CGPoint(x: 310, y: 0)
                        ),
                        index: 6
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 360, y: 0)
                        ),
                        index: 7
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 100, height: 80),
                            at: CGPoint(x: 390, y: 0)
                        ),
                        index: 8
                    ),
                ]
            }

            var firstCollision = makePlaced()
            firstCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 130, y: 0),
                    contentSize: CGSize(width: 490, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(firstCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(firstCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                firstCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 130, y: 0)
            )

            var beforePush = makePlaced()
            beforePush.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 300, y: 0),
                    contentSize: CGSize(width: 490, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(beforePush.contains { $0.item === firstHeader })
            XCTAssertTrue(beforePush.contains { $0.item === secondHeader })
            XCTAssertTrue(beforePush.contains { $0.item === thirdHeader })
            XCTAssertEqual(
                beforePush.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 300, y: 0)
            )
            XCTAssertEqual(
                beforePush.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 360, y: 0)
            )

            var pushed = makePlaced()
            pushed.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 359, y: 0),
                    contentSize: CGSize(width: 490, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(pushed.contains { $0.item === firstHeader })
            XCTAssertTrue(pushed.contains { $0.item === secondHeader })
            XCTAssertTrue(pushed.contains { $0.item === thirdHeader })
            XCTAssertEqual(
                pushed.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 330, y: 0)
            )
            XCTAssertEqual(
                pushed.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 360, y: 0)
            )

            var atSecondCollision = makePlaced()
            atSecondCollision.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 360, y: 0),
                    contentSize: CGSize(width: 490, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertFalse(atSecondCollision.contains { $0.item === firstHeader })
            XCTAssertTrue(atSecondCollision.contains { $0.item === secondHeader })
            XCTAssertTrue(atSecondCollision.contains { $0.item === thirdHeader })
            XCTAssertEqual(
                atSecondCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 330, y: 0)
            )
            XCTAssertEqual(
                atSecondCollision.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 360, y: 0)
            )
        }
    }

    func testLazyLayoutHorizontalShortMiddlePinnedSectionHeadersUseNaturalAndOffscreenPositions() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstHeader, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, firstBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            let (_, secondHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 3)
            let (_, secondBody0, _) = makeLazyCache(host: host, cache: cache, implicitID: 4)
            let (_, secondBody1, _) = makeLazyCache(host: host, cache: cache, implicitID: 5)
            let (_, thirdHeader, _) = makeLazyCache(host: host, cache: cache, implicitID: 6)
            let (_, thirdBody, _) = makeLazyCache(host: host, cache: cache, implicitID: 7)
            let secondBodies = [secondBody0, secondBody1]

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            firstHeader.section = LazyLayoutCacheSection(id: 10, isHeader: true)
            firstBody.section = LazyLayoutCacheSection(id: 10)
            secondHeader.section = LazyLayoutCacheSection(id: 20, isHeader: true)
            for body in secondBodies {
                body.section = LazyLayoutCacheSection(id: 20)
            }
            thirdHeader.section = LazyLayoutCacheSection(id: 30, isHeader: true)
            thirdBody.section = LazyLayoutCacheSection(id: 30)
            installSize(CGSize(width: 30, height: 80), on: firstHeader)
            installSize(CGSize(width: 100, height: 80), on: firstBody)
            installSize(CGSize(width: 30, height: 80), on: secondHeader)
            for body in secondBodies {
                installSize(CGSize(width: 50, height: 80), on: body)
            }
            installSize(CGSize(width: 30, height: 80), on: thirdHeader)
            installSize(CGSize(width: 100, height: 80), on: thirdBody)

            func makePlaced() -> [_LazyLayout_PlacedSubview] {
                [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 100, height: 80),
                            at: CGPoint(x: 30, y: 0)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 130, y: 0)
                        ),
                        index: 2
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody0,
                        placement: _Placement(
                            proposedSize: CGSize(width: 50, height: 80),
                            at: CGPoint(x: 160, y: 0)
                        ),
                        index: 3
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondBody1,
                        placement: _Placement(
                            proposedSize: CGSize(width: 50, height: 80),
                            at: CGPoint(x: 210, y: 0)
                        ),
                        index: 4
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 260, y: 0)
                        ),
                        index: 5
                    ),
                    _LazyLayout_PlacedSubview(
                        item: thirdBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 100, height: 80),
                            at: CGPoint(x: 290, y: 0)
                        ),
                        index: 6
                    ),
                ]
            }

            func pinned(at offset: CGFloat) -> [_LazyLayout_PlacedSubview] {
                var placed = makePlaced()
                placed.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: CGPoint(x: offset, y: 0),
                        contentSize: CGSize(width: 390, height: 80),
                        containerSize: CGSize(width: 120, height: 80)
                    ),
                    layoutDirection: .leftToRight,
                    axes: .horizontal,
                    pinnedViews: .sectionHeaders
                )
                return placed
            }

            let atFirstCollision = pinned(at: 130)
            XCTAssertFalse(atFirstCollision.contains { $0.item === firstHeader })
            XCTAssertEqual(
                atFirstCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 130, y: 0)
            )

            let afterMiddleNatural = pinned(at: 131)
            XCTAssertFalse(afterMiddleNatural.contains { $0.item === firstHeader })
            XCTAssertEqual(
                afterMiddleNatural.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 130, y: 0)
            )
            XCTAssertEqual(
                afterMiddleNatural.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 260, y: 0)
            )

            let atMiddleTrailingEdge = pinned(at: 160)
            XCTAssertEqual(
                atMiddleTrailingEdge.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: 130, y: 0)
            )
            XCTAssertEqual(
                atMiddleTrailingEdge.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 260, y: 0)
            )

            let afterMiddleTrailingEdge = pinned(at: 161)
            XCTAssertEqual(
                afterMiddleTrailingEdge.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: -30, y: 0)
            )
            XCTAssertEqual(
                afterMiddleTrailingEdge.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 260, y: 0)
            )

            let beforeThirdCollision = pinned(at: 259)
            XCTAssertEqual(
                beforeThirdCollision.first { $0.item === secondHeader }?.placement.anchorPosition,
                CGPoint(x: -30, y: 0)
            )
            XCTAssertEqual(
                beforeThirdCollision.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 260, y: 0)
            )

            let atThirdCollision = pinned(at: 260)
            XCTAssertFalse(atThirdCollision.contains { $0.item === secondHeader })
            XCTAssertEqual(
                atThirdCollision.first { $0.item === thirdHeader }?.placement.anchorPosition,
                CGPoint(x: 260, y: 0)
            )
        }
    }

    func testLazyLayoutPinnedSectionHeaderShortRouteUsesBodyItemCountBoundary() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            func placed(
                cache: LazyLayoutViewCache,
                sectionID: UInt32,
                implicitIDStart: Int,
                bodyHeights: [CGFloat],
                thirdHeaderY: CGFloat
            ) -> (header: LazyLayoutCacheItem, placed: [_LazyLayout_PlacedSubview]) {
                let (_, firstHeader, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart
                )
                let (_, firstBody, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 1
                )
                let (_, secondHeader, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 2
                )
                let secondBodies = bodyHeights.enumerated().map { offset, _ in
                    makeLazyCache(
                        host: host,
                        cache: cache,
                        implicitID: implicitIDStart + 3 + offset
                    ).1
                }
                let (_, thirdHeader, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 3 + bodyHeights.count
                )
                let (_, thirdBody, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 4 + bodyHeights.count
                )

                firstHeader.section = LazyLayoutCacheSection(id: sectionID, isHeader: true)
                firstBody.section = LazyLayoutCacheSection(id: sectionID)
                secondHeader.section = LazyLayoutCacheSection(id: sectionID + 1, isHeader: true)
                for body in secondBodies {
                    body.section = LazyLayoutCacheSection(id: sectionID + 1)
                }
                thirdHeader.section = LazyLayoutCacheSection(id: sectionID + 2, isHeader: true)
                thirdBody.section = LazyLayoutCacheSection(id: sectionID + 2)

                installSize(CGSize(width: 80, height: 30), on: firstHeader)
                installSize(CGSize(width: 80, height: 100), on: firstBody)
                installSize(CGSize(width: 80, height: 30), on: secondHeader)
                for (index, body) in secondBodies.enumerated() {
                    installSize(CGSize(width: 80, height: bodyHeights[index]), on: body)
                }
                installSize(CGSize(width: 80, height: 30), on: thirdHeader)
                installSize(CGSize(width: 80, height: 100), on: thirdBody)

                var result: [_LazyLayout_PlacedSubview] = [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 100),
                            at: CGPoint(x: 0, y: 30)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: 130)
                        ),
                        index: 2
                    ),
                ]

                var y: CGFloat = 160
                for (offset, body) in secondBodies.enumerated() {
                    result.append(
                        _LazyLayout_PlacedSubview(
                            item: body,
                            placement: _Placement(
                                proposedSize: CGSize(width: 80, height: bodyHeights[offset]),
                                at: CGPoint(x: 0, y: y)
                            ),
                            index: 3 + offset
                        )
                    )
                    y += bodyHeights[offset]
                }
                result.append(
                    _LazyLayout_PlacedSubview(
                        item: thirdHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 30),
                            at: CGPoint(x: 0, y: thirdHeaderY)
                        ),
                        index: 3 + secondBodies.count
                    )
                )
                result.append(
                    _LazyLayout_PlacedSubview(
                        item: thirdBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 80, height: 100),
                            at: CGPoint(x: 0, y: thirdHeaderY + 30)
                        ),
                        index: 4 + secondBodies.count
                    )
                )

                return (secondHeader, result)
            }

            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)

            let longLengthShortCount = placed(
                cache: cache,
                sectionID: 100,
                implicitIDStart: 10,
                bodyHeights: [50, 200],
                thirdHeaderY: 410
            )
            var longLengthPinned = longLengthShortCount.placed
            longLengthPinned.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 161),
                    contentSize: CGSize(width: 80, height: 540),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                longLengthPinned.first { $0.item === longLengthShortCount.header }?.placement.anchorPosition,
                CGPoint(x: 0, y: -30)
            )

            let shortLengthLongCount = placed(
                cache: cache,
                sectionID: 200,
                implicitIDStart: 30,
                bodyHeights: [34, 33, 33],
                thirdHeaderY: 260
            )
            var shortLengthPinned = shortLengthLongCount.placed
            shortLengthPinned.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 161),
                    contentSize: CGSize(width: 80, height: 390),
                    containerSize: CGSize(width: 80, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                shortLengthPinned.first { $0.item === shortLengthLongCount.header }?.placement.anchorPosition,
                CGPoint(x: 0, y: 161)
            )
        }
    }

    func testLazyLayoutHorizontalPinnedSectionHeaderShortRouteUsesBodyItemCountBoundary() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            func placed(
                cache: LazyLayoutViewCache,
                sectionID: UInt32,
                implicitIDStart: Int,
                bodyWidths: [CGFloat],
                thirdHeaderX: CGFloat
            ) -> (header: LazyLayoutCacheItem, placed: [_LazyLayout_PlacedSubview]) {
                let (_, firstHeader, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart
                )
                let (_, firstBody, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 1
                )
                let (_, secondHeader, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 2
                )
                let secondBodies = bodyWidths.enumerated().map { offset, _ in
                    makeLazyCache(
                        host: host,
                        cache: cache,
                        implicitID: implicitIDStart + 3 + offset
                    ).1
                }
                let (_, thirdHeader, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 3 + bodyWidths.count
                )
                let (_, thirdBody, _) = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitIDStart + 4 + bodyWidths.count
                )

                firstHeader.section = LazyLayoutCacheSection(id: sectionID, isHeader: true)
                firstBody.section = LazyLayoutCacheSection(id: sectionID)
                secondHeader.section = LazyLayoutCacheSection(id: sectionID + 1, isHeader: true)
                for body in secondBodies {
                    body.section = LazyLayoutCacheSection(id: sectionID + 1)
                }
                thirdHeader.section = LazyLayoutCacheSection(id: sectionID + 2, isHeader: true)
                thirdBody.section = LazyLayoutCacheSection(id: sectionID + 2)

                installSize(CGSize(width: 30, height: 80), on: firstHeader)
                installSize(CGSize(width: 100, height: 80), on: firstBody)
                installSize(CGSize(width: 30, height: 80), on: secondHeader)
                for (index, body) in secondBodies.enumerated() {
                    installSize(CGSize(width: bodyWidths[index], height: 80), on: body)
                }
                installSize(CGSize(width: 30, height: 80), on: thirdHeader)
                installSize(CGSize(width: 100, height: 80), on: thirdBody)

                var result: [_LazyLayout_PlacedSubview] = [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 0, y: 0)
                        ),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: firstBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 100, height: 80),
                            at: CGPoint(x: 30, y: 0)
                        ),
                        index: 1
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: 130, y: 0)
                        ),
                        index: 2
                    ),
                ]

                var x: CGFloat = 160
                for (offset, body) in secondBodies.enumerated() {
                    result.append(
                        _LazyLayout_PlacedSubview(
                            item: body,
                            placement: _Placement(
                                proposedSize: CGSize(width: bodyWidths[offset], height: 80),
                                at: CGPoint(x: x, y: 0)
                            ),
                            index: 3 + offset
                        )
                    )
                    x += bodyWidths[offset]
                }
                result.append(
                    _LazyLayout_PlacedSubview(
                        item: thirdHeader,
                        placement: _Placement(
                            proposedSize: CGSize(width: 30, height: 80),
                            at: CGPoint(x: thirdHeaderX, y: 0)
                        ),
                        index: 3 + secondBodies.count
                    )
                )
                result.append(
                    _LazyLayout_PlacedSubview(
                        item: thirdBody,
                        placement: _Placement(
                            proposedSize: CGSize(width: 100, height: 80),
                            at: CGPoint(x: thirdHeaderX + 30, y: 0)
                        ),
                        index: 4 + secondBodies.count
                    )
                )

                return (secondHeader, result)
            }

            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)

            let longLengthShortCount = placed(
                cache: cache,
                sectionID: 100,
                implicitIDStart: 10,
                bodyWidths: [50, 200],
                thirdHeaderX: 410
            )
            var longLengthPinned = longLengthShortCount.placed
            longLengthPinned.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 161, y: 0),
                    contentSize: CGSize(width: 540, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                longLengthPinned.first { $0.item === longLengthShortCount.header }?.placement.anchorPosition,
                CGPoint(x: -30, y: 0)
            )

            let shortLengthLongCount = placed(
                cache: cache,
                sectionID: 200,
                implicitIDStart: 30,
                bodyWidths: [34, 33, 33],
                thirdHeaderX: 260
            )
            var shortLengthPinned = shortLengthLongCount.placed
            shortLengthPinned.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 161, y: 0),
                    contentSize: CGSize(width: 390, height: 80),
                    containerSize: CGSize(width: 120, height: 80)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                shortLengthPinned.first { $0.item === shortLengthLongCount.header }?.placement.anchorPosition,
                CGPoint(x: 161, y: 0)
            )
        }
    }

    func testLazyGridPinnedSectionHeaderShortRouteUsesMajorGroupBoundary() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            func makeItem(
                implicitID: Int,
                section: LazyLayoutCacheSection,
                size: CGSize
            ) -> LazyLayoutCacheItem {
                let (_, item, _) = makeLazyCache(host: host, cache: cache, implicitID: implicitID)
                item.section = section
                installSize(size, on: item)
                return item
            }

            func makeCase(
                horizontal: Bool,
                secondBodyCount: Int,
                implicitIDStart: Int
            ) -> (secondHeader: LazyLayoutCacheItem, placed: [_LazyLayout_PlacedSubview]) {
                let headerSize = horizontal
                    ? CGSize(width: 30, height: 120)
                    : CGSize(width: 120, height: 30)
                let bodySize = horizontal
                    ? CGSize(width: 50, height: 60)
                    : CGSize(width: 60, height: 50)
                let thirdBodySize = horizontal
                    ? CGSize(width: 100, height: 120)
                    : CGSize(width: 120, height: 100)

                func point(major: CGFloat, minor: CGFloat) -> CGPoint {
                    horizontal ? CGPoint(x: major, y: minor) : CGPoint(x: minor, y: major)
                }

                let firstHeader = makeItem(
                    implicitID: implicitIDStart,
                    section: LazyLayoutCacheSection(id: UInt32(implicitIDStart), isHeader: true),
                    size: headerSize
                )
                let secondSectionID = UInt32(implicitIDStart + 10)
                let secondHeader = makeItem(
                    implicitID: implicitIDStart + 1,
                    section: LazyLayoutCacheSection(id: secondSectionID, isHeader: true),
                    size: headerSize
                )
                let secondBodies = (0..<secondBodyCount).map { offset in
                    makeItem(
                        implicitID: implicitIDStart + 2 + offset,
                        section: LazyLayoutCacheSection(id: secondSectionID),
                        size: bodySize
                    )
                }
                let thirdHeaderImplicitID = implicitIDStart + 2 + secondBodies.count
                let thirdHeader = makeItem(
                    implicitID: thirdHeaderImplicitID,
                    section: LazyLayoutCacheSection(id: UInt32(thirdHeaderImplicitID), isHeader: true),
                    size: headerSize
                )
                let thirdBody = makeItem(
                    implicitID: thirdHeaderImplicitID + 1,
                    section: LazyLayoutCacheSection(id: UInt32(thirdHeaderImplicitID)),
                    size: thirdBodySize
                )

                var placed = [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(proposedSize: headerSize, at: point(major: 0, minor: 0)),
                        index: 0
                    ),
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(proposedSize: headerSize, at: point(major: 130, minor: 0)),
                        index: 1
                    ),
                ]

                for (offset, body) in secondBodies.enumerated() {
                    let major = CGFloat(160 + (offset / 2) * 50)
                    let minor = CGFloat((offset % 2) * 60)
                    placed.append(
                        _LazyLayout_PlacedSubview(
                            item: body,
                            placement: _Placement(proposedSize: bodySize, at: point(major: major, minor: minor)),
                            index: 2 + offset
                        )
                    )
                }
                let thirdHeaderMajor = CGFloat(160 + ((secondBodies.count + 1) / 2) * 50)
                placed.append(
                    _LazyLayout_PlacedSubview(
                        item: thirdHeader,
                        placement: _Placement(proposedSize: headerSize, at: point(major: thirdHeaderMajor, minor: 0)),
                        index: 2 + secondBodies.count
                    )
                )
                placed.append(
                    _LazyLayout_PlacedSubview(
                        item: thirdBody,
                        placement: _Placement(proposedSize: thirdBodySize, at: point(major: thirdHeaderMajor + 30, minor: 0)),
                        index: 3 + secondBodies.count
                    )
                )

                return (secondHeader, placed)
            }

            let verticalShortCase = makeCase(horizontal: false, secondBodyCount: 4, implicitIDStart: 100)
            var verticalShort = verticalShortCase.placed
            verticalShort.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 161),
                    contentSize: CGSize(width: 120, height: 390),
                    containerSize: CGSize(width: 120, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                verticalShort.first { $0.item === verticalShortCase.secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: -30)
            )

            let verticalLongCase = makeCase(horizontal: false, secondBodyCount: 6, implicitIDStart: 200)
            var verticalLong = verticalLongCase.placed
            verticalLong.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 161),
                    contentSize: CGSize(width: 120, height: 440),
                    containerSize: CGSize(width: 120, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .vertical,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                verticalLong.first { $0.item === verticalLongCase.secondHeader }?.placement.anchorPosition,
                CGPoint(x: 0, y: 161)
            )

            let horizontalShortCase = makeCase(horizontal: true, secondBodyCount: 4, implicitIDStart: 300)
            var horizontalShort = horizontalShortCase.placed
            horizontalShort.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 161, y: 0),
                    contentSize: CGSize(width: 390, height: 120),
                    containerSize: CGSize(width: 120, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                horizontalShort.first { $0.item === horizontalShortCase.secondHeader }?.placement.anchorPosition,
                CGPoint(x: -30, y: 0)
            )

            let horizontalLongCase = makeCase(horizontal: true, secondBodyCount: 6, implicitIDStart: 400)
            var horizontalLong = horizontalLongCase.placed
            horizontalLong.pinSectionHeadersAndFooters(
                geometry: ScrollGeometry(
                    contentOffset: CGPoint(x: 161, y: 0),
                    contentSize: CGSize(width: 440, height: 120),
                    containerSize: CGSize(width: 120, height: 120)
                ),
                layoutDirection: .leftToRight,
                axes: .horizontal,
                pinnedViews: .sectionHeaders
            )
            XCTAssertEqual(
                horizontalLong.first { $0.item === horizontalLongCase.secondHeader }?.placement.anchorPosition,
                CGPoint(x: 161, y: 0)
            )
        }
    }

    func testLazyGridPinnedSectionFootersUseTrailingAndOffscreenPositions() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            func makeItem(
                implicitID: Int,
                section: LazyLayoutCacheSection,
                size: CGSize
            ) -> LazyLayoutCacheItem {
                let (_, item, _) = makeLazyCache(host: host, cache: cache, implicitID: implicitID)
                item.section = section
                installSize(size, on: item)
                return item
            }

            func makeCase(
                horizontal: Bool,
                implicitIDStart: Int
            ) -> (
                firstFooter: LazyLayoutCacheItem,
                secondHeader: LazyLayoutCacheItem,
                placed: [_LazyLayout_PlacedSubview]
            ) {
                let headerSize = horizontal
                    ? CGSize(width: 30, height: 120)
                    : CGSize(width: 120, height: 30)
                let bodySize = horizontal
                    ? CGSize(width: 50, height: 60)
                    : CGSize(width: 60, height: 50)
                let footerSize = horizontal
                    ? CGSize(width: 24, height: 120)
                    : CGSize(width: 120, height: 24)

                func point(major: CGFloat, minor: CGFloat) -> CGPoint {
                    horizontal ? CGPoint(x: major, y: minor) : CGPoint(x: minor, y: major)
                }

                let firstSection = UInt32(implicitIDStart)
                let secondSection = UInt32(implicitIDStart + 20)
                let firstHeader = makeItem(
                    implicitID: implicitIDStart,
                    section: LazyLayoutCacheSection(id: firstSection, isHeader: true),
                    size: headerSize
                )
                let bodies = (0..<4).map { offset in
                    makeItem(
                        implicitID: implicitIDStart + 1 + offset,
                        section: LazyLayoutCacheSection(id: firstSection),
                        size: bodySize
                    )
                }
                let firstFooter = makeItem(
                    implicitID: implicitIDStart + 5,
                    section: LazyLayoutCacheSection(id: firstSection, isFooter: true),
                    size: footerSize
                )
                let secondHeader = makeItem(
                    implicitID: implicitIDStart + 6,
                    section: LazyLayoutCacheSection(id: secondSection, isHeader: true),
                    size: headerSize
                )

                var placed = [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(proposedSize: headerSize, at: point(major: 0, minor: 0)),
                        index: 0
                    ),
                ]

                for (offset, body) in bodies.enumerated() {
                    placed.append(
                        _LazyLayout_PlacedSubview(
                            item: body,
                            placement: _Placement(
                                proposedSize: bodySize,
                                at: point(
                                    major: CGFloat(30 + (offset / 2) * 50),
                                    minor: CGFloat((offset % 2) * 60)
                                )
                            ),
                            index: 1 + offset
                        )
                    )
                }

                placed.append(
                    _LazyLayout_PlacedSubview(
                        item: firstFooter,
                        placement: _Placement(proposedSize: footerSize, at: point(major: 130, minor: 0)),
                        index: 5
                    )
                )
                placed.append(
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(proposedSize: headerSize, at: point(major: 154, minor: 0)),
                        index: 6
                    )
                )

                return (firstFooter, secondHeader, placed)
            }

            func assertCase(horizontal: Bool, implicitIDStart: Int) throws {
                let sample = makeCase(horizontal: horizontal, implicitIDStart: implicitIDStart)
                let contentSize = horizontal
                    ? CGSize(width: 304, height: 120)
                    : CGSize(width: 120, height: 304)
                let containerSize = CGSize(width: 120, height: 120)
                let axis: Axis.Set = horizontal ? .horizontal : .vertical
                let pinnedOffset = CGPoint.zero
                let naturalOffset = horizontal ? CGPoint(x: 40, y: 0) : CGPoint(x: 0, y: 40)
                let sectionEndOffset = horizontal ? CGPoint(x: 154, y: 0) : CGPoint(x: 0, y: 154)
                let pinnedPosition = horizontal ? CGPoint(x: 96, y: 0) : CGPoint(x: 0, y: 96)
                let footerNaturalPosition = horizontal ? CGPoint(x: 130, y: 0) : CGPoint(x: 0, y: 130)
                let secondHeaderPosition = horizontal ? CGPoint(x: 154, y: 0) : CGPoint(x: 0, y: 154)

                var pinned = sample.placed
                pinned.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: pinnedOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: .sectionFooters
                )
                XCTAssertEqual(
                    try XCTUnwrap(pinned.first { $0.item === sample.firstFooter }).placement.anchorPosition,
                    pinnedPosition
                )

                var natural = sample.placed
                natural.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: naturalOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: .sectionFooters
                )
                XCTAssertEqual(
                    try XCTUnwrap(natural.first { $0.item === sample.firstFooter }).placement.anchorPosition,
                    footerNaturalPosition
                )

                var offscreen = sample.placed
                offscreen.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: sectionEndOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: .sectionFooters
                )
                XCTAssertEqual(
                    try XCTUnwrap(offscreen.first { $0.item === sample.firstFooter }).placement.anchorPosition,
                    footerNaturalPosition
                )
                XCTAssertEqual(
                    try XCTUnwrap(offscreen.first { $0.item === sample.secondHeader }).placement.anchorPosition,
                    secondHeaderPosition
                )
            }

            try assertCase(horizontal: false, implicitIDStart: 500)
            try assertCase(horizontal: true, implicitIDStart: 600)
        }
    }

    func testLazyGridPinnedSectionHeadersRemainAtFooterBoundaryWhenFootersAlsoPinned() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            func makeItem(
                implicitID: Int,
                section: LazyLayoutCacheSection,
                size: CGSize
            ) -> LazyLayoutCacheItem {
                let (_, item, _) = makeLazyCache(host: host, cache: cache, implicitID: implicitID)
                item.section = section
                installSize(size, on: item)
                return item
            }

            func makeCase(
                horizontal: Bool,
                implicitIDStart: Int
            ) -> (
                firstHeader: LazyLayoutCacheItem,
                firstFooter: LazyLayoutCacheItem,
                secondHeader: LazyLayoutCacheItem,
                placed: [_LazyLayout_PlacedSubview]
            ) {
                let headerSize = horizontal
                    ? CGSize(width: 30, height: 120)
                    : CGSize(width: 120, height: 30)
                let bodySize = horizontal
                    ? CGSize(width: 50, height: 60)
                    : CGSize(width: 60, height: 50)
                let footerSize = horizontal
                    ? CGSize(width: 24, height: 120)
                    : CGSize(width: 120, height: 24)

                func point(major: CGFloat, minor: CGFloat) -> CGPoint {
                    horizontal ? CGPoint(x: major, y: minor) : CGPoint(x: minor, y: major)
                }

                let firstSection = UInt32(implicitIDStart)
                let secondSection = UInt32(implicitIDStart + 20)
                let firstHeader = makeItem(
                    implicitID: implicitIDStart,
                    section: LazyLayoutCacheSection(id: firstSection, isHeader: true),
                    size: headerSize
                )
                let bodies = (0..<4).map { offset in
                    makeItem(
                        implicitID: implicitIDStart + 1 + offset,
                        section: LazyLayoutCacheSection(id: firstSection),
                        size: bodySize
                    )
                }
                let firstFooter = makeItem(
                    implicitID: implicitIDStart + 5,
                    section: LazyLayoutCacheSection(id: firstSection, isFooter: true),
                    size: footerSize
                )
                let secondHeader = makeItem(
                    implicitID: implicitIDStart + 6,
                    section: LazyLayoutCacheSection(id: secondSection, isHeader: true),
                    size: headerSize
                )

                var placed = [
                    _LazyLayout_PlacedSubview(
                        item: firstHeader,
                        placement: _Placement(proposedSize: headerSize, at: point(major: 0, minor: 0)),
                        index: 0
                    ),
                ]

                for (offset, body) in bodies.enumerated() {
                    placed.append(
                        _LazyLayout_PlacedSubview(
                            item: body,
                            placement: _Placement(
                                proposedSize: bodySize,
                                at: point(
                                    major: CGFloat(30 + (offset / 2) * 50),
                                    minor: CGFloat((offset % 2) * 60)
                                )
                            ),
                            index: 1 + offset
                        )
                    )
                }

                placed.append(
                    _LazyLayout_PlacedSubview(
                        item: firstFooter,
                        placement: _Placement(proposedSize: footerSize, at: point(major: 130, minor: 0)),
                        index: 5
                    )
                )
                placed.append(
                    _LazyLayout_PlacedSubview(
                        item: secondHeader,
                        placement: _Placement(proposedSize: headerSize, at: point(major: 154, minor: 0)),
                        index: 6
                    )
                )

                return (firstHeader, firstFooter, secondHeader, placed)
            }

            func assertCase(horizontal: Bool, implicitIDStart: Int) throws {
                let sample = makeCase(horizontal: horizontal, implicitIDStart: implicitIDStart)
                let contentSize = horizontal
                    ? CGSize(width: 304, height: 120)
                    : CGSize(width: 120, height: 304)
                let containerSize = CGSize(width: 120, height: 120)
                let axis: Axis.Set = horizontal ? .horizontal : .vertical
                let boundaryOffset = horizontal ? CGPoint(x: 154, y: 0) : CGPoint(x: 0, y: 154)
                let afterOffset = horizontal ? CGPoint(x: 160, y: 0) : CGPoint(x: 0, y: 160)
                let headerBoundaryPosition = horizontal ? CGPoint(x: 154, y: 0) : CGPoint(x: 0, y: 154)
                let footerPosition = horizontal ? CGPoint(x: 130, y: 0) : CGPoint(x: 0, y: 130)

                var boundary = sample.placed
                boundary.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: boundaryOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: [.sectionHeaders, .sectionFooters]
                )

                XCTAssertEqual(
                    try XCTUnwrap(boundary.first { $0.item === sample.firstHeader }).placement.anchorPosition,
                    headerBoundaryPosition
                )
                XCTAssertEqual(
                    try XCTUnwrap(boundary.first { $0.item === sample.firstFooter }).placement.anchorPosition,
                    footerPosition
                )
                XCTAssertEqual(
                    try XCTUnwrap(boundary.first { $0.item === sample.secondHeader }).placement.anchorPosition,
                    headerBoundaryPosition
                )

                var afterBoundary = sample.placed
                afterBoundary.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: afterOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: [.sectionHeaders, .sectionFooters]
                )

                XCTAssertNil(afterBoundary.first { $0.item === sample.firstHeader })
                XCTAssertEqual(
                    try XCTUnwrap(afterBoundary.first { $0.item === sample.secondHeader }).placement.anchorPosition,
                    headerBoundaryPosition
                )
            }

            try assertCase(horizontal: false, implicitIDStart: 500)
            try assertCase(horizontal: true, implicitIDStart: 600)
        }
    }

    func testLazyGridPinnedMiddleSectionHeaderUsesSentinelWhenFootersAlsoPinned() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)

            func installSize(_ size: CGSize, on item: LazyLayoutCacheItem) {
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(graph.makeInput(value: testLayoutComputer(
                        sizeThatFits: { _ in size }
                    )))
                )
            }

            func makeItem(
                implicitID: Int,
                section: LazyLayoutCacheSection,
                size: CGSize
            ) -> LazyLayoutCacheItem {
                let (_, item, _) = makeLazyCache(host: host, cache: cache, implicitID: implicitID)
                item.section = section
                installSize(size, on: item)
                return item
            }

            func makeCase(
                horizontal: Bool,
                implicitIDStart: Int
            ) -> (
                middleHeader: LazyLayoutCacheItem,
                middleFooter: LazyLayoutCacheItem,
                thirdHeader: LazyLayoutCacheItem,
                placed: [_LazyLayout_PlacedSubview]
            ) {
                let headerSize = horizontal
                    ? CGSize(width: 30, height: 120)
                    : CGSize(width: 120, height: 30)
                let bodySize = horizontal
                    ? CGSize(width: 50, height: 60)
                    : CGSize(width: 60, height: 50)
                let footerSize = horizontal
                    ? CGSize(width: 24, height: 120)
                    : CGSize(width: 120, height: 24)

                func point(major: CGFloat, minor: CGFloat) -> CGPoint {
                    horizontal ? CGPoint(x: major, y: minor) : CGPoint(x: minor, y: major)
                }

                let sectionIDs = (0..<3).map { UInt32(implicitIDStart + $0 * 20) }
                var placed: [_LazyLayout_PlacedSubview] = []
                var middleHeader: LazyLayoutCacheItem?
                var middleFooter: LazyLayoutCacheItem?
                var thirdHeader: LazyLayoutCacheItem?
                var nextImplicitID = implicitIDStart
                var nextIndex = 0

                for sectionOffset in 0..<3 {
                    let sectionBase = CGFloat(sectionOffset) * 154
                    let sectionID = sectionIDs[sectionOffset]
                    let header = makeItem(
                        implicitID: nextImplicitID,
                        section: LazyLayoutCacheSection(id: sectionID, isHeader: true),
                        size: headerSize
                    )
                    nextImplicitID += 1
                    placed.append(
                        _LazyLayout_PlacedSubview(
                            item: header,
                            placement: _Placement(
                                proposedSize: headerSize,
                                at: point(major: sectionBase, minor: 0)
                            ),
                            index: nextIndex
                        )
                    )
                    nextIndex += 1
                    if sectionOffset == 1 {
                        middleHeader = header
                    } else if sectionOffset == 2 {
                        thirdHeader = header
                    }

                    for bodyOffset in 0..<4 {
                        let body = makeItem(
                            implicitID: nextImplicitID,
                            section: LazyLayoutCacheSection(id: sectionID),
                            size: bodySize
                        )
                        nextImplicitID += 1
                        placed.append(
                            _LazyLayout_PlacedSubview(
                                item: body,
                                placement: _Placement(
                                    proposedSize: bodySize,
                                    at: point(
                                        major: sectionBase + 30 + CGFloat((bodyOffset / 2) * 50),
                                        minor: CGFloat((bodyOffset % 2) * 60)
                                    )
                                ),
                                index: nextIndex
                            )
                        )
                        nextIndex += 1
                    }

                    let footer = makeItem(
                        implicitID: nextImplicitID,
                        section: LazyLayoutCacheSection(id: sectionID, isFooter: true),
                        size: footerSize
                    )
                    nextImplicitID += 1
                    placed.append(
                        _LazyLayout_PlacedSubview(
                            item: footer,
                            placement: _Placement(
                                proposedSize: footerSize,
                                at: point(major: sectionBase + 130, minor: 0)
                            ),
                            index: nextIndex
                        )
                    )
                    nextIndex += 1
                    if sectionOffset == 1 {
                        middleFooter = footer
                    }
                }

                return (
                    try! XCTUnwrap(middleHeader),
                    try! XCTUnwrap(middleFooter),
                    try! XCTUnwrap(thirdHeader),
                    placed
                )
            }

            func assertCase(horizontal: Bool, implicitIDStart: Int) throws {
                let sample = makeCase(horizontal: horizontal, implicitIDStart: implicitIDStart)
                let contentSize = horizontal
                    ? CGSize(width: 462, height: 120)
                    : CGSize(width: 120, height: 462)
                let containerSize = CGSize(width: 120, height: 120)
                let axis: Axis.Set = horizontal ? .horizontal : .vertical
                let middleFooterOffset = horizontal ? CGPoint(x: 284, y: 0) : CGPoint(x: 0, y: 284)
                let middleBoundaryOffset = horizontal ? CGPoint(x: 308, y: 0) : CGPoint(x: 0, y: 308)
                let afterBoundaryOffset = horizontal ? CGPoint(x: 314, y: 0) : CGPoint(x: 0, y: 314)
                let middleSentinel = horizontal ? CGPoint(x: -30, y: 0) : CGPoint(x: 0, y: -30)
                let middleFooterPosition = horizontal ? CGPoint(x: 284, y: 0) : CGPoint(x: 0, y: 284)
                let thirdHeaderPosition = horizontal ? CGPoint(x: 308, y: 0) : CGPoint(x: 0, y: 308)

                var middleFooterNatural = sample.placed
                middleFooterNatural.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: middleFooterOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: [.sectionHeaders, .sectionFooters]
                )
                XCTAssertEqual(
                    try XCTUnwrap(middleFooterNatural.first { $0.item === sample.middleHeader }).placement.anchorPosition,
                    middleSentinel
                )
                XCTAssertEqual(
                    try XCTUnwrap(middleFooterNatural.first { $0.item === sample.middleFooter }).placement.anchorPosition,
                    middleFooterPosition
                )
                XCTAssertEqual(
                    try XCTUnwrap(middleFooterNatural.first { $0.item === sample.thirdHeader }).placement.anchorPosition,
                    thirdHeaderPosition
                )

                var middleBoundary = sample.placed
                middleBoundary.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: middleBoundaryOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: [.sectionHeaders, .sectionFooters]
                )
                XCTAssertEqual(
                    try XCTUnwrap(middleBoundary.first { $0.item === sample.middleHeader }).placement.anchorPosition,
                    middleSentinel
                )
                XCTAssertEqual(
                    try XCTUnwrap(middleBoundary.first { $0.item === sample.middleFooter }).placement.anchorPosition,
                    middleFooterPosition
                )
                XCTAssertEqual(
                    try XCTUnwrap(middleBoundary.first { $0.item === sample.thirdHeader }).placement.anchorPosition,
                    thirdHeaderPosition
                )

                var afterBoundary = sample.placed
                afterBoundary.pinSectionHeadersAndFooters(
                    geometry: ScrollGeometry(
                        contentOffset: afterBoundaryOffset,
                        contentSize: contentSize,
                        containerSize: containerSize
                    ),
                    layoutDirection: .leftToRight,
                    axes: axis,
                    pinnedViews: [.sectionHeaders, .sectionFooters]
                )
                XCTAssertNil(afterBoundary.first { $0.item === sample.middleHeader })
                XCTAssertEqual(
                    try XCTUnwrap(afterBoundary.first { $0.item === sample.thirdHeader }).placement.anchorPosition,
                    thirdHeaderPosition
                )
            }

            try assertCase(horizontal: false, implicitIDStart: 700)
            try assertCase(horizontal: true, implicitIDStart: 800)
        }
    }

    func testLazyLayoutViewCacheResetPrefetchPhasesNoOpsWithoutCapability() {
        let host = GraphHost()

        host.data.withCurrent {
            let (_, item, _) = makeLazyCache(host: host)
            item.prefetchSeed = 13
            item.prefetchPhase = .prefetching

            item.cache?.resetPrefetchPhases()

            XCTAssertEqual(item.prefetchSeed, 13)
            XCTAssertEqual(item.prefetchPhase, .prefetching)
        }
    }

    func testLazyLayoutViewCacheResetPrefetchPhasesClearsChildMaxDisplayListSubviews() {

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            let (unrelatedChildCache, _, _) = makeLazyCache(host: host, implicitID: 11)
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            item.prefetchSeed = 13
            item.prefetchPhase = .prefetching
            childCache.maxDisplayListSubviews = 2
            unrelatedChildCache.maxDisplayListSubviews = 3

            cache.resetPrefetchPhases()

            XCTAssertEqual(item.prefetchSeed, 0)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
            XCTAssertNil(childCache.maxDisplayListSubviews)
            XCTAssertEqual(unrelatedChildCache.maxDisplayListSubviews, 3)
        }
    }

    func testLazyLayoutViewCacheUpdatePrefetchPhasesNoOpsWithoutCapability() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host)
            cache.commitSeed = 23
            item.prefetchSeed = 7
            item.prefetchPhase = .pendingDisplay
            item.displayIndex = nil
            item.placement = nil

            cache.updatePrefetchPhases()

            XCTAssertEqual(item.prefetchSeed, 7)
            XCTAssertEqual(item.prefetchPhase, .pendingDisplay)
            XCTAssertNil(item.placement)
        }
    }

    func testLazyLayoutViewCacheUpdatePrefetchPhasesClearsDisplayedActivePrefetchState() {

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, displayed, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[displayed.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            displayed.displayIndex = 0
            displayed.prefetchPhase = .pendingDisplay
            cache.maxDisplayListSubviews = 4
            childCache.maxDisplayListSubviews = 2

            let (_, hiddenPendingDisplay, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            hiddenPendingDisplay.displayIndex = nil
            hiddenPendingDisplay.prefetchSeed = 7
            hiddenPendingDisplay.prefetchPhase = .pendingDisplay
            hiddenPendingDisplay.placement = nil

            cache.updatePrefetchPhases()

            XCTAssertEqual(displayed.prefetchPhase, .notPrefetching)
            XCTAssertNil(cache.maxDisplayListSubviews)
            XCTAssertNil(childCache.maxDisplayListSubviews)
            XCTAssertEqual(hiddenPendingDisplay.prefetchSeed, 7)
            XCTAssertEqual(hiddenPendingDisplay.prefetchPhase, .pendingDisplay)
            XCTAssertNil(hiddenPendingDisplay.placement)
        }
    }

    func testLazyLayoutViewCacheUpdatePrefetchPhasesResetsDisplayedInactiveChildLimit() {

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, displayed, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            let (unrelatedChildCache, _, _) = makeLazyCache(host: host, implicitID: 11)
            cache.childCaches[displayed.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            displayed.displayIndex = 0
            displayed.prefetchPhase = .notPrefetching
            cache.maxDisplayListSubviews = 4
            childCache.maxDisplayListSubviews = 2
            unrelatedChildCache.maxDisplayListSubviews = 3

            cache.updatePrefetchPhases()

            XCTAssertEqual(displayed.prefetchPhase, .notPrefetching)
            XCTAssertEqual(cache.maxDisplayListSubviews, 4)
            XCTAssertNil(childCache.maxDisplayListSubviews)
            XCTAssertEqual(unrelatedChildCache.maxDisplayListSubviews, 3)
        }
    }

    func testLazyLayoutViewCacheUpdatePrefetchPhasesClearsAgedPendingRemovalState() {

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, agedRemoval, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (_, retainedRemoval, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            let (_, pendingDisplay, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 3
            )
            cache.lru.transactionSeed = 10
            cache.lru.maxIdle = 2

            agedRemoval.displayIndex = nil
            agedRemoval.prefetchPhase = .pendingRemoval
            agedRemoval.removalTransactionSeed = 7

            retainedRemoval.displayIndex = nil
            retainedRemoval.prefetchPhase = .pendingRemoval
            retainedRemoval.removalTransactionSeed = 8

            pendingDisplay.displayIndex = nil
            pendingDisplay.prefetchPhase = .pendingDisplay
            pendingDisplay.removalTransactionSeed = 1

            cache.updatePrefetchPhases()

            XCTAssertEqual(agedRemoval.prefetchPhase, .notPrefetching)
            XCTAssertEqual(retainedRemoval.prefetchPhase, .pendingRemoval)
            XCTAssertEqual(pendingDisplay.prefetchPhase, .pendingDisplay)
        }
    }

    func testLazyLayoutViewCacheAdvancePrefetchDisplayMapsChildSchedulingResult() {

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            cache.commitSeed = 33
            item.prefetchSeed = 33
            item.prefetchPhase = .prefetching
            childCache.placedIndices = (min: 0, max: 2)

            var advance = cache.advancePrefetchPhaseForDisplayWithNotifyFlag(item: item)
            XCTAssertEqual(advance.result, .some)
            XCTAssertTrue(advance.didNotify)
            XCTAssertEqual(item.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(childCache.maxDisplayListSubviews, 0)

            advance = cache.advancePrefetchPhaseForDisplayWithNotifyFlag(item: item)
            XCTAssertEqual(advance.result, .some)
            XCTAssertTrue(advance.didNotify)
            XCTAssertEqual(childCache.maxDisplayListSubviews, 1)

            childCache.maxDisplayListSubviews = 3
            advance = cache.advancePrefetchPhaseForDisplayWithNotifyFlag(item: item)
            XCTAssertEqual(advance.result, .none)
            XCTAssertFalse(advance.didNotify)
            XCTAssertEqual(item.prefetchPhase, .pendingDisplay)

            let (_, noChildItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            noChildItem.prefetchSeed = 33
            noChildItem.prefetchPhase = .prefetching
            advance = cache.advancePrefetchPhaseForDisplayWithNotifyFlag(item: noChildItem)
            XCTAssertEqual(advance.result, .all)
            XCTAssertTrue(advance.didNotify)
            XCTAssertEqual(noChildItem.prefetchPhase, .pendingDisplay)

            let (disabledCache, disabledItem, _) = makeLazyCache(
                host: host,
                implicitID: 3
            )
            disabledItem.prefetchPhase = .prefetching
            let disabledAdvance = disabledCache.advancePrefetchPhaseForDisplayWithNotifyFlag(item: disabledItem)
            XCTAssertEqual(disabledAdvance.result, .none)
            XCTAssertFalse(disabledAdvance.didNotify)
            XCTAssertEqual(disabledItem.prefetchPhase, .prefetching)
        }
    }

    func testLazyLayoutViewCacheAdvancePrefetchRemovalClearsPendingRemovalAndReturnsAll() {

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, first, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (_, second, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            let (_, retained, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 3
            )
            first.prefetchPhase = .pendingRemoval
            second.prefetchPhase = .pendingRemoval
            retained.prefetchPhase = .prefetching

            var advance = cache.advancePrefetchPhaseForRemovalWithNotifyFlag()
            XCTAssertEqual(advance.result, .all)
            XCTAssertTrue(advance.didNotify)
            XCTAssertEqual(first.prefetchPhase, .notPrefetching)
            XCTAssertEqual(second.prefetchPhase, .notPrefetching)
            XCTAssertEqual(retained.prefetchPhase, .prefetching)

            advance = cache.advancePrefetchPhaseForRemovalWithNotifyFlag()
            XCTAssertEqual(advance.result, .all)
            XCTAssertFalse(advance.didNotify)

            let (disabledCache, disabledItem, _) = makeLazyCache(
                host: host,
                implicitID: 4
            )
            disabledItem.prefetchPhase = .pendingRemoval
            let disabledAdvance = disabledCache.advancePrefetchPhaseForRemovalWithNotifyFlag()
            XCTAssertEqual(disabledAdvance.result, .none)
            XCTAssertFalse(disabledAdvance.didNotify)
            XCTAssertEqual(disabledItem.prefetchPhase, .pendingRemoval)
        }
    }

    func testLazySubviewPrefetcherResetsOnStateChangeAndHonorsAllowedEdges() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 19
            item.prefetchSeed = 19
            item.prefetchPhase = .prefetching

            var horizontalState = ScrollPrefetchState(deadline: 1)
            horizontalState.edges = .horizontal
            let stateAttribute = graph.makeInput(value: horizontalState)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache
            )

            XCTAssertEqual(prefetcher.updateHostState(), .none)
            XCTAssertEqual(item.prefetchPhase, .prefetching)
            XCTAssertFalse(prefetcher.didScheduleContinuation)

            var verticalState = ScrollPrefetchState(deadline: 2)
            verticalState.edges = .vertical
            stateAttribute.setValue(verticalState)

            XCTAssertEqual(prefetcher.updateHostState(), .all)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
            XCTAssertEqual(item.prefetchSeed, 0)
            XCTAssertTrue(prefetcher.didScheduleContinuation)
            XCTAssertEqual(prefetcher.operations.count, 1)
            guard case .layout = prefetcher.operations.last else {
                XCTFail("expected reset-seeded layout operation after unnotified removal helper")
                return
            }
        }
    }

    func testLazySubviewPrefetcherResetSeedsRemovalBeforeLayoutResult() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 10, height: 11),
                CGSize(width: 20, height: 21),
            ]
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                supportsPrefetching: true,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 41

            let (_, removalItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 50
            )
            removalItem.prefetchPhase = .pendingRemoval

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache,
                size: ViewSize(CGSize(width: 72, height: 120))
            )

            XCTAssertEqual(prefetcher.nextLayoutOffset, 0)
            XCTAssertEqual(prefetcher.updateHostState(), .all)
            XCTAssertEqual(removalItem.prefetchPhase, .notPrefetching)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(prefetcher.nextLayoutOffset, 1)
            XCTAssertEqual(prefetcher.operations.count, 2)
            guard case .outputs = prefetcher.operations.last else {
                XCTFail("expected output-harvest operation after reset-seeded layout")
                return
            }
            guard case let .layoutDisplay(item, proposal) = prefetcher.operations.first else {
                XCTFail("expected reset-seeded layout display operation after removal")
                return
            }
            XCTAssertEqual(item.id.canonicalID, _ViewList_ID(implicitID: 0).elementID(at: 0).canonicalID)
            XCTAssertEqual(proposal, _ProposedSize(width: 72, height: nil))
        }
    }

    func testLazySubviewPrefetcherRetriesOutputHarvestBeforeLayoutDisplay() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, outputItem, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (_, layoutDisplayItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 64
            outputItem.prefetchSeed = 64

            let displayNode = graph.makeInput(value: DisplayList())
            var preferences = PreferencesOutputs()
            preferences.append(DisplayList.Key.self, node: displayNode.identifier)
            outputItem.outputs = _ViewOutputs(preferences: preferences)

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache
            )
            prefetcher.lastCacheCommitSeed = cache.commitSeed
            prefetcher.operations = [
                .layoutDisplay(layoutDisplayItem, _ProposedSize(width: 72, height: nil)),
                .outputs,
            ]

            XCTAssertEqual(prefetcher.updateHostState(), .some)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(layoutDisplayItem.prefetchPhase, .notPrefetching)
            XCTAssertEqual(prefetcher.operations.count, 2)
            guard case .outputs = prefetcher.operations.last else {
                XCTFail("expected output-harvest operation to be retried before layout-display work")
                return
            }
            guard case let .layoutDisplay(remainingItem, _) = prefetcher.operations.first else {
                XCTFail("expected layout-display operation to remain until output harvest finishes")
                return
            }
            XCTAssertTrue(remainingItem === layoutDisplayItem)

            outputItem.prefetchSeed = 0

            XCTAssertEqual(prefetcher.updateHostState(), .none)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(layoutDisplayItem.prefetchPhase, .notPrefetching)
            XCTAssertEqual(prefetcher.operations.count, 1)
            guard case let .layoutDisplay(deferredItem, _) = prefetcher.operations.last else {
                XCTFail("expected layout-display operation to remain after empty output harvest")
                return
            }
            XCTAssertTrue(deferredItem === layoutDisplayItem)

            XCTAssertEqual(prefetcher.updateHostState(), .all)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(layoutDisplayItem.prefetchSeed, 64)
            XCTAssertEqual(layoutDisplayItem.prefetchPhase, .pendingDisplay)
        }
    }

    func testLazySubviewPrefetcherSchedulesDisplayAfterEmptyOutputHarvest() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, layoutDisplayItem, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 64

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache
            )
            prefetcher.lastCacheCommitSeed = cache.commitSeed
            prefetcher.operations = [
                .layoutDisplay(layoutDisplayItem, _ProposedSize(width: 72, height: nil)),
                .outputs,
            ]

            XCTAssertEqual(prefetcher.updateHostState(), .none)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(layoutDisplayItem.prefetchPhase, .notPrefetching)
            XCTAssertEqual(prefetcher.operations.count, 1)
            guard case let .layoutDisplay(remainingItem, _) = prefetcher.operations.last else {
                XCTFail("expected display operation to wait until the next continuation")
                return
            }
            XCTAssertTrue(remainingItem === layoutDisplayItem)

            XCTAssertEqual(prefetcher.updateHostState(), .all)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(layoutDisplayItem.prefetchSeed, 64)
            XCTAssertEqual(layoutDisplayItem.prefetchPhase, .pendingDisplay)
        }
    }

    func testLazySubviewPrefetcherConsumesDisplayAndRemovalOperationsFromStack() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, displayItem, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (_, removalItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            let (childCache, _, _) = makeLazyCache(
                host: host,
                implicitID: 10
            )
            cache.childCaches[displayItem.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 33
            displayItem.prefetchSeed = 33
            displayItem.prefetchPhase = .prefetching
            removalItem.prefetchPhase = .pendingRemoval
            childCache.placedIndices = (min: 0, max: 2)

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache
            )
            prefetcher.lastCacheCommitSeed = cache.commitSeed
            prefetcher.operations = [.removal, .display(displayItem)]

            XCTAssertEqual(prefetcher.updateHostState(), .some)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(displayItem.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(childCache.maxDisplayListSubviews, 0)
            XCTAssertEqual(removalItem.prefetchPhase, .pendingRemoval)
            XCTAssertEqual(prefetcher.operations.count, 2)
            guard case let .display(retriedDisplayItem) = prefetcher.operations.last else {
                XCTFail("expected display operation to be retried after partial child prefetch")
                return
            }
            XCTAssertTrue(retriedDisplayItem === displayItem)

            prefetcher.operations = [.removal]

            XCTAssertEqual(prefetcher.updateHostState(), .all)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(removalItem.prefetchPhase, .notPrefetching)
        }
    }

    func testLazySubviewPrefetcherUpdateValueStopsAfterNotifiedDisplayPhase() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, displayItem, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (_, removalItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            let (childCache, _, _) = makeLazyCache(
                host: host,
                implicitID: 10
            )
            cache.childCaches[displayItem.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 33
            displayItem.prefetchSeed = 33
            displayItem.prefetchPhase = .prefetching
            removalItem.prefetchPhase = .pendingRemoval
            childCache.placedIndices = (min: 0, max: 2)

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache
            )
            prefetcher.lastCacheCommitSeed = cache.commitSeed
            prefetcher.operations = [.removal, .display(displayItem)]

            let prefetcherAttribute = graph.makeStatefulRule(prefetcher)
            _ = prefetcherAttribute.value

            XCTAssertEqual(displayItem.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(childCache.maxDisplayListSubviews, 0)
            XCTAssertEqual(removalItem.prefetchPhase, .pendingRemoval)
        }
    }

    func testLazySubviewPrefetcherUpdateValueRepeatsAfterUnnotifiedDisplayPhase() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, displayItem, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (_, removalItem, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 2
            )
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 33
            displayItem.prefetchSeed = 33
            displayItem.prefetchPhase = .pendingDisplay
            removalItem.prefetchPhase = .pendingRemoval

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache
            )
            prefetcher.lastCacheCommitSeed = cache.commitSeed
            prefetcher.operations = [.removal, .display(displayItem)]

            let prefetcherAttribute = graph.makeStatefulRule(prefetcher)
            _ = prefetcherAttribute.value

            XCTAssertEqual(displayItem.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(removalItem.prefetchPhase, .notPrefetching)
        }
    }

    func testLazySubviewPrefetcherConsumesLayoutDisplayProposalPayload() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 44

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache
            )
            prefetcher.lastCacheCommitSeed = cache.commitSeed
            prefetcher.operations = [
                .layoutDisplay(item, _ProposedSize(width: 72, height: nil))
            ]

            XCTAssertEqual(prefetcher.updateHostState(), .all)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(prefetcher.operations.count, 0)
            XCTAssertEqual(item.prefetchSeed, 44)
            XCTAssertEqual(item.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(item.placement?.proposedSize.width, 72)
            XCTAssertEqual(item.placement?.proposedSize.height, 10)
        }
    }

    func testLazySubviewPrefetcherProducesStackLayoutDisplayProposalPayload() throws {

        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 10, height: 11),
                CGSize(width: 20, height: 21),
                CGSize(width: 30, height: 31),
            ]
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                supportsPrefetching: true,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            cache.allowedPrefetchEdges = .vertical
            cache.commitSeed = 55

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache,
                size: ViewSize(CGSize(width: 72, height: 120))
            )

            XCTAssertEqual(
                prefetcher.makeLayoutPrefetchResult(
                    info: state,
                    offset: 2,
                    axis: .vertical,
                    owner: stateAttribute.identifier
                ),
                .all
            )
            XCTAssertEqual(prefetcher.operations.count, 1)
            guard case let .layoutDisplay(item, proposal) = prefetcher.operations.last else {
                XCTFail("expected layout-display prefetch operation")
                return
            }

            let expectedID = _ViewList_ID(implicitID: 2).elementID(at: 0)
            let layoutComputer = try XCTUnwrap(item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(item.id.canonicalID, expectedID.canonicalID)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
            XCTAssertEqual(proposal, _ProposedSize(width: 72, height: nil))
            XCTAssertEqual(layoutComputer.sizeThatFits(.unspecified), sizes[2])

            XCTAssertEqual(prefetcher.update(info: state, owner: stateAttribute.identifier), .all)
            XCTAssertFalse(prefetcher.didScheduleContinuation)
            XCTAssertEqual(prefetcher.operations.count, 0)
            XCTAssertEqual(item.prefetchSeed, 55)
            XCTAssertEqual(item.prefetchPhase, .pendingDisplay)
            XCTAssertEqual(item.placement, _Placement(proposedSize: CGSize(width: 72, height: 10)))

            let (hCache, _, _) = makeLazyCache(
                host: host,
                implicitID: 100,
                supportsPrefetching: true,
                list: list
            )
            hCache.items.removeAll()
            hCache.lru.invalidate()
            hCache.allowedPrefetchEdges = .horizontal

            var hState = ScrollPrefetchState(deadline: 2)
            hState.edges = .horizontal
            let hStateAttribute = graph.makeInput(value: hState)
            var hPrefetcher = makeLazyHStackPrefetcher(
                graph: graph,
                state: hStateAttribute,
                cache: hCache,
                size: ViewSize(CGSize(width: 120, height: 33))
            )

            XCTAssertEqual(
                hPrefetcher.makeLayoutPrefetchResult(
                    info: hState,
                    offset: 1,
                    axis: .horizontal,
                    owner: hStateAttribute.identifier
                ),
                .all
            )
            guard case let .layoutDisplay(hItem, hProposal) = hPrefetcher.operations.last else {
                XCTFail("expected horizontal layout-display prefetch operation")
                return
            }

            let expectedHorizontalID = _ViewList_ID(implicitID: 1).elementID(at: 0)
            XCTAssertEqual(hItem.id.canonicalID, expectedHorizontalID.canonicalID)
            XCTAssertEqual(hProposal, _ProposedSize(width: nil, height: 33))
        }
    }

    func testLazySubviewPrefetcherProducesGridLayoutDisplayProposalPayload() throws {

        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 10, height: 11),
                CGSize(width: 20, height: 21),
                CGSize(width: 30, height: 31),
            ]
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                supportsPrefetching: true,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            cache.allowedPrefetchEdges = .vertical

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVGridPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache,
                size: ViewSize(CGSize(width: 72, height: 120))
            )

            XCTAssertEqual(
                prefetcher.makeLayoutPrefetchResult(
                    info: state,
                    offset: 2,
                    axis: .vertical,
                    owner: stateAttribute.identifier
                ),
                .all
            )
            XCTAssertEqual(prefetcher.operations.count, 1)
            guard case let .layoutDisplay(item, proposal) = prefetcher.operations.last else {
                XCTFail("expected vertical grid layout-display prefetch operation")
                return
            }

            let expectedID = _ViewList_ID(implicitID: 2).elementID(at: 0)
            let layoutComputer = try XCTUnwrap(item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(item.id.canonicalID, expectedID.canonicalID)
            XCTAssertEqual(proposal, _ProposedSize(width: 72, height: nil))
            XCTAssertEqual(layoutComputer.sizeThatFits(.unspecified), sizes[2])

            let (hCache, _, _) = makeLazyCache(
                host: host,
                implicitID: 100,
                supportsPrefetching: true,
                list: list
            )
            hCache.items.removeAll()
            hCache.lru.invalidate()
            hCache.allowedPrefetchEdges = .horizontal

            var hState = ScrollPrefetchState(deadline: 2)
            hState.edges = .horizontal
            let hStateAttribute = graph.makeInput(value: hState)
            var hPrefetcher = makeLazyHGridPrefetcher(
                graph: graph,
                state: hStateAttribute,
                cache: hCache,
                size: ViewSize(CGSize(width: 120, height: 33))
            )

            XCTAssertEqual(
                hPrefetcher.makeLayoutPrefetchResult(
                    info: hState,
                    offset: 1,
                    axis: .horizontal,
                    owner: hStateAttribute.identifier
                ),
                .all
            )
            guard case let .layoutDisplay(hItem, hProposal) = hPrefetcher.operations.last else {
                XCTFail("expected horizontal grid layout-display prefetch operation")
                return
            }

            let expectedHorizontalID = _ViewList_ID(implicitID: 1).elementID(at: 0)
            XCTAssertEqual(hItem.id.canonicalID, expectedHorizontalID.canonicalID)
            XCTAssertEqual(hProposal, _ProposedSize(width: nil, height: 33))
        }
    }

    func testLazySubviewPrefetcherSkipsStackLayoutDisplayBeyondViewportWindow() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = (0..<80).map { index in
                CGSize(width: 10 + CGFloat(index), height: 20 + CGFloat(index))
            }
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                supportsPrefetching: true,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            cache.allowedPrefetchEdges = .vertical

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)
            var prefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache,
                size: ViewSize(CGSize(width: 72, height: 100))
            )

            XCTAssertEqual(
                prefetcher.makeLayoutPrefetchResult(
                    info: state,
                    offset: 76,
                    axis: .vertical,
                    owner: stateAttribute.identifier
                ),
                .none
            )
            XCTAssertTrue(prefetcher.operations.isEmpty)
            XCTAssertTrue(cache.items.isEmpty)

            XCTAssertEqual(
                prefetcher.makeLayoutPrefetchResult(
                    info: state,
                    offset: 75,
                    axis: .vertical,
                    owner: stateAttribute.identifier
                ),
                .all
            )
            XCTAssertEqual(prefetcher.operations.count, 1)
            guard case let .layoutDisplay(item, proposal) = prefetcher.operations.last else {
                XCTFail("expected layout-display prefetch operation")
                return
            }
            XCTAssertEqual(item.id.canonicalID, _ViewList_ID(implicitID: 75).elementID(at: 0).canonicalID)
            XCTAssertEqual(proposal, _ProposedSize(width: 72, height: nil))
        }
    }

    func testLazySubviewPrefetcherSkipsStackLayoutDisplayForDisjointScrollWindows() {

        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let sizes = [
                CGSize(width: 10, height: 11),
                CGSize(width: 20, height: 21),
                CGSize(width: 30, height: 31),
            ]
            let list = SegmentedLayoutViewList(graph: graph, sizes: sizes)
            let (cache, _, _) = makeLazyCache(
                host: host,
                implicitID: 99,
                supportsPrefetching: true,
                list: list
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            cache.allowedPrefetchEdges = .vertical

            var state = ScrollPrefetchState(deadline: 1)
            state.edges = .vertical
            let stateAttribute = graph.makeInput(value: state)

            var disjointTransform = ViewTransform()
            disjointTransform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: .zero,
                    contentSize: CGSize(width: 100, height: 500),
                    containerSize: CGSize(width: 100, height: 100)
                ),
                isClipped: true
            )
            disjointTransform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 200),
                    contentSize: CGSize(width: 100, height: 500),
                    containerSize: CGSize(width: 100, height: 100)
                ),
                isClipped: true
            )
            XCTAssertEqual(disjointTransform.containingScrollGeometry?.visibleRect.minY, 0)
            XCTAssertEqual(disjointTransform.nearestScrollGeometry?.visibleRect.minY, 200)

            var disjointPrefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache,
                size: ViewSize(CGSize(width: 72, height: 120)),
                transform: disjointTransform
            )
            XCTAssertEqual(
                disjointPrefetcher.makeLayoutPrefetchResult(
                    info: state,
                    offset: 2,
                    axis: .vertical,
                    owner: stateAttribute.identifier
                ),
                .none
            )
            XCTAssertTrue(disjointPrefetcher.operations.isEmpty)
            XCTAssertTrue(cache.items.isEmpty)

            var overlappingTransform = ViewTransform()
            overlappingTransform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: .zero,
                    contentSize: CGSize(width: 100, height: 500),
                    containerSize: CGSize(width: 100, height: 100)
                ),
                isClipped: true
            )
            overlappingTransform.appendScrollGeometry(
                ScrollGeometry(
                    contentOffset: CGPoint(x: 0, y: 50),
                    contentSize: CGSize(width: 100, height: 500),
                    containerSize: CGSize(width: 100, height: 100)
                ),
                isClipped: true
            )
            var overlappingPrefetcher = makeLazyVStackPrefetcher(
                graph: graph,
                state: stateAttribute,
                cache: cache,
                size: ViewSize(CGSize(width: 72, height: 120)),
                transform: overlappingTransform
            )
            XCTAssertEqual(
                overlappingPrefetcher.makeLayoutPrefetchResult(
                    info: state,
                    offset: 2,
                    axis: .vertical,
                    owner: stateAttribute.identifier
                ),
                .all
            )
            XCTAssertEqual(overlappingPrefetcher.operations.count, 1)
            guard case let .layoutDisplay(item, proposal) = overlappingPrefetcher.operations.last else {
                XCTFail("expected layout-display prefetch operation")
                return
            }
            XCTAssertEqual(item.id.canonicalID, _ViewList_ID(implicitID: 2).elementID(at: 0).canonicalID)
            XCTAssertEqual(proposal, _ProposedSize(width: 72, height: nil))
        }
    }

    func testLazyLayoutViewCacheChildPrefetchPhaseTracksMaxDisplayListSubviews() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host, implicitID: 1)
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            cache.commitSeed = 21
            item.prefetchSeed = 21
            childCache.placedIndices = (min: 0, max: 2)

            XCTAssertNil(childCache.maxDisplayListSubviews)
            XCTAssertFalse(cache.hasChildPrefetchPhaseWork(item: item))
            XCTAssertTrue(cache.setupChildPrefetchPhase(item: item))
            XCTAssertEqual(childCache.maxDisplayListSubviews, 0)
            XCTAssertTrue(cache.hasChildPrefetchPhaseWork(item: item))

            XCTAssertTrue(cache.advanceChildPrefetchPhase(item: item))
            XCTAssertEqual(childCache.maxDisplayListSubviews, 1)
            XCTAssertTrue(cache.hasChildPrefetchPhaseWork(item: item))

            XCTAssertTrue(cache.advanceChildPrefetchPhase(item: item))
            XCTAssertEqual(childCache.maxDisplayListSubviews, 2)
            XCTAssertTrue(cache.hasChildPrefetchPhaseWork(item: item))

            XCTAssertTrue(cache.advanceChildPrefetchPhase(item: item))
            XCTAssertEqual(childCache.maxDisplayListSubviews, 3)
            XCTAssertFalse(cache.hasChildPrefetchPhaseWork(item: item))

            cache.resetMaxDisplayListSubviews(item: item)
            XCTAssertNil(childCache.maxDisplayListSubviews)
            XCTAssertFalse(cache.hasChildPrefetchPhaseWork(item: item))
        }
    }

    func testLazyLayoutViewCacheChildPrefetchPhaseUsesDisplaySeedGate() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host, implicitID: 1)
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(
                children: [WeakBox(childCache)]
            )
            cache.commitSeed = 21
            item.prefetchSeed = 20
            childCache.placedIndices = (min: 0, max: 2)

            XCTAssertFalse(cache.setupChildPrefetchPhase(item: item))
            XCTAssertNil(childCache.maxDisplayListSubviews)
            childCache.maxDisplayListSubviews = 0
            XCTAssertFalse(cache.hasChildPrefetchPhaseWork(item: item))
            XCTAssertFalse(cache.advanceChildPrefetchPhase(item: item))
            XCTAssertEqual(childCache.maxDisplayListSubviews, 0)

            cache.resetMaxDisplayListSubviews(item: item)
            XCTAssertNil(childCache.maxDisplayListSubviews)
        }
    }

    func testLazyLayoutViewCacheChildPrefetchPhaseSkipsReleasedWeakChildren() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host, implicitID: 1)
            var releasedChild = WeakBox<LazyLayoutViewCache>(nil)
            do {
                let (deadChildCache, _, _) = makeLazyCache(host: host, implicitID: 10)
                deadChildCache.placedIndices = (min: 0, max: 2)
                deadChildCache.maxDisplayListSubviews = 0
                releasedChild = WeakBox(deadChildCache)
            }
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(children: [releasedChild])
            cache.commitSeed = 21
            item.prefetchSeed = 21

            XCTAssertFalse(cache.hasChildPrefetchPhaseWork(item: item))
            XCTAssertFalse(cache.setupChildPrefetchPhase(item: item))
            XCTAssertFalse(cache.advanceChildPrefetchPhase(item: item))

            let (liveChildCache, _, _) = makeLazyCache(host: host, implicitID: 11)
            liveChildCache.placedIndices = (min: 0, max: 2)
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(
                children: [
                    releasedChild,
                    WeakBox(liveChildCache),
                ]
            )

            XCTAssertTrue(cache.setupChildPrefetchPhase(item: item))
            XCTAssertEqual(liveChildCache.maxDisplayListSubviews, 0)
            XCTAssertTrue(cache.advanceChildPrefetchPhase(item: item))
            XCTAssertEqual(liveChildCache.maxDisplayListSubviews, 1)

            cache.resetMaxDisplayListSubviews(item: item)
            XCTAssertNil(liveChildCache.maxDisplayListSubviews)
        }
    }

    func testLazyLayoutViewCacheItemDataMissReusesLRUCandidateBeforeNewItem() {
        let host = GraphHost()

        host.data.withCurrent {
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            candidate.insertionTransactionSeed = 18
            candidate.usedSeed = 12
            candidate.placementSeed = 10
            candidate.prefetchSeed = 4

            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertTrue(returned === candidate)
            XCTAssertNil(cache.item(for: oldID.canonicalID))
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === candidate)
            XCTAssertEqual(candidate.id, targetID)
            XCTAssertEqual(candidate.reuseIdentifier, targetID.reuseIdentifier)
            XCTAssertEqual(candidate.usedSeed, 0)
            XCTAssertEqual(candidate.prefetchSeed, 0)
            XCTAssertEqual(candidate.prefetchPhase, .notPrefetching)
            XCTAssertEqual(cache.lru.usedSeed, 1)
        }
    }

    func testLazyLayoutViewCacheItemDataReuseMovesChildCachesToRefreshedID() {
        let host = GraphHost()

        host.data.withCurrent {
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[oldID.canonicalID] = LazyLayoutCacheChildren(
                seed: 7,
                children: [WeakBox(childCache)]
            )
            cache.childCacheSeeds[7] = oldID.canonicalID
            cache.lru.transactionSeed = 20
            cache.commitSeed = 21
            candidate.insertionTransactionSeed = 18
            candidate.placementSeed = 10
            candidate.prefetchSeed = 21

            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertTrue(returned === candidate)
            XCTAssertNil(cache.childCaches[oldID.canonicalID])
            XCTAssertEqual(cache.childCaches[targetID.canonicalID]?.seed, 7)
            XCTAssertEqual(cache.childCacheSeeds[7], targetID.canonicalID)
            XCTAssertTrue(cache.childCaches[targetID.canonicalID]?.children.first?.base === childCache)
            returned.prefetchSeed = cache.commitSeed
            XCTAssertTrue(cache.setupChildPrefetchPhase(item: returned))
            XCTAssertEqual(childCache.maxDisplayListSubviews, 0)
        }
    }

    func testLazyLayoutViewCacheAddItemMarksFreshCandidateWithLRUTransactionSeed() {
        let host = GraphHost()

        host.data.withCurrent {
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            cache.lru.transactionSeed = 20
            candidate.insertionTransactionSeed = 0
            candidate.placementSeed = 10
            candidate.displayIndex = nil

            cache.addItem(candidate)
            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertEqual(candidate.insertionTransactionSeed, 20)
            XCTAssertFalse(returned === candidate)
            XCTAssertTrue(cache.item(for: oldID.canonicalID) === candidate)
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === returned)
            XCTAssertEqual(returned.insertionTransactionSeed, 20)
        }
    }

    func testLazyLayoutViewCacheAddItemResetRefreshesNonScrollEditStateForReuse() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, state) = makeLazyCache(host: host)
            cache.lru.transactionSeed = 8
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 6,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: true
                )
            )

            cache.addItem(item, reset: true)

            XCTAssertEqual(item.insertionTransactionSeed, 8)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 7,
                    phase: .willAppear,
                    enableTransitions: false,
                    isRemoved: false
                )
            )
            XCTAssertEqual(item.usedSeed, 0)
            XCTAssertEqual(item.placementSeed, 0)
            XCTAssertEqual(item.commitSeed, 0)
            XCTAssertEqual(item.prefetchSeed, 0)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
        }
    }

    func testLazyLayoutViewCacheAddItemNonScrollUsesViewListEditForTransitionState() {
        let host = GraphHost()

        host.data.withCurrent {
            let recorder = ViewListEditRecorder()
            let list = EditingViewList(edit: .inserted, recorder: recorder)
            let (cache, item, state) = makeLazyCache(host: host, list: list)
            cache.lru.lastTransactionID.value = 42
            cache.lru.transactionSeed = 13
            recorder.ids.removeAll()
            recorder.transactionIDs.removeAll()
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 2,
                    phase: .didDisappear,
                    enableTransitions: false,
                    isRemoved: true
                )
            )

            cache.addItem(item)

            XCTAssertEqual(item.insertionTransactionSeed, 13)
            XCTAssertEqual(recorder.ids, [item.id])
            XCTAssertEqual(recorder.transactionIDs.map(\.value), [42])
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 2,
                    phase: .willAppear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )
        }
    }

    func testLazyLayoutViewCacheAddItemFromScrollViewPublishesIdentityStateWithoutReset() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, state) = makeLazyCache(host: host)
            cache.lru.transactionSeed = 11
            item.usedSeed = 4
            item.placementSeed = 5
            item.commitSeed = 6
            item.prefetchSeed = 7
            item.prefetchPhase = .prefetching
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 3,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: true
                )
            )

            withTransaction(\.fromScrollView, true) {
                cache.addItem(item)
            }

            XCTAssertEqual(item.insertionTransactionSeed, 11)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 3,
                    phase: .identity,
                    enableTransitions: false,
                    isRemoved: false
                )
            )
            XCTAssertEqual(item.usedSeed, 4)
            XCTAssertEqual(item.placementSeed, 5)
            XCTAssertEqual(item.commitSeed, 6)
            XCTAssertEqual(item.prefetchSeed, 7)
            XCTAssertEqual(item.prefetchPhase, .prefetching)
        }
    }

    func testLazyLayoutViewCacheAddItemFromScrollViewResetRefreshesStateAndSeeds() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, state) = makeLazyCache(host: host)
            cache.lru.transactionSeed = 12
            item.usedSeed = 4
            item.placementSeed = 5
            item.commitSeed = 6
            item.prefetchSeed = 7
            item.prefetchPhase = .prefetching
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 8,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: true
                )
            )

            withTransaction(\.fromScrollView, true) {
                cache.addItem(item, reset: true)
            }

            XCTAssertEqual(item.insertionTransactionSeed, 12)
            XCTAssertEqual(
                state.value,
                LazyLayoutCacheItem.State(
                    resetDelta: 9,
                    phase: .identity,
                    enableTransitions: false,
                    isRemoved: false
                )
            )
            XCTAssertEqual(item.usedSeed, 0)
            XCTAssertEqual(item.placementSeed, 0)
            XCTAssertEqual(item.commitSeed, 0)
            XCTAssertEqual(item.prefetchSeed, 0)
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
        }
    }

    func testLazyLayoutViewCacheItemDataReusePreservesCandidateSubgraphAndOutputs() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            candidate.insertionTransactionSeed = 18
            candidate.usedSeed = 12
            candidate.placementSeed = 10
            let originalSubgraph = candidate.subgraph
            let originalLayoutSize = CGSize(width: 12, height: 8)
            candidate.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(
                    graph.makeInput(value: LayoutComputer.fixed(originalLayoutSize))
                )
            )

            var makeViewCount = 0
            let replacementElements = _ViewList_SubgraphElements(
                base: UnaryElements(
                    body: BodyUnaryViewGenerator(
                        body: { _ in
                            makeViewCount += 1
                            return _ViewOutputs(
                                layoutComputer: OptionalAttribute(
                                    graph.makeInput(value: LayoutComputer.fixed(CGSize(width: 99, height: 99)))
                                )
                            )
                        },
                        viewType: EmptyView.self
                    ),
                    baseInputs: makeViewInputs(graph: graph).base
                )
            )
            let data = _LazyLayout_Subview.Data(
                elements: replacementElements,
                id: targetID,
                list: graph.makeInput(value: EmptyViewList() as any ViewList)
            )

            let returned = cache.item(data: data)
            let layout = try XCTUnwrap(returned.outputs._layoutComputer.attribute?.value)

            XCTAssertTrue(returned === candidate)
            XCTAssertTrue(returned.subgraph === originalSubgraph)
            XCTAssertEqual(makeViewCount, 0)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), originalLayoutSize)
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === candidate)
            XCTAssertNil(cache.item(for: oldID.canonicalID))
        }
    }

    func testLazyLayoutViewCacheItemDataMissSkipsFreshReuseCandidate() {
        let host = GraphHost()

        host.data.withCurrent {
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            candidate.insertionTransactionSeed = 20
            candidate.placementSeed = 10

            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertFalse(returned === candidate)
            XCTAssertTrue(cache.item(for: oldID.canonicalID) === candidate)
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === returned)
        }
    }

    func testLazyLayoutViewCacheItemDataMissSkipsCurrentSeedReuseCandidate() {
        let host = GraphHost()

        host.data.withCurrent {
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            cache.placementSeed = 20
            candidate.insertionTransactionSeed = 18
            candidate.placementSeed = 20

            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertFalse(returned === candidate)
            XCTAssertTrue(cache.item(for: oldID.canonicalID) === candidate)
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === returned)
        }
    }

    func testLazyLayoutViewCacheItemDataMissSkipsDisplayedReuseCandidate() {
        let host = GraphHost()

        host.data.withCurrent {
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            candidate.insertionTransactionSeed = 18
            candidate.placementSeed = 10
            candidate.displayIndex = 3

            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertFalse(returned === candidate)
            XCTAssertTrue(cache.item(for: oldID.canonicalID) === candidate)
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === returned)
        }
    }

    func testLazyLayoutViewCacheItemDataMissReusesPendingRemovalCandidate() {
        let host = GraphHost()

        host.data.withCurrent {
            let oldID = _ViewList_ID(implicitID: 1)
            let targetID = _ViewList_ID(implicitID: 99)
            let (cache, candidate, _) = makeLazyCache(
                host: host,
                implicitID: oldID.index,
                reuseIdentifier: targetID.reuseIdentifier
            )
            cache.lru.transactionSeed = 20
            candidate.insertionTransactionSeed = 18
            candidate.usedSeed = 12
            candidate.placementSeed = 10
            candidate.prefetchSeed = 4
            candidate.prefetchPhase = .pendingRemoval

            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertTrue(returned === candidate)
            XCTAssertNil(cache.item(for: oldID.canonicalID))
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === candidate)
            XCTAssertEqual(candidate.id, targetID)
            XCTAssertEqual(candidate.insertionTransactionSeed, 20)
            XCTAssertEqual(candidate.prefetchSeed, 0)
            XCTAssertEqual(candidate.prefetchPhase, .notPrefetching)
        }
    }

    func testLazyLayoutViewCacheItemDataMissCreatesNewItemWhenNoReusableCandidate() {
        let host = GraphHost()

        host.data.withCurrent {
            let targetID = _ViewList_ID(explicitID: AnyHashable("new"))
            let (cache, seeded, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                reuseIdentifier: targetID.reuseIdentifier &+ 1
            )
            cache.items.removeAll()
            cache.lru.invalidate()
            var traits = ViewTraitCollection()
            traits[ZIndexTraitKey.self] = 11

            let data = makeLazyData(
                graph: host.data.graph,
                id: targetID,
                traits: traits,
                section: LazyLayoutCacheSection(id: 3, isHeader: true)
            )
            let item = cache.item(data: data)

            XCTAssertFalse(item === seeded)
            XCTAssertEqual(item.id, targetID)
            XCTAssertEqual(item.reuseIdentifier, targetID.reuseIdentifier)
            XCTAssertEqual(item.zIndex, 11)
            XCTAssertEqual(item.section, LazyLayoutCacheSection(id: 3, isHeader: true))
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === item)
        }
    }

    func testLazyLayoutViewCacheNewItemMaterializesElementOutputsInItemSubgraph() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            let targetID = _ViewList_ID(explicitID: AnyHashable("materialized"))
            let (cache, _, _) = makeLazyCache(host: host, implicitID: 1)
            cache.items.removeAll()
            cache.lru.invalidate()

            var makeViewCount = 0
            weak var observedSubgraph: AGSubgraph?
            let layoutSize = CGSize(width: 31, height: 17)
            let elements = _ViewList_SubgraphElements(
                base: UnaryElements(
                    body: BodyUnaryViewGenerator(
                        body: { _ in
                            makeViewCount += 1
                            observedSubgraph = AGSubgraph.current
                            return _ViewOutputs(
                                layoutComputer: OptionalAttribute(
                                    graph.makeInput(value: LayoutComputer.fixed(layoutSize))
                                )
                            )
                        },
                        viewType: EmptyView.self
                    ),
                    baseInputs: makeViewInputs(graph: graph).base
                )
            )
            let data = _LazyLayout_Subview.Data(
                elements: elements,
                id: targetID,
                list: graph.makeInput(value: EmptyViewList() as any ViewList)
            )

            let item = cache.item(data: data)
            let layout = try XCTUnwrap(item.outputs._layoutComputer.attribute?.value)

            XCTAssertEqual(makeViewCount, 1)
            XCTAssertTrue(observedSubgraph === item.subgraph)
            XCTAssertGreaterThan(item.subgraph.nodes.count, 0)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), layoutSize)
            XCTAssertTrue(cache.item(for: targetID.canonicalID) === item)
        }
    }

    func testLazyScrollableStoresOptionalConcreteCacheAndUsesCacheCollectionIDs() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let list = SegmentedLayoutViewList(
                graph: graph,
                sizes: [
                    CGSize(width: 5, height: 12),
                    CGSize(width: 10, height: 12),
                ]
            )
            let cache = makeConcreteLazyGridCache(
                host: host,
                layout: LazyVGridLayout(
                    columns: [GridItem(.fixed(12))],
                    alignment: .center,
                    spacing: 0,
                    pinnedViews: []
                ),
                nearestScrollableAxes: .vertical
            )
            cache.inputs.size = graph.makeInput(
                value: ViewSize(width: 12, height: 40)
            )
            cache._list = graph.makeInput(value: list as any ViewList)

            let (_, item, _) = makeLazyCache(
                host: host,
                cache: cache,
                implicitID: 1,
                list: list
            )
            item.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(
                    graph.makeInput(value: LayoutComputer.fixed(CGSize(width: 10, height: 12)))
                )
            )
            let placement = _Placement(
                proposedSize: CGSize(width: 10, height: 12),
                anchoring: .topLeading,
                at: CGPoint(x: 20, y: 30)
            )
            cache._placedSubviews.setValue([
                _LazyLayout_PlacedSubview(item: item, placement: placement, index: 1),
            ])

            let parent = LazyRecordingScrollable(acceptsTargets: false)
            let child = LazyRecordingScrollable(acceptsTargets: true)
            let parentAttr = graph.makeInput(value: parent as any Scrollable)
            let childrenAttr = graph.makeInput(value: [child as any Scrollable])
            let scrollable = LazyScrollable<LazyVGridLayout>(
                position: graph.makeInput(value: CGPoint.zero).asWeak(),
                transform: graph.makeInput(value: ViewTransform()).asWeak(),
                parent: parentAttr.asWeak(),
                children: childrenAttr.asWeak(),
                cache: cache
            )

            XCTAssertTrue(scrollable.cache === cache)
            XCTAssertTrue(scrollable.isLazy)
            XCTAssertEqual(LazyScrollable<LazyVGridLayout>.accessibilityRole, .grid)
            XCTAssertEqual(scrollable.visibleCollectionViewIDs, [item.id.canonicalID])
            XCTAssertEqual(scrollable.collectionViewID(for: item.subgraph), item.id.canonicalID)
            XCTAssertNil(scrollable.collectionViewID(for: AGSubgraph()))

            var index = 0
            var appliedIDs: [_ViewList_ID.Canonical] = []
            XCTAssertTrue(scrollable.applyCollectionViewIDs(from: &index) { id, stop in
                appliedIDs.append(id)
                stop = false
            })
            XCTAssertEqual(index, 2)
            XCTAssertEqual(appliedIDs.count, 2)
            XCTAssertEqual(appliedIDs.map(\.implicitID), [0, 1])
            XCTAssertEqual(scrollable.firstCollectionViewIndex(of: appliedIDs[1]), 1)

            let visible = scrollable.visibleSubviews
            XCTAssertEqual(visible.count, 1)
            XCTAssertEqual(visible.first?.id, item.id)
            XCTAssertEqual(visible.first?.frame, CGRect(x: 20, y: 30, width: 10, height: 12))

            let request = graph.makeStatefulRule(
                LazyScrollableTargetRequest(
                    scrollable: scrollable,
                    id: appliedIDs[1],
                    anchor: .center
                )
            )
            XCTAssertFalse(request.value)
            XCTAssertEqual(parent.targetRequestCount, 1)
            XCTAssertEqual(child.targetRequestCount, 0)
            XCTAssertEqual(
                parent.lastTarget,
                ScrollTarget(rect: CGRect(x: 0, y: 12, width: 12, height: 12), anchor: .center)
            )

            parent.firstChildMarker = LazyScrollableLookupMarker(11)
            let parentResult = scrollable.mapFirstChild(ofType: LazyScrollableLookupMarker.self) { $0.value }
            XCTAssertEqual(parentResult, 11)
            XCTAssertEqual(parent.mapFirstChildCallCount, 1)
            XCTAssertEqual(child.mapFirstChildCallCount, 0)

            parent.firstChildMarker = nil
            parent.mapFirstChildCallCount = 0
            child.mapFirstChildCallCount = 0
            child.firstChildMarker = LazyScrollableLookupMarker(22)
            let childResult = scrollable.mapFirstChild(ofType: LazyScrollableLookupMarker.self) { $0.value }
            XCTAssertEqual(childResult, 22)
            XCTAssertEqual(parent.mapFirstChildCallCount, 1)
            XCTAssertEqual(child.mapFirstChildCallCount, 1)

            parent.mapFirstChildCallCount = 0
            child.mapFirstChildCallCount = 0
            let directChild = scrollable.mapFirstChild(ofType: LazyRecordingScrollable.self) { $0 }
            XCTAssertTrue(directChild === child)
            XCTAssertEqual(parent.mapFirstChildCallCount, 1)
            XCTAssertEqual(child.mapFirstChildCallCount, 0)
        }
    }

    func testLazyScrollableNextVisibleCollectionViewIDUsesVisibleLazyIndexes() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let list = SegmentedLayoutViewList(
                graph: graph,
                sizes: Array(repeating: CGSize(width: 10, height: 10), count: 7)
            )
            let cache = makeConcreteLazyGridCache(
                host: host,
                layout: LazyVGridLayout(
                    columns: [GridItem(.fixed(10))],
                    alignment: .center,
                    spacing: nil,
                    pinnedViews: [.sectionHeaders]
                ),
                nearestScrollableAxes: [.horizontal, .vertical]
            )
            cache._list = graph.makeInput(value: list as any ViewList)

            func item(
                implicitID: Int,
                at origin: CGPoint,
                section: LazyLayoutCacheSection = LazyLayoutCacheSection()
            ) -> _LazyLayout_PlacedSubview {
                let item = makeLazyCache(
                    host: host,
                    cache: cache,
                    implicitID: implicitID,
                    list: list
                ).item
                item.section = section
                item.outputs = _ViewOutputs(
                    layoutComputer: OptionalAttribute(
                        graph.makeInput(value: LayoutComputer.fixed(CGSize(width: 10, height: 10)))
                    )
                )
                return _LazyLayout_PlacedSubview(
                    item: item,
                    placement: _Placement(
                        proposedSize: CGSize(width: 10, height: 10),
                        anchoring: .topLeading,
                        at: origin
                    ),
                    index: implicitID
                )
            }

            cache._placedSubviews.setValue([
                item(implicitID: 0, at: CGPoint(x: 0, y: 20)),
                item(implicitID: 1, at: CGPoint(x: 20, y: 0)),
                item(implicitID: 2, at: CGPoint(x: 20, y: 20)),
                item(
                    implicitID: 3,
                    at: CGPoint(x: 42, y: 20),
                    section: LazyLayoutCacheSection(id: 2, isFooter: true)
                ),
                item(
                    implicitID: 4,
                    at: CGPoint(x: 20, y: 42),
                    section: LazyLayoutCacheSection(id: 1, isHeader: true)
                ),
                item(implicitID: 5, at: CGPoint(x: 22, y: 64)),
                item(implicitID: 6, at: CGPoint(x: 64, y: 20)),
            ])

            let parent = LazyRecordingScrollable(acceptsTargets: false)
            let parentAttr = graph.makeInput(value: parent as any Scrollable)
            let childrenAttr = graph.makeInput(value: [any Scrollable]())
            let scrollable = LazyScrollable<LazyVGridLayout>(
                position: graph.makeInput(value: CGPoint.zero).asWeak(),
                transform: graph.makeInput(value: ViewTransform()).asWeak(),
                parent: parentAttr.asWeak(),
                children: childrenAttr.asWeak(),
                cache: cache
            )

            var collectionIndex = 0
            var collectionIDs: [_ViewList_ID.Canonical] = []
            XCTAssertTrue(scrollable.applyCollectionViewIDs(from: &collectionIndex) { id, stop in
                collectionIDs.append(id)
                stop = false
            })
            XCTAssertEqual(collectionIDs.count, 7)

            let source = collectionIDs[2]
            XCTAssertEqual(
                scrollable.nextVisibleCollectionViewID(
                    towards: .top,
                    from: source,
                    border: .zero,
                    ignoring: []
                ),
                collectionIDs[1]
            )
            XCTAssertEqual(
                scrollable.nextVisibleCollectionViewID(
                    towards: .leading,
                    from: source,
                    border: .zero,
                    ignoring: []
                ),
                collectionIDs[0]
            )
            XCTAssertEqual(
                scrollable.nextVisibleCollectionViewID(
                    towards: .trailing,
                    from: source,
                    border: .zero,
                    ignoring: []
                ),
                collectionIDs[3]
            )
            XCTAssertEqual(
                scrollable.nextVisibleCollectionViewID(
                    towards: .trailing,
                    from: source,
                    border: .zero,
                    ignoring: [.sectionFooters]
                ),
                collectionIDs[6]
            )
            XCTAssertEqual(
                scrollable.nextVisibleCollectionViewID(
                    towards: .bottom,
                    from: source,
                    border: .zero,
                    ignoring: []
                ),
                collectionIDs[4]
            )
            XCTAssertEqual(
                scrollable.nextVisibleCollectionViewID(
                    towards: .bottom,
                    from: source,
                    border: .zero,
                    ignoring: [.sectionHeaders]
                ),
                collectionIDs[5]
            )
            XCTAssertNil(
                scrollable.nextVisibleCollectionViewID(
                    towards: .center,
                    from: source,
                    border: .zero,
                    ignoring: []
                )
            )
        }
    }

    func testLazyScrollableBuildsNonVisibleTargetFromListIndex() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 0),
                pinnedViews: []
            )
            let list = SegmentedLayoutViewList(
                graph: graph,
                sizes: [
                    CGSize(width: 40, height: 10),
                    CGSize(width: 50, height: 20),
                    CGSize(width: 60, height: 30),
                ]
            )
            var inputs = makeViewInputs(graph: graph)
            inputs.size = graph.makeInput(value: ViewSize(width: 100, height: 40))
            let cache = _LazyLayoutViewCache(
                layout: graph.makeInput(value: layout),
                cacheState: LazyVStackLayout.initialCache,
                viewGraph: host,
                parentSubgraph: AGSubgraph(),
                inputs: inputs,
                outputs: _ViewOutputs(),
                list: graph.makeInput(value: list as any ViewList),
                layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                nearestScrollableAxes: graph.makeInput(value: Axis.Set.vertical),
                placedSubviews: graph.makeInput(value: []),
                prefetchSignal: graph.makeInput(value: ()),
                scrollPosition: OptionalAttribute(),
                accessibilityEnabled: graph.makeInput(value: false)
            )
            cache.containingSize = CGSize(width: 100, height: 40)

            let parent = LazyRecordingScrollable(acceptsTargets: true)
            let parentAttr = graph.makeInput(value: parent as any Scrollable)
            let childrenAttr = graph.makeInput(value: [any Scrollable]())
            let scrollable = LazyScrollable<LazyVStackLayout>(
                position: graph.makeInput(value: CGPoint.zero).asWeak(),
                transform: graph.makeInput(value: ViewTransform()).asWeak(),
                parent: parentAttr.asWeak(),
                children: childrenAttr.asWeak(),
                cache: cache
            )

            var collectionIndex = 0
            var collectionIDs: [_ViewList_ID.Canonical] = []
            XCTAssertTrue(scrollable.applyCollectionViewIDs(from: &collectionIndex) { id, stop in
                collectionIDs.append(id)
                stop = false
            })
            XCTAssertEqual(collectionIDs.count, 3)

            let targetID = collectionIDs[2]
            XCTAssertEqual(scrollable.firstCollectionViewIndex(of: targetID), 2)
            let request = graph.makeStatefulRule(
                LazyScrollableTargetRequest(
                    scrollable: scrollable,
                    id: targetID,
                    anchor: .bottom
                )
            )

            XCTAssertTrue(request.value)
            XCTAssertEqual(parent.targetRequestCount, 1)
            XCTAssertEqual(
                parent.lastTarget,
                ScrollTarget(rect: CGRect(x: 0, y: 30, width: 100, height: 15), anchor: .bottom)
            )
            XCTAssertTrue(cache._placedSubviews.value.isEmpty)
            XCTAssertEqual(cache.items.count, 2)
            XCTAssertFalse(cache.items.values.contains {
                $0.id.canonicalID.implicitID == targetID.implicitID
            })
        }
    }

    func testLazyScrollableNonVisibleTargetMirrorsRectForRightToLeftLayoutDirection() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 0),
                pinnedViews: []
            )
            let list = SegmentedLayoutViewList(
                graph: graph,
                sizes: [
                    CGSize(width: 40, height: 10),
                    CGSize(width: 50, height: 20),
                    CGSize(width: 60, height: 30),
                ]
            )
            var inputs = makeViewInputs(graph: graph)
            inputs.size = graph.makeInput(value: ViewSize(width: 100, height: 40))
            let cache = _LazyLayoutViewCache(
                layout: graph.makeInput(value: layout),
                cacheState: LazyVStackLayout.initialCache,
                viewGraph: host,
                parentSubgraph: AGSubgraph(),
                inputs: inputs,
                outputs: _ViewOutputs(),
                list: graph.makeInput(value: list as any ViewList),
                layoutDirection: graph.makeInput(value: LayoutDirection.rightToLeft),
                nearestScrollableAxes: graph.makeInput(value: Axis.Set.vertical),
                placedSubviews: graph.makeInput(value: []),
                prefetchSignal: graph.makeInput(value: ()),
                scrollPosition: OptionalAttribute(),
                accessibilityEnabled: graph.makeInput(value: false)
            )
            cache.containingSize = CGSize(width: 100, height: 40)

            let parent = LazyRecordingScrollable(acceptsTargets: true)
            let parentAttr = graph.makeInput(value: parent as any Scrollable)
            let childrenAttr = graph.makeInput(value: [any Scrollable]())
            let scrollable = LazyScrollable<LazyVStackLayout>(
                position: graph.makeInput(value: CGPoint.zero).asWeak(),
                transform: graph.makeInput(value: ViewTransform()).asWeak(),
                parent: parentAttr.asWeak(),
                children: childrenAttr.asWeak(),
                cache: cache
            )

            var collectionIndex = 0
            var collectionIDs: [_ViewList_ID.Canonical] = []
            XCTAssertTrue(scrollable.applyCollectionViewIDs(from: &collectionIndex) { id, stop in
                collectionIDs.append(id)
                stop = false
            })

            let request = graph.makeStatefulRule(
                LazyScrollableTargetRequest(
                    scrollable: scrollable,
                    id: collectionIDs[2],
                    anchor: .top
                )
            )

            XCTAssertTrue(request.value)
            XCTAssertEqual(parent.targetRequestCount, 1)
            XCTAssertEqual(
                parent.lastTarget,
                ScrollTarget(rect: CGRect(x: 0, y: 30, width: 100, height: 15), anchor: .top)
            )
        }
    }

    func testLazyScrollableNonVisibleTargetUsesNearestContentCoordinateSpace() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let layout = LazyVStackLayout(
                base: _VStackLayout(alignment: .leading, spacing: 0),
                pinnedViews: []
            )
            let list = SegmentedLayoutViewList(
                graph: graph,
                sizes: [
                    CGSize(width: 40, height: 10),
                    CGSize(width: 50, height: 20),
                    CGSize(width: 60, height: 30),
                ]
            )
            var inputs = makeViewInputs(graph: graph)
            inputs.size = graph.makeInput(value: ViewSize(width: 100, height: 40))
            let cache = _LazyLayoutViewCache(
                layout: graph.makeInput(value: layout),
                cacheState: LazyVStackLayout.initialCache,
                viewGraph: host,
                parentSubgraph: AGSubgraph(),
                inputs: inputs,
                outputs: _ViewOutputs(),
                list: graph.makeInput(value: list as any ViewList),
                layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                nearestScrollableAxes: graph.makeInput(value: Axis.Set.vertical),
                placedSubviews: graph.makeInput(value: []),
                prefetchSignal: graph.makeInput(value: ()),
                scrollPosition: OptionalAttribute(),
                accessibilityEnabled: graph.makeInput(value: false)
            )
            cache.containingSize = CGSize(width: 100, height: 40)

            var contentTransform = ViewTransform.identity
            contentTransform.appendTranslation(CGSize(width: 300, height: 300))
            contentTransform.appendSizedSpace(
                id: ScrollCoordinateSpace.content.id,
                size: CGSize(width: 500, height: 500)
            )
            contentTransform.appendTranslation(CGSize(width: 40, height: 50))
            contentTransform.appendSizedSpace(
                id: ScrollCoordinateSpace.content.id,
                size: CGSize(width: 100, height: 90)
            )
            contentTransform.appendTranslation(CGSize(width: -11, height: -13))

            let parent = LazyRecordingScrollable(acceptsTargets: true)
            let parentAttr = graph.makeInput(value: parent as any Scrollable)
            let childrenAttr = graph.makeInput(value: [any Scrollable]())
            let scrollable = LazyScrollable<LazyVStackLayout>(
                position: graph.makeInput(value: CGPoint.zero).asWeak(),
                transform: graph.makeInput(value: contentTransform).asWeak(),
                parent: parentAttr.asWeak(),
                children: childrenAttr.asWeak(),
                cache: cache
            )

            var collectionIndex = 0
            var collectionIDs: [_ViewList_ID.Canonical] = []
            XCTAssertTrue(scrollable.applyCollectionViewIDs(from: &collectionIndex) { id, stop in
                collectionIDs.append(id)
                stop = false
            })

            let request = graph.makeStatefulRule(
                LazyScrollableTargetRequest(
                    scrollable: scrollable,
                    id: collectionIDs[2],
                    anchor: .top
                )
            )

            XCTAssertTrue(request.value)
            XCTAssertEqual(parent.targetRequestCount, 1)
            XCTAssertEqual(
                parent.lastTarget,
                ScrollTarget(rect: CGRect(x: -11, y: 17, width: 100, height: 15), anchor: .top)
            )
        }
    }

    func testLazyStackMakeViewConstructsConcreteCacheAndPublishesLazyScrollable() throws {
        let host = GraphHost()
        var scrollablesID: AGAttribute!

        try host.data.withCurrent {
            let graph = host.data.graph
            let stack = LazyVStack(spacing: 0) {
                LazyFixedItemView()
                LazyFixedItemView()
            }
            let source = graph.makeInput(value: stack)
            var inputs = makeViewInputs(graph: graph)
            inputs.size = graph.makeInput(value: ViewSize(width: 20, height: 20))
            inputs.preferences.keys.add(ScrollablePreferenceKey.self)

            let outputs = type(of: stack)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: inputs
            )
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(
                layout.sizeThatFits(_ProposedSize(CGSize(width: 20, height: 20))),
                CGSize(width: 20, height: 2)
            )

            let scrollablesAttr = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            scrollablesID = scrollablesAttr
            XCTAssertFalse(Attribute<ScrollablePreferenceKey.Value>(scrollablesAttr).value.isEmpty)
            XCTAssertFalse(host.hasPendingTransactions)
        }

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let scrollable = try XCTUnwrap(
                scrollables.compactMap { $0 as? LazyScrollable<LazyVStackLayout> }.first
            )
            let cache = try XCTUnwrap(scrollable.cache)

            XCTAssertTrue(cache._list.value.count(style: _ViewList_IteratorStyle()) >= 2)
            XCTAssertTrue(type(of: cache._layout.value) == LazyVStackLayout.self)
            XCTAssertEqual(scrollable.visibleCollectionViewIDs.count, 2)
            XCTAssertEqual(cache.items.count, 2)
            XCTAssertEqual(LazyScrollable<LazyVStackLayout>.accessibilityRole, .stack)
        }
    }

    func testLazyStackMakeViewPhaseResetRefreshesConcreteCache() throws {
        let host = GraphHost()
        var scrollablesID: AGAttribute!
        var phaseAttr: Attribute<_GraphInputs.Phase>!

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let stack = LazyVStack(spacing: 0) {
                    LazyFixedItemView()
                    LazyFixedItemView()
                }
                let source = graph.makeInput(value: stack)
                var inputs = makeViewInputs(graph: graph)
                inputs.size = graph.makeInput(value: ViewSize(width: 20, height: 20))
                inputs.preferences.keys.add(ScrollablePreferenceKey.self)
                phaseAttr = inputs.base.phase

                let outputs = type(of: stack)._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                let layoutComputer = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                _ = layoutComputer.sizeThatFits(_ProposedSize(CGSize(width: 20, height: 20)))
                scrollablesID = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            }
        }

        host.flushTransactions()

        try host.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let scrollable = try XCTUnwrap(
                scrollables.compactMap { $0 as? LazyScrollable<LazyVStackLayout> }.first
            )
            let cache = try XCTUnwrap(scrollable.cache)

            cache.lru.transactionSeed = 44
            cache.commitSeed = 33
            cache.placementSeed = 34

            var phase = phaseAttr.value
            phase.resetSeed = 2
            phaseAttr.setValue(phase)
            host.data.rootSubgraph.update(flags: AGAttributeFlags.transactional.rawValue)

            // Reset publishes generation 1; the dependent placement pass
            // advances the three cache generations to their settled value.
            XCTAssertEqual(cache.lru.transactionSeed, 2)
            XCTAssertEqual(cache.commitSeed, 2)
            XCTAssertEqual(cache.placementSeed, 2)
            XCTAssertEqual(cache.items.count, 2)
        }
    }

    func testLazyStackMakeViewParentPhaseChangeRefreshesConcreteCache() throws {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph
        var scrollablesID: AGAttribute!

        try viewGraph.data.withCurrent {
            try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let graph = viewGraph.data.graph
                let stack = LazyVStack(spacing: 0) {
                    LazyFixedItemView()
                    LazyFixedItemView()
                }
                let source = graph.makeInput(value: stack)
                var inputs = makeViewInputs(graph: graph)
                inputs.base.phase = viewGraph.data._phase
                inputs.size = graph.makeInput(value: ViewSize(width: 20, height: 20))
                inputs.preferences.keys.add(ScrollablePreferenceKey.self)

                let outputs = type(of: stack)._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                let layoutComputer = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                _ = layoutComputer.sizeThatFits(_ProposedSize(CGSize(width: 20, height: 20)))
                scrollablesID = try XCTUnwrap(outputs.preferences.value(for: ScrollablePreferenceKey.self))
            }
        }

        viewGraph.flushTransactions()

        try viewGraph.data.withCurrent {
            let scrollables = Attribute<ScrollablePreferenceKey.Value>(scrollablesID).value
            let scrollable = try XCTUnwrap(
                scrollables.compactMap { $0 as? LazyScrollable<LazyVStackLayout> }.first
            )
            let cache = try XCTUnwrap(scrollable.cache)

            cache.lru.transactionSeed = 144
            cache.commitSeed = 133
            cache.placementSeed = 134

            var oldParentPhase = _GraphInputs.Phase()
            oldParentPhase.resetSeed = 1
            var newParentPhase = _GraphInputs.Phase()
            newParentPhase.resetSeed = 2
            viewGraph.updateGraphPhase(oldParentPhase: oldParentPhase, newParentPhase: newParentPhase)
            viewGraph.data.rootSubgraph.update(flags: AGAttributeFlags.transactional.rawValue)

            XCTAssertEqual(viewGraph.data._phase.value.resetSeed, 1)
            // Reset publishes generation 1; the dependent placement pass
            // advances the three cache generations to their settled value.
            XCTAssertEqual(cache.lru.transactionSeed, 2)
            XCTAssertEqual(cache.commitSeed, 2)
            XCTAssertEqual(cache.placementSeed, 2)
            XCTAssertEqual(cache.items.count, 2)
        }
    }

    private func assertLazyLayout<L: LazyLayout>(_: L) {
    }

    private func assertLazyStack<L: LazyStack>(_ layout: L) {
        assertLazyLayout(layout)
    }

    private func assertLazyHVStack<L: LazyHVStack>(
        _ layout: L,
        baseType: L.Base.Type,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        assertLazyStack(layout)
        XCTAssertTrue(type(of: layout.base) == baseType, file: file, line: line)
    }

    private func assertHVGrid<G: HVGrid>(_ layout: G) {
        assertLazyStack(layout)
    }

    private func assertLazyStackWitnessSurface<L: LazyStack>(
        _ layout: L,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        _ = L.majorAxis
        _ = layout.spacing
        _ = layout.headerAnchor
        _ = layout.footerAnchor

        var minorSize = CGFloat(42)
        let geometry = layout.minorGeometry(updatingSize: &minorSize)
        XCTAssertGreaterThanOrEqual(geometry.count, 0, file: file, line: line)
        XCTAssertEqual(geometry.data, geometry.data, file: file, line: line)
    }

    private final class ViewListEditRecorder {
        var ids: [_ViewList_ID] = []
        var transactionIDs: [TransactionID] = []
        var firstOffsetCallCount = 0
    }

    private struct EditingViewList: ViewList {
        var edit: _ViewList_Edit?
        var recorder: ViewListEditRecorder?
        var sourceIDs: [_ViewList_ID] = []

        func edit(forID id: _ViewList_ID, since: TransactionID) -> _ViewList_Edit? {
            recorder?.ids.append(id)
            recorder?.transactionIDs.append(since)
            return edit
        }

        func firstOffset<A: Hashable>(
            forID id: A,
            style: _ViewList_IteratorStyle
        ) -> Int? {
            recorder?.firstOffsetCallCount += 1
            guard let canonicalID = id as? _ViewList_ID.Canonical else {
                return nil
            }
            return sourceIDs.firstIndex {
                $0.canonicalID == canonicalID
            }
        }
    }

    @discardableResult
    private func commitPlacedSubviews(
        _ placedSubviews: [_LazyLayout_PlacedSubview],
        to cache: LazyLayoutViewCache,
        from previousPlacedSubviews: [_LazyLayout_PlacedSubview] = [],
        wasCancelled: Bool = false,
        containingSize: CGSize = .zero
    ) -> [_LazyLayout_PlacedSubview] {
        var result = placedSubviews
        cache.commitPlacedSubviews(
            from: previousPlacedSubviews,
            to: &result,
            wasCancelled: wasCancelled,
            context: AnyRuleContext(attribute: cache._placedSubviews.identifier),
            containingSize: containingSize
        )
        return result
    }

    private final class PhaseCapturingElements: _ViewList_Elements {
        var capturedPhase: Attribute<_GraphInputs.Phase>?

        var count: Int { 1 }

        @discardableResult
        func makeElements(
            from: inout Int,
            inputs: _ViewInputs,
            indirectMap: IndirectAttributeMap?,
            body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
        ) -> (_ViewOutputs?, Bool) {
            guard from == 0 else {
                from -= 1
                return (nil, true)
            }
            let outputs = body(inputs) { finalInputs in
                self.capturedPhase = finalInputs.base.phase
                return _ViewOutputs()
            }
            return (outputs.0, false)
        }
    }

    private func makeLazyCache(
        host: GraphHost,
        cache existingCache: LazyLayoutViewCache? = nil,
        implicitID: Int = 1,
        reuseIdentifier: Int = 0,
        supportsPrefetching: Bool = false,
        list: (any ViewList)? = nil
    ) -> (
        cache: LazyLayoutViewCache,
        item: LazyLayoutCacheItem,
        state: Attribute<LazyLayoutCacheItem.State>
    ) {
        let graph = host.data.graph
        let listValue: any ViewList = list ?? EmptyViewList()
        let listAttribute = graph.makeInput(value: listValue)
        let cache: LazyLayoutViewCache
        if let existingCache {
            cache = existingCache
        } else {
            let parentSubgraph = AGSubgraph()
            let inputs = makeViewInputs(graph: graph)
            if supportsPrefetching {
                cache = PrefetchCapableLazyLayoutViewCache(
                    viewGraph: host,
                    parentSubgraph: parentSubgraph,
                    inputs: inputs,
                    outputs: _ViewOutputs(),
                    list: listAttribute,
                    layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                    nearestScrollableAxes: graph.makeInput(value: Axis.Set()),
                    placedSubviews: graph.makeInput(value: []),
                    prefetchSignal: graph.makeInput(value: ()),
                    scrollPosition: OptionalAttribute(),
                    accessibilityEnabled: graph.makeInput(value: false)
                )
            } else {
                cache = TestingLazyLayoutViewCache(
                    viewGraph: host,
                    parentSubgraph: parentSubgraph,
                    inputs: inputs,
                    outputs: _ViewOutputs(),
                    list: listAttribute,
                    layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                    nearestScrollableAxes: graph.makeInput(value: Axis.Set()),
                    placedSubviews: graph.makeInput(value: []),
                    prefetchSignal: graph.makeInput(value: ()),
                    scrollPosition: OptionalAttribute(),
                    accessibilityEnabled: graph.makeInput(value: false)
                )
            }
        }

        let itemSubgraph = AGSubgraph()
        let state = graph.makeInput(value: LazyLayoutCacheItem.State())
        let item = LazyLayoutCacheItem(
            cache: cache,
            subgraph: itemSubgraph,
            outputs: _ViewOutputs(),
            state: state,
            list: OptionalAttribute(listAttribute),
            elements: _ViewList_SubgraphElements(base: EmptyViewListElements()),
            elementIndex: 0,
            id: _ViewList_ID(implicitID: implicitID),
            reuseIdentifier: reuseIdentifier
        )
        cache.addItem(item)
        return (cache, item, state)
    }

    private func makeLazyData(
        graph: _AGGraph,
        id: _ViewList_ID,
        traits: ViewTraitCollection = ViewTraitCollection(),
        section: LazyLayoutCacheSection = LazyLayoutCacheSection(),
        elements: _ViewList_SubgraphElements? = nil,
        list: (any ViewList)? = nil
    ) -> _LazyLayout_Subview.Data {
        let listValue: any ViewList = list ?? EmptyViewList()
        return _LazyLayout_Subview.Data(
            elements: elements ?? _ViewList_SubgraphElements(
                base: CountingViewListElements(count: max(id.index + 1, 1))
            ),
            id: id,
            traits: traits,
            list: graph.makeInput(value: listValue),
            section: section
        )
    }

    private func makeLazyVStackPrefetcher(
        graph: _AGGraph,
        state: Attribute<ScrollPrefetchState>,
        cache: LazyLayoutViewCache,
        size: ViewSize = .zero,
        transform: ViewTransform = ViewTransform()
    ) -> LazySubviewPrefetcher<LazyVStackLayout> {
        LazySubviewPrefetcher(
            layout: graph.makeInput(value: LazyVStackLayout(
                base: _VStackLayout(),
                pinnedViews: []
            )),
            size: graph.makeInput(value: size),
            position: graph.makeInput(value: CGPoint.zero),
            transform: graph.makeInput(value: transform),
            environment: graph.makeInput(value: EnvironmentValues()),
            prefetchState: state,
            cache: graph.makeInput(value: cache),
            containerSize: OptionalAttribute()
        )
    }

    private func makeLazyHStackPrefetcher(
        graph: _AGGraph,
        state: Attribute<ScrollPrefetchState>,
        cache: LazyLayoutViewCache,
        size: ViewSize = .zero,
        transform: ViewTransform = ViewTransform()
    ) -> LazySubviewPrefetcher<LazyHStackLayout> {
        LazySubviewPrefetcher(
            layout: graph.makeInput(value: LazyHStackLayout(
                base: _HStackLayout(),
                pinnedViews: []
            )),
            size: graph.makeInput(value: size),
            position: graph.makeInput(value: CGPoint.zero),
            transform: graph.makeInput(value: transform),
            environment: graph.makeInput(value: EnvironmentValues()),
            prefetchState: state,
            cache: graph.makeInput(value: cache),
            containerSize: OptionalAttribute()
        )
    }

    private func makeLazyVGridPrefetcher(
        graph: _AGGraph,
        state: Attribute<ScrollPrefetchState>,
        cache: LazyLayoutViewCache,
        size: ViewSize = .zero,
        transform: ViewTransform = ViewTransform()
    ) -> LazySubviewPrefetcher<LazyVGridLayout> {
        LazySubviewPrefetcher(
            layout: graph.makeInput(value: LazyVGridLayout(
                columns: [GridItem(.fixed(12))],
                alignment: .center,
                spacing: nil,
                pinnedViews: []
            )),
            size: graph.makeInput(value: size),
            position: graph.makeInput(value: CGPoint.zero),
            transform: graph.makeInput(value: transform),
            environment: graph.makeInput(value: EnvironmentValues()),
            prefetchState: state,
            cache: graph.makeInput(value: cache),
            containerSize: OptionalAttribute()
        )
    }

    private func makeLazyHGridPrefetcher(
        graph: _AGGraph,
        state: Attribute<ScrollPrefetchState>,
        cache: LazyLayoutViewCache,
        size: ViewSize = .zero,
        transform: ViewTransform = ViewTransform()
    ) -> LazySubviewPrefetcher<LazyHGridLayout> {
        LazySubviewPrefetcher(
            layout: graph.makeInput(value: LazyHGridLayout(
                rows: [GridItem(.fixed(12))],
                alignment: .center,
                spacing: nil,
                pinnedViews: []
            )),
            size: graph.makeInput(value: size),
            position: graph.makeInput(value: CGPoint.zero),
            transform: graph.makeInput(value: transform),
            environment: graph.makeInput(value: EnvironmentValues()),
            prefetchState: state,
            cache: graph.makeInput(value: cache),
            containerSize: OptionalAttribute()
        )
    }

    private func makeConcreteLazyGridCache<LayoutType: LazyStack>(
        host: GraphHost,
        layout: LayoutType,
        nearestScrollableAxes: Axis.Set
    ) -> _LazyLayoutViewCache<LayoutType>
    where LayoutType.Cache == _LazyStack_Cache<LayoutType> {
        let graph = host.data.graph
        return _LazyLayoutViewCache(
            layout: graph.makeInput(value: layout),
            cacheState: LayoutType.initialCache,
            viewGraph: host,
            parentSubgraph: AGSubgraph(),
            inputs: makeViewInputs(graph: graph),
            outputs: _ViewOutputs(),
            list: graph.makeInput(value: EmptyViewList() as any ViewList),
            layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
            nearestScrollableAxes: graph.makeInput(value: nearestScrollableAxes),
            placedSubviews: graph.makeInput(value: []),
            prefetchSignal: graph.makeInput(value: ()),
            scrollPosition: OptionalAttribute(),
            accessibilityEnabled: graph.makeInput(value: false)
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(.zero)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func makeViewListInputs(graph: _AGGraph) -> _ViewListInputs {
        _ViewListInputs(from: makeViewInputs(graph: graph))
    }

    private func flattenedLazyLayoutNodes(
        in subviews: _LazyLayout_Subviews
    ) -> [_LazyLayout_Subviews.Node] {
        var result: [_LazyLayout_Subviews.Node] = []

        func visit(_ subviews: _LazyLayout_Subviews) {
            var from = 0
            _ = subviews.applyNodes(from: &from) { _, node, _ in
                switch node {
                case .section:
                    result.append(node)
                case .subviews(let child):
                    if case .sublist = child.node {
                        result.append(node)
                    } else {
                        visit(child)
                    }
                }
            }
        }

        visit(subviews)
        return result
    }

    private func lazyLayoutSections(
        in subviews: _LazyLayout_Subviews
    ) -> [_LazyLayout_Section] {
        flattenedLazyLayoutNodes(in: subviews).compactMap { node in
            guard case .section(let section) = node else {
                return nil
            }
            return section
        }
    }

    private func materializeAllItems(
        in listAttribute: Attribute<any ViewList>
    ) {
        var from = 0
        _ = listAttribute.value.applyNodes(
            from: &from,
            style: _ViewList_IteratorStyle(),
            list: listAttribute,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, _, _, _ in
            true
        }
    }

    private func materializeViewList<Root: View>(
        _ root: Root,
        graph: _AGGraph
    ) {
        let rootAttr = graph.makeInput(value: root)
        let outputs = type(of: root)._makeViewList(
            view: _GraphValue(_attribute: rootAttr),
            inputs: makeViewListInputs(graph: graph)
        )

        switch outputs.views {
        case .staticList:
            break
        case .dynamicList(let listAttr, _):
            materializeAllItems(in: listAttr)
        }
    }

}

private final class SectionCollectionRecorder {
    struct RegionCounts: Equatable {
        var header: Int
        var content: Int
        var footer: Int
    }

    var sectionCount = 0
    var regionCounts: [RegionCounts] = []
}

private final class SectionContainerValuesRecorder {
    struct Snapshot: Equatable {
        var section: String
        var header: String
        var content: String
        var footer: String
    }

    var snapshots: [Snapshot] = []
}

private final class SectionIDRecorder {
    struct Snapshot {
        var sectionIDMirrorLabels: [String]
        var sectionIDBase: Any
        var headerID: _ViewList_ID?
        var contentIDs: [_ViewList_ID] = []
        var rowIDMirrorLabels: [String]
        var rowID: _ViewList_ID?
        var footerID: _ViewList_ID?
    }

    var snapshots: [Snapshot] = []
}

private struct LazySectionProbeValueKey: ContainerValueKey {
    static var defaultValue: String { "default" }
}

private struct SectionAccumulatorProbeTraitKey: _ViewTraitKey {
    static var defaultValue: String { "" }
}

private extension ContainerValues {
    var lazySectionProbeValue: String {
        get { self[LazySectionProbeValueKey.self] }
        set { self[LazySectionProbeValueKey.self] = newValue }
    }
}

private final class ViewListOptionsRecorder {
    var options: _ViewListInputs.Options = []
}

private final class SectionListVariadicIDRecorder {
    var ids: [AnyHashable] = []
}

private struct SectionListVariadicIDCaptureRoot: _VariadicView.MultiViewRoot {
    static var _viewListOptions: Int {
        _ViewListInputs.Options.requiresSections.rawValue
    }

    var recorder: SectionListVariadicIDRecorder

    func body(children: _VariadicView.Children) -> SectionListVariadicIDCaptureView {
        SectionListVariadicIDCaptureView(
            recorder: recorder,
            children: children
        )
    }
}

private struct SectionListVariadicIDCaptureView: View, TestPrimitiveView {
    var recorder: SectionListVariadicIDRecorder
    var children: _VariadicView.Children

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        capture.recorder.ids = capture.children.map(\.id)
        return _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }

    typealias Body = Never
}

private struct ViewListOptionsCaptureView: View, TestPrimitiveView {
    var recorder: ViewListOptionsRecorder

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        view._attribute.value.recorder.options = inputs.options
        return _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }

    typealias Body = Never
}

private struct SectionCollectionCaptureView: View, TestPrimitiveView {
    var recorder: SectionCollectionRecorder
    var collection: SectionCollection

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        capture.recorder.sectionCount = capture.collection.count
        capture.recorder.regionCounts = capture.collection.map {
            SectionCollectionRecorder.RegionCounts(
                header: $0.header.count,
                content: $0.content.count,
                footer: $0.footer.count
            )
        }
        return _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }

    typealias Body = Never
}

private struct SectionContainerValuesCaptureView: View, TestPrimitiveView {
    var recorder: SectionContainerValuesRecorder
    var collection: SectionCollection

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        for section in capture.collection {
            capture.recorder.snapshots.append(
                SectionContainerValuesRecorder.Snapshot(
                    section: section.containerValues.lazySectionProbeValue,
                    header: value(in: section.header),
                    content: value(in: section.content),
                    footer: value(in: section.footer)
                )
            )
        }
        return _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }

    private static func value(in subviews: SubviewsCollection) -> String {
        guard !subviews.isEmpty else {
            return "none"
        }
        return subviews[subviews.startIndex].containerValues.lazySectionProbeValue
    }

    typealias Body = Never
}

private struct SectionIDCaptureView: View, TestPrimitiveView {
    var recorder: SectionIDRecorder
    var collection: SectionCollection

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        for section in capture.collection {
            let sectionMirror = Mirror(reflecting: section.id)
            let headerID = firstViewListID(in: section.header)
            let row = section.content.isEmpty ? nil : section.content[section.content.startIndex]
            let rowMirror = row.map { Mirror(reflecting: $0.id) }
            let footerID = firstViewListID(in: section.footer)
            capture.recorder.snapshots.append(
                SectionIDRecorder.Snapshot(
                    sectionIDMirrorLabels: sectionMirror.children.map { $0.label ?? "" },
                    sectionIDBase: section.id.base.base,
                    headerID: headerID,
                    contentIDs: section.content.indices.compactMap {
                        section.content[$0].id.base
                    },
                    rowIDMirrorLabels: rowMirror?.children.map { $0.label ?? "" } ?? [],
                    rowID: row?.id.base,
                    footerID: footerID
                )
            )
        }
        return _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }

    typealias Body = Never

    private static func firstViewListID(in subviews: SubviewsCollection) -> _ViewList_ID? {
        guard !subviews.isEmpty else {
            return nil
        }
        return subviews[subviews.startIndex].id.base
    }
}

private struct SectionConfigurationCaptureView: View, TestPrimitiveView {
    var recorder: SectionCollectionRecorder
    var section: SectionConfiguration

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        capture.recorder.sectionCount += 1
        capture.recorder.regionCounts.append(
            SectionCollectionRecorder.RegionCounts(
                header: capture.section.header.count,
                content: capture.section.content.count,
                footer: capture.section.footer.count
            )
        )
        return _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    typealias Body = Never
}

private struct SectionConfigurationIDCaptureView: View, TestPrimitiveView {
    var recorder: SectionIDRecorder
    var section: SectionConfiguration

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        let sectionMirror = Mirror(reflecting: capture.section.id)
        let headerID = firstViewListID(in: capture.section.header)
        let row = capture.section.content.isEmpty ? nil : capture.section.content[capture.section.content.startIndex]
        let rowMirror = row.map { Mirror(reflecting: $0.id) }
        let footerID = firstViewListID(in: capture.section.footer)
        capture.recorder.snapshots.append(
            SectionIDRecorder.Snapshot(
                sectionIDMirrorLabels: sectionMirror.children.map { $0.label ?? "" },
                sectionIDBase: capture.section.id.base.base,
                headerID: headerID,
                contentIDs: capture.section.content.indices.compactMap {
                    capture.section.content[$0].id.base
                },
                rowIDMirrorLabels: rowMirror?.children.map { $0.label ?? "" } ?? [],
                rowID: row?.id.base,
                footerID: footerID
            )
        )
        return _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }

    typealias Body = Never

    private static func firstViewListID(in subviews: SubviewsCollection) -> _ViewList_ID? {
        guard !subviews.isEmpty else {
            return nil
        }
        return subviews[subviews.startIndex].id.base
    }
}

private struct SectionConfigurationValuesCaptureView: View, TestPrimitiveView {
    var recorder: SectionContainerValuesRecorder
    var section: SectionConfiguration

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        capture.recorder.snapshots.append(
            SectionContainerValuesRecorder.Snapshot(
                section: capture.section.containerValues.lazySectionProbeValue,
                header: value(in: capture.section.header),
                content: value(in: capture.section.content),
                footer: value(in: capture.section.footer)
            )
        )
        return _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    private static func value(in subviews: SubviewsCollection) -> String {
        guard !subviews.isEmpty else {
            return "none"
        }
        return subviews[subviews.startIndex].containerValues.lazySectionProbeValue
    }

    typealias Body = Never
}

private struct LazyContainerOrdinaryPreferenceKey: PreferenceKey {
    static var defaultValue: [String] { [] }

    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

private class TestingLazyLayoutViewCache: LazyLayoutViewCache {
    override class var viewType: Any.Type {
        TestingLazyLayoutViewCache.self
    }

    override func initialPlacement(
        newIndex: Int,
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasInsertedToSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        newPlacedSubviews[newIndex].placement
    }

    override func finalPlacement(
        oldIndex: Int,
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasRemovedFromSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        oldPlacedSubviews[oldIndex].placement
    }
}

private final class PlacementRecordingLazyLayoutViewCache:
    TestingLazyLayoutViewCache {
    var initialResult = _Placement(proposedSize: CGSize.zero)
    var finalResult = _Placement(proposedSize: CGSize.zero)
    var initialCallCount = 0
    var finalCallCount = 0
    var lastWasInsertedToSubviews = false
    var lastWasRemovedFromSubviews = false

    override func initialPlacement(
        newIndex: Int,
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasInsertedToSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        initialCallCount += 1
        lastWasInsertedToSubviews = wasInsertedToSubviews
        return initialResult
    }

    override func finalPlacement(
        oldIndex: Int,
        oldPlacedSubviews: [_LazyLayout_PlacedSubview],
        newPlacedSubviews: [_LazyLayout_PlacedSubview],
        wasRemovedFromSubviews: Bool,
        context: AnyRuleContext
    ) -> _Placement {
        finalCallCount += 1
        lastWasRemovedFromSubviews = wasRemovedFromSubviews
        return finalResult
    }
}

private final class PrefetchCapableLazyLayoutViewCache: TestingLazyLayoutViewCache {
    override var supportsPrefetching: Bool {
        true
    }
}

private struct CountingViewListElements: _ViewList_Elements {
    var count: Int

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        guard from < count else {
            from -= count
            return (nil, true)
        }
        from = 0
        return body(inputs) { _ in _ViewOutputs() }
    }
}

private struct SectionAccumulatorNestedList: ViewList {
    var base: any ViewList
    var attribute: Attribute<any ViewList>

    func count(style: _ViewList_IteratorStyle) -> Int {
        base.count(style: style)
    }

    func estimatedCount(style: _ViewList_IteratorStyle) -> Int {
        base.estimatedCount(style: style)
    }

    var traitKeys: ViewTraitKeys? {
        ViewTraitKeys()
    }

    var viewIDs: _ViewList_ID_Views? {
        base.viewIDs
    }

    func appendViewIDs(
        into accumulator: inout HeterogeneousViewIDsAccumulator
    ) {
        base.appendViewIDs(into: &accumulator)
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (
            inout Int,
            _ViewList_IteratorStyle,
            _ViewList_Node,
            _ViewList_TemporarySublistTransform
        ) -> Bool
    ) -> Bool {
        to(
            &from,
            style,
            .list(base, attribute),
            transform
        )
    }
}

private struct IndexedLayoutViewListElements: _ViewList_Elements {
    var graph: _AGGraph
    var sizes: [CGSize]

    var count: Int {
        sizes.count
    }

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        guard from < sizes.count else {
            from -= sizes.count
            return (nil, true)
        }

        let size = sizes[from]
        from = 0
        return body(inputs) { _ in
            _ViewOutputs(
                layoutComputer: OptionalAttribute(
                    graph.makeInput(value: LayoutComputer.fixed(size))
                )
            )
        }
    }
}

private final class LazyScrollableLookupMarker {
    var value: Int

    init(_ value: Int) {
        self.value = value
    }
}

private final class LazyRecordingScrollable: Scrollable {
    var acceptsTargets: Bool
    var targetRequestCount = 0
    var lastTarget: ScrollTarget?
    var adjustedOffsets: [(CGSize, ContentOffsetAdjustmentReason)] = []
    var firstChildMarker: LazyScrollableLookupMarker?
    var mapFirstChildCallCount = 0

    init(acceptsTargets: Bool) {
        self.acceptsTargets = acceptsTargets
    }

    func scroll<ID>(to id: ID) -> Bool where ID: Hashable {
        false
    }

    func setContentTarget(_ target: @escaping (ScrollGeometry, LayoutDirection) -> ScrollTarget?) -> Bool {
        targetRequestCount += 1
        lastTarget = target(ScrollGeometry(), .leftToRight)
        return acceptsTargets
    }

    var allowsContentOffsetAdjustments: Bool {
        true
    }

    func adjustContentOffset(by offset: CGSize, reason: ContentOffsetAdjustmentReason) -> Bool {
        adjustedOffsets.append((offset, reason))
        return true
    }

    func mapFirstChild<A, B>(ofType type: A.Type, body: (A) -> B) -> B? {
        mapFirstChildCallCount += 1
        if let marker = firstChildMarker as? A {
            return body(marker)
        }
        return nil
    }
}

private struct LazyScrollableTargetRequest<LayoutType: LazyLayout>: StatefulRule {
    typealias Value = Bool

    var scrollable: LazyScrollable<LayoutType>
    var id: _ViewList_ID.Canonical
    var anchor: UnitPoint?

    mutating func updateValue() {
        _AGGraph.setStatefulOutput(scrollable.scroll(toCollectionViewID: id, anchor: anchor))
    }
}

private struct SegmentedLayoutViewList: ViewList {
    var graph: _AGGraph
    var sizes: [CGSize]

    func count(style: _ViewList_IteratorStyle) -> Int {
        sizes.count
    }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        for index in sizes.indices {
            if from > 0 {
                from -= 1
                continue
            }

            let sublist = _ViewList_Sublist(
                start: 0,
                count: 1,
                id: _ViewList_ID(implicitID: index),
                elements: _ViewList_SubgraphElements(
                    base: IndexedLayoutViewListElements(graph: graph, sizes: [sizes[index]])
                ),
                traits: ViewTraitCollection(),
                list: list
            )
            let shouldContinue = to(&from, style, .sublist(sublist), transform)
            from = 0
            if !shouldContinue { return false }
        }
        return true
    }

    var debugDescription: String {
        "SegmentedLayoutViewList(\(sizes.count))"
    }
}

private struct LazySubviewTestLayoutValueKey: LayoutValueKey {
    static let defaultValue = -1
}

private func assertRemovableAttribute<T: RemovableAttribute>(_ type: T.Type) {}
