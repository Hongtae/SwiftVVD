import XCTest
@testable import VUI
@testable import VVD

final class TabViewSurfaceTests: XCTestCase {
    // ASSERTIONS: tabSurfaceOwner27Observed
    // ASSERTIONS: tabSurfaceOwnerFieldMetadata27Observed
    func testModernTabAndTabViewRetainObservedOwners() {
        var selection = 2
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )
        let first = Tab(
            "First",
            systemImage: "1.circle",
            value: 1
        ) {
            Text("First Content")
        }
        let view = TabView(selection: binding) {
            first
            Tab(
                "Second",
                systemImage: "2.circle",
                value: 2,
                role: .prominent
            ) {
                Text("Second Content")
            }
        }

        XCTAssertEqual(first._value, 1)
        XCTAssertNil(first.role)
        XCTAssertEqual(view.selection?.wrappedValue, 2)
        view.selection?.wrappedValue = 1
        XCTAssertEqual(selection, 1)

        let viewType = String(reflecting: type(of: view))
        XCTAssertTrue(viewType.contains("TabContentBuilder"))
        XCTAssertTrue(viewType.contains("_TupleTabContent"))
        let bodyType = String(reflecting: type(of: view.body))
        XCTAssertTrue(bodyType.contains("ResolvedTabView"))
        XCTAssertTrue(bodyType.contains("TabViewStyleConfiguration"))
        XCTAssertTrue(bodyType.contains("StaticSourceWriter"))
    }

    // ASSERTIONS: tabSurfaceOwner27Observed
    func testNoSelectionCustomLabelConditionalAndStyleSurfaceTypeCheck() {
        let custom = Tab(value: 7) {
            Text("Seven Content")
        } label: {
            Label("Seven", systemImage: "7.circle")
        }
        XCTAssertEqual(custom._value, 7)

        let condition = true
        let view = TabView(selection: Binding.constant(7)) {
            if condition {
                custom
            } else {
                Tab("Eight", systemImage: "8.circle", value: 8) {
                    Text("Eight Content")
                }
            }
        }
        _ = view.tabViewStyle(.automatic)
        _ = view.tabViewStyle(.grouped)
        _ = view.tabViewStyle(.sidebarAdaptable)
        _ = view.tabViewStyle(.tabBarOnly)

        let unselected = TabView {
            Tab("First", systemImage: "1.circle") {
                Text("First Content")
            }
            Tab("Second", systemImage: "2.circle") {
                Text("Second Content")
            }
        }
        XCTAssertNil(unselected.selection)
    }

    // ASSERTIONS: tabSurfaceOwner27Observed
    func testGroupForEachAndOptionalSelectionValueTypeCheck() {
        let values = [1, 2]
        let grouped = TabView(selection: Binding<Int?>.constant(1)) {
            Group {
                ForEach(values, id: \.self) { value in
                    Tab(value: value) {
                        Text("Content \(value)")
                    } label: {
                        Text("Tab \(value)")
                    }
                }
            }
        }

        XCTAssertEqual(grouped.selection?.wrappedValue, 1)
        XCTAssertTrue(
            String(reflecting: type(of: grouped)).contains("TabContentBuilder")
        )
    }

    // ASSERTIONS: tabSurfaceOwner27Observed
    func testCustomTabViewStyleReceivesRuntimeDispatch() {
        let recorder = TabStyleInvocationRecorder()
        let root = TabView(selection: Binding.constant(1)) {
            Tab("First", systemImage: "1.circle", value: 1) {
                Text("First")
            }
        }
        .tabViewStyle(RecordingTabViewStyle(recorder: recorder))
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: type(of: root),
            content: root,
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        viewGraph.setSize(CGSize(width: 200, height: 120))
        viewGraph.updateOutputs(at: .zero)

        XCTAssertEqual(recorder.makeViewCount, 1)
    }

    // ASSERTIONS: tabSelectionPublicControl27Observed
    // ASSERTIONS: tabContentLifetime27Observed
    func testSelectionProjectionWritesOnlyTaggedValues() {
        var selection = 1
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )
        let projection = TabSelectionProjection(binding: binding)

        XCTAssertTrue(projection.isSelected(1))
        XCTAssertFalse(projection.isSelected(2))
        projection.select(2)
        XCTAssertEqual(selection, 2)
        projection.select(nil)
        XCTAssertEqual(selection, 2)
    }

    // ASSERTIONS: tabSelectionPublicControl27Observed
    @MainActor
    func testWindowPointerSelectsTaggedTab() {
        let store = TabSelectionStore(selection: 1)
        let controller = WindowController(
            content: TabSelectionRoutingRoot(store: store),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TabSelectionRoutingRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw
        ) { _, _ in }

        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: CGPoint(x: 150, y: 16),
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: CGPoint(x: 150, y: 16),
            timestamp: 0.01
        )))

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertEqual(store.selection, 2)
    }

    // ASSERTIONS: tabUnboundSelectionOwner27Observed
    // ASSERTIONS: tabUnboundContentLifetime27Observed
    @MainActor
    func testUnboundWindowPointerSwitchesTabsAndRetainsState() {
        let probe = TabLifecycleProbe()
        let controller = WindowController(
            content: TabUnboundRoutingRoot(probe: probe),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(TabUnboundRoutingRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw
        ) { _, _ in }
        XCTAssertEqual(probe.events, ["first-appear-1"])

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 150, y: 16)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        controller.updateView(
            tick: 1,
            delta: 0.03,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw
        ) { _, _ in }
        XCTAssertEqual(
            probe.events,
            ["first-appear-1", "first-disappear", "second-appear-1"]
        )

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 50, y: 16)))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        controller.updateView(
            tick: 2,
            delta: 0.03,
            date: controller.date,
            contentSize: CGSize(width: 200, height: 120),
            redraw: &redraw
        ) { _, _ in }
        XCTAssertEqual(
            probe.events,
            [
                "first-appear-1",
                "first-disappear",
                "second-appear-1",
                "second-disappear",
                "first-appear-2",
            ]
        )
    }

    @MainActor
    private func pointerClick(
        _ controller: WindowController,
        at location: CGPoint
    ) -> Bool {
        let down = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: location,
            timestamp: 0
        ))
        let up = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: location,
            timestamp: 0.01
        ))
        return down && up
    }

    // ASSERTIONS: tabInvalidSelection27Observed
    // ASSERTIONS: tabContentLifetime27Observed
    func testRendererFallsBackWithoutWritingAndRetainsTabState() throws {
        let probe = TabLifecycleProbe()
        let content = TabLifecycleHost(probe: probe)
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(
            rootViewType: TabLifecycleHost.self,
            content: content,
            rendererHost: rendererHost,
            requestedOutputs: []
        )
        rendererHost.storage = viewGraph
        viewGraph.setSize(CGSize(width: 480, height: 320))
        viewGraph.instantiateIfNeeded()

        viewGraph.updateOutputs(at: .zero)

        let selection = try XCTUnwrap(probe.selection)
        XCTAssertEqual(selection.wrappedValue, 99)
        XCTAssertEqual(probe.events, ["first-appear-1"])
        let firstCounter = try XCTUnwrap(probe.firstCounter)
        firstCounter.wrappedValue = 41
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))

        selection.wrappedValue = 2
        XCTAssertEqual(selection.wrappedValue, 2)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        viewGraph.updateOutputs(at: Time(seconds: 1))
        XCTAssertEqual(
            probe.events,
            ["first-appear-1", "first-disappear", "second-appear-1"]
        )

        selection.wrappedValue = 1
        XCTAssertEqual(selection.wrappedValue, 1)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        viewGraph.updateOutputs(at: Time(seconds: 2))
        XCTAssertEqual(
            probe.events,
            [
                "first-appear-1",
                "first-disappear",
                "second-appear-1",
                "second-disappear",
                "first-appear-2",
            ]
        )
        XCTAssertEqual(try XCTUnwrap(probe.firstCounter).wrappedValue, 41)
    }
}

