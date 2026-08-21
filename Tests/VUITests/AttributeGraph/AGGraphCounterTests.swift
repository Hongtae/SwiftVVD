import Synchronization
import XCTest
@testable import VUI

final class AGGraphCounterTests: XCTestCase {
    func testComputedOutputReusesGraphOwnedStorageAcrossPublications() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        var proposedValue = 1

        ref.withCurrent {
            let output = graph.makeRule { proposedValue }
            XCTAssertEqual(output.value, 1)

            let initialStorage = try! XCTUnwrap(
                graph.slots[Int(output.identifier.rawValue)].node?.value
                    as? _AGValueStorage<Int>
            )
            let initialPointer = initialStorage.rawPointer

            graph.invalidateAttribute(output.identifier)
            XCTAssertEqual(output.value, 1)
            let equalStorage = try! XCTUnwrap(
                graph.slots[Int(output.identifier.rawValue)].node?.value
                    as? _AGValueStorage<Int>
            )
            XCTAssertTrue(initialStorage === equalStorage)
            XCTAssertEqual(initialPointer, equalStorage.rawPointer)

            proposedValue = 2
            graph.invalidateAttribute(output.identifier)
            XCTAssertEqual(output.value, 2)
            let changedStorage = try! XCTUnwrap(
                graph.slots[Int(output.identifier.rawValue)].node?.value
                    as? _AGValueStorage<Int>
            )
            XCTAssertTrue(initialStorage === changedStorage)
            XCTAssertEqual(initialPointer, changedStorage.rawPointer)
        }
    }

    func testStoredKeyPathProjectionUsesOffsetNodeAndReusesStorage() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(
                value: StoredProjectionRoot(value: 1)
            )
            let projection = graph.subscriptNode(
                parent: source,
                keyPath: \.value
            )
            guard case .offset = graph.slots[
                Int(projection.identifier.rawValue)
            ].node?.kind else {
                return XCTFail("Stored key paths must use an offset node.")
            }
            XCTAssertEqual(projection.value, 1)

            let initialStorage = try! XCTUnwrap(
                graph.slots[Int(projection.identifier.rawValue)].node?.value
                    as? _AGValueStorage<Int>
            )
            let initialPointer = initialStorage.rawPointer

            source.value = StoredProjectionRoot(value: 2)
            XCTAssertEqual(projection.value, 2)
            let changedStorage = try! XCTUnwrap(
                graph.slots[Int(projection.identifier.rawValue)].node?.value
                    as? _AGValueStorage<Int>
            )
            XCTAssertTrue(initialStorage === changedStorage)
            XCTAssertEqual(initialPointer, changedStorage.rawPointer)
        }
    }

    func testComputedKeyPathProjectionUsesTypedFocusRule() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(
                value: ComputedProjectionRoot(storedValue: 1)
            )
            let projection = graph.subscriptNode(
                parent: source,
                keyPath: \.computedValue
            )

            XCTAssertTrue(
                projection.identifier._bodyType
                    == Focus<ComputedProjectionRoot, Int>.self
            )
            guard case .ruleBody = graph.slots[
                Int(projection.identifier.rawValue)
            ].node?.kind else {
                return XCTFail("Computed key paths must use a Focus rule.")
            }
            XCTAssertEqual(projection.value, 2)

            source.value = ComputedProjectionRoot(storedValue: 5)
            XCTAssertEqual(projection.value, 6)
        }
    }

    func testGraphContextFacadeStoresOneContextPerGraph() {
        let graph = _AGGraph()
        let first = AGGraphContextToken()
        let second = AGGraphContextToken()

        XCTAssertNil(AGGraphGetContext(graph))

        AGGraphSetContext(graph, first)
        XCTAssertTrue(AGGraphGetContext(graph) === first)
        XCTAssertTrue(_AGGraphGetContext(graph) === first)

        _AGGraphSetContext(graph, second)
        XCTAssertTrue(AGGraphGetContext(graph) === second)

        AGGraphSetContext(graph, nil)
        XCTAssertNil(AGGraphGetContext(graph))
    }

    func testAttributeBodyProtocolDefaultsMatchObservedSurface() {
        XCTAssertEqual(DefaultAttributeBody.comparisonMode, .layout)
        XCTAssertEqual(DefaultAttributeBody.flags, .mainThread)
        XCTAssertFalse(DefaultAttributeBody._hasDestroySelf)
        XCTAssertTrue(AsyncAttributeBody.flags.isEmpty)
        XCTAssertTrue(ObservedStatefulRule._hasDestroySelf)
    }

    func testRawAttributeInfoUsesStableSwiftOwnedBodyStorage() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = Attribute(value: 3)
            let recorder = MutableRuleRecorder()
            XCTAssertTrue(source.identifier._bodyType == _External.self)
            XCTAssertTrue(source.identifier.valueType == Int.self)
            XCTAssertEqual(
                source.identifier._bodyPointer,
                source.identifier._bodyPointer
            )

            let output = graph.makeRule(
                MutableRule(source: source, offset: 4, recorder: recorder)
            )
            let originalPointer = output.identifier._bodyPointer
            XCTAssertTrue(output.identifier._bodyType == MutableRule.self)
            XCTAssertTrue(output.identifier.valueType == Int.self)
            XCTAssertEqual(output.value, 7)

            output.mutateBody(as: MutableRule.self, invalidating: true) {
                $0.offset = 8
            }
            XCTAssertEqual(output.identifier._bodyPointer, originalPointer)
            XCTAssertEqual(output.value, 11)
        }
    }

    func testLowLevelAttributeInitializerRetainsBodyAndRunsUpdateFunction() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = Attribute(value: 5)
            var body = LowLevelDoublingBody(source: source)
            var initialValue = 0
            let output = withUnsafePointer(to: &body) { bodyPointer in
                withUnsafePointer(to: &initialValue) { valuePointer in
                    Attribute<Int>(
                        body: bodyPointer,
                        value: valuePointer,
                        flags: LowLevelDoublingBody.flags,
                        update: { LowLevelDoublingBody.update }
                    )
                }
            }

            XCTAssertTrue(output.identifier._bodyType == LowLevelDoublingBody.self)
            XCTAssertTrue(output.identifier.valueType == Int.self)
            XCTAssertEqual(output.value, 10)

            source.value = 7
            XCTAssertEqual(output.value, 14)
        }
    }

    func testRawOffsetUsesStableDistinctOpaqueIdentity() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = Attribute(value: 1)
            let offset = source.identifier.unsafeOffset(at: 0)
            XCTAssertNotEqual(offset, source.identifier)
            XCTAssertEqual(offset, source.identifier.unsafeOffset(at: 0))
        }
    }

    func testRuleInitialValueStillPerformsFirstEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = RuleInitialValueRecorder()

        ref.withCurrent {
            let output = graph.makeRule(
                RuleWithInitialValue(recorder: recorder)
            )

            XCTAssertTrue(graph.hasCachedValue(for: output.identifier))
            XCTAssertEqual(recorder.evaluationCount, 0)
            XCTAssertEqual(output.value, 42)
            XCTAssertEqual(recorder.evaluationCount, 1)
        }
    }

    func testAttributeToOptionalCreatesASeparateUpdatingRule() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = Attribute(value: 3)
            let optional = source.toOptional

            XCTAssertNotEqual(optional.identifier, source.identifier)
            XCTAssertEqual(optional.value, 3)

            source.value = 5
            XCTAssertEqual(optional.value, 5)
        }
    }

    func testEmptyTypedAttributeWrappersReturnNil() {
        let optional = OptionalAttribute<Int>()
        let weak = WeakAttribute<Int>()

        XCTAssertNil(optional.attribute)
        XCTAssertNil(weak.attribute)
    }

    func testWeakAttributeResolvesItsOwningGraphWithoutCurrentContext() {
        let firstGraph = _AGGraph()
        let secondGraph = _AGGraph()
        var first = WeakAttribute<Int>()
        var second = WeakAttribute<Int>()

        _AGGraphContext(graph: firstGraph).withCurrent {
            first = firstGraph.makeInput(value: 11).asWeak()
        }
        _AGGraphContext(graph: secondGraph).withCurrent {
            second = secondGraph.makeInput(value: 22).asWeak()
        }

        XCTAssertNil(_AGGraph.current)
        XCTAssertEqual(first.base.identifier, second.base.identifier)
        XCTAssertNotEqual(first.base.seed, second.base.seed)
        XCTAssertTrue(first.graph === firstGraph)
        XCTAssertTrue(second.graph === secondGraph)
        XCTAssertEqual(first.value, 11)
        XCTAssertEqual(second.value, 22)
        XCTAssertNil(_AGGraph.current)
    }

    func testWeakAttributeRejectsRemovedGenerationOutsideGraphContext() {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        var stale = WeakAttribute<Int>()
        var replacement = WeakAttribute<Int>()

        context.withCurrent {
            let first = graph.makeInput(value: 11)
            stale = first.asWeak()
            graph.removeNode(first.identifier)

            let second = graph.makeInput(value: 22)
            replacement = second.asWeak()
        }

        XCTAssertNil(_AGGraph.current)
        XCTAssertEqual(stale.base.identifier, replacement.base.identifier)
        XCTAssertNotEqual(stale.base.seed, replacement.base.seed)
        XCTAssertNil(stale.graph)
        XCTAssertNil(stale.value)
        XCTAssertTrue(replacement.graph === graph)
        XCTAssertEqual(replacement.value, 22)
        XCTAssertNil(_AGGraph.current)
    }

    func testExplicitInputRegistersDependencyWithoutReadingValue() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = Attribute(value: 1)
            let recorder = MutableRuleRecorder()
            let output = graph.makeRule {
                recorder.evaluationCount += 1
                return 42
            }

            XCTAssertEqual(output.value, 42)
            XCTAssertEqual(recorder.evaluationCount, 1)
            output.addInput(source, options: [], token: 17)

            source.value = 2
            XCTAssertTrue(
                output.breadthFirstSearch(
                    options: .inputs
                ) { $0 == source.identifier }
            )
            XCTAssertTrue(
                source.identifier.breadthFirstSearch(
                    options: .outputs
                ) { $0 == output.identifier }
            )
            XCTAssertEqual(output.value, 42)
            XCTAssertEqual(recorder.evaluationCount, 2)
        }
    }

    func testUpdateValueRegistersDependencyWithoutReadingThePayload() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let intermediateRecorder = MutableRuleRecorder()
        let consumerRecorder = MutableRuleRecorder()

        ref.withCurrent {
            let source = Attribute(value: 1)
            let intermediate = graph.makeRule {
                intermediateRecorder.evaluationCount += 1
                return UpdateOnlyPayload(source: source.value)
            }
            let consumer = graph.makeRule {
                consumerRecorder.evaluationCount += 1
                intermediate.updateValue()
                return 42
            }

            XCTAssertEqual(consumer.value, 42)
            XCTAssertEqual(intermediateRecorder.evaluationCount, 1)
            XCTAssertEqual(consumerRecorder.evaluationCount, 1)

            source.value = 2
            XCTAssertEqual(consumer.value, 42)
            XCTAssertEqual(intermediateRecorder.evaluationCount, 2)
            XCTAssertEqual(consumerRecorder.evaluationCount, 2)
        }
    }

    func testRepeatedDynamicReadsReuseOneInputEdge() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 3)
            let output = graph.makeRule {
                source.value + source.value
            }

            XCTAssertEqual(output.value, 6)
            let outputIndex = Int(output.identifier.rawValue)
            let sourceIndex = Int(source.identifier.rawValue)
            XCTAssertEqual(
                graph.slots[outputIndex].node!.inputs.filter {
                    $0.attribute == source.identifier.rawValue
                }.count,
                1
            )
            XCTAssertEqual(
                graph.slots[sourceIndex].node!.outputs.filter {
                    $0 == output.identifier.rawValue
                }.count,
                1
            )

            source.setValue(4)
            XCTAssertEqual(output.value, 8)
            XCTAssertEqual(
                graph.slots[outputIndex].node!.inputs.filter {
                    $0.attribute == source.identifier.rawValue
                }.count,
                1
            )
            XCTAssertEqual(
                graph.slots[sourceIndex].node!.outputs.filter {
                    $0 == output.identifier.rawValue
                }.count,
                1
            )
        }
    }

    func testConditionalDynamicReadReplacesItsStaleInputEdge() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let selector = graph.makeInput(value: true)
            let left = graph.makeInput(value: 11)
            let right = graph.makeInput(value: 29)
            let output = graph.makeRule {
                selector.value ? left.value : right.value
            }

            XCTAssertEqual(output.value, 11)
            let outputIndex = Int(output.identifier.rawValue)
            XCTAssertTrue(
                graph.slots[outputIndex].node!.inputs.contains {
                    $0.attribute == left.identifier.rawValue
                }
            )
            XCTAssertFalse(
                graph.slots[outputIndex].node!.inputs.contains {
                    $0.attribute == right.identifier.rawValue
                }
            )

            selector.setValue(false)
            XCTAssertEqual(output.value, 29)
            XCTAssertFalse(
                graph.slots[outputIndex].node!.inputs.contains {
                    $0.attribute == left.identifier.rawValue
                }
            )
            XCTAssertTrue(
                graph.slots[outputIndex].node!.inputs.contains {
                    $0.attribute == right.identifier.rawValue
                }
            )
            XCTAssertFalse(
                graph.slots[Int(left.identifier.rawValue)].node!.outputs
                    .contains(output.identifier.rawValue)
            )
            XCTAssertEqual(
                graph.slots[Int(right.identifier.rawValue)].node!.outputs
                    .filter { $0 == output.identifier.rawValue }.count,
                1
            )
        }
    }

    func testRepeatedExplicitInputsPreserveRepeatedEdgeRecords() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let output = graph.makeRule { 42 }
            XCTAssertEqual(output.value, 42)

            output.addInput(
                source,
                options: [],
                token: 0
            )
            output.addInput(
                source,
                options: [],
                token: 1
            )

            XCTAssertEqual(
                graph.slots[Int(output.identifier.rawValue)].node!.inputs
                    .filter { $0.attribute == source.identifier.rawValue }.count,
                2
            )
            XCTAssertEqual(
                graph.slots[Int(source.identifier.rawValue)].node!.outputs
                    .filter { $0 == output.identifier.rawValue }.count,
                2
            )
        }
    }

    func testFixedProjectionKeepsOnePermanentInputEdge() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(
                value: KeyPathChangedInputPair(first: 1, second: 10)
            )
            let projection = graph.subscriptNode(
                parent: source,
                keyPath: \.first
            )
            let projectionIndex = Int(projection.identifier.rawValue)

            XCTAssertEqual(projection.value, 1)
            XCTAssertEqual(
                graph.slots[projectionIndex].node!.inputs.count,
                1
            )
            XCTAssertEqual(
                graph.slots[projectionIndex].node!.inputs[0].attribute,
                source.identifier.rawValue
            )
            XCTAssertNotEqual(
                graph.slots[projectionIndex].node!.inputs[0].flags
                    & _AGGraph.InputEdge.permanent,
                0
            )

            source.setValue(
                KeyPathChangedInputPair(first: 2, second: 20)
            )
            XCTAssertEqual(projection.value, 2)
            XCTAssertEqual(
                graph.slots[projectionIndex].node!.inputs.count,
                1
            )
        }
    }

    func testKeyPathProjectionHasConstructionLocalSubgraphLifetime() {
        // ASSERTIONS attributeGraphProjectionSubgraphLifetimeObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let sourceSubgraph = AGSubgraph()
            let source = AGSubgraph.withCurrent(sourceSubgraph) {
                graph.makeInput(
                    value: KeyPathChangedInputPair(first: 1, second: 10)
                )
            }

            let firstSubgraph = AGSubgraph()
            let (first, repeatedFirst) = AGSubgraph.withCurrent(firstSubgraph) {
                (
                    graph.subscriptNode(parent: source, keyPath: \.second),
                    graph.subscriptNode(parent: source, keyPath: \.second)
                )
            }
            let secondSubgraph = AGSubgraph()
            let second = AGSubgraph.withCurrent(secondSubgraph) {
                graph.subscriptNode(parent: source, keyPath: \.second)
            }

            XCTAssertNotEqual(first.identifier, repeatedFirst.identifier)
            XCTAssertNotEqual(first.identifier, second.identifier)
            XCTAssertNotEqual(repeatedFirst.identifier, second.identifier)
            XCTAssertTrue(
                graph.subgraph(for: first.identifier) === firstSubgraph
            )
            XCTAssertTrue(
                graph.subgraph(for: repeatedFirst.identifier) === firstSubgraph
            )
            XCTAssertTrue(
                graph.subgraph(for: second.identifier) === secondSubgraph
            )
            XCTAssertEqual(first.value, 10)
            XCTAssertEqual(repeatedFirst.value, 10)
            XCTAssertEqual(second.value, 10)

            let firstID = Int(first.identifier.rawValue)
            let repeatedFirstID = Int(repeatedFirst.identifier.rawValue)
            firstSubgraph.invalidate()

            XCTAssertNil(graph.slots[firstID].node)
            XCTAssertNil(graph.slots[repeatedFirstID].node)
            XCTAssertEqual(second.value, 10)
            XCTAssertTrue(secondSubgraph.isValid)
        }
    }

    func testSubgraphAssociationIsWeakAndSlotReuseStartsUnassociated() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            weak var releasedSubgraph: AGSubgraphRef?
            let first: Attribute<Int>
            do {
                let subgraph = AGSubgraph()
                releasedSubgraph = subgraph
                first = AGSubgraph.withCurrent(subgraph) {
                    graph.makeInput(value: 1)
                }
                XCTAssertTrue(graph.subgraph(for: first.identifier) === subgraph)
            }

            XCTAssertNil(releasedSubgraph)
            XCTAssertNil(graph.subgraph(for: first.identifier))

            let firstID = first.identifier
            graph.removeNode(firstID)
            let replacement = graph.makeInput(value: 2)
            XCTAssertEqual(replacement.identifier.rawValue, firstID.rawValue)
            XCTAssertNil(graph.subgraph(for: replacement.identifier))
        }
    }

    func testBreadthFirstSearchChecksStartAndDeduplicatesCycles() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let first = Attribute(value: 1)
            let second = Attribute(value: 2)
            let third = Attribute(value: 3)
            first.addInput(second, options: [], token: 0)
            second.identifier.addInput(
                third.identifier,
                options: [],
                token: 0
            )
            third.addInput(first, options: [], token: 0)

            var visited: [AGAttribute] = []
            XCTAssertFalse(
                first.breadthFirstSearch(
                    options: [.inputs, .outputs]
                ) { attribute in
                    visited.append(attribute)
                    return false
                }
            )
            XCTAssertEqual(Set(visited), Set([
                first.identifier,
                second.identifier,
                third.identifier,
            ]))
            XCTAssertEqual(visited.count, 3)

            var startVisits = 0
            XCTAssertTrue(
                first.identifier.breadthFirstSearch(
                    options: []
                ) { attribute in
                    startVisits += 1
                    return attribute == first.identifier
                }
            )
            XCTAssertEqual(startVisits, 1)
        }
    }

    func testStatefulRuleValueSurfacePublishesOutput() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = StatefulValueRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 3)
            let output = graph.makeStatefulRule(
                ValuePublishingStatefulRule(source: source, recorder: recorder)
            )

            XCTAssertEqual(output.value, 3)
            XCTAssertEqual(recorder.hadValue, [false])

            source.setValue(5)
            XCTAssertEqual(output.value, 5)
            XCTAssertEqual(recorder.hadValue, [false, true])
        }
    }

    func testObservedAttributeDestroyRunsOnceOnNodeRemoval() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = ObservedDestroyRecorder()

        ref.withCurrent {
            let output = graph.makeStatefulRule(
                ObservedStatefulRule(recorder: recorder)
            )

            XCTAssertEqual(output.value, 1)
            graph.removeNode(output.identifier)
            XCTAssertEqual(recorder.destroyCount, 1)
        }
    }

    func testSubgraphInvalidationDestroysParentNewestNodesBeforeNewestChild() {
        // ASSERTIONS attributeGraphSubgraphDestructionOrderObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = ObservedDestroyOrderRecorder()

        ref.withCurrent {
            let parent = AGSubgraph()
            AGSubgraph.withCurrent(parent) {
                _ = graph.makeStatefulRule(
                    ObservedDestroyOrderRule(label: "parent first", recorder: recorder)
                )
                _ = graph.makeStatefulRule(
                    ObservedDestroyOrderRule(label: "parent second", recorder: recorder)
                )
            }
            let olderChild = AGSubgraph(parent: parent)
            AGSubgraph.withCurrent(olderChild) {
                _ = graph.makeStatefulRule(
                    ObservedDestroyOrderRule(label: "older child", recorder: recorder)
                )
            }
            let newerChild = AGSubgraph(parent: parent)
            AGSubgraph.withCurrent(newerChild) {
                _ = graph.makeStatefulRule(
                    ObservedDestroyOrderRule(label: "newer child", recorder: recorder)
                )
            }

            parent.invalidate()

            XCTAssertEqual(
                recorder.labels,
                [
                    "parent second",
                    "parent first",
                    "newer child",
                    "older child",
                ]
            )
        }
    }

    func testGraphCounterStartsAtZeroAndUnknownLanesReturnZero() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            XCTAssertEqual(graph.graphCounter(lane: 1), 0)
            XCTAssertEqual(graph.graphCounter(lane: 0), 0)
            XCTAssertEqual(graph.graphCounter(lane: 2), 0)
            XCTAssertEqual(TransactionID(graph: graph).value, 0)
        }
    }

    func testLazyRuleEvaluationAdvancesCounterOncePerTopLevelUpdate() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let derived = graph.makeRule {
                source.value + 1
            }

            XCTAssertEqual(graph.graphCounter(lane: 1), 0)
            XCTAssertEqual(derived.value, 2)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)
            XCTAssertEqual(derived.value, 2)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)

            source.setValue(2)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)
            XCTAssertEqual(derived.value, 3)
            XCTAssertEqual(graph.graphCounter(lane: 1), 2)
            XCTAssertEqual(TransactionID(graph: graph).value, 2)
        }
    }

    func testNestedRuleEvaluationAdvancesCounterOnlyOnce() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let child = graph.makeRule {
                source.value + 1
            }
            let parent = graph.makeRule {
                child.value + 1
            }

            XCTAssertEqual(parent.value, 3)
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)

            source.setValue(3)
            XCTAssertEqual(parent.value, 5)
            XCTAssertEqual(graph.graphCounter(lane: 1), 2)
        }
    }

    func testEstablishedDeepDependencyChainUpdatesIteratively() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            var output = source

            for depth in 1...4_096 {
                let input = output
                output = graph.makeRule {
                    input.value + 1
                }

                // Establish each edge without recursively pulling the entire chain.
                XCTAssertEqual(output.value, depth + 1)
            }

            source.setValue(2)

            XCTAssertEqual(output.value, 4_098)
        }
    }

    func testEagerSideEffectUsesEstablishedDependencyTraversal() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = NestedEvaluationDepthRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            var output = source

            for _ in 0..<64 {
                let input = output
                output = graph.makeRule {
                    recorder.depth += 1
                    recorder.maximumDepth = max(
                        recorder.maximumDepth,
                        recorder.depth
                    )
                    defer { recorder.depth -= 1 }
                    return input.value + 1
                }
            }

            var observed: [Int] = []
            graph.makeSideEffectRule {
                observed.append(output.value)
            }
            XCTAssertEqual(observed, [65])

            recorder.depth = 0
            recorder.maximumDepth = 0
            source.setValue(2)

            XCTAssertEqual(observed, [65, 66])
            XCTAssertEqual(recorder.maximumDepth, 1)
        }
    }

    func testUnevaluatedRuleChainUsesLightweightNestedPulls() async {
        let result = await Task.detached {
            let graph = _AGGraph()
            let ref = _AGGraphContext(graph: graph)

            return ref.withCurrent {
                let source = graph.makeInput(value: 1)
                var output = source

                for _ in 0..<64 {
                    let input = output
                    output = graph.makeRule {
                        input.value + 1
                    }
                }

                return output.value
            }
        }.value

        XCTAssertEqual(result, 65)
    }

    func testUnevaluatedDeepKeyPathChainUpdatesIteratively() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 42)
            var output = source

            for _ in 0..<4_096 {
                output = graph.subscriptNode(parent: output, keyPath: \.self)
            }

            XCTAssertEqual(output.value, 42)
        }
    }

    func testUnchangedIntermediateOutputStopsDownstreamEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let intermediate = graph.makeRule {
                recorder.intermediateEvaluations += 1
                return source.value.isMultiple(of: 2)
            }
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return intermediate.value ? "even" : "odd"
            }

            XCTAssertEqual(downstream.value, "odd")
            XCTAssertEqual(recorder.intermediateEvaluations, 1)
            XCTAssertEqual(recorder.downstreamEvaluations, 1)

            source.setValue(3)

            XCTAssertEqual(downstream.value, "odd")
            XCTAssertEqual(recorder.intermediateEvaluations, 2)
            XCTAssertEqual(recorder.downstreamEvaluations, 1)
        }
    }

    func testChangedIntermediateOutputReevaluatesDownstream() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let intermediate = graph.makeRule {
                recorder.intermediateEvaluations += 1
                return source.value.isMultiple(of: 2)
            }
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return intermediate.value ? "even" : "odd"
            }

            XCTAssertEqual(downstream.value, "odd")
            source.setValue(2)

            XCTAssertEqual(downstream.value, "even")
            XCTAssertEqual(recorder.intermediateEvaluations, 2)
            XCTAssertEqual(recorder.downstreamEvaluations, 2)
        }
    }

    func testChangedComputedValueDoesNotTransitivelyInvalidateLateOutputCycle() throws {
        // ASSERTIONS attributeGraphLateOutputCycleCacheObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let storage = LateOutputStorage()

        try ref.withCurrent {
            let source = graph.makeInput(value: true)
            let owner = graph.makeStatefulRule(
                LateOutputOwnerRule(source: source, storage: storage),
                initialValue: 0
            )
            storage.owner = owner

            XCTAssertEqual(owner.value, 1)
            let downstream = try XCTUnwrap(storage.downstream)
            XCTAssertEqual(downstream.value, 1)
            XCTAssertEqual(storage.childEvaluations, 1)
            XCTAssertEqual(storage.downstreamEvaluations, 1)
        }
    }

    func testNonEquatableInputUsesGraphValueComparison() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: NonEquatableInput(value: 1))
            let output = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return source.value.value
            }

            XCTAssertEqual(output.value, 1)
            XCTAssertEqual(recorder.downstreamEvaluations, 1)

            source.setValue(NonEquatableInput(value: 1))
            XCTAssertEqual(output.value, 1)
            XCTAssertEqual(recorder.downstreamEvaluations, 1)

            source.setValue(NonEquatableInput(value: 2))
            XCTAssertEqual(output.value, 2)
            XCTAssertEqual(recorder.downstreamEvaluations, 2)
        }
    }

    func testTypeDescriptorEqualitySuppressesEquivalentRuleOutput() {
        // ASSERTIONS: viewSizeTypeDescriptorEqualityObserved
        // ASSERTIONS: viewGeometryTypeDescriptorEqualityObserved
        // ASSERTIONS: viewTransformTypeDescriptorEqualityObserved
        func requireDescriptorEquality<T: _AGTypeDescriptorEquatable>(
            _ type: T.Type
        ) {}
        requireDescriptorEquality(ViewSize.self)
        requireDescriptorEquality(ViewGeometry.self)
        requireDescriptorEquality(ViewTransform.self)

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()
        DescriptorEquatableOutput.equalityCallCount = 0

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let intermediate = graph.makeRule(
                DescriptorEquatableOutputRule(
                    source: source,
                    recorder: recorder
                )
            )
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return intermediate.value.semanticValue
            }

            XCTAssertEqual(downstream.value, 1)
            source.setValue(11)

            XCTAssertEqual(downstream.value, 1)
            XCTAssertEqual(recorder.intermediateEvaluations, 2)
            XCTAssertEqual(recorder.downstreamEvaluations, 1)
            XCTAssertGreaterThan(DescriptorEquatableOutput.equalityCallCount, 0)

            source.setValue(2)

            XCTAssertEqual(downstream.value, 2)
            XCTAssertEqual(recorder.intermediateEvaluations, 3)
            XCTAssertEqual(recorder.downstreamEvaluations, 2)
        }
    }

    func testTextDescriptorEqualitySuppressesEquivalentRuleOutput() {
        // ASSERTIONS: textAttributeGraphComparisonObserved
        func requireDescriptorEquality<T: _AGTypeDescriptorEquatable>(
            _ type: T.Type
        ) {}
        requireDescriptorEquality(Text.self)

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let intermediate = graph.makeRule(
                TextDescriptorOutputRule(source: source)
            )
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return intermediate.value
            }

            XCTAssertEqual(downstream.value, Text("Static"))
            source.setValue(11)

            XCTAssertEqual(downstream.value, Text("Static"))
            XCTAssertEqual(recorder.downstreamEvaluations, 1)

            source.setValue(2)

            XCTAssertEqual(downstream.value, Text("Changed"))
            XCTAssertEqual(recorder.downstreamEvaluations, 2)
        }
    }

    func testTypedOffsetSuppressesAnEquivalentProjectedTextField() {
        // ASSERTIONS: attributeGraphTypedOffsetFieldComparisonObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let carrier = graph.makeRule(
                OffsetTextCarrierRule(source: source)
            )
            let textOffset = MemoryLayout<OffsetTextCarrier>.offset(
                of: \OffsetTextCarrier.text
            )!
            let projectedText = carrier.unsafeOffset(
                at: textOffset,
                as: Text.self
            )
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return projectedText.value
            }

            XCTAssertEqual(downstream.value, Text("Static"))
            XCTAssertEqual(recorder.downstreamEvaluations, 1)

            source.setValue(2)
            XCTAssertEqual(downstream.value, Text("Static"))
            XCTAssertEqual(recorder.downstreamEvaluations, 1)

            source.setValue(3)
            XCTAssertEqual(downstream.value, Text("Changed"))
            XCTAssertEqual(recorder.downstreamEvaluations, 2)
        }
    }

    func testGenericEquatableRuleOutputDoesNotDispatchEqualityWitness() {
        // ASSERTIONS: attributeGraphRuleOutputGenericEquatableNotDispatchedObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()
        GenericEquatableOutput.equalityCallCount = 0

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let intermediate = graph.makeRule(
                GenericEquatableOutputRule(
                    source: source,
                    recorder: recorder
                )
            )
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return intermediate.value.semanticValue
            }

            XCTAssertEqual(downstream.value, 1)
            source.setValue(11)

            XCTAssertEqual(downstream.value, 1)
            XCTAssertEqual(recorder.intermediateEvaluations, 2)
            XCTAssertEqual(recorder.downstreamEvaluations, 2)
            XCTAssertEqual(GenericEquatableOutput.equalityCallCount, 0)
        }
    }

    func testStatefulRuleWithoutPublishedOutputStopsDownstreamEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 0)
            let intermediate = graph.makeStatefulRule(
                ConditionalOutputRule(source: source, recorder: recorder)
            )
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return intermediate.value + 1
            }

            XCTAssertEqual(downstream.value, 8)
            source.setValue(1)

            XCTAssertEqual(downstream.value, 8)
            XCTAssertEqual(recorder.intermediateEvaluations, 2)
            XCTAssertEqual(recorder.downstreamEvaluations, 1)
        }
    }

    func testUnchangedKeyPathProjectionStopsDownstreamEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutputPropagationRecorder()

        ref.withCurrent {
            let source = graph.makeInput(
                value: KeyPathChangedInputPair(first: 1, second: 10)
            )
            let first = graph.subscriptNode(parent: source, keyPath: \.first)
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return first.value + 1
            }

            XCTAssertEqual(downstream.value, 2)
            source.setValue(KeyPathChangedInputPair(first: 1, second: 20))

            XCTAssertEqual(downstream.value, 2)
            XCTAssertEqual(recorder.downstreamEvaluations, 1)
        }
    }

    func testTypedRuleBodyCanBeMutatedBeforeAndAfterFirstEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = MutableRuleRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 2)
            let output = graph.makeRule(
                MutableRule(source: source, offset: 1, recorder: recorder)
            )

            output.mutateBody(as: MutableRule.self, invalidating: false) { rule in
                rule.offset = 3
            }
            XCTAssertEqual(recorder.evaluationCount, 0)
            XCTAssertEqual(output.value, 5)
            XCTAssertEqual(recorder.evaluationCount, 1)

            output.mutateBody(
                as: MutableRule.self,
                invalidating: true
            ) { rule in
                rule.offset = 4
            }
            XCTAssertEqual(output.value, 6)
            XCTAssertEqual(recorder.evaluationCount, 2)

            source.setValue(5)
            XCTAssertEqual(output.value, 9)
            XCTAssertEqual(recorder.evaluationCount, 3)
        }
    }

    func testRawAttributeSetValueDoesNotCaptureAmbientTransaction() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            var transaction = Transaction()
            transaction.disablesAnimations = true

            withTransaction(transaction) {
                XCTAssertTrue(source.setValue(2))
            }
            XCTAssertNil(graph.transaction(for: source.identifier))

            XCTAssertTrue(source.setValue(3, transaction: transaction))
            XCTAssertEqual(
                graph.transaction(for: source.identifier)?.disablesAnimations,
                true
            )
        }
    }

    func testSideEffectRuleEvaluationAdvancesCounterPerSynchronousRun() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            var observed: [Int] = []

            graph.makeSideEffectRule {
                observed.append(source.value)
            }

            XCTAssertEqual(observed, [1])
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)

            source.setValue(2)

            XCTAssertEqual(observed, [1, 2])
            XCTAssertEqual(graph.graphCounter(lane: 1), 2)
            XCTAssertEqual(TransactionID(graph: graph).value, 2)
        }
    }

    func testInputMutationMarksAllOutgoingEdgesBeforeEagerSideEffectEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = OutgoingEdgeBatchRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            var sideEffectIDs: [UInt32] = []
            for _ in 0..<4 {
                let sideEffect = graph.makeSideEffectRule {
                    let value = source.value
                    if value == 2, recorder.allOutputsWereDirty == nil {
                        recorder.allOutputsWereDirty = recorder.outputIDs.allSatisfy { rawID in
                            graph.slots[Int(rawID)].node?.needsEvaluation == true
                        }
                    }
                }
                sideEffectIDs.append(sideEffect.identifier.rawValue)
            }
            recorder.outputIDs = sideEffectIDs

            source.setValue(2)
        }

        XCTAssertEqual(recorder.allOutputsWereDirty, true)
    }

    func testDiamondInvalidationMarksEveryChangedInputBeforeDeduplicatingNode() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let first = graph.makeRule {
                source.value + 10
            }
            let second = graph.makeRule {
                source.value + 20
            }
            let output = graph.makeRule {
                first.value + second.value
            }

            XCTAssertEqual(output.value, 32)

            source.setValue(2)

            let outputIndex = Int(output.identifier.rawValue)
            let changedInputs = Set(
                graph.slots[outputIndex].node!.inputs.compactMap { input in
                    input.flags & _AGGraph.InputEdge.changed != 0
                        ? input.attribute
                        : nil
                }
            )
            XCTAssertEqual(changedInputs, Set([
                first.identifier.rawValue,
                second.identifier.rawValue,
            ]))
            XCTAssertTrue(graph.slots[outputIndex].node!.needsEvaluation)
            XCTAssertEqual(output.value, 34)
        }
    }

    // ASSERTIONS attributeGraphDirtyPendingPropagationObserved
    func testChangedComputedOutputMarksEveryRepeatedDirectEdgeRecord() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let intermediate = graph.makeRule {
                source.value * 2
            }
            let output = graph.makeRule {
                intermediate.value + 1
            }

            XCTAssertEqual(output.value, 3)
            output.addInput(intermediate, options: [], token: 1)

            let intermediateID = intermediate.identifier.rawValue
            let intermediateIndex = Int(intermediateID)
            let outputIndex = Int(output.identifier.rawValue)
            XCTAssertEqual(
                graph.slots[intermediateIndex].node!.outputs.filter {
                    $0 == output.identifier.rawValue
                }.count,
                2
            )

            source.setValue(2)
            for edgeIndex in graph.slots[outputIndex].node!.inputs.indices
            where graph.slots[outputIndex].node!.inputs[edgeIndex].attribute
                == intermediateID {
                graph.slots[outputIndex].node!.inputs[edgeIndex].flags &=
                    ~_AGGraph.InputEdge.changed
            }

            XCTAssertEqual(intermediate.value, 4)
            let repeatedEdges = graph.slots[outputIndex].node!.inputs.filter {
                $0.attribute == intermediateID
            }
            XCTAssertEqual(repeatedEdges.count, 2)
            XCTAssertTrue(repeatedEdges.allSatisfy {
                $0.flags & _AGGraph.InputEdge.changed != 0
            })
        }
    }

    // ASSERTIONS attributeGraphDirtyTransitionGateObserved
    func testRepeatedInvalidationStopsAtAlreadyDirtyDependent() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let first = graph.makeInput(value: 1)
            let second = graph.makeInput(value: 10)
            let shared = graph.makeRule {
                first.value + second.value
            }
            let downstream = graph.makeRule {
                shared.value * 2
            }

            XCTAssertEqual(downstream.value, 22)

            first.setValue(2)
            let downstreamIndex = Int(downstream.identifier.rawValue)
            let firstTraversal = graph.slots[downstreamIndex].node!
                .invalidationTraversal
            XCTAssertTrue(graph.slots[downstreamIndex].node!.needsEvaluation)

            second.setValue(20)

            XCTAssertEqual(
                graph.slots[downstreamIndex].node!.invalidationTraversal,
                firstTraversal,
                "An already-dirty shared node must stop repeated descendant traversal."
            )
            let sharedIndex = Int(shared.identifier.rawValue)
            let changedInputs = Set(
                graph.slots[sharedIndex].node!.inputs.compactMap { input in
                    input.flags & _AGGraph.InputEdge.changed != 0
                        ? input.attribute
                        : nil
                }
            )
            XCTAssertEqual(changedInputs, Set([
                first.identifier.rawValue,
                second.identifier.rawValue,
            ]))
            XCTAssertEqual(downstream.value, 44)
        }
    }

    func testSideEffectCreatedDuringEvaluationRunsFromGraphWorkList() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 7)
            var events: [String] = []
            let producer = graph.makeRule {
                events.append("producer.begin")
                graph.makeSideEffectRule {
                    events.append("sideEffect.\(source.value)")
                }
                events.append("producer.end")
                return 1
            }

            XCTAssertEqual(producer.value, 1)
            XCTAssertEqual(
                events,
                ["producer.begin", "producer.end", "sideEffect.7"]
            )
            XCTAssertEqual(graph.graphCounter(lane: 1), 1)
        }
    }

    func testSideEffectCreatedDuringAnotherGraphUpdateWaitsForOwnGraphUpdate() {
        let outerGraph = _AGGraph()
        let outerRef = _AGGraphContext(graph: outerGraph)
        let innerGraph = _AGGraph()
        let innerRef = _AGGraphContext(graph: innerGraph)
        var events: [String] = []

        outerRef.withCurrent {
            let producer = outerGraph.makeRule {
                events.append("outer.begin")
                _ = innerRef.withCurrent {
                    innerGraph.makeSideEffectRule {
                        events.append("inner.sideEffect")
                    }
                }
                events.append("outer.end")
                return 1
            }

            XCTAssertEqual(producer.value, 1)
        }

        XCTAssertEqual(events, ["outer.begin", "outer.end"])

        innerRef.withCurrent {
            let trigger = innerGraph.makeRule { 1 }
            XCTAssertEqual(trigger.value, 1)
        }

        XCTAssertEqual(
            events,
            ["outer.begin", "outer.end", "inner.sideEffect"]
        )
    }

    func testEagerSideEffectDoesNotReenterWhileDependencyMutatesDuringEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: 0)
            let derived = graph.makeRule {
                let value = source.value
                if value == 0 {
                    source.setValue(1)
                }
                return source.value + 10
            }
            var observed: [Int] = []

            graph.makeSideEffectRule {
                observed.append(derived.value)
            }

            XCTAssertEqual(observed, [11])
            XCTAssertEqual(derived.value, 11)
        }
    }

    func testRuleContextUpdateDefersInvalidatedSideEffectsToNextGraphUpdate() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let owner = graph.makeRule { 0 }
            let source = graph.makeInput(value: 0)
            var events: [String] = []

            graph.makeSideEffectRule {
                events.append("sideEffect.\(source.value)")
            }
            events.removeAll()

            // ASSERTIONS ruleContextNativeUpdateScopeObserved
            AnyRuleContext(attribute: owner.identifier).update {
                events.append("update.begin")
                source.setValue(1)
                events.append("update.end")
                XCTAssertEqual(events, ["update.begin", "update.end"])
            }

            XCTAssertEqual(events, ["update.begin", "update.end"])
            XCTAssertEqual(owner.value, 0)
            XCTAssertEqual(
                events,
                ["update.begin", "update.end", "sideEffect.1"]
            )
        }
    }

    func testNestedDifferentGraphEvaluationAdvancesEachGraphCounter() {
        let outerGraph = _AGGraph()
        let outerRef = _AGGraphContext(graph: outerGraph)
        let innerGraph = _AGGraph()
        let innerRef = _AGGraphContext(graph: innerGraph)

        var innerSource: Attribute<Int>!
        var innerDerived: Attribute<Int>!

        innerRef.withCurrent {
            innerSource = innerGraph.makeInput(value: 2)
            innerDerived = innerGraph.makeRule {
                innerSource.value + 10
            }
        }

        outerRef.withCurrent {
            let outerTick = outerGraph.makeInput(value: 0)
            let outerDerived = outerGraph.makeRule {
                _ = outerTick.value
                return innerRef.withCurrent {
                    innerDerived.value
                } + 1
            }

            XCTAssertEqual(outerDerived.value, 13)
            XCTAssertEqual(outerGraph.graphCounter(lane: 1), 1)
            XCTAssertEqual(innerGraph.graphCounter(lane: 1), 1)

            innerRef.withCurrent {
                innerSource.setValue(3)
            }
            XCTAssertEqual(outerGraph.graphCounter(lane: 1), 1)
            XCTAssertEqual(innerGraph.graphCounter(lane: 1), 1)

            outerTick.setValue(1)
            XCTAssertEqual(outerDerived.value, 14)
            XCTAssertEqual(outerGraph.graphCounter(lane: 1), 2)
            XCTAssertEqual(innerGraph.graphCounter(lane: 1), 2)
        }
    }

    func testCurrentContextDoesNotPropagateToChildTask() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let probe = CurrentContextTaskProbe(graph: graph)

        ref.withCurrent {
            Task {
                probe.run()
            }
            XCTAssertEqual(probe.wait(), .success)
        }

        XCTAssertFalse(probe.observed)
    }

    func testCurrentContextTokenMapAllowsReturningToOuterGraph() {
        let outerGraph = _AGGraph()
        let outerRef = _AGGraphContext(graph: outerGraph)
        let innerGraph = _AGGraph()
        let innerRef = _AGGraphContext(graph: innerGraph)

        outerRef.withCurrent {
            XCTAssertTrue(_AGGraph.current === outerGraph)

            innerRef.withCurrent {
                XCTAssertTrue(_AGGraph.current === innerGraph)

                outerRef.withCurrent {
                    XCTAssertTrue(_AGGraph.current === outerGraph)
                }

                XCTAssertTrue(_AGGraph.current === innerGraph)
            }

            XCTAssertTrue(_AGGraph.current === outerGraph)
        }
    }

    func testParentInvalidationMarksKeyPathChildInputsChanged() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = KeyPathChangedInputRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: KeyPathChangedInputPair(first: 1, second: 10))
            let first = graph.subscriptNode(parent: source, keyPath: \.first)
            let second = graph.subscriptNode(parent: source, keyPath: \.second)
            let output = graph.makeStatefulRule(
                KeyPathChangedInputRule(
                    first: first,
                    second: second,
                    recorder: recorder
                )
            )

            XCTAssertEqual(output.value, 11)

            source.setValue(KeyPathChangedInputPair(first: 2, second: 20))
            XCTAssertEqual(output.value, 22)
        }

        XCTAssertEqual(
            recorder.snapshots,
            [
                KeyPathChangedInputSnapshot(firstChanged: false, secondChanged: false),
                KeyPathChangedInputSnapshot(firstChanged: true, secondChanged: true),
            ]
        )
    }

    func testContextAndAttributeChangedValueUseInputChangeFlag() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = ChangedValueRecorder()

        ref.withCurrent {
            let first = graph.makeInput(value: 1)
            let second = graph.makeInput(value: 10)
            let output = graph.makeStatefulRule(
                ChangedValueRule(
                    first: first,
                    second: second,
                    recorder: recorder
                )
            )

            XCTAssertEqual(output.value, 11)
            output.invalidateValue()
            XCTAssertEqual(output.value, 11)

            first.setValue(2)
            XCTAssertEqual(output.value, 12)
        }

        XCTAssertEqual(
            recorder.snapshots,
            [
                KeyPathChangedInputSnapshot(firstChanged: true, secondChanged: true),
                KeyPathChangedInputSnapshot(firstChanged: false, secondChanged: false),
                KeyPathChangedInputSnapshot(firstChanged: true, secondChanged: false),
            ]
        )
    }

    func testValueWithoutDependencySkipsInputEdgeAndRestoresRuleContext() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = TrackingIsolationRecorder()

        ref.withCurrent {
            let tracked = graph.makeInput(value: 1)
            let isolated = graph.makeInput(value: 10)
            let output = graph.makeStatefulRule(
                TrackingIsolationRule(
                    tracked: tracked,
                    isolated: isolated,
                    recorder: recorder
                )
            )

            XCTAssertEqual(output.value, 11)
            XCTAssertEqual(recorder.values, [11])

            isolated.setValue(20)
            XCTAssertEqual(output.value, 11)
            XCTAssertEqual(recorder.values, [11])

            tracked.setValue(2)
            XCTAssertEqual(output.value, 22)
            XCTAssertEqual(recorder.values, [11, 22])
        }
    }

    func testStatefulBodySupportsNestedMutationDuringDependencyEvaluation() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let target = ReentrantStatefulMutationTarget()

        ref.withCurrent {
            let dependency: Attribute<Int> = graph.makeRule {
                guard let attribute = target.attribute else {
                    XCTFail("missing stateful target")
                    return 0
                }
                graph.mutateStatefulRule(
                    attribute,
                    as: ReentrantStatefulMutationRule.self,
                    invalidating: true
                ) {
                    $0.offset = 40
                }
                return 2
            }
            let output = graph.makeStatefulRule(
                ReentrantStatefulMutationRule(dependency: dependency)
            )
            target.attribute = output.identifier

            XCTAssertEqual(output.value, 42)
        }
    }

    func testDetachedIndirectAttributeRestoresItsOriginalDefaultValue() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let placeholder = graph.makeIndirectAttribute(defaultValue: 7)
            let concrete = graph.makeInput(value: 42)

            XCTAssertEqual(placeholder.value, 7)
            graph.setIndirectTarget(placeholder, to: concrete)
            XCTAssertEqual(placeholder.value, 42)

            concrete.setValue(55)
            XCTAssertEqual(placeholder.value, 55)

            graph.setIndirectTarget(placeholder, to: nil)
            XCTAssertEqual(placeholder.value, 7)
        }
    }

    func testIndirectAttributeReusesTypedStorageForLargeValues() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = graph.makeInput(value: UpdateOnlyPayload(source: 1))
            let indirect = graph.makeIndirectAttribute(source: source)

            XCTAssertEqual(indirect.value, UpdateOnlyPayload(source: 1))
            let initialStorage = try! XCTUnwrap(
                graph.slots[Int(indirect.identifier.rawValue)].node?.value
                    as? _AGValueStorage<UpdateOnlyPayload>
            )
            let initialPointer = initialStorage.rawPointer

            source.setValue(UpdateOnlyPayload(source: 5))

            XCTAssertEqual(indirect.value, UpdateOnlyPayload(source: 5))
            let changedStorage = try! XCTUnwrap(
                graph.slots[Int(indirect.identifier.rawValue)].node?.value
                    as? _AGValueStorage<UpdateOnlyPayload>
            )
            XCTAssertTrue(initialStorage === changedStorage)
            XCTAssertEqual(initialPointer, changedStorage.rawPointer)
        }
    }

    func testCrossGraphReferenceReusesTypedStorageForLargeValues() {
        let sourceGraph = _AGGraph()
        let sourceRef = _AGGraphContext(graph: sourceGraph)
        let source = sourceRef.withCurrent {
            sourceGraph.makeInput(value: UpdateOnlyPayload(source: 1))
        }
        let targetGraph = _AGGraph()
        let targetRef = _AGGraphContext(graph: targetGraph)

        let reference = targetRef.withCurrent {
            targetGraph.makeCrossGraphRef(
                source: source,
                in: sourceGraph
            )
        }

        targetRef.withCurrent {
            XCTAssertEqual(reference.value, UpdateOnlyPayload(source: 1))
        }
        let initialStorage = try! XCTUnwrap(
            targetGraph.slots[Int(reference.identifier.rawValue)].node?.value
                as? _AGValueStorage<UpdateOnlyPayload>
        )
        let initialPointer = initialStorage.rawPointer

        _ = sourceRef.withCurrent {
            source.setValue(UpdateOnlyPayload(source: 5))
        }
        targetRef.withCurrent {
            targetGraph.inbox.drain()
            XCTAssertEqual(reference.value, UpdateOnlyPayload(source: 5))
        }

        let changedStorage = try! XCTUnwrap(
            targetGraph.slots[Int(reference.identifier.rawValue)].node?.value
                as? _AGValueStorage<UpdateOnlyPayload>
        )
        XCTAssertTrue(initialStorage === changedStorage)
        XCTAssertEqual(initialPointer, changedStorage.rawPointer)
    }

    func testRemovedIndirectSourceRestoresFallbackBeforeSlotReuse() {
        // ASSERTIONS attributeGraphIndirectTargetLifetimeObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let fallback = graph.makeInput(value: false)
            let indirect = graph.makeIndirectAttribute(source: fallback)
            let childSubgraph = AGSubgraph()
            let childSource = AGSubgraph.withCurrent(childSubgraph) {
                graph.makeInput(value: true)
            }

            graph.setIndirectTarget(indirect, to: childSource)
            XCTAssertTrue(indirect.value)
            XCTAssertEqual(
                graph.indirectTarget(indirect.identifier),
                childSource.identifier
            )

            let removedSlot = childSource.identifier.rawValue
            childSubgraph.invalidate()

            XCTAssertEqual(
                graph.indirectTarget(indirect.identifier),
                fallback.identifier
            )
            let replacement = graph.makeInput(value: 42)
            XCTAssertEqual(replacement.identifier.rawValue, removedSlot)
            XCTAssertFalse(indirect.value)
        }
    }

    func testUnevaluatedIndirectTargetIsDetachedWhenItsSourceIsRemoved() {
        // ASSERTIONS attributeGraphIndirectTargetLifetimeObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let fallback = graph.makeInput(value: false)
            let indirect = graph.makeIndirectAttribute(source: fallback)
            let childSubgraph = AGSubgraph()
            let childSource = AGSubgraph.withCurrent(childSubgraph) {
                graph.makeInput(value: true)
            }

            graph.setIndirectTarget(indirect, to: childSource)
            childSubgraph.invalidate()

            XCTAssertEqual(
                graph.indirectTarget(indirect.identifier),
                fallback.identifier
            )
            XCTAssertFalse(indirect.value)
        }
    }

    func testNilIndirectRetargetRestoresItsOriginalSource() {
        // ASSERTIONS attributeGraphIndirectTargetLifetimeObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let fallback = graph.makeInput(value: false)
            let indirect = graph.makeIndirectAttribute(source: fallback)
            let replacement = graph.makeInput(value: true)

            graph.setIndirectTarget(indirect, to: replacement)
            XCTAssertTrue(indirect.value)

            graph.setIndirectTarget(indirect.identifier, to: nil)
            XCTAssertEqual(
                graph.indirectTarget(indirect.identifier),
                fallback.identifier
            )
            XCTAssertFalse(indirect.value)
        }
    }

    func testHashableRuleCachedValueUsesAReusableUpdatingAttribute() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = Attribute(value: 3)
            let rule = CachedDoublingRule(source: source)
            let options: AGCachedValueOptions = []

            XCTAssertNil(rule.cachedValueIfExists(options: options, owner: nil))
            XCTAssertEqual(rule.cachedValue(options: options, owner: nil), 6)
            XCTAssertEqual(graph.cachedRuleEntries.count, 1)
            XCTAssertEqual(rule.cachedValue(options: options, owner: nil), 6)
            XCTAssertEqual(graph.cachedRuleEntries.count, 1)

            XCTAssertEqual(
                rule.cachedValue(
                    options: .prefetchInput,
                    owner: nil
                ),
                6
            )
            XCTAssertEqual(graph.cachedRuleEntries.count, 1)

            source.value = 4
            XCTAssertEqual(rule.cachedValueIfExists(options: options, owner: nil), 8)
            XCTAssertEqual(graph.cachedRuleEntries.count, 1)
        }
    }

    func testCachedRuleSubgraphRemovalPreservesUnrelatedCacheEntries() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let retainedSubgraph = AGSubgraph()
            let removedSubgraph = AGSubgraph()
            let retainedSource = AGSubgraph.withCurrent(retainedSubgraph) {
                graph.makeInput(value: 3)
            }
            let removedSource = AGSubgraph.withCurrent(removedSubgraph) {
                graph.makeInput(value: 5)
            }

            let retainedRule = CachedDoublingRule(source: retainedSource)
            let removedRule = CachedDoublingRule(source: removedSource)
            XCTAssertEqual(
                retainedRule.cachedValue(options: [], owner: retainedSource.identifier),
                6
            )
            XCTAssertEqual(
                removedRule.cachedValue(options: [], owner: removedSource.identifier),
                10
            )
            XCTAssertEqual(graph.cachedRuleEntries.count, 2)
            XCTAssertEqual(graph.cachedRuleKeysByAttribute.count, 2)

            removedSubgraph.invalidate()

            XCTAssertEqual(graph.cachedRuleEntries.count, 1)
            XCTAssertEqual(graph.cachedRuleKeysByAttribute.count, 1)
            XCTAssertEqual(
                retainedRule.cachedValue(options: [], owner: retainedSource.identifier),
                6
            )
            XCTAssertEqual(graph.cachedRuleEntries.count, 1)
            XCTAssertEqual(graph.cachedRuleKeysByAttribute.count, 1)
        }
    }

    func testCachedValuePrefetchesInputBeforeDecidingToEvaluateConsumer() {
        // ASSERTIONS attributeGraphCachedRuleInputPrefetchObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let prefetchedRecorder = MutableRuleRecorder()
        let deferredRecorder = MutableRuleRecorder()

        ref.withCurrent {
            let source = graph.makeInput(value: 1)
            let cachedRule = CachedParityRule(source: source)
            let prefetched = graph.makeRule {
                prefetchedRecorder.evaluationCount += 1
                return cachedRule.cachedValue(
                    options: .prefetchInput,
                    owner: nil
                )
            }
            let deferred = graph.makeRule {
                deferredRecorder.evaluationCount += 1
                return cachedRule.cachedValue(options: [], owner: nil)
            }

            XCTAssertEqual(prefetched.value, 1)
            XCTAssertEqual(deferred.value, 1)
            XCTAssertEqual(prefetchedRecorder.evaluationCount, 1)
            XCTAssertEqual(deferredRecorder.evaluationCount, 1)

            let prefetchedEdge = try! XCTUnwrap(
                graph.slots[Int(prefetched.identifier.rawValue)].node?.inputs
                    .first
            )
            let deferredEdge = try! XCTUnwrap(
                graph.slots[Int(deferred.identifier.rawValue)].node?.inputs
                    .first
            )
            XCTAssertEqual(
                prefetchedEdge.flags & _AGGraph.InputEdge.deferredUpdate,
                0
            )
            XCTAssertNotEqual(
                deferredEdge.flags & _AGGraph.InputEdge.deferredUpdate,
                0
            )

            source.setValue(3)
            let cachedNodeIndex = Int(prefetchedEdge.attribute)
            XCTAssertTrue(
                graph.slots[cachedNodeIndex].node!.needsEvaluation
            )

            XCTAssertEqual(prefetched.value, 1)
            XCTAssertEqual(prefetchedRecorder.evaluationCount, 1)
            XCTAssertFalse(
                graph.slots[cachedNodeIndex].node!.needsEvaluation
            )
            XCTAssertEqual(deferred.value, 1)
            XCTAssertEqual(deferredRecorder.evaluationCount, 2)
        }
    }

    func testSubgraphInvalidationDefersNodeDestructionUntilGraphUpdateCompletes() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = DeferredSubgraphInvalidationRecorder()

        ref.withCurrent {
            let subgraph = AGSubgraph()
            let source = AGSubgraph.withCurrent(subgraph) {
                graph.makeInput(value: 42)
            }
            let output = graph.makeStatefulRule(
                DeferredSubgraphInvalidationRule(
                    graph: graph,
                    subgraph: subgraph,
                    source: source,
                    recorder: recorder
                )
            )

            XCTAssertEqual(output.value, 42)
            XCTAssertFalse(subgraph.isValid)
            XCTAssertEqual(recorder.nodeWasPresentAfterInvalidation, [true])
            XCTAssertFalse(graph.hasNode(source.identifier))
        }
    }

    func testSubgraphUpdateDrainsPendingInvalidationAfterTraversal() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = DeferredSubgraphInvalidationRecorder()

        ref.withCurrent {
            let root = AGSubgraph()
            let child = AGSubgraph(parent: root)
            let output = AGSubgraph.withCurrent(child) {
                graph.makeStatefulRule(
                    DeferredSubgraphInvalidationRule(
                        graph: graph,
                        subgraph: child,
                        source: graph.makeInput(value: 42),
                        recorder: recorder
                    )
                )
            }
            output.identifier.setFlags(.transactional, mask: .transactional)

            root.update(flags: AGAttributeFlags.transactional.rawValue)

            XCTAssertEqual(recorder.nodeWasPresentAfterInvalidation, [true])
            XCTAssertFalse(child.isValid)
            XCTAssertFalse(graph.hasNode(output.identifier))
        }
    }

    func testSubgraphUpdateRevisitsEarlierNodeInvalidatedLaterInTraversal() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        let recorder = SubgraphUpdateValueRecorder()

        ref.withCurrent {
            let subgraph = AGSubgraph()
            let source = AGSubgraph.withCurrent(subgraph) {
                graph.makeInput(value: 1)
            }
            let mutator = AGSubgraph.withCurrent(subgraph) {
                graph.makeStatefulRule(
                    SubgraphUpdateSourceMutationRule(source: source)
                )
            }
            let output = AGSubgraph.withCurrent(subgraph) {
                graph.makeStatefulRule(
                    SubgraphUpdateRecordingRule(
                        source: source,
                        recorder: recorder
                    )
                )
            }
            output.identifier.setFlags(.transactional, mask: .transactional)
            mutator.identifier.setFlags(.transactional, mask: .transactional)

            subgraph.update(flags: AGAttributeFlags.transactional.rawValue)

            XCTAssertEqual(recorder.values, [1, 2])
            XCTAssertEqual(output.value, 2)
        }
    }

    func testSubgraphUpdateEvaluatesNewestRegisteredNodeFirst() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        var evaluations: [String] = []

        ref.withCurrent {
            let subgraph = AGSubgraph()
            let first = AGSubgraph.withCurrent(subgraph) {
                graph.makeRule {
                    evaluations.append("first")
                    return 1
                }
            }
            let second = AGSubgraph.withCurrent(subgraph) {
                graph.makeRule {
                    evaluations.append("second")
                    return 2
                }
            }
            first.identifier.setFlags(.transactional, mask: .transactional)
            second.identifier.setFlags(.transactional, mask: .transactional)

            subgraph.update(flags: AGAttributeFlags.transactional.rawValue)

            XCTAssertEqual(evaluations, ["second", "first"])
        }
    }
}

