import XCTest
@testable import VUI
@testable import VVD

final class DisclosureOutlineControlTests: XCTestCase {
    private struct Node: Identifiable {
        var id: Int
        var name: String
        var children: [Node]?
    }

    private var nodes: [Node] {
        [
            Node(
                id: 1,
                name: "Root",
                children: [
                    Node(id: 11, name: "Leaf", children: nil),
                ]
            ),
        ]
    }

    // ASSERTIONS: disclosureGroupPublicStructure27Observed
    // ASSERTIONS: disclosureGroupOwnerLowering27Observed
    // ASSERTIONS: disclosureOutlineFieldMetadata27Observed
    func testDisclosureGroupRetainsObservedStorageAndResolvedOwner() {
        let disclosure = DisclosureGroup {
            Text("Content")
        } label: {
            Text("Label")
        }

        XCTAssertEqual(
            Mirror(reflecting: disclosure).children.compactMap(\.label),
            ["label", "content", "_isExpanded"]
        )
        let bodyType = String(reflecting: type(of: disclosure.body))
        XCTAssertTrue(bodyType.contains("ResolvedDisclosureGroupStyle"))
        XCTAssertTrue(bodyType.contains("StaticSourceWriter"))
        _ = disclosure.disclosureGroupStyle(.automatic)
    }

    // ASSERTIONS: disclosureGroupStyleBinding27Observed
    func testDisclosureStyleConfigurationWritesExpansionBinding() {
        var isExpanded = true
        var writes: [Bool] = []
        let configuration = DisclosureGroupStyleConfiguration(
            isExpanded: Binding(
                get: { isExpanded },
                set: {
                    isExpanded = $0
                    writes.append($0)
                }
            )
        )

        XCTAssertEqual(
            Mirror(reflecting: configuration).children.compactMap(\.label),
            ["label", "content", "_isExpanded"]
        )
        configuration.$isExpanded.wrappedValue = false
        configuration.isExpanded = true
        XCTAssertTrue(isExpanded)
        XCTAssertEqual(writes, [false, true])
    }

    // ASSERTIONS: outlineGroupPublicStructure27Observed
    // ASSERTIONS: outlineGroupBindingData27Observed
    // ASSERTIONS: outlineGroupOwnerLowering27Observed
    func testOutlineGroupRetainsObservedOwnersForValueAndBindingData() {
        var mutableNodes = nodes
        let valueOutline = OutlineGroup(nodes, children: \.children) {
            Text($0.name)
        }
        let rootOutline = OutlineGroup(nodes[0], children: \.children) {
            Text($0.name)
        }
        let bindingOutline = OutlineGroup(
            Binding(
                get: { mutableNodes },
                set: { mutableNodes = $0 }
            ),
            children: \.children
        ) {
            Text($0.wrappedValue.name)
        }

        let outlineFields = [
            "_expandedElements",
            "base",
            "id",
            "children",
            "parentContent",
            "leafContent",
            "grouping",
        ]
        let primitiveFields = [
            "base",
            "parentContent",
            "leafContent",
            "grouping",
            "id",
            "children",
            "_expandedElements",
            "contentID",
        ]
        XCTAssertEqual(
            Mirror(reflecting: valueOutline).children.compactMap(\.label),
            outlineFields
        )
        XCTAssertEqual(
            Mirror(reflecting: bindingOutline).children.compactMap(\.label),
            outlineFields
        )
        if case .forest = valueOutline.base {
        } else {
            XCTFail("collection construction should retain the forest base")
        }
        if case .tree = rootOutline.base {
        } else {
            XCTFail("single-root construction should retain the tree base")
        }
        XCTAssertEqual(
            Mirror(reflecting: valueOutline.body)
                .children.compactMap(\.label),
            primitiveFields
        )
        XCTAssertEqual(
            Mirror(reflecting: bindingOutline.body)
                .children.compactMap(\.label),
            primitiveFields
        )
    }

    // ASSERTIONS: outlineGroupExpansionIdentity27Observed
    // ASSERTIONS: outlineGroupExpansionProjection27Observed
    func testOutlineExpansionProjectionUsesElementIdentity() {
        var expanded: Set<Int> = [1]
        let binding = Binding(
            get: { expanded },
            set: { expanded = $0 }
        )
        typealias Primitive = OutlinePrimitive<
            [Node],
            Int,
            Text,
            Text,
            DisclosureGroup<Text, OutlineSubgroupChildren>
        >
        let root = binding.projecting(
            Primitive.ExpansionProjection(id: 1)
        )
        let branch = binding.projecting(
            Primitive.ExpansionProjection(id: 12)
        )

        XCTAssertTrue(root.wrappedValue)
        XCTAssertFalse(branch.wrappedValue)
        branch.wrappedValue = true
        XCTAssertEqual(expanded, [1, 12])
        root.wrappedValue = false
        XCTAssertEqual(expanded, [12])
    }

    // ASSERTIONS: disclosureGroupPointerExpansion27Observed
    @MainActor
    func testMountedDisclosurePointerWritesExpansionBinding() throws {
        let store = DisclosurePointerStore()
        let controller = WindowController(
            content: DisclosurePointerRoot(store: store),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(DisclosurePointerRoot.self)
            )
        )
        update(controller, ticks: 0..<3)

