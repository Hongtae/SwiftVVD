import Foundation
import XCTest
@testable import VUI
@testable import VVD

final class TableSurfaceTests: XCTestCase {
    private struct Row: Identifiable {
        var id: Int
        var name: String
        var score: Int
    }

    private let rows = [
        Row(id: 1, name: "One", score: 10),
        Row(id: 2, name: "Two", score: 20),
        Row(id: 3, name: "Three", score: 30),
    ]

    private final class SelectionStore: @unchecked Sendable {
        var rows: [Row]
        var selection: Int?
        var writes: [Int?] = []

        init(rows: [Row], selection: Int? = nil) {
            self.rows = rows
            self.selection = selection
        }
    }

    private struct SelectionRoot: View {
        var store: SelectionStore

        var body: some View {
            Table(
                store.rows,
                selection: Binding(
                    get: { store.selection },
                    set: {
                        store.selection = $0
                        store.writes.append($0)
                    }
                )
            ) {
                TableColumn("Name") { row in
                    Text(row.name)
                }
            }
        }
    }

    private final class SortStore: @unchecked Sendable {
        var rows: [Row]
        var sortOrder: [KeyPathComparator<Row>] = []
        var writes: [[SortOrder]] = []

        init(rows: [Row]) {
            self.rows = rows
        }
    }

    private struct SortRoot: View {
        var store: SortStore

        var body: some View {
            Table(
                store.rows,
                sortOrder: Binding(
                    get: { store.sortOrder },
                    set: {
                        store.sortOrder = $0
                        store.writes.append($0.map(\.order))
                    }
                )
            ) {
                TableColumn("Name", value: \.name)
            }
        }
    }

    private struct WidthRoot: View {
        var store: SortStore

        var body: some View {
            Table(
                store.rows,
                sortOrder: Binding(
                    get: { store.sortOrder },
                    set: { store.sortOrder = $0 }
                )
            ) {
                TableColumn("Name", value: \.name)
                    .width(min: 90, ideal: 120, max: 180)
                TableColumn("Score", value: \.score) { row in
                    Text("\(row.score)")
                }
                .width(75)
            }
        }
    }

    // ASSERTIONS: tablePublicStructure27Observed
    // ASSERTIONS: tableFieldMetadata27Observed
    // ASSERTIONS: tableColumnSizing27Observed
    func testDataTableRetainsObservedOwnersAndColumnSizing() {
        var selection: Int? = 1
        var sortOrder: [KeyPathComparator<Row>] = []
        let table = Table(
            rows,
            selection: Binding(
                get: { selection },
                set: { selection = $0 }
            ),
            sortOrder: Binding(
                get: { sortOrder },
                set: { sortOrder = $0 }
            )
        ) {
            TableColumn("Name", value: \.name)
                .width(min: 90, ideal: 120, max: 180)
            TableColumn("Score", value: \.score) { row in
                Text("\(row.score)")
            }
            .width(75)
        }

        XCTAssertEqual(
            Mirror(reflecting: table).children.map(\.label),
            [
                "columns",
                "rows",
                "selection",
                "sortOrder",
                "columnCustomization",
            ]
        )
        XCTAssertEqual(
            Mirror(reflecting: table.columns).children.map(\.label),
            ["value"]
        )
        XCTAssertEqual(
            Mirror(reflecting: table.rows).children.map(\.label),
            ["data"]
        )

        let constrained = TableColumn<Row, Never, Text, Text>("Name") {
            Text($0.name)
        }
        .width(min: 90, ideal: 120, max: 180)
        XCTAssertEqual(constrained.sizingBehavior.constraints?.min, 90)
        XCTAssertEqual(constrained.sizingBehavior.constraints?.ideal, 120)
        XCTAssertEqual(constrained.sizingBehavior.constraints?.max, 180)

        let fixed = TableColumn<Row, Never, Text, Text>("Score") {
            Text("\($0.score)")
        }
        .width(75)
        XCTAssertEqual(fixed.sizingBehavior.constraints?.min, 75)
        XCTAssertEqual(fixed.sizingBehavior.constraints?.ideal, 75)
        XCTAssertEqual(fixed.sizingBehavior.constraints?.max, 75)
    }

