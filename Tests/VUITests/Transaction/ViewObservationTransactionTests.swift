import Foundation
import Observation
import XCTest
@testable import VUI

@Observable
private final class ViewObservationTransactionModel {
    var value: CGFloat = 10
}

private struct ViewObservationTransactionKey: TransactionKey {
    static let defaultValue = 0
}

private enum ViewObservationTransactionProbeError: Error {
    case expected
}

private struct ObservationTransactionRoot: View {
    let model: ViewObservationTransactionModel

    var body: ObservationTransactionLeaf {
        ObservationTransactionLeaf(width: model.value)
    }
}

private struct ObservationTransactionLeaf: View, TestPrimitiveView {
    var width: CGFloat

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        let layout = graph.makeRule {
            let leaf = view._attribute.value
            return LayoutComputer.fixed(CGSize(width: leaf.width, height: 12))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct ObservationAnimatableTransactionRoot: View {
    let model: ViewObservationTransactionModel

    var body: ObservationAnimatableTransactionLeaf {
        ObservationAnimatableTransactionLeaf(width: model.value)
    }
}

private struct ObservationAnimatableTransactionLeaf: View, TestPrimitiveView, Animatable {
    var width: CGFloat

    typealias Body = Never

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        var animatedView = view
        Self._makeAnimatable(value: &animatedView, inputs: inputs.base)
        let layout = graph.makeRule {
            let leaf = animatedView._attribute.value
            return LayoutComputer.fixed(CGSize(width: leaf.width, height: 12))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

private final class StateAnimatableTransactionProbe {
    var toggle: (() -> Void)?
}

private struct ShapeLeafFrameCacheIDs: Equatable {
    var inputPosition: AGAttribute
    var inputSize: AGAttribute
    var sourcePosition: AGAttribute?
    var sourceSize: AGAttribute?
    var presentationPosition: AGAttribute?
    var presentationSize: AGAttribute?

    init(inputs: _ViewInputs) {
        let frame = inputs.base.cachedEnvironment.value.animatedFrame
        inputPosition = inputs.position.identifier
        inputSize = inputs.size.identifier
        sourcePosition = frame?.position.identifier
        sourceSize = frame?.size.identifier
        presentationPosition = frame?._animatedPosition?.identifier
        presentationSize = frame?._animatedSize?.identifier
    }
}

private final class ShapeLeafFrameCacheProbe {
    var beforeBody: ShapeLeafFrameCacheIDs?
    var afterBody: ShapeLeafFrameCacheIDs?
}

private struct ShapeLeafFrameCacheProbeModifier: ViewModifier {
    let probe: ShapeLeafFrameCacheProbe

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        let probe = modifier._attribute.value.probe
        probe.beforeBody = ShapeLeafFrameCacheIDs(inputs: inputs)
        let outputs = body(_Graph(), inputs)
        probe.afterBody = ShapeLeafFrameCacheIDs(inputs: inputs)
        return outputs
    }
}

private struct ShapeLeafFrameCacheProbeRoot: View {
    let probe: ShapeLeafFrameCacheProbe

    var body: some View {
        Rectangle()
            .modifier(ShapeLeafFrameCacheProbeModifier(probe: probe))
            .frame(width: 180, height: 96)
            .animation(.default, value: false)
    }
}

private struct StateAnimatableTransactionRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: ObservationAnimatableTransactionLeaf {
        probe.toggle = {
            expanded.toggle()
        }
        return ObservationAnimatableTransactionLeaf(width: expanded ? 24 : 10)
    }
}

private struct AnimationLabDisplayLeaf: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 20, height: 20))
        }
        let displayList: Attribute<DisplayList> = graph.makeRule {
            var list = DisplayList()
            list.appendDebugItem(bounds: CGRect(x: 0, y: 0, width: 20, height: 20)) { _ in }
            return list
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)
        return outputs
    }
}

private struct AnimationLabItemLeaf: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }

        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 20, height: 20))
        }
        let displayList: Attribute<DisplayList> = graph.makeRule {
            var list = DisplayList()
            list.appendItem(bounds: CGRect(x: 0, y: 0, width: 20, height: 20)) { _ in }
            return list
        }
        var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(layout))
        outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)
        return outputs
    }
}

private struct StateAnimationLabModifierStackRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return AnimationLabDisplayLeaf()
            .scaleEffect(expanded ? 1.08 : 0.78)
            .rotationEffect(.degrees(expanded ? 8 : -8))
            .offset(x: expanded ? 42 : -42, y: expanded ? 8 : -8)
            .opacity(expanded ? 0.92 : 0.55)
    }
}

private struct StateScaleEffectOnlyRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return AnimationLabItemLeaf()
            .scaleEffect(expanded ? 1.08 : 0.78)
    }
}

private struct StateOffsetEffectOnlyRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return AnimationLabItemLeaf()
            .offset(
                x: expanded ? 42 : -42,
                y: expanded ? 8 : -8
            )
    }
}

private struct StateRotationEffectOnlyRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return AnimationLabItemLeaf()
            .rotationEffect(.degrees(expanded ? 8 : -8))
    }
}

private struct StateOpacityEffectOnlyRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return AnimationLabItemLeaf()
            .opacity(expanded ? 0.92 : 0.55)
    }
}

private struct StateShapeFillColorOnlyRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return RoundedRectangle(cornerRadius: 10)
            .fill(expanded ? Color.purple : Color.blue)
            .frame(width: 72, height: 72)
    }
}

private struct StateShapeFillMeshGradientOnlyRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var shifted = false

    var body: some View {
        probe.toggle = {
            shifted.toggle()
        }
        return RoundedRectangle(cornerRadius: 10)
            .fill(MeshGradient(
                width: 3,
                height: 3,
                points: [
                    [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                    [0.0, 0.5],
                    shifted ? [0.68, 0.30] : [0.32, 0.70],
                    [1.0, 0.5],
                    [0.0, 1.0], [0.5, 1.0], [1.0, 1.0],
                ],
                colors: shifted
                    ? [
                        .red, .orange, .yellow,
                        .purple, .pink, .green,
                        .blue, .cyan, .mint,
                    ]
                    : [
                        .blue, .cyan, .mint,
                        .indigo, .purple, .pink,
                        .green, .yellow, .orange,
                    ],
                background: .black,
                smoothsColors: true,
                colorSpace: .perceptual
            ))
            .frame(width: 96, height: 72)
    }
}

private struct StateAnimationLabPreMutationRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false
    @State private var runCount = 0

    var body: some View {
        probe.toggle = {
            runCount += 1
            withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                expanded.toggle()
            }
        }
        let markerOffset = CGFloat(runCount) * 0
        return AnimationLabItemLeaf()
            .scaleEffect(expanded ? 1.08 : 0.78)
            .offset(x: markerOffset, y: 0)
    }
}

private struct StateAnimationLabCompletionRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false
    @State private var runCount = 0
    @State private var completionStatus = "idle"

    var body: some View {
        probe.toggle = {
            let nextRun = runCount + 1
            runCount = nextRun
            completionStatus = "spring running"
            withAnimation(
                .spring(duration: 20.0, bounce: 0.35),
                completionCriteria: .logicallyComplete
            ) {
                expanded.toggle()
            } completion: {
                completionStatus = "spring logical completion \(nextRun)"
            }
        }
        let markerOffset = CGFloat(runCount + completionStatus.count) * 0
        return AnimationLabItemLeaf()
            .scaleEffect(expanded ? 1.08 : 0.78)
            .offset(x: markerOffset, y: 0)
    }
}

private struct ShapeAnimatableSizingProbe: Shape {
    var width: CGFloat

    var animatableData: CGFloat {
        get { width }
        set { width = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path(rect)
    }

    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: width, height: 12)
    }
}

private struct StateShapeAnimatableRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: ShapeAnimatableSizingProbe {
        probe.toggle = {
            expanded.toggle()
        }
        return ShapeAnimatableSizingProbe(width: expanded ? 48 : 12)
    }
}

private struct StateAnimationLabShapeFrameRoot: View {
    let probe: StateAnimatableTransactionProbe
    @State private var expanded = false

    var body: some View {
        probe.toggle = {
            expanded.toggle()
        }
        return HStack(spacing: 28) {
            RoundedRectangle(cornerRadius: expanded ? 28 : 10)
                .fill(expanded ? Color.purple : Color.blue)
                .frame(
                    width: expanded ? 180 : 72,
                    height: expanded ? 96 : 72
                )
                .scaleEffect(expanded ? 1.08 : 0.78)
                .rotationEffect(.degrees(expanded ? 8 : -8))
                .offset(
                    x: expanded ? 42 : -42,
                    y: expanded ? 8 : -8
                )
                .opacity(expanded ? 0.92 : 0.55)
        }
        .frame(width: 420, height: 240)
    }
}

