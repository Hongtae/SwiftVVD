import XCTest
@testable import VUI

final class GraphHostRemovedStateTests: XCTestCase {
    func testRemovedStateTransitionsDispatchSubgraphRemovableCallbacksOnce() {
        let host = GraphHost()
        let recorder = RemovedStateRecorder()

        installRemovableRule(in: host, recorder: recorder)

        host.removedState = .unattached
        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)

        host.removedState = .unattached
        XCTAssertEqual(recorder.events, ["update", "willRemove"])

        host.removedState = []
        XCTAssertEqual(recorder.events, ["update", "willRemove", "didReinsert"])
        XCTAssertFalse(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)
    }

    func testHiddenForReuseSetsHiddenFlagAndDispatchesRemoval() {
        let host = RecordingRemovedStateGraphHost()
        let recorder = RemovedStateRecorder()

        installRemovableRule(in: host, recorder: recorder)

        host.removedState = .hiddenForReuse

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(host.isRemoved)
        XCTAssertTrue(host.isHiddenForReuse)
        XCTAssertEqual(host.isHiddenForReuseDidChangeCount, 1)

        host.removedState = .unattached

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)
        XCTAssertEqual(host.isHiddenForReuseDidChangeCount, 2)
    }

    func testChildHostInheritsParentHiddenForReuseRemoval() {
        let parent = GraphHost()
        let child = ChildRemovedStateGraphHost(parent: parent)
        let recorder = RemovedStateRecorder()

        installRemovableRule(in: child, recorder: recorder)

        parent.removedState = .hiddenForReuse
        child.updateRemovedState()

        XCTAssertEqual(recorder.events, ["update", "willRemove"])
        XCTAssertTrue(child.isRemoved)
        XCTAssertTrue(child.isHiddenForReuse)

        parent.removedState = []
        child.updateRemovedState()

        XCTAssertEqual(recorder.events, ["update", "willRemove", "didReinsert"])
        XCTAssertFalse(child.isRemoved)
        XCTAssertFalse(child.isHiddenForReuse)
    }

    func testViewGraphHostUpdateRemovedStatePacksUnattachedAndHiddenForReuse() {
        let host = ViewGraphHost()

        host.updateRemovedState(isUnattached: true, isHiddenForReuse: false)
        XCTAssertEqual(host.removedState, .unattached)
        XCTAssertTrue(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)

        host.updateRemovedState(isUnattached: true, isHiddenForReuse: true)
        XCTAssertEqual(host.removedState, [.unattached, .hiddenForReuse])
        XCTAssertTrue(host.isRemoved)
        XCTAssertTrue(host.isHiddenForReuse)

        host.updateRemovedState(isUnattached: false, isHiddenForReuse: false)
        XCTAssertEqual(host.removedState, [])
        XCTAssertFalse(host.isRemoved)
        XCTAssertFalse(host.isHiddenForReuse)
    }

    func testViewGraphHiddenForReuseDispatchesFeatureBufferHook() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        let feature = RecordingViewGraphFeature()
        viewGraph.addFeature(feature)

        XCTAssertEqual(viewGraph.viewGraphFeatureCount, 1)

        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: true)

        XCTAssertEqual(feature.hiddenReuseChangeGraphs.count, 1)
        XCTAssertTrue(feature.hiddenReuseChangeGraphs[0] === viewGraph)

        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: true)
        XCTAssertEqual(feature.hiddenReuseChangeGraphs.count, 1)

        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: false)
        XCTAssertEqual(feature.hiddenReuseChangeGraphs.count, 2)
        XCTAssertTrue(feature.hiddenReuseChangeGraphs[1] === viewGraph)
    }

    func testViewGraphFeatureDefaultsAreNoopAndAllowAsyncUpdate() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        let feature = DefaultOnlyViewGraphFeature()

        XCTAssertEqual(feature.allowsAsyncUpdate(graph: viewGraph), true)
        XCTAssertFalse(feature.needsUpdate(graph: viewGraph))

        feature.uninstantiate(graph: viewGraph)
        feature.outputsDidChange(graph: viewGraph)
        feature.update(graph: viewGraph)

        viewGraph.addFeature(feature)
        viewGraph.updateRemovedState(isUnattached: false, isHiddenForReuse: true)
        XCTAssertEqual(viewGraph.viewGraphFeatureCount, 1)
    }

    func testViewGraphFeatureBufferModifiesRootInputsAndOutputs() {
        let recorder = ViewGraphFeatureDispatchRecorder()
        let feature = InputOutputMutatingViewGraphFeature(recorder: recorder)
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: FeatureDispatchRootView.self,
            content: FeatureDispatchRootView(recorder: recorder),
            rendererHost: rendererHost,
            requestedOutputs: [],
            features: [feature]
        )
        rendererHost.storage = viewGraph

        XCTAssertEqual(viewGraph.viewGraphFeatureCount, 1)
        XCTAssertEqual(recorder.events, ["inputs", "root", "outputs"])
        XCTAssertTrue(recorder.rootUsingGraphicsRenderer)
        XCTAssertTrue(recorder.rootAnimationsDisabled)
        XCTAssertTrue(recorder.outputFeatureSawLayoutComputer)
        XCTAssertTrue(recorder.outputFeatureSawUsingGraphicsRenderer)
        XCTAssertNil(viewGraph.rootLayoutComputer)
    }

    func testImageRendererHostViewGraphInstallsGraphicsRendererAndAnimationsDisabledOnly() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph

        let graph = _AGGraph()
        _AGGraph.withCurrent(graph) {
            var inputs = makeViewInputs(graph: graph)
            inputs.base.options = [.supportsVariableFrameDuration]

            ImageRendererHostViewGraph().modifyViewInputs(inputs: &inputs, graph: viewGraph)

            XCTAssertTrue(inputs[UsingGraphicsRenderer.self])
            XCTAssertTrue(inputs.base.options.contains(.animationsDisabled))
            XCTAssertTrue(inputs.base.options.contains(.supportsVariableFrameDuration))
            XCTAssertEqual(
                inputs.base.options.rawValue,
                _GraphInputs.Options.animationsDisabled.rawValue
                    | _GraphInputs.Options.supportsVariableFrameDuration.rawValue
            )
        }
    }

    private func installRemovableRule(in host: GraphHost, recorder: RemovedStateRecorder) {
        host.data.withCurrent {
            AGSubgraph.$current.withValue(host.data.rootSubgraph) {
                let attr = host.data.graph.makeStatefulRule(RemovableRecorderRule(recorder: recorder))
                _ = attr.value
            }
        }
    }

    private func makeGraphInputs(graph: _AGGraph) -> _GraphInputs {
        _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time()),
            cachedEnvironment: MutableBox(
                CachedEnvironment(
                    environment: graph.makeInput(value: EnvironmentValues.tracking())
                )
            ),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(
            base: makeGraphInputs(graph: graph),
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(CGSize(width: 10, height: 10))),
            safeAreaInsets: OptionalAttribute<SafeAreaInsets>(),
            containerSize: OptionalAttribute<ViewSize>(),
            stackOrientation: nil
        )
    }
}

