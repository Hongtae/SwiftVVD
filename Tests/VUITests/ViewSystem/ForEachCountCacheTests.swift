import XCTest
@testable import VUI

final class ForEachCountCacheTests: XCTestCase {
    func testForEachListInitOwnsGenerationAndResetsCountCache() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let root = ForEach([0, 1], id: \.self) { value in
                    Text("\(value)")
                }
                let source = graph.makeInput(value: root)
                let outputs = type(of: root)._makeViewList(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewListInputs(graph: graph)
                )
                guard case .dynamicList(let listAttribute, _) = outputs.views else {
                    return XCTFail("ForEach should publish a dynamic list")
                }

                let first = try XCTUnwrap(
                    listAttribute.value as? ForEachList<[Int], Int, Text>
                )
                XCTAssertEqual(first.seed, 1)
                XCTAssertTrue(
                    listAttribute.identifier._bodyType ==
                        ForEachList<[Int], Int, Text>.Init.self
                )

                first.state.viewCounts = [1, 2]
                first.state.viewCountStyle = _ViewList_IteratorStyle(value: 9)
                let info = try XCTUnwrap(first.state.info)
                info.setValue(
                    ForEachState<[Int], Int, Text>.Info(
                        state: first.state,
                        seed: 99
                    )
                )

