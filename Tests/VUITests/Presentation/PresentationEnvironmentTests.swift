import XCTest
@testable import VUI

final class PresentationEnvironmentTests: XCTestCase {
    @MainActor
    func testSheetContentInheritsAndTracksEnvironmentAtPresentationSite() {
        var isPresented: Binding<Bool>?
        var environmentValue: Binding<String>?
        var observedValues: [String] = []
        let controller = WindowController(
            content: SheetEnvironmentHost(
                captureBindings: {
                    isPresented = $0
                    environmentValue = $1
                },
                captureEnvironment: { observedValues.append($0) }
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(SheetEnvironmentHost.self)
            )
        )

        controller.viewGraph.updateOutputs(at: Time(seconds: 0))
        isPresented?.wrappedValue = true
        controller.viewGraph.updateOutputs(at: Time(seconds: 1))
        var redraw = false
        let withGraphicsContext: WindowContext.WithGraphicsContext = { _, _ in }
        controller.updateView(
            tick: 1,
            delta: 1 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(1),
            contentSize: CGSize(width: 320, height: 240),
            redraw: &redraw,
            withGraphicsContext
        )

        XCTAssertTrue(
            observedValues.contains("sheet-inherited"),
            "Observed sheet environment values: \(observedValues)"
        )

        environmentValue?.wrappedValue = "sheet-updated"
        controller.viewGraph.updateOutputs(at: Time(seconds: 2))
        controller.updateView(
            tick: 2,
            delta: 2 - controller.animationTimestamp.seconds,
            date: controller.date.addingTimeInterval(2),
            contentSize: CGSize(width: 320, height: 240),
            redraw: &redraw,
            withGraphicsContext
        )

        XCTAssertTrue(
            observedValues.contains("sheet-updated"),
            "Observed updated sheet environment values: \(observedValues)"
        )
    }

    @MainActor
    func testContextMenuPopupInheritsAndTracksSourceEnvironment() throws {
        let parent = WindowController(
            content: EmptyView(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ContextMenuEnvironmentProbe.self)
            )
        )

