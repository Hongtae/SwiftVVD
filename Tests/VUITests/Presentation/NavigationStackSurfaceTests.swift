import Foundation
import XCTest
@testable import VUI
@testable import VVD

final class NavigationStackSurfaceTests: XCTestCase {
    // ASSERTIONS: navigationPathPublicValue27Observed
    // ASSERTIONS: navigationPathCodable27Observed
    func testNavigationPathValueAndCodableSemantics() throws {
        var path = NavigationPath()
        XCTAssertTrue(path.isEmpty)

        path.append(7)
        path.append("two")
        path.append(3.5)
        XCTAssertEqual(path.count, 3)

        var copy = NavigationPath()
        copy.append(7)
        copy.append("two")
        copy.append(3.5)
        XCTAssertEqual(path, copy)

        let representation = try XCTUnwrap(path.codable)
        let data = try JSONEncoder().encode(representation)
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            "[\"Swift.Double\",\"3.5\",\"Swift.String\",\"\\\"two\\\"\",\"Swift.Int\",\"7\"]"
        )

        let decodedRepresentation = try JSONDecoder().decode(
            NavigationPath.CodableRepresentation.self,
            from: data
        )
        XCTAssertNotEqual(representation, decodedRepresentation)
        let decoded = NavigationPath(decodedRepresentation)
        XCTAssertEqual(decoded.count, 3)
        XCTAssertNotEqual(path, decoded)
        XCTAssertEqual(decoded, NavigationPath(decodedRepresentation))

        path.removeLast(2)
        XCTAssertEqual(path.count, 1)
        XCTAssertFalse(path.isEmpty)

