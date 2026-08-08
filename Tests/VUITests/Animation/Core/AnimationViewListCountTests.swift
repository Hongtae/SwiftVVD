import XCTest
@testable import VUI

private struct CountedAnimationContent: View, Equatable, TestPrimitiveView {
    typealias Body = Never

    static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        3
    }
}

private struct AnimationViewTransactionMarkerKey: TransactionKey {
    static let defaultValue = 0
}

private struct TransactionReportingAnimationViewList: ViewList {
    var countValue: Int

    func count(style: _ViewList_IteratorStyle) -> Int {
        countValue
    }
}

private struct TransactionReportingAnimationContent: View, Equatable, TestPrimitiveView {
    var equalityKey: Int
    var width: CGFloat

    typealias Body = Never

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.equalityKey == rhs.equalityKey
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let transaction = inputs.base.transaction
        let layout = graph.makeRule {
            let content = view._attribute.value
            let currentTransaction = transaction.value
            let duration = currentTransaction.animation?.box.duration ?? -1
            let marker = currentTransaction[AnimationViewTransactionMarkerKey.self]
            return LayoutComputer.fixed(
                CGSize(
                    width: content.width,
                    height: CGFloat(marker) + CGFloat(duration * 100)
                )
            )
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
        }
        let transaction = inputs.base.transaction
        let list: Attribute<any ViewList> = graph.makeRule {
            let content = view._attribute.value
            let currentTransaction = transaction.value
            let duration = currentTransaction.animation?.box.duration ?? -1
            let marker = currentTransaction[AnimationViewTransactionMarkerKey.self]
            return TransactionReportingAnimationViewList(
                countValue: Int(content.width) + marker + Int(duration * 100)
            )
        }
        return _ViewListOutputs(
            views: .dynamicList(list, nil),
            nextImplicitID: 0,
            staticCount: nil
        )
    }
}

final class AnimationViewListCountTests: XCTestCase {
    func testAnimationModifierCarriesPrimitiveViewModifierMarker() {
        func primitiveModifierTypeName<T: PrimitiveViewModifier>(_ modifier: T) -> String {
            String(describing: T.self)
        }

        XCTAssertTrue(
            primitiveModifierTypeName(
                _AnimationModifier(animation: Animation.linear(duration: 0.25), value: 1)
            ).contains("_AnimationModifier")
        )
    }

