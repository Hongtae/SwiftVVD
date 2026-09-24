import Foundation
import XCTest
@testable import VUI

// ASSERTIONS textCasePublic27Observed

final class TextCaseOwnerTests: XCTestCase {
    private var previousContext: (any AppContext)?
    private var sceneResources = SceneResources()

    override func setUp() {
        previousContext = appContext
        appContext = StyleTestAppContext()
        sceneResources = SceneResources()
    }

    override func tearDown() {
        appContext = previousContext
        previousContext = nil
    }

    func testViewModifierPublishesNearestEnvironmentValue() {
        XCTAssertNil(resolvedValue { $0 })
        XCTAssertEqual(
            resolvedValue { $0.textCase(.uppercase) },
            .uppercase
        )
        XCTAssertEqual(
            resolvedValue { $0.textCase(.lowercase) },
            .lowercase
        )
        XCTAssertEqual(
            resolvedValue {
                $0.textCase(.uppercase).textCase(.lowercase)
            },
            .uppercase
        )
        XCTAssertEqual(
            resolvedValue {
                $0.textCase(.lowercase).textCase(.uppercase)
            },
            .lowercase
        )
        XCTAssertEqual(
            resolvedValue { $0.textCase(.uppercase).textCase(nil) },
            .uppercase
        )
        XCTAssertNil(
            resolvedValue { $0.textCase(nil).textCase(.uppercase) }
        )
    }

    func testResolvedTextConvertsEachStorageWithTheEnvironmentLocale() throws {
        let source = "AbC iIıİ ß é Σς"
        let rows: [(Text.Case?, String, String)] = [
            (nil, "en_US", source),
            (.uppercase, "en_US", "ABC IIIİ SS É ΣΣ"),
            (.lowercase, "en_US", "abc iiıi̇ ß é σς"),
            (.uppercase, "tr_TR", "ABC İIIİ SS É ΣΣ"),
            (.lowercase, "tr_TR", "abc iııi ß é σς"),
        ]

        for (textCase, locale, expected) in rows {
            var environment = resolutionEnvironment(locale: locale)
            environment.textCase = textCase
            for text in [
                Text(verbatim: source),
                Text(AttributedString(source)),
                Text("AbC iIıİ ß é Σς"),
            ] {
                XCTAssertEqual(
                    strings(try resolve(text, environment: environment))
                        .joined(),
                    expected
                )
            }
        }
    }

    func testAttributedExpansionRetainsTheSourceRunStyle() throws {
        var value = AttributedString("aßb")
        let sharpS = value.index(afterCharacter: value.startIndex)..<value.index(
            value.startIndex,
            offsetByCharacters: 2
        )
        value[sharpS].foregroundColor = VUI.Color.red

        var environment = resolutionEnvironment(locale: "en_US")
        environment.textCase = .uppercase
        let rows = styledRows(
            try resolve(Text(value), environment: environment)
        )
        let red = VUI.Color.red.resolve(in: environment)

        XCTAssertEqual(rows.map(\.string), ["A", "SS", "B"])
        XCTAssertNotEqual(rows[0].color?.resolve(in: environment), red)
        XCTAssertEqual(rows[1].color?.resolve(in: environment), red)
        XCTAssertNotEqual(rows[2].color?.resolve(in: environment), red)
    }

    func testResolutionVersionReadsLocaleOnlyForAnActiveCase() {
        let text = Text(verbatim: "iI")
        let date = Date(timeIntervalSince1970: 0)
        var english = resolutionEnvironment(locale: "en_US")
        var turkish = resolutionEnvironment(locale: "tr_TR")

        XCTAssertEqual(
            text._resolutionVersion(in: english, referenceDate: date),
            text._resolutionVersion(in: turkish, referenceDate: date)
        )

        english.textCase = .uppercase
        turkish.textCase = .uppercase
        XCTAssertNotEqual(
            text._resolutionVersion(in: english, referenceDate: date),
            text._resolutionVersion(in: turkish, referenceDate: date)
        )
    }

    private func resolutionEnvironment(locale: String) -> EnvironmentValues {
        var environment = EnvironmentValues()
        environment.locale = Locale(identifier: locale)
        environment.font = .system(size: 23)
        environment.defaultFontRenderingMode = .vector()
        return environment
    }

    private func resolve(
        _ text: Text,
        environment: EnvironmentValues
    ) throws -> ResolvedTextSource {
        try XCTUnwrap(
            text._resolve(
                context: GraphTextResolutionContext(
                    environment: environment,
                    sceneResources: sceneResources
                ),
                referenceDate: Date(timeIntervalSince1970: 0)
            )
        )
    }

    private func strings(_ source: ResolvedTextSource) -> [String] {
        source.runs.compactMap { run in
            guard case let .styledText(_, string, _, _) = run else {
                return nil
            }
            return string
        }
    }

    private func styledRows(
        _ source: ResolvedTextSource
    ) -> [(string: String, color: Color?)] {
        source.runs.compactMap { run in
            guard case let .styledText(_, string, _, attributes) = run else {
                return nil
            }
            return (string, attributes.foregroundColor)
        }
    }

    private func resolvedValue<Content: View>(
        transform: (TextCaseProbe) -> Content
    ) -> Text.Case? {
        let recorder = TextCaseRecorder()
        let content = transform(TextCaseProbe(recorder: recorder))
        let graph = _AGGraph()

        _AGGraph.withCurrent(graph) {
            let source = graph.makeInput(value: content)
            _ = Content._makeView(
                view: _GraphValue(_attribute: source),
                inputs: makeViewInputs(graph: graph)
            )
        }

        XCTAssertTrue(recorder.didRecord)
        return recorder.value
    }

    private func makeViewInputs(graph: _AGGraph) -> _ViewInputs {
        let base = _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: .zero),
            containerPosition: graph.makeInput(value: .zero),
            size: graph.makeInput(value: ViewSize(width: 0, height: 0)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}

private final class TextCaseRecorder {
    var didRecord = false
    var value: Text.Case?
}

private struct TextCaseProbe: View, TestPrimitiveView {
    typealias Body = Never

    let recorder: TextCaseRecorder

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("TextCaseProbe._makeView requires an active graph.")
        }
        let value = view._attribute.value
        value.recorder.didRecord = true
        value.recorder.value = inputs.base.cachedEnvironment.value
            .environment.value.textCase
        let layout = graph.makeInput(value: LayoutComputer.fixed(.zero))
        return _ViewOutputs(layoutComputer: OptionalAttribute(layout))
    }
}
