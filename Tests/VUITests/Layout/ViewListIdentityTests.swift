import XCTest
@testable import VUI

final class ViewListIdentityTests: XCTestCase {
    func testSExpPrinterMatchesObservedMultilineAndSingleLineFormatting() {
        // ASSERTIONS sExpPrinterFormattingObserved
        var multiline = SExpPrinter(tag: "root")
        multiline.print("value")
        multiline.push("child")
        multiline.print("leaf", newline: false)
        multiline.newline()
        multiline.print("tail", newline: false)
        multiline.pop()

        XCTAssertEqual(
            multiline.end(),
            "(root\n  value\n  (child leaf\n     tail))"
        )
        XCTAssertEqual(multiline.depth, 0)
        XCTAssertEqual(multiline.indent, "")

        var singleLine = SExpPrinter(tag: "root", singleLine: true)
        singleLine.print("value")
        singleLine.push("child")
        singleLine.print("leaf")
        singleLine.pop()

        XCTAssertEqual(singleLine.end(), "(root value(child leaf))")
        XCTAssertEqual(singleLine.depth, 0)
        XCTAssertEqual(singleLine.indent, "")
    }

    func testSubviewIDStoresFullViewListIDAndForwardsTypedLookup() {
        var base = _ViewList_ID(implicitID: 3)
        base.bind(
            explicitID: "row",
            owner: .invalid,
            isUnary: true,
            reuseID: 17
        )
        base.bind(
            explicitID: 42,
            owner: .invalid,
            isUnary: false,
            reuseID: 18
        )

        let id = Subview.ID(base)

        XCTAssertEqual(id.base, base)
        XCTAssertTrue(id.containsID("row"))
        XCTAssertTrue(id.containsID(42))
        XCTAssertFalse(id.containsID("missing"))
        XCTAssertTrue(Mirror(reflecting: id).children.first?.value is _ViewList_ID)
    }

    func testViewListIDElementIDReplacesIndexAndPreservesIdentityLanes() {
        let base = _ViewList_ID(explicitID: AnyHashable("row"), implicitID: 42)

        let element = base.elementID(at: 7)

        XCTAssertEqual(element._index, 7)
        XCTAssertEqual(element.implicitID, base.implicitID)
        XCTAssertEqual(element.explicitIDs, base.explicitIDs)
        XCTAssertEqual(element.canonicalID._index, 7)
        XCTAssertEqual(element.canonicalID.implicitID, 42)
        XCTAssertEqual(element.canonicalID.explicitID, AnyHashable("row"))
    }

    func testViewListIDCanonicalUsesFirstExplicitIDAndUnarySentinel() {
        var id = _ViewList_ID(implicitID: 5)
        id.explicitIDs = [
            _ViewList_ID.Explicit(id: AnyHashable("first"), reuseID: 11, isUnary: true),
            _ViewList_ID.Explicit(id: AnyHashable("second"), reuseID: 22, isUnary: false),
        ]

        let canonical = id.canonicalID

        XCTAssertEqual(canonical._index, 5)
        XCTAssertEqual(canonical.implicitID, -1)
        XCTAssertEqual(canonical.explicitID, AnyHashable("first"))
        XCTAssertFalse(canonical.requiresImplicitID)
    }

    func testViewListIDCanonicalPreservesImplicitIDForNonUnaryExplicitID() {
        var id = _ViewList_ID(implicitID: 6)
        id.explicitIDs = [
            _ViewList_ID.Explicit(id: AnyHashable("first"), reuseID: 11, isUnary: false),
            _ViewList_ID.Explicit(id: AnyHashable("second"), reuseID: 22, isUnary: true),
        ]

        let canonical = id.canonicalID

        XCTAssertEqual(canonical._index, 6)
        XCTAssertEqual(canonical.implicitID, 6)
        XCTAssertEqual(canonical.explicitID, AnyHashable("first"))
        XCTAssertTrue(canonical.requiresImplicitID)
    }

