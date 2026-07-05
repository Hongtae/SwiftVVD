import XCTest
@testable import VUI

final class ViewListIdentityTests: XCTestCase {
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

    func testViewListIDElementIDMaterializesGeneratedRowAndSharedSeeds() {
        let rowSeed = _ViewList_ID.GeneratedIDSeed(
            base: UniqueID(value: 1_000),
            kind: .rowLocal
        )
        let sharedSeed = _ViewList_ID.GeneratedIDSeed(
            base: UniqueID(value: 2_000),
            kind: .shared
        )

        var generatedOnly = _ViewList_ID(implicitID: 0)
        generatedOnly.bindGeneratedID(
            seed: rowSeed,
            owner: .invalid,
            isUnary: false,
            reuseID: _ViewList_ID.generatedRowReuseID
        )
        generatedOnly.bindGeneratedID(
            seed: sharedSeed,
            owner: .invalid,
            isUnary: false,
            reuseID: _ViewList_ID.generatedSectionReuseID
        )

        let firstGenerated = generatedOnly.elementID(at: 0)
        let thirdGenerated = generatedOnly.elementID(at: 2)

        XCTAssertEqual(firstGenerated.explicitIDs.count, 2)
        XCTAssertEqual((firstGenerated.explicitIDs[0].id.base as? UniqueID)?.value, 1_001)
        XCTAssertEqual((thirdGenerated.explicitIDs[0].id.base as? UniqueID)?.value, 1_003)
        XCTAssertEqual((firstGenerated.explicitIDs[1].id.base as? UniqueID)?.value, 2_000)
        XCTAssertEqual((thirdGenerated.explicitIDs[1].id.base as? UniqueID)?.value, 2_000)
        XCTAssertEqual(firstGenerated.explicitIDs.map(\.isUnary), [true, false])
        XCTAssertEqual(firstGenerated.canonicalID.explicitID, firstGenerated.explicitIDs[0].id)

        var explicitRow = _ViewList_ID(implicitID: 0)
        explicitRow.bind(explicitID: "row", owner: .invalid, isUnary: true, reuseID: 17)
        explicitRow.bindGeneratedID(
            seed: rowSeed,
            owner: .invalid,
            isUnary: false,
            reuseID: _ViewList_ID.generatedRowReuseID
        )
        explicitRow.bindGeneratedID(
            seed: sharedSeed,
            owner: .invalid,
            isUnary: false,
            reuseID: _ViewList_ID.generatedSectionReuseID
        )

        let explicitElement = explicitRow.elementID(at: 4)

        XCTAssertEqual(explicitElement.explicitIDs.count, 3)
        XCTAssertEqual(explicitElement.explicitIDs[0].id, AnyHashable("row"))
        XCTAssertEqual((explicitElement.explicitIDs[1].id.base as? UniqueID)?.value, 1_005)
        XCTAssertEqual((explicitElement.explicitIDs[2].id.base as? UniqueID)?.value, 2_000)
        XCTAssertEqual(explicitElement.explicitIDs.map(\.isUnary), [true, false, false])
        XCTAssertEqual(explicitElement.canonicalID.explicitID, AnyHashable("row"))
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
            elements: EmptyViewListElements(),
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
}

private final class TransformCallLog {
    var events: [String] = []
}

private struct RecordingTransformItem: _ViewList_SublistTransform_Item {
    var name: String
    var log: TransformCallLog

    func apply(to sublist: inout _ViewList_Sublist) {
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

    func apply(to sublist: inout _ViewList_Sublist) {
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
