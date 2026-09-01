import XCTest
@testable import VUI

final class FocusedValuesTests: XCTestCase {
    func testListResolutionAppliesLaterItemsAsHigherPriority() {
        // ASSERTIONS commandsFocusedSceneValueHierarchyRuntimeObserved
        let list = FocusedValueList(
            items: [
                item { $0.focusedValuesTestTitle = "Descendant" },
                item { $0.focusedValuesTestTitle = "Outer" },
            ]
        )

        let values = FocusedValues(resolving: list)

        XCTAssertEqual(values.focusedValuesTestTitle, "Outer")
    }

    func testResolutionPrefersDeeperSceneAndFocusedInnerView() {
        // ASSERTIONS commandsFocusedValueScopeDepthArbitrationRuntimeObserved
        // ASSERTIONS commandsOrdinaryFocusedValueSameKeyRuntimeObserved
        let scenes = FocusedValues(
            resolving: FocusedValueList(
                items: [
                    item(sceneDepth: 0) {
                        $0.focusedValuesTestTitle = "Root Scene"
                    },
                    item(sceneDepth: 1) {
                        $0.focusedValuesTestTitle = "Destination Scene"
                    },
                ]
            )
        )
        XCTAssertEqual(
            scenes.focusedValuesTestTitle,
            "Destination Scene"
        )

        let ordinary = FocusedValues(
            resolving: FocusedValueList(
                items: [
                    item(isFocused: true) {
                        $0.focusedValuesTestTitle = "Inner"
                    },
                    item(isFocused: true) {
                        $0.focusedValuesTestTitle = "Outer"
                    },
                    item(sceneDepth: 0) {
                        $0.focusedValuesTestTitle = "Scene"
                    },
                ]
            )
        )
        XCTAssertEqual(ordinary.focusedValuesTestTitle, "Inner")

        let unfocused = FocusedValues(
            resolving: FocusedValueList(
                items: [
                    item(isFocused: false) {
                        $0.focusedValuesTestTitle = "Unfocused"
                    },
                    item(sceneDepth: 0) {
                        $0.focusedValuesTestTitle = "Scene"
                    },
                ]
            )
        )
        XCTAssertEqual(unfocused.focusedValuesTestTitle, "Scene")
    }

    func testPresentationOverrideRetainsUnshadowedRootValues() {
        // ASSERTIONS commandsPresentationChildOverridesRootFocusRuntimeObserved
        var root = FocusedValues(
            resolving: FocusedValueList(
                items: [
                    item { values in
                        values.focusedValuesTestTitle = "Root"
                        values.focusedValuesRootOnlyValue = 42
                    }
                ]
            )
        )
        let presentation = FocusedValues(
            resolving: FocusedValueList(
                items: [
                    item { $0.focusedValuesTestTitle = "Presentation" }
                ]
            )
        )

        root.override(with: presentation)

        XCTAssertEqual(root.focusedValuesTestTitle, "Presentation")
        XCTAssertEqual(root.focusedValuesRootOnlyValue, 42)
    }

    @MainActor
    func testWindowGraphPublishesOuterFocusedSceneValue() {
        // ASSERTIONS commandsFocusedSceneValueHierarchyRuntimeObserved
        let content = VStack {
            Text("Descendant")
                .focusedSceneValue(
                    \.focusedValuesTestTitle,
                    "Descendant"
                )
        }
        .focusedSceneValue(\.focusedValuesTestTitle, "Outer")
        let controller = WindowController(
            content: content,
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(FocusedValuesTests.self)
            )
        )
        let startDate = controller.date