private struct StoredProjectionRoot {
    var value: Int
}

private struct ComputedProjectionRoot {
    var storedValue: Int
    var computedValue: Int { storedValue + 1 }
}

private struct UpdateOnlyPayload: Equatable {
    var first: Int
    var second: Int
    var third: Int
    var fourth: Int

    init(source: Int) {
        first = source
        second = source &+ 1
        third = source &+ 2
        fourth = source &+ 3
    }
}

private final class AGGraphContextToken {}

private struct KeyPathChangedInputPair: Equatable {
    var first: Int
    var second: Int
}

private struct DefaultAttributeBody: _AttributeBody {}

private struct AsyncAttributeBody: AsyncAttribute {}

private final class RuleInitialValueRecorder {
    var evaluationCount = 0
}

private struct RuleWithInitialValue: Rule {
    static var initialValue: Int? { 41 }

    var recorder: RuleInitialValueRecorder

    var value: Int {
        recorder.evaluationCount += 1
        return 42
    }
}

private struct CachedDoublingRule: Rule, Hashable {
    var source: Attribute<Int>

    var value: Int {
        source.value * 2
    }
}

private struct CachedParityRule: Rule, Hashable {
    var source: Attribute<Int>

    var value: Int {
        source.value & 1
    }
}

private final class DeferredSubgraphInvalidationRecorder {
    var nodeWasPresentAfterInvalidation: [Bool] = []
}

