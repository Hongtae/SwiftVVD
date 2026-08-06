import XCTest
@testable import VUI

private struct PrimitiveOnlyProbe: PrimitiveView {
    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        _ViewOutputs()
    }
}

private struct UnaryBodyProbe: View, UnaryView {
    var body: EmptyView { EmptyView() }
}

private struct UnaryStoredInput: GraphInput {
    static var defaultValue: Int { 0 }
}

private struct UnaryIncomingInput: GraphInput {
    static var defaultValue: Int { 0 }
}

private func makeViewListCountInputs(graph: _AGGraph) -> _ViewListCountInputs {
    _ViewListCountInputs(
        base: _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        )
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

private func isPrimitiveView(_ type: Any.Type) -> Bool {
    type is any PrimitiveView.Type
}

private func isUnaryView(_ type: Any.Type) -> Bool {
    type is any UnaryView.Type
}

final class PrimitiveViewTests: XCTestCase {
    func testPrimitiveAndUnaryRolesRemainIndependent() {
        XCTAssertTrue(isPrimitiveView(PrimitiveOnlyProbe.self))
        XCTAssertFalse(isUnaryView(PrimitiveOnlyProbe.self))
        XCTAssertFalse(isPrimitiveView(UnaryBodyProbe.self))
        XCTAssertTrue(isUnaryView(UnaryBodyProbe.self))

        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            let inputs = makeViewListCountInputs(graph: graph)
            XCTAssertNil(PrimitiveOnlyProbe._viewListCount(inputs: inputs))
            XCTAssertEqual(UnaryBodyProbe._viewListCount(inputs: inputs), 1)
        }
    }

    func testObservedUnaryPrimitiveFamiliesUseBothRoles() {
        XCTAssertTrue(isPrimitiveView(Spacer.self))
        XCTAssertTrue(isUnaryView(Spacer.self))
        XCTAssertTrue(isPrimitiveView(HStack<EmptyView>.self))
        XCTAssertTrue(isUnaryView(HStack<EmptyView>.self))
        XCTAssertTrue(isPrimitiveView(VStack<EmptyView>.self))
        XCTAssertTrue(isUnaryView(VStack<EmptyView>.self))
        XCTAssertTrue(isPrimitiveView(ZStack<EmptyView>.self))
        XCTAssertTrue(isUnaryView(ZStack<EmptyView>.self))
    }

    func testObservedMultiViewAndSpecializedListFamiliesAreNotUnaryMarkers() {
        XCTAssertTrue(isPrimitiveView(Group<EmptyView>.self))
        XCTAssertFalse(isUnaryView(Group<EmptyView>.self))
        XCTAssertTrue(isPrimitiveView(Text.self))
        XCTAssertFalse(isUnaryView(Text.self))
        XCTAssertTrue(isPrimitiveView(Image.self))
        XCTAssertFalse(isUnaryView(Image.self))
        XCTAssertTrue(isPrimitiveView(EmptyView.self))
        XCTAssertFalse(isUnaryView(EmptyView.self))
    }

    func testObservedNeverBodyExceptionsRemainDistinctFromPrimitiveView() {
        XCTAssertTrue(isPrimitiveView(Section<EmptyView, EmptyView, EmptyView>.self))
        XCTAssertTrue(isPrimitiveView(PlaceholderContentView<Int>.self))
        XCTAssertTrue(isPrimitiveView(_ViewModifier_Content<EmptyModifier>.self))

        XCTAssertFalse(isPrimitiveView(ModifiedContent<EmptyView, EmptyModifier>.self))
        XCTAssertFalse(isPrimitiveView(IDView<EmptyView, Int>.self))
    }

    func testTextAndImageKeepTheirSpecializedSingleItemCounts() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        ref.withCurrent {
            let inputs = makeViewListCountInputs(graph: graph)
            XCTAssertEqual(Text._viewListCount(inputs: inputs), 1)
            XCTAssertEqual(Image._viewListCount(inputs: inputs), 1)
        }
    }

    func testUnaryListHelpersKeepGeneratorSpecializations() throws {
        // ASSERTIONS unaryViewGeneratorStructureObserved
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        try ref.withCurrent {
            let viewInputs = makeViewInputs(graph: graph)
            let listInputs = viewInputs.listInputs
            let source = graph.makeInput(value: EmptyView())

            let typedOutputs = _ViewListOutputs.unaryViewList(
                view: _GraphValue(_attribute: source),
                inputs: listInputs
            )
            guard case .staticList(let typedList) = typedOutputs.views,
                  case .unaryElements(let typedElements) = typedList else {
                return XCTFail("Expected typed unary static-list storage.")
            }
            let typed = try XCTUnwrap(
                typedElements as? UnaryElements<TypedUnaryViewGenerator>
            )
            XCTAssertEqual(
                Mirror(reflecting: typed).children.compactMap(\.label),
                ["body", "baseInputs"]
            )
            XCTAssertEqual(
                typed.body.view.identifier,
                source.identifier.rawValue
            )
            XCTAssertEqual(
                ObjectIdentifier(typed.body.viewType),
                ObjectIdentifier(EmptyView.self)
            )

            let bodyOutputs = _ViewListOutputs.unaryViewList(
                viewType: UnaryBodyProbe.self,
                inputs: listInputs
            ) { _ in
                _ViewOutputs()
            }
            guard case .staticList(let bodyList) = bodyOutputs.views,
                  case .unaryElements(let bodyElements) = bodyList else {
                return XCTFail("Expected body unary static-list storage.")
            }
            let body = try XCTUnwrap(
                bodyElements as? UnaryElements<BodyUnaryViewGenerator>
            )
            XCTAssertEqual(
                Mirror(reflecting: body).children.compactMap(\.label),
                ["body", "baseInputs"]
            )
            XCTAssertEqual(
                ObjectIdentifier(body.body.viewType),
                ObjectIdentifier(UnaryBodyProbe.self)
            )
        }
    }

    func testBodyUnaryElementsMergeStoredAndIncomingInputs() throws {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)
        try ref.withCurrent {
            var listInputs = makeViewInputs(graph: graph).listInputs
            listInputs.base[UnaryStoredInput.self] = 11

            var observedStored = 0
            var observedIncoming = 0
            let outputs = _ViewListOutputs.unaryViewList(
                viewType: UnaryBodyProbe.self,
                inputs: listInputs
            ) { inputs in
                observedStored = inputs.base[UnaryStoredInput.self]
                observedIncoming = inputs.base[UnaryIncomingInput.self]
                return _ViewOutputs()
            }
            guard case .staticList(let list) = outputs.views,
                  case .unaryElements(let elements) = list else {
                return XCTFail("Expected unary static-list storage.")
            }

            var incomingInputs = makeViewInputs(graph: graph)
            incomingInputs.base[UnaryIncomingInput.self] = 22
            XCTAssertNotNil(
                elements.makeOneElement(
                    at: 0,
                    inputs: incomingInputs
                ) { inputs, makeView in
                    makeView(inputs)
                }
            )
            XCTAssertEqual(observedStored, 11)
            XCTAssertEqual(observedIncoming, 22)

            var from = 2
            let skipped = elements.makeElements(
                from: &from,
                inputs: incomingInputs,
                indirectMap: nil
            ) { _, _ in
                XCTFail("Skipped unary elements must not materialize a view.")
                return (nil, false)
            }
            XCTAssertNil(skipped.0)
            XCTAssertTrue(skipped.1)
            XCTAssertEqual(from, 1)
        }
    }
}