    func testViewListIDReuseIdentifierIgnoresExplicitMetadataLanes() {
        var first = _ViewList_ID(implicitID: 3)
        first.explicitIDs = [
            _ViewList_ID.Explicit(id: AnyHashable("row"), reuseID: 1, isUnary: false),
        ]
        var second = _ViewList_ID(implicitID: 3)
        second.explicitIDs = [
            _ViewList_ID.Explicit(id: AnyHashable("row"), reuseID: 9, isUnary: true),
        ]

        XCTAssertEqual(first.reuseIdentifier, second.reuseIdentifier)
    }

    func testViewListIDStaticExplicitCreatesUnaryCanonicalID() {
        let id = _ViewList_ID.explicit("row")

        XCTAssertEqual(id._index, 0)
        XCTAssertEqual(id.implicitID, 0)
        XCTAssertEqual(id.explicitIDs.count, 1)
        XCTAssertEqual(id.explicitIDs[0].id, AnyHashable("row"))
        XCTAssertEqual(id.explicitIDs[0].reuseID, 0)
        XCTAssertNil(id.explicitIDs[0].owner)
        XCTAssertTrue(id.explicitIDs[0].isUnary)
        XCTAssertEqual(id.primaryExplicitID, AnyHashable("row"))
        XCTAssertEqual(id.canonicalID._index, 0)
        XCTAssertEqual(id.canonicalID.implicitID, -1)
        XCTAssertEqual(id.canonicalID.explicitID, AnyHashable("row"))
    }

    func testViewListIDBindStoresMetadataAndLookupUsesTypeAndOwner() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let firstOwner = graph.makeInput(value: "first").identifier
            let secondOwner = graph.makeInput(value: "second").identifier
            var id = _ViewList_ID(implicitID: 2)

            id.bind(explicitID: "first", owner: firstOwner, isUnary: false, reuseID: 17)
            id.bind(explicitID: 42, owner: secondOwner, isUnary: true, reuseID: 23)

            XCTAssertEqual(id.explicitIDs.count, 2)
            XCTAssertEqual(id.explicitIDs[0].id, AnyHashable("first"))
            XCTAssertEqual(id.explicitIDs[0].owner?.rawValue, firstOwner.rawValue)
            XCTAssertEqual(id.explicitIDs[0].reuseID, 17)
            XCTAssertFalse(id.explicitIDs[0].isUnary)
            XCTAssertEqual(id.explicitIDs[1].id, AnyHashable(42))
            XCTAssertEqual(id.explicitIDs[1].owner?.rawValue, secondOwner.rawValue)
            XCTAssertEqual(id.explicitIDs[1].reuseID, 23)
            XCTAssertTrue(id.explicitIDs[1].isUnary)

            let typedString: String? = id.explicitID(for: String.self)
            let typedInt: Int? = id.explicitID(for: Int.self)
            let ownerString: String? = id.explicitID(owner: firstOwner)
            let ownerInt: Int? = id.explicitID(owner: secondOwner)
            let wrongOwner: Int? = id.explicitID(owner: firstOwner)

