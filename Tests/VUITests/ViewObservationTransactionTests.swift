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

private struct ObservationTransactionLeaf: View, _PrimitiveView {
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

private struct ObservationAnimatableTransactionLeaf: View, _PrimitiveView, Animatable {
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
}

private final class StateAnimatableTransactionProbe {
    var toggle: (() -> Void)?
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

private struct AnimationLabDisplayLeaf: View, _PrimitiveView {
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

private struct AnimationLabItemLeaf: View, _PrimitiveView {
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

                withAnimation(.linear(duration: 1.0)) {
                    model.value = 24
                }

                host.data.rootSubgraph.update()

                let sampledWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                XCTAssertLessThan(sampledWidth, 24)
                XCTAssertGreaterThanOrEqual(sampledWidth, 10)
                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertNotNil(propagated.animation)
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

                host.data.rootSubgraph.update()

                let sampledWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                XCTAssertLessThan(sampledWidth, 24)
                XCTAssertGreaterThanOrEqual(sampledWidth, 10)
                let propagated = try XCTUnwrap(graph.transaction(for: layoutAttr.identifier))
                XCTAssertNotNil(propagated.animation)
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
                let outputs = StateAnimationLabModifierStackRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                    )
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                time.setValue(Time(seconds: 0.5))
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                time.setValue(Time(seconds: 0.6))
                host.data.rootSubgraph.update()
                let midpointBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)

