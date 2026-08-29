import XCTest
import Observation
import Synchronization
@testable import VUI

final class RootToolbarHostTests: XCTestCase {
    func testToolbarModifierPublishesHostReadableRootStorage() throws {
        let host = ToolbarTestRendererHost()
        let graph = ViewGraph(
            replaceableContent: Text("Scene")
                .toolbar {
                    ToolbarItem {
                        Text("Action")
                    }
                },
            rendererHost: host,
            features: [RootToolbarViewGraph()]
        )
        host.storage = graph
        graph.updateOutputs(at: .zero)

        let storage = try XCTUnwrap(host.receivedToolbarStorage)
        XCTAssertNotNil(storage.configuration)
        XCTAssertNil(storage.configuration?.customizationID)
        XCTAssertEqual(storage.items.count, 1)
        if let item = storage.items.first {
            XCTAssertEqual(item.placement, .automatic)
            XCTAssertTrue(item.showsByDefault)
        }
    }

    func testPlainToolbarBuilderSupportsParameterPackBeyondPreviousLimit()
    throws {
        let host = ToolbarTestRendererHost()
        let graph = ViewGraph(
            replaceableContent: Text("Scene")
                .toolbar {
                    ToolbarItem { Text("First") }
                    ToolbarItem { Text("Second") }
                    ToolbarItem { Text("Third") }
                    ToolbarItem { Text("Fourth") }
                    ToolbarItem { Text("Fifth") }
                    ToolbarItem { Text("Sixth") }
                },
            rendererHost: host,
            features: [RootToolbarViewGraph()]
        )
        host.storage = graph
        graph.updateOutputs(at: .zero)

        let storage = try XCTUnwrap(host.receivedToolbarStorage)
        XCTAssertNil(storage.configuration?.customizationID)
        XCTAssertEqual(storage.items.count, 6)
    }

    func testCustomizableToolbarPublishesIdentityAndItems() throws {
        let host = ToolbarTestRendererHost()
        let graph = ViewGraph(
            replaceableContent: Text("Scene")
                .toolbar(id: "root-toolbar") {
                    ToolbarItem(id: "first") {
                        Text("First")
                    }
                    ToolbarItem(id: "second") {
                        Text("Second")
                    }
                    ToolbarItem(id: "third") {
                        Text("Third")
                    }
                    ToolbarItem(id: "fourth") {
                        Text("Fourth")
                    }
                    ToolbarItem(id: "fifth") {
                        Text("Fifth")
                    }
                    ToolbarItem(id: "sixth") {
                        Text("Sixth")
                    }
                },
            rendererHost: host,
            features: [RootToolbarViewGraph()]
        )
        host.storage = graph
        graph.updateOutputs(at: .zero)

        let storage = try XCTUnwrap(host.receivedToolbarStorage)
        XCTAssertEqual(
            storage.configuration?.customizationID,
            "root-toolbar"
        )
        XCTAssertEqual(
            storage.items.map(\.id),
            [
                ToolbarStorage.ID("first"),
                ToolbarStorage.ID("second"),
                ToolbarStorage.ID("third"),
                ToolbarStorage.ID("fourth"),
                ToolbarStorage.ID("fifth"),
                ToolbarStorage.ID("sixth"),
            ]
        )
    }

    func testRootBridgeOutlivesReplaceableToolbarSnapshots() throws {
        let bridge = RootToolbarBridge()
        let first = toolbarStorage(id: "first")

        XCTAssertTrue(bridge.update(storage: first))
        XCTAssertEqual(bridge.snapshot?.visibility, .visible)
        XCTAssertEqual(
            bridge.allocatedHeight,
            RootToolbarHost.toolbarHeight
        )
        XCTAssertFalse(bridge.update(storage: first))

        var refreshedContent = first
        refreshedContent.items[0].view = AnyView(Text("refreshed"))
        XCTAssertTrue(bridge.update(storage: refreshedContent))

        XCTAssertTrue(bridge.toggleVisibility())
        XCTAssertEqual(bridge.snapshot?.visibility, .hidden)
        XCTAssertEqual(bridge.allocatedHeight, 0)

        // Replacing the concrete toolbar snapshot preserves bridge-owned
        // visibility as long as the root toolbar remains installed.
        XCTAssertTrue(bridge.update(storage: toolbarStorage(id: "second")))
        XCTAssertEqual(bridge.snapshot?.visibility, .hidden)

        XCTAssertTrue(bridge.update(storage: ToolbarStorage()))
        XCTAssertNil(bridge.snapshot)
        XCTAssertEqual(bridge.allocatedHeight, 0)

        XCTAssertTrue(bridge.update(storage: toolbarStorage(id: "third")))
        XCTAssertEqual(bridge.snapshot?.visibility, .visible)
    }

