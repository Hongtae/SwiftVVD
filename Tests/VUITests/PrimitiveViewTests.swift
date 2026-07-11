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

private func makeViewListCountInputs(graph: _AGGraph) -> _ViewListCountInputs {
    _ViewListCountInputs(
        base: _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(
                CachedEnvironment(
                    environment: graph.makeInput(value: EnvironmentValues())
                )
            ),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
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
}
