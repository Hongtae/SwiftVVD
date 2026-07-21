import Synchronization
import XCTest
@testable import VUI

final class AGGraphCounterTests: XCTestCase {
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
        XCTAssertEqual(DefaultAttributeBody.comparisonMode.rawValue, 2)
        XCTAssertEqual(DefaultAttributeBody.flags.rawValue, 8)
        XCTAssertFalse(DefaultAttributeBody._hasDestroySelf)
        XCTAssertEqual(AsyncAttributeBody.flags.rawValue, 0)
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
            output.addInput(source, options: AGInputOptions(rawValue: 0), token: 17)

            source.value = 2
            XCTAssertTrue(
                output.breadthFirstSearch(
                    options: AGSearchOptions(rawValue: 1)
                ) { $0 == source.identifier }
            )
            XCTAssertTrue(
                source.identifier.breadthFirstSearch(
                    options: AGSearchOptions(rawValue: 2)
                ) { $0 == output.identifier }
            )
            XCTAssertEqual(output.value, 42)
            XCTAssertEqual(recorder.evaluationCount, 2)
        }
    }

    func testBreadthFirstSearchChecksStartAndDeduplicatesCycles() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let first = Attribute(value: 1)
            let second = Attribute(value: 2)
            let third = Attribute(value: 3)
            first.addInput(second, options: AGInputOptions(rawValue: 0), token: 0)
            second.identifier.addInput(
                third.identifier,
                options: AGInputOptions(rawValue: 0),
                token: 0
            )
            third.addInput(first, options: AGInputOptions(rawValue: 0), token: 0)

            var visited: [AGAttribute] = []
            XCTAssertFalse(
                first.breadthFirstSearch(
                    options: AGSearchOptions(rawValue: 3)
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
                    options: AGSearchOptions(rawValue: 0)
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

            first.setValue(2)
            XCTAssertEqual(output.value, 12)
        }

        XCTAssertEqual(
            recorder.snapshots,
            [
                KeyPathChangedInputSnapshot(firstChanged: false, secondChanged: false),
                KeyPathChangedInputSnapshot(firstChanged: true, secondChanged: false),
            ]
        )
    }

    func testWithoutTrackingSkipsDependencyAndRestoresRuleContext() {
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

    func testHashableRuleCachedValueUsesAReusableUpdatingAttribute() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let source = Attribute(value: 3)
            let rule = CachedDoublingRule(source: source)
            let options = AGCachedValueOptions(rawValue: 0)

            XCTAssertNil(rule.cachedValueIfExists(options: options, owner: nil))
            XCTAssertEqual(rule.cachedValue(options: options, owner: nil), 6)
            XCTAssertEqual(graph.cachedRuleEntries.count, 1)
            XCTAssertEqual(rule.cachedValue(options: options, owner: nil), 6)
            XCTAssertEqual(graph.cachedRuleEntries.count, 1)

            XCTAssertEqual(
                rule.cachedValue(
                    options: AGCachedValueOptions(rawValue: 1),
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

private struct NonEquatableInput {
    var value: Int
}

private final class OutputPropagationRecorder {
    var intermediateEvaluations = 0
    var downstreamEvaluations = 0
    var sideEffectEvaluations = 0
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
            options: AGValueOptions(rawValue: 0)
        )
        let secondResult = second.changedValue(
            options: AGValueOptions(rawValue: 0)
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
        let value = tracked.value + _AGGraph.withoutTracking {
            isolated.value
        }
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
