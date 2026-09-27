import Observation
import XCTest
@testable import VUI

final class ColorSchemeHostTests: XCTestCase {
    func testPreferredColorSchemeIsHostReadableAndRepostsRootEnvironment() throws {
        // ASSERTIONS colorSchemeHostPreferenceOwner27Observed
        // ASSERTIONS colorSchemePublicControl27Observed
        // ASSERTIONS colorSchemePrecedence27Observed
        XCTAssertTrue(PreferredColorSchemeKey._isReadableByHost)

        let recorder = ColorSchemeEnvironmentRecorder()
        let controller = WindowController(
            content: ColorSchemeEnvironmentLeaf(recorder: recorder)
                .preferredColorScheme(.dark),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self)
            )
        )

        update(controller, ticks: 0..<6)

        try controller.viewGraph.data.withCurrent {
            let environment = try XCTUnwrap(recorder.environment).value
            XCTAssertEqual(environment.colorScheme, .dark)
            let primary = Color.primary.resolve(in: environment)
            XCTAssertEqual(primary.red, 1, accuracy: 0.000_001)
            XCTAssertEqual(primary.green, 1, accuracy: 0.000_001)
            XCTAssertEqual(primary.blue, 1, accuracy: 0.000_001)
            XCTAssertEqual(primary.opacity, 216.0 / 255.0, accuracy: 0.000_001)
        }
    }

    func testPreferredColorSchemeTracksDynamicValueAndClearsToAutomatic() throws {
        // ASSERTIONS colorSchemeHostPreferenceOwner27Observed
        // ASSERTIONS colorSchemeAutomaticHost27Observed
        let model = PreferredColorSchemeModel()
        let recorder = ColorSchemeEnvironmentRecorder()
        let controller = WindowController(
            content: DynamicPreferredColorSchemeRoot(
                model: model,
                recorder: recorder
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self)
            )
        )

        update(controller, ticks: 0..<6)
        XCTAssertEqual(try scheme(in: recorder, controller: controller), .dark)

        model.scheme = .light
        Update.dispatchActions()
        update(controller, ticks: 6..<12)
        XCTAssertEqual(try scheme(in: recorder, controller: controller), .light)

        model.scheme = nil
        Update.dispatchActions()
        update(controller, ticks: 12..<18)
        XCTAssertNil(controller.environment.explicitPreferredColorScheme)
        XCTAssertEqual(try scheme(in: recorder, controller: controller), .light)
    }

    func testExplicitDescendantColorSchemeOverridesHostPreference() throws {
        // ASSERTIONS colorSchemePublicControl27Observed
        // ASSERTIONS colorSchemePrecedence27Observed
        let recorder = ColorSchemeEnvironmentRecorder()
        let controller = WindowController(
            content: ColorSchemeEnvironmentLeaf(recorder: recorder)
                .environment(\.colorScheme, .light)
                .preferredColorScheme(.dark),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self)
            )
        )

        update(controller, ticks: 0..<6)

        XCTAssertEqual(controller.environment.colorScheme, .dark)
        XCTAssertEqual(try scheme(in: recorder, controller: controller), .light)
    }

    func testSiblingPreferredColorSchemesKeepFirstValueForHost() throws {
        // ASSERTIONS colorSchemePublicControl27Observed
        // ASSERTIONS colorSchemePrecedence27Observed
        let first = ColorSchemeEnvironmentRecorder()
        let second = ColorSchemeEnvironmentRecorder()
        let controller = WindowController(
            content: HStack {
                ColorSchemeEnvironmentLeaf(recorder: first)
                    .preferredColorScheme(.dark)
                ColorSchemeEnvironmentLeaf(recorder: second)
                    .preferredColorScheme(.light)
            },
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self)
            )
        )

        update(controller, ticks: 0..<6)

        XCTAssertEqual(controller.environment.colorScheme, .dark)
        XCTAssertEqual(try scheme(in: first, controller: controller), .dark)
        XCTAssertEqual(try scheme(in: second, controller: controller), .dark)
    }

    func testBackgroundAndWindowSurfacesFollowColorScheme() {
        // ASSERTIONS colorBackgroundPalette27Observed
        let backgroundRows: [
            (ColorScheme, ColorSchemeContrast, Float)
        ] = [
            (.light, .standard, 1),
            (.light, .increased, 1),
            (.dark, .standard, 46.0 / 255.0),
            (.dark, .increased, 30.0 / 255.0),
        ]
        for (scheme, contrast, component) in backgroundRows {
            var environment = EnvironmentValues()
            environment.colorScheme = scheme
            environment._colorSchemeContrast = contrast
            let color = backgroundColor(in: environment)
            XCTAssertEqual(color.red, component, accuracy: 0.000_001)
            XCTAssertEqual(color.green, component, accuracy: 0.000_001)
            XCTAssertEqual(color.blue, component, accuracy: 0.000_001)
            XCTAssertEqual(color.opacity, 1, accuracy: 0.000_001)
        }

        let model = PreferredColorSchemeModel()
        let controller = WindowController(
            content: DynamicPreferredColorSchemeRoot(
                model: model,
                recorder: ColorSchemeEnvironmentRecorder()
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self, index: 1)
            )
        )

        update(controller, ticks: 0..<6)
        XCTAssertEqual(
            controller.configuration.backgroundColor,
            BackendColor(rgba8: .init(r: 30, g: 30, b: 30, a: 255))
        )

        model.scheme = .light
        Update.dispatchActions()
        update(controller, ticks: 6..<12)
        XCTAssertEqual(
            controller.configuration.backgroundColor,
            BackendColor(rgba8: .init(r: 255, g: 255, b: 255, a: 255))
        )
    }

    @MainActor
    func testPresentedSheetTracksDynamicPreferredColorScheme() throws {
        // ASSERTIONS colorSchemeHostPreferenceOwner27Observed
        var isPresented: Binding<Bool>?
        var usesDarkMode: Binding<Bool>?
        var observedSchemes: [ColorScheme] = []
        let controller = WindowController(
            content: DynamicPreferredColorSchemeSheetRoot(
                capturePresentation: { isPresented = $0 },
                captureDarkMode: { usesDarkMode = $0 },
                captureScheme: { observedSchemes.append($0) }
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self, index: 2)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        try XCTUnwrap(isPresented).wrappedValue = true
        controller.viewGraph.updateOutputs(at: Time(seconds: 1))
        update(controller, ticks: 1..<8)
        XCTAssertTrue(observedSchemes.contains(.light))

        try XCTUnwrap(usesDarkMode).wrappedValue = true
        Update.dispatchActions()
        update(controller, ticks: 8..<16)
        XCTAssertEqual(
            observedSchemes.last,
            .dark,
            "Observed sheet schemes: \(observedSchemes)"
        )
    }

    @MainActor
    func testNewSheetUsesLatestDynamicPreferredColorScheme() throws {
        // ASSERTIONS colorSchemeHostPreferenceOwner27Observed
        var isPresented: Binding<Bool>?
        var usesDarkMode: Binding<Bool>?
        var observedSchemes: [ColorScheme] = []
        let controller = WindowController(
            content: DynamicPreferredColorSchemeSheetRoot(
                capturePresentation: { isPresented = $0 },
                captureDarkMode: { usesDarkMode = $0 },
                captureScheme: { observedSchemes.append($0) }
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self, index: 3)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        try XCTUnwrap(usesDarkMode).wrappedValue = true
        Update.dispatchActions()
        update(controller, ticks: 1..<8)
        XCTAssertEqual(controller.environment.colorScheme, .dark)

        try XCTUnwrap(isPresented).wrappedValue = true
        Update.dispatchActions()
        update(controller, ticks: 8..<16)
        XCTAssertEqual(
            observedSchemes.last,
            .dark,
            "Observed sheet schemes: \(observedSchemes)"
        )
    }

    @MainActor
    func testItemSheetUsesLatestDynamicPreferredColorScheme() throws {
        // ASSERTIONS colorSchemePresentationBoundary27Observed
        var selectedItem: Binding<ColorSchemeSheetItem?>?
        var usesDarkMode: Binding<Bool>?
        var observedSchemes: [ColorScheme] = []
        let controller = WindowController(
            content: DynamicPreferredColorSchemeItemSheetRoot(
                capturePresentation: { selectedItem = $0 },
                captureDarkMode: { usesDarkMode = $0 },
                captureScheme: { observedSchemes.append($0) }
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self, index: 4)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        try XCTUnwrap(usesDarkMode).wrappedValue = true
        Update.dispatchActions()
        update(controller, ticks: 1..<8)
        XCTAssertEqual(controller.environment.colorScheme, .dark)

        try XCTUnwrap(selectedItem).wrappedValue = ColorSchemeSheetItem(id: 1)
        Update.dispatchActions()
        update(controller, ticks: 8..<16)
        XCTAssertEqual(
            observedSchemes.last,
            .dark,
            "Observed item sheet schemes: \(observedSchemes)"
        )
    }

    @MainActor
    func testSheetLocalPreferenceOverridesAndRestoresInheritedScheme() throws {
        // ASSERTIONS colorSchemePresentationBoundary27Observed
        var isPresented: Binding<Bool>?
        var sheetScheme: Binding<ColorScheme?>?
        var observedSchemes: [ColorScheme] = []
        let controller = WindowController(
            content: PreferredColorSchemeSheetOverrideRoot(
                capturePresentation: { isPresented = $0 },
                captureSheetScheme: { sheetScheme = $0 },
                captureScheme: { observedSchemes.append($0) }
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self, index: 5)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        try XCTUnwrap(isPresented).wrappedValue = true
        Update.dispatchActions()
        update(controller, ticks: 1..<8)
        XCTAssertEqual(
            observedSchemes.last,
            .light,
            "Observed sheet override schemes: \(observedSchemes)"
        )

        try XCTUnwrap(sheetScheme).wrappedValue = nil
        Update.dispatchActions()
        update(controller, ticks: 8..<16)
        XCTAssertEqual(
            observedSchemes.last,
            .dark,
            "Observed restored sheet schemes: \(observedSchemes)"
        )
    }

    @MainActor
    func testAlertInheritsPreferredColorScheme() throws {
        // ASSERTIONS colorSchemePresentationBoundary27Observed
        var isPresented: Binding<Bool>?
        var observedSchemes: [ColorScheme] = []
        let controller = WindowController(
            content: PreferredColorSchemeAlertRoot(
                capturePresentation: { isPresented = $0 },
                captureScheme: { observedSchemes.append($0) }
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self, index: 6)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        try XCTUnwrap(isPresented).wrappedValue = true
        Update.dispatchActions()
        update(controller, ticks: 1..<10)
        XCTAssertEqual(
            observedSchemes.last,
            .dark,
            "Observed alert schemes: \(observedSchemes)"
        )
    }

    @MainActor
    func testConfirmationDialogInheritsPreferredColorScheme() throws {
        // ASSERTIONS colorSchemePresentationBoundary27Observed
        var isPresented: Binding<Bool>?
        var observedSchemes: [ColorScheme] = []
        let controller = WindowController(
            content: PreferredColorSchemeConfirmationDialogRoot(
                capturePresentation: { isPresented = $0 },
                captureScheme: { observedSchemes.append($0) }
            ),
            scene: WindowKey(
                namespace: .app,
                sceneID: SceneID(ColorSchemeHostTests.self, index: 7)
            )
        )

        controller.viewGraph.updateOutputs(at: .zero)
        try XCTUnwrap(isPresented).wrappedValue = true
        Update.dispatchActions()
        update(controller, ticks: 1..<10)
        XCTAssertEqual(
            observedSchemes.last,
            .dark,
            "Observed confirmation-dialog schemes: \(observedSchemes)"
        )
    }

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
                contentSize: CGSize(width: 240, height: 120),
                redraw: &redraw
            ) { _, _ in }
        }
    }

    private func scheme(
        in recorder: ColorSchemeEnvironmentRecorder,
        controller: WindowController
    ) throws -> ColorScheme {
        try controller.viewGraph.data.withCurrent {
            try XCTUnwrap(recorder.environment).value.colorScheme
        }
    }

    private func backgroundColor(
        in environment: EnvironmentValues
    ) -> Color.Resolved {
        var shape = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 0),
            environment: environment
        )
        BackgroundStyle()._apply(to: &shape)
        guard case let .color(color) = shape.result else {
            XCTFail("BackgroundStyle must resolve a color")
            return Color.clear.resolve(in: environment)
        }
        return color.resolve(in: environment)
    }

}