    func testRepeatedAbsentRootToolbarUpdateDoesNotNotifyObservers() {
        // ASSERTIONS commandsRootToolbarAbsentNoOpRuntimeObserved
        let bridge = RootToolbarBridge()
        let observationCount = Mutex(0)

        withObservationTracking {
            _ = bridge.snapshot
            _ = bridge.customizationSession
        } onChange: {
            observationCount.withLock { $0 += 1 }
        }

        XCTAssertFalse(bridge.update(storage: ToolbarStorage()))
        XCTAssertEqual(observationCount.withLock { $0 }, 0)
    }

    func testRootBridgeOwnsToolbarCommandValidationAndCustomizationSession()
    throws {
        // ASSERTIONS commandsToolbarRootOwnerFieldMetadataObserved
        // ASSERTIONS commandsToolbarRootOwnerDisassemblyObserved
        let bridge = RootToolbarBridge()

        XCTAssertNil(bridge.commandContext)
        XCTAssertFalse(bridge.perform(.toggleVisibility))
        XCTAssertFalse(bridge.perform(.customize))

        XCTAssertTrue(bridge.update(storage: toolbarStorage(id: "plain")))
        XCTAssertEqual(bridge.commandContext?.visibility, .visible)
        XCTAssertEqual(bridge.commandContext?.canToggleVisibility, true)
        XCTAssertEqual(bridge.commandContext?.canCustomize, false)
        XCTAssertTrue(bridge.perform(.toggleVisibility))
        XCTAssertEqual(bridge.commandContext?.visibility, .hidden)

        let customizable = customizableToolbarStorage()
        XCTAssertTrue(bridge.update(storage: customizable))
        XCTAssertEqual(bridge.commandContext?.canCustomize, true)
        XCTAssertTrue(bridge.perform(.customize))
        XCTAssertEqual(bridge.commandContext?.visibility, .visible)
        XCTAssertEqual(
            bridge.commandContext?.customizationIsPresented,
            true
        )
        XCTAssertEqual(
            bridge.commandContext?.canToggleVisibility,
            false
        )
        XCTAssertFalse(bridge.perform(.toggleVisibility))

        XCTAssertEqual(
            bridge.snapshot?.visibleItemIDs,
            [ToolbarStorage.ID("first")]
        )
        XCTAssertTrue(
            bridge.toggleCustomizationItem(ToolbarStorage.ID("second"))
        )
        XCTAssertEqual(
            bridge.snapshot?.visibleItemIDs,
            [ToolbarStorage.ID("first"), ToolbarStorage.ID("second")]
        )
        XCTAssertTrue(bridge.endCustomization())
        XCTAssertEqual(
            bridge.commandContext?.customizationIsPresented,
            false
        )
        XCTAssertEqual(bridge.commandContext?.canToggleVisibility, true)

        XCTAssertTrue(bridge.update(storage: ToolbarStorage()))
        XCTAssertNil(bridge.commandContext)
        XCTAssertTrue(bridge.update(storage: customizable))
        XCTAssertEqual(
            bridge.snapshot?.visibleItemIDs,
            [ToolbarStorage.ID("first"), ToolbarStorage.ID("second")]
        )
    }

    func testRootFeatureTracksToolbarRemovalAndReinstallation() throws {
        let host = ToolbarTestRendererHost()
        let graph = ViewGraph(
            replaceableContent: toolbarView(id: "first"),
            rendererHost: host,
            features: [RootToolbarViewGraph()]
        )
        host.storage = graph

        graph.updateOutputs(at: .zero)
        XCTAssertEqual(
            host.receivedToolbarStorage?.items.map(\.id),
            [ToolbarStorage.ID("first")]
        )

        let rootInput = try XCTUnwrap(graph.rootAnyViewContentInput)
        graph.data.withCurrent {
            rootInput.setValue(AnyView(Text("No toolbar")))
        }
        graph.updateOutputs(at: .zero)
        XCTAssertNil(host.receivedToolbarStorage?.configuration)
        XCTAssertEqual(host.receivedToolbarStorage?.items.count, 0)

        graph.data.withCurrent {
            rootInput.setValue(toolbarView(id: "second"))
        }
        graph.updateOutputs(at: .zero)
        XCTAssertNotNil(host.receivedToolbarStorage?.configuration)
        XCTAssertEqual(
            host.receivedToolbarStorage?.items.map(\.id),
            [ToolbarStorage.ID("second")]
        )
    }

