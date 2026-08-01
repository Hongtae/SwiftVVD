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

final class DynamicLayoutStateTests: XCTestCase {
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
                                body: { _ in output(value) },
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
            let hash = StrongHash(words: (1, 2, 3, 4, 5))
            let scope = graph.makeInput(
                value: _DisplayList_StableIdentityScope(
                    root: root,
                    hash: hash,
                    map: _DisplayList_StableIdentityMap(),
                    serial: 9
                )
            )
            root.scopes.append(WeakAttribute(scope))

            XCTAssertTrue(
                _DisplayList_StableIdentityScope.defaultValue.isInvalid
            )
            XCTAssertTrue(scope.value.root === root)
            XCTAssertEqual(scope.value.hash, hash)
            XCTAssertTrue(scope.value.map.isEmpty)
            XCTAssertEqual(scope.value.serial, 9)
            XCTAssertFalse(root.scopes[0].isInvalid)
            XCTAssertNil(root.map)
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

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
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
