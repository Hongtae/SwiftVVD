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
        _ update: @escaping (inout FocusedValues) -> Void
    ) -> FocusedValueList.Item {
        FocusedValueList.Item(
            version: DisplayList.Version(forUpdate: ()),
            isFocused: true,
            update: update
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