@MainActor
private final class ObservationAsyncWaiter {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

final class ViewObservationTransactionTests: XCTestCase {
    // ASSERTIONS shapeLeafRekeysAnimatedFrameToModelGeometryObserved
    func testShapeLeafRekeysAnimatedFrameCacheToModelGeometry() throws {
        let rendererHost = TestViewRendererHost()
        let probe = ShapeLeafFrameCacheProbe()
        let host = ViewGraph(
            rootViewType: ShapeLeafFrameCacheProbeRoot.self,
            content: ShapeLeafFrameCacheProbeRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        let before = try XCTUnwrap(probe.beforeBody)
        let after = try XCTUnwrap(probe.afterBody)

        XCTAssertNotEqual(before.sourcePosition, before.inputPosition)
        XCTAssertNotEqual(before.sourceSize, before.inputSize)
        XCTAssertEqual(after.sourcePosition, after.inputPosition)
        XCTAssertEqual(after.sourceSize, after.inputSize)
        XCTAssertNotEqual(after.presentationPosition, after.inputPosition)
        XCTAssertNotEqual(after.presentationSize, after.inputSize)
    }

    func testDefaultBodyObservationInvalidationPropagatesCurrentTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: ObservationTransactionRoot(model: model))
                let outputs = ObservationTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))
                XCTAssertNil(graph.transaction(for: layoutAttr.identifier))

                var transaction = Transaction()
                transaction[ViewObservationTransactionKey.self] = 7

                withTransaction(transaction) {
                    model.value = 24
                }

                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(propagated[ViewObservationTransactionKey.self], 7)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 24, height: 12))
            }
        }
    }

    func testDefaultBodyObservationAnimatableSourceUsesScopedTransaction() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let model = ViewObservationTransactionModel()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: ObservationAnimatableTransactionRoot(model: model))
                let outputs = ObservationAnimatableTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))

                var transaction = Transaction(animation: .linear(duration: 1.0))
                transaction.disablesAnimations = false
                withTransaction(transaction) {
                    model.value = 24
                }

                host.runTransaction(
                    transaction,
                    do: {
                        host.data.rootSubgraph.update()
                    },
                    id: nil
                )

                let sampledWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                XCTAssertLessThan(sampledWidth, 24)
                XCTAssertGreaterThanOrEqual(sampledWidth, 10)
                XCTAssertTrue(host.data.transaction.isEmpty)
            }
        }
    }

    func testDefaultBodyStateActionAnimatableSourceUsesScopedTransaction() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: StateAnimatableTransactionRoot(probe: probe))
                let outputs = StateAnimatableTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }

                host.flushTransactions()
                host.data.rootSubgraph.update()

                let sampledWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                XCTAssertLessThan(sampledWidth, 24)
                XCTAssertGreaterThanOrEqual(sampledWidth, 10)
                XCTAssertTrue(host.data.transaction.isEmpty)
            }
        }
    }

    func testDefaultBodyStateActionAnimatesAnimationLabModifierStack() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateAnimationLabModifierStackRoot(probe: probe))
                var inputs = makeViewInputs(
                    graph: graph,
                    time: time,
                    size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                )
                inputs.needsGeometry = true
                let outputs = StateAnimationLabModifierStackRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(
                    firstRenderedDebugBounds(
                        in: Attribute<DisplayList>(displayID).value
                    )
                )
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                time.setValue(Time(seconds: 0.5))
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                time.setValue(Time(seconds: 0.6))
                host.data.rootSubgraph.update()
                let midpointBounds = try XCTUnwrap(
                    firstRenderedDebugBounds(
                        in: Attribute<DisplayList>(displayID).value
                    )
                )

                time.setValue(Time(seconds: 2.0))
                host.data.rootSubgraph.update()
                let finalBounds = try XCTUnwrap(
                    firstRenderedDebugBounds(
                        in: Attribute<DisplayList>(displayID).value
                    )
                )

                XCTAssertNotEqual(initialBounds, finalBounds)
                XCTAssertNotEqual(midpointBounds, finalBounds)
                XCTAssertGreaterThan(midpointBounds.minX, initialBounds.minX)
                XCTAssertLessThan(midpointBounds.minX, finalBounds.minX)
            }
        }
    }

    func testDefaultBodyStateActionAnimationLabModifierStackSamplesEveryTenthSecond() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateAnimationLabModifierStackRoot(probe: probe))
                var inputs = makeViewInputs(
                    graph: graph,
                    time: time,
                    size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                )
                inputs.needsGeometry = true
                let outputs = StateAnimationLabModifierStackRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(
                    firstRenderedDebugBounds(
                        in: Attribute<DisplayList>(displayID).value
                    )
                )
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                var samples: [(time: Double, bounds: CGRect)] = []
                for step in 0...10 {
                    let sampleTime = Double(step) / 10.0
                    time.setValue(Time(seconds: sampleTime))
                    host.data.rootSubgraph.update()
                    let bounds = try XCTUnwrap(
                        firstRenderedDebugBounds(
                            in: Attribute<DisplayList>(displayID).value
                        )
                    )
                    samples.append((sampleTime, bounds))
                }

                time.setValue(Time(seconds: 2.0))
                host.data.rootSubgraph.update()
                let finalBounds = try XCTUnwrap(
                    firstRenderedDebugBounds(
                        in: Attribute<DisplayList>(displayID).value
                    )
                )

                let distinctIntermediateMinX = Set(
                    samples.dropFirst().dropLast().map { ($0.bounds.minX * 1_000).rounded() }
                )
                XCTAssertGreaterThanOrEqual(distinctIntermediateMinX.count, 3)
                XCTAssertEqual(samples.first?.bounds, initialBounds)
                XCTAssertNotEqual(samples.last?.bounds, initialBounds)
                XCTAssertNotEqual(samples.last?.bounds, finalBounds)
                XCTAssertLessThan(samples[1].bounds.minX, finalBounds.minX)
                XCTAssertLessThan(samples[5].bounds.minX, finalBounds.minX)
                XCTAssertGreaterThan(samples[5].bounds.minX, initialBounds.minX)
            }
        }
    }

    func testDefaultBodyStateActionSpringScaleEffectSamplesIntermediateTransform() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateScaleEffectOnlyRoot(probe: probe))
                let outputs = StateScaleEffectOnlyRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                    )
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(
                    firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                )
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                    toggle()
                }
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                var sampledBounds: [CGRect] = []
                for frame in 1...1_800 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    sampledBounds.append(try XCTUnwrap(
                        firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                    ))
                }

                let earlyBounds = sampledBounds[60 - 1]
                let finalBounds = try XCTUnwrap(sampledBounds.last)
                let intermediateBounds = try XCTUnwrap(
                    sampledBounds.first { bounds in
                        bounds.width > initialBounds.width &&
                            bounds.width < finalBounds.width
                    }
                )

                XCTAssertEqual(initialBounds.width, 15.6, accuracy: 0.000_001)
                XCTAssertGreaterThan(intermediateBounds.width, initialBounds.width)
                XCTAssertLessThan(intermediateBounds.width, finalBounds.width)
                XCTAssertGreaterThan(finalBounds.width, earlyBounds.width)
                XCTAssertEqual(finalBounds.width, 21.6, accuracy: 0.000_001)
                XCTAssertEqual(finalBounds.height, 21.6, accuracy: 0.000_001)
            }
        }
    }

    func testDefaultBodyStateActionRootScaleEffectSamplesIntermediateTransform() throws {
        let rendererHost = TestViewRendererHost()
        let probe = StateAnimatableTransactionProbe()
        let host = ViewGraph(
            rootViewType: StateScaleEffectOnlyRoot.self,
            content: StateScaleEffectOnlyRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleBounds(at seconds: Double) throws -> CGRect {
            let time = Time(seconds: seconds)
            rendererHost.currentTimestamp = time
            host.updateOutputs(at: time)
            return try host.data.withCurrent {
                try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                    let layout = try XCTUnwrap(host.rootLayoutComputer).value
                    let proposalSize = CGSize(width: 200, height: 200)
                    layout.place(
                        at: CGPoint(x: proposalSize.width / 2, y: proposalSize.height / 2),
                        anchor: .center,
                        proposal: ProposedViewSize(proposalSize)
                    )
                    host.data.rootSubgraph.update()
                    return try XCTUnwrap(
                        firstItemBounds(in: try XCTUnwrap(host.rootDisplayList?.value))
                    )
                }
            }
        }

        let initialBounds = try sampleBounds(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
            toggle()
        }

        var samples: [(time: Double, bounds: CGRect)] = []
        for frame in 1...1_800 {
            let sampleTime = Double(frame) / 60.0
            let bounds = try sampleBounds(at: sampleTime)
            if frame.isMultiple(of: 6) {
                samples.append((sampleTime, bounds))
            }
        }

        let finalBounds = try XCTUnwrap(samples.last?.bounds)
        let intermediateBounds = try XCTUnwrap(
            samples.first { sample in
                sample.bounds.width > initialBounds.width &&
                    sample.bounds.width < finalBounds.width
            }?.bounds
        )

        XCTAssertEqual(initialBounds.width, 15.6, accuracy: 0.000_001)
        XCTAssertGreaterThan(intermediateBounds.width, initialBounds.width)
        XCTAssertLessThan(intermediateBounds.width, finalBounds.width)
        XCTAssertEqual(finalBounds.width, 21.6, accuracy: 0.001)
        XCTAssertEqual(finalBounds.height, 21.6, accuracy: 0.001)
    }

    func testDefaultBodyStateActionRootOffsetEffectSamplesIntermediateTransform() throws {
        let rendererHost = TestViewRendererHost()
        let probe = StateAnimatableTransactionProbe()
        let host = ViewGraph(
            rootViewType: StateOffsetEffectOnlyRoot.self,
            content: StateOffsetEffectOnlyRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleBounds(at seconds: Double) throws -> CGRect {
            let displayList = try sampleRootDisplayList(
                host: host,
                rendererHost: rendererHost,
                at: seconds
            )
            return try XCTUnwrap(firstItemBounds(in: displayList))
        }

        let initialBounds = try sampleBounds(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, bounds: CGRect)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            samples.append((sampleTime, try sampleBounds(at: sampleTime)))
        }

        let finalBounds = try sampleBounds(at: 2.0)
        let intermediateBounds = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX > initialBounds.minX &&
                    sample.bounds.minX < finalBounds.minX
            }?.bounds
        )

        XCTAssertGreaterThan(intermediateBounds.minX, initialBounds.minX)
        XCTAssertLessThan(intermediateBounds.minX, finalBounds.minX)
        XCTAssertEqual(finalBounds.minX - initialBounds.minX, 84, accuracy: 0.001)
    }

    func testDefaultBodyStateActionRootRotationEffectSamplesIntermediateTransform() throws {
        let rendererHost = TestViewRendererHost()
        let probe = StateAnimatableTransactionProbe()
        let host = ViewGraph(
            rootViewType: StateRotationEffectOnlyRoot.self,
            content: StateRotationEffectOnlyRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleBounds(at seconds: Double) throws -> CGRect {
            let displayList = try sampleRootDisplayList(
                host: host,
                rendererHost: rendererHost,
                at: seconds
            )
            return try XCTUnwrap(firstItemBounds(in: displayList))
        }

        let initialBounds = try sampleBounds(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, bounds: CGRect)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            samples.append((sampleTime, try sampleBounds(at: sampleTime)))
        }

        let finalBounds = try sampleBounds(at: 2.0)
        let minimumBounds = try XCTUnwrap(samples.min { $0.bounds.width < $1.bounds.width }?.bounds)

        XCTAssertLessThan(minimumBounds.width, initialBounds.width)
        XCTAssertEqual(finalBounds.width, initialBounds.width, accuracy: 0.001)
        XCTAssertEqual(finalBounds.height, initialBounds.height, accuracy: 0.001)
    }

    func testDefaultBodyStateActionRootOpacityEffectSamplesIntermediateOpacity() throws {
        let rendererHost = TestViewRendererHost()
        let probe = StateAnimatableTransactionProbe()
        let host = ViewGraph(
            rootViewType: StateOpacityEffectOnlyRoot.self,
            content: StateOpacityEffectOnlyRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleOpacity(at seconds: Double) throws -> Double {
            let displayList = try sampleRootDisplayList(
                host: host,
                rendererHost: rendererHost,
                at: seconds
            )
            return try XCTUnwrap(displayList.itemRecords.first?.opacity)
        }

        let initialOpacity = try sampleOpacity(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, opacity: Double)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            samples.append((sampleTime, try sampleOpacity(at: sampleTime)))
        }

        let finalOpacity = try sampleOpacity(at: 2.0)
        let intermediateOpacity = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.opacity > initialOpacity &&
                    sample.opacity < finalOpacity
            }?.opacity
        )

        XCTAssertEqual(initialOpacity, 0.55, accuracy: 0.001)
        XCTAssertGreaterThan(intermediateOpacity, initialOpacity)
        XCTAssertLessThan(intermediateOpacity, finalOpacity)
        XCTAssertEqual(finalOpacity, 0.92, accuracy: 0.001)
    }

    func testDefaultBodyStateActionRootShapeFillColorSamplesIntermediateColor() throws {
        let rendererHost = TestViewRendererHost()
        let probe = StateAnimatableTransactionProbe()
        let host = ViewGraph(
            rootViewType: StateShapeFillColorOnlyRoot.self,
            content: StateShapeFillColorOnlyRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleColor(at seconds: Double) throws -> Color {
            let displayList = try sampleRootDisplayList(
                host: host,
                rendererHost: rendererHost,
                at: seconds
            )
            guard let color = firstShapeFillColor(in: displayList) else {
                XCTFail(
                    "missing shape fill color at \(seconds): "
                        + displayListSummary(displayList)
                )
                return .clear
            }
            return color
        }

        let initialColor = try sampleColor(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, color: Color)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            samples.append((sampleTime, try sampleColor(at: sampleTime)))
        }

        let finalColor = try sampleColor(at: 2.0)
        let intermediateColor = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.color.backendColor.r > initialColor.backendColor.r &&
                    sample.color.backendColor.r < finalColor.backendColor.r
            }?.color
        )

        XCTAssertEqual(initialColor.backendColor.r, Color.blue.backendColor.r, accuracy: 0.001)
        XCTAssertEqual(initialColor.backendColor.b, Color.blue.backendColor.b, accuracy: 0.001)
        XCTAssertGreaterThan(intermediateColor.backendColor.r, initialColor.backendColor.r)
        XCTAssertLessThan(intermediateColor.backendColor.r, finalColor.backendColor.r)
        XCTAssertEqual(finalColor.backendColor.r, Color.purple.backendColor.r, accuracy: 0.001)
        XCTAssertEqual(finalColor.backendColor.b, Color.purple.backendColor.b, accuracy: 0.001)
    }

    func testDefaultBodyStateActionRootShapeFillMeshSamplesIntermediatePaint() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(
                    value: StateShapeFillMeshGradientOnlyRoot(probe: probe)
                )
                var inputs = makeViewInputs(
                    graph: graph,
                    time: time,
                    size: graph.makeInput(value: ViewSize(width: 200, height: 200))
                )
                inputs.requestsLayoutComputer = true
                let outputs = StateShapeFillMeshGradientOnlyRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                let displayID = try XCTUnwrap(
                    outputs.preferences.value(for: DisplayList.Key.self)
                )

                func sampleMesh(at seconds: Double) throws -> MeshGradient {
                    time.setValue(Time(seconds: seconds))
                    let layout = layoutAttr.value
                    layout.place(
                        at: .zero,
                        anchor: .topLeading,
                        proposal: ProposedViewSize(CGSize(width: 200, height: 200))
                    )
                    host.data.rootSubgraph.update()
                    let displayList = Attribute<DisplayList>(displayID).value
                    guard let mesh = firstShapeFillMeshGradient(in: displayList) else {
                        XCTFail(
                            "missing shape fill mesh at \(seconds): "
                                + displayListSummary(displayList)
                        )
                        throw ViewObservationTransactionProbeError.expected
                    }
                    return mesh
                }

                let initialMesh = try sampleMesh(at: 0)
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.flushTransactions()

                var samples: [MeshGradient] = []
                for step in 0...10 {
                    samples.append(try sampleMesh(at: Double(step) / 10.0))
                }
                let finalMesh = try sampleMesh(at: 2.0)

                func point(_ mesh: MeshGradient, at index: Int) throws -> SIMD2<Float> {
                    guard case let .points(points) = mesh.locations else {
                        throw ViewObservationTransactionProbeError.expected
                    }
                    return points[index]
                }

                func color(_ mesh: MeshGradient, at index: Int) throws -> Color.Resolved {
                    guard case let .resolvedColors(colors) = mesh.colors else {
                        throw ViewObservationTransactionProbeError.expected
                    }
                    return colors[index]
                }

                let initialPoint = try point(initialMesh, at: 4)
                let finalPoint = try point(finalMesh, at: 4)
                let initialColor = try color(initialMesh, at: 0)
                let finalColor = try color(finalMesh, at: 0)
                let intermediateMesh = try XCTUnwrap(
                    samples.dropFirst().dropLast().first { mesh in
                        guard let point = try? point(mesh, at: 4),
                              let color = try? color(mesh, at: 0) else {
                            return false
                        }
                        return point.x > initialPoint.x &&
                            point.x < finalPoint.x &&
                            color.linearRed > initialColor.linearRed &&
                            color.linearRed < finalColor.linearRed
                    }
                )
                let intermediatePoint = try point(intermediateMesh, at: 4)
                let intermediateColor = try color(intermediateMesh, at: 0)

                XCTAssertEqual(initialPoint.x, 0.32, accuracy: 0.000_001)
                XCTAssertEqual(initialPoint.y, 0.70, accuracy: 0.000_001)
                XCTAssertGreaterThan(intermediatePoint.x, initialPoint.x)
                XCTAssertLessThan(intermediatePoint.x, finalPoint.x)
                XCTAssertLessThan(intermediatePoint.y, initialPoint.y)
                XCTAssertGreaterThan(intermediatePoint.y, finalPoint.y)
                XCTAssertGreaterThan(intermediateColor.linearRed, initialColor.linearRed)
                XCTAssertLessThan(intermediateColor.linearRed, finalColor.linearRed)
                XCTAssertEqual(finalPoint.x, 0.68, accuracy: 0.000_001)
                XCTAssertEqual(finalPoint.y, 0.30, accuracy: 0.000_001)
                XCTAssertEqual(
                    finalColor.linearRed,
                    Color.red.resolve(in: EnvironmentValues()).linearRed,
                    accuracy: 0.000_001
                )

                // ASSERTIONS meshGradientResolvedPaintAnimationPathObserved
            }
        }
    }

    func testStateActionPreMutationDoesNotStealSpringTransaction() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateAnimationLabPreMutationRoot(probe: probe))
                let outputs = StateAnimationLabPreMutationRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                    )
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(
                    firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                )
                let toggle = try XCTUnwrap(probe.toggle)

                toggle()
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                XCTAssertTrue(host.hasScheduledViewUpdate)

                var sampledBounds: [CGRect] = []
                for frame in 1...1_800 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    sampledBounds.append(try XCTUnwrap(
                        firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                    ))
                }

                let finalBounds = try XCTUnwrap(sampledBounds.last)
                let intermediateBounds = try XCTUnwrap(
                    sampledBounds.first { bounds in
                        bounds.width > initialBounds.width &&
                            bounds.width < finalBounds.width
                    }
                )

                XCTAssertGreaterThan(intermediateBounds.width, initialBounds.width)
                XCTAssertLessThan(intermediateBounds.width, finalBounds.width)
                XCTAssertEqual(finalBounds.width, 21.6, accuracy: 0.000_001)
            }
        }
    }

    func testStateActionCompletionPreMutationsDoNotStealSpringTransaction() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateAnimationLabCompletionRoot(probe: probe))
                let outputs = StateAnimationLabCompletionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                    )
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(
                    firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                )
                let toggle = try XCTUnwrap(probe.toggle)

                toggle()
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                XCTAssertTrue(host.hasScheduledViewUpdate)

                var sampledBounds: [CGRect] = []
                for frame in 1...1_800 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    sampledBounds.append(try XCTUnwrap(
                        firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                    ))
                }

                let finalBounds = try XCTUnwrap(sampledBounds.last)
                let intermediateBounds = try XCTUnwrap(
                    sampledBounds.first { bounds in
                        bounds.width > initialBounds.width &&
                            bounds.width < finalBounds.width
                    }
                )

                XCTAssertGreaterThan(intermediateBounds.width, initialBounds.width)
                XCTAssertLessThan(intermediateBounds.width, finalBounds.width)
                XCTAssertEqual(finalBounds.width, 21.6, accuracy: 0.000_001)
            }
        }
    }

    func testStateActionCompletionSpringScaleEffectRetargetsWhileAnimating() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateAnimationLabCompletionRoot(probe: probe))
                let outputs = StateAnimationLabCompletionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                    )
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(
                    firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                )
                let toggle = try XCTUnwrap(probe.toggle)

                toggle()
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                for frame in 1...120 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    _ = Attribute<DisplayList>(displayID).value
                }
                let outboundBounds = try XCTUnwrap(
                    firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                )
                XCTAssertGreaterThan(outboundBounds.width, initialBounds.width)
                XCTAssertLessThan(outboundBounds.width, 21.6)

                toggle()
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                var retargetSamples: [CGRect] = []
                for frame in 121...1_920 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    retargetSamples.append(try XCTUnwrap(
                        firstItemBounds(in: Attribute<DisplayList>(displayID).value)
                    ))
                }

                let finalBounds = try XCTUnwrap(retargetSamples.last)
                let intermediateBounds = try XCTUnwrap(
                    retargetSamples.first { bounds in
                        bounds.width < outboundBounds.width &&
                            bounds.width > finalBounds.width
                    }
                )

                XCTAssertLessThan(intermediateBounds.width, outboundBounds.width)
                XCTAssertGreaterThan(intermediateBounds.width, finalBounds.width)
                XCTAssertEqual(finalBounds.width, 15.6, accuracy: 0.02)
            }
        }
    }

    func testDefaultBodyStateActionShapeAnimatableDataSamplesEveryTenthSecond() throws {
        let rendererHost = TestViewRendererHost()
        let host = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = host
        let probe = StateAnimatableTransactionProbe()

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let time = graph.makeInput(value: Time(seconds: 0))
                let source = graph.makeInput(value: StateShapeAnimatableRoot(probe: probe))
                var inputs = makeViewInputs(graph: graph, time: time)
                inputs.requestsLayoutComputer = true
                let outputs = StateShapeAnimatableRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                let initialWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.flushTransactions()
                host.data.rootSubgraph.update()
                _ = layoutAttr.value.sizeThatFits(.unspecified)

                // Generic AnimatorState preserves its first two display-lane
                // samples before entering the running phase. Drive those
                // frames explicitly before taking tenth-second samples.
                for warmupTime in [1.0 / 60.0, 2.0 / 60.0] {
                    time.setValue(Time(seconds: warmupTime))
                    host.data.rootSubgraph.update()
                    _ = layoutAttr.value.sizeThatFits(.unspecified)
                }

                var samples: [(time: Double, width: CGFloat)] = []
                for step in 1...10 {
                    let sampleTime = Double(step) / 10.0
                    time.setValue(Time(seconds: sampleTime))
                    host.data.rootSubgraph.update()
                    samples.append((
                        sampleTime,
                        layoutAttr.value.sizeThatFits(.unspecified).width
                    ))
                }

                time.setValue(Time(seconds: 2.0))
                host.data.rootSubgraph.update()
                let finalWidth = layoutAttr.value.sizeThatFits(.unspecified).width

                XCTAssertEqual(initialWidth, 12)
                XCTAssertEqual(finalWidth, 48)
                XCTAssertGreaterThan(samples[0].width, initialWidth)
                XCTAssertLessThan(samples[0].width, finalWidth)
                XCTAssertGreaterThan(samples[4].width, samples[0].width)
                XCTAssertLessThan(samples[4].width, finalWidth)
            }
        }
    }

    func testDefaultBodyStateActionAnimationLabShapeFrameSamplesEveryTenthSecond() throws {
        let rendererHost = TestViewRendererHost()
        let probe = StateAnimatableTransactionProbe()
        let host = ViewGraph(
            rootViewType: StateAnimationLabShapeFrameRoot.self,
            content: StateAnimationLabShapeFrameRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleBounds(at seconds: Double) throws -> CGRect {
            host.updateOutputs(at: Time(seconds: seconds))
            return try host.data.withCurrent {
                try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                    let layout = try XCTUnwrap(host.rootLayoutComputer).value
                    let proposalSize = CGSize(width: 420, height: 240)
                    layout.place(
                        at: CGPoint(x: proposalSize.width / 2, y: proposalSize.height / 2),
                        anchor: .center,
                        proposal: ProposedViewSize(proposalSize)
                    )
                    return try XCTUnwrap(host.rootDisplayList?.value.interpolationBounds)
                }
            }
        }

        let initialBounds = try sampleBounds(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, bounds: CGRect)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            samples.append((sampleTime, try sampleBounds(at: sampleTime)))
        }

        let finalBounds = try sampleBounds(at: 2.0)

        let firstGrowingSample = try XCTUnwrap(
            samples.dropFirst().first { $0.bounds.width > initialBounds.width }
        )

        XCTAssertNotEqual(initialBounds, finalBounds)
        XCTAssertEqual(samples[0].bounds.width, initialBounds.width, accuracy: 0.001)
        XCTAssertLessThan(firstGrowingSample.bounds.width, finalBounds.width)
        XCTAssertGreaterThan(samples[5].bounds.width, samples[1].bounds.width)
        XCTAssertLessThan(samples[5].bounds.width, finalBounds.width)
    }

    func testDefaultBodyStateActionAnimationLabFullStackSamplesBoundsAndOpacityEveryTenthSecond() throws {
        let rendererHost = TestViewRendererHost()
        let probe = StateAnimatableTransactionProbe()
        let host = ViewGraph(
            rootViewType: StateAnimationLabShapeFrameRoot.self,
            content: StateAnimationLabShapeFrameRoot(probe: probe),
            rendererHost: rendererHost
        )
        rendererHost.storage = host

        func sampleDisplayList(at seconds: Double) throws -> DisplayList {
            host.updateOutputs(at: Time(seconds: seconds))
            return try host.data.withCurrent {
                try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                    let layout = try XCTUnwrap(host.rootLayoutComputer).value
                    let proposalSize = CGSize(width: 420, height: 240)
                    layout.place(
                        at: CGPoint(x: proposalSize.width / 2, y: proposalSize.height / 2),
                        anchor: .center,
                        proposal: ProposedViewSize(proposalSize)
                    )
                    host.data.rootSubgraph.update()
                    return try XCTUnwrap(host.rootDisplayList?.value)
                }
            }
        }

        let initialDisplayList = try sampleDisplayList(at: 0)
        let initialBounds = try XCTUnwrap(initialDisplayList.interpolationBounds)
        let initialOpacity = try XCTUnwrap(firstOpacity(in: initialDisplayList))
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, bounds: CGRect, opacity: Double)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            let displayList = try sampleDisplayList(at: sampleTime)
            samples.append((
                sampleTime,
                try XCTUnwrap(displayList.interpolationBounds),
                try XCTUnwrap(firstOpacity(in: displayList))
            ))
        }

        let finalDisplayList = try sampleDisplayList(at: 2.0)
        let finalBounds = try XCTUnwrap(finalDisplayList.interpolationBounds)
        let finalOpacity = try XCTUnwrap(firstOpacity(in: finalDisplayList))
        let firstMovingSample = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.bounds.minX > initialBounds.minX &&
                    sample.bounds.minX < finalBounds.minX
            },
            """
            expected intermediate x movement:
            initial=\(initialBounds)
            final=\(finalBounds)
            samples=\(samples)
            """
        )
        let firstOpacitySample = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.opacity > initialOpacity &&
                    sample.opacity < finalOpacity
            },
            """
            expected intermediate opacity:
            initial=\(initialOpacity)
            final=\(finalOpacity)
            samples=\(samples)
            """
        )

        XCTAssertGreaterThan(firstMovingSample.bounds.minX, initialBounds.minX)
        XCTAssertLessThan(firstMovingSample.bounds.minX, finalBounds.minX)
        XCTAssertGreaterThan(firstOpacitySample.opacity, initialOpacity)
        XCTAssertLessThan(firstOpacitySample.opacity, finalOpacity)
    }

    func testKeyPathThrowingBodyMutationPropagatesScopedTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        do {
            try withTransaction(\.disablesAnimations, true) {
                model.value = 28
                throw ViewObservationTransactionProbeError.expected
            }
            XCTFail("throwing key-path withTransaction returned normally")
        } catch ViewObservationTransactionProbeError.expected {
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertTrue(propagated.disablesAnimations)
                XCTAssertFalse(propagated.tracksVelocity)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 28, height: 12))
            }
        }
    }

    func testKeyPathThrowingCatchMutationDoesNotInheritThrownTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        do {
            try withTransaction(\.disablesAnimations, true) {
                throw ViewObservationTransactionProbeError.expected
            }
            XCTFail("throwing key-path withTransaction returned normally")
        } catch ViewObservationTransactionProbeError.expected {
            model.value = 32
        } catch {
            XCTFail("unexpected error: \(error)")
        }

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                XCTAssertNil(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 32, height: 12))
            }
        }
    }

    func testNestedKeyPathThrowingCatchMutationRestoresOuterTransaction() throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        withTransaction(\.tracksVelocity, true) {
            do {
                try withTransaction(\.disablesAnimations, true) {
                    throw ViewObservationTransactionProbeError.expected
                }
                XCTFail("throwing key-path withTransaction returned normally")
            } catch ViewObservationTransactionProbeError.expected {
                model.value = 36
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }

        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                let propagated = try XCTUnwrap(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertFalse(propagated.disablesAnimations)
                XCTAssertTrue(propagated.tracksVelocity)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 36, height: 12))
            }
        }
    }

    @MainActor
    func testDispatchQueueObservableInvalidationScheduledInsideTransactionDoesNotPropagateScopedTransaction() async throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        var transaction = Transaction(animation: .linear(duration: 0.20))
        transaction[ViewObservationTransactionKey.self] = 11

        let waiter = ObservationAsyncWaiter()
        withTransaction(transaction) {
            DispatchQueue.main.async {
                model.value = 32
                waiter.resume()
            }
        }
        await waiter.wait()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                XCTAssertNil(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 32, height: 12))
            }
        }
    }

    @MainActor
    func testMainActorObservableInvalidationScheduledInsideAnimationDoesNotPropagateScopedTransaction() async throws {
        let host = GraphHost()
        let model = ViewObservationTransactionModel()
        let layoutAttr = try makeObservedLayout(host: host, model: model)

        let waiter = ObservationAsyncWaiter()
        _ = withAnimation(.linear(duration: 0.20)) {
            Task { @MainActor in
                model.value = 48
                waiter.resume()
            }
        }
        await waiter.wait()

        host.data.withCurrent {
            AGSubgraph.withCurrent(host.data.rootSubgraph) {
                host.data.rootSubgraph.update()

                XCTAssertNil(host.data.graph.transaction(for: layoutAttr.identifier))
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 48, height: 12))
            }
        }
    }

    private func makeObservedLayout(
        host: GraphHost,
        model: ViewObservationTransactionModel
    ) throws -> Attribute<LayoutComputer> {
        try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let graph = host.data.graph
                let source = graph.makeInput(value: ObservationTransactionRoot(model: model))
                let outputs = ObservationTransactionRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                XCTAssertEqual(layoutAttr.value.sizeThatFits(.unspecified), CGSize(width: 10, height: 12))
                XCTAssertNil(graph.transaction(for: layoutAttr.identifier))
                return layoutAttr
            }
        }
    }

    private func sampleRootDisplayList(
        host: ViewGraph,
        rendererHost: TestViewRendererHost,
        at seconds: Double
    ) throws -> DisplayList {
        let time = Time(seconds: seconds)
        rendererHost.currentTimestamp = time
        host.updateOutputs(at: time)
        return try host.data.withCurrent {
            try AGSubgraph.withCurrent(host.data.rootSubgraph) {
                let layout = try XCTUnwrap(host.rootLayoutComputer).value
                let proposalSize = CGSize(width: 200, height: 200)
                layout.place(
                    at: CGPoint(x: proposalSize.width / 2, y: proposalSize.height / 2),
                    anchor: .center,
                    proposal: ProposedViewSize(proposalSize)
                )
                host.data.rootSubgraph.update()
                return try XCTUnwrap(host.rootDisplayList?.value)
            }
        }
    }

    private func firstShapeFillColor(in displayList: DisplayList) -> Color? {
        for record in displayList.itemRecords {
            if case let .color(color)? = record.shapeStyle {
                return color
            }
        }
        for effect in displayList.effects {
            if let color = firstShapeFillColor(in: effect.contents) {
                return color
            }
        }
        return nil
    }

    private func firstShapeFillMeshGradient(
        in displayList: DisplayList
    ) -> MeshGradient? {
        for record in displayList.itemRecords {
            if case let .meshGradient(mesh)? = record.shapeStyle {
                return mesh
            }
        }
        for effect in displayList.effects {
            if let mesh = firstShapeFillMeshGradient(in: effect.contents) {
                return mesh
            }
        }
        return nil
    }

    private func firstItemBounds(in displayList: DisplayList) -> CGRect? {
        if let bounds = displayList.itemRecords.compactMap(\.bounds).first {
            return bounds
        }
        for effect in displayList.effects {
            if let bounds = firstItemBounds(in: effect.contents) {
                return bounds
            }
        }
        return nil
    }

    private func firstRenderedDebugBounds(
        in displayList: DisplayList
    ) -> CGRect? {
        if let item = displayList.debugItems.first,
           let bounds = item.record.bounds {
            let offset = CGAffineTransform(
                translationX: item.frame.minX - bounds.minX,
                y: item.frame.minY - bounds.minY
            )
            return bounds.applying(offset).standardized
        }

        for item in displayList.items {
            let nestedBounds: CGRect?
            switch item.value {
            case let .effect(_, contents):
                nestedBounds = firstRenderedDebugBounds(in: contents)
            case let .states(states):
                nestedBounds = states.last.flatMap {
                    firstRenderedDebugBounds(in: $0.1)
                }
            case .content, .empty:
                nestedBounds = nil
            }
            guard let nestedBounds else { continue }

            let placement = CGAffineTransform(
                translationX: item.frame.minX,
                y: item.frame.minY
            )
            if case let .effect(.transform(projection), _) = item.value,
               projection.isAffine {
                return nestedBounds.applying(
                    CGAffineTransform(
                        a: projection.m11,
                        b: projection.m12,
                        c: projection.m21,
                        d: projection.m22,
                        tx: projection.m31,
                        ty: projection.m32
                    ).concatenating(placement)
                ).standardized
            }
            return nestedBounds.applying(placement).standardized
        }
        return nil
    }

    private func firstOpacity(in displayList: DisplayList) -> Double? {
        for record in displayList.itemRecords {
            if let opacity = record.opacity {
                return opacity
            }
        }
        for effect in displayList.effects {
            if let opacity = firstOpacity(in: effect.contents) {
                return opacity
            }
        }
        return nil
    }

    private func displayListSummary(_ displayList: DisplayList, depth: Int = 0) -> String {
        let records = displayList.itemRecords.map { record in
            "kind=\(record.kind) effect=\(String(describing: record.effectKind)) style=\(String(describing: record.shapeStyle)) bounds=\(String(describing: record.bounds))"
        }
        let effects = displayList.effects.enumerated().map { index, effect in
            "effect[\(index)]=\(effect.effect) contents={\(displayListSummary(effect.contents, depth: depth + 1))}"
        }
        return "items=\(records) effects=\(effects) bounds=\(String(describing: displayList.interpolationBounds))"
    }

    private func makeViewInputs(
        graph: _AGGraph,
        time: Attribute<Time>? = nil,
        size: Attribute<ViewSize>? = nil
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            time: time ?? graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
            environment: environment,
            transaction: GraphHost.currentHost.data._transaction
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
            size: size ?? graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