private struct DeferredSubgraphInvalidationRule: StatefulRule {
    typealias Value = Int

    var graph: _AGGraph
    var subgraph: AGSubgraph
    var source: Attribute<Int>
    var recorder: DeferredSubgraphInvalidationRecorder

    mutating func updateValue() {
        subgraph.invalidate()
        recorder.nodeWasPresentAfterInvalidation.append(
            graph.hasNode(source.identifier)
        )
        value = source.value
    }
}

private final class SubgraphUpdateValueRecorder {
    var values: [Int] = []
}

private struct SubgraphUpdateRecordingRule: StatefulRule {
    typealias Value = Int

    var source: Attribute<Int>
    var recorder: SubgraphUpdateValueRecorder

    mutating func updateValue() {
        let value = source.value
        recorder.values.append(value)
        self.value = value
    }
}

private struct SubgraphUpdateSourceMutationRule: StatefulRule {
    typealias Value = Void

    var source: Attribute<Int>

    mutating func updateValue() {
        source.setValue(2)
        value = ()
    }
}

private final class StatefulValueRecorder {
    var hadValue: [Bool] = []
}

private struct LowLevelDoublingBody: _AttributeBody {
    var source: Attribute<Int>

    static func update(
        _ body: UnsafeMutableRawPointer,
        _ attribute: AGAttribute
    ) {
        _ = attribute
        let body = body.assumingMemoryBound(to: Self.self).pointee
        _AGGraph.setStatefulOutput(body.source.value * 2)
    }
}