            XCTAssertEqual(typedString, "first")
            XCTAssertEqual(typedInt, 42)
            XCTAssertEqual(ownerString, "first")
            XCTAssertEqual(ownerInt, 42)
            XCTAssertNil(wrongOwner)
            XCTAssertTrue(id.containsID("first"))
            XCTAssertTrue(id.containsID(42))
            XCTAssertFalse(id.containsID("missing"))
        }
    }

    func testViewListIDExplicitEqualityIncludesMetadataButHashIgnoresOwnerAndUnary() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let firstOwner = graph.makeInput(value: "first").identifier
            let secondOwner = graph.makeInput(value: "second").identifier
            var first = _ViewList_ID(implicitID: 1)
            first.bind(explicitID: "row", owner: firstOwner, isUnary: false, reuseID: 7)
            var second = _ViewList_ID(implicitID: 1)
            second.bind(explicitID: "row", owner: secondOwner, isUnary: true, reuseID: 7)
            var third = _ViewList_ID(implicitID: 1)
            third.bind(explicitID: "row", owner: firstOwner, isUnary: false, reuseID: 8)

            XCTAssertNotEqual(first, second)
            XCTAssertNotEqual(first, third)
            XCTAssertEqual(first.hashValue, second.hashValue)
            XCTAssertNotEqual(first.hashValue, third.hashValue)
        }
    }

    func testViewListIDElementCollectionCopiesBaseAndUsesDirectElementIndex() {
        let base = _ViewList_ID(explicitID: AnyHashable("row"), implicitID: 8)

        let collection = base.elementIDs(count: 3)

        XCTAssertEqual(collection.startIndex, 0)
        XCTAssertEqual(collection.endIndex, 3)
        XCTAssertEqual(collection.count, 3)
        XCTAssertEqual(collection.id, base)
        XCTAssertEqual(collection[2]._index, 2)
        XCTAssertEqual(collection[2].implicitID, 8)
        XCTAssertEqual(collection[2].explicitIDs, base.explicitIDs)
    }

    func testBaseViewListApplyIDsUsesStoredImplicitID() {
        let list = BaseViewList(
            elements: FixedCountViewListElements(count: 2),
            implicitID: 7
        )
        var index = 0
        var ids: [_ViewList_ID] = []

        let completed = list.applyIDs(from: &index) { id in
            ids.append(id)
            return true
        }

        XCTAssertTrue(completed)
        XCTAssertEqual(ids.map(\.index), [0, 1])
        XCTAssertEqual(ids.map(\.implicitID), [7, 7])
        XCTAssertEqual(ids.map(\.canonicalID._index), [0, 1])
        XCTAssertEqual(ids.map(\.canonicalID.implicitID), [7, 7])
    }

    func testViewListCanonicalFirstOffsetFallsBackToTransformedSublists() {
        let list = BaseViewList(
            elements: FixedCountViewListElements(count: 4),
            implicitID: 7
        )
        let target = _ViewList_ID(implicitID: 7).elementID(at: 2).canonicalID

        XCTAssertEqual(list.firstOffset(of: target), 2)
        XCTAssertNil(
            list.firstOffset(
                of: _ViewList_ID.Canonical(
                    _index: 2,
                    implicitID: 8,
                    explicitID: nil
                )
            )
        )
    }

    func testViewListCanonicalFirstOffsetUsesPublishedViewIDs() {
        let ids = _ViewList_ID._Views(
            ContiguousArray([
                _ViewList_ID(explicitID: AnyHashable("first"), implicitID: 4),
                _ViewList_ID(explicitID: AnyHashable("second"), implicitID: 9),
            ]),
            isDataDependent: true
        )
        let list = CanonicalIDsOnlyViewList(ids: ids)

        XCTAssertEqual(list.firstOffset(of: ids[1].canonicalID), 1)
        XCTAssertNil(
            list.firstOffset(
                of: _ViewList_ID.Canonical(
                    _index: 9,
                    implicitID: -1,
                    explicitID: AnyHashable("missing")
                )
            )
        )
    }

    func testBaseViewListAppendViewIDsUsesStoredImplicitLane() {
        let list = BaseViewList(
            elements: FixedCountViewListElements(count: 2),
            implicitID: 7
        )
        var accumulator = HeterogeneousViewIDsAccumulator()

        list.appendViewIDs(into: &accumulator)
        let ids = accumulator.finalize().asCanonical()

        XCTAssertEqual(ids.map(\._index), [0, 1])
        XCTAssertEqual(ids.map(\.implicitID), [7, 7])
        XCTAssertEqual(ids.map(\.explicitID), [nil, nil])
    }

    func testSublistAppendViewIDsUsesStoredUpperBoundAndUnarySentinel() {
        let elements = _ViewList_SubgraphElements(
            base: FixedCountViewListElements(count: 2)
        )
        let explicit = _ViewList_Sublist(
            start: 1,
            count: 3,
            id: _ViewList_ID(explicitID: AnyHashable("row"), implicitID: 41),
            elements: elements,
            traits: ViewTraitCollection(),
            list: nil
        )
        var explicitAccumulator = HeterogeneousViewIDsAccumulator()

        explicit.appendViewIDs(into: &explicitAccumulator)
        let explicitIDs = explicitAccumulator.finalize().asCanonical()

        XCTAssertEqual(explicitIDs.map(\._index), [1, 2])
        XCTAssertEqual(explicitIDs.map(\.implicitID), [-1, -1])
        XCTAssertEqual(explicitIDs.map(\.explicitID), [
            AnyHashable("row"),
            AnyHashable("row"),
        ])

        let generated = _ViewList_Sublist(
            start: 1,
            count: 3,
            id: _ViewList_ID(implicitID: 41),
            elements: elements,
            traits: ViewTraitCollection(),
            list: nil
        )
        var generatedAccumulator = HeterogeneousViewIDsAccumulator()

        generated.appendViewIDs(into: &generatedAccumulator)
        let generatedIDs = generatedAccumulator.finalize().asCanonical()

        XCTAssertEqual(generatedIDs.map(\._index), [1, 2])
        XCTAssertEqual(generatedIDs.map(\.implicitID), [-1, -1])
        XCTAssertEqual(generatedIDs.map(\.explicitID), [nil, nil])
    }

    func testViewListGroupAppendViewIDsForwardsStoredListsInOrder() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let first: Attribute<any ViewList> = graph.makeInput(
                value: BaseViewList(
                    elements: FixedCountViewListElements(count: 2),
                    implicitID: 7
                ) as any ViewList
            )
            let second: Attribute<any ViewList> = graph.makeInput(
                value: BaseViewList(
                    elements: FixedCountViewListElements(count: 1),
                    implicitID: 9
                ) as any ViewList
            )
            let group = _ViewList_Group(lists: [
                (first.value, first),
                (second.value, second),
            ])
            var accumulator = HeterogeneousViewIDsAccumulator()

            group.appendViewIDs(into: &accumulator)
            let ids = accumulator.finalize().asCanonical()

            XCTAssertEqual(ids.map(\._index), [0, 1, 0])
            XCTAssertEqual(ids.map(\.implicitID), [7, 7, 9])
        }
    }

    func testViewListSectionAppendViewIDsSelectsHierarchicalLeadingRegion() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func region(count: Int, implicitID: Int) -> (
                list: any ViewList,
                attribute: Attribute<any ViewList>
            ) {
                let attribute: Attribute<any ViewList> = graph.makeInput(
                    value: BaseViewList(
                        elements: FixedCountViewListElements(count: count),
                        implicitID: implicitID
                    ) as any ViewList
                )
                return (attribute.value, attribute)
            }

            let base = _ViewList_Group(lists: [
                region(count: 1, implicitID: 10),
                region(count: 2, implicitID: 20),
                region(count: 1, implicitID: 30),
            ])
            var flatAccumulator = HeterogeneousViewIDsAccumulator()
            _ViewList_Section(base: base).appendViewIDs(into: &flatAccumulator)
            let flatIDs = flatAccumulator.finalize().asCanonical()

            XCTAssertEqual(flatIDs.map(\._index), [0, 0, 1, 0])
            XCTAssertEqual(flatIDs.map(\.implicitID), [10, 20, 20, 30])

            var hierarchicalAccumulator = HeterogeneousViewIDsAccumulator()
            _ViewList_Section(
                base: base,
                isHierarchical: true
            ).appendViewIDs(into: &hierarchicalAccumulator)
            let hierarchicalIDs = hierarchicalAccumulator.finalize().asCanonical()

            XCTAssertEqual(hierarchicalIDs.map(\._index), [0])
            XCTAssertEqual(hierarchicalIDs.map(\.implicitID), [10])
        }
    }

    func testViewListSectionApplyNodesAlignsOffsetsAndUsesRegionStyles() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            func region() -> (
                list: any ViewList,
                attribute: Attribute<any ViewList>
            ) {
                let attribute: Attribute<any ViewList> = graph.makeInput(
                    value: BaseViewList(
                        elements: FixedCountViewListElements(count: 1)
                    ) as any ViewList
                )
                return (attribute.value, attribute)
            }

            let section = _ViewList_Section(
                id: 42,
                base: _ViewList_Group(lists: [
                    region(),
                    region(),
                    region(),
                ])
            )
            var from = 5
            var starts: [Int] = []
            var styles: [UInt] = []
            var ids: [UInt32] = []
            var headerFlags: [Bool] = []
            var footerFlags: [Bool] = []

            let completed = section.applyNodes(
                from: &from,
                style: _ViewList_IteratorStyle(value: 6),
                transform: _ViewList_TemporarySublistTransform()
            ) { nodeFrom, style, node, info, _ in
                guard case .sublist = node else {
                    return false
                }
                starts.append(nodeFrom)
                styles.append(style.value)
                ids.append(info.id)
                headerFlags.append(info.isHeader)
                footerFlags.append(info.isFooter)
                return true
            }

            XCTAssertTrue(completed)
            XCTAssertEqual(from, 0)
            XCTAssertEqual(starts, [3, 0, 0])
            XCTAssertEqual(styles, [7, 6, 7])
            XCTAssertEqual(ids, [42, 42, 42])
            XCTAssertEqual(headerFlags, [true, false, false])
            XCTAssertEqual(footerFlags, [false, false, true])

            var hierarchicalFrom = 0
            var hierarchicalRegions = 0
            XCTAssertTrue(
                _ViewList_Section(
                    id: 42,
                    base: section.base,
                    isHierarchical: true
                ).applyNodes(
                    from: &hierarchicalFrom,
                    style: _ViewList_IteratorStyle(value: 2),
                    transform: _ViewList_TemporarySublistTransform()
                ) { _, _, _, _, _ in
                    hierarchicalRegions += 1
                    return true
                }
            )
            XCTAssertEqual(hierarchicalRegions, 1)
        }
    }

    func testViewListNodeApplySublistsScalesSkipAndResetsVisitedOffset() {
        let sublist = _ViewList_Sublist(
            start: 0,
            count: 2,
            id: _ViewList_ID(implicitID: 4),
            elements: _ViewList_SubgraphElements(
                base: FixedCountViewListElements(count: 2)
            ),
            traits: ViewTraitCollection(),
            list: nil
        )
        let node = _ViewList_Node.sublist(sublist)
        let transform = _ViewList_TemporarySublistTransform()
            .withPushedItem(ApplyingIDTransformItem(id: "section"))

        var skippedFrom = 4
        var skippedCallbacks = 0
        XCTAssertTrue(
            node.applySublists(
                from: &skippedFrom,
                style: _ViewList_IteratorStyle(value: 5),
                transform: transform
            ) { _ in
                skippedCallbacks += 1
                return true
            }
        )
        XCTAssertEqual(skippedFrom, 0)
        XCTAssertEqual(skippedCallbacks, 0)

        var visitedFrom = 3
        var visitedIDs: [[AnyHashable]] = []
        XCTAssertTrue(
            node.applySublists(
                from: &visitedFrom,
                style: _ViewList_IteratorStyle(value: 5),
                transform: transform
            ) { transformed in
                visitedIDs.append(transformed.id.allExplicitIDs)
                return true
            }
        )
        XCTAssertEqual(visitedFrom, 0)
        XCTAssertEqual(visitedIDs, [[AnyHashable("section")]])
    }

    func testForEachSublistDefaultUsesCollectionIteratorStyle() {
        let log = IteratorStyleLog()
        let list = IteratorStyleRecordingViewList(log: log)
        var counts: [Int] = []

        XCTAssertTrue(
            _forEachSublist(in: list) { sublist in
                counts.append(sublist.count)
                return true
            }
        )

        XCTAssertEqual(log.values, [2])
        XCTAssertEqual(counts, [1])
    }

    func testViewListGroupForwardsSiblingIdentityWithoutAddingEntryIDs() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let first: Attribute<any ViewList> = graph.makeInput(
                value: BaseViewList(elements: FixedCountViewListElements(count: 1)) as any ViewList
            )
            let second: Attribute<any ViewList> = graph.makeInput(
                value: BaseViewList(elements: FixedCountViewListElements(count: 1)) as any ViewList
            )
            let group = _ViewList_Group(lists: [
                (first.value, first),
                (second.value, second),
            ])
            var index = 0
            var ids: [_ViewList_ID] = []

            let completed = group.applyIDs(from: &index) { id in
                ids.append(id)
                return true
            }

            XCTAssertTrue(completed)
            XCTAssertEqual(ids.count, 2)
            XCTAssertEqual(ids[0].canonicalID, ids[1].canonicalID)
            XCTAssertTrue(ids[0].allExplicitIDs.isEmpty)
            XCTAssertTrue(ids[1].allExplicitIDs.isEmpty)
        }
    }

    func testViewListGroupPreservesExistingExplicitIdentityAsPrimary() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let rowList: Attribute<any ViewList> = graph.makeInput(
                value: ExplicitSingleViewList(explicitID: AnyHashable("row")) as any ViewList
            )
            let group = _ViewList_Group(lists: [
                (rowList.value, rowList),
            ])
            var index = 0
            var ids: [_ViewList_ID] = []

            let completed = group.applyIDs(from: &index) { id in
                ids.append(id)
                return true
            }

            XCTAssertTrue(completed)
            XCTAssertEqual(ids.count, 1)
            XCTAssertEqual(ids[0].canonicalID.explicitID, AnyHashable("row"))
            XCTAssertEqual(ids[0].allExplicitIDs, [AnyHashable("row")])
        }
    }

    func testSublistTransformAppliesBindIDAndWrapSubgraphsInReverseItemOrder() {
        let log = TransformCallLog()
        var transform = _ViewList_SublistTransform()
        transform.push(RecordingTransformItem(name: "first", log: log))
        transform.push(RecordingTransformItem(name: "second", log: log))

        var id = _ViewList_ID(implicitID: 0)
        transform.bindID(&id)

        XCTAssertEqual(log.events, ["bind:second", "bind:first"])
        XCTAssertEqual(id.allExplicitIDs, [AnyHashable("second"), AnyHashable("first")])

        log.events.removeAll()
        var sublist = _ViewList_Sublist(
            start: 0,
            count: 0,
            id: _ViewList_ID(implicitID: 0),
            elements: _ViewList_SubgraphElements(base: EmptyViewListElements()),
            traits: ViewTraitCollection(),
            list: nil
        )
        transform.apply(to: &sublist)

        XCTAssertEqual(log.events, ["apply:second", "apply:first"])

        log.events.removeAll()
        var storage = _ViewList_SublistSubgraphStorage()
        transform.wrapSubgraphs(into: &storage)

        XCTAssertEqual(log.events, ["wrap:second", "wrap:first"])
        XCTAssertFalse(transform.isEmpty)
    }

    func testTemporarySublistTransformScopesPushedItemsAndCopiesToPermanentTransform() {
        let log = TransformCallLog()
        let base = _ViewList_TemporarySublistTransform()
        let first = base.withPushedItem(RecordingTransformItem(name: "first", log: log))
        let second = first.withPushedItem(RecordingTransformItem(name: "second", log: log))

        var baseID = _ViewList_ID(implicitID: 0)
        base.bindID(&baseID)
        XCTAssertTrue(log.events.isEmpty)
        XCTAssertTrue(base.isEmpty)

        var firstID = _ViewList_ID(implicitID: 0)
        first.bindID(&firstID)
        XCTAssertEqual(log.events, ["bind:first"])
        XCTAssertEqual(firstID.allExplicitIDs, [AnyHashable("first")])

        log.events.removeAll()
        var secondID = _ViewList_ID(implicitID: 0)
        second.bindID(&secondID)
        XCTAssertEqual(log.events, ["bind:second", "bind:first"])
        XCTAssertEqual(secondID.allExplicitIDs, [AnyHashable("second"), AnyHashable("first")])

        log.events.removeAll()
        let permanent = second.copy()
        var copiedID = _ViewList_ID(implicitID: 0)
        permanent.bindID(&copiedID)

        XCTAssertEqual(log.events, ["bind:second", "bind:first"])
        XCTAssertEqual(copiedID.allExplicitIDs, [AnyHashable("second"), AnyHashable("first")])
    }

    func testViewListApplyIDsEnumeratesTransformedIDsAndUpdatesIndexOnStop() {
        let list = BaseViewList(elements: FixedCountViewListElements(count: 4))
        let transform = _ViewList_TemporarySublistTransform()
            .withPushedItem(ApplyingIDTransformItem(id: "section"))
        var index = 1
        var ids: [_ViewList_ID] = []

        let completed = list.applyIDs(from: &index, transform: transform) { id in
            ids.append(id)
            return ids.count < 2
        }

        XCTAssertFalse(completed)
        XCTAssertEqual(index, 3)
        XCTAssertEqual(ids.map(\.index), [1, 2])
        XCTAssertEqual(ids.map(\.allExplicitIDs), [
            [AnyHashable("section")],
            [AnyHashable("section")],
        ])
        XCTAssertEqual(ids.map(\.canonicalID._index), [1, 2])
    }

    func testHeterogeneousViewIDsAccumulatorRestoresNestedExplicitIDScope() {
        var accumulator = HeterogeneousViewIDsAccumulator()

        accumulator.withExplicitID("outer", isUnary: true) { scoped in
            scoped.append(index: 0, implicitID: 10)
            scoped.withExplicitID("inner", isUnary: false) { nested in
                nested.append(index: 1, implicitID: 11)
            }
            scoped.append(index: 2, implicitID: 12)
        }

        let ids = accumulator.finalize().asCanonical()
        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(ids[0]._index, 0)
        XCTAssertEqual(ids[0].implicitID, -1)
        XCTAssertEqual(ids[0].explicitID, AnyHashable("outer"))
        XCTAssertEqual(ids[1]._index, 1)
        XCTAssertEqual(ids[1].implicitID, 11)
        XCTAssertEqual(ids[1].explicitID, AnyHashable("inner"))
        XCTAssertEqual(ids[2]._index, 2)
        XCTAssertEqual(ids[2].implicitID, -1)
        XCTAssertEqual(ids[2].explicitID, AnyHashable("outer"))
    }

    func testHeterogeneousViewIDsAccumulatorFinalizesWithoutConsumingBufferedIDs() {
        var accumulator = HeterogeneousViewIDsAccumulator()
        accumulator.append(index: 3, implicitID: 7)

        let first = accumulator.finalize().asCanonical()
        let second = accumulator.finalize().asCanonical()

        XCTAssertEqual(first, second)
        XCTAssertEqual(accumulator.count, 1)
        XCTAssertFalse(accumulator.isEmpty)
        XCTAssertEqual(first.first?._index, 3)
        XCTAssertEqual(first.first?.implicitID, 7)
        XCTAssertNil(first.first?.explicitID)
    }

    func testHeterogeneousViewIDsAccumulatorPreservesUnaryZeroInRange() {
        var accumulator = HeterogeneousViewIDsAccumulator()
        accumulator.append(indices: -1..<2, implicitID: -1, explicitID: "row")

        let ids = accumulator.finalize().asCanonical()

        XCTAssertEqual(ids.map(\._index), [-1, 0, 1])
        XCTAssertEqual(ids.map(\.implicitID), [-1, -1, -1])
        XCTAssertEqual(ids.map(\.explicitID), [
            AnyHashable("row"),
            AnyHashable("row"),
            AnyHashable("row"),
        ])
    }
}