        let noncodable = NavigationPath([
            AnyHashable(ObjectIdentifier(NavigationStackSurfaceTests.self))
        ])
        XCTAssertNil(noncodable.codable)
    }

    // ASSERTIONS: navigationSurfaceOwner27Observed
    // ASSERTIONS: navigationSurfaceOwnerFieldMetadata27Observed
    func testCoreNavigationSurfaceTypeChecks() {
        var path: [Int] = []
        let binding = Binding(
            get: { path },
            set: { path = $0 }
        )
        let valueLink = NavigationLink(value: 1) {
            Text("Value")
        }
        let directLink = NavigationLink {
            Text("Destination")
        } label: {
            Text("Direct")
        }
        let stack = NavigationStack(path: binding) {
            valueLink
                .navigationDestination(for: Int.self) {
                    Text("Value \($0)")
                }
        }
        let unbound = NavigationStack {
            directLink
        }
        let presented = Text("Root").navigationDestination(
            isPresented: Binding.constant(true)
        ) {
            Text("Presented")
        }
        let item = Text("Root").navigationDestination(
            item: Binding<Int?>.constant(4)
        ) {
            Text("Item \($0)")
        }

        _ = stack.body
        _ = unbound.body
        _ = presented
        _ = item
        XCTAssertTrue(path.isEmpty)
    }

    // ASSERTIONS: navigationStackPublicControl27Observed
    func testActiveNavigationPublishesBackIntoTheRootToolbar() throws {
        let host = NavigationToolbarRendererHost()
        let graph = ViewGraph(
            replaceableContent: NavigationStack(path: Binding.constant([1])) {
                Text("Root")
                    .navigationDestination(for: Int.self) {
                        Text("Destination \($0)")
                    }
            },
            rendererHost: host,
            features: [RootToolbarViewGraph()]
        )
        host.storage = graph
        graph.updateOutputs(at: .zero)

        let item = try XCTUnwrap(host.receivedToolbarStorage?.items.first)
        XCTAssertEqual(
            item.id,
            ToolbarStorage.ID("com.vui.navigationStack.back")
        )
        XCTAssertEqual(item.placement, .navigation)
    }

    // ASSERTIONS: navigationPathMutation27Observed
    // ASSERTIONS: navigationDestinationLifetime27Observed
    @MainActor
    func testProgrammaticPathMountsEveryLayerAndRemovesOnlyPoppedLayers() throws {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationInitialPathRoot(probe: probe),
            identity: NavigationInitialPathRoot.self
        )

        update(controller, ticks: 0..<8)
        XCTAssertEqual(Set(probe.events), Set([
            "root-appear",
            "destination-1-appear",
            "destination-2-appear",
        ]))

        let path = try XCTUnwrap(probe.path)
        path.wrappedValue = []
        settle(controller, ticks: 8..<16)
        XCTAssertTrue(probe.events.contains("destination-1-disappear"))
        XCTAssertTrue(probe.events.contains("destination-2-disappear"))
        XCTAssertFalse(probe.events.contains("root-disappear"))

        path.wrappedValue = [3]
        settle(controller, ticks: 16..<24)
        XCTAssertTrue(probe.events.contains("destination-3-appear"))

        path.wrappedValue.append(4)
        settle(controller, ticks: 24..<32)
        XCTAssertTrue(probe.events.contains("destination-4-appear"))

        path.wrappedValue.removeLast()
        settle(controller, ticks: 32..<40)
        XCTAssertTrue(probe.events.contains("destination-4-disappear"))
        XCTAssertFalse(probe.events.contains("destination-3-disappear"))
    }

    // ASSERTIONS: navigationStackPublicControl27Observed
    // ASSERTIONS: navigationPathMutation27Observed
    @MainActor
    func testValueLinkAndBackWriteTheBoundPath() throws {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationValueLinkRoot(probe: probe),
            identity: NavigationValueLinkRoot.self
        )
        update(controller, ticks: 0..<8)
        XCTAssertTrue(probe.hasNavigationContext)

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 150, y: 90)))
        settle(controller, ticks: 8..<16)
        XCTAssertEqual(try XCTUnwrap(probe.path).wrappedValue, [1])
        XCTAssertTrue(probe.events.contains("destination-1-appear"))

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 15, y: 20)))
        settle(controller, ticks: 16..<24)
        XCTAssertEqual(try XCTUnwrap(probe.path).wrappedValue, [])
        XCTAssertTrue(probe.events.contains("destination-1-disappear"))
    }

    @MainActor
    func testNilValueLinkCannotMutateTheBoundPath() throws {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationNilValueLinkRoot(probe: probe),
            identity: NavigationNilValueLinkRoot.self
        )
        update(controller, ticks: 0..<8)

        _ = pointerClick(controller, at: CGPoint(x: 150, y: 90))
        settle(controller, ticks: 8..<16)

        XCTAssertEqual(try XCTUnwrap(probe.path).wrappedValue, [])
        XCTAssertFalse(probe.events.contains("destination-1-appear"))
    }

    // ASSERTIONS: navigationDirectLinkControl27Observed
    // ASSERTIONS: navigationDestinationLifetime27Observed
    @MainActor
    func testDirectLinkUsesPresentationStateWithoutMutatingPath() throws {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationDirectLinkRoot(probe: probe),
            identity: NavigationDirectLinkRoot.self
        )
        update(controller, ticks: 0..<8)

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 150, y: 90)))
        settle(controller, ticks: 8..<16)
        XCTAssertEqual(try XCTUnwrap(probe.path).wrappedValue, [])
        XCTAssertTrue(probe.events.contains("direct-appear"))

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 15, y: 20)))
        settle(controller, ticks: 16..<24)
        XCTAssertEqual(try XCTUnwrap(probe.path).wrappedValue, [])
        XCTAssertTrue(probe.events.contains("direct-disappear"))
    }

    // ASSERTIONS: navigationPresentedBinding27Observed
    @MainActor
    func testPresentedAndItemDestinationsWriteBackOnBack() throws {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationPresentedRoot(probe: probe),
            identity: NavigationPresentedRoot.self
        )
        update(controller, ticks: 0..<8)
        XCTAssertTrue(try XCTUnwrap(probe.isPresented).wrappedValue)
        XCTAssertTrue(probe.events.contains("boolean-appear"))

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 15, y: 20)))
        settle(controller, ticks: 8..<16)
        XCTAssertFalse(try XCTUnwrap(probe.isPresented).wrappedValue)
        XCTAssertTrue(probe.events.contains("boolean-disappear"))

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 150, y: 90)))
        settle(controller, ticks: 16..<24)
        XCTAssertTrue(probe.events.contains("item-4-appear"))

        XCTAssertTrue(pointerClick(controller, at: CGPoint(x: 15, y: 20)))
        settle(controller, ticks: 24..<32)
        XCTAssertNil(try XCTUnwrap(probe.item).wrappedValue)
        XCTAssertTrue(probe.events.contains("item-4-disappear"))
    }

    // ASSERTIONS: navigationDestinationPrecedence27Observed
    @MainActor
    func testFirstDestinationRegistrationWins() {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationDestinationPrecedenceRoot(probe: probe),
            identity: NavigationDestinationPrecedenceRoot.self
        )
        update(controller, ticks: 0..<8)

        XCTAssertTrue(probe.events.contains("inner-appear"))
        XCTAssertFalse(probe.events.contains("outer-appear"))
    }

    // ASSERTIONS: navigationTabDestinationBoundary27Observed
    @MainActor
    func testTabBoundaryBlocksOuterStack() throws {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationOuterTabBoundaryRoot(probe: probe),
            identity: NavigationOuterTabBoundaryRoot.self
        )
        update(controller, ticks: 0..<8)
        _ = pointerClick(
            controller,
            at: CGPoint(x: 150, y: 120)
        )
        settle(controller, ticks: 8..<16)
        XCTAssertEqual(try XCTUnwrap(probe.path).wrappedValue, [])
        XCTAssertFalse(
            probe.events.contains("destination-1-appear")
        )
    }

    // ASSERTIONS: navigationTabDestinationBoundary27Observed
    // ASSERTIONS: navigationDestinationScopeOwnership27Observed
    // ASSERTIONS: dynamicViewPhaseEarlyParentPublicationObserved
    @MainActor
    func testTabBoundaryAllowsInnerStack() throws {
        let probe = NavigationLifecycleProbe()
        let controller = makeController(
            content: NavigationInnerTabBoundaryRoot(probe: probe),
            identity: NavigationInnerTabBoundaryRoot.self
        )
        update(controller, ticks: 0..<8)
        XCTAssertTrue(pointerClick(
            controller,
            at: CGPoint(x: 150, y: 120)
        ))
        settle(controller, ticks: 8..<16)
        XCTAssertEqual(try XCTUnwrap(probe.path).wrappedValue, [1])
        XCTAssertTrue(
            probe.events.contains("destination-1-appear")
        )
    }

    @MainActor
    private func makeController<Content: View>(
        content: Content,
        identity: Any.Type
    ) -> WindowController {
        WindowController(
            content: content,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(identity)
            )
        )
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
                contentSize: CGSize(width: 300, height: 180),
                redraw: &redraw
            ) { _, _ in }
        }
    }

    @MainActor
    private func settle(
        _ controller: WindowController,
        ticks: Range<Int>
    ) {
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        update(controller, ticks: ticks)
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

}