private final class RemovedStateRecorder {
    var events: [String] = []
}

private struct RemovableRecorderRule: StatefulRule, RemovableAttribute {
    typealias Value = Void

    var recorder: RemovedStateRecorder

    mutating func updateValue() {
        recorder.events.append("update")
        _AGGraph.setStatefulOutput(())
    }

    static func willRemove(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("willRemove")
        }
    }

    static func didReinsert(attribute: AGAttribute) {
        _AGGraph.current?.mutateStatefulRule(attribute, as: Self.self) { rule in
            rule.recorder.events.append("didReinsert")
        }
    }
}

private final class RecordingRemovedStateGraphHost: GraphHost {
    var isHiddenForReuseDidChangeCount = 0

    override func isHiddenForReuseDidChange() {
        isHiddenForReuseDidChangeCount += 1
    }
}

private final class ChildRemovedStateGraphHost: GraphHost {
    private weak var parent: GraphHost?

    init(parent: GraphHost) {
        self.parent = parent
        super.init(graph: parent.data.graph)
    }

    override var parentHost: GraphHost? {
        parent
    }
}

private final class RecordingViewGraphFeature: ViewGraphFeature {
    var hiddenReuseChangeGraphs: [ViewGraph] = []

    func isHiddenForReuseDidChange(graph: ViewGraph) {
        hiddenReuseChangeGraphs.append(graph)
    }
}

private struct DefaultOnlyViewGraphFeature: ViewGraphFeature {}

private final class ViewGraphFeatureDispatchRecorder {
    var events: [String] = []
    var rootUsingGraphicsRenderer = false
    var rootAnimationsDisabled = false
    var outputFeatureSawLayoutComputer = false
    var outputFeatureSawUsingGraphicsRenderer = false
}

private struct InputOutputMutatingViewGraphFeature: ViewGraphFeature {
    let recorder: ViewGraphFeatureDispatchRecorder

    func modifyViewInputs(inputs: inout _ViewInputs, graph: ViewGraph) {
        recorder.events.append("inputs")
        inputs[UsingGraphicsRenderer.self] = true
        inputs.base.options.insert(.animationsDisabled)
    }

    func modifyViewOutputs(outputs: inout _ViewOutputs, inputs: _ViewInputs, graph: ViewGraph) {
        recorder.events.append("outputs")
        recorder.outputFeatureSawLayoutComputer = outputs._layoutComputer.attribute != nil
        recorder.outputFeatureSawUsingGraphicsRenderer = inputs[UsingGraphicsRenderer.self]
        outputs._layoutComputer = OptionalAttribute()
    }
}

private struct FeatureDispatchRootView: View {
    let recorder: ViewGraphFeatureDispatchRecorder

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("FeatureDispatchRootView._makeView called outside an active _AGGraph context.")
        }
        let recorder = view._attribute.value.recorder
        recorder.events.append("root")
        recorder.rootUsingGraphicsRenderer = inputs[UsingGraphicsRenderer.self]
        recorder.rootAnimationsDisabled = inputs.base.options.contains(.animationsDisabled)

        let layoutComputer = graph.makeRule {
            LayoutComputer.fixed(CGSize(width: 1, height: 1))
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layoutComputer))
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(views: .staticList(.merged([])), nextImplicitID: 0, staticCount: 0)
    }
}

extension FeatureDispatchRootView: _PrimitiveView {}