    // ASSERTIONS: tableSelectionSortControl27Observed
    func testErasedSelectionAndSortBindingsWriteBackOnce() throws {
        var selection: Int? = 1
        var selectionWrites: [Int?] = []
        var sortOrder: [KeyPathComparator<Row>] = []
        var sortWrites: [[SortOrder]] = []
        let table = Table(
            rows,
            selection: Binding(
                get: { selection },
                set: {
                    selection = $0
                    selectionWrites.append($0)
                }
            ),
            sortOrder: Binding(
                get: { sortOrder },
                set: {
                    sortOrder = $0
                    sortWrites.append($0.map(\.order))
                }
            )
        ) {
            TableColumn("Name", value: \.name)
        }

        var manager = try XCTUnwrap(table.selection?.wrappedValue)
        manager.select(AnyHashable(2), additive: false)
        table.selection?.wrappedValue = manager
        XCTAssertEqual(selection, 2)
        XCTAssertEqual(selectionWrites, [2])

        let column = TableColumn<Row, KeyPathComparator<Row>, Text, Text>(
            "Name",
            value: \.name
        )
        let comparator = try XCTUnwrap(column.comparator)
        table.sortOrder?.wrappedValue = [comparator]
        XCTAssertEqual(sortOrder.count, 1)
        XCTAssertEqual(sortOrder[0].order, .forward)
        XCTAssertEqual(sortWrites, [[.forward]])
    }

    // ASSERTIONS: tableSelectionSortControl27Observed
    @MainActor
    func testMountedPointerWritesSelectionAndSortOnce() throws {
        let size = CGSize(width: 320, height: 180)
        let selectionStore = SelectionStore(rows: rows)
        let selectionController = WindowController(
            content: SelectionRoot(store: selectionStore),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(SelectionRoot.self)
            )
        )
        mount(selectionController, size: size)

        let selectionPoint = try XCTUnwrap(
            firstSingleTapPoint(in: selectionController, size: size)
        )
        XCTAssertTrue(pointerClick(selectionController, at: selectionPoint))
        Update.dispatchActions()
        XCTAssertNotNil(selectionStore.selection)
        XCTAssertEqual(selectionStore.writes.count, 1)

