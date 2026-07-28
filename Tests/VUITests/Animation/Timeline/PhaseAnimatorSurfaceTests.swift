import Foundation
import XCTest
@testable import VUI

private struct PhaseSizedView: View, TestPrimitiveView {
    var width: CGFloat

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            let value = view._attribute.value
            return LayoutComputer.fixed(CGSize(width: value.width, height: 19))
        }
        layout.flags = .transactional
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct PhaseAnimatorRelaySource: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 31, height: 23))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct PhaseAnimatorTransactionWidthKey: TransactionKey {
    static let defaultValue: CGFloat = 0
}

private final class PhasePublicationRecorder {
    var phases: [Int] = []

    func record(_ phase: Int) {
        phases.append(phase)
    }

    func removeAll() {
        phases.removeAll()
    }
}

private final class PhaseTriggerActionRecorder {
    var keyframeAction: (() -> Void)?
    var phaseAction: (() -> Void)?
    var phases: [Int] = []
}

private struct StateDrivenPhaseAnimatorVisualRoot: View {
    @State private var keyframeTrigger = 0
    @State private var phaseTrigger = 0

    var recorder: PhaseTriggerActionRecorder

    var body: some View {
        recorder.keyframeAction = {
            keyframeTrigger += 1
        }
        recorder.phaseAction = {
            phaseTrigger += 1
        }
        return VStack {
            Circle()
                .fill(Color.purple)
                .frame(width: 86, height: 86)
                .phaseAnimator([0, 1, 2], trigger: phaseTrigger) { content, phase in
                    recorder.phases.append(phase)
                    return content
                        .scaleEffect(phase == 1 ? 1.35 : 0.82)
                        .offset(y: phase == 2 ? 34 : -8)
                        .opacity(phase == 2 ? 0.30 : 1.0)
                } animation: { phase in
                    switch phase {
                    case 0:
                        .easeOut(duration: 0.35)
                    case 1:
                        .spring(duration: 0.8, bounce: 0.35)
                    default:
                        .easeInOut(duration: 0.55)
                    }
                }
            }
        }
}

private struct PhaseAnimatorBodyRoot: View {
    var trigger: Int
    var recorder: PhasePublicationRecorder

    var body: some View {
        PhaseAnimator(
            [0, 1, 2],
            trigger: trigger,
            content: { phase in
                recorder.record(phase)
                return PhaseSizedView(width: CGFloat(phase))
            },
            animation: { _ in nil }
        )
    }
}

private struct PhaseAnimatorVisualBodyRoot: View {
    var trigger: Int
    var recorder: PhasePublicationRecorder

    var body: some View {
        Circle()
            .fill(Color.purple)
            .frame(width: 86, height: 86)
            .phaseAnimator([0, 1, 2], trigger: trigger) { content, phase in
                recorder.record(phase)
                return content
                    .scaleEffect(phase == 1 ? 1.35 : 0.82)
                    .offset(y: phase == 2 ? 34 : -8)
                    .opacity(phase == 2 ? 0.30 : 1.0)
            } animation: { _ in
                .linear(duration: 1.0)
            }
    }
}

private struct TransactionSizedPhaseView: View, TestPrimitiveView {
    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeView called outside an active _AGGraph context.")
        }
        let transaction = inputs.base.transaction
        let layout = graph.makeRule {
            let width = transaction.value[PhaseAnimatorTransactionWidthKey.self]
            return LayoutComputer.fixed(CGSize(width: width, height: 29))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private func firstPhaseItemBounds(in displayList: DisplayList) -> CGRect? {
    if let bounds = displayList.itemRecords.compactMap(\.bounds).first {
        return bounds
    }
    for effect in displayList.effects {
        if let bounds = firstPhaseItemBounds(in: effect.contents) {
            return bounds
        }
    }
    return nil
}

private struct PhaseAnimatorSourceVisitor: AttributeBodyVisitor {
    var source: AGAttribute?

    mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>) {
        guard let sourceValue = Mirror(reflecting: body.pointee).children.first(where: {
            $0.label == "_source"
        })?.value else {
            return
        }
        source = Mirror(reflecting: sourceValue).children.first(where: {
            $0.label == "identifier"
        })?.value as? AGAttribute
    }
}

final class PhaseAnimatorSurfaceTests: XCTestCase {
    func testStorageLabelsMatchObservedShape() {
        let view = PhaseAnimator([1, 2]) { phase in
            PhaseSizedView(width: CGFloat(phase))
        }

        let labels = Mirror(reflecting: view).children.map(\.label)
        XCTAssertEqual(labels, [
            "phases",
            "content",
            "animation",
            "behavior",
            "_currentIndex",
            "_seed",
        ])
    }

