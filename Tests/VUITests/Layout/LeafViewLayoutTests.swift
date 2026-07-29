import Foundation
import XCTest
@testable import VUI

private struct LeafLayoutProbe: LeafViewLayout {
    var measuredSize: CGSize
    var measuredSpacing: Spacing

    func spacing() -> Spacing {
        measuredSpacing
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        CGSize(
            width: proposal.width ?? measuredSize.width,
            height: proposal.height ?? measuredSize.height
        )
    }
}

private func spacingDistance(_ spacing: Spacing, at edge: AbsoluteEdge) -> CGFloat? {
    spacing.minima[Spacing.Key(category: .default, edge: edge)]?.value
}

private struct LeafAnimatableShape: Shape {
    var width: CGFloat

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(rect)
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: proposal.width ?? width, height: proposal.height ?? 8)
    }
}

private struct LeafDefaultSizingShape: Shape {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(rect.insetBy(dx: 20, dy: 30))
    }
}

private final class RootLeafInputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _requestsLayoutComputer = false

    var requestsLayoutComputer: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _requestsLayoutComputer
    }

    func record(_ value: Bool) {
        lock.lock()
        _requestsLayoutComputer = value
        lock.unlock()
    }

    func reset() {
        record(false)
    }
}

private let rootLeafInputCapture = RootLeafInputCapture()

private struct RootLeafLayoutProbe: View {
    var measuredSize: CGSize

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        rootLeafInputCapture.record(inputs.requestsLayoutComputer)
        var outputs = _ViewOutputs()
        makeLeafLayout(&outputs, view: view, inputs: inputs)
        return outputs
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        proposal.fixingUnspecifiedDimensions(at: measuredSize)
    }

    typealias Body = Never
}

extension RootLeafLayoutProbe: PrimitiveView, LeafViewLayout {
}

final class LeafViewLayoutTests: XCTestCase {
    func testSharedHelperInstallsLayoutOnlyWhenRequested() {
        withGraph { graph in
            let leaf = graph.makeInput(
                value: LeafLayoutProbe(
                    measuredSize: CGSize(width: 12, height: 7),
                    measuredSpacing: ViewSpacing(
                        top: 1,
                        leading: 2,
                        bottom: 3,
                        trailing: 4
                    ).spacing
                )
            )

            var unrequestedOutputs = _ViewOutputs()
            LeafLayoutProbe.makeLeafLayout(
                &unrequestedOutputs,
                view: _GraphValue(_attribute: leaf),
                inputs: makeViewInputs(graph: graph, requestsLayoutComputer: false)
            )
            XCTAssertNil(unrequestedOutputs._layoutComputer.attribute)

            var requestedOutputs = _ViewOutputs()
            LeafLayoutProbe.makeLeafLayout(
                &requestedOutputs,
                view: _GraphValue(_attribute: leaf),
                inputs: makeViewInputs(graph: graph, requestsLayoutComputer: true)
            )
            let computer = try! XCTUnwrap(requestedOutputs._layoutComputer.attribute).value
            XCTAssertEqual(computer.sizeThatFits(.unspecified), CGSize(width: 12, height: 7))
            XCTAssertEqual(
                computer.sizeThatFits(_ProposedSize(width: 30, height: nil)),
                CGSize(width: 30, height: 7)
            )
            XCTAssertEqual(spacingDistance(computer.spacing(), at: .top), 1)
            XCTAssertEqual(spacingDistance(computer.spacing(), at: .left), 2)
            XCTAssertEqual(spacingDistance(computer.spacing(), at: .bottom), 3)
            XCTAssertEqual(spacingDistance(computer.spacing(), at: .right), 4)
            XCTAssertEqual(computer.layoutPriority(), 0)
        }
    }

    func testLeafLayoutComputerTracksLeafValueChanges() {
        withGraph { graph in
            let leaf = graph.makeInput(
                value: LeafLayoutProbe(
                    measuredSize: CGSize(width: 8, height: 5),
                    measuredSpacing: Spacing()
                )
            )
            var outputs = _ViewOutputs()
            LeafLayoutProbe.makeLeafLayout(
                &outputs,
                view: _GraphValue(_attribute: leaf),
                inputs: makeViewInputs(graph: graph, requestsLayoutComputer: true)
            )
            let computerAttribute = try! XCTUnwrap(outputs._layoutComputer.attribute)
            XCTAssertEqual(computerAttribute.value.sizeThatFits(.unspecified), CGSize(width: 8, height: 5))

            leaf.setValue(
                LeafLayoutProbe(
                    measuredSize: CGSize(width: 19, height: 11),
                    measuredSpacing: .zero
                )
            )
            let updated = computerAttribute.value
            XCTAssertEqual(updated.sizeThatFits(.unspecified), CGSize(width: 19, height: 11))
            XCTAssertEqual(spacingDistance(updated.spacing(), at: .top), 0)
            XCTAssertEqual(spacingDistance(updated.spacing(), at: .right), 0)
        }
    }

