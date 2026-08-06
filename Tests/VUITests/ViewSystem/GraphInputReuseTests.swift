import XCTest
@testable import VUI

private struct ReusableAttributeCarrier {
    var attribute: Attribute<Int>?
}

extension ReusableAttributeCarrier: GraphReusable {
    mutating func makeReusable(indirectMap: IndirectAttributeMap) {
        guard var attribute else { return }
        attribute.makeReusable(indirectMap: indirectMap)
        self.attribute = attribute
    }

    mutating func tryToReuse(
        by other: ReusableAttributeCarrier,
        indirectMap: IndirectAttributeMap,
        testOnly: Bool
    ) -> Bool {
        switch (attribute, other.attribute) {
        case (nil, nil):
            return true
        case (.some(var attribute), .some(let otherAttribute)):
            return attribute.tryToReuse(
                by: otherAttribute,
                indirectMap: indirectMap,
                testOnly: testOnly
            )
        default:
            return false
        }
    }
}

private struct ReusableAttributeInput: ViewInput {
    static var defaultValue: ReusableAttributeCarrier {
        ReusableAttributeCarrier(attribute: nil)
    }

    static func valuesEqual(
        _ lhs: ReusableAttributeCarrier,
        _ rhs: ReusableAttributeCarrier
    ) -> Bool {
        lhs.attribute?.identifier == rhs.attribute?.identifier
    }
}

private struct PlainReuseInput: GraphInput {
    static var defaultValue: Int { 0 }
}

final class GraphInputReuseTests: XCTestCase {
    func testBodyInputEqualityUsesClosureIdentityAndStackShape() {
        // ASSERTIONS bodyInputClosureEqualityObserved
        func makeViewClosure(
            token: Int
        ) -> (_Graph, _ViewInputs) -> _ViewOutputs {
            { _, _ in
                _ = token
                fatalError("Equality must not invoke modifier bodies.")
            }
        }
        func makeViewListClosure(
            token: Int
        ) -> (_Graph, _ViewListInputs) -> _ViewListOutputs {
            { _, _ in
                _ = token
                fatalError("Equality must not invoke modifier bodies.")
            }
        }

        let viewClosure = makeViewClosure(token: 1)
        let otherViewClosure = makeViewClosure(token: 2)
        let viewElement = BodyInputElement(makeView: viewClosure)
        let sameViewElement = viewElement
        let otherViewElement = BodyInputElement(makeView: otherViewClosure)
        let listElement = BodyInputElement(
            makeViewList: makeViewListClosure(token: 1)
        )

        XCTAssertEqual(viewElement, sameViewElement)
        XCTAssertNotEqual(viewElement, otherViewElement)
        XCTAssertNotEqual(viewElement, listElement)
        XCTAssertTrue(
            BodyInput<Int>.valuesEqual(
                .node(viewElement, .empty),
                .node(sameViewElement, .empty)
            )
        )
        XCTAssertFalse(
            BodyInput<Int>.valuesEqual(
                .node(viewElement, .empty),
                .node(sameViewElement, .node(sameViewElement, .empty))
            )
        )
    }

    func testReusableInputCarrierAndOptionBitsMatchObservedStructure() {
        // ASSERTIONS graphReusableStructureObserved
        // ASSERTIONS graphReuseOptionsProcessGlobalOverrideObserved
        let storage = ReusableInputs.defaultValue

        XCTAssertEqual(storage.filter.value, 0)
        if case .empty = storage.stack {
            // Expected newest-first stack sentinel.
        } else {
            XCTFail("Expected an empty reusable-input type stack.")
        }
        XCTAssertEqual(GraphReuseOptions.lazyLayouts.rawValue, 0x2)
        XCTAssertEqual(GraphReuseOptions.viewListContent.rawValue, 0x4)
        XCTAssertEqual(GraphReuseOptions.expandedReuse.rawValue, 0x8)
        XCTAssertEqual(GraphReuseOptions.default.rawValue, 0)

        let previousOptions = GraphReuseOptions.overrideValue
        defer { GraphReuseOptions.overrideValue = previousOptions }
        GraphReuseOptions.overrideValue = nil
        XCTAssertEqual(GraphReuseOptions.current, .default)
        GraphReuseOptions.overrideValue = [.lazyLayouts, .expandedReuse]
        XCTAssertEqual(
            GraphReuseOptions.current,
            [.lazyLayouts, .expandedReuse]
        )
        let crossThreadRawValue = DispatchQueue.global().sync {
            GraphReuseOptions.current.rawValue
        }
        XCTAssertEqual(
            crossThreadRawValue,
            GraphReuseOptions.lazyLayouts.rawValue
                | GraphReuseOptions.expandedReuse.rawValue
        )
    }

