import XCTest
@testable import VUI

private struct ArchivedTraitsViewList: ViewList {
    var traits: ViewTraitCollection
}

private struct ArchivedContentProbeTransition: Transition {
    var effect: ContentTransition.Effect

    func body(content: Content, phase: TransitionPhase) -> Content {
        content
    }

    func _makeContentTransition(
        transition: inout _Transition_ContentTransition
    ) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            transition.result = .effects([effect])
        }
    }
}

private struct MergedElementPreferenceKey: PreferenceKey {
    static var defaultValue: [Int] { [] }

    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

private struct EncodableStableIdentityProbe: Hashable, Codable {
    var value: Int
}

private final class TupleStableScopeRecorder {
    var hashes: [StrongHash] = []
}

private struct TupleStableScopeProbeView<Payload>: PrimitiveView {
    var recorder: TupleStableScopeRecorder
    var payload: Payload

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let scope = inputs.base.stableIDScope?.attribute else {
            fatalError("Tuple stable-scope probe requires a live scope.")
        }
        view._attribute.value.recorder.hashes.append(
            scope.valueAndFlags(
                options: .withoutDependency
            ).value.hash
        )
        return .unaryViewList(view: view, inputs: inputs)
    }
}

private final class IDViewCachedContentRecorder {
    var content: Attribute<IDViewCachedContentProbeView>?
}

private struct IDViewCachedContentProbeView: PrimitiveView {
    var payload: Int
    var recorder: IDViewCachedContentRecorder

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let content = view._attribute.value
        content.recorder.content = view._attribute
        return .unaryViewList(view: view, inputs: inputs)
    }
}

private struct ZeroCountProbeViewList: ViewList {
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
        let sublist = _ViewList_Sublist(
            start: from,
            count: 0,
            id: _ViewList_ID(),
            elements: _ViewList_SubgraphElements(
                base: EmptyViewListElements()
            ),
            traits: ViewTraitCollection(),
            list: list
        )
        return to(&from, style, .sublist(sublist), transform)
    }
}

private struct ReusableDynamicContainerProbeItem: DynamicContainerItem {
    var id: Int
    var storageKind: Int
    var reusableStorageKinds: Set<Int>
    var viewCount: Int = 1
    var needsTransitions: Bool = false

    var count: Int { viewCount }

    func matchesIdentity(of other: Self) -> Bool {
        id == other.id
    }

    static var supportsReuse: Bool { true }

    func canBeReused(by other: Self) -> Bool {
        reusableStorageKinds.contains(other.storageKind)
    }
}

private struct ReusableDynamicContainerProbeAdaptor:
    DynamicContainerAdaptor {
    typealias Item = ReusableDynamicContainerProbeItem
    typealias Items = [Item]
    typealias ItemLayout = Void

    var source: Attribute<Items>

    static var maxUnusedItems: Int { 1 }

    mutating func updatedItems() -> Items? {
        source.value
    }

    func foreachItem(items: Items, _ body: (Item) -> Void) {
        items.forEach(body)
    }

    static func containsItem(_ items: Items, _ item: Item) -> Bool {
        items.contains { item.matchesIdentity(of: $0) }
    }

    func makeItemLayout(
        item: Item,
        uniqueId: UInt32,
        inputs: _ViewInputs,
        containerInfo: Attribute<DynamicContainer.Info>,
        containerInputs: (inout _ViewInputs) -> Void
    ) -> (_ViewOutputs, Void) {
        (_ViewOutputs(), ())
    }

    func removeItemLayout(uniqueId: UInt32, itemLayout: Void) {}
}

private final class DynamicContainerInfoEqualityRecorder {
    var producerEvaluations = 0
    var consumerEvaluations = 0
}

private struct DynamicContainerInfoEqualityRule: Rule {
    var source: Attribute<Int>
    var recorder: DynamicContainerInfoEqualityRecorder

    var value: DynamicContainer.Info {
        recorder.producerEvaluations += 1
        let input = source.value
        var info = DynamicContainer.Info()
        info.indexMap = [UInt32(input): input]
        info.seed = input == 2 ? 8 : 7
        return info
    }
}