private struct ValuePublishingStatefulRule: StatefulRule {
    typealias Value = Int

    var source: Attribute<Int>
    var recorder: StatefulValueRecorder

    mutating func updateValue() {
        recorder.hadValue.append(hasValue)
        value = source.value
    }
}

private final class ObservedDestroyRecorder {
    var destroyCount = 0
}

private final class ObservedDestroyOrderRecorder {
    var labels: [String] = []
}

private struct ObservedStatefulRule: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = Int

    var recorder: ObservedDestroyRecorder

    mutating func updateValue() {
        value = 1
    }

    mutating func destroy() {
        recorder.destroyCount += 1
    }
}

private struct ObservedDestroyOrderRule: StatefulRule, ObservedAttribute {
    typealias Value = Int

    var label: String
    var recorder: ObservedDestroyOrderRecorder

    mutating func updateValue() {
        value = 1
    }

    mutating func destroy() {
        recorder.labels.append(label)
    }
}

private struct NonEquatableInput {
    var value: Int
}

private struct DescriptorEquatableOutput: Equatable, _AGTypeDescriptorEquatable {
    nonisolated(unsafe) static var equalityCallCount = 0

    var semanticValue: Int
    var ignoredValue: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        equalityCallCount += 1
        return lhs.semanticValue == rhs.semanticValue
    }
}

