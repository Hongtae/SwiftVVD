import Foundation
import XCTest
@testable import VUI

private struct TransactionModifierMarkerKey: TransactionKey {
    static let defaultValue = 0
}

private struct TransactionModifierReportingViewList: ViewList {
    var countValue: Int

    func count(style: _ViewList_IteratorStyle) -> Int {
        countValue
    }
}

private struct TransactionModifierReportingContent: View, _PrimitiveView {
    var width: CGFloat

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active AttributeGraph context.")
        }

        let transaction = inputs.base.transaction
        let layout = graph.makeRule {
            let content = view._attribute.value
            let currentTransaction = transaction.value
            let duration = currentTransaction.animation?.box.duration ?? -1
            let marker = currentTransaction[TransactionModifierMarkerKey.self]
            return LayoutComputer.fixed(
                CGSize(
                    width: content.width,
                    height: CGFloat(marker) + CGFloat(duration * 100)
                )
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct TransactionModifierForwardingModifier: ViewModifier {
    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

final class TransactionModifierTests: XCTestCase {
    func testTransactionModifierAppliesTransformOverLiveParentTransaction() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            var graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let modifier = graph.makeInput(
                value: _TransactionModifier { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = .linear(duration: 0.25)
                }
            )

            _TransactionModifier._makeInputs(
                modifier: _GraphValue(_attribute: modifier),
                inputs: &graphInputs.inputs
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 725,
                duration: 0.25
            )

            var nextParent = Transaction(animation: .linear(duration: 2.0))
            nextParent[TransactionModifierMarkerKey.self] = 900
            graphInputs.parent.setValue(nextParent)

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 925,
                duration: 0.25
            )
        }
    }

    func testTransactionModifierViewListAppliesTransformOverLiveParentTransaction() throws {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let modifier = graph.makeInput(
                value: _TransactionModifier { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = .linear(duration: 0.25)
                }
            )

            let outputs = _TransactionModifier._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(base: graphInputs.inputs)
            ) { _, inputs in
                self.makeTransactionReportingViewList(graph: graph, inputs: inputs)
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 750)

            var nextParent = Transaction(animation: .linear(duration: 2.0))
            nextParent[TransactionModifierMarkerKey.self] = 900
            graphInputs.parent.setValue(nextParent)

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 950)
        }
    }

    func testValueTransactionModifierAppliesTransformOnlyAfterObservedValueChanges() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            var graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let modifier = graph.makeInput(
                value: valueTransactionModifier(value: 1, markerOffset: 25, duration: 0.25)
            )

            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: modifier),
                inputs: &graphInputs.inputs
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 700,
                duration: 1.0
            )

            modifier.setValue(
                valueTransactionModifier(value: 1, markerOffset: 25, duration: 0.25)
            )
            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 700,
                duration: 1.0
            )

            modifier.setValue(
                valueTransactionModifier(value: 2, markerOffset: 25, duration: 0.25)
            )
            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 725,
                duration: 0.25
            )

            var nextParent = Transaction(animation: .linear(duration: 2.0))
            nextParent[TransactionModifierMarkerKey.self] = 900
            graphInputs.parent.setValue(nextParent)

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 900,
                duration: 2.0
            )
        }
    }

    func testValueTransactionModifierViewListAppliesTransformOnlyAfterObservedValueChanges() throws {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let modifier = graph.makeInput(
                value: valueTransactionModifier(value: 1, markerOffset: 25, duration: 0.25)
            )

            let outputs = _ValueTransactionModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(base: graphInputs.inputs)
            ) { _, inputs in
                self.makeTransactionReportingViewList(graph: graph, inputs: inputs)
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            modifier.setValue(
                valueTransactionModifier(value: 1, markerOffset: 25, duration: 0.25)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            modifier.setValue(
                valueTransactionModifier(value: 2, markerOffset: 25, duration: 0.25)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 750)

            var nextParent = Transaction(animation: .linear(duration: 2.0))
            nextParent[TransactionModifierMarkerKey.self] = 900
            graphInputs.parent.setValue(nextParent)

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 1100)
        }
    }

    func testValueTransactionModifierNilAnimationClearsInheritedAnimationOnlyAfterObservedValueChanges() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            var graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let modifier = graph.makeInput(
                value: _ValueTransactionModifier(value: 1) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = nil
                }
            )

            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: modifier),
                inputs: &graphInputs.inputs
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 700,
                duration: 1.0
            )

            modifier.setValue(
                _ValueTransactionModifier(value: 2) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = nil
                }
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 725,
                duration: nil
            )
        }
    }

    func testValueTransactionModifierViewListNilAnimationClearsInheritedAnimationOnlyAfterObservedValueChanges() throws {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let modifier = graph.makeInput(
                value: _ValueTransactionModifier(value: 1) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = nil
                }
            )

            let outputs = _ValueTransactionModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(base: graphInputs.inputs)
            ) { _, inputs in
                self.makeTransactionReportingViewList(graph: graph, inputs: inputs)
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            modifier.setValue(
                _ValueTransactionModifier(value: 2) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = nil
                }
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 625)
        }
    }

    func testNestedValueTransactionModifiersKeepContentAdjacentTransformAsFinalWriter() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            var graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let outer = graph.makeInput(
                value: valueTransactionModifier(value: 1, marker: 200, duration: 0.2)
            )
            let inner = graph.makeInput(
                value: valueTransactionModifier(value: 1, marker: 300, duration: 0.3)
            )

            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: outer),
                inputs: &graphInputs.inputs
            )
            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: inner),
                inputs: &graphInputs.inputs
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 700,
                duration: 1.0
            )

            outer.setValue(
                valueTransactionModifier(value: 2, marker: 200, duration: 0.2)
            )
            inner.setValue(
                valueTransactionModifier(value: 2, marker: 300, duration: 0.3)
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 300,
                duration: 0.3
            )
        }
    }

    func testPushPopTransactionModifierAppliesBaseTransformBeforeWrappedModifier() throws {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _PushPopTransactionModifier(
                    content: TransactionModifierForwardingModifier()
                ) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = .linear(duration: 0.25)
                }
            )
            let content = graph.makeInput(
                value: TransactionModifierReportingContent(width: 10)
            )

            let outputs = _PushPopTransactionModifier<
                TransactionModifierForwardingModifier
            >._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                TransactionModifierReportingContent._makeView(
                    view: _GraphValue(_attribute: content),
                    inputs: inputs
                )
            }

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)
            assertLayout(layout, width: 10, height: 750)
        }
    }

    func testPushPopTransactionModifierAppliesBaseTransformBeforeWrappedModifierViewList() {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _PushPopTransactionModifier(
                    content: TransactionModifierForwardingModifier()
                ) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = .linear(duration: 0.25)
                }
            )

            let outputs = _PushPopTransactionModifier<
                TransactionModifierForwardingModifier
            >._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                let transaction = inputs.base.transaction.value
                self.assertTransaction(transaction, marker: 725, duration: 0.25)
                return _ViewListOutputs(
                    views: .staticList(.merged([])),
                    nextImplicitID: transaction[TransactionModifierMarkerKey.self],
                    staticCount: Int((transaction.animation?.box.duration ?? 0) * 100)
                )
            }

            XCTAssertEqual(outputs.nextImplicitID, 725)
            XCTAssertEqual(outputs.staticCount, 25)
        }
    }

    func testViewTransactionBodyWrapsPlaceholderContentWithPushPopTransaction() throws {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let view = TransactionModifierReportingContent(width: 10)
                .transaction({ transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = .linear(duration: 0.25)
                }) { content in
                    content
                }
            let viewAttr = graph.makeInput(value: view)

            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)
            assertLayout(layout, width: 10, height: 750)
        }
    }

    func testViewAnimationBodySetsAnimationThroughPushPopTransaction() throws {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let view = TransactionModifierReportingContent(width: 10)
                .animation(.linear(duration: 0.25)) { content in
                    content
                }
            let viewAttr = graph.makeInput(value: view)

            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)
            assertLayout(layout, width: 10, height: 725)
        }
    }

    func testViewAnimationBodyRespectsDisabledAnimations() throws {
        let graph = AttributeGraph()
        let ref = AttributeGraphRef(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            parent.disablesAnimations = true
            let view = TransactionModifierReportingContent(width: 10)
                .animation(.linear(duration: 0.25)) { content in
                    content
                }
            let viewAttr = graph.makeInput(value: view)

            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: viewAttr),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)
            assertLayout(layout, width: 10, height: 800)
        }
    }

    private func makeGraphInputs(
        graph: AttributeGraph,
        transaction: Transaction
    ) -> (inputs: _GraphInputs, parent: Attribute<Transaction>) {
        let parent = graph.makeInput(value: transaction)
        let inputs = _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(
                CachedEnvironment(
                    environment: graph.makeInput(value: EnvironmentValues())
                )
            ),
            phase: graph.makeInput(value: Phase()),
            transaction: parent,
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
        return (inputs, parent)
    }

    private func makeViewInputs(
        graph: AttributeGraph,
        transaction: Transaction
    ) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph, transaction: transaction).inputs,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }

    private func makeViewListInputs(base: _GraphInputs) -> _ViewListInputs {
        _ViewListInputs(
            base: base,
            implicitID: 0,
            options: 0,
            _traits: OptionalAttribute(),
            traitKeys: nil,
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
    }

    private func makeViewListInputs(
        graph: AttributeGraph,
        transaction: Transaction
    ) -> _ViewListInputs {
        makeViewListInputs(base: makeGraphInputs(graph: graph, transaction: transaction).inputs)
    }

    private func makeTransactionReportingViewList(
        graph: AttributeGraph,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let transaction = inputs.base.transaction
        let list: Attribute<any ViewList> = graph.makeRule {
            let currentTransaction = transaction.value
            let duration = currentTransaction.animation?.box.duration ?? -1
            let marker = currentTransaction[TransactionModifierMarkerKey.self]
            return TransactionModifierReportingViewList(
                countValue: marker + Int(duration * 100)
            )
        }
        return _ViewListOutputs(
            views: .dynamicList(list, nil),
            nextImplicitID: 0,
            staticCount: nil
        )
    }

    private func dynamicListAttribute(
        from outputs: _ViewListOutputs,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Attribute<any ViewList>? {
        guard case .dynamicList(let list, _) = outputs.views else {
            XCTFail("Expected dynamic view list output.", file: file, line: line)
            return nil
        }
        return list
    }

    private func valueTransactionModifier(
        value: Int,
        markerOffset: Int,
        duration: Double
    ) -> _ValueTransactionModifier<Int> {
        _ValueTransactionModifier(value: value) { transaction in
            transaction[TransactionModifierMarkerKey.self] += markerOffset
            transaction.animation = .linear(duration: duration)
        }
    }

    private func valueTransactionModifier(
        value: Int,
        marker: Int,
        duration: Double
    ) -> _ValueTransactionModifier<Int> {
        _ValueTransactionModifier(value: value) { transaction in
            transaction[TransactionModifierMarkerKey.self] = marker
            transaction.animation = .linear(duration: duration)
        }
    }

    private func assertTransaction(
        _ transaction: Transaction,
        marker: Int,
        duration: Double?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            transaction[TransactionModifierMarkerKey.self],
            marker,
            file: file,
            line: line
        )
        if let duration {
            guard let animation = transaction.animation else {
                XCTFail("Expected transaction animation.", file: file, line: line)
                return
            }
            XCTAssertEqual(
                animation.box.duration,
                duration,
                accuracy: 0.001,
                file: file,
                line: line
            )
        } else {
            XCTAssertNil(transaction.animation, file: file, line: line)
        }
    }

    private func assertLayout(
        _ layout: Attribute<LayoutComputer>,
        width: CGFloat,
        height: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let size = layout.value.sizeThatFits(.unspecified)
        XCTAssertEqual(size.width, width, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(size.height, height, accuracy: 0.001, file: file, line: line)
    }
}