    func testVisibleRootToolbarHostBuildsItsViewRoute() throws {
        let host = TestViewRendererHost()
        let bridge = RootToolbarBridge()
        XCTAssertTrue(bridge.update(storage: toolbarStorage(id: "action")))
        let graph = ViewGraph(
            replaceableContent: RootToolbarHost.hostRootView(
                sceneContent: AnyView(Text("Scene")),
                bridge: bridge
            ),
            rendererHost: host
        )
        host.storage = graph

        graph.updateOutputs(at: .zero)

        XCTAssertNotNil(graph.rootLayoutComputer)
    }

    func testStableRootHostObservesBridgeInstallation() throws {
        let counter = ToolbarRenderCounter()
        let bridge = RootToolbarBridge()
        let host = TestViewRendererHost()
        let graph = ViewGraph(
            replaceableContent: RootToolbarHost.hostRootView(
                sceneContent: AnyView(Text("Scene")),
                bridge: bridge
            ),
            rendererHost: host
        )
        host.storage = graph

        graph.updateOutputs(at: .zero)
        XCTAssertEqual(counter.value, 0)

        var storage = toolbarStorage(id: "action")
        storage.items[0].view = AnyView(
            ToolbarRenderProbe(counter: counter)
        )
        XCTAssertTrue(bridge.update(storage: storage))
        graph.updateOutputs(at: .zero)

        XCTAssertGreaterThan(counter.value, 0)
    }

    func testRootHostDoesNotConsumeSheetWeakGenerator() throws {
        let sourceHost = TestViewRendererHost()
        let sourceGraph = ViewGraph(
            replaceableContent: Text("Generator source"),
            rendererHost: sourceHost
        )
        sourceHost.storage = sourceGraph

        let foreignGenerator: TypedUnaryViewGenerator =
            sourceGraph.data.withCurrent {
                let graph = sourceGraph.data.graph
                let source = graph.makeInput(
                    value: Text("Foreign")
                )
                return TypedUnaryViewGenerator(
                    _GraphValue(_attribute: source),
                    baseInputs: _GraphInputs(
                        time: graph.makeInput(value: .zero),
                        phase: graph.makeInput(value: _GraphInputs.Phase()),
                        environment: graph.makeInput(value: .tracking()),
                        transaction: graph.makeInput(value: Transaction())
                    )
                )
            }

        var storage = toolbarStorage(id: "action")
        storage.items[0].generator = foreignGenerator
        let bridge = RootToolbarBridge()
        XCTAssertTrue(bridge.update(storage: storage))

        let host = TestViewRendererHost()
        let graph = ViewGraph(
            replaceableContent: RootToolbarHost.hostRootView(
                sceneContent: AnyView(Text("Scene")),
                bridge: bridge
            ),
            rendererHost: host
        )
        host.storage = graph

        // A root host rebuilds the erased value in its own graph. Reusing the
        // sheet bridge's weak generator here would cross graph ownership.
        graph.updateOutputs(at: .zero)

        XCTAssertNotNil(graph.rootLayoutComputer)
    }

    private func toolbarStorage(id: String) -> ToolbarStorage {
        var storage = ToolbarStorage()
        storage.configuration = ToolbarStorage.Configuration(
            customizationID: nil
        )
        storage.items = [
            ToolbarStorage.Item(
                id: ToolbarStorage.ID(id),
                placement: .automatic,
                view: AnyView(Text(id))
            ),
        ]
        return storage
    }

    private func customizableToolbarStorage() -> ToolbarStorage {
        var storage = ToolbarStorage()
        storage.configuration = ToolbarStorage.Configuration(
            customizationID: "root-toolbar"
        )
        storage.items = [
            ToolbarStorage.Item(
                id: ToolbarStorage.ID("first"),
                placement: .automatic,
                view: AnyView(Text("First"))
            ),
            ToolbarStorage.Item(
                id: ToolbarStorage.ID("second"),
                placement: .automatic,
                view: AnyView(Text("Second")),
                showsByDefault: false
            ),
        ]
        return storage
    }

    private func toolbarView(id: String) -> AnyView {
        AnyView(
            Text("Scene")
                .toolbar {
                    ToolbarItem(id: id) {
                        Text(id)
                    }
                }
        )
    }
}

private final class ToolbarRenderCounter {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}

private struct ToolbarRenderProbe: View, PrimitiveView {
    typealias Body = Never

    var counter: ToolbarRenderCounter

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        view._attribute.value.counter.increment()
        return _ViewOutputs()
    }

    static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

private final class ToolbarTestRendererHost:
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

    func requestUpdate(after: Double) {}

    func `as`<T>(_ type: T.Type) -> T? {
        self as? T
    }

    func updateRootView() {}
    func updateEnvironment() {}
    func updateSize() {}
    func updateSafeArea() {}
    func updateContainerSize() {}

    func rootToolbarStorageDidChange(_ storage: ToolbarStorage) {
        receivedToolbarStorage = storage
    }
}