        try parent.viewGraph.data.withCurrent {
            let graph = parent.viewGraph.data.graph
            var initial = EnvironmentValues()
            initial.presentationEnvironmentProbeValue = "popup-initial"
            initial.presentationChildUsingPlatformWindow = false
            let environment = graph.makeInput(value: initial)
            let phase = try XCTUnwrap(parent.viewGraph.phaseAttr)
            let itemList = graph.makeInput(value: PlatformItemList())
            let responder = AGSubgraph.withCurrent(
                parent.viewGraph.data.rootSubgraph
            ) {
                ContextMenuResponder(
                    inputs: makeContextMenuViewInputs(
                        graph: graph,
                        environment: environment,
                        phase: phase
                    ),
                    itemList: itemList.asWeak(),
                    environment: environment,
                    phase: phase
                )
            }

            responder.present(from: parent, at: .zero)
            XCTAssertEqual(
                try presentedEnvironment(in: parent),
                "popup-initial"
            )

            var updated = initial
            updated.presentationEnvironmentProbeValue = "popup-updated"
            environment.setValue(updated)
            graph.inbox.drain()
            graph.drainActions()
            drainPresentationEnvironmentUpdates(in: parent)

            XCTAssertEqual(
                try presentedEnvironment(in: parent),
                "popup-updated"
            )
        }
    }

    // ASSERTIONS viewGraphHostEnvironmentWrapperOwnershipObserved
    @MainActor
    func testNestedPopupTracksParentPresentationEnvironment() throws {
        var initial = EnvironmentValues()
        initial.presentationEnvironmentProbeValue = "nested-initial"
        let root = PopupWindowController(
            content: EmptyView(),
            environment: initial,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(NestedPopupEnvironmentProbe.self)
            ),
            usesPlatformWindow: false
        )
        let child = PopupWindowController(
            content: EmptyView(),
            environment: initial,
            scene: root.scene,
            usesPlatformWindow: false
        )
        root.addPresentationChild(child: child)

        var updated = initial
        updated.presentationEnvironmentProbeValue = "nested-updated"
        var sourcePhase = _GraphInputs.Phase()
        sourcePhase.resetSeed = 4
        root.setPresentationEnvironment(
            updated,
            viewPhase: ViewGraphHost.Phase(base: sourcePhase)
        )
        drainPresentationEnvironmentUpdates(in: root)

        XCTAssertEqual(
            child.environment.presentationEnvironmentProbeValue,
            "nested-updated"
        )
        XCTAssertEqual(
            root.viewGraph.parentPhase?.value,
            sourcePhase.value
        )
        XCTAssertEqual(
            child.viewGraph.parentPhase?.value,
            sourcePhase.value
        )
    }

    // ASSERTIONS viewGraphHostEnvironmentWrapperOwnershipObserved
    @MainActor
    func testContextMenuSubmenuReadsParentPopupPhaseFromItsOwningGraph() throws {
        var leaf = PlatformItemList.Item(systemItem: .button)
        leaf.text = NSAttributedString(string: "Leaf")
        leaf.selectionBehavior = .init(
            isMomentary: true,
            isContainerSelection: true,
            yieldsToContainerSelection: false,
            isPickerOption: false,
            visualStyle: .plain,
            onSelect: {},
            onDeselect: nil,
            springLoadingBehavior: .automatic
        )
        var submenu = PlatformItemList.Item(systemItem: .menu)
        submenu.text = NSAttributedString(string: "Submenu")
        submenu.platformIdentifier = "submenu"
        submenu.children = PlatformItemList(items: [leaf])
        let items = contextMenuPresentationItems([submenu])
        let presentedSubmenu = try XCTUnwrap(items.first)

        let actions = ContextMenuPopupActions()
        let session = ContextMenuPresentationSession()
        let root = ContextMenuWindowController(
            content: EmptyView(),
            environment: EnvironmentValues(),
            viewPhase: ViewGraphHost.Phase(),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ContextMenuSubmenuPhaseProbe.self)
            ),
            anchor: .zero,
            items: items,
            actions: actions,
            usesPlatformWindow: false,
            session: session
        )
        root.viewGraph.updateOutputs(at: .zero)
        XCTAssertNil(_AGGraph.current)

        root.openSubmenu(
            presentedSubmenu,
            at: CGPoint(x: 20, y: 10)
        )

        var presentedChildren: [PresentationChildWindowController] = []
        root.forEachPresentationChild { presentedChildren.append($0) }
        XCTAssertEqual(presentedChildren.count, 1)
        presentedChildren[0].viewGraph.updateOutputs(at: .zero)
        XCTAssertNotNil(presentedChildren[0].viewGraph.parentPhase)
        root.dismissAllPresentationChildren()
    }

    @MainActor
    func testPresentationEnvironmentUpdateDoesNotEnterActiveChildGraph() {
        var initial = EnvironmentValues()
        initial.presentationEnvironmentProbeValue = "concurrent-initial"
        let root = PopupWindowController(
            content: EmptyView(),
            environment: initial,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ConcurrentPresentationEnvironmentProbe.self)
            ),
            usesPlatformWindow: false
        )
        let child = PopupWindowController(
            content: EmptyView(),
            environment: initial,
            scene: root.scene,
            usesPlatformWindow: true
        )
        root.addPresentationChild(child: child)

        let enteredChildGraph = DispatchSemaphore(value: 0)
        let releaseChildGraph = DispatchSemaphore(value: 0)
        let childGraphExited = DispatchSemaphore(value: 0)
        // This test deliberately transfers one graph handle to the worker that
        // owns its active current scope; production GraphHost.Data stays
        // non-Sendable because this carrier is only a test synchronization aid.
        let childGraph = UncheckedSendableValue(child.viewGraph.data)
        DispatchQueue.global().async {
            childGraph.value.withCurrent {
                enteredChildGraph.signal()
                releaseChildGraph.wait()
            }
            childGraphExited.signal()
        }

        XCTAssertEqual(enteredChildGraph.wait(timeout: .now() + 2), .success)

        var updated = initial
        updated.presentationEnvironmentProbeValue = "concurrent-updated"
        root.setPresentationEnvironment(
            updated,
            viewPhase: ViewGraphHost.Phase()
        )

        releaseChildGraph.signal()
        XCTAssertEqual(childGraphExited.wait(timeout: .now() + 2), .success)
        drainPresentationEnvironmentUpdates(in: root)

        XCTAssertEqual(
            child.environment.presentationEnvironmentProbeValue,
            "concurrent-updated"
        )
    }

    @MainActor
    private func presentedEnvironment(in parent: WindowController) throws -> String {
        var values: [String] = []
        parent.forEachPresentationChild {
            values.append($0.environment.presentationEnvironmentProbeValue)
        }
        return try XCTUnwrap(values.last)
    }

    @MainActor
    private func drainPresentationEnvironmentUpdates(in controller: WindowController) {
        _ = controller.viewGraph.data.withCurrent {
            controller.viewGraph.data.graph.inbox.drain()
        }
        controller.forEachPresentationChild {
            drainPresentationEnvironmentUpdates(in: $0)
        }
    }
}

