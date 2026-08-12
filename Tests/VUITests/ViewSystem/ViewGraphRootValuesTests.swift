import XCTest
@testable import VUI

final class ViewGraphRootValuesTests: XCTestCase {
    func testRootOutputsInstantiateAfterTheProposedSizeInputExists() throws {
        // ASSERTIONS: viewGraphRootInstantiationOrderObserved
        let host = TestRootValueUpdaterHost()
        let recorder = RootOutputInstantiationRecorder()
        let viewGraph = ViewGraph(
            rootViewType: RootOutputInstantiationView.self,
            content: RootOutputInstantiationView(recorder: recorder),
            rendererHost: host
        )
        host.storage = viewGraph

        XCTAssertNotNil(viewGraph.rootGeometry)
        XCTAssertNil(viewGraph.rootLayoutComputer)
        XCTAssertFalse(viewGraph.isInstantiated)
        XCTAssertEqual(recorder.makeViewCount, 0)

        let size = CGSize(width: 123, height: 456)
        viewGraph.setSize(size)
        try viewGraph.data.withCurrent {
            XCTAssertEqual(try XCTUnwrap(viewGraph.sizeAttr).value.value, size)
        }

        viewGraph.instantiateIfNeeded()

        XCTAssertTrue(viewGraph.isInstantiated)
        XCTAssertNotNil(viewGraph.rootLayoutComputer)
        XCTAssertEqual(recorder.makeViewCount, 1)
    }

    func testLayoutRootPublishesContainerSizeInputBeforeInstantiation() throws {
        // ASSERTIONS: viewGraphRootInstantiationOrderObserved
        let host = TestRootValueUpdaterHost()
        let recorder = RootOutputInstantiationRecorder()
        let viewGraph = ViewGraph(
            rootViewType: RootOutputInstantiationView.self,
            content: RootOutputInstantiationView(recorder: recorder),
            rendererHost: host
        )
        host.storage = viewGraph

        let containerSize = ViewSize(
            CGSize(width: 321, height: 654),
            proposal: _ProposedSize(width: 123, height: 456)
        )
        viewGraph.setContainerSize(containerSize)
        viewGraph.instantiateIfNeeded()

        try viewGraph.data.withCurrent {
            XCTAssertEqual(
                try XCTUnwrap(viewGraph.containerSizeAttr).value,
                containerSize
            )
        }
        XCTAssertEqual(recorder.containerSize, containerSize)
    }

    func testRootWithoutLayoutOutputOmitsContainerSizeInput() {
        // ASSERTIONS: viewGraphRootInstantiationOrderObserved
        let host = TestRootValueUpdaterHost()
        let recorder = RootOutputInstantiationRecorder()
        let viewGraph = ViewGraph(
            rootViewType: RootOutputInstantiationView.self,
            content: RootOutputInstantiationView(recorder: recorder),
            rendererHost: host,
            requestedOutputs: []
        )
        host.storage = viewGraph

        XCTAssertNil(viewGraph.containerSizeAttr)
        viewGraph.setContainerSize(ViewSize(CGSize(width: 10, height: 20)))
        viewGraph.instantiateIfNeeded()

        XCTAssertNil(recorder.containerSize)
    }

    func testRootDisplayListOutputUsesOrdinaryUnflaggedRule() throws {
        // ASSERTIONS: viewGraphRootDisplayListUnflaggedObserved
        let host = TestRootValueUpdaterHost()
        let viewGraph = ViewGraph(
            rootViewType: Color.self,
            content: Color.red,
            rendererHost: host
        )
        host.storage = viewGraph
        viewGraph.setSize(CGSize(width: 40, height: 40))
        viewGraph.instantiateIfNeeded()

        try viewGraph.data.withCurrent {
            let displayList = try XCTUnwrap(viewGraph.rootDisplayList)
            XCTAssertTrue(displayList.flags.isEmpty)
        }
    }