        let sortStore = SortStore(rows: rows)
        let sortController = WindowController(
            content: SortRoot(store: sortStore),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(SortRoot.self)
            )
        )
        mount(sortController, size: size)

        let sortPoint = try XCTUnwrap(
            firstSingleTapPoint(in: sortController, size: size)
        )
        XCTAssertTrue(pointerClick(sortController, at: sortPoint))
        Update.dispatchActions()
        XCTAssertEqual(sortStore.sortOrder.count, 1)
        XCTAssertEqual(sortStore.sortOrder[0].order, .forward)
        XCTAssertEqual(sortStore.writes, [[.forward]])
    }

    // ASSERTIONS: tableColumnSizing27Observed
    @MainActor
    func testMountedColumnWidthsRespectFixedAndConstrainedSizing() throws {
        let size = CGSize(width: 480, height: 260)
        let store = SortStore(rows: rows)
        let controller = WindowController(
            content: WidthRoot(store: store),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(WidthRoot.self)
            )
        )
        mount(controller, size: size)

        let ranges = try XCTUnwrap(
            firstSingleTapHorizontalRanges(in: controller, size: size)
        )
        XCTAssertEqual(ranges.count, 2)
        XCTAssertEqual(ranges[0].upperBound - ranges[0].lowerBound + 1, 180)
        XCTAssertEqual(ranges[1].upperBound - ranges[1].lowerBound + 1, 75)
    }

    // ASSERTIONS: tablePublicStructure27Observed
    func testExplicitRowsAndStyleSurfaceTypeCheck() {
        var sortOrder: [KeyPathComparator<Row>] = []
        let table = Table(of: Row.self) {
            TableColumn("Name") { row in
                Text(row.name)
            }
        } rows: {
            TableRow(rows[0])
            TableRow(rows[1])
        }

        let sortedTable = Table(
            sortOrder: Binding(
                get: { sortOrder },
                set: { sortOrder = $0 }
            )
        ) {
            TableColumn("Name", value: \.name)
        } rows: {
            TableRow(rows[0])
            TableRow(rows[1])
        }

        XCTAssertEqual(
            Mirror(reflecting: table.rows).children.map(\.label),
            ["value"]
        )
        XCTAssertNotNil(sortedTable.sortOrder)
        _ = table.tableStyle(.automatic)
        _ = table.tableStyle(.inset)
        _ = table.tableStyle(.bordered)
        _ = table.tableColumnHeaders(.hidden)
    }

    // ASSERTIONS: tableOwnerLowering27Observed
    func testDataTableMaterializesACommonDisplayList() {
        let table = Table(rows) {
            TableColumn("Name") { row in
                Text(row.name)
            }
            TableColumn("Score") { row in
                Text("\(row.score)")
            }
        }
        .frame(width: 320, height: 180)

        let renderer = TestViewRendererHost()
        let graph = ViewGraph(
            rootViewType: type(of: table),
            content: table,
            rendererHost: renderer
        )
        renderer.storage = graph
        graph.setSize(CGSize(width: 320, height: 180))
        graph.updateOutputs(at: .zero)

        XCTAssertNotNil(graph.data.withCurrent { graph.displayList() })
    }

    // ASSERTIONS: tablePublicStructure27Observed
    // ASSERTIONS: tableFieldMetadata27Observed
    func testBuildersComposeConditionalGroupedAndTenElementContent() throws {
        let includeScore = true
        let grouped = Table(of: Row.self) {
            Group {
                TableColumn("Name") { (row: Row) in
                    Text(row.name)
                }
                if includeScore {
                    TableColumn("Score") { (row: Row) in
                        Text("\(row.score)")
                    }
                }
            }
        } rows: {
            TableRow(rows[0])
            if includeScore {
                TableRow(rows[1])
            }
            ForEach([rows[2]]) { row in
                TableRow(row)
            }
        }

        let groupedColumns: any TableColumnContentMaterializing =
            grouped.columns
        let groupedRows: any TableRowContentMaterializing = grouped.rows
        XCTAssertEqual(groupedColumns.materializeTableColumns().count, 2)
        XCTAssertEqual(groupedRows.materializeTableRows().count, 3)

        let tenColumns = Table(rows) {
            TableColumn("0") { Text($0.name) }
            TableColumn("1") { Text($0.name) }
            TableColumn("2") { Text($0.name) }
            TableColumn("3") { Text($0.name) }
            TableColumn("4") { Text($0.name) }
            TableColumn("5") { Text($0.name) }
            TableColumn("6") { Text($0.name) }
            TableColumn("7") { Text($0.name) }
            TableColumn("8") { Text($0.name) }
            TableColumn("9") { Text($0.name) }
        }
        let tenColumnMaterializer: any TableColumnContentMaterializing =
            tenColumns.columns
        XCTAssertEqual(
            tenColumnMaterializer.materializeTableColumns().count,
            10
        )

        let tenRows = Table(of: Row.self) {
            TableColumn("Name") { Text($0.name) }
        } rows: {
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
            TableRow(rows[0])
        }
        let tenRowMaterializer: any TableRowContentMaterializing =
            tenRows.rows
        XCTAssertEqual(tenRowMaterializer.materializeTableRows().count, 10)
    }

    // ASSERTIONS: tableFieldMetadata27Observed
    // ASSERTIONS: tableColumnCustomizationCodable27Observed
    func testColumnCustomizationBindingUsesTheObservedErasedOwner() throws {
        var customization = TableColumnCustomization<Row>()
        customization[visibility: "name"] = .hidden
        var writes = 0

        let table = Table(
            rows,
            columnCustomization: Binding(
                get: { customization },
                set: {
                    customization = $0
                    writes += 1
                }
            )
        ) {
            TableColumn("Name") { Text($0.name) }
                .customizationID("name")
        }

        let binding = try XCTUnwrap(table.columnCustomization)
        let id = TableColumnCustomizationID("name")
        XCTAssertEqual(
            binding.wrappedValue.perColumnState[id]?.visibility,
            .hidden
        )

        var erased = binding.wrappedValue
        var entry = try XCTUnwrap(erased.perColumnState[id])
        entry.visibility = .visible
        erased.perColumnState[id] = entry
        binding.wrappedValue = erased
        XCTAssertEqual(customization[visibility: "name"], .visible)
        XCTAssertEqual(writes, 1)
    }

    // ASSERTIONS: tableColumnCustomizationCodable27Observed
    func testColumnCustomizationCodableUsesTheObservedPrivateOwners() throws {
        var customization = TableColumnCustomization<Row>()
        XCTAssertEqual(customization[visibility: "name"], .automatic)
        XCTAssertEqual(
            String(
                data: try JSONEncoder().encode(customization),
                encoding: .utf8
            ),
            #"{"perColumnState":[]}"#
        )

        customization[visibility: "name"] = .hidden
        let encoded = try JSONEncoder().encode(customization)
        XCTAssertEqual(
            String(data: encoded, encoding: .utf8),
            #"{"perColumnState":[{"base":{"explicit":{"_0":"name"}}},{"visibility":{"hidden":{}}}]}"#
        )

        let decoded = try JSONDecoder().decode(
            TableColumnCustomization<Row>.self,
            from: encoded
        )
        XCTAssertEqual(decoded, customization)
        XCTAssertEqual(decoded[visibility: "name"], .hidden)

        customization[visibility: "name"] = .automatic
        XCTAssertEqual(customization[visibility: "name"], .automatic)
        XCTAssertEqual(
            String(
                data: try JSONEncoder().encode(customization),
                encoding: .utf8
            ),
            #"{"perColumnState":[{"base":{"explicit":{"_0":"name"}}},{"visibility":{"automatic":{}}}]}"#
        )
    }

    @MainActor
    private func mount(
        _ controller: WindowController,
        size: CGSize
    ) {
        var redraw = false
        controller.updateView(
            tick: 0,
            delta: 0,
            date: controller.date,
            contentSize: size,
            redraw: &redraw
        ) { _, _ in }
    }

    @MainActor
    private func firstSingleTapPoint(
        in controller: WindowController,
        size: CGSize
    ) -> CGPoint? {
        controller.viewGraph.data.withCurrent {
            guard let root = controller.viewGraph.responderNode
                    as? MultiViewResponder else {
                return nil
            }
            for y in stride(from: 2.0, to: size.height - 2, by: 2.0) {
                for x in stride(from: 2.0, to: size.width - 2, by: 2.0) {
                    let point = CGPoint(x: x, y: y)
                    if root.respondersContaining(point: point).contains(
                        where: { responder in
                            guard let gesture =
                                    responder as? any AnyGestureResponder else {
                                return false
                            }
                            let type = String(reflecting: gesture.gestureType)
                            return type.contains("SingleTapGesture")
                                && type.contains("MouseEvent")
                        }
                    ) {
                        return point
                    }
                }
            }
            return nil
        }
    }

    @MainActor
    private func firstSingleTapHorizontalRanges(
        in controller: WindowController,
        size: CGSize
    ) -> [ClosedRange<CGFloat>]? {
        controller.viewGraph.data.withCurrent {
            guard let root = controller.viewGraph.responderNode
                    as? MultiViewResponder else {
                return nil
            }
            for y in stride(from: 2.0, to: size.height - 2, by: 2.0) {
                var ranges: [ObjectIdentifier: (CGFloat, CGFloat)] = [:]
                for x in stride(from: 0.0, to: size.width, by: 1.0) {
                    let point = CGPoint(x: x, y: y)
                    for responder in root.respondersContaining(point: point) {
                        guard let gesture =
                                responder as? any AnyGestureResponder else {
                            continue
                        }
                        let type = String(reflecting: gesture.gestureType)
                        guard type.contains("SingleTapGesture"),
                              type.contains("MouseEvent") else {
                            continue
                        }
                        let id = ObjectIdentifier(responder)
                        if let range = ranges[id] {
                            ranges[id] = (min(range.0, x), max(range.1, x))
                        } else {
                            ranges[id] = (x, x)
                        }
                    }
                }
                if ranges.count == 2 {
                    return ranges.values
                        .map { $0.0...$0.1 }
                        .sorted { $0.lowerBound < $1.lowerBound }
                }
            }
            return nil
        }
    }

    @MainActor
    private func pointerClick(
        _ controller: WindowController,
        at point: CGPoint
    ) -> Bool {
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
        return down && up
    }
}