        controller.viewGraph.updateOutputs(at: .zero)
        update(
            controller,
            tick: 1,
            seconds: 1,
            startDate: startDate
        )

        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Outer"
        )
    }

    @MainActor
    func testOrdinaryFocusedValueFollowsTextFieldFocusTransfer() throws {
        // ASSERTIONS commandsOrdinaryFocusedValueResponderRuntimeObserved
        // ASSERTIONS commandsOrdinaryFocusedValueSameKeyRuntimeObserved
        let model = FocusedValuesTextFieldModel()
        let controller = FocusedValuesTextFieldController(model: model)
        let startDate = controller.date

        func render(_ tick: UInt64) {
            update(
                controller,
                tick: tick,
                seconds: Double(tick),
                startDate: startDate
            )
            Update.dispatchActions()
        }

        render(0)
        render(1)
        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Scene"
        )

        let focus = try XCTUnwrap(model.focusBinding)
        focus.wrappedValue = .first
        render(2)
        render(3)
        render(4)
        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "First Inner"
        )

        focus.wrappedValue = .second
        render(5)
        render(6)
        render(7)
        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Second Inner"
        )

        focus.wrappedValue = nil
        render(8)
        render(9)
        render(10)
        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Scene"
        )
    }

    @MainActor
    func testFocusedSceneValueVersionChangesOnlyWithContent() throws {
        // ASSERTIONS commandsFocusedValueVersionGatingRuntimeObserved
        var title: Binding<String>?
        var unrelated: Binding<Int>?
        let controller = WindowController(
            content: FocusedValueVersionHost { capturedTitle, capturedUnrelated in
                title = capturedTitle
                unrelated = capturedUnrelated
            },
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(FocusedValueVersionHost.self)
            )
        )
        let startDate = controller.date

        controller.viewGraph.updateOutputs(at: .zero)
        update(controller, tick: 1, seconds: 1, startDate: startDate)
        update(controller, tick: 2, seconds: 2, startDate: startDate)

        let initialVersion = controller.resolvedFocusedValues.version
        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Initial"
        )

        try XCTUnwrap(unrelated).wrappedValue += 1
        update(controller, tick: 3, seconds: 3, startDate: startDate)
        update(controller, tick: 4, seconds: 4, startDate: startDate)

        XCTAssertEqual(
            controller.resolvedFocusedValues.version,
            initialVersion
        )

        try XCTUnwrap(title).wrappedValue = "Updated"
        update(controller, tick: 5, seconds: 5, startDate: startDate)
        update(controller, tick: 6, seconds: 6, startDate: startDate)

        XCTAssertNotEqual(
            controller.resolvedFocusedValues.version,
            initialVersion
        )
        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Updated"
        )
    }

    @MainActor
    func testActiveModalOverridesAndThenRestoresRootFocusedValues() throws {
        // ASSERTIONS commandsPresentationChildFocusRuntimeObserved
        // ASSERTIONS commandsPresentationChildOverridesRootFocusRuntimeObserved
        var isPresented: Binding<Bool>?
        let controller = WindowController(
            content: FocusedValuesSheetHost {
                isPresented = $0
            },
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(FocusedValuesSheetHost.self)
            )
        )
        let startDate = controller.date

        controller.viewGraph.updateOutputs(at: .zero)
        update(controller, tick: 1, seconds: 1, startDate: startDate)
        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Root"
        )

        try XCTUnwrap(isPresented).wrappedValue = true
        controller.viewGraph.updateOutputs(at: Time(seconds: 2))
        update(controller, tick: 2, seconds: 2, startDate: startDate)
        update(controller, tick: 3, seconds: 3, startDate: startDate)
        update(controller, tick: 4, seconds: 4, startDate: startDate)

        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Presentation"
        )

        controller.dismissAllModalWindows()
        update(controller, tick: 5, seconds: 5, startDate: startDate)
        update(controller, tick: 6, seconds: 6, startDate: startDate)
        update(controller, tick: 7, seconds: 7, startDate: startDate)

        XCTAssertEqual(
            controller.resolvedFocusedValues.focusedValuesTestTitle,
            "Root"
        )
    }

    private func item(
        sceneDepth: Int = 0,
        _ update: @escaping (inout FocusedValues) -> Void
    ) -> FocusedValueList.Item {
        FocusedValueList.Item(
            version: DisplayList.Version(forUpdate: ()),
            isFocused: false,
            update: { values in
                values.storageOptions = [.scene]
                values.navigationDepth = sceneDepth
                update(&values)
            }
        )
    }

    private func item(
        isFocused: Bool,
        _ update: @escaping (inout FocusedValues) -> Void
    ) -> FocusedValueList.Item {
        FocusedValueList.Item(
            version: DisplayList.Version(forUpdate: ()),
            isFocused: isFocused,
            update: { values in
                values.storageOptions = isFocused
                    ? [.inFocusedViewHierarchy]
                    : []
                update(&values)
            }
        )
    }

    @MainActor
    private func update(
        _ controller: WindowController,
        tick: UInt64,
        seconds: Double,
        startDate: Date
    ) {
        var redraw = false
        controller.updateView(
            tick: tick,
            delta: 1,
            date: startDate.addingTimeInterval(seconds),
            contentSize: CGSize(width: 320, height: 240),
            redraw: &redraw,
            { _, _ in }
        )
    }
}