private struct UncheckedSendableValue<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

private struct ContextMenuSubmenuPhaseProbe {}

private struct PresentationEnvironmentProbeKey: EnvironmentKey {
    static let defaultValue = "default"
}

private extension EnvironmentValues {
    var presentationEnvironmentProbeValue: String {
        get { self[PresentationEnvironmentProbeKey.self] }
        set { self[PresentationEnvironmentProbeKey.self] = newValue }
    }
}

private struct SheetEnvironmentHost: View {
    let captureBindings: (Binding<Bool>, Binding<String>) -> Void
    let captureEnvironment: (String) -> Void
    @State private var isPresented = false
    @State private var environmentValue = "sheet-inherited"

    var body: some View {
        let _ = captureBindings($isPresented, $environmentValue)
        Color.clear
            .frame(width: 100, height: 40)
            .sheet(isPresented: $isPresented) {
                SheetEnvironmentReader(capture: captureEnvironment)
            }
            .environment(
                \.presentationEnvironmentProbeValue,
                environmentValue
            )
    }
}

private struct SheetEnvironmentReader: View {
    @Environment(\.presentationEnvironmentProbeValue) private var value
    let capture: (String) -> Void

    var body: some View {
        let _ = capture(value)
        Text(value)
    }
}

private final class ContextMenuEnvironmentProbe {}
private final class NestedPopupEnvironmentProbe {}
private final class ConcurrentPresentationEnvironmentProbe {}

private func makeContextMenuViewInputs(
    graph: _AGGraph,
    environment: Attribute<EnvironmentValues>,
    phase: Attribute<_GraphInputs.Phase>
) -> _ViewInputs {
    _ViewInputs(
        base: _GraphInputs(
            time: graph.makeInput(value: Time.zero),
            phase: phase,
            environment: environment,
            transaction: graph.makeInput(value: Transaction())
        ),
        customInputs: PropertyList(),
        preferences: PreferencesInputs(
            keys: PreferenceKeys(),
            hostKeys: graph.makeInput(value: PreferenceKeys())
        ),
        transform: graph.makeInput(value: ViewTransform.identity),
        position: graph.makeInput(value: CGPoint.zero),
        containerPosition: graph.makeInput(value: CGPoint.zero),
        size: graph.makeInput(
            value: ViewSize(CGSize(width: 100, height: 40))
        ),
        safeAreaInsets: OptionalAttribute(),
        containerSize: OptionalAttribute(),
        stackOrientation: nil
    )
}