@Observable
private final class PreferredColorSchemeModel {
    var scheme: ColorScheme? = .dark
}

private struct DynamicPreferredColorSchemeRoot: View {
    var model: PreferredColorSchemeModel
    var recorder: ColorSchemeEnvironmentRecorder

    var body: some View {
        ColorSchemeEnvironmentLeaf(recorder: recorder)
            .preferredColorScheme(model.scheme)
    }
}

private struct DynamicPreferredColorSchemeSheetRoot: View {
    let capturePresentation: (Binding<Bool>) -> Void
    let captureDarkMode: (Binding<Bool>) -> Void
    let captureScheme: (ColorScheme) -> Void
    @State private var isPresented = false
    @State private var usesDarkMode = false

    var body: some View {
        let _ = capturePresentation($isPresented)
        let _ = captureDarkMode($usesDarkMode)
        Color.clear
            .sheet(isPresented: $isPresented) {
                ColorSchemeSheetReader(capture: captureScheme)
            }
            .preferredColorScheme(usesDarkMode ? .dark : .light)
    }
}

private struct ColorSchemeSheetReader: View {
    @Environment(\.colorScheme) private var colorScheme
    let capture: (ColorScheme) -> Void

    var body: some View {
        let _ = capture(colorScheme)
        Text("Sheet")
    }
}