private struct CanonicalIDsOnlyViewList: ViewList {
    var ids: _ViewList_ID_Views

    var viewIDs: _ViewList_ID_Views? {
        ids
    }
}

private final class TransformCallLog {
    var events: [String] = []
}

private final class IteratorStyleLog {
    var values: [UInt] = []
}

private struct IteratorStyleRecordingViewList: ViewList {
    var log: IteratorStyleLog

    func count(style: _ViewList_IteratorStyle) -> Int {
        1
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
        log.values.append(style.value)
        let sublist = _ViewList_Sublist(
            start: from,
            count: 1,
            id: _ViewList_ID(implicitID: 0),
            elements: _ViewList_SubgraphElements(
                base: FixedCountViewListElements(count: 1)
            ),
            traits: ViewTraitCollection(),
            list: list
        )
        let result = to(&from, style, .sublist(sublist), transform)
        from = 0
        return result
    }
}

private struct RecordingTransformItem: _ViewList_SublistTransform_Item {
    var name: String
    var log: TransformCallLog

    func apply(sublist: inout _ViewList_Sublist) {
        log.events.append("apply:\(name)")
    }

    func bindID(_ id: inout _ViewList_ID) {
        log.events.append("bind:\(name)")
        id.bind(explicitID: name, owner: .invalid, isUnary: false, reuseID: 0)
    }

