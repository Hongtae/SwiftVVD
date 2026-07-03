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
            ]
            XCTAssertEqual(namespaceValues.count, 12)
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
            cache.commitSeed = 20
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
            cache.commitSeed = 20
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
            cache.commitSeed = 20
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
            cache.commitSeed = 20
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
            cache.commitSeed = 20
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

            let outputs = cache.prefetchOutputs()

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
            cache.commitSeed = 20
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
            XCTAssertEqual(cache.lru.generationSeed, 1)
        }
    }

    func testLazyLayoutViewCacheAddItemMarksFreshCandidateWithCommitSeed() {
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
            cache.commitSeed = 20
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

    func testLazyLayoutViewCacheAddItemResetRefreshesStateForReuse() {
        let host = GraphHost()

        host.data.withCurrent {
            let (cache, item, state) = makeLazyCache(host: host)
            cache.commitSeed = 8
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
                    phase: .identity,
                    enableTransitions: true,
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
            cache.commitSeed = 20
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
            cache.commitSeed = 20
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
            cache.commitSeed = 20
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
            cache.commitSeed = 20
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

private struct LazyContainerOrdinaryPreferenceKey: PreferenceKey {
    static var defaultValue: [String] { [] }

    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}

private func assertRemovableAttribute<T: RemovableAttribute>(_ type: T.Type) {}
