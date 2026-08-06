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

private struct TransactionModifierReportingContent: View, TestPrimitiveView {
    var width: CGFloat

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
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

private struct TransactionModifierScopeReportingModifier: ViewModifier {
    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let modifierTransaction = inputs.base.transaction
        let bodyOutputs = body(_Graph(), inputs)
        guard let bodyLayout = bodyOutputs._layoutComputer.attribute else {
            return bodyOutputs
        }
        let layout = graph.makeRule {
            let transaction = modifierTransaction.value
            let duration = transaction.animation?.box.duration ?? -1
            let marker = transaction[TransactionModifierMarkerKey.self]
            let bodySize = bodyLayout.value.sizeThatFits(.unspecified)
            return LayoutComputer.fixed(
                CGSize(
                    width: CGFloat(marker) + CGFloat(duration * 100),
                    height: bodySize.height
                )
            )
        }
        var outputs = bodyOutputs
        outputs._layoutComputer = OptionalAttribute(layout)
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        let transaction = inputs.base.transaction.value
        var outputs = body(_Graph(), inputs)
        outputs.nextImplicitID = transaction[TransactionModifierMarkerKey.self]
        return outputs
    }
}

final class TransactionModifierTests: XCTestCase {
    func testGeometryTransactionUsesLastSavedTransaction() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var inputs = makeViewInputs(graph: graph, transaction: Transaction())
            let ordinary = inputs.base.transaction
            XCTAssertEqual(inputs.geometryTransaction().identifier, ordinary.identifier)

            let firstSaved = graph.makeInput(value: Transaction())
            let lastSaved = graph.makeInput(value: Transaction())
            inputs.savedTransactions = [firstSaved, lastSaved]
            inputs.base.transaction = graph.makeInput(value: Transaction())