    func wrapSubgraph(into storage: inout _ViewList_SublistSubgraphStorage) {
        log.events.append("wrap:\(name)")
    }
}

private struct ApplyingIDTransformItem: _ViewList_SublistTransform_Item {
    var id: String

    func apply(sublist: inout _ViewList_Sublist) {
        bindID(&sublist.id)
    }

    func bindID(_ id: inout _ViewList_ID) {
        id.bind(explicitID: self.id, owner: .invalid, isUnary: false, reuseID: 0)
    }
}

private struct FixedCountViewListElements: _ViewList_Elements {
    var count: Int

    @discardableResult
    func makeElements(
        from: inout Int,
        inputs: _ViewInputs,
        indirectMap: IndirectAttributeMap?,
        body: (_ViewInputs, @escaping (_ViewInputs) -> _ViewOutputs) -> (_ViewOutputs?, Bool)
    ) -> (_ViewOutputs?, Bool) {
        from = max(0, from - count)
        return (nil, true)
    }
}

private struct ExplicitSingleViewList: ViewList {
    var explicitID: AnyHashable

    func count(style: _ViewList_IteratorStyle) -> Int { 1 }

    func applyNodes(
        from: inout Int,
        style: _ViewList_IteratorStyle,
        list: Attribute<any ViewList>?,
        transform: _ViewList_TemporarySublistTransform,
        to: (inout Int, _ViewList_IteratorStyle, _ViewList_Node, _ViewList_TemporarySublistTransform) -> Bool
    ) -> Bool {
        let sublist = _ViewList_Sublist(
            start: from,
            count: 1,
            id: _ViewList_ID(explicitID: explicitID),
            elements: _ViewList_SubgraphElements(
                base: FixedCountViewListElements(count: 1)
            ),
            traits: ViewTraitCollection(),
            list: list
        )
        let result = to(&from, style, .sublist(sublist), transform)
        from = 0
        return result
    }
}
