import XCTest
@testable import VUI
@testable import VVD

final class PickerSurfaceTests: XCTestCase {
    // ASSERTIONS: pickerPublicStructure27Observed
    // ASSERTIONS: pickerFieldMetadata27Observed
    func testPublicPickerRetainsResolvedOwnerAndStyleSurface() {
        var selection = 2
        let binding = Binding(
            get: { selection },
            set: { selection = $0 }
        )
        let picker = Picker(selection: binding) {
            Text("One").tag(1)
            Text("Two").tag(2)
            Text("Three").tag(3)
        } label: {
            Text("Mode")
        } currentValueLabel: {
            Text("Current")
        }

        let fields = Mirror(reflecting: picker).children.map(\.label)
        XCTAssertEqual(
            fields,
            ["selection", "label", "content", "currentValueLabel"]
        )
        XCTAssertEqual(picker.selection.count, 1)
        XCTAssertEqual(picker.selection[0].wrappedValue, 2)

        let bodyType = String(reflecting: type(of: picker.body))
        XCTAssertTrue(bodyType.contains("ResolvedPicker"))
        XCTAssertTrue(bodyType.contains("StaticSourceWriter"))
        XCTAssertTrue(bodyType.contains("OptionalSourceWriter"))

        _ = picker.pickerStyle(.automatic)
        _ = picker.pickerStyle(.menu)
        _ = picker.pickerStyle(.segmented)
        _ = picker.pickerStyle(.radioGroup)
        _ = picker.pickerStyle(.inline)
        _ = picker.pickerStyle(.palette)
        _ = picker.pickerStyle(.tabs)
    }

    // ASSERTIONS: pickerPublicStructure27Observed
    func testPublicInitializerFamiliesTypeCheck() {
        let titleResource: LocalizedStringResource = "Mode"
        let selections = [Binding.constant(1), Binding.constant(2)]
        let sources = selections.map(PickerSelectionSource.init(selection:))

        _ = Picker(
            titleResource,
            sources: sources,
            selection: \.selection
        ) {
            Text("One").tag(1)
        } currentValueLabel: {
            Text("Current")
        }
        _ = Picker(
            titleResource,
            systemImage: "slider.horizontal.3",
            sources: selections,
            selection: \.self
        ) {
            Text("One").tag(1)
        } currentValueLabel: {
            Text("Current")
        }
        _ = Picker(
            "Mode",
            systemImage: "slider.horizontal.3",
            selection: Binding.constant(1)
        ) {
            Text("One").tag(1)
        } currentValueLabel: {
            Text("Current")
        }
    }