private struct DescriptorEquatableOutputRule: Rule {
    var source: Attribute<Int>
    var recorder: OutputPropagationRecorder

    var value: DescriptorEquatableOutput {
        recorder.intermediateEvaluations += 1
        return DescriptorEquatableOutput(
            semanticValue: source.value % 10,
            ignoredValue: source.value
        )
    }
}

private struct TextDescriptorOutputRule: Rule {
    var source: Attribute<Int>

    var value: Text {
        source.value == 2 ? Text("Changed") : Text("Static")
    }
}

private struct OffsetTextCarrier {
    var text: Text
    var marker: Int
}

private struct OffsetTextCarrierRule: Rule {
    var source: Attribute<Int>

    var value: OffsetTextCarrier {
        let input = source.value
        return OffsetTextCarrier(
            text: input == 3 ? Text("Changed") : Text("Static"),
            marker: input
        )
    }
}

private struct GenericEquatableOutput: Equatable {
    nonisolated(unsafe) static var equalityCallCount = 0

    var semanticValue: Int
    var ignoredValue: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        equalityCallCount += 1
        return lhs.semanticValue == rhs.semanticValue
    }
}

private struct GenericEquatableOutputRule: Rule {
    var source: Attribute<Int>
    var recorder: OutputPropagationRecorder