private struct ColorSchemeSheetItem: Identifiable {
    var id: Int
}

private struct DynamicPreferredColorSchemeItemSheetRoot: View {
    let capturePresentation: (Binding<ColorSchemeSheetItem?>) -> Void
    let captureDarkMode: (Binding<Bool>) -> Void
    let captureScheme: (ColorScheme) -> Void
    @State private var selectedItem: ColorSchemeSheetItem?
    @State private var usesDarkMode = false

    var body: some View {
        let _ = capturePresentation($selectedItem)
        let _ = captureDarkMode($usesDarkMode)
        Color.clear
            .sheet(item: $selectedItem) { _ in
                ColorSchemeSheetReader(capture: captureScheme)
            }
            .environment(\.modalSessionUsingPlatformWindow, true)
            .preferredColorScheme(usesDarkMode ? .dark : .light)
    }
}

private struct PreferredColorSchemeSheetOverrideRoot: View {
    let capturePresentation: (Binding<Bool>) -> Void
    let captureSheetScheme: (Binding<ColorScheme?>) -> Void
    let captureScheme: (ColorScheme) -> Void
    @State private var isPresented = false
    @State private var sheetScheme: ColorScheme? = .light

    var body: some View {
        let _ = capturePresentation($isPresented)
        let _ = captureSheetScheme($sheetScheme)
        Color.clear
            .sheet(isPresented: $isPresented) {
                ColorSchemeSheetReader(capture: captureScheme)
                    .preferredColorScheme(sheetScheme)
            }
            .preferredColorScheme(.dark)
    }
}