                let second = try XCTUnwrap(
                    listAttribute.value as? ForEachList<[Int], Int, Text>
                )
                XCTAssertEqual(second.seed, 2)
                XCTAssertTrue(second.state.viewCounts.isEmpty)
                XCTAssertEqual(second.state.viewCountStyle.value, 2)
            }
        }
    }

    func testUniformUnaryCountMaterializesOnlyFirstItem() throws {
        let root = ForEach([0, 1, 2], id: \.self) { value in
            Text("\(value)")
        }

        try withForEachState(root) { state, list in
            XCTAssertTrue(state.items.isEmpty)
            XCTAssertEqual(list.count(style: _ViewList_IteratorStyle(value: 2)), 3)
            XCTAssertEqual(state.items.count, 1)
            guard case .resolved(1) = state.viewsPerElementCount else {
                return XCTFail("expected a resolved unary count")
            }
            XCTAssertTrue(state.viewCounts.isEmpty)
            XCTAssertFalse(state.createdAllItems)

            var from = 0
            var visited = 0
            _ = list.applyNodes(
                from: &from,
                style: _ViewList_IteratorStyle(value: 2),
                list: nil,
                transform: _ViewList_TemporarySublistTransform()
            ) { _, _, _, _ in
                visited += 1
                return true
            }
            XCTAssertEqual(visited, 3)
            XCTAssertEqual(state.items.count, 3)
            XCTAssertFalse(state.createdAllItems)
        }
    }

    func testUniformMultiViewCountUsesResolvedProduct() throws {
        let root = ForEach([0, 1, 2], id: \.self) { value in
            Text("\(value)-a")
            Text("\(value)-b")
        }

        try withForEachState(root) { state, list in
            XCTAssertEqual(list.count(style: _ViewList_IteratorStyle(value: 2)), 6)
            XCTAssertEqual(state.items.count, 1)
            guard case .resolved(2) = state.viewsPerElementCount else {
                return XCTFail("expected a resolved two-view count")
            }
            XCTAssertTrue(state.viewCounts.isEmpty)
            XCTAssertFalse(state.createdAllItems)
        }
    }

    func testHeterogeneousCountCachesCumulativeCounts() throws {
        let root = ForEach([0, 1], id: \.self) { value in
            if value == 0 {
                Text("single")
            } else {
                TupleView((Text("first"), Text("second")))
            }
        }

        try withForEachState(root) { state, list in
            XCTAssertEqual(list.count(style: _ViewList_IteratorStyle(value: 2)), 3)
            XCTAssertEqual(state.items.count, 2)
            guard case .indeterminate = state.viewsPerElementCount else {
                return XCTFail("expected an indeterminate per-element count")
            }
            XCTAssertEqual(state.viewCounts, [1, 3])
            XCTAssertEqual(state.viewCountStyle, _ViewList_IteratorStyle(value: 2))
            XCTAssertTrue(state.createdAllItems)
        }
    }

    func testHeterogeneousReconciliationCarriesLastOffsetBoundary() throws {
        let root = ForEach([0, 1, 2], id: \.self) { value in
            if value == 1 {
                Text("first")
                Text("second")
            } else {
                Text("\(value)")
            }
        }

        try withForEachState(root) { state, list in
            let style = _ViewList_IteratorStyle(value: 2)
            XCTAssertEqual(list.count(style: style), 4)
            XCTAssertTrue(state.createdAllItems)

            let reordered = ForEach([2, 0, 1], id: \.self) { value in
                if value == 1 {
                    Text("first")
                    Text("second")
                } else {
                    Text("\(value)")
                }
            }
            state.update(view: reordered)
            publishCurrentInfo(for: state)
            XCTAssertEqual(state.firstInsertionOffset, 2)
            XCTAssertFalse(state.createdAllItems)

            XCTAssertEqual(state.count(style: style), 4)
            let inserted = ForEach([2, 3, 0, 1], id: \.self) { value in
                if value == 1 {
                    Text("first")
                    Text("second")
                } else {
                    Text("\(value)")
                }
            }
            state.update(view: inserted)
            publishCurrentInfo(for: state)
            XCTAssertEqual(state.firstInsertionOffset, 3)

            XCTAssertEqual(state.count(style: style), 5)
            let empty = ForEach([Int](), id: \.self) { value in
                if value == 1 {
                    Text("first")
                    Text("second")
                } else {
                    Text("\(value)")
                }
            }
            state.update(view: empty)
            publishCurrentInfo(for: state)
            XCTAssertEqual(state.firstInsertionOffset, 0)
            XCTAssertFalse(state.createdAllItems)
        }
    }

    func testHeterogeneousAppendClassifiesNewTailWhenItIsMaterialized() throws {
        let root = ForEach([0, 1, 2], id: \.self) { value in
            if value == 1 {
                Text("first")
                Text("second")
            } else {
                Text("\(value)")
            }
        }

        try withForEachState(root) { state, list in
            let style = _ViewList_IteratorStyle(value: 2)
            XCTAssertEqual(list.count(style: style), 4)
            XCTAssertTrue(state.createdAllItems)

            let appended = ForEach([0, 1, 2, 3], id: \.self) { value in
                if value == 1 {
                    Text("first")
                    Text("second")
                } else {
                    Text("\(value)")
                }
            }
            state.update(view: appended)
            publishCurrentInfo(for: state)

            XCTAssertEqual(state.firstInsertionOffset, 2)
            guard case .builder(var beforeCount) = state.edits else {
                return XCTFail("append should preserve lazy edit storage")
            }
            XCTAssertTrue(beforeCount.insertOffsets.finalize().isEmpty)
            XCTAssertTrue(beforeCount.edits.inserts.isEmpty)

            XCTAssertEqual(state.count(style: style), 5)
            guard case .builder(let afterCount) = state.edits else {
                return XCTFail("materialization should not finalize edit storage")
            }
            XCTAssertEqual(afterCount.edits.inserts, [3])
            XCTAssertNotNil(state.items[3])
        }
    }

    func testHeterogeneousRefreshClassifiesRecreatedEvictedTailItems() throws {
        let root = ForEach([0, 1, 2], id: \.self) { value in
            if value == 0 {
                Text("first")
                Text("second")
            } else {
                Text("\(value)")
            }
        }

        try withForEachState(root) { state, list in
            let style = _ViewList_IteratorStyle(value: 2)
            XCTAssertEqual(list.count(style: style), 4)
            XCTAssertTrue(state.createdAllItems)

            state.items[1]?.timeToLive = 1
            state.items[2]?.timeToLive = 1
            state.evictItems(seed: 1)
            XCTAssertEqual(Set(state.items.keys), [0])
            XCTAssertEqual(state.evictedIDs, [1, 2])

            let refreshed = ForEach([0, 1, 2], id: \.self) { value in
                if value == 0 {
                    Text("refreshed-first")
                    Text("refreshed-second")
                } else {
                    Text("refreshed-\(value)")
                }
            }
            state.update(view: refreshed)
            publishCurrentInfo(for: state)
            XCTAssertEqual(state.firstInsertionOffset, 0)

            XCTAssertEqual(state.count(style: style), 4)
            XCTAssertEqual(Set(state.items.keys), [0, 1, 2])
            XCTAssertTrue(state.evictedIDs.isEmpty)
            guard case .builder(let edits) = state.edits else {
                return XCTFail("recreated tail edits should remain lazy")
            }
            XCTAssertEqual(edits.edits.inserts, [1, 2])
            var pending = edits.insertOffsets
            XCTAssertTrue(pending.finalize().isEmpty)
        }
    }

    func testReconciliationDoesNotRefreshItemTTLUntilVisit() throws {
        let root = ForEach([0, 1], id: \.self) { value in
            Text("\(value)")
        }

        try withForEachState(root) { state, list in
            XCTAssertEqual(list.count(style: _ViewList_IteratorStyle(value: 2)), 2)
            let item = try XCTUnwrap(state.items[0])
            item.timeToLive = 5

            let reordered = ForEach([1, 0], id: \.self) { value in
                Text("\(value)")
            }
            state.update(view: reordered)
            XCTAssertEqual(item.timeToLive, 5)
            XCTAssertEqual(item.offset, 1)

            _ = state.item(at: reordered.data.index(after: reordered.data.startIndex), offset: 1)
            XCTAssertEqual(item.timeToLive, 8)
        }
    }

    func testRetainedRemovedItemReattachesOnlyWhenReinsertedRowIsVisited() throws {
        let root = ForEach(["A", "B", "C"], id: \.self) { value in
            Text(value)
        }

        try withForEachState(root) { state, _ in
            let bIndex = root.data.index(after: root.data.startIndex)
            let item = state.item(at: bIndex, offset: 1)
            item.refcount += 1

            let removed = ForEach(["A", "C"], id: \.self) { value in
                Text(value)
            }
            state.update(view: removed)
            XCTAssertTrue(item.isRemoved)
            XCTAssertEqual(item.timeToLive, 0)
            XCTAssertEqual(item.refcount, 1)
            XCTAssertTrue(AGSubgraphIsValid(item.subgraph))

            let reinserted = ForEach(["A", "B", "C"], id: \.self) { value in
                Text(value)
            }
            state.update(view: reinserted)
            XCTAssertTrue(item.isRemoved)
            XCTAssertEqual(item.seed, state.seed)
            guard case .builder(var beforeVisit) = state.edits else {
                return XCTFail("reinsertion should preserve lazy edit storage")
            }
            XCTAssertEqual(beforeVisit.insertOffsets.finalize(), IndexSet(integer: 1))
            XCTAssertTrue(beforeVisit.edits.inserts.isEmpty)

            _ = state.item(at: bIndex, offset: 1)
            XCTAssertFalse(item.isRemoved)
            XCTAssertEqual(item.timeToLive, 8)
            XCTAssertEqual(item.refcount, 2)
            XCTAssertTrue(item.subgraph.isInserted)
        }
    }

    func testUniformUnaryViewIDsBindEveryElementWithoutMaterializingAllItems() throws {
        let root = ForEach([10, 20, 30], id: \.self) { value in
            Text("\(value)")
        }

        try withForEachState(root) { state, list in
            let ids = try XCTUnwrap(list.viewIDs)
            let owner = try XCTUnwrap(state.list).identifier

            XCTAssertTrue(ids.isDataDependent)
            XCTAssertEqual(ids.count, 3)
            XCTAssertEqual(
                ids.map { (id: _ViewList_ID) -> Int? in
                    id.explicitID(owner: owner)
                },
                [10, 20, 30]
            )
            XCTAssertEqual(state.items.count, 1)
            XCTAssertFalse(state.createdAllItems)
        }
    }

    func testUniformMultiViewIDsRepeatElementIdentityAcrossBaseViews() throws {
        let root = ForEach([10, 20], id: \.self) { value in
            Text("\(value)-a")
            Text("\(value)-b")
        }

        try withForEachState(root) { state, list in
            let ids = try XCTUnwrap(list.viewIDs)
            let owner = try XCTUnwrap(state.list).identifier

            XCTAssertEqual(ids.count, 4)
            XCTAssertEqual(
                ids.map { (id: _ViewList_ID) -> Int? in
                    id.explicitID(owner: owner)
                },
                [10, 10, 20, 20]
            )
            XCTAssertEqual(ids.map(\.index), [0, 1, 0, 1])
            XCTAssertEqual(state.items.count, 1)
        }
    }

    func testUnaryAppendViewIDsUsesOneConcreteIDCollection() throws {
        let root = ForEach([10, 20, 30], id: \.self) { value in
            Text("\(value)")
        }

        try withForEachState(root) { state, list in
            var accumulator = HeterogeneousViewIDsAccumulator()
            list.appendViewIDs(into: &accumulator)
            let ids = accumulator.finalize()

            XCTAssertEqual(ids.collection.subCollections.count, 1)
            XCTAssertEqual(
                ids.collection.subCollections[0].elementTypeID,
                ObjectIdentifier(Int.self)
            )
            XCTAssertEqual(ids.asCanonical().map(\.explicitID), [10, 20, 30])
            XCTAssertEqual(state.items.count, 1)
        }
    }

    func testMultiViewAppendViewIDsUsesOneTypedCanonicalCollection() throws {
        let root = ForEach([10, 20], id: \.self) { value in
            Text("\(value)-a")
            Text("\(value)-b")
        }

        try withForEachState(root) { state, list in
            var accumulator = HeterogeneousViewIDsAccumulator()
            list.appendViewIDs(into: &accumulator)
            let ids = accumulator.finalize()

            XCTAssertEqual(ids.collection.subCollections.count, 1)
            XCTAssertEqual(
                ids.collection.subCollections[0].elementTypeID,
                ObjectIdentifier(TypedCanonicalViewID<Int>.self)
            )
            XCTAssertEqual(ids.asCanonical().map(\._index), [0, 1, 0, 1])
            XCTAssertEqual(ids.asCanonical().map(\.implicitID), [0, 0, 0, 0])
            XCTAssertEqual(ids.asCanonical().map(\.explicitID), [10, 10, 20, 20])
            XCTAssertEqual(state.items.count, 1)
        }
    }

    func testConstantAppendViewIDsRetainsSpecializedOwnerScopedCarriers() throws {
        let unary = ForEach(4..<7) { value in
            Text("\(value)")
        }

        try withForEachState(unary) { _, list in
            var accumulator = HeterogeneousViewIDsAccumulator()
            list.appendViewIDs(into: &accumulator)
            let ids = accumulator.finalize()

            XCTAssertEqual(ids.collection.subCollections.count, 1)
            XCTAssertEqual(
                ids.collection.subCollections[0].elementTypeID,
                ObjectIdentifier(ForEachConstantID.self)
            )
            XCTAssertEqual(
                ids.asCanonical().compactMap {
                    ($0.explicitID?.base as? ForEachConstantID)?.offset
                },
                [0, 1, 2]
            )
        }

        let multiple = ForEach(4..<6) { value in
            Text("\(value)-a")
            Text("\(value)-b")
        }

        try withForEachState(multiple) { _, list in
            var accumulator = HeterogeneousViewIDsAccumulator()
            list.appendViewIDs(into: &accumulator)
            let ids = accumulator.finalize()

            XCTAssertEqual(ids.collection.subCollections.count, 1)
            XCTAssertEqual(
                ids.collection.subCollections[0].elementTypeID,
                ObjectIdentifier(
                    TypedCanonicalViewID<ForEachConstantID>.self
                )
            )
            XCTAssertEqual(ids.asCanonical().map(\._index), [0, 1, 0, 1])
            XCTAssertEqual(
                ids.asCanonical().compactMap {
                    ($0.explicitID?.base as? ForEachConstantID)?.offset
                },
                [0, 0, 1, 1]
            )
        }
    }

    func testDynamicChildCountAppendViewIDsPreservesNestedCanonicalIDs() throws {
        let root = ForEach([10, 20], id: \.self) { value in
            if value == 10 {
                Text("single")
            } else {
                TupleView((Text("first"), Text("second")))
            }
        }

        try withForEachState(root) { state, list in
            var accumulator = HeterogeneousViewIDsAccumulator()
            list.appendViewIDs(into: &accumulator)
            let ids = accumulator.finalize().asCanonical()
            let explicitIDs = ids.compactMap {
                $0.explicitID?.base as? UniqueID
            }

            XCTAssertEqual(ids.map(\._index), [0, 0, 1])
            XCTAssertEqual(ids.map(\.implicitID), [-1, -1, -1])
            XCTAssertEqual(explicitIDs.count, 3)
            XCTAssertNotEqual(explicitIDs[0], explicitIDs[1])
            XCTAssertEqual(explicitIDs[1], explicitIDs[2])
            XCTAssertEqual(state.items.count, 2)
            XCTAssertFalse(state.createdAllItems)
        }
    }

    func testConstantRangeViewIDsBindPrivateOffsetsButFirstOffsetMatchesPublicID() throws {
        let root = ForEach(4..<7) { value in
            Text("\(value)")
        }

        try withForEachState(root) { state, list in
            let ids = try XCTUnwrap(list.viewIDs)
            let owner = try XCTUnwrap(state.list).identifier
            let boundOffsets = ids.map { id -> Int? in
                let constantID: ForEachConstantID? = id.explicitID(owner: owner)
                return constantID?.offset
            }

            XCTAssertEqual(boundOffsets, [0, 1, 2])
            XCTAssertEqual(
                list.firstOffset(
                    forID: 1,
                    style: _ViewList_IteratorStyle(value: 2)
                ),
                1
            )
            XCTAssertEqual(state.items.count, 2)
            guard case .some(.exact) =
                    state.matchingStrategyCache[ObjectIdentifier(Int.self)] else {
                return XCTFail("expected exact Int ID matching")
            }
        }
    }

    func testFirstOffsetFindsOuterAndNestedIDsWithHeterogeneousCounts() throws {
        let root = ForEach([10, 20], id: \.self) { value in
            if value == 10 {
                Text("single")
            } else {
                TupleView((
                    Text("first").id("nested"),
                    Text("second")
                ))
            }
        }

        try withForEachState(root) { state, list in
            let style = _ViewList_IteratorStyle(value: 2)

            XCTAssertNil(list.viewIDs)
            XCTAssertEqual(list.firstOffset(forID: 20, style: style), 1)
            XCTAssertEqual(list.firstOffset(forID: "nested", style: style), 1)
            XCTAssertEqual(state.items.count, 2)
            guard case .some(.noMatch) =
                    state.matchingStrategyCache[ObjectIdentifier(String.self)] else {
                return XCTFail("expected nested lookup after an outer ID type mismatch")
            }
        }
    }

    func testFirstOffsetMatchesAnyHashableElementIDs() throws {
        let values: [AnyHashable] = ["first", 20, "third"]
        let root = ForEach(values, id: \.self) { value in
            Text("\(value)")
        }

        try withForEachState(root) { state, list in
            XCTAssertEqual(
                list.firstOffset(
                    forID: 20,
                    style: _ViewList_IteratorStyle(value: 2)
                ),
                1
            )
            guard case .some(.anyHashable) =
                    state.matchingStrategyCache[ObjectIdentifier(Int.self)] else {
                return XCTFail("expected AnyHashable element ID matching")
            }
        }
    }

    func testFirstOffsetMatchesCustomIDRepresentation() throws {
        let values = [
            CompositeID(primary: 10, alias: "first"),
            CompositeID(primary: 20, alias: "second")
        ]
        let root = ForEach(values, id: \.self) { value in
            Text(value.alias)
        }

        try withForEachState(root) { state, list in
            XCTAssertEqual(
                list.firstOffset(
                    forID: "second",
                    style: _ViewList_IteratorStyle(value: 2)
                ),
                1
            )
            guard case .some(.customIDRepresentation) =
                    state.matchingStrategyCache[ObjectIdentifier(String.self)] else {
                return XCTFail("expected custom element ID matching")
            }
        }
    }

    func testDuplicateIDReusesFirstItemAndPublishesItsTraits() throws {
        let rows = [
            DuplicateForEachRow(id: 1, label: "first"),
            DuplicateForEachRow(id: 1, label: "duplicate"),
            DuplicateForEachRow(id: 2, label: "last"),
        ]
        let root = ForEach(rows) { row in
            Text(row.label)
        }

        try withForEachState(root) { state, list in
            let traits = transformedTraits(in: list)
            XCTAssertEqual(traits.count, 3)
            XCTAssertEqual(
                traits.map { $0[DynamicViewContentIDTraitKey.self] },
                [state.contentID, state.contentID, state.contentID]
            )
            XCTAssertEqual(
                traits.map { $0[DynamicViewContentOffsetTraitKey.self] },
                [0, 0, 2]
            )
            XCTAssertEqual(traits.compactMap(taggedInt), [1, 1, 2])

            XCTAssertEqual(state.items.count, 2)
            let duplicate = try XCTUnwrap(state.items[1])
            XCTAssertEqual(duplicate.index, rows.startIndex)
            XCTAssertEqual(duplicate.offset, 0)
            XCTAssertTrue(duplicate.hasWarned)
            XCTAssertEqual(state.items[2]?.offset, 2)
        }
    }

    func testConstantRangePublishesOffsetTraitsAndDoesNotReplaceChildTag() throws {
        let constant = ForEach(3..<6) { value in
            Text("\(value)")
        }

        try withForEachState(constant) { _, list in
            let traits = transformedTraits(in: list)
            XCTAssertEqual(
                traits.map { $0[DynamicViewContentOffsetTraitKey.self] },
                [0, 1, 2]
            )
            XCTAssertEqual(traits.compactMap(taggedInt), [0, 1, 2])
        }

        let explicitlyTagged = ForEach([1], id: \.self) { value in
            Text("\(value)").tag(99)
        }
        try withForEachState(explicitlyTagged) { _, list in
            let traits = transformedTraits(in: list)
            XCTAssertEqual(traits.compactMap(taggedInt), [99])
        }
    }

    func testCurrentItemEditFallsBackToNestedDynamicList() throws {
        let root = ForEach([10], id: \.self) { value in
            Text("\(value)")
        }

        try withForEachStateAndHost(root) { state, _, host in
            let item = state.item(at: root.data.startIndex, offset: 0)
            let nested: Attribute<any ViewList> = host.data.graph.makeInput(
                value: NestedEditViewList(result: .removed) as any ViewList
            )
            item.views = .dynamicList(nested, nil)

            var id = _ViewList_ID(implicitID: 0)
            item.bindID(&id, isUnary: true, isConstant: false)
            let transaction = TransactionID()
            XCTAssertLessThan(transaction, state.lastTransaction)
            XCTAssertEqual(
                state.edit(forID: id, since: transaction),
                .removed
            )
        }
    }

    func testLazyEditsRecordsKnownIdentityWithoutFinalizingPendingOffsets() {
        typealias State = ForEachState<[Int], Int, Text>

        var raw = State.LazyEdits.raw(State.Edits())
        raw.appendInsert(id: 90)
        guard case .raw(let rawEdits) = raw else {
            return XCTFail("raw edits should remain raw")
        }
        XCTAssertEqual(rawEdits.inserts, [90])

        let root = ForEach([10, 20], id: \.self) { value in
            Text("\(value)")
        }
        var builder = State.EditsBuilder(
            data: root.data,
            idGenerator: root.idGenerator
        )
        builder.appendInsert(atOffset: 1)
        var lazy = State.LazyEdits.builder(builder)

        lazy.appendInsert(id: 90)
        guard case .builder(var retainedBuilder) = lazy else {
            return XCTFail("known identity insertion should preserve the builder")
        }
        XCTAssertEqual(retainedBuilder.edits.inserts, [90])
        XCTAssertEqual(retainedBuilder.insertOffsets.finalize(), IndexSet(integer: 1))

        let finalized = lazy.finalized()
        XCTAssertEqual(finalized.inserts, [20, 90])
    }

    func testConstantRangeRetainsInitialDataWhileRefreshingContent() throws {
        let root = ForEach(5..<8) { value in
            ConstantRangeProbeContent(token: "initial-\(value)")
        }

        try withForEachState(root) { state, _ in
            let shifted = ForEach(6..<9) { value in
                ConstantRangeProbeContent(token: "shifted-\(value)")
            }
            state.update(view: shifted)
            XCTAssertEqual(state.view?.data, 5..<8)
            XCTAssertEqual(state.view?.content(5).token, "shifted-5")

            let resized = ForEach(6..<10) { value in
                ConstantRangeProbeContent(token: "resized-\(value)")
            }
            state.update(view: resized)
            XCTAssertEqual(state.view?.data, 5..<8)
            XCTAssertEqual(state.view?.content(7).token, "resized-7")
            guard case .builder(var edits) = state.edits else {
                return XCTFail("constant range should keep a lazy edit builder")
            }
            XCTAssertTrue(edits.insertOffsets.finalize().isEmpty)
            XCTAssertTrue(edits.edits.removes.isEmpty)
        }
    }

    func testDefaultEvictorAgesOnlyItemsNotVisitedInTheCurrentUpdate() throws {
        let root = ForEach([0, 1], id: \.self) { value in
            Text("\(value)")
        }

        try withForEachStateAndHost(root) { state, list, host in
            XCTAssertEqual(list.count(style: _ViewList_IteratorStyle(value: 2)), 2)
            let first = try XCTUnwrap(state.items[0])
            XCTAssertEqual(first.timeToLive, 8)
            XCTAssertTrue(state.pendingEviction)

            advanceUpdate(host)
            XCTAssertEqual(first.timeToLive, 7)
            XCTAssertEqual(state.evictionSeed, 1)
            XCTAssertFalse(state.pendingEviction)

            let secondIndex = root.data.index(after: root.data.startIndex)
            for expectedFirstTTL in stride(from: Int8(6), through: 1, by: -1) {
                _ = state.item(at: secondIndex, offset: 1)
                advanceUpdate(host)
                XCTAssertEqual(first.timeToLive, expectedFirstTTL)
                XCTAssertEqual(state.items[1]?.timeToLive, 7)
                XCTAssertFalse(state.pendingEviction)
            }

            _ = state.item(at: secondIndex, offset: 1)
            advanceUpdate(host)
            XCTAssertNil(state.items[0])
            XCTAssertTrue(state.evictedIDs.contains(0))
            XCTAssertEqual(first.refcount, 0)
            XCTAssertFalse(AGSubgraphIsValid(first.subgraph))

            _ = state.item(at: root.data.startIndex, offset: 0)
            advanceUpdate(host)
            XCTAssertNotNil(state.items[0])
            XCTAssertFalse(state.evictedIDs.contains(0))
        }
    }

    func testEvictorHonorsExplicitDisabledInput() throws {
        let root = ForEach([0], id: \.self) { value in
            Text("\(value)")
        }

        try withForEachStateAndHost(
            root,
            evictionEnabled: false
        ) { state, list, host in
            XCTAssertEqual(list.count(style: _ViewList_IteratorStyle(value: 2)), 1)
            let item = try XCTUnwrap(state.items[0])

            advanceUpdate(host)
            XCTAssertEqual(item.timeToLive, 8)
            XCTAssertEqual(state.evictionSeed, 0)
            XCTAssertTrue(state.pendingEviction)

            let enabled = state.inputs.base[ForEachEvictionInput.self].toStrong()
            enabled.setValue(true)
            host.data.rootSubgraph.update(flags: 1)
            XCTAssertEqual(item.timeToLive, 7)
            XCTAssertEqual(state.evictionSeed, 1)
            XCTAssertFalse(state.pendingEviction)
        }
    }

    func testEvictionPassIsBoundedToSixtyFourExpiredItems() throws {
        let root = ForEach(Array(0..<65), id: \.self) { value in
            Text("\(value)")
        }

        try withForEachState(root) { state, _ in
            for offset in root.data.indices {
                let item = state.item(at: offset, offset: offset)
                item.timeToLive = 1
            }
            XCTAssertEqual(state.items.count, 65)

            state.evictItems(seed: 1)
            XCTAssertEqual(state.items.count, 1)
            XCTAssertEqual(state.evictedIDs.count, 64)
            XCTAssertTrue(state.pendingEviction)

            state.evictItems(seed: 2)
            XCTAssertTrue(state.items.isEmpty)
            XCTAssertEqual(state.evictedIDs.count, 65)
            XCTAssertFalse(state.pendingEviction)
        }
    }

    private func withForEachState<Data, ID, Content>(
        _ root: ForEach<Data, ID, Content>,
        body: (
            ForEachState<Data, ID, Content>,
            any ViewList
        ) throws -> Void
    ) throws where Data: RandomAccessCollection, ID: Hashable, Content: View {
        try withForEachStateAndHost(root) { state, list, _ in
            try body(state, list)
        }
    }

    private func withForEachStateAndHost<Data, ID, Content>(
        _ root: ForEach<Data, ID, Content>,
        evictionEnabled: Bool? = nil,
        body: (
            ForEachState<Data, ID, Content>,
            any ViewList,
            GraphHost
        ) throws -> Void
    ) throws where Data: RandomAccessCollection, ID: Hashable, Content: View {
        let host = GraphHost()
        let graph = host.data.graph

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let source = graph.makeInput(value: root)
                let inputs = makeViewListInputs(
                    graph: graph,
                    evictionEnabled: evictionEnabled
                )
                let outputs = type(of: root)._makeViewList(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                guard case .dynamicList(let listAttribute, _) = outputs.views else {
                    return XCTFail("ForEach should publish a dynamic list")
                }
                let list = listAttribute.value
                let typedList = try XCTUnwrap(
                    list as? ForEachList<Data, ID, Content>
                )
                try body(typedList.state, list, host)
            }
        }
    }

    private func advanceUpdate(_ host: GraphHost) {
        host.data.updateSeed &+= 1
        host.data.rootSubgraph.update(flags: 1)
    }

    private func publishCurrentInfo<Data, ID, Content>(
        for state: ForEachState<Data, ID, Content>
    ) where Data: RandomAccessCollection, ID: Hashable, Content: View {
        state.info?.setValue(
            ForEachState<Data, ID, Content>.Info(
                state: state,
                seed: state.seed
            )
        )
    }

    private func transformedTraits(in list: any ViewList) -> [ViewTraitCollection] {
        var result: [ViewTraitCollection] = []
        var from = 0
        _ = list.applyNodes(
            from: &from,
            style: _ViewList_IteratorStyle(value: 2),
            list: nil,
            transform: _ViewList_TemporarySublistTransform()
        ) { _, _, node, transform in
            guard case .sublist(var sublist) = node else {
                return true
            }
            transform.apply(to: &sublist)
            result.append(sublist.traits)
            return true
        }
        return result
    }

    private func taggedInt(_ traits: ViewTraitCollection) -> Int? {
        guard case .tagged(let value) = traits[TagValueTraitKey<Int>.self] else {
            return nil
        }
        return value
    }

    private func makeViewListInputs(
        graph: _AGGraph,
        evictionEnabled: Bool? = nil
    ) -> _ViewListInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        var base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        )
        if let evictionEnabled {
            base[ForEachEvictionInput.self] = WeakAttribute(
                graph.makeInput(value: evictionEnabled)
            )
        }
        let viewInputs = _ViewInputs(
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
        return _ViewListInputs(from: viewInputs)
    }
}

private struct DuplicateForEachRow: Identifiable {
    var id: Int
    var label: String
}

private struct ConstantRangeProbeContent: View {
    var token: String

    var body: some View {
        Text(token)
    }
}

private struct NestedEditViewList: ViewList {
    var result: _ViewList_Edit

    func edit(
        forID id: _ViewList_ID,
        since transaction: TransactionID
    ) -> _ViewList_Edit? {
        result
    }
}

private struct CompositeID: Hashable, HasCustomIDRepresentation {
    var primary: Int
    var alias: String

    func containsID<ID: Hashable>(_ id: ID) -> Bool {
        if let primary = id as? Int {
            return self.primary == primary
        }
        if let alias = id as? String {
            return self.alias == alias
        }
        return false
    }
}