private final class NavigationLifecycleProbe {
    var path: Binding<[Int]>?
    var isPresented: Binding<Bool>?
    var item: Binding<Int?>?
    var hasNavigationContext = false
    var events: [String] = []
}

private final class NavigationToolbarRendererHost:
    ViewRendererHost,
    RootToolbarStorageHost
{
    var storage: ViewGraph!
    let sceneResources = SceneResources()
    var currentTimestamp = Time.zero
    var valuesNeedingUpdate: ViewGraphRootValues = []
    var renderingPhase = ViewRenderingPhase()
    var externalUpdateCount = 0
    var receivedToolbarStorage: ToolbarStorage?

    var viewGraph: ViewGraph { storage }
    var responderNode: ResponderNode? { nil }
    var gestureGraph: GestureGraph? { nil }

    func rootToolbarStorageDidChange(_ storage: ToolbarStorage) {
        receivedToolbarStorage = storage
    }

    func requestUpdate(after: Double) {}

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }

    func updateRootView() {}
    func updateEnvironment() {}
    func updateSize() {}
    func updateSafeArea() {}
    func updateContainerSize() {}
}

private struct NavigationProbeLabel: View {
    let probe: NavigationLifecycleProbe
    @Environment(\.navigationStackContext) private var context

    var body: some View {
        let _ = probe.hasNavigationContext = context != nil
        Text("Push")
            .frame(width: 260, height: 150)
    }
}

