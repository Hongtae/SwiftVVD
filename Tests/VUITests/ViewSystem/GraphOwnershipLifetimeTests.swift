import Foundation
import XCTest
@testable import VUI

final class GraphOwnershipLifetimeTests: XCTestCase {
    func testMountedStateOrBindingBufferDoesNotKeepItsHostOrGraphAlive() {
        weak var hostReference: TestViewRendererHost?
        weak var viewGraphReference: ViewGraph?
        weak var graphReference: _AGGraph?
        func mount() -> (_DynamicPropertyBuffer, StateOrBinding<Int>) {
            let host = TestViewRendererHost()
            let viewGraph = ViewGraph(rootViewType: EmptyView.self,
                content: EmptyView(), rendererHost: host)
            host.storage = viewGraph
            hostReference = host
            viewGraphReference = viewGraph
            graphReference = viewGraph.data.graph
            return viewGraph.data.withCurrent {
                let graph = viewGraph.data.graph
                var state = StateOrBinding(wrappedValue: 6)
                var inputs = _GraphInputs(
                    time: graph.makeInput(value: Time.zero),
                    phase: graph.makeInput(value: _GraphInputs.Phase()),
                    environment: graph.makeInput(value: EnvironmentValues()),
                    transaction: graph.makeInput(value: Transaction()))
                let buffer = _DynamicPropertyBuffer(
                    fields: .init(entries: [.init(offset: 0, type: StateOrBinding<Int>.self)]),
                    container: _GraphValue(_attribute: graph.makeInput(value: state)),
                    inputs: &inputs)
                buffer.applyContexts(to: &state)
                XCTAssertEqual(state.wrappedValue, 6)
                return (buffer, state)
            }
        }
        let mounted = mount()
        withExtendedLifetime(mounted) {
            XCTAssertNil(hostReference)
            XCTAssertNil(viewGraphReference)
            XCTAssertNil(graphReference)
            XCTAssertEqual(mounted.1.wrappedValue, 6)
        }
    }

    func testGraphReferenceRuleUpdatesWithoutKeepingItsGraphAlive() {
        weak var graphReference: _AGGraph?
        func evaluate() {
            let graph = _AGGraph()
            graphReference = graph
            _AGGraph.withCurrent(graph) {
                let graphID = ObjectIdentifier(graph)
                let input = graph.makeInput(value: 3)
                var evaluations = 0
                let output: Attribute<Int> = graph.makeRule { graphRef in
                    XCTAssertEqual(ObjectIdentifier(graphRef.graph), graphID)
                    evaluations += 1
                    return input.value * 2
                }

                XCTAssertEqual(evaluations, 0)
                XCTAssertEqual(output.value, 6)
                XCTAssertEqual(output.value, 6)
                XCTAssertEqual(evaluations, 1)

                input.setValue(7)
                XCTAssertEqual(output.value, 14)
                XCTAssertEqual(evaluations, 2)
            }
        }
        evaluate()
        XCTAssertNil(graphReference)
    }

    // ASSERTIONS statePropertyBoxHostSignalObserved
    func testMountedStateBufferDoesNotKeepItsHostOrGraphAlive() {
        weak var hostReference: TestViewRendererHost?
        weak var viewGraphReference: ViewGraph?
        weak var graphReference: _AGGraph?
        func mount() -> (_DynamicPropertyBuffer, State<Int>) {
            let host = TestViewRendererHost()
            let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
            host.storage = viewGraph
            hostReference = host
            viewGraphReference = viewGraph
            graphReference = viewGraph.data.graph
            return viewGraph.data.withCurrent {
                let graph = viewGraph.data.graph
                var state = State(wrappedValue: 6)
                var inputs = _GraphInputs(
                    time: graph.makeInput(value: Time.zero),
                    phase: graph.makeInput(value: _GraphInputs.Phase()),
                    environment: graph.makeInput(value: EnvironmentValues()),
                    transaction: graph.makeInput(value: Transaction()))
                let buffer = _DynamicPropertyBuffer(
                    fields: .init(entries: [.init(offset: 0, type: State<Int>.self)]),
                    container: _GraphValue(_attribute: graph.makeInput(value: state)),
                    inputs: &inputs)
                buffer.applyContexts(to: &state)
                XCTAssertNotNil(state._location)
                XCTAssertEqual(state.wrappedValue, 6)
                return (buffer, state)
            }
        }
        let mounted = mount()
        withExtendedLifetime(mounted) {
            XCTAssertNil(hostReference)
            XCTAssertNil(viewGraphReference)
            XCTAssertNil(graphReference)
            XCTAssertEqual(mounted.1.wrappedValue, 6)
        }
    }

    func testPreferenceReductionRulesDoNotKeepTheirGraphAlive() throws {
        for mode in 0..<3 {
            weak var graphReference: _AGGraph?
            func reduce() throws {
                let graph = _AGGraph()
                graphReference = graph
                try _AGGraph.withCurrent(graph) {
                    let first = graph.makeInput(value: ["first"])
                    let second = graph.makeInput(value: ["second"])
                    var firstOutput = PreferencesOutputs()
                    firstOutput.append(LifetimeKey.self, node: first.identifier)
                    var secondOutput = PreferencesOutputs()
                    secondOutput.append(LifetimeKey.self, node: second.identifier)
                    var keys = PreferenceKeys()
                    keys.add(LifetimeKey.self)
                    let inputs = PreferencesInputs(keys: keys, hostKeys: graph.makeInput(value: keys))
                    let result: PreferencesOutputs
                    switch mode {
                    case 0:
                        result = PreferencesOutputs.merge([firstOutput, secondOutput], in: graph)
                    case 1:
                        let firstPlaceholder = inputs.makeIndirectOutputs()
                        let secondPlaceholder = inputs.makeIndirectOutputs()
                        firstOutput.attachIndirectOutputs(to: firstPlaceholder)
                        secondOutput.attachIndirectOutputs(to: secondPlaceholder)
                        result = PreferencesOutputs.merge([firstPlaceholder, secondPlaceholder], in: graph)
                    default:
                        let placeholder = inputs.makeIndirectOutputs()
                        var concrete = firstOutput
                        concrete.append(LifetimeKey.self, node: second.identifier)
                        concrete.attachIndirectOutputs(to: placeholder)
                        result = placeholder
                    }
                    let node = try XCTUnwrap(result.value(for: LifetimeKey.self))
                    XCTAssertEqual(Attribute<[String]>(node).value, ["first", "second"])
                }
            }
            try reduce()
            XCTAssertNil(graphReference, "reduction mode \(mode)")
        }
    }
}

private struct LifetimeKey: PreferenceKey {
    static var defaultValue: [String] { ["default"] }
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value += nextValue()
    }
}