    var value: GenericEquatableOutput {
        recorder.intermediateEvaluations += 1
        return GenericEquatableOutput(
            semanticValue: source.value % 10,
            ignoredValue: source.value
        )
    }
}

private final class OutputPropagationRecorder {
    var intermediateEvaluations = 0
    var downstreamEvaluations = 0
    var sideEffectEvaluations = 0
}

private final class LateOutputStorage {
    var owner: Attribute<Int>?
    var downstream: Attribute<Int>?
    var childEvaluations = 0
    var downstreamEvaluations = 0
}

private struct LateOutputOwnerRule: StatefulRule {
    typealias Value = Int

    var source: Attribute<Bool>
    var storage: LateOutputStorage

    mutating func updateValue() {
        guard source.value else {
            value = 0
            return
        }
        if storage.downstream == nil {
            guard let graph = _AGGraph.current,
                  let owner = storage.owner else {
                preconditionFailure(
                    "Late output construction requires its owner attribute."
                )
            }
            let recorder = storage
            let child = graph.makeRule {
                recorder.childEvaluations += 1
                return owner.value
            }
            let downstream = graph.makeRule {
                recorder.downstreamEvaluations += 1
                return child.value + 1
            }
            // Cache the owner's fallback through an edge that did not exist
            // when this evaluation was originally invalidated.
            _ = downstream.value
            storage.downstream = downstream
        }
        value = 1
    }
}