        let firstPoint = try XCTUnwrap(
            firstButtonGesturePoint(in: controller)
        )
        click(controller, at: firstPoint)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        update(controller, ticks: 3..<6)
        XCTAssertTrue(store.isExpanded)
        XCTAssertEqual(store.writes, [true])

        let secondPoint = try XCTUnwrap(
            firstButtonGesturePoint(in: controller)
        )
        click(controller, at: secondPoint)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        update(controller, ticks: 6..<9)
        XCTAssertFalse(store.isExpanded)
        XCTAssertEqual(store.writes, [true, false])
    }

    // ASSERTIONS: outlineGroupExpansionIdentity27Observed
    // ASSERTIONS: outlineGroupOwnerLowering27Observed
    @MainActor
    func testMountedOutlineExpansionPublishesNestedBranch() throws {
        let controller = WindowController(
            content: OutlinePointerRoot(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(OutlinePointerRoot.self)
            )
        )
        update(controller, ticks: 0..<3)
        XCTAssertEqual(buttonGestureCount(in: controller), 1)

        let point = try XCTUnwrap(firstButtonGesturePoint(in: controller))
        click(controller, at: point)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        update(controller, ticks: 3..<7)
        XCTAssertEqual(buttonGestureCount(in: controller), 2)

        click(controller, at: point)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        update(controller, ticks: 7..<11)
        XCTAssertEqual(buttonGestureCount(in: controller), 1)
    }

    @MainActor
    private func update(
        _ controller: WindowController,
        ticks: Range<Int>
    ) {
        for tick in ticks {
            var redraw = false
            controller.updateView(
                tick: UInt64(tick),
                delta: 1.0 / 60.0,
                date: controller.date.addingTimeInterval(1.0 / 60.0),
                contentSize: CGSize(width: 280, height: 180),
                redraw: &redraw
            ) { _, _ in }
        }
    }

    @MainActor
    private func firstButtonGesturePoint(
        in controller: WindowController
    ) -> CGPoint? {
        for y in stride(from: 0.0, through: 180.0, by: 2.0) {
            for x in stride(from: 0.0, through: 280.0, by: 2.0) {
                let point = CGPoint(x: x, y: y)
                guard let responder = controller.gestureEnvironment
                    .eventBinding(
                        at: point,
                        accepting: VUI.MouseEvent.self
                    )?.responder as? any AnyGestureResponder else {
                    continue
                }
                if String(reflecting: responder.gestureType)
                    .contains("ButtonGesture") {
                    return point
                }
            }
        }
        return nil
    }

    @MainActor
    private func buttonGestureCount(
        in controller: WindowController
    ) -> Int {
        func count(in responder: ViewResponder) -> Int {
            let ownCount: Int
            if let gesture = responder as? any AnyGestureResponder,
               String(reflecting: gesture.gestureType)
                .contains("ButtonGesture") {
                ownCount = 1
            } else {
                ownCount = 0
            }
            return responder.children.reduce(ownCount) {
                $0 + count(in: $1)
            }
        }

        return controller.viewGraph.data.withCurrent {
            guard let root = controller.viewGraph.responderNode
                as? ViewResponder else {
                return 0
            }
            return count(in: root)
        }
    }

    @MainActor
    private func click(
        _ controller: WindowController,
        at point: CGPoint
    ) {
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonDown,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: point,
            timestamp: 0
        )))
        XCTAssertTrue(controller.handleMouseEvent(event: MouseEvent(
            type: .buttonUp,
            device: .genericMouse,
            deviceID: 0,
            buttonID: 0,
            clickCount: 1,
            location: point,
            timestamp: 0.01
        )))
    }
}

private final class DisclosurePointerStore: @unchecked Sendable {
    var isExpanded = false
    var writes: [Bool] = []
}

private struct DisclosurePointerRoot: View {
    let store: DisclosurePointerStore

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { store.isExpanded },
                set: {
                    store.isExpanded = $0
                    store.writes.append($0)
                }
            )
        ) {
            Text("Mounted content")
        } label: {
            Text("Details")
        }
        .frame(width: 240, height: 140)
    }
}

private struct OutlinePointerNode: Identifiable {
    var id: Int
    var name: String
    var children: [OutlinePointerNode]?
}

private struct OutlinePointerRoot: View {
    private let nodes = [
        OutlinePointerNode(
            id: 1,
            name: "Root",
            children: [
                OutlinePointerNode(
                    id: 11,
                    name: "Leaf",
                    children: nil
                ),
                OutlinePointerNode(
                    id: 12,
                    name: "Branch",
                    children: [
                        OutlinePointerNode(
                            id: 121,
                            name: "Nested leaf",
                            children: nil
                        ),
                    ]
                ),
            ]
        ),
    ]

    var body: some View {
        OutlineGroup(nodes, children: \.children) {
            Text($0.name)
        }
        .frame(width: 240, height: 140)
    }
}