    func testRootValueRawOrderMatchesCurrentHostSurface() {
        XCTAssertEqual(ViewGraphRootValues.rootView.rawValue, 0x1)
        XCTAssertEqual(ViewGraphRootValues.environment.rawValue, 0x2)
        XCTAssertEqual(ViewGraphRootValues.transform.rawValue, 0x4)
        XCTAssertEqual(ViewGraphRootValues.size.rawValue, 0x8)
        XCTAssertEqual(ViewGraphRootValues.safeArea.rawValue, 0x10)
        XCTAssertEqual(ViewGraphRootValues.containerSize.rawValue, 0x20)
        XCTAssertEqual(ViewGraphRootValues.focusStore.rawValue, 0x40)
        XCTAssertEqual(ViewGraphRootValues.focusedItem.rawValue, 0x80)
        XCTAssertEqual(ViewGraphRootValues.focusedValues.rawValue, 0x100)
        XCTAssertEqual(ViewGraphRootValues.all.rawValue, 0x1ff)
    }

    func testInvalidatePropertiesUnionsNewBitsAndSchedulesOnlyForNewDirtyValues() {
        let host = TestRootValueUpdaterHost()
        let viewGraph = ViewGraph(
            rootViewType: EmptyView.self,
            content: EmptyView(),
            rendererHost: host
        )
        host.storage = viewGraph
        let delegate = RecordingViewGraphDelegate(graph: viewGraph)
        viewGraph.viewDelegate = delegate

        host.invalidateProperties([.size], mayDeferUpdate: false)

        XCTAssertEqual(host.valuesNeedingUpdate, [.size])
        XCTAssertFalse(viewGraph.mayDeferUpdate)
        XCTAssertEqual(delegate.setNeedsUpdateCount, 1)

        host.invalidateProperties([.size], mayDeferUpdate: true)

        XCTAssertEqual(host.valuesNeedingUpdate, [.size])
        XCTAssertEqual(delegate.setNeedsUpdateCount, 1)

        host.invalidateProperties([.environment], mayDeferUpdate: true)

        XCTAssertEqual(host.valuesNeedingUpdate, [.environment, .size])
        XCTAssertFalse(viewGraph.mayDeferUpdate)
        XCTAssertEqual(delegate.setNeedsUpdateCount, 2)
    }
}

private final class RootOutputInstantiationRecorder: @unchecked Sendable {
    var makeViewCount = 0
    var containerSize: ViewSize?
}

private struct RootOutputInstantiationView: View, PrimitiveView, LeafViewLayout {
    var recorder: RootOutputInstantiationRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        let recorder = view._attribute.value.recorder
        recorder.makeViewCount += 1
        recorder.containerSize = inputs.containerSize.attribute?.value
        var outputs = _ViewOutputs()
        makeLeafLayout(&outputs, view: view, inputs: inputs)
        return outputs
    }

    func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
        .zero
    }

    typealias Body = Never
}

private final class TestRootValueUpdaterHost: ViewRendererHost, ViewGraphRootValueUpdater {
    var storage: ViewGraph!
    let sceneResources = SceneResources()
    var currentTimestamp: Time = Time(seconds: 0)
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase: ViewRenderingPhase = ViewRenderingPhase()
    var externalUpdateCount: Int = 0

    var viewGraph: ViewGraph { storage }
    var responderNode: ResponderNode? { nil }
    var gestureGraph: GestureGraph? { nil }

    func updateRootView() {}
    func updateEnvironment() {}
    func updateSize() {}
    func updateSafeArea() {}
    func updateContainerSize() {}

    func requestUpdate(after: Double) {}

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }
}

private final class RecordingViewGraphDelegate: ViewGraphDelegate {
    weak var graph: ViewGraph?
    var setNeedsUpdateCount = 0

    init(graph: ViewGraph) {
        self.graph = graph
    }

    func updateGraph<T>(body: (GraphHost) -> T) -> T {
        guard let graph else {
            fatalError("The view graph must outlive its delegate.")
        }
        return body(graph)
    }

    func graphDidChange() {
        setNeedsUpdate()
    }

    func setNeedsUpdate() {
        setNeedsUpdateCount += 1
    }

    func requestUpdate(after: Double) {}

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }
}
