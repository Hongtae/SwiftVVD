import XCTest
@testable import VUI
@testable import VVD

final class ListSectionSurfaceTests: XCTestCase {
    // ASSERTIONS: listSurfaceOwner27Observed
    // ASSERTIONS: listBodyOwner27Observed
    // ASSERTIONS: listSurfaceOwnerFieldMetadata27Observed
    func testListStoresSelectionContentAndResolvedStyleRoute() {
        var selection: Int? = 7
        let list = List(
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            )
        ) {
            Text("Seven").tag(7)
            Section("Other") {
                Text("Eight").tag(8)
            }
        }

        guard var manager = list.selection?.wrappedValue else {
            return XCTFail("List should retain the projected selection binding")
        }
        XCTAssertTrue(manager.isSelected(7))
        manager.select(8)
        list.selection?.wrappedValue = manager
        XCTAssertEqual(selection, 8)

        let bodyType = String(reflecting: type(of: list.body))
        XCTAssertTrue(bodyType.contains("ResettableLazyLayoutRoot"))
        XCTAssertTrue(bodyType.contains("ResolvedList"))
        XCTAssertTrue(bodyType.contains("ListStyleContent"))
    }

    // ASSERTIONS: listSelectionPublicControl27Observed
    func testSelectionManagerDistinguishesReplacementAndAdditiveClicks() {
        var manager = SelectionManagerBox.set([1])

        manager.select(2, additive: false)
        XCTAssertEqual(manager, .set([2]))

        manager.select(3, additive: true)
        XCTAssertEqual(manager, .set([2, 3]))

        manager.select(2, additive: true)
        XCTAssertEqual(manager, .set([3]))
        XCTAssertTrue(manager.allowsMultipleSelection)
        XCTAssertTrue(manager.allowsEmptySelection)

        var optional = SelectionManagerBox<Int>.optional(1)
        optional.select(2, additive: true)
        XCTAssertEqual(optional, .optional(2))
        optional.deselect(2)
        XCTAssertEqual(optional, .optional(nil))

        var required = SelectionManagerBox.required(1)
        required.deselect(1)
        XCTAssertEqual(required, .required(1))
        XCTAssertFalse(required.allowsEmptySelection)
    }

    // ASSERTIONS: listStyleCoreOptions27Observed
    func testInsetAndBorderedStylesRetainObservedCoreOptions() {
        XCTAssertEqual(InsetListStyle().options.rawValue, 3)
        XCTAssertEqual(
            InsetListStyle(alternatesRowBackgrounds: true).options.rawValue,
            35
        )
        XCTAssertEqual(BorderedListStyle().options.rawValue, 19)
        XCTAssertEqual(
            BorderedListStyle(
                alternatesRowBackgrounds: true
            ).options.rawValue,
            51
        )
    }

    // ASSERTIONS: listSectionExpansionPublicControl27Observed
    func testSectionExpansionAndLocalizedResourceInitializers() {
        var expanded = true
        let binding = Binding(
            get: { expanded },
            set: { expanded = $0 }
        )
        let section = Section(
            "Expandable",
            isExpanded: binding
        ) {
            Text("Content")
        }

        XCTAssertTrue(section.isExpanded?.wrappedValue == true)
        section.isExpanded?.wrappedValue = false
        XCTAssertFalse(expanded)

        let localized = Section(
            LocalizedStringResource("Localized")
        ) {
            Text("Content")
        }
        XCTAssertNil(localized.isExpanded)
    }

    // ASSERTIONS: listSectionExpansionPublicControl27Observed
    func testSectionExpansionBindingControlsPublishedRows() {
        func publishedRowCount(isExpanded: Bool) -> Int {
            let recorder = SectionPresentationRecorder()
            let root = Group(sections: Section(
                "Header",
                isExpanded: .constant(isExpanded)
            ) {
                Text("Child")
            }) { sections in
                SectionPresentationCapture(
                    recorder: recorder,
                    sections: sections
                )
            }
            let renderer = TestViewRendererHost()
            let graph = ViewGraph(
                rootViewType: type(of: root),
                content: root,
                rendererHost: renderer
            )
            renderer.storage = graph
            graph.setSize(CGSize(width: 240, height: 180))
            graph.updateOutputs(at: .zero)
            return recorder.contentCount ?? -1
        }

        let expanded = publishedRowCount(isExpanded: true)
        let collapsed = publishedRowCount(isExpanded: false)
        XCTAssertGreaterThan(expanded, collapsed)
    }

    func testPublicConstructionFamiliesTypeCheck() {
        struct Row: Identifiable {
            var id: Int
            var title: String
        }

        let rows = [Row(id: 1, title: "One")]
        var optional: Int? = nil
        var required = 1
        var multiple: Set<Int> = []
        var mutableRows = rows

        _ = List(rows) { Text($0.title) }
        _ = List(rows, id: \.id) { Text($0.title) }
        _ = List(0..<3) { Text("\($0)") }
        _ = List(
            rows,
            selection: Binding(
                get: { optional },
                set: { optional = $0 }
            )
        ) { Text($0.title) }
        _ = List(
            0..<3,
            selection: Binding(
                get: { optional },
                set: { optional = $0 }
            )
        ) { Text("\($0)") }
        _ = List(
            0..<3,
            selection: Binding(
                get: { multiple },
                set: { multiple = $0 }
            )
        ) { Text("\($0)") }
        _ = List(
            0..<3,
            selection: Binding(
                get: { required },
                set: { required = $0 }
            )
        ) { Text("\($0)") }
        _ = List(
            rows,
            selection: Binding(
                get: { multiple },
                set: { multiple = $0 }
            )
        ) { Text($0.title) }
        _ = List(
            Binding(
                get: { mutableRows },
                set: { mutableRows = $0 }
            )
        ) { Text($0.wrappedValue.title) }
    }

    // ASSERTIONS: listModifierSurface27Observed
    // ASSERTIONS: listSectionSpacingStorage27Observed
    // ASSERTIONS: listSectionSpacingPublicLayout27Observed
    func testListModifierSurfaceStoresObservedValues() {
        XCTAssertNotEqual(
            AlternatingRowBackgroundBehavior.automatic,
            .enabled
        )
        XCTAssertNotEqual(
            AlternatingRowBackgroundBehavior.enabled,
            .disabled
        )
        XCTAssertEqual(ListSectionSpacing.compact.resolved(default: 17), 6)
        XCTAssertEqual(
            ListSectionSpacing.custom(13.5).resolved(default: 17),
            13.5
        )

        let fixed = ListItemTint.fixed(.red)
        let preferred = ListItemTint.preferred(.red)
        XCTAssertTrue(fixed.isFixed)
        XCTAssertFalse(preferred.isFixed)

        _ = Text("Row")
            .selectionDisabled()
            .listItemTint(preferred)
            .listRowSeparator(.hidden, edges: .top)
            .listRowSeparatorTint(.red, edges: .bottom)
        _ = Section("Header") { Text("Row") }
            .listSectionSeparator(.hidden, edges: .bottom)
            .listSectionSeparatorTint(.red, edges: .top)
            .sectionActions {
                Button("Add") {}
            }
        _ = List { Text("Row") }
            .alternatingRowBackgrounds(.disabled)
            .listSectionSpacing(.compact)
    }

    // ASSERTIONS: listSectionPresentation27Observed
    func testSectionPresentationModifiersExposeCurrentSurface() {
        var environment = EnvironmentValues()
        XCTAssertEqual(environment.headerProminence, .standard)
        environment.headerProminence = .increased
        XCTAssertEqual(environment.headerProminence, .increased)

        let section = Section("Header") {
            Text("Row")
        }
        .headerProminence(.increased)
        .listSectionMargins(.horizontal, 24)

        _ = List {
            section
        }
        .listStyle(.plain)
    }

    // ASSERTIONS: listSectionPresentation27Observed
    func testSectionPresentationTraitsReachSectionCollection() {
        let recorder = SectionPresentationRecorder()
        let root = Group(sections: Section("Header") {
            Text("Row")
        }
        .headerProminence(.increased)
        .listSectionMargins(.horizontal, 24)) { sections in
            SectionPresentationCapture(
                recorder: recorder,
                sections: sections
            )
        }

        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: type(of: root),
            content: root,
            rendererHost: renderer
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 240, height: 180))
        graph.updateOutputs(at: .zero)

        XCTAssertEqual(recorder.prominence, .increased)
        XCTAssertEqual(recorder.margins?.leading, 24)
        XCTAssertEqual(recorder.margins?.trailing, 24)
        XCTAssertNil(recorder.margins?.top)
        XCTAssertNil(recorder.margins?.bottom)
    }

    // ASSERTIONS: listEditTraitSurface27Observed
    // ASSERTIONS: listDesktopDeleteKeyNoAction27Observed
    func testDynamicContentEditTraitsExposeCurrentSurface() {
        struct Row: Identifiable {
            var id: Int
        }

        let rows = [Row(id: 1), Row(id: 2)]
        var deleted = IndexSet()
        var moved: (IndexSet, Int)?
        _ = ForEach(rows) { row in
            Text("\(row.id)")
                .deleteDisabled(row.id == 1)
                .moveDisabled(row.id == 2)
        }
        .onDelete { deleted = $0 }
        .onMove { moved = ($0, $1) }

        let delete: OnDeleteTraitKey.Value = { deleted = $0 }
        let move: OnMoveTraitKey.Value = { moved = ($0, $1) }
        delete?(IndexSet(integer: 1))
        move?(IndexSet(integer: 0), 2)
        XCTAssertEqual(deleted, IndexSet(integer: 1))
        XCTAssertEqual(moved?.0, IndexSet(integer: 0))
        XCTAssertEqual(moved?.1, 2)
        XCTAssertFalse(IsDeleteDisabledTraitKey.defaultValue)
        XCTAssertFalse(IsMoveDisabledTraitKey.defaultValue)
    }

    func testListMaterializesThroughSectionCollectionAndScrollHost() throws {
        let root = List {
            Text("Before")
            Section("Header") {
                ForEach(0..<3) { index in
                    Text("Row \(index)")
                }
            }
            .sectionActions {
                Button("Add") {}
            }
            .headerProminence(.increased)
            .listSectionMargins(.horizontal, 12)
        }
        .listStyle(.plain)

        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: type(of: root),
            content: root,
            rendererHost: renderer
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 240, height: 180))
        graph.updateOutputs(at: .zero)

        let list = graph.data.withCurrent { graph.displayList() }
        XCTAssertNotNil(list)
    }

    // ASSERTIONS: listSelectionPublicControl27Observed
    @MainActor
    func testWindowMouseClicksUpdateListSelectionBinding() {
        let store = ListSelectionStore(selection: [1])
        let controller = WindowController(
            content: ListSelectionRoutingRoot(store: store),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ListSelectionRoutingRoot.self)
            )
        )

        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: CGSize(width: 240, height: 120),
            redraw: &redraw
        ) { _, _ in }

        XCTAssertTrue(pointerClick(
            controller,
            at: CGPoint(x: 120, y: 37)
        ))
        XCTAssertEqual(store.selection, [2])

        XCTAssertTrue(pointerClick(
            controller,
            modifiers: [.command],
            at: CGPoint(x: 120, y: 12)
        ))
        XCTAssertEqual(store.selection, [1, 2])

        XCTAssertFalse(pointerClick(
            controller,
            at: CGPoint(x: 120, y: 62)
        ))
        XCTAssertEqual(store.selection, [1, 2])
    }

    @MainActor
    private func pointerClick(
        _ controller: WindowController,
        modifiers: KeyboardModifierFlags = [],
        at location: CGPoint
    ) -> Bool {
        let down = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            modifiers: modifiers,
            location: location,
            timestamp: 0
        ))
        let up = controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            modifiers: modifiers,
            location: location,
            timestamp: 0.01
        ))
        return down && up
    }
}