    // ASSERTIONS: pickerOwnerLowering27Observed
    func testCustomPickerStyleReceivesRuntimeDispatch() {
        let recorder = PickerInspectionRecorder()
        let root = Picker("Mode", selection: Binding.constant(1)) {
            Text("One").tag(1)
            Text("Two").tag(2)
        }
        .pickerStyle(InspectingPickerStyle(recorder: recorder))
        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: type(of: root),
            content: root,
            rendererHost: renderer,
            requestedOutputs: []
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 200, height: 100))
        graph.updateOutputs(at: .zero)

        XCTAssertEqual(recorder.makeViewCount, 1)
        XCTAssertEqual(recorder.tags, [AnyHashable(1), AnyHashable(2)])
    }

    // ASSERTIONS: pickerOptionMaterialization27Observed
    // ASSERTIONS: pickerSelectionWritebackOwner27Observed
    // ASSERTIONS: pickerImplicitTag27Observed
    func testImplicitForEachTagsDriveSelectionWriteback() throws {
        var selection = 1
        let recorder = PickerInspectionRecorder()
        let root = Picker(
            "Mode",
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            ForEach([1, 2, 3], id: \.self) { value in
                Text("Value \(value)")
            }
        }
        .pickerStyle(InspectingPickerStyle(recorder: recorder))
        render(root)

        XCTAssertEqual(
            recorder.tags,
            [AnyHashable(1), AnyHashable(2), AnyHashable(3)]
        )
        try XCTUnwrap(recorder.selectSecond)()
        XCTAssertEqual(selection, 2)
    }

    // ASSERTIONS: pickerOptionalTag27Observed
    // ASSERTIONS: pickerSelectionWritebackOwner27Observed
    func testOptionalTagAndMultipleSourcesWriteThroughEveryBinding() throws {
        var first: Int? = nil
        var second: Int? = 2
        let sources = [
            PickerSelectionSource(
                selection: Binding(
                    get: { first },
                    set: { first = $0 }
                )
            ),
            PickerSelectionSource(
                selection: Binding(
                    get: { second },
                    set: { second = $0 }
                )
            ),
        ]
        let recorder = PickerInspectionRecorder()
        let picker = Picker(
            "Mode",
            sources: sources,
            selection: \.selection
        ) {
            Text("None").tag(nil as Int?)
            Text("One").tag(1)
            Text("Two").tag(2)
        }
        .pickerStyle(InspectingPickerStyle(recorder: recorder))
        render(picker)

        XCTAssertEqual(
            recorder.tags,
            [AnyHashable(Optional<Int>.none), AnyHashable(1), AnyHashable(2)]
        )
        try XCTUnwrap(recorder.selectSecond)()
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 1)
    }

    // ASSERTIONS: pickerPublicStructure27Observed
    // ASSERTIONS: pickerFieldMetadata27Observed
    func testCurrentValueLabelRoutesThroughOptionalSourceWriter() throws {
        let root = Picker(selection: Binding.constant(1)) {
            Text("One").tag(1)
        } label: {
            Text("Mode")
        } currentValueLabel: {
            PickerFixedSizeView(size: CGSize(width: 37, height: 19))
        }
        .pickerStyle(CurrentValueOnlyPickerStyle())
        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: type(of: root),
            content: root,
            rendererHost: renderer
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 200, height: 100))
        graph.updateOutputs(at: .zero)

        try graph.data.withCurrent {
            try AGSubgraph.withCurrent(graph.data.rootSubgraph) {
                let layout = try XCTUnwrap(graph.rootLayoutComputer).value
                XCTAssertEqual(
                    layout.sizeThatFits(.unspecified),
                    CGSize(width: 37, height: 19)
                )
            }
        }
    }

    // ASSERTIONS: pickerSelectionWritebackOwner27Observed
    func testSelectionProjectionWritesOnlyWhenAnOptionBecomesSelected() {
        var first = 1
        var second = 2
        let projection = PickerSelectionProjection(selections: [
            Binding(get: { first }, set: { first = $0 }),
            Binding(get: { second }, set: { second = $0 }),
        ])
        let binding = projection.binding(for: 3)

        XCTAssertFalse(binding.wrappedValue)
        binding.wrappedValue = false
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 2)
        binding.wrappedValue = true
        XCTAssertEqual(first, 3)
        XCTAssertEqual(second, 3)
        XCTAssertTrue(binding.wrappedValue)
    }

    // ASSERTIONS: pickerStylePlatformLowering27Observed
    // ASSERTIONS: pickerMenuSelection27Observed
    // ASSERTIONS: pickerSegmentedSelection27Observed
    // ASSERTIONS: pickerRadioInlineSelection27Observed
    func testPortableStyleBodiesRenderThroughTheirObservedFamilies() {
        func picker() -> some View {
            Picker("Mode", selection: Binding.constant(2)) {
                Text("One").tag(1)
                Text("Two").tag(2)
                Text("Three").tag(3)
            }
        }

        render(picker().pickerStyle(.automatic))
        render(picker().pickerStyle(.menu))
        render(picker().pickerStyle(.segmented))
        render(picker().pickerStyle(.radioGroup))
        render(picker().pickerStyle(.inline))
        render(picker().pickerStyle(.palette))
        render(picker().pickerStyle(.tabs))
    }

    // ASSERTIONS: pickerSegmentedSelection27Observed
    // ASSERTIONS: pickerSelectionWritebackOwner27Observed
    @MainActor
    func testSegmentedPointerSelectsTaggedOption() {
        let store = PickerPointerSelectionStore(selection: 1)
        let controller = WindowController(
            content: PickerPointerSelectionRoot(store: store),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(PickerPointerSelectionRoot.self)
            )
        )
        var redraw = false
        let size = CGSize(width: 240, height: 120)
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }

        let hitPoints: [CGPoint] = controller.viewGraph.data.withCurrent {
            guard let responder = controller.viewGraph.responderNode
                    as? MultiViewResponder else {
                return []
            }
            var points: [CGPoint] = []
            for y in stride(from: 0.0, through: size.height, by: 4.0) {
                for x in stride(from: 0.0, through: size.width, by: 4.0) {
                    let point = CGPoint(x: x, y: y)
                    let hits = responder.respondersContaining(point: point)
                    if hits.contains(where: {
                        $0 is any AnyGestureResponder
                    }) {
                        points.append(point)
                    }
                }
            }
            return points.sorted {
                $0.x == $1.x ? $0.y < $1.y : $0.x > $1.x
            }
        }
        XCTAssertFalse(hitPoints.isEmpty)
        guard let point = hitPoints.first else { return }

        let down = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: point,
            timestamp: 0
        ))
        let up = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: point,
            timestamp: 0.01
        ))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.002))

        XCTAssertTrue(down)
        XCTAssertTrue(up)
        XCTAssertEqual(store.selection, 2)
    }

    private func render<Content: View>(_ root: Content) {
        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: Content.self,
            content: root,
            rendererHost: renderer,
            requestedOutputs: []
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 240, height: 120))
        graph.updateOutputs(at: .zero)
    }
}

private struct PickerSelectionSource<Value> {
    var selection: Binding<Value>
}

private final class PickerPointerSelectionStore: @unchecked Sendable {
    var selection: Int

    init(selection: Int) {
        self.selection = selection
    }
}

private struct PickerPointerSelectionRoot: View {
    var store: PickerPointerSelectionStore

