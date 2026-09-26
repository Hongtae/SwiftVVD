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