final class DynamicLayoutStateTests: XCTestCase {
    func testDynamicContainerInfoDescriptorEqualityUsesOnlyTheSeed() {
        // ASSERTIONS dynamicContainerInfoTypeDescriptorEqualityObserved
        func requireDescriptorEquality<T: _AGTypeDescriptorEquatable>(
            _ type: T.Type
        ) {}
        requireDescriptorEquality(DynamicContainer.Info.self)

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = DynamicContainerInfoEqualityRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let info = graph.makeRule(
                DynamicContainerInfoEqualityRule(
                    source: source,
                    recorder: recorder
                )
            )
            let consumer = graph.makeRule {
                recorder.consumerEvaluations += 1
                return info.value.seed
            }

            XCTAssertEqual(consumer.value, 7)
            XCTAssertEqual(recorder.producerEvaluations, 1)
            XCTAssertEqual(recorder.consumerEvaluations, 1)

            source.setValue(11)
            XCTAssertEqual(consumer.value, 7)
            XCTAssertEqual(recorder.producerEvaluations, 2)
            XCTAssertEqual(recorder.consumerEvaluations, 1)

            source.setValue(2)
            XCTAssertEqual(consumer.value, 8)
            XCTAssertEqual(recorder.producerEvaluations, 3)
            XCTAssertEqual(recorder.consumerEvaluations, 2)
        }
    }

    func testDynamicContainerIDUsesUniqueIDThenSignedViewIndexOrdering() {
        // ASSERTIONS dynamicLayoutStateOwnershipObserved
        let ids = [
            DynamicContainerID(uniqueId: 2, viewIndex: 0),
            DynamicContainerID(uniqueId: 1, viewIndex: 1),
            DynamicContainerID(uniqueId: 1, viewIndex: -1),
            DynamicContainerID(uniqueId: 1, viewIndex: 0),
        ]

        XCTAssertEqual(
            ids.sorted(),
            [
                DynamicContainerID(uniqueId: 1, viewIndex: -1),
                DynamicContainerID(uniqueId: 1, viewIndex: 0),
                DynamicContainerID(uniqueId: 1, viewIndex: 1),
                DynamicContainerID(uniqueId: 2, viewIndex: 0),
            ]
        )
    }

    func testDynamicLayoutMapStoresFlatSortedEntriesAndRemovesOneItemRange() {
        // ASSERTIONS dynamicLayoutStateOwnershipObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let firstComputer = graph.makeInput(
                value: LayoutComputer.defaultValue
            )
            let secondComputer = graph.makeInput(
                value: LayoutComputer.defaultValue
            )
            let first = LayoutProxyAttributes(
                layoutComputer: firstComputer
            )
            let second = LayoutProxyAttributes(
                layoutComputer: secondComputer
            )
            let firstID = DynamicContainerID(uniqueId: 4, viewIndex: 0)
            let secondID = DynamicContainerID(uniqueId: 2, viewIndex: 1)

            var map = DynamicLayoutMap()
            map[firstID] = first
            map[secondID] = second

            XCTAssertEqual(map.map.map(\.id), [secondID, firstID])
            XCTAssertEqual(map[firstID], first)
            XCTAssertEqual(map[secondID], second)
            XCTAssertEqual(
                map[DynamicContainerID(uniqueId: 9, viewIndex: 0)],
                LayoutProxyAttributes()
            )

            map[firstID] = LayoutProxyAttributes()
            XCTAssertEqual(map.map.map(\.id), [secondID])

            map[DynamicContainerID(uniqueId: 2, viewIndex: 0)] = first
            map.remove(uniqueId: 2)
            XCTAssertTrue(map.map.isEmpty)
        }
    }

    func testDynamicLayoutMapReordersByContainerInfoAndViewIndex() {
        // ASSERTIONS dynamicLayoutStateOwnershipObserved
        // ASSERTIONS wrappingIncrementAndBasePlusOffsetObserved
        // ASSERTIONS flatSortedActivePrefixObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let attributes = (0..<5).map { _ in
                LayoutProxyAttributes(
                    layoutComputer: graph.makeInput(
                        value: LayoutComputer.defaultValue
                    )
                )
            }
            let first = makeItem(
                uniqueId: 8,
                source: "first",
                viewCount: 2
            )
            let second = makeItem(
                uniqueId: 3,
                source: "second",
                viewCount: 1
            )
            let removed = makeItem(
                uniqueId: 6,
                source: "removed",
                viewCount: 1
            )
            let unused = makeItem(
                uniqueId: 4,
                source: "unused",
                viewCount: 1
            )
            var info = DynamicContainer.Info()
            info.replaceItems(
                active: [first, second],
                removed: [removed],
                unused: [unused]
            )
            info.displayMap = [1, 0]

            var map = DynamicLayoutMap()
            map[DynamicContainerID(uniqueId: 8, viewIndex: 0)] =
                attributes[0]
            map[DynamicContainerID(uniqueId: 8, viewIndex: 1)] =
                attributes[1]
            map[DynamicContainerID(uniqueId: 3, viewIndex: 0)] =
                attributes[2]
            map[DynamicContainerID(uniqueId: 6, viewIndex: 0)] =
                attributes[3]
            map[DynamicContainerID(uniqueId: 4, viewIndex: 0)] =
                attributes[4]

            XCTAssertEqual(
                map.attributes(info: info),
                Array(attributes.prefix(3))
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 8, viewIndex: 0)
                ),
                0
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 8, viewIndex: 1)
                ),
                1
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 3, viewIndex: 0)
                ),
                2
            )
            XCTAssertEqual(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 8, viewIndex: 2)
                ),
                2,
                "The producer, rather than Info.viewIndex, owns the child-offset range invariant."
            )
            XCTAssertNil(
                info.viewIndex(
                    id: DynamicContainerID(uniqueId: 99, viewIndex: 0)
                )
            )
        }
    }

    func testDynamicViewListItemUsesObservedDefaultReusePolicy() {
        // ASSERTIONS dynamicContainerAdaptorAndItemProtocolsObserved
        // ASSERTIONS dynamicContainerAdaptorOwnershipObserved
        let item = DynamicViewListItem(
            id: _ViewList_ID(explicitID: AnyHashable("row")),
            elements: _ViewList_SubgraphElements(
                base: EmptyViewListElements()
            ),
            traits: ViewTraitCollection(),
            list: nil
        )

        XCTAssertEqual(item.count, 0)
        XCTAssertFalse(item.needsTransitions)
        XCTAssertEqual(item.zIndex, 0)
        XCTAssertFalse(DynamicViewListItem.supportsReuse)
        XCTAssertFalse(item.canBeReused(by: item))
        XCTAssertNil(item.viewID)
    }

    func testDynamicContainerExactIdentityReordersWithoutResettingSlots() {
        // ASSERTIONS dynamicContainerReuseSelectionOrderObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let first = reusableItem(id: 1)
            let second = reusableItem(id: 2)
            let source = graph.makeInput(value: [first, second])
            let info = makeReusableContainer(
                graph: graph,
                source: source
            )

            let initial = info.value
            XCTAssertEqual(initial.activeItems.map(\.uniqueId), [1, 2])

            source.setValue([second, first])
            let reordered = info.value

            XCTAssertEqual(reordered.activeItems.map(\.uniqueId), [2, 1])
            XCTAssertEqual(reordered.activeItems.map(\.resetSeed), [0, 0])
        }
    }

    func testDynamicContainerExactIdentityOwnsMetadataCompatibility() {
        // ASSERTIONS dynamicContainerReuseControlFlowObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(value: [reusableItem(id: 1)])
            let info = makeReusableContainer(
                graph: graph,
                source: source
            )
            _ = info.value

            source.setValue([
                reusableItem(
                    id: 1,
                    viewCount: 2,
                    needsTransitions: true
                ),
            ])
            let updated = info.value
            let slot = updated.activeItems[updated.activeItems.startIndex]

            XCTAssertEqual(slot.uniqueId, 1)
            XCTAssertEqual(slot.viewCount, 1)
            XCTAssertFalse(slot.needsTransitions)
            XCTAssertEqual(
                slot.for(ReusableDynamicContainerProbeAdaptor.self)
                    .item.count,
                2
            )
            XCTAssertTrue(
                slot.for(ReusableDynamicContainerProbeAdaptor.self)
                    .item.needsTransitions
            )
        }
    }

    func testDynamicContainerReuseProtectsLaterIncomingIdentity() {
        // ASSERTIONS dynamicContainerReuseSelectionOrderObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let first = reusableItem(
                id: 1,
                storageKind: 1,
                reusableStorageKinds: [2]
            )
            let second = reusableItem(
                id: 2,
                storageKind: 1,
                reusableStorageKinds: [2]
            )
            let source = graph.makeInput(value: [first, second])
            let info = makeReusableContainer(
                graph: graph,
                source: source
            )
            _ = info.value

            source.setValue([
                reusableItem(
                    id: 9,
                    storageKind: 2,
                    reusableStorageKinds: []
                ),
                reusableItem(
                    id: 1,
                    storageKind: 2,
                    reusableStorageKinds: []
                ),
            ])
            let updated = info.value

            XCTAssertEqual(updated.activeItems.map(\.uniqueId), [2, 1])
            XCTAssertEqual(
                updated.activeItems
                    .map { $0.for(ReusableDynamicContainerProbeAdaptor.self).item.id },
                [9, 1]
            )
            XCTAssertEqual(updated.activeItems.map(\.resetSeed), [1, 0])
        }
    }

    func testDynamicContainerGeneralReuseSkipsTransitionOwnedStorage() {
        // ASSERTIONS dynamicContainerReuseSelectionOrderObserved
        let host = GraphHost()
        host.data.withCurrent {
            let graph = host.data.graph
            let source = graph.makeInput(value: [
                reusableItem(
                    id: 1,
                    storageKind: 1,
                    reusableStorageKinds: [2],
                    needsTransitions: true
                ),
                reusableItem(
                    id: 2,
                    storageKind: 1,
                    reusableStorageKinds: [2]
                ),
            ])
            let info = makeReusableContainer(
                graph: graph,
                source: source
            )
            _ = info.value

            source.setValue([
                reusableItem(
                    id: 9,
                    storageKind: 2,
                    reusableStorageKinds: []
                ),
            ])
            let updated = info.value

            XCTAssertEqual(updated.activeItems.map(\.uniqueId), [2])
            XCTAssertEqual(
                updated.activeItems.first?
                    .for(ReusableDynamicContainerProbeAdaptor.self)
                    .item.id,
                9
            )
        }
    }

    func testDynamicContainerPrefersRetainedUnusedStorageForReuse() {
        // ASSERTIONS dynamicContainerReuseSelectionOrderObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let first = reusableItem(
                id: 1,
                storageKind: 1,
                reusableStorageKinds: [2]
            )
            let second = reusableItem(
                id: 2,
                storageKind: 1,
                reusableStorageKinds: [2]
            )
            let source = graph.makeInput(value: [first, second])
            let info = makeReusableContainer(
                graph: graph,
                source: source
            )
            _ = info.value

            source.setValue([first])
            let shrunk = info.value
            XCTAssertEqual(shrunk.activeItems.map(\.uniqueId), [1])
            XCTAssertEqual(shrunk.unusedCount, 1)
            XCTAssertEqual(shrunk.items.last?.uniqueId, 2)
            XCTAssertNil(shrunk.items.last?.phase)

            source.setValue([
                reusableItem(
                    id: 9,
                    storageKind: 2,
                    reusableStorageKinds: []
                ),
            ])
            let reused = info.value

            XCTAssertEqual(reused.activeItems.map(\.uniqueId), [2])
            XCTAssertEqual(reused.activeItems.first?.resetSeed, 2)
            XCTAssertEqual(
                reused.activeItems.first?
                    .for(ReusableDynamicContainerProbeAdaptor.self)
                    .item.id,
                9
            )
        }
    }

    func testZeroCountSublistDoesNotReachTraversalCallback() {
        // ASSERTIONS zeroCountSublistsAreSkippedObserved
        var callbackCount = 0

        XCTAssertTrue(
            _forEachSublist(in: ZeroCountProbeViewList()) { _ in
                callbackCount += 1
                return true
            }
        )
        XCTAssertEqual(callbackCount, 0)
    }

    func testMergedElementsPreserveEveryPreferenceContributor() throws {
        // ASSERTIONS mergedElementOutputsObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let inputs = makeViewInputs(graph: graph)
            func output(_ value: Int) -> _ViewOutputs {
                let attribute = graph.makeInput(value: [value])
                var preferences = PreferencesOutputs()
                preferences.append(
                    MergedElementPreferenceKey.self,
                    node: attribute.identifier
                )
                return _ViewOutputs(preferences: preferences)
            }
            func listOutput(_ value: Int) -> _ViewListOutputs {
                _ViewListOutputs(
                    views: .staticList(
                        .unaryElements(
                            UnaryElements(
                                body: BodyUnaryViewGenerator(
                                    body: { _ in output(value) },
                                    viewType: EmptyView.self
                                ),
                                baseInputs: inputs.base
                            )
                        )
                    ),
                    nextImplicitID: 1,
                    staticCount: 1
                )
            }

            let result = try XCTUnwrap(
                MergedElements(outputs: [listOutput(1), listOutput(2)])
                    .makeAllElements(inputs: inputs) {
                        elementInputs,
                        makeView in
                        makeView(elementInputs)
                    }
            )
            let preference = try XCTUnwrap(
                result.preferences.value(
                    for: MergedElementPreferenceKey.self
                )
            )
            XCTAssertEqual(Attribute<[Int]>(preference).value, [1, 2])
        }
    }

    func testStableIdentityScopeCarriesRootHashMapAndSerial() {
        // ASSERTIONS stableIdentityScopeCarrierObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let root = _DisplayList_StableIdentityRoot()
            let scope = graph.makeInput(
                value: _DisplayList_StableIdentityScope(root: root)
            )
            root.scopes.append(WeakAttribute(scope))

            XCTAssertTrue(
                _DisplayList_StableIdentityScope.defaultValue.isInvalid
            )
            XCTAssertTrue(scope.value.root === root)
            XCTAssertEqual(scope.value.hash, StrongHash(of: "root"))
            XCTAssertTrue(scope.value.map.isEmpty)
            XCTAssertEqual(scope.value.serial, 0)
            XCTAssertFalse(root.scopes[0].isInvalid)
            XCTAssertNil(root.map)
        }
    }

    func testStableIdentityNamespaceBuildsHierarchicalHashesAndRootMap()
        throws {
        // ASSERTIONS stableIdentityNamespaceControlFlowObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            let root = _DisplayList_StableIdentityRoot()
            inputs.configureStableIDs(root: root)

            XCTAssertTrue(
                inputs.base.options.contains(.needsStableDisplayListIDs)
            )
            XCTAssertEqual(root.scopes.count, 1)
            let rootScope = try XCTUnwrap(
                inputs.base.stableIDScope?.attribute
            ).valueAndFlags(
                options: .withoutDependency
            ).value
            XCTAssertEqual(rootScope.hash, StrongHash(of: "root"))

            inputs.base.pushStableIndex(17)
            let indexScope = try XCTUnwrap(
                inputs.base.stableIDScope?.attribute
            ).valueAndFlags(
                options: .withoutDependency
            ).value
            XCTAssertEqual(
                indexScope.hash,
                childStableHash(id: 17, parent: rootScope.hash)
            )

            let explicitID = EncodableStableIdentityProbe(value: 23)
            inputs.base.pushStableID(explicitID)
            let explicitScope = try XCTUnwrap(
                inputs.base.stableIDScope?.attribute
            ).valueAndFlags(
                options: .withoutDependency
            ).value
            XCTAssertEqual(
                explicitScope.hash,
                childStableHash(
                    id: try StrongHash(encodable: explicitID),
                    parent: indexScope.hash
                )
            )

            inputs.base.pushStableType(Self.self)
            let typeScope = try XCTUnwrap(
                inputs.base.stableIDScope?.attribute
            ).valueAndFlags(
                options: .withoutDependency
            ).value
            XCTAssertEqual(
                typeScope.hash,
                childStableHash(
                    id: makeStableTypeData(Self.self),
                    parent: explicitScope.hash
                )
            )
            XCTAssertEqual(root.scopes.count, 4)

            XCTAssertEqual(inputs.makeStableIdentity().serial, 1)
            let firstIdentity = inputs.pushIdentity()
            XCTAssertNil(root.map)
            XCTAssertEqual(
                root[firstIdentity],
                _DisplayList_StableIdentity(
                    hash: typeScope.hash,
                    serial: 2
                )
            )
            XCTAssertNotNil(root.map)

            let secondIdentity = inputs.pushIdentity()
            XCTAssertNil(root.map)
            XCTAssertEqual(
                root[secondIdentity],
                _DisplayList_StableIdentity(
                    hash: typeScope.hash,
                    serial: 3
                )
            )
            XCTAssertEqual(
                root[firstIdentity],
                _DisplayList_StableIdentity(
                    hash: typeScope.hash,
                    serial: 2
                )
            )
        }
    }

    func testStableIdentityScopePushesAreNoOpsWithoutOption() {
        // ASSERTIONS stableIdentityNamespaceControlFlowObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)

            inputs.base.pushStableIndex(17)
            inputs.base.pushStableID("row")
            inputs.base.pushStableType(Self.self)

            XCTAssertNil(inputs.base.stableIDScope)
            XCTAssertTrue(
                inputs.base[_DisplayList_StableIdentityScope.self].isInvalid
            )
            let firstIdentity = inputs.pushIdentity()
            let secondIdentity = inputs.pushIdentity()
            XCTAssertEqual(
                secondIdentity.value,
                firstIdentity.value &+ 1
            )
        }
    }

    func testTupleViewUsesLogicalElementIndexForStableIdentityScope()
        throws {
        // ASSERTIONS tupleViewMakeListVisitorControlFlowObserved
        let host = GraphHost()
        try host.data.withCurrent {
            let graph = host.data.graph
            var viewInputs = makeViewInputs(graph: graph)
            let root = _DisplayList_StableIdentityRoot()
            viewInputs.configureStableIDs(root: root)
            let rootHash = try XCTUnwrap(
                viewInputs.base.stableIDScope?.attribute
            ).valueAndFlags(
                options: .withoutDependency
            ).value.hash

            let recorder = TupleStableScopeRecorder()
            let value = TupleView(
                (
                    TupleStableScopeProbeView(
                        recorder: recorder,
                        payload: UInt8(1)
                    ),
                    TupleStableScopeProbeView(
                        recorder: recorder,
                        payload: (
                            UInt64(2),
                            UInt64(3),
                            UInt64(4),
                            UInt64(5)
                        )
                    )
                )
            )
            let attribute = graph.makeInput(value: value)

            _ = type(of: value)._makeViewList(
                view: _GraphValue(_attribute: attribute),
                inputs: _ViewListInputs(from: viewInputs)
            )

            XCTAssertEqual(
                recorder.hashes,
                [
                    childStableHash(id: 0, parent: rootHash),
                    childStableHash(id: 1, parent: rootHash),
                ]
            )
        }
    }

    func testStableIdentityScopeMutationDoesNotInvalidateGraphDependents()
        throws {
        // ASSERTIONS stableIdentityNamespaceControlFlowObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            inputs.configureStableIDs(
                root: _DisplayList_StableIdentityRoot()
            )
            let scope = try XCTUnwrap(
                inputs.base.stableIDScope?.attribute
            )
            var evaluations = 0
            let observedSerial = graph.makeRule {
                evaluations += 1
                return scope.value.serial
            }

            XCTAssertEqual(observedSerial.value, 0)
            XCTAssertEqual(evaluations, 1)
            XCTAssertEqual(inputs.makeStableIdentity().serial, 1)
            XCTAssertEqual(
                scope.valueAndFlags(
                    options: .withoutDependency
                ).value.serial,
                1
            )

            // Scope bookkeeping mutates the graph-owned payload in place. It
            // does not publish an ordinary input change to dependent rules.
            XCTAssertEqual(observedSerial.value, 0)
            XCTAssertEqual(evaluations, 1)
        }
    }

    func testStableIdentityRootKeepsEarlierScopeValueOnDuplicateMerge() {
        // ASSERTIONS stableIdentityNamespaceControlFlowObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let root = _DisplayList_StableIdentityRoot()
            let identity = _DisplayList_Identity(decodedValue: 41)
            let firstStable = _DisplayList_StableIdentity(
                hash: StrongHash(of: "first"),
                serial: 1
            )
            let secondStable = _DisplayList_StableIdentity(
                hash: StrongHash(of: "second"),
                serial: 2
            )
            var firstScope = _DisplayList_StableIdentityScope(root: root)
            var secondScope = _DisplayList_StableIdentityScope(root: root)
            firstScope.map[identity] = firstStable
            secondScope.map[identity] = secondStable
            let first = Attribute(value: firstScope)
            let second = Attribute(value: secondScope)
            root.scopes = [WeakAttribute(first), WeakAttribute(second)]

            XCTAssertEqual(root[identity], firstStable)
        }
    }

    func testStableIdentityRootPrunesInvalidWeakScopesDuringMerge() {
        // ASSERTIONS stableIdentityNamespaceControlFlowObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            let root = _DisplayList_StableIdentityRoot()
            inputs.configureStableIDs(root: root)
            root.scopes.append(WeakAttribute())

            let identity = inputs.pushIdentity()
            XCTAssertEqual(root.scopes.count, 2)
            XCTAssertNotNil(root[identity])
            XCTAssertEqual(root.scopes.count, 1)
        }
    }

    func testIDViewPushesExplicitStableScopeBeforeChildList()
        throws {
        // ASSERTIONS dynamicViewIdentityProducerDisassemblyObserved
        // ASSERTIONS stableIdentityNamespaceControlFlowObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            let root = _DisplayList_StableIdentityRoot()
            inputs.configureStableIDs(root: root)
            let rootHash = try XCTUnwrap(
                inputs.base.stableIDScope?.attribute
            ).valueAndFlags(
                options: .withoutDependency
            ).value.hash
            let idViewValue = IDView(EmptyView(), id: "row")
            let idView = graph.makeInput(value: idViewValue)

            _ = idViewValue.makeChildViewList(
                metadata: (),
                view: idView,
                inputs: _ViewListInputs(from: inputs)
            )

            XCTAssertEqual(root.scopes.count, 2)
            let childScope = try XCTUnwrap(
                root.scopes.last?.attribute
            ).valueAndFlags(
                options: .withoutDependency
            ).value
            XCTAssertEqual(
                childScope.hash,
                childStableHash(id: "row", parent: rootHash)
            )
        }
    }

    func testIDViewChildListCachesContentUntilIdentityChanges()
        throws {
        // ASSERTIONS idViewCachedContentRuleObserved
        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let recorder = IDViewCachedContentRecorder()
            let initial = IDView(
                IDViewCachedContentProbeView(
                    payload: 1,
                    recorder: recorder
                ),
                id: "row"
            )
            let source = graph.makeInput(value: initial)
            let inputs = makeViewInputs(graph: graph)

            _ = initial.makeChildViewList(
                metadata: (),
                view: source,
                inputs: _ViewListInputs(from: inputs)
            )

            let cached = try XCTUnwrap(recorder.content)
            XCTAssertEqual(cached.value.payload, 1)

            source.setValue(
                IDView(
                    IDViewCachedContentProbeView(
                        payload: 2,
                        recorder: recorder
                    ),
                    id: "row"
                )
            )
            XCTAssertEqual(cached.value.payload, 1)

            source.setValue(
                IDView(
                    IDViewCachedContentProbeView(
                        payload: 3,
                        recorder: recorder
                    ),
                    id: "replacement"
                )
            )
            XCTAssertEqual(cached.value.payload, 3)
        }
    }

    func testArchivedAnimationEffectUsesIdentityWithoutAnimation() {
        // ASSERTIONS viewListArchivedAnimationObserved
        let effect = ViewListArchivedAnimation.Effect(
            animation: nil,
            value: StrongHash(words: (1, 2, 3, 4, 5))
        )

        guard case .identity = effect.effectValue(size: .zero) else {
            return XCTFail("A missing archived animation must emit identity.")
        }
    }

    func testArchivedAnimationRuleCopiesHashOnlyWithAnimation() {
        // ASSERTIONS viewListArchivedAnimationObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let hash = StrongHash(words: (1, 2, 3, 4, 5))
            let animation = Animation.linear(duration: 0.25)
            var traits = ViewTraitCollection()
            traits[ArchivedAnimationTraitKey.self] =
                ArchivedAnimationTraitKey(
                    animation: animation,
                    hash: hash
                )
            let list: Attribute<any ViewList> = graph.makeInput(
                value: ArchivedTraitsViewList(traits: traits)
            )
            let output = graph.makeRule(
                ViewListArchivedAnimation(
                    _traitsList: OptionalAttribute(list)
                )
            ).value

            XCTAssertEqual(output.animation, animation)
            XCTAssertEqual(output.value, hash)
            guard case let .interpolatorAnimation(effect) =
                output.effectValue(size: .zero) else {
                return XCTFail(
                    "An archived animation must emit an interpolator effect."
                )
            }
            XCTAssertEqual(effect.animation, animation)
            XCTAssertEqual(effect.value, hash)
        }
    }

    func testArchivedContentTransitionBuildsBinaryRendererState() {
        // ASSERTIONS dynamicLayoutArchivedTransitionObserved
        // ASSERTIONS contentTransitionStateEnvironmentKeyObserved
        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            let effect = ContentTransition.Effect(
                type: .opacity,
                begin: 0.25,
                duration: 0.5,
                events: 3
            )
            let animation = Animation.linear(duration: 0.75)
            let initialState = ContentTransition.State(
                transition: .opacity,
                style: .animatedWidget,
                animation: animation,
                options: [.formsGroup]
            )
            var environment = EnvironmentValues()
            environment.contentTransitionState = initialState
            let helper = TransitionHelper(
                _list: OptionalAttribute<any ViewList>(),
                _info: graph.makeInput(value: DynamicContainer.Info()),
                uniqueId: 7,
                transition: ArchivedContentProbeTransition(effect: effect),
                phase: .identity
            )
            let output = graph.makeStatefulRule(
                ViewListContentTransition(
                    helper: helper,
                    _size: graph.makeInput(
                        value: ViewSize(width: 30, height: 20)
                    ),
                    _environment: graph.makeInput(value: environment)
                )
            ).value

            XCTAssertEqual(output.state.style, initialState.style)
            XCTAssertEqual(output.state.animation, animation)
            XCTAssertEqual(output.state.options, initialState.options)
            let rendererTransition = output.state.transition.rbTransition
            XCTAssertEqual(
                rendererTransition.method,
                ContentTransition.Method.binary.method
            )
            XCTAssertEqual(rendererTransition.effects.count, 1)
            guard let rendererEffect = rendererTransition.effects.first else {
                return XCTFail("The binary transition must retain its effect.")
            }
            XCTAssertEqual(rendererEffect.type, effect.type.type)
            XCTAssertEqual(
                rendererEffect.beginTime,
                effect.begin,
                accuracy: 1.0 / 255.0
            )
            XCTAssertEqual(
                rendererEffect.duration,
                effect.duration,
                accuracy: 1.0 / 255.0
            )
            XCTAssertEqual(rendererEffect.events, effect.events)
        }
    }

    private func makeItem(
        uniqueId: UInt32,
        source: String,
        viewCount: Int32
    ) -> DynamicContainer.ItemInfo {
        DynamicContainer.ItemInfo(
            subgraph: AGSubgraph(),
            uniqueId: uniqueId,
            viewCount: viewCount,
            outputs: _ViewOutputs()
        )
    }

    private func childStableHash<ID: StronglyHashable>(
        id: ID,
        parent: StrongHash
    ) -> StrongHash {
        var hasher = StrongHasher()
        hasher.combine(id)
        hasher.combine(parent)
        return hasher.finalize()
    }

    private func reusableItem(
        id: Int,
        storageKind: Int = 1,
        reusableStorageKinds: Set<Int> = [1],
        viewCount: Int = 1,
        needsTransitions: Bool = false
    ) -> ReusableDynamicContainerProbeItem {
        ReusableDynamicContainerProbeItem(
            id: id,
            storageKind: storageKind,
            reusableStorageKinds: reusableStorageKinds,
            viewCount: viewCount,
            needsTransitions: needsTransitions
        )
    }

    private func makeReusableContainer(
        graph: _AGGraph,
        source: Attribute<[ReusableDynamicContainerProbeItem]>
    ) -> Attribute<DynamicContainer.Info> {
        graph.makeStatefulRule(
            DynamicContainerInfo(
                adaptor: ReusableDynamicContainerProbeAdaptor(
                    source: source
                ),
                inputs: makeViewInputs(graph: graph),
                outputs: _ViewOutputs(),
                parentSubgraph: AGSubgraph.current,
                info: DynamicContainer.Info(),
                lastUniqueId: 0,
                lastRemoved: 0,
                lastResetSeed: .max,
                needsPhaseUpdate: false
            )
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
}