    func testInitialPhaseContentBuildsDirectPhaseAnimatorView() throws {
        try withPhaseAnimatorHost { _, graph in
            let view = PhaseAnimator([7, 11]) { phase in
                PhaseSizedView(width: CGFloat(phase))
            }
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 7, height: 19))
        }
    }

    func testEmptyPhasesBuildsEmptyOutput() throws {
        try withPhaseAnimatorHost { _, graph in
            let view = PhaseAnimator([Int]()) { phase in
                PhaseSizedView(width: CGFloat(phase))
            }
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), .zero)
        }
    }

    func testRepeatingNilAnimationPublishesImmediateVisibleCycle() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            let recorder = PhasePublicationRecorder()
            let view: PhaseAnimator<Int, PhaseSizedView> = PhaseAnimator(
                [0, 1, 2],
                content: { phase in
                    recorder.record(phase)
                    return PhaseSizedView(width: CGFloat(phase))
                },
                animation: { _ in nil }
            )
            let outputs: _ViewOutputs = AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let source = graph.makeInput(value: view)
                return type(of: view)._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
            }

            func currentSize() throws -> CGSize {
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                return layout.sizeThatFits(.unspecified)
            }

            XCTAssertEqual(try currentSize(), CGSize(width: 0, height: 19))
            recorder.removeAll()

            viewGraph.flushTransactions()
            viewGraph.updateOutputs(at: Time(seconds: 0))
            XCTAssertEqual(try currentSize(), CGSize(width: 0, height: 19))

            XCTAssertEqual(compactedPhases(recorder.phases), [1, 2, 0])
            XCTAssertEqual(try currentSize(), CGSize(width: 0, height: 19))
        }
    }

    func testEventDrivenNilAnimationPublishesImmediateTriggerCycle() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            typealias Animator = PhaseAnimator<Int, PhaseSizedView>
            let recorder = PhasePublicationRecorder()
            func makeAnimator(trigger: Int) -> Animator {
                Animator(
                    [0, 1, 2],
                    trigger: trigger,
                    content: { phase in
                        recorder.record(phase)
                        return PhaseSizedView(width: CGFloat(phase))
                    },
                    animation: { _ in nil }
                )
            }

            let source: Attribute<Animator>
            let outputs: _ViewOutputs
            (source, outputs) = AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let animator = makeAnimator(trigger: 0)
                let source = graph.makeInput(value: animator)
                let outputs = type(of: animator)._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                return (source, outputs)
            }

            func currentSize() throws -> CGSize {
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                return layout.sizeThatFits(.unspecified)
            }

            XCTAssertEqual(try currentSize(), CGSize(width: 0, height: 19))
            viewGraph.updateOutputs(at: Time(seconds: 0))
            recorder.removeAll()

            viewGraph.asyncTransaction(
                Transaction(),
                id: Transaction.id,
                mutation: CustomGraphMutation {
                    source.setValue(makeAnimator(trigger: 1))
                },
                style: .deferred,
                mayDeferUpdate: false
            )
            viewGraph.flushTransactions()
            XCTAssertEqual(compactedPhases(recorder.phases), [1, 2, 0])
            XCTAssertEqual(try currentSize(), CGSize(width: 0, height: 19))
        }
    }

    func testEventDrivenTriggerPropagatesThroughDefaultBodyRule() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            let recorder = PhasePublicationRecorder()
            func root(trigger: Int) -> PhaseAnimatorBodyRoot {
                PhaseAnimatorBodyRoot(trigger: trigger, recorder: recorder)
            }

            let source: Attribute<PhaseAnimatorBodyRoot>
            let outputs: _ViewOutputs
            (source, outputs) = AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let source = graph.makeInput(value: root(trigger: 0))
                let outputs = PhaseAnimatorBodyRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
                return (source, outputs)
            }

            func currentSize() throws -> CGSize {
                let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
                return layout.sizeThatFits(.unspecified)
            }

            XCTAssertEqual(try currentSize(), CGSize(width: 0, height: 19))
            viewGraph.updateOutputs(at: Time(seconds: 0))
            recorder.removeAll()

            source.setValue(root(trigger: 1))
            XCTAssertEqual(try currentSize(), CGSize(width: 1, height: 19))
            XCTAssertEqual(compactedPhases(recorder.phases), [1])

            viewGraph.flushTransactions()
            _ = try currentSize()

            XCTAssertEqual(compactedPhases(recorder.phases), [1, 2, 0])
            XCTAssertEqual(try currentSize(), CGSize(width: 0, height: 19))
        }
    }

    func testEventDrivenVisualModifiersAnimateThroughDefaultBodyRule() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            let recorder = PhasePublicationRecorder()
            let time = graph.makeInput(value: Time(seconds: 0))
            func root(trigger: Int) -> PhaseAnimatorVisualBodyRoot {
                PhaseAnimatorVisualBodyRoot(
                    trigger: trigger,
                    recorder: recorder
                )
            }

            var inputs = makeViewInputs(
                graph: graph,
                time: time,
                size: graph.makeInput(value: ViewSize(width: 86, height: 86))
            )
            inputs.preferences.keys.add(DisplayList.Key.self)
            let source: Attribute<PhaseAnimatorVisualBodyRoot>
            let outputs: _ViewOutputs
            (source, outputs) = AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let source = graph.makeInput(value: root(trigger: 0))
                let outputs = PhaseAnimatorVisualBodyRoot._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: inputs
                )
                return (source, outputs)
            }
            let displayID = try XCTUnwrap(
                outputs.preferences.value(for: DisplayList.Key.self)
            )
            let displayList = Attribute<DisplayList>(displayID)

            _ = displayList.value
            viewGraph.updateOutputs(at: Time(seconds: 0))
            recorder.removeAll()

            source.setValue(root(trigger: 1))
            viewGraph.data.rootSubgraph.update()
            let triggered = displayList.value

            XCTAssertEqual(compactedPhases(recorder.phases), [1])
            XCTAssertFalse(viewGraph.nextUpdate.views.time.seconds.isInfinite)

            time.setValue(Time(seconds: 0.5))
            viewGraph.data.rootSubgraph.update()
            _ = displayList.value

            time.setValue(Time(seconds: 0.6))
            viewGraph.data.rootSubgraph.update()
            let midpoint = displayList.value

            XCTAssertNotEqual(
                triggered.interpolationBounds,
                midpoint.interpolationBounds
            )
            XCTAssertEqual(compactedPhases(recorder.phases), [1])
        }
    }

    func testSecondStateActionTriggersVisualPhaseAnimator() throws {
        let rendererHost = TestViewRendererHost()
        let recorder = PhaseTriggerActionRecorder()
        let content = StateDrivenPhaseAnimatorVisualRoot(recorder: recorder)
        let viewGraph = ViewGraph(
            rootViewType: type(of: content),
            content: content,
            rendererHost: rendererHost
        )
        rendererHost.storage = viewGraph

        func sample(at seconds: Double) throws -> DisplayList {
            let time = Time(seconds: seconds)
            rendererHost.currentTimestamp = time
            viewGraph.updateOutputs(at: time)
            return try viewGraph.data.withCurrent {
                try AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                    let layout = try XCTUnwrap(viewGraph.rootLayoutComputer).value
                    let proposalSize = CGSize(width: 240, height: 220)
                    layout.place(
                        at: CGPoint(x: proposalSize.width / 2, y: proposalSize.height / 2),
                        anchor: .center,
                        proposal: ProposedViewSize(proposalSize)
                    )
                    viewGraph.data.rootSubgraph.update()
                    return try XCTUnwrap(viewGraph.rootDisplayList?.value)
                }
            }
        }

        let initial = try sample(at: 0)
        recorder.phases.removeAll()
        try XCTUnwrap(recorder.phaseAction)()

        var samples: [(Double, CGRect?)] = []
        for step in 0...40 {
            let seconds = Double(step) / 20.0
            samples.append((seconds, firstPhaseItemBounds(in: try sample(at: seconds))))
        }
        print("PHASE_BOUNDS", firstPhaseItemBounds(in: initial) as Any, samples)
        XCTAssertEqual(compactedPhases(recorder.phases).first, 1)
    }

    @MainActor
    func testSecondStateActionTriggersVisualPhaseAnimatorInOverlayPresentation() throws {
        let recorder = PhaseTriggerActionRecorder()
        let content = StateDrivenPhaseAnimatorVisualRoot(recorder: recorder)
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(EmptyView.self)
            )
        )
        let child = parent.viewGraph.data.withCurrent {
            let sourceGraph = parent.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(
                value: AnyView(SheetContent(content: AnyView(content)))
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(StateDrivenPhaseAnimatorVisualRoot.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
        }
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Display-list animation sampling should not request graphics resources.")
        }

        func dumpScaleNodes(_ stage: String) {
            child.viewGraph.data.withCurrent {
                let graph = child.viewGraph.data.graph
                for (rawID, info) in graph.attributeInfos.sorted(by: { $0.key < $1.key }) {
                    guard let body = info.body,
                          String(describing: body.bodyType).contains("AnimatableAttribute<_ScaleEffect>") else {
                        continue
                    }
                    let node = graph.slots[Int(rawID)].node
                    var visitor = PhaseAnimatorSourceVisitor()
                    graph.visitBody(
                        AGAttribute(rawValue: rawID),
                        visitor: &visitor
                    )
                    let sourceID = visitor.source?.rawValue
                    let sourceNode = sourceID.flatMap { graph.slots[Int($0)].node }
                    var subgraph = graph.nodeSubgraphs[rawID]?.value
                    var ancestry: [String] = []
                    while let current = subgraph {
                        ancestry.append(String(describing: ObjectIdentifier(current)))
                        subgraph = current.parent
                    }
                    print(
                        "PRESENTED_SCALE_NODE",
                        stage,
                        rawID,
                        node?.flags.rawValue as Any,
                        node?.needsEvaluation as Any,
                        node?.valueVersion as Any,
                        node?.transaction?.effectiveAnimation as Any,
                        "source=\(sourceID as Any)",
                        "sourceValue=\(sourceNode?.value?.anyValue as Any)",
                        "sourceDirty=\(sourceNode?.needsEvaluation as Any)",
                        "sourceVersion=\(sourceNode?.valueVersion as Any)",
                        "sourceInputs=\(sourceNode?.inputs as Any)",
                        ancestry,
                        "root=\(ObjectIdentifier(child.viewGraph.data.rootSubgraph))"
                    )
                }
            }
        }

        func update(at seconds: Double, tick: UInt64) throws -> (DisplayList, Bool) {
            var redraw = false
            child.updateView(
                tick: tick,
                delta: seconds - child.animationTimestamp.seconds,
                date: child.date.addingTimeInterval(seconds),
                contentSize: CGSize(width: 680, height: 430),
                redraw: &redraw,
                withGC
            )
            let displayList = try child.viewGraph.data.withCurrent {
                try XCTUnwrap(child.viewGraph.rootDisplayList?.value)
            }
            return (displayList, redraw)
        }

        let initial = try update(at: 0, tick: 0)
        for settleTick in 1...4 {
            guard child.viewGraph.hasPendingTransactions ||
                    child.viewGraph.data.graph.inbox.hasPendingWork else {
                break
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            _ = try update(at: 0, tick: UInt64(settleTick))
        }
        print(
            "PRESENTED_PENDING initial",
            child.viewGraph.hasPendingTransactions,
            child.viewGraph.needsTransaction,
            child.viewGraph.data.graph.inbox.hasPendingWork,
            child.viewGraph.hasScheduledViewUpdate,
            Update.queuedActionReasons
        )
        dumpScaleNodes("initial")
        recorder.phases.removeAll()
        try XCTUnwrap(recorder.phaseAction)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        print(
            "PRESENTED_PENDING action",
            child.viewGraph.hasPendingTransactions,
            child.viewGraph.needsTransaction,
            child.viewGraph.data.graph.inbox.hasPendingWork,
            child.viewGraph.hasScheduledViewUpdate,
            Update.queuedActionReasons
        )
        dumpScaleNodes("action")

        var samples: [(Double, CGRect?, Bool)] = []
        for step in 0...40 {
            let seconds = Double(step) / 20.0
            let sample = try update(at: seconds, tick: UInt64(step + 1))
            if step < 3 {
                print(
                    "PRESENTED_PENDING sample-\(step)",
                    child.viewGraph.hasPendingTransactions,
                    child.viewGraph.needsTransaction,
                    child.viewGraph.data.graph.inbox.hasPendingWork,
                    child.viewGraph.hasScheduledViewUpdate,
                    Update.queuedActionReasons
                )
                dumpScaleNodes("sample-\(step)")
            }
            samples.append((seconds, firstPhaseItemBounds(in: sample.0), sample.1))
        }
        print(
            "PRESENTED_PHASE_BOUNDS",
            firstPhaseItemBounds(in: initial.0) as Any,
            samples,
            compactedPhases(recorder.phases)
        )
        XCTAssertEqual(compactedPhases(recorder.phases).first, 1)
    }

    @MainActor
    func testSingleRetriggerDuringFadedTransitionReturnsToCompactInOverlayPresentation() throws {
        let recorder = PhaseTriggerActionRecorder()
        let content = StateDrivenPhaseAnimatorVisualRoot(recorder: recorder)
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(EmptyView.self)
            )
        )
        let child = parent.viewGraph.data.withCurrent {
            let sourceGraph = parent.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(
                value: AnyView(SheetContent(content: AnyView(content)))
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(StateDrivenPhaseAnimatorVisualRoot.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
        }
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Display-list animation sampling should not request graphics resources.")
        }

        func update(at seconds: Double, tick: UInt64) throws -> DisplayList {
            var redraw = false
            child.updateView(
                tick: tick,
                delta: seconds - child.animationTimestamp.seconds,
                date: child.date.addingTimeInterval(seconds),
                contentSize: CGSize(width: 680, height: 430),
                redraw: &redraw,
                withGC
            )
            return try child.viewGraph.data.withCurrent {
                try XCTUnwrap(child.viewGraph.rootDisplayList?.value)
            }
        }

        let initial = try update(at: 0, tick: 0)
        for settleTick in 1...4 {
            guard child.viewGraph.hasPendingTransactions ||
                    child.viewGraph.data.graph.inbox.hasPendingWork else {
                break
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            _ = try update(at: 0, tick: UInt64(settleTick))
        }

        recorder.phases.removeAll()
        try XCTUnwrap(recorder.phaseAction)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var tick = UInt64(10)
        for step in 0...22 {
            _ = try update(at: Double(step) * 0.05, tick: tick)
            tick += 1
        }
        XCTAssertEqual(compactedPhases(recorder.phases), [1, 2])

        try XCTUnwrap(recorder.phaseAction)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var settled = try update(at: 1.15, tick: tick)
        tick += 1
        for step in 24...70 {
            settled = try update(at: Double(step) * 0.05, tick: tick)
            tick += 1
        }

        XCTAssertEqual(
            compactedPhases(recorder.phases),
            [1, 2, 1, 2, 0],
            "One retrigger during faded motion must finish the restarted cycle."
        )
        XCTAssertEqual(
            firstPhaseItemBounds(in: settled),
            firstPhaseItemBounds(in: initial)
        )
    }

    @MainActor
    func testRapidDoubleRetriggerDuringFadedTransitionStopsAtFadedInOverlayPresentation() throws {
        let recorder = PhaseTriggerActionRecorder()
        let content = StateDrivenPhaseAnimatorVisualRoot(recorder: recorder)
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(EmptyView.self)
            )
        )
        let child = parent.viewGraph.data.withCurrent {
            let sourceGraph = parent.viewGraph.data.graph
            let contentAttr: Attribute<AnyView> = sourceGraph.makeInput(
                value: AnyView(SheetContent(content: AnyView(content)))
            )
            return ModalWindowController(
                crossGraphContent: contentAttr,
                sourceGraph: sourceGraph,
                scene: WindowKey(
                    namespace: .app,
                    sceneID: SceneID(StateDrivenPhaseAnimatorVisualRoot.self)
                ),
                parentController: parent,
                usesPlatformWindow: false
            )
        }
        let withGC: WindowContext.WithGraphicsContext = { _, _ in
            XCTFail("Display-list animation sampling should not request graphics resources.")
        }

        func update(at seconds: Double, tick: UInt64) throws -> DisplayList {
            var redraw = false
            child.updateView(
                tick: tick,
                delta: seconds - child.animationTimestamp.seconds,
                date: child.date.addingTimeInterval(seconds),
                contentSize: CGSize(width: 680, height: 430),
                redraw: &redraw,
                withGC
            )
            return try child.viewGraph.data.withCurrent {
                try XCTUnwrap(child.viewGraph.rootDisplayList?.value)
            }
        }

        let initial = try update(at: 0, tick: 0)
        for settleTick in 1...4 {
            guard child.viewGraph.hasPendingTransactions ||
                    child.viewGraph.data.graph.inbox.hasPendingWork else {
                break
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            _ = try update(at: 0, tick: UInt64(settleTick))
        }

        recorder.phases.removeAll()
        try XCTUnwrap(recorder.phaseAction)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var tick = UInt64(10)
        for step in 0...22 {
            _ = try update(at: Double(step) * 0.05, tick: tick)
            tick += 1
        }
        XCTAssertEqual(compactedPhases(recorder.phases), [1, 2])

        try XCTUnwrap(recorder.phaseAction)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        _ = try update(at: 1.15, tick: tick)
        tick += 1

        try XCTUnwrap(recorder.phaseAction)()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        var stopped = try update(at: 1.20, tick: tick)
        tick += 1
        for step in 25...70 {
            stopped = try update(at: Double(step) * 0.05, tick: tick)
            tick += 1
        }

        XCTAssertEqual(
            compactedPhases(recorder.phases),
            [1, 2, 1, 2],
            "Two rapid retriggers at the faded boundary preserve the observed faded stop."
        )
        let initialBounds = try XCTUnwrap(firstPhaseItemBounds(in: initial))
        let stoppedBounds = try XCTUnwrap(firstPhaseItemBounds(in: stopped))
        XCTAssertEqual(stoppedBounds.size, initialBounds.size)
        XCTAssertEqual(stoppedBounds.midY - initialBounds.midY, 42, accuracy: 0.001)
    }

    func testChildValueStorageLabelsMatchObservedProjectionShape() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer

        let value = Container.Child.Value(
            content: PhaseSizedView(width: 1),
            phaseChangeTransaction: Transaction(),
            phaseChangeTransactionSeed: 3
        )

        let labels = Mirror(reflecting: value).children.map(\.label)
        XCTAssertEqual(labels, [
            "content",
            "phaseChangeTransaction",
            "phaseChangeTransactionSeed",
        ])
    }

    func testAnimationCompletionStorageLabelsMatchObservedShape() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer

        let completion = Container.AnimationCompletion(seed: 2, didAnimate: true)

        let labels = Mirror(reflecting: completion).children.map(\.label)
        XCTAssertEqual(labels, [
            "seed",
            "didAnimate",
        ])
    }

    func testCompletionListenerStorageLabelsMatchObservedShape() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer

        let listener = Container.CompletionListener { _ in }

        let labels = Mirror(reflecting: listener).children.map(\.label)
        XCTAssertEqual(labels, [
            "action",
            "count",
            "didAnimate",
            "didFireAction",
        ])
    }

    func testCompletionListenerFallbackSkipsAfterAnimationWasAdded() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
        var completions: [Bool] = []
        let listener = Container.CompletionListener { didAnimate in
            completions.append(didAnimate)
        }

        listener.animationWasAdded()
        listener.fireNoAnimationFallback()

        XCTAssertEqual(completions, [])

        let actions = listener.animationWasRemoved()

        XCTAssertEqual(completions, [true])
        XCTAssertEqual(actions.count, 0)
        XCTAssertEqual(listener.animationWasRemoved().count, 0)
    }

    func testCompletionListenerFallbackDoesNotUseDidFireGate() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
        var completions: [Bool] = []
        let listener = Container.CompletionListener { didAnimate in
            completions.append(didAnimate)
        }

        listener.fireNoAnimationFallback()
        listener.fireNoAnimationFallback()

        XCTAssertEqual(completions, [false, false])
        XCTAssertEqual(listener.animationWasRemoved().count, 0)
    }

    func testCompletionListenerRemovalBeforeAddDecrementsActiveCount() {
        typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
        var completions: [Bool] = []
        let listener = Container.CompletionListener { didAnimate in
            completions.append(didAnimate)
        }

        XCTAssertEqual(listener.animationWasRemoved().count, 0)

        let count = Mirror(reflecting: listener).children
            .first { $0.label == "count" }?.value as? Int
        XCTAssertEqual(count, -1)
        XCTAssertEqual(completions, [])
    }

    func testChildStorageLabelsMatchObservedShape() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            let labels = Mirror(reflecting: child).children.map(\.label)
            XCTAssertEqual(labels, [
                "_view",
                "_transaction",
                "_transactionSeed",
                "_phase",
                "_animationCompletion",
                "_isVisible",
                "currentIndex",
                "completionSeed",
                "resetSeed",
                "endlessLoopState",
                "lastBehavior",
                "phaseChangeTransaction",
                "phaseChangeTransactionSeed",
            ])
            let storageTypes = Dictionary(uniqueKeysWithValues: Mirror(reflecting: child).children.compactMap {
                child -> (String, String)? in
                guard let label = child.label else { return nil }
                return (label, Self.typeDescription(of: child.value))
            })
            XCTAssertTrue(
                storageTypes["_animationCompletion"]?.contains("WeakAttribute<Swift.Optional<") == true,
                "\(storageTypes)"
            )
            XCTAssertTrue(
                storageTypes["_isVisible"]?.contains("WeakAttribute<Swift.Bool>") == true,
                "\(storageTypes)"
            )
        }
    }

    func testInitialTransactionPassesThroughChildTransactionRule() throws {
        try withPhaseAnimatorHost { _, graph in
            let view = PhaseAnimator([0]) { _ in
                TransactionSizedPhaseView()
            }
            var transaction = Transaction()
            transaction[PhaseAnimatorTransactionWidthKey.self] = 43

            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph, transaction: transaction)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 43, height: 29))
        }
    }

    func testChildValueTransactionRuleIntegrationSelectsPhaseChangeTransactionWhenSeedMatches() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 64
            let transaction = graph.makeInput(value: baseTransaction)
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 31
            let childAttr: Attribute<Container.Child.Value> = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )
            let phaseChangeTransaction = graph.makeRule {
                childAttr.value.phaseChangeTransaction
            }
            let phaseChangeTransactionSeed = graph.makeRule {
                childAttr.value.phaseChangeTransactionSeed
            }
            let selectedTransaction = graph.makeStatefulRule(
                Container.TransactionRule(
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phaseChangeTransaction: phaseChangeTransaction,
                    phaseChangeTransactionSeed: phaseChangeTransactionSeed
                )
            )

            Update.begin()
            let selected = selectedTransaction.value

            XCTAssertEqual(childAttr.value.content.width, 1)
            XCTAssertEqual(phaseChangeTransactionSeed.value, 31)
            XCTAssertEqual(selected[PhaseAnimatorTransactionWidthKey.self], 64)
            XCTAssertNotNil(selected.animation)
            XCTAssertEqual(Update.queuedActionReasons, [nil])

            Update.end()
        }
    }

    func testChildAdvanceFromWrapsWithinPhaseBounds() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            viewGraph.data.transactionSeed = 5
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            child.advance(from: 2)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 1)
            XCTAssertEqual(child.phaseChangeTransactionSeed, 5)
        }
    }

    func testChildAdvanceFromMovesToNextPhaseBeforeWrap() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            viewGraph.data.transactionSeed = 6
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            child.advance(from: 0)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, 1)
            XCTAssertEqual(child.phaseChangeTransactionSeed, 6)
        }
    }

    func testChildAdvanceFromRequiresAtLeastTwoPhases() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            child.advance(from: 0)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 0)
        }
    }

    func testChildAdvanceToOutOfBoundsFallsBackToAdvanceFrom() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )

            child.advance(to: 3)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 1)
        }
    }

    func testChildAdvanceToEmptyPhasesFallsBackWithoutMutation() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 2
            child.completionSeed = 7
            child.endlessLoopState = .animating

            child.advance(to: 0)

            XCTAssertEqual(child.currentIndex, 2)
            XCTAssertEqual(child.completionSeed, 7)
            XCTAssertEqual(child.endlessLoopState, .animating)
            XCTAssertNil(child.phaseChangeTransactionSeed)
        }
    }

    func testChildAdvanceToMatchingMonitoringLoopTargetPausesLoopState() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 1)

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 0)
            XCTAssertEqual(child.completionSeed, 4)
            XCTAssertEqual(child.endlessLoopState, .paused)
        }
    }

    func testChildAdvanceToDifferentMonitoringLoopTargetContinuesAdvancePath() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 0
            child.completionSeed = 4
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, 5)
            XCTAssertEqual(child.endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 2))
        }
    }

    func testChildAdvanceToPausedLoopStateReturnsWithoutMutation() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.endlessLoopState = .paused

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 2)
            XCTAssertEqual(child.completionSeed, 4)
            XCTAssertEqual(child.endlessLoopState, .paused)
        }
    }

    func testChildAdvanceToAnimatedPhaseRegistersLogicalCompletionListener() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 64
            let transaction = graph.makeInput(value: baseTransaction)
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 11
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )

            Update.begin()
            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, 1)
            XCTAssertEqual(child.phaseChangeTransactionSeed, 11)
            XCTAssertEqual(child.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 64)
            XCTAssertNotNil(child.phaseChangeTransaction.animation)
            XCTAssertTrue(
                child.phaseChangeTransaction.animationLogicalListener is Container.CompletionListener
            )
            XCTAssertNil(completion.value)
            XCTAssertEqual(Update.queuedActionReasons, [nil])
            XCTAssertFalse(viewGraph.hasPendingTransactions)

            Update.end()

            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 1)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildAdvanceToNilAnimationRetainsSourceTransactionProperties() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 72
            let transaction = graph.makeInput(value: baseTransaction)
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 12
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, 1)
            XCTAssertEqual(child.phaseChangeTransactionSeed, 12)
            XCTAssertEqual(child.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 72)
            XCTAssertNil(child.phaseChangeTransaction.animation)
            XCTAssertNil(child.phaseChangeTransaction.animationLogicalListener)
            XCTAssertNil(completion.value)
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 1)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildAdvanceToWrapsCompletionSeedWithoutTrap() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 13
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.completionSeed = Int.max

            child.advance(to: 1)

            XCTAssertEqual(child.currentIndex, 1)
            XCTAssertEqual(child.completionSeed, Int.min)
            XCTAssertEqual(child.phaseChangeTransactionSeed, 13)
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, Int.min)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildAnimatedCompletionListenerPublishesAnimatedCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )

            Update.begin()
            child.advance(to: 1)
            let listener = child.phaseChangeTransaction.animationLogicalListener
                as? Container.CompletionListener
            listener?.animationWasAdded()
            Update.end()

            XCTAssertFalse(viewGraph.hasPendingTransactions)

            let actions = listener?.animationWasRemoved() ?? []
            XCTAssertEqual(actions.count, 0)
            actions.forEach { $0() }

            XCTAssertTrue(viewGraph.hasPendingTransactions)
            XCTAssertNil(completion.value)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 1)
            XCTAssertEqual(completion.value?.didAnimate, true)
        }
    }

    func testChildAnimatedCompletionCallbackQueuesEmptyAsyncTransaction() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )

            Update.begin()
            child.advance(to: 1)
            let listener = try XCTUnwrap(
                child.phaseChangeTransaction.animationLogicalListener
                    as? Container.CompletionListener
            )
            listener.animationWasAdded()
            Update.end()

            var ambient = Transaction()
            ambient[PhaseAnimatorTransactionWidthKey.self] = 128
            var mergedMutationDidRun = false
            withTransaction(ambient) {
                XCTAssertEqual(listener.animationWasRemoved().count, 0)
                viewGraph.asyncTransaction(
                    Transaction(),
                    id: Transaction.id,
                    mutation: CustomGraphMutation {
                        mergedMutationDidRun = true
                    }
                )
            }

            XCTAssertTrue(viewGraph.hasPendingTransactions)
            XCTAssertEqual(viewGraph.data.transactionSeed, 0)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 1)
            XCTAssertEqual(completion.value?.didAnimate, true)
            XCTAssertTrue(mergedMutationDidRun)
            XCTAssertEqual(viewGraph.data.transactionSeed, 1)
        }
    }

    func testChildClampedIndexForMonitoringStateReturnsClampedCurrentIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            let container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 2
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)

            XCTAssertEqual(child.clampedIndex, 2)
        }
    }

    func testChildUpdateClampsOutOfRangeAnimatingIndexToLastPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 99
            child.lastBehavior = container.behavior

            let childValue = graph.makeStatefulRule(child)

            XCTAssertEqual(childValue.value.content.width, 2)
            var storedIndex: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                storedIndex = child.currentIndex
            }
            XCTAssertEqual(storedIndex, 99)
        }
    }

    func testChildClampedIndexForEmptyAnimatingPhasesReturnsLastIndexExpression() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 0
            child.endlessLoopState = .animating

            XCTAssertEqual(child.clampedIndex, -1)
        }
    }

    func testChildClampedIndexForEmptyPausedPhasesReturnsZero() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var child = makeChild(
                in: graph,
                viewGraph: viewGraph,
                container: container
            )
            child.currentIndex = 3
            child.endlessLoopState = .paused

            XCTAssertEqual(child.clampedIndex, 0)
        }
    }

    func testChildUpdateDoesNotTreatAbsentCompletionAsFalseCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            let childValue = graph.makeStatefulRule(
                child
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdateWithAbsentCompletionPublishesCurrentPhaseOnly() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 3
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let absentCompletionValue = childValue.value

            XCTAssertEqual(absentCompletionValue.content.width, 1)
            XCTAssertNil(absentCompletionValue.phaseChangeTransactionSeed)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdatePublishesStoredPhaseTransactionBeforePhaseChangeTransactionExists() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 377
            var storedPhaseTransaction = Transaction()
            storedPhaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 911
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: baseTransaction)
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            child.phaseChangeTransaction = storedPhaseTransaction

            let childValue = graph.makeStatefulRule(child)

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertEqual(childValue.value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 911)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdateKeepsStoredPhaseTransactionAndSeedBeforePublish() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 377
            var storedPhaseTransaction = Transaction()
            storedPhaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 911
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: baseTransaction)
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            child.phaseChangeTransaction = storedPhaseTransaction
            child.phaseChangeTransactionSeed = 123

            let childValue = graph.makeStatefulRule(child)

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertEqual(childValue.value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 911)
            XCTAssertEqual(childValue.value.phaseChangeTransactionSeed, 123)
        }
    }

    func testChildUpdateSinglePhaseRepeatingDoesNotCreateCompletionTransaction() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.1) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            let childValue = graph.makeStatefulRule(
                child
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
            XCTAssertNil(completion.value)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateRepeatingVisibleUpdateRunsBeforeNonAnimatedCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 23
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(
                child
            )

            let started = childValue.value

            XCTAssertEqual(started.content.width, 1)
            XCTAssertEqual(started.phaseChangeTransactionSeed, 23)
            XCTAssertNil(started.phaseChangeTransaction.animation)

            completion.setValue(.some(Container.AnimationCompletion(seed: 1, didAnimate: false)))
            let advanced = childValue.value

            XCTAssertEqual(advanced.content.width, 2)
            XCTAssertEqual(advanced.phaseChangeTransactionSeed, 23)
            XCTAssertNil(advanced.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 2)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateSkipsNonAnimatedEventDrivenCompletionAtZeroIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: false)))
            let unchanged = childValue.value

            XCTAssertEqual(unchanged.content.width, 0)
            XCTAssertNil(unchanged.phaseChangeTransactionSeed)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateNonAnimatedEventDrivenCompletionAtNonzeroIndexAdvancesLoop() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: false)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 29
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 5
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let loopValue = childValue.value

            XCTAssertEqual(loopValue.content.width, 2)
            XCTAssertEqual(loopValue.phaseChangeTransactionSeed, 29)
            XCTAssertTrue(viewGraph.hasPendingTransactions)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateNonAnimatedCompletionWithExistingMonitoringPayloadStillAdvances() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: behavior
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: false)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 67
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 5
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 0)
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 67)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 0))

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateIgnoresCompletionWithMismatchedSeed() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 1, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 2
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let staleCompletionValue = childValue.value

            XCTAssertEqual(staleCompletionValue.content.width, 1)
            XCTAssertNil(staleCompletionValue.phaseChangeTransactionSeed)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateRepeatingVisibleUpdateRunsBeforeAnimatedCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 17
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(
                child
            )

            let started = childValue.value

            XCTAssertEqual(started.content.width, 1)
            XCTAssertEqual(started.phaseChangeTransactionSeed, 17)
            XCTAssertNotNil(started.phaseChangeTransaction.animation)

            completion.setValue(.some(Container.AnimationCompletion(seed: 1, didAnimate: true)))
            let advanced = childValue.value

            XCTAssertEqual(advanced.content.width, 2)
            XCTAssertEqual(advanced.phaseChangeTransactionSeed, 17)
            XCTAssertNotNil(advanced.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateSkipsAnimatedEventDrivenCompletionAtZeroIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 19
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: true)))
            let unchanged = childValue.value

            XCTAssertEqual(unchanged.content.width, 0)
            XCTAssertNil(unchanged.phaseChangeTransactionSeed)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateStartsVisibleRepeatingSequence() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 31
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            let initialVisibleValue = childValue.value

            XCTAssertEqual(initialVisibleValue.content.width, 1)
            XCTAssertEqual(initialVisibleValue.phaseChangeTransactionSeed, 31)
            XCTAssertNotNil(initialVisibleValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateStartsEventDrivenSequenceWhenTriggerChanges() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in
                        animationRequests += 1
                        return .linear(duration: 0.25)
                    },
                    behavior: .eventDriven(trigger: AnyEquatable(1))
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 37
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in
                        animationRequests += 1
                        return .linear(duration: 0.25)
                    },
                    behavior: .eventDriven(trigger: AnyEquatable(2))
                )
            )
            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 1)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 37)
            XCTAssertNotNil(triggeredValue.phaseChangeTransaction.animation)
            XCTAssertEqual(animationRequests, 1)
        }
    }

    func testChildUpdateBurstEventDrivenTriggersFollowObservedRestartSequence() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            func container(trigger: Int) -> Container {
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in
                        animationRequests += 1
                        return .linear(duration: 0.25)
                    },
                    behavior: .eventDriven(trigger: AnyEquatable(trigger))
                )
            }
            let source = graph.makeInput(value: container(trigger: 1))
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 39
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)
            XCTAssertNil(childValue.value.phaseChangeTransactionSeed)
            XCTAssertEqual(animationRequests, 0)

            source.setValue(container(trigger: 2))
            let firstTrigger = childValue.value

            XCTAssertEqual(firstTrigger.content.width, 1)
            completion.setValue(.some(Container.AnimationCompletion(seed: 1, didAnimate: true)))
            let firstCompletion = childValue.value

            XCTAssertEqual(firstCompletion.content.width, 2)

            source.setValue(container(trigger: 4))
            let burstRestart = childValue.value

            XCTAssertEqual(burstRestart.content.width, 1)
            completion.setValue(.some(Container.AnimationCompletion(seed: 3, didAnimate: true)))
            let secondCompletion = childValue.value

            XCTAssertEqual(secondCompletion.content.width, 2)
            completion.setValue(.some(Container.AnimationCompletion(seed: 4, didAnimate: true)))
            let finalCompletion = childValue.value

            XCTAssertEqual(finalCompletion.content.width, 0)
            XCTAssertEqual(animationRequests, 5)
        }
    }

    func testChildUpdateSwitchingFromRepeatingToEventDrivenAdvancesToFirstPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: .eventDriven(trigger: AnyEquatable(1))
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 47
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.lastBehavior = .repeating
            let childValue = graph.makeStatefulRule(child)

            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 0)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 47)
            XCTAssertNil(triggeredValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateViewChangeFromRepeatingToEventDrivenResetsBeforeMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(2))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 71
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = repeating
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.none)
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = repeating
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 71)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, eventDriven)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeFromEventDrivenToRepeatingRestartsBeforeMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 79
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = eventDriven
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(nil)
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = eventDriven
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 79)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, repeating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeFromEventDrivenToRepeatingConsumesCompletionAfterMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 83
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = eventDriven
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.some(Container.AnimationCompletion(seed: 6, didAnimate: true)))
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = eventDriven
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 83)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 7)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, repeating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 7)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeFromEventDrivenToRepeatingConsumesFalseCompletionAfterMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 87
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = eventDriven
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.some(Container.AnimationCompletion(seed: 6, didAnimate: false)))
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = eventDriven
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 87)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 7)
            XCTAssertEqual(endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 0))
            XCTAssertEqual(lastBehavior, repeating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 7)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeFromEventDrivenToRepeatingSkipsStaleCompletionAfterMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 89
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = eventDriven
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.some(Container.AnimationCompletion(seed: 5, didAnimate: false)))
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = eventDriven
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 89)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, repeating)
            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeFromEventDrivenToRepeatingMakesPostRestartCompletionStaleAfterMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 89
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = eventDriven
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.some(Container.AnimationCompletion(seed: 5, didAnimate: true)))
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = eventDriven
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 89)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, repeating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeFromEventDrivenToRepeatingAbsentCompletionPublishesAfterMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 91
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = eventDriven
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.none)
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = eventDriven
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 91)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertNil(completion.value)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, repeating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeFromEventDrivenToRepeatingInvalidCompletionPublishesAfterMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let eventDriven = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let repeating = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: eventDriven
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let weakCompletion = completion.asWeak()
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 93
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = eventDriven
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = eventDriven
            }
            graph.removeNode(completion.identifier)

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: repeating
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 93)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, repeating)

            viewGraph.flushTransactions()

            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateSwitchingFromEventDrivenToRepeatingRunsVisibleStartThenMismatchAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: .repeating
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 53
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 0)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 53)
            XCTAssertNil(triggeredValue.phaseChangeTransaction.animation)
            var currentIndex: Int?
            var completionSeed: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 2)
        }
    }

    func testChildUpdateEventDrivenTriggerChangeRestartsFromZeroSource() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: .eventDriven(trigger: AnyEquatable(2))
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 59
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 1)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 59)
            XCTAssertNil(triggeredValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateAnimatedEventDrivenCompletionWrapsToZero() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 7, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 41
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 7
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let wrappedValue = childValue.value

            XCTAssertEqual(wrappedValue.content.width, 0)
            XCTAssertEqual(wrappedValue.phaseChangeTransactionSeed, 41)
            XCTAssertNotNil(wrappedValue.phaseChangeTransaction.animation)
            XCTAssertEqual(animationRequests, 1)
        }
    }

    func testChildUpdateEventDrivenTriggerChangeStartsAfterCompletedCycle() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let oldBehavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in .linear(duration: 0.25) },
                    behavior: oldBehavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 43
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 0
            child.completionSeed = 5
            child.lastBehavior = oldBehavior
            let childValue = graph.makeStatefulRule(child)

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in .linear(duration: 0.25) },
                    behavior: .eventDriven(trigger: AnyEquatable(2))
                )
            )
            let triggeredValue = childValue.value

            XCTAssertEqual(triggeredValue.content.width, 1)
            XCTAssertEqual(triggeredValue.phaseChangeTransactionSeed, 43)
            XCTAssertNotNil(triggeredValue.phaseChangeTransaction.animation)
        }
    }

    func testChildUpdateViewChangeResetsPausedRepeatingLoopAndRestarts() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .animating)
        }
    }

    func testChildUpdateViewChangeRepeatingRestartMakesOldCompletionStale() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            completion.setValue(.some(Container.AnimationCompletion(seed: 4, didAnimate: true)))
            viewGraph.data.transactionSeed = 53

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 53)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .animating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeRepeatingRestartConsumesMatchingCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            completion.setValue(.some(Container.AnimationCompletion(seed: 5, didAnimate: true)))
            viewGraph.data.transactionSeed = 57

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 57)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeRepeatingRestartConsumesMatchingFalseCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            completion.setValue(.some(Container.AnimationCompletion(seed: 5, didAnimate: false)))
            viewGraph.data.transactionSeed = 59

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 59)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 2))

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeRepeatingRestartAbsentCompletionPublishesAfterRestart() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            completion.setValue(nil)
            viewGraph.data.transactionSeed = 67

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 67)
            XCTAssertNil(completion.value)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .animating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeRepeatingRestartInvalidCompletionPublishesAfterRestart() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            graph.removeNode(completion.identifier)
            viewGraph.data.transactionSeed = 61

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 61)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)

            viewGraph.flushTransactions()

            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateViewChangeResetsPausedEventDrivenLoopWithoutRestart() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 4)
            XCTAssertEqual(endlessLoopState, .animating)
        }
    }

    func testChildUpdateViewChangeEventDrivenClearsPausedLoopBeforeMatchingCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            completion.setValue(.some(Container.AnimationCompletion(seed: 4, didAnimate: true)))
            viewGraph.data.transactionSeed = 59

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 59)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .animating)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeEventDrivenZeroIndexCompletionPublishesAfterReset() {
        func assertZeroIndexCompletionPublishes(didAnimate: Bool) {
            withPhaseAnimatorHost { viewGraph, graph in
                typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
                let behavior = PhaseAnimator<Int, PhaseSizedView>
                    .Behavior
                    .eventDriven(trigger: AnyEquatable(1))
                let source = graph.makeInput(
                    value: Container(
                        phases: [0, 1, 2],
                        content: { PhaseSizedView(width: CGFloat($0)) },
                        animation: { _ in nil },
                        behavior: behavior
                    )
                )
                let transaction = graph.makeInput(value: Transaction())
                let phase = graph.makeInput(value: Phase())
                let completion = graph.makeInput(
                    value: Optional<Container.AnimationCompletion>.some(
                        Container.AnimationCompletion(seed: 4, didAnimate: didAnimate)
                    )
                )
                let isVisible = graph.makeInput(value: true)
                var child = Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
                child.currentIndex = 0
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
                let childValue = graph.makeStatefulRule(child)
                _ = childValue.value
                viewGraph.flushTransactions()
                graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                    child.currentIndex = 0
                    child.completionSeed = 4
                    child.endlessLoopState = .paused
                    child.lastBehavior = behavior
                }
                completion.setValue(
                    .some(Container.AnimationCompletion(seed: 4, didAnimate: didAnimate))
                )

                source.setValue(
                    Container(
                        phases: [0, 1, 2],
                        content: { PhaseSizedView(width: CGFloat($0)) },
                        animation: { _ in nil },
                        behavior: behavior
                    )
                )
                let value = childValue.value

                XCTAssertEqual(value.content.width, 0)
                XCTAssertNil(value.phaseChangeTransactionSeed)
                XCTAssertNil(value.phaseChangeTransaction.animation)
                XCTAssertFalse(viewGraph.hasPendingTransactions)
                XCTAssertEqual(completion.value?.seed, 4)
                XCTAssertEqual(completion.value?.didAnimate, didAnimate)
                var currentIndex: Int?
                var completionSeed: Int?
                var endlessLoopState: Container.Child.EndlessLoopState?
                var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
                graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                    currentIndex = child.currentIndex
                    completionSeed = child.completionSeed
                    endlessLoopState = child.endlessLoopState
                    lastBehavior = child.lastBehavior
                }
                XCTAssertEqual(currentIndex, 0)
                XCTAssertEqual(completionSeed, 4)
                XCTAssertEqual(endlessLoopState, .animating)
                XCTAssertEqual(lastBehavior, behavior)
            }
        }

        assertZeroIndexCompletionPublishes(didAnimate: true)
        assertZeroIndexCompletionPublishes(didAnimate: false)
    }

    func testChildUpdateViewChangeEventDrivenAbsentCompletionPublishesAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            completion.setValue(.none)

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 4)
            XCTAssertEqual(endlessLoopState, .animating)
        }
    }

    func testChildUpdateViewChangeEventDrivenInvalidCompletionPublishesAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            graph.removeNode(completion.identifier)
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            viewGraph.data.transactionSeed = 63

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 4)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateViewChangeEventDrivenStaleCompletionPublishesAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 3, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(completion.value?.seed, 3)
            XCTAssertEqual(completion.value?.didAnimate, true)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 4)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateViewChangeEventDrivenFalseCompletionAdvancesAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .paused
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(
                Optional.some(Container.AnimationCompletion(seed: 4, didAnimate: false))
            )
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .paused
                child.lastBehavior = behavior
            }
            viewGraph.data.transactionSeed = 64

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 64)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 1))
            XCTAssertEqual(lastBehavior, behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateViewChangeClearsMonitoringLoopWithoutRestart() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 0)
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.none)
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.completionSeed = 4
                child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 0)
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 4)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateShorterRepeatingPhasesPublishClampedCurrentPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 3
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 3
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            var currentIndex: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
            }
            XCTAssertEqual(currentIndex, 3)
        }
    }

    func testChildUpdateLongerRepeatingPhasesPublishCurrentPhaseBeforeContinuation() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 0
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 0
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            var currentIndex: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
            }
            XCTAssertEqual(currentIndex, 0)
        }
    }

    func testChildUpdateReorderedRepeatingPhasesPublishCurrentIndexPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 2, 1, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            var currentIndex: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
            }
            XCTAssertEqual(currentIndex, 1)
        }
    }

    func testChildUpdateShorterEventDrivenPhasesPublishClampedCurrentPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 3
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 3
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            var currentIndex: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
            }
            XCTAssertEqual(currentIndex, 3)
        }
    }

    func testChildUpdateLongerEventDrivenPhasesPublishCurrentPhaseBeforeContinuation() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 1, 2, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            var currentIndex: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
            }
            XCTAssertEqual(currentIndex, 1)
        }
    }

    func testChildUpdateReorderedEventDrivenPhasesPublishCurrentIndexPhase() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let source = graph.makeInput(
                value: Container(
                    phases: [0, 1, 2, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)
            _ = childValue.value
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 1
                child.lastBehavior = behavior
            }

            source.setValue(
                Container(
                    phases: [0, 2, 1, 3],
                    content: { PhaseSizedView(width: CGFloat($0)) },
                    animation: { _ in nil },
                    behavior: behavior
                )
            )
            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            var currentIndex: Int?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
            }
            XCTAssertEqual(currentIndex, 1)
        }
    }

    func testChildUpdateDoesNotConsumeCompletionWhileInvisible() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: false)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            XCTAssertEqual(childValue.value.content.width, 0)

            completion.setValue(.some(Container.AnimationCompletion(seed: 0, didAnimate: true)))
            let unchanged = childValue.value

            XCTAssertEqual(unchanged.content.width, 0)
            XCTAssertNil(unchanged.phaseChangeTransactionSeed)
        }
    }

    func testChildUpdateWithInvalidVisibilityWeakAttributePublishesCurrentPhaseOnly() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 3, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let weakVisibility = isVisible.asWeak()
            graph.removeNode(isVisible.identifier)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: weakVisibility
            )
            child.currentIndex = 1
            child.completionSeed = 3
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateInvalidVisibilityPublishesUpdatedContainerContent() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let original = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: .repeating
            )
            let updated = Container(
                phases: [10, 11, 12],
                content: { PhaseSizedView(width: CGFloat($0 * 10)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(99))
            )
            let source = graph.makeInput(value: original)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 3, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let weakVisibility = isVisible.asWeak()
            graph.removeNode(isVisible.identifier)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: weakVisibility
            )
            child.currentIndex = 1
            child.completionSeed = 3
            child.lastBehavior = original.behavior
            let childValue = graph.makeStatefulRule(child)

            source.setValue(updated)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 110)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            var currentIndex: Int?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(lastBehavior, original.behavior)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateMatchingGraphPhaseDoesNotResetBeforeInvalidVisibilityPublish() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 7
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 9, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let weakVisibility = isVisible.asWeak()
            graph.removeNode(isVisible.identifier)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: weakVisibility
            )
            child.currentIndex = 2
            child.completionSeed = 9
            child.resetSeed = 7
            child.endlessLoopState = .animating
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 9)
            XCTAssertEqual(resetSeed, 7)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, .eventDriven(trigger: AnyEquatable(1)))
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateGraphPhaseResetBeforeInvalidVisibilityPublish() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 8
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let weakVisibility = isVisible.asWeak()
            graph.removeNode(isVisible.identifier)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: weakVisibility
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 7
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 191
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 91
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 191)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 91)
            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, true)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 8)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertNil(lastBehavior)
        }
    }

    func testChildUpdateWithInvalidCompletionWeakAttributeDoesNotConsumeCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(7)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in .linear(duration: 0.25) },
                behavior: behavior
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 3, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            graph.removeNode(completion.identifier)
            let isVisible = graph.makeInput(value: true)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 3
            child.lastBehavior = behavior
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertNil(value.phaseChangeTransactionSeed)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateGraphPhaseResetInvalidCompletionPublishesAfterBehaviorStore() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(9)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: behavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 6
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            graph.removeNode(completion.identifier)
            let isVisible = graph.makeInput(value: true)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 5
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 197
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 97
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 197)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 97)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateInvisibleResetInvalidCompletionPublishesAfterBehaviorStore() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(11)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: behavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 12
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            graph.removeNode(completion.identifier)
            let isVisible = graph.makeInput(value: false)

            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 12
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 211
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 111
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 211)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 111)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 12)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateGraphPhaseResetKeepsPhaseChangeTransactionState() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(1))
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 1
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 9
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 177
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 77
            let childValue = graph.makeStatefulRule(child)

            let resetValue = childValue.value

            XCTAssertEqual(resetValue.content.width, 0)
            XCTAssertEqual(resetValue.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 177)
            XCTAssertEqual(resetValue.phaseChangeTransactionSeed, 77)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 10)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)
        }
    }

    func testChildUpdateGraphPhaseResetVisibleRepeatingStartsFromResetIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 71
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 71)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeRepeatingStartsBeforeResetLane() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initial.behavior
            }
            completion.setValue(.none)
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 91

            let value = childValue.value

            XCTAssertEqual(value.content.width, 101)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 91)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changed.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeRepeatingSkipsBehaviorMismatchAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(1))
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in nil },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
            }
            completion.setValue(.none)
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 93

            let value = childValue.value

            XCTAssertEqual(value.content.width, 101)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 93)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeRepeatingInvalidCompletionPublishesAfterResetLane() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initial.behavior
            }
            graph.removeNode(completion.identifier)
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 161

            let value = childValue.value

            XCTAssertEqual(value.content.width, 101)
            XCTAssertNotNil(value.phaseChangeTransaction.animation)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 161)
            XCTAssertEqual(animationRequests, 1)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changed.behavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeRepeatingAbsentCompletionPublishesAfterResetLane() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initial.behavior
            }
            completion.setValue(.none)
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 162

            let value = childValue.value

            XCTAssertEqual(value.content.width, 101)
            XCTAssertNotNil(value.phaseChangeTransaction.animation)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 162)
            XCTAssertEqual(animationRequests, 1)
            XCTAssertNil(completion.value)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changed.behavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeRepeatingStaleCompletionPublishesAfterResetLane() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initial.behavior
            }
            completion.setValue(
                .some(Container.AnimationCompletion(seed: 5, didAnimate: true))
            )
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 163

            let value = childValue.value

            XCTAssertEqual(value.content.width, 101)
            XCTAssertNotNil(value.phaseChangeTransaction.animation)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 163)
            XCTAssertEqual(animationRequests, 1)
            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, true)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changed.behavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeRepeatingFalseCompletionAdvancesAfterResetLane() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 6, didAnimate: false)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initial.behavior
            }
            completion.setValue(
                .some(Container.AnimationCompletion(seed: 6, didAnimate: false))
            )
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 164

            let value = childValue.value

            XCTAssertEqual(value.content.width, 102)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 164)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 7)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 1))
            XCTAssertEqual(lastBehavior, changed.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 7)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeRepeatingMatchingCompletionAdvancesAfterResetLane() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 6, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initial.behavior
            }
            completion.setValue(
                .some(Container.AnimationCompletion(seed: 6, didAnimate: true))
            )
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 165

            let value = childValue.value

            XCTAssertEqual(value.content.width, 102)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 165)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 7)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changed.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 7)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseResetVisibleRepeatingConsumesPostAdvanceCompletion() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 6, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 72
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 72)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 7)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 7)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseResetVisibleRepeatingFalseCompletionInstallsMonitoringAfterVisibleAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 6, didAnimate: false)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 73
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 2)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 73)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 2)
            XCTAssertEqual(completionSeed, 7)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .monitoring(firstNonAnimatedPhaseIndex: 1))
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 7)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseResetVisibleRepeatingInvalidCompletionPublishesAfterVisibleAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 6, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            graph.removeNode(completion.identifier)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 76
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 76)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateGraphPhaseResetVisibleRepeatingStaleCompletionPublishesAfterVisibleAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 74
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 74)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseResetVisibleRepeatingAbsentCompletionPublishesAfterVisibleAdvance() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            viewGraph.data.transactionSeed = 75
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 75)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            XCTAssertNil(completion.value)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseResetEventDrivenCompletionSkipsResetZeroIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: behavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 2)
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 211
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 111
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 211)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 111)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeEventDrivenZeroIndexCompletionPublishes() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(2)
            )
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 219
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
                child.phaseChangeTransaction = phaseTransaction
                child.phaseChangeTransactionSeed = 119
            }
            completion.setValue(.some(Container.AnimationCompletion(seed: 5, didAnimate: true)))
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 100)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 219)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 119)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, true)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeEventDrivenMatchingCompletionPublishesAtResetZeroIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(2)
            )
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 269
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
                child.phaseChangeTransaction = phaseTransaction
                child.phaseChangeTransactionSeed = 169
            }
            completion.setValue(.some(Container.AnimationCompletion(seed: 5, didAnimate: true)))
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 100)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 269)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 169)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, true)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeSkipsBehaviorMismatchAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.repeating
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>
                .Behavior
                .eventDriven(trigger: AnyEquatable(2))
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: true)
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 239
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            completion.setValue(.none)
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
                child.phaseChangeTransaction = phaseTransaction
                child.phaseChangeTransactionSeed = 119
            }
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)
            viewGraph.data.transactionSeed = 151

            let value = childValue.value

            XCTAssertEqual(value.content.width, 100)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 239)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 119)
            XCTAssertNil(value.phaseChangeTransaction.animation)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertNil(completion.value)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeEventDrivenInvalidCompletionPublishes() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(2)
            )
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            let isVisible = graph.makeInput(value: true)
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 229
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: weakCompletion,
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
                child.phaseChangeTransaction = phaseTransaction
                child.phaseChangeTransactionSeed = 129
            }
            graph.removeNode(completion.identifier)
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 100)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 229)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 129)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeEventDrivenAbsentCompletionPublishes() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(2)
            )
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 239
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
                child.phaseChangeTransaction = phaseTransaction
                child.phaseChangeTransactionSeed = 139
            }
            completion.setValue(.none)
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 100)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 239)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 139)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertNil(completion.value)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeEventDrivenStaleCompletionPublishes() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(2)
            )
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 249
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
                child.phaseChangeTransaction = phaseTransaction
                child.phaseChangeTransactionSeed = 149
            }
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 100)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 249)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 149)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(completion.value?.seed, 4)
            XCTAssertEqual(completion.value?.didAnimate, true)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)
        }
    }

    func testChildUpdateGraphPhaseAndViewChangeEventDrivenFalseCompletionPublishesAtResetZeroIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let initialBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let changedBehavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(2)
            )
            let initial = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: initialBehavior
            )
            let changed = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0 + 100)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: changedBehavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: initial)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: false)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 259
            let childValue = graph.makeStatefulRule(
                Container.Child(
                    view: source,
                    transaction: transaction,
                    transactionSeed: viewGraph.data._transactionSeed,
                    phase: phase,
                    animationCompletion: completion.asWeak(),
                    isVisible: isVisible.asWeak()
                )
            )

            _ = childValue.value
            viewGraph.flushTransactions()
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                child.currentIndex = 2
                child.completionSeed = 4
                child.resetSeed = 3
                child.endlessLoopState = .paused
                child.lastBehavior = initialBehavior
                child.phaseChangeTransaction = phaseTransaction
                child.phaseChangeTransactionSeed = 159
            }
            var nextPhase = graphPhase
            nextPhase.resetSeed = 9
            phase.setValue(nextPhase)
            source.setValue(changed)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 100)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 259)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 159)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, changedBehavior)
        }
    }

    func testChildUpdateGraphPhaseResetEventDrivenAbsentCompletionPublishesAfterBehaviorStore() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: behavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(value: Optional<Container.AnimationCompletion>.none)
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .paused
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 229
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 129
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 229)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 129)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertNil(completion.value)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateGraphPhaseResetEventDrivenInvalidCompletionPublishesAfterBehaviorStore() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: behavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let weakCompletion = completion.asWeak()
            graph.removeNode(completion.identifier)
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: weakCompletion,
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .paused
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 227
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 127
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 227)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 127)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateGraphPhaseResetEventDrivenStaleCompletionPublishesAfterBehaviorStore() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return .linear(duration: 0.25)
                },
                behavior: behavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .paused
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 233
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 133
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 233)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 133)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(completion.value?.seed, 4)
            XCTAssertEqual(completion.value?.didAnimate, true)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateGraphPhaseResetEventDrivenFalseCompletionSkipsMonitoringAtResetZeroIndex() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            var animationRequests = 0
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(1)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in
                    animationRequests += 1
                    return nil
                },
                behavior: behavior
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 3
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: false)
                )
            )
            let isVisible = graph.makeInput(value: true)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 1
            child.endlessLoopState = .paused
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 223
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 123
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 223)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 123)
            XCTAssertEqual(animationRequests, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(completion.value?.seed, 5)
            XCTAssertEqual(completion.value?.didAnimate, false)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(resetSeed, 3)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateInvisibleResetReturnsInitialPhaseWithoutClearingPhaseTransactionState() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 4, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: false)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 1
            child.completionSeed = 4
            child.endlessLoopState = .animating
            child.lastBehavior = container.behavior
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 183
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 83
            let childValue = graph.makeStatefulRule(child)

            let resetValue = childValue.value

            XCTAssertEqual(resetValue.content.width, 0)
            XCTAssertEqual(resetValue.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 183)
            XCTAssertEqual(resetValue.phaseChangeTransactionSeed, 83)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
        }
    }

    func testChildUpdateInvisibleResetStoresCurrentBehaviorAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let behavior = PhaseAnimator<Int, PhaseSizedView>.Behavior.eventDriven(
                trigger: AnyEquatable(2)
            )
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: behavior
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: false)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 1)
            child.lastBehavior = .repeating
            let childValue = graph.makeStatefulRule(child)

            let resetValue = childValue.value

            XCTAssertEqual(resetValue.content.width, 0)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertNil(completion.value)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 5)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, behavior)
        }
    }

    func testChildUpdateInvisibleResetConsumesMatchingCompletionAfterReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: Phase())
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 5, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: false)
            viewGraph.data.transactionSeed = 41
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 1)
            child.lastBehavior = container.behavior
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 41)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 6)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testChildUpdateGraphPhaseAndInvisibleResetIncrementCompletionSeedTwice() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .eventDriven(trigger: AnyEquatable(2))
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 9
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.none
            )
            let isVisible = graph.makeInput(value: false)
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 7
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 1)
            child.lastBehavior = .repeating
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 199
            child.phaseChangeTransaction = phaseTransaction
            child.phaseChangeTransactionSeed = 99
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 0)
            XCTAssertEqual(value.phaseChangeTransaction[PhaseAnimatorTransactionWidthKey.self], 199)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 99)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 0)
            XCTAssertEqual(completionSeed, 6)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)
        }
    }

    func testChildUpdateGraphPhaseAndInvisibleResetConsumesMatchingCompletionAfterSecondReset() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let container = Container(
                phases: [0, 1, 2],
                content: { PhaseSizedView(width: CGFloat($0)) },
                animation: { _ in nil },
                behavior: .repeating
            )
            var graphPhase = Phase()
            graphPhase.resetSeed = 9
            let source = graph.makeInput(value: container)
            let transaction = graph.makeInput(value: Transaction())
            let phase = graph.makeInput(value: graphPhase)
            let completion = graph.makeInput(
                value: Optional<Container.AnimationCompletion>.some(
                    Container.AnimationCompletion(seed: 6, didAnimate: true)
                )
            )
            let isVisible = graph.makeInput(value: false)
            viewGraph.data.transactionSeed = 61
            var child = Container.Child(
                view: source,
                transaction: transaction,
                transactionSeed: viewGraph.data._transactionSeed,
                phase: phase,
                animationCompletion: completion.asWeak(),
                isVisible: isVisible.asWeak()
            )
            child.currentIndex = 2
            child.completionSeed = 4
            child.resetSeed = 7
            child.endlessLoopState = .monitoring(firstNonAnimatedPhaseIndex: 1)
            child.lastBehavior = .eventDriven(trigger: AnyEquatable(1))
            let childValue = graph.makeStatefulRule(child)

            let value = childValue.value

            XCTAssertEqual(value.content.width, 1)
            XCTAssertEqual(value.phaseChangeTransactionSeed, 61)
            XCTAssertTrue(viewGraph.hasPendingTransactions)
            var currentIndex: Int?
            var completionSeed: Int?
            var resetSeed: UInt32?
            var endlessLoopState: Container.Child.EndlessLoopState?
            var lastBehavior: PhaseAnimator<Int, PhaseSizedView>.Behavior?
            graph.mutateStatefulRule(childValue.identifier, as: Container.Child.self) { child in
                currentIndex = child.currentIndex
                completionSeed = child.completionSeed
                resetSeed = child.resetSeed
                endlessLoopState = child.endlessLoopState
                lastBehavior = child.lastBehavior
            }
            XCTAssertEqual(currentIndex, 1)
            XCTAssertEqual(completionSeed, 7)
            XCTAssertEqual(resetSeed, 9)
            XCTAssertEqual(endlessLoopState, .animating)
            XCTAssertEqual(lastBehavior, container.behavior)

            viewGraph.flushTransactions()

            XCTAssertEqual(completion.value?.seed, 7)
            XCTAssertEqual(completion.value?.didAnimate, false)
        }
    }

    func testAppearanceHandlerQueuesVisibleAssignmentThroughAsyncTransaction() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let isVisible = graph.makeInput(value: false)
            let appear = Container.appearanceHandler(isVisible: isVisible.asWeak(), value: true)

            appear()

            XCTAssertTrue(viewGraph.hasPendingTransactions)
            XCTAssertFalse(viewGraph.mayDeferUpdate)
            XCTAssertFalse(isVisible.value)

            viewGraph.flushTransactions()

            XCTAssertTrue(isVisible.value)
            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(viewGraph.data.transactionSeed, 1)
        }
    }

    func testAppearanceHandlerQueuesWithCurrentTransactionAndID() {
        withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let isVisible = graph.makeInput(value: false)
            let appear = Container.appearanceHandler(isVisible: isVisible.asWeak(), value: true)
            var ambient = Transaction()
            ambient[PhaseAnimatorTransactionWidthKey.self] = 515
            var mergedMutationDidRun = false
            var observedWidth: CGFloat?

            withTransaction(ambient) {
                let id = Transaction.id
                appear()
                viewGraph.asyncTransaction(
                    Transaction.current,
                    id: id,
                    mutation: CustomGraphMutation {
                        mergedMutationDidRun = true
                        observedWidth = Transaction.current[PhaseAnimatorTransactionWidthKey.self]
                    },
                    style: .deferred,
                    mayDeferUpdate: false
                )
            }

            XCTAssertTrue(viewGraph.hasPendingTransactions)
            XCTAssertFalse(viewGraph.mayDeferUpdate)
            XCTAssertFalse(isVisible.value)

            viewGraph.flushTransactions()

            XCTAssertTrue(isVisible.value)
            XCTAssertTrue(mergedMutationDidRun)
            XCTAssertEqual(observedWidth, 515)
            XCTAssertEqual(viewGraph.data.transactionSeed, 1)
        }
    }

    func testStateTransitioningContainerMakeViewEvaluatesAppearanceDuringHostUpdate() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            let view = PhaseAnimator([7]) { phase in
                PhaseSizedView(width: CGFloat(phase))
            }
            let outputs = AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let source = graph.makeInput(value: view)
                return type(of: view)._makeView(
                    view: _GraphValue(_attribute: source),
                    inputs: makeViewInputs(graph: graph)
                )
            }

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 7, height: 19))
            XCTAssertFalse(viewGraph.hasPendingTransactions)

            viewGraph.updateOutputs(at: Time(seconds: 0))

            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(viewGraph.data.transactionSeed, 2)
        }
    }

    func testStateTransitioningContainerMakeViewListEvaluatesAppearanceDuringHostUpdate() throws {
        try withPhaseAnimatorHost { viewGraph, graph in
            typealias Container = PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
            let view = Container(
                phases: [7],
                content: { phase in
                    PhaseSizedView(width: CGFloat(phase))
                },
                animation: { _ in .default },
                behavior: .eventDriven(trigger: AnyEquatable(0))
            )
            let outputs = AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                let source = graph.makeInput(value: view)
                let listInputs = makeViewInputs(graph: graph).listInputs
                return Container._makeViewList(
                    view: _GraphValue(_attribute: source),
                    inputs: listInputs
                )
            }

            guard case let .staticList(elements) = outputs.views else {
                return XCTFail("Expected a static list output.")
            }
            guard case .modified = elements else {
                return XCTFail("Expected the appearance modifier to wrap the list elements.")
            }

            var from = 0
            let (materialized, _) = AGSubgraph.withCurrent(viewGraph.data.rootSubgraph) {
                elements.makeElements(
                    from: &from,
                    inputs: makeViewInputs(graph: graph),
                    indirectMap: nil
                ) { inputs, makeView in
                    (makeView(inputs), false)
                }
            }
            let layout = try XCTUnwrap(materialized?._layoutComputer.attribute?.value)

            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 7, height: 19))
            XCTAssertFalse(viewGraph.hasPendingTransactions)

            viewGraph.updateOutputs(at: Time(seconds: 0))

            XCTAssertFalse(viewGraph.hasPendingTransactions)
            XCTAssertEqual(viewGraph.data.transactionSeed, 2)
        }
    }

    func testTransactionRuleSelectsPhaseChangeTransactionWhenSeedMatches() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 13
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 89

            let transaction = graph.makeInput(value: baseTransaction)
            let transactionSeed = graph.makeInput(value: UInt32(7))
            let phaseChangeTransaction = graph.makeInput(value: phaseTransaction)
            let phaseChangeTransactionSeed = graph.makeInput(value: Optional<UInt32>.some(7))
            let selected = graph.makeStatefulRule(
                PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.TransactionRule(
                    transaction: transaction,
                    transactionSeed: transactionSeed,
                    phaseChangeTransaction: phaseChangeTransaction,
                    phaseChangeTransactionSeed: phaseChangeTransactionSeed
                )
            )

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 89)

            phaseChangeTransactionSeed.setValue(8)

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 13)
        }
    }

    func testTransactionRuleFallsBackWhenPhaseChangeSeedIsNil() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 21
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 144

            let selected = graph.makeStatefulRule(
                PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.TransactionRule(
                    transaction: graph.makeInput(value: baseTransaction),
                    transactionSeed: graph.makeInput(value: UInt32(9)),
                    phaseChangeTransaction: graph.makeInput(value: phaseTransaction),
                    phaseChangeTransactionSeed: graph.makeInput(value: Optional<UInt32>.none)
                )
            )

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 21)
        }
    }

    func testTransactionRuleRechecksCurrentTransactionSeed() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            var baseTransaction = Transaction()
            baseTransaction[PhaseAnimatorTransactionWidthKey.self] = 34
            var phaseTransaction = Transaction()
            phaseTransaction[PhaseAnimatorTransactionWidthKey.self] = 233

            let transactionSeed = graph.makeInput(value: UInt32(2))
            let phaseChangeTransactionSeed = graph.makeInput(value: Optional<UInt32>.some(3))
            let selected = graph.makeStatefulRule(
                PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.TransactionRule(
                    transaction: graph.makeInput(value: baseTransaction),
                    transactionSeed: transactionSeed,
                    phaseChangeTransaction: graph.makeInput(value: phaseTransaction),
                    phaseChangeTransactionSeed: phaseChangeTransactionSeed
                )
            )

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 34)

            transactionSeed.setValue(3)

            XCTAssertEqual(selected.value[PhaseAnimatorTransactionWidthKey.self], 233)
        }
    }

    func testTransactionRuleStorageLabelsMatchObservedShape() {
        let graph = _AGGraph()
        let ref = _AGGraphContext(graph: graph)

        ref.withCurrent {
            let rule = PhaseAnimator<Int, PhaseSizedView>
                .StateTransitioningContainer
                .TransactionRule(
                    transaction: graph.makeInput(value: Transaction()),
                    transactionSeed: graph.makeInput(value: UInt32.zero),
                    phaseChangeTransaction: graph.makeInput(value: Transaction()),
                    phaseChangeTransactionSeed: graph.makeInput(value: Optional<UInt32>.none)
                )

            let labels = Mirror(reflecting: rule).children.map(\.label)
            XCTAssertEqual(labels, [
                "_transaction",
                "_transactionSeed",
                "_phaseChangeTransaction",
                "_phaseChangeTransactionSeed",
            ])
        }
    }

    func testViewPhaseAnimatorRelaysPlaceholderContent() throws {
        try withPhaseAnimatorHost { _, graph in
            let view = PhaseAnimatorRelaySource().phaseAnimator([0]) { placeholder, _ in
                placeholder
            }
            let source = graph.makeInput(value: view)
            let outputs = type(of: view)._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )

            let layout = try XCTUnwrap(outputs._layoutComputer.attribute?.value)
            XCTAssertEqual(layout.sizeThatFits(.unspecified), CGSize(width: 31, height: 23))
        }
    }

    private func makeViewInputs(
        graph: _AGGraph,
        transaction: Transaction = Transaction(),
        time: Attribute<Time>? = nil,
        size: Attribute<ViewSize>? = nil
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            time: time ?? graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: Phase()),
            environment: environment,
            transaction: graph.makeInput(value: transaction)
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

    private func withPhaseAnimatorHost(
        _ body: (ViewGraph, _AGGraph) throws -> Void
    ) rethrows {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        try viewGraph.data.withCurrent {
            try body(viewGraph, viewGraph.data.graph)
        }
    }

    private func makeChild(
        in graph: _AGGraph,
        viewGraph: ViewGraph,
        container: PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer
    ) -> PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.Child {
        let source = graph.makeInput(value: container)
        let transaction = graph.makeInput(value: Transaction())
        let phase = graph.makeInput(value: Phase())
        let completion = graph.makeInput(
            value: Optional<PhaseAnimator<Int, PhaseSizedView>
                .StateTransitioningContainer
                .AnimationCompletion>.none
        )
        let isVisible = graph.makeInput(value: true)
        return PhaseAnimator<Int, PhaseSizedView>.StateTransitioningContainer.Child(
            view: source,
            transaction: transaction,
            transactionSeed: viewGraph.data._transactionSeed,
            phase: phase,
            animationCompletion: completion.asWeak(),
            isVisible: isVisible.asWeak()
        )
    }

    private static func typeDescription(of value: Any) -> String {
        String(reflecting: Mirror(reflecting: value).subjectType)
    }

    private func compactedPhases(_ phases: [Int]) -> [Int] {
        phases.reduce(into: []) { result, phase in
            if result.last != phase {
                result.append(phase)
            }
        }
    }
}