    func testShapeViewRoutesDirectAndAnimatedShapesThroughSharedLeafEngine() {
        withGraph { graph in
            let staticShape = graph.makeInput(
                value: _ShapeView(shape: Rectangle(), style: Color.red)
            )

            let unrequested = _ShapeView<Rectangle, Color>._makeView(
                view: _GraphValue(_attribute: staticShape),
                inputs: makeViewInputs(graph: graph, requestsLayoutComputer: false)
            )
            XCTAssertNil(unrequested._layoutComputer.attribute)

            let requested = _ShapeView<Rectangle, Color>._makeView(
                view: _GraphValue(_attribute: staticShape),
                inputs: makeViewInputs(graph: graph, requestsLayoutComputer: true)
            )
            let computer = try! XCTUnwrap(requested._layoutComputer.attribute).value
            XCTAssertTrue(
                computer.box is LayoutEngineBox<LeafLayoutEngine<_ShapeView<Rectangle, Color>>>
            )
            XCTAssertEqual(
                computer.sizeThatFits(_ProposedSize(width: 30, height: 20)),
                CGSize(width: 30, height: 20)
            )

            let animatableShape = graph.makeInput(
                value: _ShapeView(
                    shape: LeafAnimatableShape(width: 13),
                    style: Color.red
                )
            )
            let animated = _ShapeView<LeafAnimatableShape, Color>._makeView(
                view: _GraphValue(_attribute: animatableShape),
                inputs: makeViewInputs(graph: graph, requestsLayoutComputer: true)
            )
            let animatedComputer = try! XCTUnwrap(animated._layoutComputer.attribute).value
            XCTAssertTrue(
                animatedComputer.box is LayoutEngineBox<LeafLayoutEngine<AnimatedShape<LeafAnimatableShape>>>
            )
            XCTAssertEqual(
                animatedComputer.sizeThatFits(.unspecified),
                CGSize(width: 13, height: 8)
            )
        }
    }

    func testStrokedAnimatableShapePreservesFixedProposalForPathGeometry() {
        withGraph { graph in
            let view = graph.makeInput(
                value: _ShapeView(
                    shape: _StrokedShape(
                        shape: LeafDefaultSizingShape(phase: 0),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    ),
                    style: Color.purple
                )
            )
            let outputs = _ShapeView<
                _StrokedShape<LeafDefaultSizingShape>,
                Color
            >._makeView(
                view: _GraphValue(_attribute: view),
                inputs: makeViewInputs(
                    graph: graph,
                    requestsLayoutComputer: true
                )
            )
            let computer = try! XCTUnwrap(
                outputs._layoutComputer.attribute
            ).value

            XCTAssertTrue(
                computer.box is LayoutEngineBox<
                    LeafLayoutEngine<
                        AnimatedShape<_StrokedShape<LeafDefaultSizingShape>>
                    >
                >
            )
            XCTAssertEqual(
                computer.sizeThatFits(
                    _ProposedSize(width: 240, height: 110)
                ),
                CGSize(width: 240, height: 110)
            )
            XCTAssertEqual(
                computer.sizeThatFits(.unspecified),
                CGSize(width: 10, height: 10)
            )
        }
    }

    func testViewGraphRootRequestsLeafLayoutComputer() throws {
        rootLeafInputCapture.reset()
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: RootLeafLayoutProbe.self,
            content: RootLeafLayoutProbe(
                measuredSize: CGSize(width: 17, height: 9)
            ),
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        XCTAssertTrue(rootLeafInputCapture.requestsLayoutComputer)
        try viewGraph.data.withCurrent {
            let computer = try XCTUnwrap(viewGraph.rootLayoutComputer).value
            XCTAssertEqual(computer.sizeThatFits(.unspecified), CGSize(width: 17, height: 9))
        }
    }

    private func withGraph(_ body: (_AGGraph) -> Void) {
        let graph = _AGGraph()
        let context = _AGGraphContext(graph: graph)
        context.withCurrent {
            body(graph)
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        requestsLayoutComputer: Bool
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        var inputs = _ViewInputs(
            base: _GraphInputs(
                time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: Phase()),
                environment: environment,
                transaction: graph.makeInput(value: Transaction())
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
        inputs.requestsLayoutComputer = requestsLayoutComputer
        return inputs
    }
}