private final class NestedEvaluationDepthRecorder {
    var depth = 0
    var maximumDepth = 0
}

private final class OutgoingEdgeBatchRecorder {
    var outputIDs: [UInt32] = []
    var allOutputsWereDirty: Bool?
}

private struct ConditionalOutputRule: StatefulRule {
    typealias Value = Int

    var source: Attribute<Int>
    var recorder: OutputPropagationRecorder

    mutating func updateValue() {
        recorder.intermediateEvaluations += 1
        guard source.value == 0 else { return }
        _AGGraph.setStatefulOutput(7)
    }
}

private final class MutableRuleRecorder {
    var evaluationCount = 0
}

private struct MutableRule: Rule {
    var source: Attribute<Int>
    var offset: Int
    var recorder: MutableRuleRecorder

    var value: Int {
        recorder.evaluationCount += 1
        return source.value + offset
    }
}

private struct KeyPathChangedInputSnapshot: Equatable {
    var firstChanged: Bool
    var secondChanged: Bool
}

private final class KeyPathChangedInputRecorder {
    var snapshots: [KeyPathChangedInputSnapshot] = []
}

private final class ChangedValueRecorder {
    var snapshots: [KeyPathChangedInputSnapshot] = []
}

private struct ChangedValueRule: StatefulRule {
    typealias Value = Int