private struct PreferredColorSchemeAlertRoot: View {
    let capturePresentation: (Binding<Bool>) -> Void
    let captureScheme: (ColorScheme) -> Void
    @State private var isPresented = false

    var body: some View {
        let _ = capturePresentation($isPresented)
        Color.clear
            .alert("Alert", isPresented: $isPresented) {
                Button("OK") {}
            } message: {
                ColorSchemeAlertReader(capture: captureScheme)
            }
            .environment(\.modalSessionUsingPlatformWindow, false)
            .preferredColorScheme(.dark)
    }
}

private struct ColorSchemeAlertReader: View {
    @Environment(\.colorScheme) private var colorScheme
    let capture: (ColorScheme) -> Void

    var body: some View {
        let _ = capture(colorScheme)
        Text("Message")
    }
}

private struct PreferredColorSchemeConfirmationDialogRoot: View {
    let capturePresentation: (Binding<Bool>) -> Void
    let captureScheme: (ColorScheme) -> Void
    @State private var isPresented = false

    var body: some View {
        let _ = capturePresentation($isPresented)
        Color.clear
            .confirmationDialog(
                "Confirmation",
                isPresented: $isPresented,
                titleVisibility: .visible
            ) {
                Button("OK") {}
            } message: {
                ColorSchemeConfirmationDialogReader(capture: captureScheme)
            }
            .environment(\.modalSessionUsingPlatformWindow, false)
            .preferredColorScheme(.dark)
    }
}

private struct ColorSchemeConfirmationDialogReader: View {
    @Environment(\.colorScheme) private var colorScheme
    let capture: (ColorScheme) -> Void

    var body: some View {
        let _ = capture(colorScheme)
        Text("Message")
    }
}

private final class ColorSchemeEnvironmentRecorder {
    var environment: Attribute<EnvironmentValues>?
}

private struct ColorSchemeEnvironmentLeaf: View, TestPrimitiveView {
    var recorder: ColorSchemeEnvironmentRecorder

    typealias Body = Never

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        view._attribute.value.recorder.environment =
            inputs.base.cachedEnvironment.value.environment
        return _ViewOutputs()
    }
}
