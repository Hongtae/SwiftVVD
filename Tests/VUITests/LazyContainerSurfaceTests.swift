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
        XCTAssertTrue(LazyVStackLayout.AnimatableData.self == EmptyAnimatableData.self)
        XCTAssertTrue(LazyHStackLayout.AnimatableData.self == EmptyAnimatableData.self)
        XCTAssertTrue(LazyVGridLayout.AnimatableData.self == EmptyAnimatableData.self)
        XCTAssertTrue(LazyHGridLayout.AnimatableData.self == EmptyAnimatableData.self)
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
            first.usedSeed = 20
            second.usedSeed = 10

            XCTAssertTrue(
                cache.reusedItem(
                    for: _ViewList_ID(implicitID: 99).canonicalID,
                    reuseIdentifier: 4,
                    transitionType: nil
                ) === second
            )
            XCTAssertEqual(cache.lru.generationSeed, 1)

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
            candidate.usedSeed = 12
            candidate.prefetchSeed = 4
            candidate.prefetchPhase = .prefetching

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
            XCTAssertEqual(cache.lru.generationSeed, 1)
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

    private func makeLazyCache(
        host: GraphHost,
        cache existingCache: LazyLayoutViewCache? = nil,
        implicitID: Int = 1,
        reuseIdentifier: Int = 0
    ) -> (
        cache: LazyLayoutViewCache,
        item: LazyLayoutCacheItem,
        state: Attribute<LazyLayoutCacheItem.State>
    ) {
        let graph = host.data.graph
        let cache: LazyLayoutViewCache
        if let existingCache {
            cache = existingCache
        } else {
            let parentSubgraph = AGSubgraph()
            let inputs = makeViewInputs(graph: graph)
            cache = LazyLayoutViewCache(
                viewGraph: host,
                parentSubgraph: parentSubgraph,
                inputs: inputs,
                outputs: _ViewOutputs(),
                list: graph.makeInput(value: EmptyViewList() as any ViewList),
                layoutDirection: graph.makeInput(value: LayoutDirection.leftToRight),
                nearestScrollableAxes: graph.makeInput(value: Axis.Set()),
                placedSubviews: graph.makeInput(value: []),
                prefetchSignal: graph.makeInput(value: ()),
                scrollPosition: OptionalAttribute(),
                accessibilityEnabled: graph.makeInput(value: false)
            )
        }

        let itemSubgraph = AGSubgraph()
        let state = graph.makeInput(value: LazyLayoutCacheItem.State())
        let item = LazyLayoutCacheItem(
            cache: cache,
            subgraph: itemSubgraph,
            outputs: _ViewOutputs(),
            state: state,
            list: OptionalAttribute(graph.makeInput(value: EmptyViewList() as any ViewList)),
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
        section: LazyLayoutCacheSection = LazyLayoutCacheSection()
    ) -> _LazyLayout_Subview.Data {
        _LazyLayout_Subview.Data(
            elements: _ViewList_SubgraphElements(base: EmptyViewListElements()),
            id: id,
            traits: traits,
            list: graph.makeInput(value: EmptyViewList() as any ViewList),
            section: section
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