private struct NavigationDestinationContent: View {
    let name: String
    let probe: NavigationLifecycleProbe

    var body: some View {
        Text(name)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { probe.events.append("\(name)-appear") }
            .onDisappear { probe.events.append("\(name)-disappear") }
    }
}

private struct NavigationInitialPathRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var path = [1, 2]

    var body: some View {
        let _ = probe.path = $path
        NavigationStack(path: $path) {
            NavigationDestinationContent(name: "root", probe: probe)
                .navigationDestination(for: Int.self) {
                    NavigationDestinationContent(
                        name: "destination-\($0)",
                        probe: probe
                    )
                }
        }
    }
}

private struct NavigationValueLinkRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var path: [Int] = []

    var body: some View {
        let _ = probe.path = $path
        NavigationStack(path: $path) {
            NavigationLink(value: 1) {
                NavigationProbeLabel(probe: probe)
            }
            .navigationDestination(for: Int.self) {
                NavigationDestinationContent(
                    name: "destination-\($0)",
                    probe: probe
                )
            }
        }
    }
}

private struct NavigationNilValueLinkRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var path: [Int] = []

    var body: some View {
        let _ = probe.path = $path
        NavigationStack(path: $path) {
            NavigationLink(value: Int?.none) {
                NavigationProbeLabel(probe: probe)
            }
            .navigationDestination(for: Int.self) {
                NavigationDestinationContent(
                    name: "destination-\($0)",
                    probe: probe
                )
            }
        }
    }
}

private struct NavigationDirectLinkRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var path: [Int] = []

    var body: some View {
        let _ = probe.path = $path
        NavigationStack(path: $path) {
            NavigationLink {
                NavigationDestinationContent(name: "direct", probe: probe)
            } label: {
                NavigationProbeLabel(probe: probe)
            }
        }
    }
}

private struct NavigationPresentedRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var isPresented = true
    @State private var item: Int?

    var body: some View {
        let _ = probe.isPresented = $isPresented
        let _ = probe.item = $item
        NavigationStack {
            Button {
                item = 4
            } label: {
                Text("Present item")
                    .frame(width: 260, height: 150)
            }
                .navigationDestination(isPresented: $isPresented) {
                    NavigationDestinationContent(
                        name: "boolean",
                        probe: probe
                    )
                }
                .navigationDestination(item: $item) {
                    NavigationDestinationContent(
                        name: "item-\($0)",
                        probe: probe
                    )
                }
        }
    }
}

private struct NavigationDestinationPrecedenceRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var path = [1]

    var body: some View {
        NavigationStack(path: $path) {
            Text("Root")
                .navigationDestination(for: Int.self) { _ in
                    NavigationDestinationContent(
                        name: "inner",
                        probe: probe
                    )
                }
                .navigationDestination(for: Int.self) { _ in
                    NavigationDestinationContent(
                        name: "outer",
                        probe: probe
                    )
                }
        }
    }
}

private struct NavigationOuterTabBoundaryRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var path: [Int] = []

    var body: some View {
        let _ = probe.path = $path
        NavigationStack(path: $path) {
            TabView {
                Tab {
                    NavigationBoundaryLink(probe: probe)
                } label: {
                    Text("Tab")
                        .frame(width: 80, height: 24)
                }
            }
        }
    }
}

private struct NavigationInnerTabBoundaryRoot: View {
    let probe: NavigationLifecycleProbe
    @State private var path: [Int] = []

    var body: some View {
        let _ = probe.path = $path
        TabView {
            Tab {
                NavigationStack(path: $path) {
                    NavigationBoundaryLink(probe: probe)
                }
            } label: {
                Text("Tab")
                    .frame(width: 80, height: 24)
            }
        }
    }
}

private struct NavigationBoundaryLink: View {
    let probe: NavigationLifecycleProbe

    var body: some View {
        NavigationLink(value: 1) {
            Text("Push")
                .frame(width: 260, height: 100)
        }
        .navigationDestination(for: Int.self) {
            NavigationDestinationContent(
                name: "destination-\($0)",
                probe: probe
            )
        }
    }
}