            XCTAssertEqual(inputs.geometryTransaction().identifier, lastSaved.identifier)
        }
    }

    func testAnimatedFrameCacheUsesGeometryTransaction() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var inputs = makeViewInputs(graph: graph, transaction: Transaction())
            inputs.base.options.insert(.viewNeedsGeometry)
            let saved = graph.makeInput(value: Transaction(animation: .linear(duration: 0.25)))
            inputs.savedTransactions = [saved]

            var cachedEnvironment = inputs.base.cachedEnvironment.value
            _ = cachedEnvironment.animatedPosition(for: inputs)
            _ = cachedEnvironment.animatedSize(for: inputs)

            let cachedFrame = try XCTUnwrap(cachedEnvironment.animatedFrame)
            XCTAssertEqual(cachedFrame.transaction.identifier, saved.identifier)
        }
    }

    func testTransactionModifierAppliesTransformOverLiveParentTransaction() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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

    func testNestedValueTransactionModifierClearThenSetKeepsContentAdjacentSetAsFinalWriter() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            var graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let outerClear = graph.makeInput(
                value: valueTransactionModifierClearing(value: 1, marker: 200)
            )
            let innerSet = graph.makeInput(
                value: valueTransactionModifier(value: 1, marker: 300, duration: 0.3)
            )

            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: outerClear),
                inputs: &graphInputs.inputs
            )
            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: innerSet),
                inputs: &graphInputs.inputs
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 700,
                duration: 1.0
            )

            outerClear.setValue(
                valueTransactionModifierClearing(value: 2, marker: 200)
            )
            innerSet.setValue(
                valueTransactionModifier(value: 2, marker: 300, duration: 0.3)
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 300,
                duration: 0.3
            )
        }
    }

    func testNestedValueTransactionModifierSetThenClearKeepsContentAdjacentClearAsFinalWriter() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            var graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let outerSet = graph.makeInput(
                value: valueTransactionModifier(value: 1, marker: 200, duration: 0.2)
            )
            let innerClear = graph.makeInput(
                value: valueTransactionModifierClearing(value: 1, marker: 300)
            )

            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: outerSet),
                inputs: &graphInputs.inputs
            )
            _ValueTransactionModifier<Int>._makeInputs(
                modifier: _GraphValue(_attribute: innerClear),
                inputs: &graphInputs.inputs
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 700,
                duration: 1.0
            )

            outerSet.setValue(
                valueTransactionModifier(value: 2, marker: 200, duration: 0.2)
            )
            innerClear.setValue(
                valueTransactionModifierClearing(value: 2, marker: 300)
            )

            assertTransaction(
                graphInputs.inputs.transaction.value,
                marker: 300,
                duration: nil
            )
        }
    }

    func testNestedValueTransactionModifierViewListKeepsContentAdjacentTransformAsFinalWriter() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let graphInputs = makeGraphInputs(graph: graph, transaction: parent)
            let outer = graph.makeInput(
                value: valueTransactionModifier(value: 1, marker: 200, duration: 0.2)
            )
            let inner = graph.makeInput(
                value: valueTransactionModifier(value: 1, marker: 300, duration: 0.3)
            )

            let outputs = _ValueTransactionModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: outer),
                inputs: makeViewListInputs(base: graphInputs.inputs)
            ) { _, outerInputs in
                _ValueTransactionModifier<Int>._makeViewList(
                    modifier: _GraphValue(_attribute: inner),
                    inputs: outerInputs
                ) { _, innerInputs in
                    self.makeTransactionReportingViewList(graph: graph, inputs: innerInputs)
                }
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            outer.setValue(
                valueTransactionModifier(value: 2, marker: 200, duration: 0.2)
            )
            inner.setValue(
                valueTransactionModifier(value: 2, marker: 300, duration: 0.3)
            )

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 330)
        }
    }

    func testPushPopTransactionModifierKeepsTransformedModifierAndRestoresBodyTransaction() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _PushPopTransactionModifier(
                    content: TransactionModifierScopeReportingModifier()
                ) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = .linear(duration: 0.25)
                }
            )
            let content = graph.makeInput(
                value: TransactionModifierReportingContent(width: 10)
            )

            let outputs = _PushPopTransactionModifier<
                TransactionModifierScopeReportingModifier
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
            assertLayout(layout, width: 750, height: 800)
        }
    }

    func testPushPopTransactionModifierViewListRestoresBodyTransaction() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[TransactionModifierMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _PushPopTransactionModifier(
                    content: TransactionModifierScopeReportingModifier()
                ) { transaction in
                    transaction[TransactionModifierMarkerKey.self] += 25
                    transaction.animation = .linear(duration: 0.25)
                }
            )

            let outputs = _PushPopTransactionModifier<
                TransactionModifierScopeReportingModifier
            >._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                let transaction = inputs.base.transaction.value
                self.assertTransaction(transaction, marker: 700, duration: 1.0)
                return _ViewListOutputs(
                    views: .staticList(.merged([])),
                    nextImplicitID: transaction[TransactionModifierMarkerKey.self],
                    staticCount: Int((transaction.animation?.box.duration ?? 0) * 100)
                )
            }

            XCTAssertEqual(outputs.nextImplicitID, 725)
            XCTAssertEqual(outputs.staticCount, 100)
        }
    }

    func testViewTransactionBodyWrapsPlaceholderContentWithPushPopTransaction() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
            assertLayout(layout, width: 10, height: 800)
        }
    }

    func testViewAnimationBodySetsAnimationThroughPushPopTransaction() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
            assertLayout(layout, width: 10, height: 800)
        }
    }

    func testViewAnimationBodyRespectsDisabledAnimations() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

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
        graph: _AGGraph,
        transaction: Transaction
    ) -> (inputs: _GraphInputs, parent: Attribute<Transaction>) {
        let parent = graph.makeInput(value: transaction)
        let inputs = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: parent
        )
        return (inputs, parent)
    }

    private func makeViewInputs(
        graph: _AGGraph,
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
            options: [],
            _traits: OptionalAttribute(),
            traitKeys: nil,
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
    }

    private func makeViewListInputs(
        graph: _AGGraph,
        transaction: Transaction
    ) -> _ViewListInputs {
        makeViewListInputs(base: makeGraphInputs(graph: graph, transaction: transaction).inputs)
    }

    private func makeTransactionReportingViewList(
        graph: _AGGraph,
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

    private func valueTransactionModifierClearing(
        value: Int,
        marker: Int
    ) -> _ValueTransactionModifier<Int> {
        _ValueTransactionModifier(value: value) { transaction in
            transaction[TransactionModifierMarkerKey.self] = marker
            transaction.animation = nil
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
