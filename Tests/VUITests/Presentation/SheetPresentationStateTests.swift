import XCTest
@testable import VVD
@testable import VUI

final class SheetPresentationStateTests: XCTestCase {
    func testStateDrivenSheetPresentationEnqueuesModalAfterBindingSet() async throws {
        try await runStateDrivenSheetPresentationEnqueuesModalAfterBindingSet()
    }

    func testStateDrivenSheetPresentationSurvivesInactiveSiblingSheetBranch() async throws {
        try await runStateDrivenSheetPresentationSurvivesInactiveSiblingSheetBranch()
    }

    func testStateDrivenSheetPresentationSurvivesInactiveRootChainedSheet() async throws {
        try await runStateDrivenSheetPresentationSurvivesInactiveRootChainedSheet()
    }
}

@MainActor
private func runStateDrivenSheetPresentationEnqueuesModalAfterBindingSet() throws {
    var capturedBinding: Binding<Bool>?
    let view = StateDrivenSheetProbe { binding in
        capturedBinding = binding
    }
    let controller = WindowController(
        content: view,
        scene: WindowKey(namespace: .app, sceneID: SceneID(StateDrivenSheetProbe.self))
    )
    let fakeWindow = try XCTUnwrap(
        TestWindow(name: "test", style: [], delegate: nil, data: [:])
    )

    XCTAssertTrue(controller.shouldClose(window: fakeWindow))
    controller.viewGraph.updateOutputs(at: Time(seconds: 0))
    capturedBinding?.wrappedValue = true
    controller.viewGraph.updateOutputs(at: Time(seconds: 1))

    XCTAssertFalse(controller.shouldClose(window: fakeWindow))
}

@MainActor
private func runStateDrivenSheetPresentationSurvivesInactiveSiblingSheetBranch() throws {
    var capturedFirstBinding: Binding<Bool>?
    var capturedSecondBinding: Binding<Bool>?
    let view = TwoSheetProbe { first, second in
        capturedFirstBinding = first
        capturedSecondBinding = second
    }
    let controller = WindowController(
        content: view,
        scene: WindowKey(namespace: .app, sceneID: SceneID(TwoSheetProbe.self))
    )
    let fakeWindow = try XCTUnwrap(
        TestWindow(name: "test", style: [], delegate: nil, data: [:])
    )

    XCTAssertTrue(controller.shouldClose(window: fakeWindow))
    controller.viewGraph.updateOutputs(at: Time(seconds: 0))
    capturedFirstBinding?.wrappedValue = true
    XCTAssertEqual(capturedSecondBinding?.wrappedValue, false)
    controller.viewGraph.updateOutputs(at: Time(seconds: 1))

    XCTAssertFalse(controller.shouldClose(window: fakeWindow))
}

@MainActor
private func runStateDrivenSheetPresentationSurvivesInactiveRootChainedSheet() throws {
    var capturedFirstBinding: Binding<Bool>?
    var capturedSecondBinding: Binding<Bool>?
    let view = RootChainedTwoSheetProbe { first, second in
        capturedFirstBinding = first
        capturedSecondBinding = second
    }
    let controller = WindowController(
        content: view,
        scene: WindowKey(
            namespace: .app,
            sceneID: SceneID(RootChainedTwoSheetProbe.self)
        )
    )
    let fakeWindow = try XCTUnwrap(
        TestWindow(name: "test", style: [], delegate: nil, data: [:])
    )

    XCTAssertTrue(controller.shouldClose(window: fakeWindow))
    controller.viewGraph.updateOutputs(at: Time(seconds: 0))
    capturedFirstBinding?.wrappedValue = true
    XCTAssertEqual(capturedSecondBinding?.wrappedValue, false)
    controller.viewGraph.updateOutputs(at: Time(seconds: 1))

    XCTAssertFalse(controller.shouldClose(window: fakeWindow))
}

private struct StateDrivenSheetProbe: View {
    var capture: (Binding<Bool>) -> Void
    @State private var isPresented = false

    var body: some View {
        let _ = capture($isPresented)
        EmptyView()
            .sheet(isPresented: $isPresented) {
                Text("Sheet")
            }
    }
}

private struct TwoSheetProbe: View {
    var capture: (Binding<Bool>, Binding<Bool>) -> Void
    @State private var firstPresented = false
    @State private var secondPresented = false

    var body: some View {
        let _ = capture($firstPresented, $secondPresented)
        VStack {
            Text("First Host")
                .sheet(isPresented: $firstPresented) {
                    Text("First")
                }
            Text("Second Host")
                .sheet(isPresented: $secondPresented) {
                    Text("Second")
                }
        }
    }
}

private struct RootChainedTwoSheetProbe: View {
    var capture: (Binding<Bool>, Binding<Bool>) -> Void
    @State private var firstPresented = false
    @State private var secondPresented = false

    var body: some View {
        let _ = capture($firstPresented, $secondPresented)
        EmptyView()
            .sheet(isPresented: $firstPresented) {
                Text("First")
            }
            .sheet(isPresented: $secondPresented) {
                Text("Second")
            }
    }
}

@MainActor
private final class TestWindow: VVD.Window {
    var activated: Bool = false
    var visible: Bool = false
    var contentBounds: CGRect = .zero
    var windowFrame: CGRect = .zero
    var contentScaleFactor: CGFloat = 1
    var resolution: CGSize = .zero
    var origin: CGPoint = .zero
    var contentSize: CGSize = .zero
    var title: String
    weak var delegate: WindowDelegate?
    var screen: (any VVD.Screen)? { nil }
    var isValid: Bool { true }
    var platformHandle: OpaquePointer? { nil }
    var eventObservers = WindowEventObserverContainer()

    required init?(name: String, style: WindowStyle, delegate: WindowDelegate?, data: [String: Any]) {
        self.title = name
        self.delegate = delegate
    }

    func show() {}
    func hide() {}
    func activate() {}
    func minimize() {}
    func requestToClose() -> Bool { true }
    func close() {}
    func convertPointToScreen(_ point: CGPoint) -> CGPoint { point }
    func convertPointFromScreen(_ point: CGPoint) -> CGPoint { point }
}
