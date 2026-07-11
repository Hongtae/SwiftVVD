import Foundation
import XCTest
@testable import VUI

private struct LeafLayoutProbe: LeafViewLayout {
    var measuredSize: CGSize
    var measuredSpacing: ViewSpacing

    func spacing() -> ViewSpacing {
        measuredSpacing
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        CGSize(
            width: proposal.width ?? measuredSize.width,
            height: proposal.height ?? measuredSize.height
        )
    }
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
        proposal.replacingUnspecifiedDimensions(by: measuredSize)
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
                    )
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
                computer.sizeThatFits(ProposedViewSize(width: 30, height: nil)),
                CGSize(width: 30, height: 7)
            )
            XCTAssertEqual(computer.spacing.top, 1)
            XCTAssertEqual(computer.spacing.leading, 2)
            XCTAssertEqual(computer.spacing.bottom, 3)
            XCTAssertEqual(computer.spacing.trailing, 4)
            XCTAssertEqual(computer.priority, 0)
        }
    }

    func testLeafLayoutComputerTracksLeafValueChanges() {
        withGraph { graph in
            let leaf = graph.makeInput(
                value: LeafLayoutProbe(
                    measuredSize: CGSize(width: 8, height: 5),
                    measuredSpacing: ViewSpacing()
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
            XCTAssertEqual(updated.spacing.top, 0)
            XCTAssertEqual(updated.spacing.trailing, 0)
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
                computer.sizeThatFits(ProposedViewSize(width: 30, height: 20)),
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
                customInputs: PropertyList(),
                time: graph.makeInput(value: Time(seconds: 0)),
                cachedEnvironment: MutableBox(
                    CachedEnvironment(environment: environment)
                ),
                phase: graph.makeInput(value: Phase()),
                transaction: graph.makeInput(value: Transaction()),
                changedDebugProperties: 0,
                options: [],
                mergedInputs: []
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