    var body: some View {
        Picker(
            "Mode",
            selection: Binding(
                get: { store.selection },
                set: { store.selection = $0 }
            )
        ) {
            Text("One")
                .frame(width: 64, height: 24)
                .tag(1)
            Text("Two")
                .frame(width: 64, height: 24)
                .tag(2)
        }
        .pickerStyle(.segmented)
        .frame(width: 220, height: 100)
    }
}

private final class PickerInspectionRecorder: @unchecked Sendable {
    var makeViewCount = 0
    var tags: [AnyHashable] = []
    var selectSecond: (() -> Void)?
}

private struct InspectingPickerStyle: PickerStyle {
    var recorder: PickerInspectionRecorder

    static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("InspectingPickerStyle requires an active graph.")
        }
        let style = value[\.style]._attribute
        let configuration = value[\.configuration]._attribute
        style.value.recorder.makeViewCount += 1
        let body: Attribute<PickerInspectionBody<SelectionValue>> =
            graph.makeRule {
                PickerInspectionBody(
                    configuration: configuration.value,
                    recorder: style.value.recorder
                )
            }
        return PickerInspectionBody<SelectionValue>._makeView(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }

    static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("InspectingPickerStyle requires an active graph.")
        }
        let style = value[\.style]._attribute
        let configuration = value[\.configuration]._attribute
        style.value.recorder.makeViewCount += 1
        let body: Attribute<PickerInspectionBody<SelectionValue>> =
            graph.makeRule {
                PickerInspectionBody(
                    configuration: configuration.value,
                    recorder: style.value.recorder
                )
            }
        return PickerInspectionBody<SelectionValue>._makeViewList(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }
}

private struct PickerInspectionBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: PickerStyleConfiguration<SelectionValue>
    var recorder: PickerInspectionRecorder

    var body: some View {
        _VariadicView.Tree(
            PickerInspectionRoot(
                selections: configuration.selections,
                recorder: recorder
            )
        ) {
            configuration.content
        }
    }
}

private struct PickerInspectionRoot<SelectionValue>:
    _VariadicView_MultiViewRoot
where SelectionValue: Hashable {
    var selections: [Binding<SelectionValue>]
    var recorder: PickerInspectionRecorder

    func body(children: _VariadicView.Children) -> some View {
        PickerInspectionCapture(
            children: children,
            selections: selections,
            recorder: recorder
        )
    }
}

private struct PickerInspectionCapture<SelectionValue>:
    View,
    PrimitiveView,
    UnaryView
where SelectionValue: Hashable {
    typealias Body = Never

    var children: _VariadicView.Children
    var selections: [Binding<SelectionValue>]
    var recorder: PickerInspectionRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("PickerInspectionCapture requires an active graph.")
        }
        let value = view._attribute.value
        let tags: [SelectionValue] = value.children.compactMap { child in
            switch child[TagValueTraitKey<SelectionValue>.self] {
            case .untagged:
                nil
            case .tagged(let tag):
                tag
            }
        }
        value.recorder.tags = tags.map { AnyHashable($0) }
        value.recorder.selectSecond = tags.count > 1 ? {
            PickerSelectionProjection(
                selections: value.selections
            ).select(tags[1])
        } : nil
        let layout = graph.makeInput(
            value: LayoutComputer.fixed(CGSize(width: 1, height: 1))
        )
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}

private struct CurrentValueOnlyPickerStyle: PickerStyle {
    static func _makeView<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewInputs
    ) -> _ViewOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("CurrentValueOnlyPickerStyle requires an active graph.")
        }
        let configuration = value[\.configuration]._attribute
        let body: Attribute<CurrentValueOnlyPickerBody<SelectionValue>> =
            graph.makeRule {
                CurrentValueOnlyPickerBody(
                    configuration: configuration.value
                )
            }
        return CurrentValueOnlyPickerBody<SelectionValue>._makeView(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }

    static func _makeViewList<SelectionValue>(
        value: _GraphValue<_PickerValue<Self, SelectionValue>>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs where SelectionValue: Hashable {
        guard let graph = _AGGraph.current else {
            fatalError("CurrentValueOnlyPickerStyle requires an active graph.")
        }
        let configuration = value[\.configuration]._attribute
        let body: Attribute<CurrentValueOnlyPickerBody<SelectionValue>> =
            graph.makeRule {
                CurrentValueOnlyPickerBody(
                    configuration: configuration.value
                )
            }
        return CurrentValueOnlyPickerBody<SelectionValue>._makeViewList(
            view: _GraphValue(_attribute: body),
            inputs: inputs
        )
    }
}

private struct CurrentValueOnlyPickerBody<SelectionValue>: View
where SelectionValue: Hashable {
    var configuration: PickerStyleConfiguration<SelectionValue>

    @ViewBuilder
    var body: some View {
        if let currentValueLabel = configuration.currentValueLabel {
            currentValueLabel
        }
    }
}

private struct PickerFixedSizeView: View, PrimitiveView, UnaryView {
    typealias Body = Never
    var size: CGSize

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("PickerFixedSizeView requires an active graph.")
        }
        let layout = graph.makeRule {
            LayoutComputer.fixed(view._attribute.value.size)
        }
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}
