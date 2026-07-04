import XCTest
@testable import VUI

private final class LazyRootInputRecorder {
    var willRemoveBeforeInvalidation = false
    var retainCompletedUnusedRemovals = false
}

private struct LazyRootInputCaptureView: View, _PrimitiveView {
    var recorder: LazyRootInputRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("LazyRootInputCaptureView._makeView called outside an active _AGGraph context.")
        }
        let recorder = view._attribute.value.recorder
        recorder.willRemoveBeforeInvalidation = inputs.base[DynamicContainerWillRemoveBeforeInvalidation.self]
        recorder.retainCompletedUnusedRemovals = inputs[DynamicContainerRetainCompletedUnusedRemovals.self]

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

    func testResettableLazyLayoutRootInstallsRetainedUnusedOwnershipInputs() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = LazyRootInputRecorder()

        ref.withCurrent {
            let root = ResettableLazyLayoutRoot {
                LazyRootInputCaptureView(recorder: recorder)
            }
            let source = graph.makeInput(value: root)
            _ = ResettableLazyLayoutRoot<LazyRootInputCaptureView>._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            XCTAssertTrue(recorder.willRemoveBeforeInvalidation)
            XCTAssertTrue(recorder.retainCompletedUnusedRemovals)
        }
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
        XCTAssertEqual(LazyHStackLayout._lazyLayoutProperties.axes, .horizontal)
        XCTAssertEqual(LazyVStackLayout._lazyLayoutProperties.axes, .vertical)
        XCTAssertEqual(LazyVGridLayout._lazyLayoutProperties.axes, .vertical)
        XCTAssertEqual(LazyHGridLayout._lazyLayoutProperties.axes, .horizontal)
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
                HVGridGeometry(position: 0, size: 20, anchor: .leading),
                HVGridGeometry(position: 24, size: 35, anchor: .trailing),
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

    func testLazyGridLayoutNilSpacingDefaultsToEightInBothAxes() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func computer(for layout: _LazyGridLayout) -> LayoutComputer {
                let children = Array(repeating: CGSize(width: 10, height: 10), count: 4).map { size in
                    LayoutProxyAttributes(
                        layoutComputer: graph.makeInput(value: LayoutComputer.fixed(size))
                    )
                }
                return LayoutComputer(
                    box: LayoutEngineBox(
                        engine: ViewLayoutEngine(
                            layout: layout,
                            children: children,
                            layoutDirection: .leftToRight
                        )
                    )
                )
            }

            let vLayout = _LazyGridLayout(
                axis: .vertical,
                items: [GridItem(.fixed(10)), GridItem(.fixed(10))],
                horizontalAlignment: .leading,
                verticalAlignment: .top,
                spacing: nil
            )
            let vComputer = computer(for: vLayout)
            let vSize = vComputer.sizeThatFits(.unspecified)
            XCTAssertEqual(vSize, CGSize(width: 28, height: 28))
            let vGeometries = vComputer.childGeometries(
                at: ViewSize(vSize),
                origin: .zero
            )
            XCTAssertEqual(
                vGeometries.map(\.origin),
                [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 18, y: 0),
                    CGPoint(x: 0, y: 18),
                    CGPoint(x: 18, y: 18),
                ]
            )

            let hLayout = _LazyGridLayout(
                axis: .horizontal,
                items: [GridItem(.fixed(10)), GridItem(.fixed(10))],
                horizontalAlignment: .leading,
                verticalAlignment: .top,
                spacing: nil
            )
            let hComputer = computer(for: hLayout)
            let hSize = hComputer.sizeThatFits(.unspecified)
            XCTAssertEqual(hSize, CGSize(width: 28, height: 28))
            let hGeometries = hComputer.childGeometries(
                at: ViewSize(hSize),
                origin: .zero
            )
            XCTAssertEqual(
                hGeometries.map(\.origin),
                [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 0, y: 18),
                    CGPoint(x: 18, y: 0),
                    CGPoint(x: 18, y: 18),
                ]
            )

            let explicitZeroLayout = _LazyGridLayout(
                axis: .vertical,
                items: [GridItem(.fixed(10), spacing: 0), GridItem(.fixed(10))],
                horizontalAlignment: .leading,
                verticalAlignment: .top,
                spacing: 0
            )
            let explicitZeroComputer = computer(for: explicitZeroLayout)
            let explicitZeroSize = explicitZeroComputer.sizeThatFits(.unspecified)
            XCTAssertEqual(explicitZeroSize, CGSize(width: 20, height: 20))
            let explicitZeroGeometries = explicitZeroComputer.childGeometries(
                at: ViewSize(explicitZeroSize),
                origin: .zero
            )
            XCTAssertEqual(
                explicitZeroGeometries.map(\.origin),
                [
                    CGPoint(x: 0, y: 0),
                    CGPoint(x: 10, y: 0),
                    CGPoint(x: 0, y: 10),
                    CGPoint(x: 10, y: 10),
                ]
            )
        }
    }

    func testHVGridLengthAndPlacementUseMinorGeometryTracks() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let (cache, firstItem, _) = makeLazyCache(host: host, implicitID: 1)
            let (_, secondItem, _) = makeLazyCache(host: host, cache: cache, implicitID: 2)
            firstItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
                    sizeThatFits: { proposal in
                        XCTAssertEqual(proposal.width, 30)
                        XCTAssertNil(proposal.height)
                        return CGSize(width: proposal.width ?? 0, height: 40)
                    }
                )))
            )
            secondItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
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

            var placements: [(_LazyLayout_Subview, CGPoint, ProposedViewSize, UnitPoint)] = []
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
                [ProposedViewSize(width: 30, height: 80), ProposedViewSize(width: 50, height: 80)]
            )
            XCTAssertEqual(placements.map(\.3), [.leading, .trailing])

            let hLayout = LazyHGridLayout(
                rows: [GridItem(.fixed(30))],
                alignment: .top,
                spacing: nil,
                pinnedViews: []
            )
            var hPlacements: [(_LazyLayout_Subview, CGPoint, ProposedViewSize, UnitPoint)] = []
            hLayout.place(
                subviews: [subviews[0]],
                length: 70,
                minorGeometry: [HVGridGeometry(position: 12, size: 30, anchor: .top)]
            ) { subview, point, proposal, anchor in
                hPlacements.append((subview, point, proposal, anchor))
            }

            XCTAssertEqual(hPlacements.map(\.0.index), [0])
            XCTAssertEqual(hPlacements.map(\.1), [CGPoint(x: 0, y: 12)])
            XCTAssertEqual(hPlacements.map(\.2), [ProposedViewSize(width: 70, height: 30)])
            XCTAssertEqual(hPlacements.map(\.3), [.top])
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
            committed.commit(to: stateAttribute.asWeak())

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
            XCTAssertEqual(placementContext.layoutDirection, .rightToLeft)
            XCTAssertTrue(placementContext.isAccessibilityEnabled)
            XCTAssertEqual(
                placementContext.unadjustedVisibleRect,
                CGRect(x: 7, y: 11, width: 13, height: 17)
            )
            XCTAssertEqual(
                placementContext.clampedVisibleRect,
                CGRect(x: 7, y: 11, width: 13, height: 17)
            )
            XCTAssertTrue(placementContext.allowsTranslations)

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
            XCTAssertEqual(proposedSizes.subviews[0].proposal, ProposedViewSize(width: 21, height: 22))
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
                estimations: estimations,
                prefetchStride: 3
            )
            XCTAssertEqual(stackCache.minor?.count, 2)
            XCTAssertEqual(stackCache.endIndex, 12)
            XCTAssertEqual(stackCache.placedIndices, 2..<8)
            XCTAssertEqual(stackCache.placedExtent, CGFloat(5)..<CGFloat(40))
            XCTAssertEqual(stackCache.visibleExtent, CGFloat(6)..<CGFloat(30))
            XCTAssertEqual(stackCache.visibleLength, 24)
            XCTAssertEqual(stackCache.containerLength, 120)
            XCTAssertEqual(stackCache.estimations.lengthToCount[12], 2)
            XCTAssertEqual(stackCache.prefetchStride, 3)
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
                layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
                    sizeThatFits: { proposal in
                        XCTAssertEqual(proposal.width, 30)
                        XCTAssertNil(proposal.height)
                        return CGSize(width: proposal.width ?? 0, height: 40)
                    }
                )))
            )
            secondItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
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

            let firstPlacement = try XCTUnwrap(firstItem.placement)
            XCTAssertEqual(
                firstPlacement,
                _Placement(
                    proposedSize: CGSize(width: 30, height: 55),
                    anchoring: .leading,
                    at: CGPoint(x: 0, y: 10)
                )
            )
            let secondPlacement = try XCTUnwrap(secondItem.placement)
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
                let itemPlacement = try XCTUnwrap(item.placement)
                XCTAssertEqual(itemPlacement.proposedSize, CGSize(width: 80, height: 10))
                XCTAssertEqual(itemPlacement.anchor, .topLeading)
            }
            XCTAssertEqual(
                cache.items[_ViewList_ID(implicitID: 0).elementID(at: 0).canonicalID]?.placement?.anchorPosition,
                CGPoint(x: 0, y: 7)
            )
            XCTAssertEqual(
                cache.items[_ViewList_ID(implicitID: 0).elementID(at: 1).canonicalID]?.placement?.anchorPosition,
                CGPoint(x: 0, y: 42)
            )
            XCTAssertEqual(
                cache.items[_ViewList_ID(implicitID: 0).elementID(at: 2).canonicalID]?.placement?.anchorPosition,
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
            XCTAssertEqual(section.header.section, LazyLayoutCacheSection(isHeader: true))
            XCTAssertEqual(section.content.section, LazyLayoutCacheSection())
            XCTAssertEqual(section.footer.section, LazyLayoutCacheSection(isFooter: true))

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
                resolved.item.placement,
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

            var hCache = _LazyStack_Cache<LazyHStackLayout>(prefetchStride: 2)
            let hLayout = LazyHStackLayout(base: _HStackLayout(), pinnedViews: [])
            let hProposed = hLayout.proposeSizes(
                at: 5,
                subviews: subviews,
                context: context,
                cache: &hCache,
                in: ProposedViewSize(width: 90, height: 33)
            )

            let hSubview = try XCTUnwrap(hProposed.subviews.first)
            let hLayoutComputer = try XCTUnwrap(hSubview.item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(hProposed.subviews.count, 1)
            XCTAssertEqual(hSubview.index, 2)
            XCTAssertEqual(hSubview.proposal, ProposedViewSize(width: nil, height: 33))
            XCTAssertEqual(hLayoutComputer.sizeThatFits(.unspecified), sizes[2])
            XCTAssertEqual(
                hSubview.item.placement,
                _Placement(proposedSize: CGSize(width: 10, height: 33))
            )

            var vCache = _LazyStack_Cache<LazyVStackLayout>(prefetchStride: 2)
            let vLayout = LazyVStackLayout(base: _VStackLayout(), pinnedViews: [])
            let vProposed = vLayout.proposeSizes(
                at: 7,
                subviews: subviews,
                context: context,
                cache: &vCache,
                in: ProposedViewSize(width: 44, height: 90)
            )

            let vSubview = try XCTUnwrap(vProposed.subviews.first)
            let vLayoutComputer = try XCTUnwrap(vSubview.item.outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(vProposed.subviews.count, 1)
            XCTAssertEqual(vSubview.index, 3)
            XCTAssertEqual(vSubview.proposal, ProposedViewSize(width: 44, height: nil))
            XCTAssertEqual(vLayoutComputer.sizeThatFits(.unspecified), sizes[3])
            XCTAssertEqual(
                vSubview.item.placement,
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

            var passingCache = _LazyStack_Cache<LazyVStackLayout>(
                visibleLength: 100,
                prefetchStride: 1
            )
            let passing = layout.proposeSizes(
                at: 75,
                subviews: subviews,
                context: context,
                cache: &passingCache,
                in: ProposedViewSize(width: 44, height: 100)
            )
            let passingSubview = try XCTUnwrap(passing.subviews.first)
            XCTAssertEqual(passing.subviews.count, 1)
            XCTAssertEqual(passingSubview.index, 75)
            XCTAssertEqual(passingSubview.proposal, ProposedViewSize(width: 44, height: nil))

            cache.items.removeAll()
            cache.lru.invalidate()

            var blockedCache = _LazyStack_Cache<LazyVStackLayout>(
                visibleLength: 100,
                prefetchStride: 1
            )
            let blocked = layout.proposeSizes(
                at: 76,
                subviews: subviews,
                context: context,
                cache: &blockedCache,
                in: ProposedViewSize(width: 44, height: 100)
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

        item.animationWasRemoved()
        XCTAssertEqual(item.animationCount, 1)
        XCTAssertFalse(host.hasPendingTransactions)

        item.animationWasRemoved()
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
                XCTAssertTrue(rule.isRemoved)
            }

            output.animationListener?.animationWasAdded()
            XCTAssertEqual(item.animationCount, 1)
        }
    }

    func testLazyTransactionCarriesRemovableAttributeMarker() {
        assertRemovableAttribute(LazyTransaction.self)
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
            cache.commitPlacedSubviews([
                _LazyLayout_PlacedSubview(item: first, placement: placement, index: 0),
            ])
            XCTAssertEqual(cache.placementSeed, 1)
            XCTAssertEqual(first.placementSeed, 1)
            XCTAssertEqual(first.commitSeed, 1)
            XCTAssertEqual(first.placement, placement)
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
            cache.commitPlacedSubviews([
                _LazyLayout_PlacedSubview(item: first, placement: firstPlacement, index: 20),
                _LazyLayout_PlacedSubview(item: second, placement: secondPlacement, index: 21),
            ])

            XCTAssertEqual(cache.placementSeed, 1)
            XCTAssertEqual(first.displayIndex, 0)
            XCTAssertEqual(second.displayIndex, 1)
            XCTAssertEqual(first.usedSeed, cache.lru.usedSeed)
            XCTAssertEqual(second.usedSeed, cache.lru.usedSeed)
            XCTAssertEqual(first.commitSeed, cache.placementSeed)
            XCTAssertEqual(second.commitSeed, cache.placementSeed)
            XCTAssertEqual(first.placement, firstPlacement)
            XCTAssertEqual(second.placement, secondPlacement)
            XCTAssertNil(first.pendingPlacement)
            XCTAssertNil(second.pendingPlacement)
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

    func testLazyLayoutViewCacheReuseSkipsPendingRemovalCandidates() {
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

    func testLazyLayoutViewCacheUpdateItemPhaseStampsRemovalTransactionSeedForPendingRemovalCleanup() {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

        let host = GraphHost()
        let (cache, item, state) = host.data.withCurrent {
            makeLazyCache(host: host, supportsPrefetching: true)
        }

        host.data.withCurrent {
            cache.lru.transactionSeed = 30
            cache.lru.maxIdle = 2
            cache.placementSeed = 9
            item.commitSeed = 8
            item.removalTransactionSeed = 1
            item.prefetchPhase = .pendingDisplay
            item.placement = _Placement(proposedSize: CGSize(width: 20, height: 24))
            state.setValue(
                LazyLayoutCacheItem.State(
                    resetDelta: 6,
                    phase: .didDisappear,
                    enableTransitions: true,
                    isRemoved: false
                )
            )

            cache.updateItemPhase(item)

            XCTAssertNil(item.displayIndex)
            XCTAssertNil(item.placement)
            XCTAssertEqual(item.prefetchPhase, .pendingRemoval)
            XCTAssertEqual(item.removalTransactionSeed, 30)
            XCTAssertTrue(state.value.isRemoved)

            cache.lru.transactionSeed = 31
            cache.updatePrefetchPhases()
            XCTAssertEqual(item.prefetchPhase, .pendingRemoval)

            cache.lru.transactionSeed = 33
            cache.updatePrefetchPhases()
            XCTAssertEqual(item.prefetchPhase, .notPrefetching)
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

    func testLazyLayoutViewCachePrefetchCapabilityUsesHookSemanticsAndRendererGate() {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
            Semantics.overrides = Semantics.Overrides(build: .v6, runtime: nil)
            XCTAssertFalse(prefetchCache.supportsViewHierarchyPrefetching)

            Semantics.overrides = Semantics.Overrides()
            prefetchCache.commitSeed = 41
            item.displayIndex = nil
            item.prefetchPhase = .pendingDisplay
            item.beginPrefetching(at: ProposedViewSize(width: 20, height: 30))
            XCTAssertEqual(item.prefetchSeed, 41)
            XCTAssertEqual(item.prefetchPhase, .prefetching)
        }
    }

    func testConcreteLazyLayoutViewCachePrefetchCapabilityUsesParentSubgraphAndAxis() {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
            XCTAssertEqual(proposed.proposal, ProposedViewSize(width: 24, height: 36))
            XCTAssertEqual(proposed.index, 8)
            XCTAssertEqual(item.zIndex, 15)
            XCTAssertEqual(item.placement, _Placement(proposedSize: CGSize(width: 24, height: 36)))

            let placement = _Placement(
                proposedSize: CGSize(width: 40, height: 50),
                anchoring: .center,
                at: CGPoint(x: 3, y: 4)
            )
            let placed = subview.place(at: placement)

            XCTAssertTrue(placed.item === item)
            XCTAssertEqual(placed.placement, placement)
            XCTAssertEqual(placed.index, 8)
            XCTAssertEqual(item.placement, placement)
            XCTAssertTrue(cache.item(for: id.canonicalID) === item)
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
                layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
                    sizeThatFits: { proposal in
                        CGSize(
                            width: proposal.width ?? 100,
                            height: proposal.height ?? 200
                        )
                    },
                    spacing: ViewSpacing(top: 5, leading: 11, bottom: nil, trailing: nil)
                )))
            )
            predecessorItem.outputs = _ViewOutputs(
                layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
                    sizeThatFits: { _ in CGSize(width: 1, height: 2) },
                    spacing: ViewSpacing(top: nil, leading: nil, bottom: 7, trailing: 3)
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
                layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
                    sizeThatFits: { proposal in
                        proposal.replacingUnspecifiedDimensions()
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
                    layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
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
                    layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
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
                    layoutComputer: OptionalAttribute(graph.makeInput(value: LayoutComputer(
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, displayed, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[displayed.id.canonicalID] = LazyLayoutCacheChildren(
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
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

    func testLazyLayoutViewCacheUpdatePrefetchPhasesClearsAgedPendingRemovalState() {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(
                host: host,
                implicitID: 1,
                supportsPrefetching: true
            )
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
            XCTAssertEqual(proposal, ProposedViewSize(width: 72, height: nil))
        }
    }

    func testLazySubviewPrefetcherRetriesOutputHarvestBeforeLayoutDisplay() {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
                .layoutDisplay(layoutDisplayItem, ProposedViewSize(width: 72, height: nil)),
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
                .layoutDisplay(layoutDisplayItem, ProposedViewSize(width: 72, height: nil)),
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
                .layoutDisplay(item, ProposedViewSize(width: 72, height: nil))
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
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
            XCTAssertEqual(proposal, ProposedViewSize(width: 72, height: nil))
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
            XCTAssertEqual(hProposal, ProposedViewSize(width: nil, height: 33))
        }
    }

    func testLazySubviewPrefetcherProducesGridLayoutDisplayProposalPayload() throws {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
            XCTAssertEqual(proposal, ProposedViewSize(width: 72, height: nil))
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
            XCTAssertEqual(hProposal, ProposedViewSize(width: nil, height: 33))
        }
    }

    func testLazySubviewPrefetcherSkipsStackLayoutDisplayBeyondViewportWindow() {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
            XCTAssertEqual(proposal, ProposedViewSize(width: 72, height: nil))
        }
    }

    func testLazySubviewPrefetcherSkipsStackLayoutDisplayForDisjointScrollWindows() {
        let previousSemantics = Semantics.overrides
        Semantics.overrides = Semantics.Overrides()
        defer { Semantics.overrides = previousSemantics }

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
            XCTAssertEqual(proposal, ProposedViewSize(width: 72, height: nil))
        }
    }

    func testLazyLayoutViewCacheChildPrefetchPhaseTracksMaxDisplayListSubviews() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, _) = makeLazyCache(host: host, implicitID: 1)
            let (childCache, _, _) = makeLazyCache(host: host, implicitID: 10)
            cache.childCaches[item.id.canonicalID] = LazyLayoutCacheChildren(
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
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
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
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
                children: [LazyLayoutCacheChildren.WeakChild(value: childCache)]
            )
            cache.childCacheSeeds[oldID.canonicalID] = 7
            cache.lru.transactionSeed = 20
            cache.commitSeed = 21
            candidate.insertionTransactionSeed = 18
            candidate.placementSeed = 10
            candidate.prefetchSeed = 21

            let data = makeLazyData(graph: host.data.graph, id: targetID)
            let returned = cache.item(data: data)

            XCTAssertTrue(returned === candidate)
            XCTAssertNil(cache.childCaches[oldID.canonicalID])
            XCTAssertNil(cache.childCacheSeeds[oldID.canonicalID])
            XCTAssertEqual(cache.childCaches[targetID.canonicalID]?.seed, 7)
            XCTAssertEqual(cache.childCacheSeeds[targetID.canonicalID], 7)
            XCTAssertTrue(cache.childCaches[targetID.canonicalID]?.children.first?.value === childCache)
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
                    body: { _ in
                        makeViewCount += 1
                        return _ViewOutputs(
                            layoutComputer: OptionalAttribute(
                                graph.makeInput(value: LayoutComputer.fixed(CGSize(width: 99, height: 99)))
                            )
                        )
                    },
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
                    body: { _ in
                        makeViewCount += 1
                        observedSubgraph = AGSubgraph.current
                        return _ViewOutputs(
                            layoutComputer: OptionalAttribute(
                                graph.makeInput(value: LayoutComputer.fixed(layoutSize))
                            )
                        )
                    },
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
    }

    private struct EditingViewList: ViewList {
        var edit: _ViewList_Edit?
        var recorder: ViewListEditRecorder?

        func edit(forID id: _ViewList_ID, since: TransactionID) -> _ViewList_Edit? {
            recorder?.ids.append(id)
            recorder?.transactionIDs.append(since)
            return edit
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
                cache = LazyLayoutViewCache(
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
        list: (any ViewList)? = nil
    ) -> _LazyLayout_Subview.Data {
        let listValue: any ViewList = list ?? EmptyViewList()
        return _LazyLayout_Subview.Data(
            elements: _ViewList_SubgraphElements(base: EmptyViewListElements()),
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

    private func makeConcreteLazyGridCache<LayoutType: LazyLayout>(
        host: GraphHost,
        layout: LayoutType,
        nearestScrollableAxes: Axis.Set
    ) -> _LazyLayoutViewCache<LayoutType> where LayoutType.Cache == Void {
        let graph = host.data.graph
        return _LazyLayoutViewCache(
            layout: graph.makeInput(value: layout),
            cacheState: graph.makeInput(value: ()),
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
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
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
}

private struct LazyContainerOrdinaryPreferenceKey: PreferenceKey {
    static var defaultValue: [String] { [] }

    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

private final class PrefetchCapableLazyLayoutViewCache: LazyLayoutViewCache {
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
                elements: IndexedLayoutViewListElements(graph: graph, sizes: [sizes[index]]),
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

private func assertRemovableAttribute<T: RemovableAttribute>(_ type: T.Type) {}