                time.setValue(Time(seconds: 2.0))
                host.data.rootSubgraph.update()
                let finalBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)

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
                let outputs = StateAnimationLabModifierStackRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 20, height: 20))
                    )
                )
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
                let initialBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                var samples: [(time: Double, bounds: CGRect)] = []
                for step in 0...10 {
                    let sampleTime = Double(step) / 10.0
                    time.setValue(Time(seconds: sampleTime))
                    host.data.rootSubgraph.update()
                    let bounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)
                    samples.append((sampleTime, bounds))
                }

                time.setValue(Time(seconds: 2.0))
                host.data.rootSubgraph.update()
                let finalBounds = try XCTUnwrap(Attribute<DisplayList>(displayID).value.interpolationBounds)

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
                let initialTransform = try XCTUnwrap(
                    Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                )
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
                    toggle()
                }
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                var sampledTransforms: [CGAffineTransform] = []
                for frame in 1...1_800 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    sampledTransforms.append(try XCTUnwrap(
                        Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                    ))
                }

                let earlyTransform = sampledTransforms[60 - 1]
                let finalTransform = try XCTUnwrap(sampledTransforms.last)
                let intermediateTransform = try XCTUnwrap(
                    sampledTransforms.first { transform in
                        transform.a > initialTransform.a &&
                            transform.a < finalTransform.a
                    }
                )

                XCTAssertEqual(initialTransform.a, 0.78, accuracy: 0.000_001)
                XCTAssertGreaterThan(intermediateTransform.a, initialTransform.a)
                XCTAssertLessThan(intermediateTransform.a, finalTransform.a)
                XCTAssertGreaterThan(finalTransform.a, earlyTransform.a)
                XCTAssertEqual(finalTransform.a, 1.08, accuracy: 0.000_001)
                XCTAssertEqual(finalTransform.d, 1.08, accuracy: 0.000_001)
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

        func sampleTransform(at seconds: Double) throws -> CGAffineTransform {
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
                        host.rootDisplayList?.value.itemRecords.first?.affineTransform
                    )
                }
            }
        }

        let initialTransform = try sampleTransform(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.spring(duration: 20.0, bounce: 0.35)) {
            toggle()
        }

        var samples: [(time: Double, transform: CGAffineTransform)] = []
        for frame in 1...1_800 {
            let sampleTime = Double(frame) / 60.0
            let transform = try sampleTransform(at: sampleTime)
            if frame.isMultiple(of: 6) {
                samples.append((sampleTime, transform))
            }
        }

        let finalTransform = try XCTUnwrap(samples.last?.transform)
        let intermediateTransform = try XCTUnwrap(
            samples.first { sample in
                sample.transform.a > initialTransform.a &&
                    sample.transform.a < finalTransform.a
            }?.transform
        )

        XCTAssertEqual(initialTransform.a, 0.78, accuracy: 0.000_001)
        XCTAssertGreaterThan(intermediateTransform.a, initialTransform.a)
        XCTAssertLessThan(intermediateTransform.a, finalTransform.a)
        XCTAssertEqual(finalTransform.a, 1.08, accuracy: 0.001)
        XCTAssertEqual(finalTransform.d, 1.08, accuracy: 0.001)
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

        func sampleTransform(at seconds: Double) throws -> CGAffineTransform {
            let displayList = try sampleRootDisplayList(
                host: host,
                rendererHost: rendererHost,
                at: seconds
            )
            return try XCTUnwrap(displayList.itemRecords.first?.affineTransform)
        }

        let initialTransform = try sampleTransform(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, transform: CGAffineTransform)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            samples.append((sampleTime, try sampleTransform(at: sampleTime)))
        }

        let finalTransform = try sampleTransform(at: 2.0)
        let intermediateTransform = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.transform.tx > initialTransform.tx &&
                    sample.transform.tx < finalTransform.tx
            }?.transform
        )

        XCTAssertEqual(initialTransform.tx, -42, accuracy: 0.001)
        XCTAssertGreaterThan(intermediateTransform.tx, initialTransform.tx)
        XCTAssertLessThan(intermediateTransform.tx, finalTransform.tx)
        XCTAssertEqual(finalTransform.tx, 42, accuracy: 0.001)
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

        func sampleTransform(at seconds: Double) throws -> CGAffineTransform {
            let displayList = try sampleRootDisplayList(
                host: host,
                rendererHost: rendererHost,
                at: seconds
            )
            return try XCTUnwrap(displayList.itemRecords.first?.affineTransform)
        }

        let initialTransform = try sampleTransform(at: 0)
        let toggle = try XCTUnwrap(probe.toggle)

        withAnimation(.linear(duration: 1.0)) {
            toggle()
        }

        var samples: [(time: Double, transform: CGAffineTransform)] = []
        for step in 0...10 {
            let sampleTime = Double(step) / 10.0
            samples.append((sampleTime, try sampleTransform(at: sampleTime)))
        }

        let finalTransform = try sampleTransform(at: 2.0)
        let intermediateTransform = try XCTUnwrap(
            samples.dropFirst().dropLast().first { sample in
                sample.transform.b > initialTransform.b &&
                    sample.transform.b < finalTransform.b
            }?.transform
        )

        XCTAssertLessThan(initialTransform.b, 0)
        XCTAssertGreaterThan(intermediateTransform.b, initialTransform.b)
        XCTAssertLessThan(intermediateTransform.b, finalTransform.b)
        XCTAssertGreaterThan(finalTransform.b, 0)
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
                let source = graph.makeInput(value: StateShapeFillColorOnlyRoot(probe: probe))
                let outputs = StateShapeFillColorOnlyRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(
                        graph: graph,
                        time: time,
                        size: graph.makeInput(value: ViewSize(width: 200, height: 200))
                    )
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                let displayID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))

                func sampleColor(at seconds: Double) throws -> Color {
                    time.setValue(Time(seconds: seconds))
                    let layout = layoutAttr.value
                    layout.place(
                        at: .zero,
                        anchor: .topLeading,
                        proposal: ProposedViewSize(CGSize(width: 200, height: 200))
                    )
                    host.data.rootSubgraph.update()
                    let displayList = Attribute<DisplayList>(displayID).value
                    guard let color = firstShapeFillColor(in: displayList) else {
                        XCTFail("missing shape fill color at \(seconds): \(displayListSummary(displayList))")
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
                let initialTransform = try XCTUnwrap(
                    Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                )
                let toggle = try XCTUnwrap(probe.toggle)

                toggle()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                XCTAssertTrue(host.hasScheduledViewUpdate)

                var sampledTransforms: [CGAffineTransform] = []
                for frame in 1...1_800 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    sampledTransforms.append(try XCTUnwrap(
                        Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                    ))
                }

                let finalTransform = try XCTUnwrap(sampledTransforms.last)
                let intermediateTransform = try XCTUnwrap(
                    sampledTransforms.first { transform in
                        transform.a > initialTransform.a &&
                            transform.a < finalTransform.a
                    }
                )

                XCTAssertGreaterThan(intermediateTransform.a, initialTransform.a)
                XCTAssertLessThan(intermediateTransform.a, finalTransform.a)
                XCTAssertEqual(finalTransform.a, 1.08, accuracy: 0.000_001)
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
                let initialTransform = try XCTUnwrap(
                    Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                )
                let toggle = try XCTUnwrap(probe.toggle)

                toggle()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                XCTAssertTrue(host.hasScheduledViewUpdate)

                var sampledTransforms: [CGAffineTransform] = []
                for frame in 1...1_800 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    sampledTransforms.append(try XCTUnwrap(
                        Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                    ))
                }

                let finalTransform = try XCTUnwrap(sampledTransforms.last)
                let intermediateTransform = try XCTUnwrap(
                    sampledTransforms.first { transform in
                        transform.a > initialTransform.a &&
                            transform.a < finalTransform.a
                    }
                )

                XCTAssertGreaterThan(intermediateTransform.a, initialTransform.a)
                XCTAssertLessThan(intermediateTransform.a, finalTransform.a)
                XCTAssertEqual(finalTransform.a, 1.08, accuracy: 0.000_001)
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
                let initialTransform = try XCTUnwrap(
                    Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                )
                let toggle = try XCTUnwrap(probe.toggle)

                toggle()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                for frame in 1...120 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    _ = Attribute<DisplayList>(displayID).value
                }
                let outboundTransform = try XCTUnwrap(
                    Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                )
                XCTAssertGreaterThan(outboundTransform.a, initialTransform.a)
                XCTAssertLessThan(outboundTransform.a, 1.08)

                toggle()
                host.data.rootSubgraph.update()
                _ = Attribute<DisplayList>(displayID).value

                var retargetSamples: [CGAffineTransform] = []
                for frame in 121...1_920 {
                    time.setValue(Time(seconds: Double(frame) / 60.0))
                    host.data.rootSubgraph.update()
                    retargetSamples.append(try XCTUnwrap(
                        Attribute<DisplayList>(displayID).value.itemRecords.first?.affineTransform
                    ))
                }

                let finalTransform = try XCTUnwrap(retargetSamples.last)
                let intermediateTransform = try XCTUnwrap(
                    retargetSamples.first { transform in
                        transform.a < outboundTransform.a &&
                            transform.a > finalTransform.a
                    }
                )

                XCTAssertLessThan(intermediateTransform.a, outboundTransform.a)
                XCTAssertGreaterThan(intermediateTransform.a, finalTransform.a)
                XCTAssertEqual(finalTransform.a, 0.78, accuracy: 0.001)
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
                let outputs = StateShapeAnimatableRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph, time: time)
                )
                let layoutAttr = try XCTUnwrap(outputs._layoutComputer.attribute)
                let initialWidth = layoutAttr.value.sizeThatFits(.unspecified).width
                let toggle = try XCTUnwrap(probe.toggle)

                withAnimation(.linear(duration: 1.0)) {
                    toggle()
                }
                host.data.rootSubgraph.update()
                _ = layoutAttr.value.sizeThatFits(.unspecified)

                var samples: [(time: Double, width: CGFloat)] = []
                for step in 0...10 {
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
                XCTAssertGreaterThan(samples[1].width, initialWidth)
                XCTAssertLessThan(samples[1].width, finalWidth)
                XCTAssertGreaterThan(samples[5].width, samples[1].width)
                XCTAssertLessThan(samples[5].width, finalWidth)
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
            customInputs: PropertyList(),
            time: time ?? graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
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