private final class TabSelectionStore: @unchecked Sendable {
    var selection: Int

    init(selection: Int) {
        self.selection = selection
    }
}

private final class TabStyleInvocationRecorder: @unchecked Sendable {
    var makeViewCount = 0
}

private struct RecordingTabViewStyle: TabViewStyle {
    let recorder: TabStyleInvocationRecorder

    static func _makeView<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("RecordingTabViewStyle requires an active graph.")
        }
        value[\.style]._attribute.value.recorder.makeViewCount += 1
        let empty = graph.makeInput(value: EmptyView())
        return EmptyView._makeView(
            view: _GraphValue(_attribute: empty),
            inputs: inputs
        )
    }

    static func _makeViewList<SelectionValue>(
        value: _GraphValue<_TabViewValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        value[\.style]._attribute.value.recorder.makeViewCount += 1
        return EmptyView._makeViewList(
            view: _GraphValue(_attribute: Attribute(value: EmptyView())),
            inputs: inputs
        )
    }
}

private struct TabSelectionRoutingRoot: View {
    let store: TabSelectionStore

    var body: some View {
        TabView(selection: Binding(
            get: { store.selection },
            set: { store.selection = $0 }
        )) {
            Tab(value: 1) {
                Text("First content")
                    .frame(width: 200, height: 70)
            } label: {
                Text("First")
                    .frame(width: 80, height: 24)
            }
            Tab(value: 2) {
                Text("Second content")
                    .frame(width: 200, height: 70)
            } label: {
                Text("Second")
                    .frame(width: 80, height: 24)
            }
        }
    }
}

private struct TabUnboundRoutingRoot: View {
    let probe: TabLifecycleProbe

    var body: some View {
        TabView {
            Tab {
                TabLifecycleContent(name: "first", probe: probe)
                    .frame(width: 200, height: 70)
            } label: {
                Text("First")
                    .frame(width: 80, height: 24)
            }
            Tab {
                TabLifecycleContent(name: "second", probe: probe)
                    .frame(width: 200, height: 70)
            } label: {
                Text("Second")
                    .frame(width: 80, height: 24)
            }
        }
    }
}

private final class TabLifecycleProbe {
    var selection: Binding<Int>?
    var firstCounter: Binding<Int>?
    var secondCounter: Binding<Int>?
    var appearanceCounts: [String: Int] = [:]
    var events: [String] = []
}

private struct TabLifecycleHost: View {
    let probe: TabLifecycleProbe
    @State private var selection = 99

    var body: some View {
        let _ = probe.selection = $selection
        TabView(selection: $selection) {
            Tab("First", systemImage: "1.circle", value: 1) {
                TabLifecycleContent(name: "first", probe: probe)
            }
            Tab("Second", systemImage: "2.circle", value: 2) {
                TabLifecycleContent(name: "second", probe: probe)
            }
        }
    }
}

private struct TabLifecycleContent: View {
    let name: String
    let probe: TabLifecycleProbe
    @State private var retainedCounter = 0

    var body: some View {
        let _ = {
            if name == "first" {
                probe.firstCounter = $retainedCounter
            } else {
                probe.secondCounter = $retainedCounter
            }
        }()
        Text(name)
            .onAppear {
                let nextCount = (probe.appearanceCounts[name] ?? 0) + 1
                probe.appearanceCounts[name] = nextCount
                probe.events.append("\(name)-appear-\(nextCount)")
            }
            .onDisappear {
                probe.events.append("\(name)-disappear")
            }
    }
}