    func testAttributeReuseCreatesOneStableIndirectAndRetargetsIt() {
        // ASSERTIONS graphReusableIndirectRemappingObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let subgraph = AGSubgraphRef()
            let indirectMap = IndirectAttributeMap(subgraph: subgraph)
            let source = graph.makeInput(value: 11)
            let replacement = graph.makeInput(value: 42)

            var first = source
            first.makeReusable(indirectMap: indirectMap)
            var second = source
            second.makeReusable(indirectMap: indirectMap)

            XCTAssertEqual(first.identifier, second.identifier)
            XCTAssertEqual(indirectMap.map.count, 1)
            XCTAssertEqual(
                graph.indirectTarget(first.identifier),
                source.identifier
            )
            XCTAssertEqual(first.value, 11)

            var reusableSource = source
            XCTAssertTrue(
                reusableSource.tryToReuse(
                    by: replacement,
                    indirectMap: indirectMap,
                    testOnly: true
                )
            )
            XCTAssertEqual(
                graph.indirectTarget(first.identifier),
                source.identifier
            )

            XCTAssertTrue(
                reusableSource.tryToReuse(
                    by: replacement,
                    indirectMap: indirectMap,
                    testOnly: false
                )
            )
            XCTAssertEqual(
                graph.indirectTarget(first.identifier),
                replacement.identifier
            )
            XCTAssertEqual(first.value, 42)
        }
    }

    func testWithoutInvalidationDoesNotSuppressGraphLocalRetargeting() {
        // ASSERTIONS graphReusableWithoutInvalidationContextBoundaryObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let subgraph = AGSubgraphRef()
            let indirectMap = IndirectAttributeMap(subgraph: subgraph)
            let firstSource = graph.makeInput(value: 1)
            let secondSource = graph.makeInput(value: 2)
            var materialized = firstSource

            materialized.makeReusable(
                indirectMap: indirectMap,
                withoutInvalidation: true
            )
            XCTAssertEqual(materialized.value, 1)

            var reusableSource = firstSource
            XCTAssertTrue(
                reusableSource.tryToReuse(
                    by: secondSource,
                    indirectMap: indirectMap,
                    withoutInvalidation: true,
                    testOnly: false
                )
            )

            // The flag gates a cross-context invalidation callback; it does
            // not suppress ordinary graph-local dirty propagation.
            XCTAssertEqual(materialized.value, 2)
        }
    }

    func testGraphInputsReuseStandardAttributesAndRefreshesEnvironmentCache() {
        // ASSERTIONS graphInputsStandardReuseObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let original = makeGraphInputs(graph: graph, time: 1)
            let replacement = makeGraphInputs(graph: graph, time: 9)
            let originalCache = original.cachedEnvironment
            let subgraph = AGSubgraphRef()
            let indirectMap = IndirectAttributeMap(subgraph: subgraph)

            var materialized = original
            materialized.changedDebugProperties = 0
            materialized.makeReusable(indirectMap: indirectMap)

            XCTAssertEqual(indirectMap.map.count, 4)
            XCTAssertEqual(
                graph.indirectTarget(materialized.time.identifier),
                original.time.identifier
            )
            XCTAssertEqual(
                graph.indirectTarget(materialized.phase.identifier),
                original.phase.identifier
            )
            XCTAssertEqual(
                graph.indirectTarget(
                    materialized.cachedEnvironment.value.environment.identifier
                ),
                original.cachedEnvironment.value.environment.identifier
            )
            XCTAssertEqual(
                graph.indirectTarget(materialized.transaction.identifier),
                original.transaction.identifier
            )
            XCTAssertFalse(
                materialized.cachedEnvironment === originalCache
            )
            XCTAssertEqual(materialized.changedDebugProperties, 0x60)

            var reusableOriginal = original
            XCTAssertTrue(
                reusableOriginal.tryToReuse(
                    by: replacement,
                    indirectMap: indirectMap,
                    testOnly: true
                )
            )
            XCTAssertEqual(materialized.time.value.seconds, 1)

            XCTAssertTrue(
                reusableOriginal.tryToReuse(
                    by: replacement,
                    indirectMap: indirectMap,
                    testOnly: false
                )
            )
            XCTAssertEqual(materialized.time.value.seconds, 9)
            XCTAssertEqual(
                graph.indirectTarget(materialized.time.identifier),
                replacement.time.identifier
            )
        }
    }

    func testExpandedReuseSeparatesReusableAndOrdinaryCustomInputs() {
        // ASSERTIONS graphInputsExpandedReuseObserved
        let previousOptions = GraphReuseOptions.overrideValue
        GraphReuseOptions.overrideValue = [.expandedReuse]
        defer { GraphReuseOptions.overrideValue = previousOptions }

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let lhsAttribute = graph.makeInput(value: 3)
            let rhsAttribute = graph.makeInput(value: 8)
            var lhs = makeGraphInputs(graph: graph, time: 1)
            var rhs = lhs
            lhs[ReusableAttributeInput.self] =
                ReusableAttributeCarrier(attribute: lhsAttribute)
            rhs[ReusableAttributeInput.self] =
                ReusableAttributeCarrier(attribute: rhsAttribute)
            lhs[PlainReuseInput.self] = 17
            rhs[PlainReuseInput.self] = 17

            let subgraph = AGSubgraphRef()
            let indirectMap = IndirectAttributeMap(subgraph: subgraph)
            var materialized = lhs
            materialized.makeReusable(indirectMap: indirectMap)

            let reusableAttribute = materialized[
                ReusableAttributeInput.self
            ].attribute
            guard let reusableAttribute else {
                return XCTFail("Expected a materialized reusable attribute.")
            }
            XCTAssertEqual(
                graph.indirectTarget(
                    reusableAttribute.identifier
                ),
                lhsAttribute.identifier
            )

            var reusableLHS = lhs
            XCTAssertTrue(
                reusableLHS.tryToReuse(
                    by: rhs,
                    indirectMap: indirectMap,
                    testOnly: false
                )
            )
            XCTAssertEqual(reusableAttribute.value, 8)

            rhs[PlainReuseInput.self] = 99
            reusableLHS = lhs
            XCTAssertFalse(
                reusableLHS.tryToReuse(
                    by: rhs,
                    indirectMap: indirectMap,
                    testOnly: true
                )
            )
        }
    }

    func testViewAndListInputsForwardViewKeysIntoGraphInputs() {
        // ASSERTIONS graphInputViewInputSharedChannelObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var viewInputs = makeViewInputs(graph: graph)
            let source = graph.makeInput(value: 5)
            viewInputs[ReusableAttributeInput.self] =
                ReusableAttributeCarrier(attribute: source)

            XCTAssertEqual(
                viewInputs.base[
                    ReusableAttributeInput.self
                ].attribute?.identifier,
                source.identifier
            )
            XCTAssertNil(
                viewInputs.customInputs.value(
                    forKey: ReusableAttributeInput.self
                ).attribute
            )

            var listInputs = viewInputs.listInputs
            let replacement = graph.makeInput(value: 6)
            listInputs[ReusableAttributeInput.self] =
                ReusableAttributeCarrier(attribute: replacement)

            XCTAssertEqual(
                listInputs.base[
                    ReusableAttributeInput.self
                ].attribute?.identifier,
                replacement.identifier
            )
        }
    }

    private func makeGraphInputs(
        graph: _AGGraph,
        time: Double
    ) -> _GraphInputs {
        _GraphInputs(
            time: graph.makeInput(value: Time(seconds: time)),
            phase: graph.makeInput(value: Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph, time: 0),
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
