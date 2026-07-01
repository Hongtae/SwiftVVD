import XCTest
@testable import VUI

final class PreferenceBridgeTests: XCTestCase {
    func testPreferenceStorageLabelsMatchObservedShape() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let requestedKeys = makeRequestedKeys()
            let hostKeys = graph.makeInput(value: requestedKeys)
            let hostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: hostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: hostKeys,
                hostCombiner: hostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )

            XCTAssertEqual(Mirror(reflecting: bridge).children.compactMap(\.label), [
                "viewGraph",
                "isValid",
                "children",
                "requestedPreferences",
                "bridgedViewInputs",
                "_hostPreferenceKeys",
                "_hostPreferencesCombiner",
                "bridgedPreferences",
            ])
            XCTAssertEqual(
                Mirror(reflecting: bridge.bridgedPreferences[0]).children.compactMap(\.label),
                ["key", "combiner"]
            )
            XCTAssertEqual(
                Mirror(reflecting: PreferenceValues()).children.compactMap(\.label),
                ["entries"]
            )
            XCTAssertEqual(
                Mirror(reflecting: PreferenceValues.Value(value: "x", seed: VersionSeed(value: 1)))
                    .children
                    .compactMap(\.label),
                ["value", "seed"]
            )
            XCTAssertEqual(
                Mirror(reflecting: PreferenceValues.Entry(
                    key: AppendingPreferenceKey.self,
                    seed: VersionSeed(value: 1),
                    value: "x"
                ))
                .children
                .compactMap(\.label),
                ["key", "seed", "value"]
            )
            XCTAssertEqual(
                Mirror(reflecting: PreferenceCombiner<AppendingPreferenceKey>())
                    .children
                    .compactMap(\.label),
                ["attributes"]
            )
            XCTAssertEqual(
                Mirror(reflecting: HostPreferencesCombiner(
                    _keys: hostKeys,
                    _values: OptionalAttribute()
                ))
                .children
                .compactMap(\.label),
                ["_keys", "_values", "children"]
            )
            XCTAssertEqual(
                Mirror(reflecting: HostPreferencesCombiner.Child(
                    _keys: hostKeys.asWeak(),
                    _values: hostCombiner.asWeak()
                ))
                .children
                .compactMap(\.label),
                ["_keys", "_values"]
            )
        }
    }

    func testPreferenceValuesReduceEntriesByKeyAndCarryLastSeed() {
        var values = PreferenceValues()
        values.append(
            AppendingPreferenceKey.self,
            value: "a",
            seed: VersionSeed(value: 1)
        )
        values.append(
            AppendingPreferenceKey.self,
            value: "b",
            seed: VersionSeed(value: 2)
        )

        let reduced = values.value(for: AppendingPreferenceKey.self)

        XCTAssertEqual(reduced.value, "ab")
        XCTAssertEqual(reduced.seed, VersionSeed(value: 2))
    }

    func testPreferenceBridgeAddRemoveValueMutatesCombiner() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let requestedKeys = makeRequestedKeys()
            let hostKeys = graph.makeInput(value: requestedKeys)
            let hostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: hostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: hostKeys,
                hostCombiner: hostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )
            let first = graph.makeInput(value: "a")
            let second = graph.makeInput(value: "b")

            bridge.addValue(first, for: AppendingPreferenceKey.self)
            XCTAssertEqual(valueCombiner.value, "a")

            bridge.addValue(second, for: AppendingPreferenceKey.self)
            XCTAssertEqual(valueCombiner.value, "ab")

            XCTAssertTrue(
                bridge.removeValue(first, for: AppendingPreferenceKey.self)
            )
            XCTAssertEqual(valueCombiner.value, "b")
            XCTAssertFalse(
                bridge.removeValue(first, for: AppendingPreferenceKey.self)
            )
        }
    }

    func testPreferenceBridgeAddRemoveHostValuesMutatesHostCombiner() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let requestedKeys = makeRequestedKeys()
            let hostKeys = graph.makeInput(value: requestedKeys)
            let hostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: hostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: hostKeys,
                hostCombiner: hostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )
            let firstChildKeys = graph.makeInput(value: requestedKeys)
            let secondChildKeys = graph.makeInput(value: requestedKeys)
            let firstValues = graph.makeInput(value: makePreferenceValues("a", seed: 1))
            let replacementValues = graph.makeInput(value: makePreferenceValues("b", seed: 2))
            let secondValues = graph.makeInput(value: makePreferenceValues("c", seed: 3))

            bridge.addHostValues(keys: firstChildKeys, values: firstValues)
            XCTAssertEqual(
                hostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                "a"
            )

            bridge.addHostValues(keys: firstChildKeys, values: replacementValues)
            XCTAssertEqual(
                hostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                "b"
            )

            bridge.addHostValues(keys: secondChildKeys, values: secondValues)
            XCTAssertEqual(
                hostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                "bc"
            )

            XCTAssertTrue(bridge.removeHostValues(keys: firstChildKeys))
            XCTAssertEqual(
                hostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                "c"
            )
            XCTAssertFalse(bridge.removeHostValues(keys: firstChildKeys))
        }
    }

    func testPreferenceBridgeWrapInputsMergesRequestedAndHostKeys() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let bridge = PreferenceBridge(
                viewGraph: nil,
                requestedPreferences: requestedKeys,
                hostPreferenceKeys: bridgeHostKeys.asWeak(),
                hostPreferencesCombiner: bridgeHostCombiner.asWeak()
            )
            var localKeys = PreferenceKeys()
            localKeys.insert(SecondaryPreferenceKey.self)
            let localHostKeys = graph.makeInput(value: localKeys)
            var inputs = makeViewInputs(
                graph: graph,
                preferenceKeys: localKeys,
                hostKeys: localHostKeys
            )

            bridge.wrapInputs(&inputs)

            XCTAssertTrue(inputs.preferences.keys.contains(AppendingPreferenceKey.self))
            XCTAssertTrue(inputs.preferences.keys.contains(SecondaryPreferenceKey.self))
            XCTAssertTrue(inputs.preferences.hostKeys.value.contains(AppendingPreferenceKey.self))
            XCTAssertTrue(inputs.preferences.hostKeys.value.contains(SecondaryPreferenceKey.self))
        }
    }

    func testPreferenceBridgeWrapOutputsCreatesCombinerOutlets() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let bridge = PreferenceBridge(
                viewGraph: nil,
                requestedPreferences: requestedKeys,
                hostPreferenceKeys: bridgeHostKeys.asWeak(),
                hostPreferencesCombiner: bridgeHostCombiner.asWeak()
            )
            let inputs = makeViewInputs(
                graph: graph,
                preferenceKeys: requestedKeys,
                hostKeys: bridgeHostKeys
            )
            let value = graph.makeInput(value: "root")
            let hostValues = graph.makeInput(value: makePreferenceValues("host", seed: 5))
            var outputs = PreferencesOutputs()
            outputs.append(AppendingPreferenceKey.self, node: value.identifier)
            outputs.setValue(hostValues.identifier, for: HostPreferencesKey.self)

            bridge.wrapOutputs(&outputs, inputs: inputs)

            let wrappedValue = outputs.value(for: AppendingPreferenceKey.self)
            XCTAssertNotEqual(wrappedValue, value.identifier)
            XCTAssertEqual(Attribute<String>(wrappedValue!).value, "root")
            XCTAssertEqual(bridge.bridgedPreferences.count, 1)
            XCTAssertTrue(bridge.requestedPreferences.contains(AppendingPreferenceKey.self))
            let hostOutput = outputs.value(for: HostPreferencesKey.self)
            XCTAssertNotEqual(hostOutput, hostValues.identifier)
            XCTAssertEqual(
                Attribute<PreferenceValues>(hostOutput!).value.value(for: AppendingPreferenceKey.self).value,
                "host"
            )
        }
    }

    func testPreferenceTransformModifierDoesNotInstallBaseTransaction() {
        let host = GraphHost()
        var transformed: AGAttribute!
        var observedCurrent: [String] = []

        host.data.withCurrent {
            let graph = host.data.graph
            var baseTransaction = Transaction()
            baseTransaction[PreferenceTransformBaseTransactionKey.self] = "base"
            var keys = PreferenceKeys()
            keys.insert(AppendingPreferenceKey.self)
            let hostKeys = graph.makeInput(value: keys)
            let inputs = makeViewInputs(
                graph: graph,
                preferenceKeys: keys,
                hostKeys: hostKeys,
                transaction: baseTransaction
            )
            let modifier = graph.makeInput(
                value: _PreferenceTransformModifier<AppendingPreferenceKey> { value in
                    let current = Transaction.current[PreferenceTransformBaseTransactionKey.self]
                    observedCurrent.append(current)
                    value += "|\(current)"
                }
            )
            let outputs = _PreferenceTransformModifier<AppendingPreferenceKey>._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, _ in
                let value = graph.makeInput(value: "root")
                var outputs = _ViewOutputs()
                outputs.preferences.append(AppendingPreferenceKey.self, node: value.identifier)
                return outputs
            }

            transformed = outputs.preferences.value(for: AppendingPreferenceKey.self)
            XCTAssertEqual(Attribute<String>(transformed).value, "")
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(Attribute<String>(transformed!).value, "root|empty")
            XCTAssertEqual(observedCurrent, ["empty"])
        }
    }

    func testOptionalMakeViewRelaysRequestedPreferencesForSomeAndNone() throws {
        let graph = _AGGraph()

        try _AGGraph.withCurrent(graph) {
            var keys = PreferenceKeys()
            keys.insert(OptionalRelayPreferenceKey.self)
            let inputs = makeViewInputs(
                graph: graph,
                preferenceKeys: keys,
                hostKeys: graph.makeInput(value: keys)
            )

            let some = graph.makeInput(
                value: Optional<OptionalRelayEmitter>.some(OptionalRelayEmitter(value: "some"))
            )
            let someOutputs = Optional<OptionalRelayEmitter>._makeView(
                view: _GraphValue(_attribute: some),
                inputs: inputs
            )
            let somePreference = try XCTUnwrap(
                someOutputs.preferences.value(for: OptionalRelayPreferenceKey.self)
            )
            XCTAssertEqual(Attribute<String>(somePreference).value, "some")

            let none = graph.makeInput(value: Optional<OptionalRelayEmitter>.none)
            let noneOutputs = Optional<OptionalRelayEmitter>._makeView(
                view: _GraphValue(_attribute: none),
                inputs: inputs
            )
            let nonePreference = try XCTUnwrap(
                noneOutputs.preferences.value(for: OptionalRelayPreferenceKey.self)
            )
            XCTAssertEqual(Attribute<String>(nonePreference).value, "")
        }
    }

    func testPreferenceTransformQueuedTargetUpdatePropagatesDispatchTransaction() {
        let host = GraphHost()
        var transformed: AGAttribute!

        host.data.withCurrent {
            let graph = host.data.graph
            let source = graph.makeInput(value: "root")
            let transform = graph.makeInput(value: { (value: inout String) in
                value += "|queued"
            })
            var outputs = PreferencesOutputs()
            outputs.append(AppendingPreferenceKey.self, node: source.identifier)

            var transaction = Transaction()
            transaction[PreferenceTransformBaseTransactionKey.self] = "queued"

            Update.begin()
            defer {
                if Update.isActive {
                    Update.end()
                }
            }

            withTransaction(transaction) {
                outputs.makePreferenceTransformer(
                    key: AppendingPreferenceKey.self,
                    transformAttr: transform,
                    graph: graph
                )
                transformed = outputs.value(for: AppendingPreferenceKey.self)
                XCTAssertEqual(Attribute<String>(transformed).value, "")
                XCTAssertEqual(Update.queuedActionReasons, [0x11])
                Update.end()
            }

            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(Attribute<String>(transformed).value, "root|queued")
            let propagated = host.data.graph.transaction(for: transformed)
            XCTAssertEqual(propagated?[PreferenceTransformBaseTransactionKey.self], "queued")
        }
    }

    func testPreferenceTransformSuppressesDuplicateTargetUpdateAfterEquivalentBaseValue() {
        let host = GraphHost()
        var transformed: AGAttribute!
        var transform: Attribute<(inout Int) -> Void>!

        host.data.withCurrent {
            let graph = host.data.graph
            let source = graph.makeInput(value: 1)
            transform = graph.makeInput(value: { (value: inout Int) in
                value += 1
            })
            var outputs = PreferencesOutputs()
            outputs.append(SecondaryPreferenceKey.self, node: source.identifier)

            Update.begin()
            outputs.makePreferenceTransformer(
                key: SecondaryPreferenceKey.self,
                transformAttr: transform,
                graph: graph
            )
            transformed = outputs.value(for: SecondaryPreferenceKey.self)
            XCTAssertEqual(Attribute<Int>(transformed).value, 0)
            XCTAssertEqual(Update.queuedActionReasons, [0x11])
            Update.end()
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(Attribute<Int>(transformed).value, 2)
            XCTAssertFalse(host.hasPendingTransactions)

            Update.begin()
            transform.setValue({ (value: inout Int) in
                value += 1
            })
            XCTAssertEqual(Update.queuedActionReasons, [])
            Update.end()
            XCTAssertFalse(host.hasPendingTransactions)

            Update.begin()
            transform.setValue({ (value: inout Int) in
                value += 2
            })
            XCTAssertEqual(Update.queuedActionReasons, [0x11])
            Update.end()
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(Attribute<Int>(transformed).value, 3)
        }
    }

    func testPreferenceTransformDoesNotDeepCompareArrayPreferenceValues() {
        let host = GraphHost()
        var transformed: AGAttribute!
        var transform: Attribute<(inout [Int]) -> Void>!

        host.data.withCurrent {
            let graph = host.data.graph
            let source = graph.makeInput(value: [1, 2, 3])
            transform = graph.makeInput(value: { (value: inout [Int]) in
                value = value.map { $0 }
            })
            var outputs = PreferencesOutputs()
            outputs.append(ArrayPreferenceKey.self, node: source.identifier)

            Update.begin()
            outputs.makePreferenceTransformer(
                key: ArrayPreferenceKey.self,
                transformAttr: transform,
                graph: graph
            )
            transformed = outputs.value(for: ArrayPreferenceKey.self)
            XCTAssertEqual(Attribute<[Int]>(transformed).value, [])
            XCTAssertEqual(Update.queuedActionReasons, [0x11])
            Update.end()
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(Attribute<[Int]>(transformed).value, [1, 2, 3])
            XCTAssertFalse(host.hasPendingTransactions)

            Update.begin()
            transform.setValue({ (value: inout [Int]) in
                value = value.map { $0 }
            })
            XCTAssertEqual(Update.queuedActionReasons, [0x11])
            Update.end()
            XCTAssertTrue(host.hasPendingTransactions)
        }

        host.flushTransactions()

        host.data.withCurrent {
            XCTAssertEqual(Attribute<[Int]>(transformed).value, [1, 2, 3])
        }
    }

    func testPreferenceBridgeUpdateHostValuesInvalidatesHostKeys() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: bridgeHostKeys,
                hostCombiner: bridgeHostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )
            bridge.viewGraph = viewGraph

            bridge.updateHostValues(bridgeHostKeys)
        }

        XCTAssertTrue(viewGraph.hasPendingTransactions)
    }

    func testPreferenceBridgeInvalidateClearsLocalBridgeState() {
        let host = GraphHost()

        host.data.withCurrent {
            let graph = host.data.graph
            let requestedKeys = makeRequestedKeys()
            let hostKeys = graph.makeInput(value: requestedKeys)
            let hostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: hostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: hostKeys,
                hostCombiner: hostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )

            bridge.bridgedViewInputs[InvalidateProbePropertyKey.self] = true
            bridge.invalidate()

            XCTAssertFalse(bridge.isValid)
            XCTAssertTrue(bridge.children.isEmpty)
            XCTAssertTrue(bridge.requestedPreferences.keys.isEmpty)
            XCTAssertTrue(bridge.bridgedViewInputs.isEmpty)
            XCTAssertTrue(bridge.bridgedPreferences.isEmpty)
            XCTAssertNil(bridge.viewGraph)
        }
    }

    func testViewGraphUpdatePreferenceBridgeIgnoresNilEnvironmentBridge() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        var deferredUpdateCalled = false

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: bridgeHostKeys,
                hostCombiner: bridgeHostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )

            viewGraph.setPreferenceBridge(to: bridge, isInvalidating: false)
            viewGraph.updatePreferenceBridge(environment: EnvironmentValues.tracking()) {
                deferredUpdateCalled = true
            }

            XCTAssertTrue(viewGraph.preferenceBridge === bridge)
            XCTAssertEqual(bridge.children.count, 1)
        }

        XCTAssertFalse(deferredUpdateCalled)
    }

    func testViewGraphUpdatePreferenceBridgeSetsBridgeImmediatelyWhenRootInputsAreClean() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        var deferredUpdateCalled = false

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: bridgeHostKeys,
                hostCombiner: bridgeHostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )
            var environment = EnvironmentValues.tracking()
            environment.preferenceBridge = bridge

            viewGraph.updatePreferenceBridge(environment: environment) {
                deferredUpdateCalled = true
            }

            XCTAssertTrue(viewGraph.preferenceBridge === bridge)
            XCTAssertEqual(bridge.children.count, 1)
            XCTAssertFalse(deferredUpdateCalled)
        }
    }

    func testViewGraphUpdatePreferenceBridgeSetsBridgeImmediatelyWhenRootInputsAreDirtyButNotUpdating() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        rendererHost.valuesNeedingUpdate = [.environment]
        var deferredUpdateCalled = false

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: bridgeHostKeys,
                hostCombiner: bridgeHostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )
            var environment = EnvironmentValues.tracking()
            environment.preferenceBridge = bridge

            viewGraph.updatePreferenceBridge(environment: environment) {
                deferredUpdateCalled = true
            }

            XCTAssertTrue(viewGraph.preferenceBridge === bridge)
            XCTAssertEqual(bridge.children.count, 1)
            XCTAssertFalse(deferredUpdateCalled)
        }
    }

    func testViewGraphUpdatePreferenceBridgeDefersPassedClosureWhileGraphIsUpdating() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        var deferredUpdateCalled = false

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: bridgeHostKeys,
                hostCombiner: bridgeHostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )
            var environment = EnvironmentValues.tracking()
            environment.preferenceBridge = bridge

            Update.begin()
            viewGraph.runTransaction {
                viewGraph.updatePreferenceBridge(environment: environment) {
                    deferredUpdateCalled = true
                }
            }
            XCTAssertNil(viewGraph.preferenceBridge)
            XCTAssertEqual(Update.queuedActionReasons, [0x11])
            XCTAssertFalse(deferredUpdateCalled)
            Update.end()

            XCTAssertNil(viewGraph.preferenceBridge)
            XCTAssertTrue(deferredUpdateCalled)
        }
    }

    func testViewGraphPreferenceOutletsFollowHiddenForReuseState() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let requestedKeys = makeRequestedKeys()
            let bridgeHostKeys = graph.makeInput(value: requestedKeys)
            let bridgeHostCombiner = graph.makeStatefulRule(
                HostPreferencesCombiner(
                    _keys: bridgeHostKeys,
                    _values: OptionalAttribute()
                )
            )
            let valueCombiner = graph.makeStatefulRule(
                PreferenceCombiner<AppendingPreferenceKey>()
            )
            let bridge = makeBridge(
                requestedKeys: requestedKeys,
                hostKeys: bridgeHostKeys,
                hostCombiner: bridgeHostCombiner,
                bridgedCombiner: valueCombiner,
                graph: graph
            )
            let value = graph.makeInput(value: "root")
            let hostValues = graph.makeInput(value: makePreferenceValues("host", seed: 6))
            var preferences = PreferencesOutputs()
            preferences.append(AppendingPreferenceKey.self, node: value.identifier)
            preferences.setValue(hostValues.identifier, for: HostPreferencesKey.self)

            viewGraph.setPreferenceBridge(to: bridge, isInvalidating: false)
            viewGraph.makePreferenceOutlets(
                outputs: _ViewOutputs(preferences: preferences)
            )

            XCTAssertEqual(viewGraph.preferenceValueOutlets.count, 1)
            XCTAssertEqual(valueCombiner.value, "root")
            XCTAssertEqual(
                bridgeHostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                "host"
            )
            XCTAssertEqual(
                viewGraph.preferenceValues().value(for: AppendingPreferenceKey.self).value,
                "host"
            )

            viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: true)

            XCTAssertEqual(valueCombiner.value, "")
            XCTAssertEqual(
                bridgeHostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                ""
            )

            viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: false)

            XCTAssertEqual(valueCombiner.value, "root")
            XCTAssertEqual(
                bridgeHostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                "host"
            )

            viewGraph.setPreferenceBridge(to: nil, isInvalidating: true)

            XCTAssertEqual(viewGraph.preferenceValueOutlets.count, 0)
            XCTAssertEqual(valueCombiner.value, "")
            XCTAssertEqual(
                bridgeHostCombiner.value.value(for: AppendingPreferenceKey.self).value,
                ""
            )
        }
    }

    private func makeBridge(
        requestedKeys: PreferenceKeys,
        hostKeys: Attribute<PreferenceKeys>,
        hostCombiner: Attribute<PreferenceValues>,
        bridgedCombiner: Attribute<AppendingPreferenceKey.Value>,
        graph: _AGGraph
    ) -> PreferenceBridge {
        let weakCombiner = graph.weakAttributeIfValid(for: bridgedCombiner.identifier)!
        return PreferenceBridge(
            viewGraph: nil,
            requestedPreferences: requestedKeys,
            hostPreferenceKeys: hostKeys.asWeak(),
            hostPreferencesCombiner: hostCombiner.asWeak(),
            bridgedPreferences: [
                PreferenceBridge.BridgedPreference(
                    key: AppendingPreferenceKey.self,
                    combiner: weakCombiner
                ),
            ]
        )
    }

    private func makeRequestedKeys() -> PreferenceKeys {
        var keys = PreferenceKeys()
        keys.insert(AppendingPreferenceKey.self)
        return keys
    }

    private func makePreferenceValues(_ value: String, seed: UInt32) -> PreferenceValues {
        var values = PreferenceValues()
        values.append(
            AppendingPreferenceKey.self,
            value: value,
            seed: VersionSeed(value: seed)
        )
        return values
    }

    private func makeViewInputs(
        graph: _AGGraph,
        preferenceKeys: PreferenceKeys,
        hostKeys: Attribute<PreferenceKeys>,
        transaction: Transaction = Transaction()
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues.tracking())
        let graphInputs = _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: transaction),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
        return _ViewInputs(
            base: graphInputs,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(keys: preferenceKeys, hostKeys: hostKeys),
            transform: graph.makeInput(value: ViewTransform.identity),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(.zero)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}

private struct AppendingPreferenceKey: PreferenceKey {
    static let defaultValue = ""

    static func reduce(value: inout String, nextValue: () -> String) {
        value += nextValue()
    }
}

private struct SecondaryPreferenceKey: PreferenceKey {
    static let defaultValue = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

private struct ArrayPreferenceKey: PreferenceKey {
    static let defaultValue: [Int] = []

    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

private struct OptionalRelayPreferenceKey: PreferenceKey {
    static let defaultValue = ""

    static func reduce(value: inout String, nextValue: () -> String) {
        value += nextValue()
    }
}

private struct OptionalRelayEmitter: View {
    typealias Body = Never

    var value: String

    var body: Never {
        neverBody()
    }

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        var outputs = _ViewOutputs()
        outputs.preferences.append(
            OptionalRelayPreferenceKey.self,
            node: view[\.value]._attribute.identifier
        )
        return outputs
    }
}

private struct InvalidateProbePropertyKey: PropertyKey {
    static let defaultValue = false
}

private struct PreferenceTransformBaseTransactionKey: TransactionKey {
    static let defaultValue = "empty"
}