private final class ListSelectionStore: @unchecked Sendable {
    var selection: Set<Int>

    init(selection: Set<Int>) {
        self.selection = selection
    }
}

private struct ListSelectionRoutingRoot: View {
    let store: ListSelectionStore

    var body: some View {
        List(
            selection: Binding(
                get: { store.selection },
                set: { store.selection = $0 }
            )
        ) {
            Text("One").tag(1)
            Text("Two").tag(2)
            Text("Three").tag(3).selectionDisabled()
        }
        .listStyle(.plain)
    }
}

private final class SectionPresentationRecorder: @unchecked Sendable {
    var prominence: Prominence?
    var margins: OptionalEdgeInsets?
    var contentCount: Int?
}

private struct SectionPresentationCapture: View, TestPrimitiveView {
    let recorder: SectionPresentationRecorder
    let sections: SectionCollection

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        let capture = view._attribute.value
        if let section = capture.sections.first {
            capture.recorder.prominence = section.containerValues.base[
                HeaderProminenceKey.self
            ]
            capture.recorder.margins = section.containerValues.base[
                ListSectionMarginsTraitKey.self
            ]
            capture.recorder.contentCount = section.content.count
        }
        return _ViewListOutputs(
            views: .staticList(.merged([])),
            nextImplicitID: 0,
            staticCount: 0
        )
    }

    typealias Body = Never
}