private struct FocusedValuesTestTitleKey: FocusedValueKey {
    typealias Value = String
}

private struct FocusedValuesRootOnlyKey: FocusedValueKey {
    typealias Value = Int
}

private extension FocusedValues {
    var focusedValuesTestTitle: String? {
        get { self[FocusedValuesTestTitleKey.self] }
        set { self[FocusedValuesTestTitleKey.self] = newValue }
    }

    var focusedValuesRootOnlyValue: Int? {
        get { self[FocusedValuesRootOnlyKey.self] }
        set { self[FocusedValuesRootOnlyKey.self] = newValue }
    }
}

private struct FocusedValuesSheetHost: View {
    let capture: (Binding<Bool>) -> Void
    @State private var isPresented = false

    var body: some View {
        let _ = capture($isPresented)
        Text("Root")
            .focusedSceneValue(\.focusedValuesTestTitle, "Root")
            .sheet(isPresented: $isPresented) {
                Text("Presentation")
                    .focusedSceneValue(
                        \.focusedValuesTestTitle,
                        "Presentation"
                    )
            }
    }
}

private struct FocusedValueVersionHost: View {
    let capture: (Binding<String>, Binding<Int>) -> Void
    @State private var title = "Initial"
    @State private var unrelated = 0

    var body: some View {
        let _ = capture($title, $unrelated)
        Text(verbatim: "Unrelated \(unrelated)")
            .focusedSceneValue(\.focusedValuesTestTitle, title)
    }
}

private enum FocusedValuesTextFieldTarget: Hashable {
    case first
    case second
}

private final class FocusedValuesTextFieldModel {
    var first = "First"
    var second = "Second"
    var focusBinding: FocusState<FocusedValuesTextFieldTarget?>.Binding?

    var firstBinding: Binding<String> {
        Binding(
            get: { self.first },
            set: { self.first = $0 }
        )
    }

    var secondBinding: Binding<String> {
        Binding(
            get: { self.second },
            set: { self.second = $0 }
        )
    }
}

private struct FocusedValuesTextFieldHost: View {
    let model: FocusedValuesTextFieldModel
    @FocusState private var focused: FocusedValuesTextFieldTarget?

    var body: some View {
        let _ = model.focusBinding = $focused
        VStack {
            TextField("First", text: model.firstBinding)
                .focused($focused, equals: .first)
                .focusedValue(
                    \.focusedValuesTestTitle,
                    "First Inner"
                )
                .frame(width: 300)
                .focusedValue(
                    \.focusedValuesTestTitle,
                    "First Outer"
                )
            TextField("Second", text: model.secondBinding)
                .focused($focused, equals: .second)
                .focusedValue(
                    \.focusedValuesTestTitle,
                    "Second Inner"
                )
                .frame(width: 300)
                .focusedValue(
                    \.focusedValuesTestTitle,
                    "Second Outer"
                )
        }
        .focusedSceneValue(\.focusedValuesTestTitle, "Scene")
        .environment(\.defaultFontRenderingMode, .vector())
    }
}

@MainActor
private final class FocusedValuesTextFieldController: WindowController,
    @unchecked Sendable {
    init(model: FocusedValuesTextFieldModel) {
        super.init(
            content: FocusedValuesTextFieldHost(model: model),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(FocusedValuesTextFieldController.self)
            )
        )
    }
}