    func testAnimationViewForwardsStaticViewListCountToContent() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let inputs = _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: EnvironmentValues()),
                transaction: graph.makeInput(value: Transaction())
            )

            XCTAssertEqual(
                _AnimationView<CountedAnimationContent>._viewListCount(
                    inputs: _ViewListCountInputs(base: inputs)
                ),
                3
            )
        }
    }

    func testAnimationViewGatesContentAndTransactionByContentEquality() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let source = graph.makeInput(
                value: _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 10
                    ),
                    animation: .linear(duration: 0.25)
                )
            )
            let outputs = _AnimationView<TransactionReportingAnimationContent>._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            )
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 20
                    ),
                    animation: .linear(duration: 0.25)
                )
            )

            assertLayout(layout, width: 10, height: 800)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 2,
                        width: 30
                    ),
                    animation: .linear(duration: 0.25)
                )
            )

            assertLayout(layout, width: 30, height: 725)
        }
    }

    func testAnimationViewNilAnimationClearsInheritedAnimationOnContentChange() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let source = graph.makeInput(
                value: _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 10
                    ),
                    animation: nil
                )
            )
            let outputs = _AnimationView<TransactionReportingAnimationContent>._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            )
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 2,
                        width: 20
                    ),
                    animation: nil
                )
            )

            assertLayout(layout, width: 20, height: 600)
        }
    }

    func testAnimationViewHonorsInheritedDisablesAnimations() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent.disablesAnimations = true
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let source = graph.makeInput(
                value: _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 10
                    ),
                    animation: .linear(duration: 0.25)
                )
            )
            let outputs = _AnimationView<TransactionReportingAnimationContent>._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            )
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 2,
                        width: 20
                    ),
                    animation: .linear(duration: 0.25)
                )
            )

            assertLayout(layout, width: 20, height: 800)
        }
    }

    func testAnimationViewListGatesContentAndTransactionByContentEquality() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let source = graph.makeInput(
                value: _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 10
                    ),
                    animation: .linear(duration: 0.25)
                )
            )
            let outputs = _AnimationView<TransactionReportingAnimationContent>._makeViewList(
                view: _GraphValue(_attribute: source),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            )
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 810)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 20
                    ),
                    animation: .linear(duration: 0.25)
                )
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 810)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 2,
                        width: 30
                    ),
                    animation: .linear(duration: 0.25)
                )
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 755)
        }
    }

    func testAnimationViewListNilAnimationClearsInheritedAnimationOnContentChange() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let source = graph.makeInput(
                value: _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 10
                    ),
                    animation: nil
                )
            )
            let outputs = _AnimationView<TransactionReportingAnimationContent>._makeViewList(
                view: _GraphValue(_attribute: source),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            )
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 810)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 2,
                        width: 20
                    ),
                    animation: nil
                )
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 620)
        }
    }

    func testAnimationViewListHonorsInheritedDisablesAnimations() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent.disablesAnimations = true
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let source = graph.makeInput(
                value: _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 1,
                        width: 10
                    ),
                    animation: .linear(duration: 0.25)
                )
            )
            let outputs = _AnimationView<TransactionReportingAnimationContent>._makeViewList(
                view: _GraphValue(_attribute: source),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            )
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 810)

            source.setValue(
                _AnimationView(
                    content: TransactionReportingAnimationContent(
                        equalityKey: 2,
                        width: 20
                    ),
                    animation: .linear(duration: 0.25)
                )
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 820)
        }
    }

    func testAnimationModifierInjectsAnimationOnlyAfterObservedValueChanges() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            let content = graph.makeInput(
                value: TransactionReportingAnimationContent(equalityKey: 1, width: 10)
            )
            let outputs = _AnimationModifier<Int>._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                TransactionReportingAnimationContent._makeView(
                    view: _GraphValue(_attribute: content),
                    inputs: inputs
                )
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            assertLayout(layout, width: 10, height: 800)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 2)
            )
            assertLayout(layout, width: 10, height: 725)
        }
    }

    func testAnimationModifierAnimationExpiresAfterTransactionSeedAdvances() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            let content = graph.makeInput(
                value: TransactionReportingAnimationContent(equalityKey: 1, width: 10)
            )
            let outputs = _AnimationModifier<Int>._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                TransactionReportingAnimationContent._makeView(
                    view: _GraphValue(_attribute: content),
                    inputs: inputs
                )
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 2)
            )
            assertLayout(layout, width: 10, height: 725)

            host.data.transactionSeed &+= 1
            content.setValue(
                TransactionReportingAnimationContent(equalityKey: 1, width: 20)
            )
            assertLayout(layout, width: 20, height: 800)
        }
    }

    func testNestedAnimationModifiersKeepContentAdjacentAnimationAsFinalWriter() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let outer = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.2), value: 1)
            )
            let inner = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.3), value: 1)
            )
            let content = graph.makeInput(
                value: TransactionReportingAnimationContent(equalityKey: 1, width: 10)
            )

            let outputs = _AnimationModifier<Int>._makeView(
                modifier: _GraphValue(_attribute: outer),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, outerInputs in
                _AnimationModifier<Int>._makeView(
                    modifier: _GraphValue(_attribute: inner),
                    inputs: outerInputs
                ) { _, innerInputs in
                    TransactionReportingAnimationContent._makeView(
                        view: _GraphValue(_attribute: content),
                        inputs: innerInputs
                    )
                }
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            outer.setValue(
                _AnimationModifier(animation: .linear(duration: 0.2), value: 2)
            )
            inner.setValue(
                _AnimationModifier(animation: .linear(duration: 0.3), value: 2)
            )

            assertLayout(layout, width: 10, height: 730)
        }
    }

    func testNestedAnimationModifierClearThenSetKeepsContentAdjacentSetAsFinalWriter() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let outerClear = graph.makeInput(
                value: _AnimationModifier(animation: nil, value: 1)
            )
            let innerSet = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.3), value: 1)
            )
            let content = graph.makeInput(
                value: TransactionReportingAnimationContent(equalityKey: 1, width: 10)
            )

            let outputs = _AnimationModifier<Int>._makeView(
                modifier: _GraphValue(_attribute: outerClear),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, outerInputs in
                _AnimationModifier<Int>._makeView(
                    modifier: _GraphValue(_attribute: innerSet),
                    inputs: outerInputs
                ) { _, innerInputs in
                    TransactionReportingAnimationContent._makeView(
                        view: _GraphValue(_attribute: content),
                        inputs: innerInputs
                    )
                }
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            outerClear.setValue(
                _AnimationModifier(animation: nil, value: 2)
            )
            innerSet.setValue(
                _AnimationModifier(animation: .linear(duration: 0.3), value: 2)
            )

            assertLayout(layout, width: 10, height: 730)
        }
    }

    func testNestedAnimationModifierSetThenClearKeepsContentAdjacentClearAsFinalWriter() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let outerSet = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.2), value: 1)
            )
            let innerClear = graph.makeInput(
                value: _AnimationModifier(animation: nil, value: 1)
            )
            let content = graph.makeInput(
                value: TransactionReportingAnimationContent(equalityKey: 1, width: 10)
            )

            let outputs = _AnimationModifier<Int>._makeView(
                modifier: _GraphValue(_attribute: outerSet),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, outerInputs in
                _AnimationModifier<Int>._makeView(
                    modifier: _GraphValue(_attribute: innerClear),
                    inputs: outerInputs
                ) { _, innerInputs in
                    TransactionReportingAnimationContent._makeView(
                        view: _GraphValue(_attribute: content),
                        inputs: innerInputs
                    )
                }
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            outerSet.setValue(
                _AnimationModifier(animation: .linear(duration: 0.2), value: 2)
            )
            innerClear.setValue(
                _AnimationModifier(animation: nil, value: 2)
            )

            assertLayout(layout, width: 10, height: 600)
        }
    }

    func testAnimationModifierListInjectsAnimationOnlyAfterObservedValueChanges() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            let outputs = _AnimationModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                let transaction = inputs.base.transaction
                let list: Attribute<any ViewList> = graph.makeRule {
                    let currentTransaction = transaction.value
                    let duration = currentTransaction.animation?.box.duration ?? -1
                    let marker = currentTransaction[AnimationViewTransactionMarkerKey.self]
                    return TransactionReportingAnimationViewList(
                        countValue: marker + Int(duration * 100)
                    )
                }
                return _ViewListOutputs(
                    views: .dynamicList(list, nil),
                    nextImplicitID: 0,
                    staticCount: nil
                )
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 2)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 725)
        }
    }

    func testAnimationModifierListAnimationExpiresAfterTransactionSeedAdvances() throws {
        let host = GraphHost()

        try host.data.withCurrent {
            let graph = host.data.graph
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            let contentWidth = graph.makeInput(value: 10)
            let outputs = _AnimationModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                let transaction = inputs.base.transaction
                let list: Attribute<any ViewList> = graph.makeRule {
                    let currentTransaction = transaction.value
                    let duration = currentTransaction.animation?.box.duration ?? -1
                    let marker = currentTransaction[AnimationViewTransactionMarkerKey.self]
                    return TransactionReportingAnimationViewList(
                        countValue: contentWidth.value + marker + Int(duration * 100)
                    )
                }
                return _ViewListOutputs(
                    views: .dynamicList(list, nil),
                    nextImplicitID: 0,
                    staticCount: nil
                )
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 810)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 2)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 735)

            host.data.transactionSeed &+= 1
            contentWidth.setValue(20)
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 820)
        }
    }

    func testAnimationModifierListNilAnimationClearsInheritedAnimationOnValueChange() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: nil, value: 1)
            )
            let outputs = _AnimationModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                let transaction = inputs.base.transaction
                let list: Attribute<any ViewList> = graph.makeRule {
                    let currentTransaction = transaction.value
                    let duration = currentTransaction.animation?.box.duration ?? -1
                    let marker = currentTransaction[AnimationViewTransactionMarkerKey.self]
                    return TransactionReportingAnimationViewList(
                        countValue: marker + Int(duration * 100)
                    )
                }
                return _ViewListOutputs(
                    views: .dynamicList(list, nil),
                    nextImplicitID: 0,
                    staticCount: nil
                )
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            modifier.setValue(
                _AnimationModifier(animation: nil, value: 2)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 600)
        }
    }

    func testAnimationModifierListHonorsInheritedDisablesAnimations() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent.disablesAnimations = true
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            let outputs = _AnimationModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                let transaction = inputs.base.transaction
                let list: Attribute<any ViewList> = graph.makeRule {
                    let currentTransaction = transaction.value
                    let duration = currentTransaction.animation?.box.duration ?? -1
                    let marker = currentTransaction[AnimationViewTransactionMarkerKey.self]
                    return TransactionReportingAnimationViewList(
                        countValue: marker + Int(duration * 100)
                    )
                }
                return _ViewListOutputs(
                    views: .dynamicList(list, nil),
                    nextImplicitID: 0,
                    staticCount: nil
                )
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 2)
            )
            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)
        }
    }

    func testNestedAnimationModifierListKeepsContentAdjacentAnimationAsFinalWriter() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let outer = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.2), value: 1)
            )
            let inner = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.3), value: 1)
            )
            let outputs = _AnimationModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: outer),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, outerInputs in
                _AnimationModifier<Int>._makeViewList(
                    modifier: _GraphValue(_attribute: inner),
                    inputs: outerInputs
                ) { _, innerInputs in
                    self.makeTransactionReportingViewList(graph: graph, inputs: innerInputs)
                }
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            outer.setValue(
                _AnimationModifier(animation: .linear(duration: 0.2), value: 2)
            )
            inner.setValue(
                _AnimationModifier(animation: .linear(duration: 0.3), value: 2)
            )

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 730)
        }
    }

    func testNestedAnimationModifierListClearThenSetKeepsContentAdjacentSetAsFinalWriter() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let outerClear = graph.makeInput(
                value: _AnimationModifier(animation: nil, value: 1)
            )
            let innerSet = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.3), value: 1)
            )
            let outputs = _AnimationModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: outerClear),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, outerInputs in
                _AnimationModifier<Int>._makeViewList(
                    modifier: _GraphValue(_attribute: innerSet),
                    inputs: outerInputs
                ) { _, innerInputs in
                    self.makeTransactionReportingViewList(graph: graph, inputs: innerInputs)
                }
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            outerClear.setValue(
                _AnimationModifier(animation: nil, value: 2)
            )
            innerSet.setValue(
                _AnimationModifier(animation: .linear(duration: 0.3), value: 2)
            )

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 730)
        }
    }

    func testNestedAnimationModifierListSetThenClearKeepsContentAdjacentClearAsFinalWriter() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let outerSet = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.2), value: 1)
            )
            let innerClear = graph.makeInput(
                value: _AnimationModifier(animation: nil, value: 1)
            )
            let outputs = _AnimationModifier<Int>._makeViewList(
                modifier: _GraphValue(_attribute: outerSet),
                inputs: makeViewListInputs(graph: graph, transaction: parent)
            ) { _, outerInputs in
                _AnimationModifier<Int>._makeViewList(
                    modifier: _GraphValue(_attribute: innerClear),
                    inputs: outerInputs
                ) { _, innerInputs in
                    self.makeTransactionReportingViewList(graph: graph, inputs: innerInputs)
                }
            }
            let list = try XCTUnwrap(dynamicListAttribute(from: outputs))

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 800)

            outerSet.setValue(
                _AnimationModifier(animation: .linear(duration: 0.2), value: 2)
            )
            innerClear.setValue(
                _AnimationModifier(animation: nil, value: 2)
            )

            XCTAssertEqual(list.value.count(style: _ViewList_IteratorStyle()), 600)
        }
    }

    func testAnimationModifierNilAnimationClearsInheritedAnimationOnValueChange() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: nil, value: 1)
            )
            let content = graph.makeInput(
                value: TransactionReportingAnimationContent(equalityKey: 1, width: 10)
            )
            let outputs = _AnimationModifier<Int>._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                TransactionReportingAnimationContent._makeView(
                    view: _GraphValue(_attribute: content),
                    inputs: inputs
                )
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            modifier.setValue(
                _AnimationModifier(animation: nil, value: 2)
            )
            assertLayout(layout, width: 10, height: 600)
        }
    }

    func testAnimationModifierHonorsInheritedDisablesAnimations() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        try ref.withCurrent {
            var parent = Transaction(animation: .linear(duration: 1.0))
            parent.disablesAnimations = true
            parent[AnimationViewTransactionMarkerKey.self] = 700
            let modifier = graph.makeInput(
                value: _AnimationModifier(animation: .linear(duration: 0.25), value: 1)
            )
            let content = graph.makeInput(
                value: TransactionReportingAnimationContent(equalityKey: 1, width: 10)
            )
            let outputs = _AnimationModifier<Int>._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewInputs(graph: graph, transaction: parent)
            ) { _, inputs in
                TransactionReportingAnimationContent._makeView(
                    view: _GraphValue(_attribute: content),
                    inputs: inputs
                )
            }
            let layout = try XCTUnwrap(outputs._layoutComputer.attribute)

            assertLayout(layout, width: 10, height: 800)

            modifier.setValue(
                _AnimationModifier(animation: .linear(duration: 0.25), value: 2)
            )
            assertLayout(layout, width: 10, height: 800)
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        transaction: Transaction
    ) -> _ViewInputs {
        _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: EnvironmentValues()),
                transaction: graph.makeInput(value: transaction)
            ),
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

    private func makeViewListInputs(
        graph: _AGGraph,
        transaction: Transaction
    ) -> _ViewListInputs {
        _ViewListInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: EnvironmentValues()),
                transaction: graph.makeInput(value: transaction)
            ),
            implicitID: 0,
            options: [],
            _traits: OptionalAttribute(),
            traitKeys: nil,
            containerContext: nil,
            contentOffset: nil,
            debugReplaceableViewCount: nil
        )
    }

    private func makeTransactionReportingViewList(
        graph: _AGGraph,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let transaction = inputs.base.transaction
        let list: Attribute<any ViewList> = graph.makeRule {
            let currentTransaction = transaction.value
            let duration = currentTransaction.animation?.box.duration ?? -1
            let marker = currentTransaction[AnimationViewTransactionMarkerKey.self]
            return TransactionReportingAnimationViewList(
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