    var first: Attribute<Int>
    var second: Attribute<Int>
    var recorder: ChangedValueRecorder

    mutating func updateValue() {
        let firstResult = context.changedValue(
            of: first,
            options: []
        )
        let secondResult = second.changedValue(
            options: []
        )
        recorder.snapshots.append(
            KeyPathChangedInputSnapshot(
                firstChanged: firstResult.changed,
                secondChanged: secondResult.changed
            )
        )
        value = firstResult.value + secondResult.value
    }
}

private struct KeyPathChangedInputRule: StatefulRule {
    typealias Value = Int

    var first: Attribute<Int>
    var second: Attribute<Int>
    var recorder: KeyPathChangedInputRecorder

    mutating func updateValue() {
        recorder.snapshots.append(
            KeyPathChangedInputSnapshot(
                firstChanged: _AGGraph.currentStatefulInputChanged(first.identifier),
                secondChanged: _AGGraph.currentStatefulInputChanged(second.identifier)
            )
        )
        _AGGraph.setStatefulOutput(first.value + second.value)
    }
}

private final class TrackingIsolationRecorder {
    var values: [Int] = []
}

private final class CurrentContextTaskProbe: @unchecked Sendable {
    let graph: _AGGraph
    private let semaphore = DispatchSemaphore(value: 0)
    private let observedCurrent = Mutex(false)

    init(graph: _AGGraph) {
        self.graph = graph
    }

    func run() {
        observedCurrent.withLock { value in
            value = _AGGraph.current === graph
        }
        semaphore.signal()
    }

    func wait() -> DispatchTimeoutResult {
        semaphore.wait(timeout: .now() + 2)
    }

    var observed: Bool {
        observedCurrent.withLock { $0 }
    }
}

private struct TrackingIsolationRule: StatefulRule {
    typealias Value = Int

    var tracked: Attribute<Int>
    var isolated: Attribute<Int>
    var recorder: TrackingIsolationRecorder

    mutating func updateValue() {
        let value = tracked.value
            + isolated.valueAndFlags(options: .withoutDependency).value
        recorder.values.append(value)
        _AGGraph.setStatefulOutput(value)
    }
}

private final class ReentrantStatefulMutationTarget {
    var attribute: AGAttribute?
}

private struct ReentrantStatefulMutationRule: StatefulRule {
    typealias Value = Int

    var dependency: Attribute<Int>
    var offset = 0

    mutating func updateValue() {
        let value = dependency.value
        _AGGraph.setStatefulOutput(offset + value)
    }
}
