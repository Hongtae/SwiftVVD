import Foundation
import Observation
import XCTest
@testable import VUI

private struct LayerSequenceKey: PreferenceKey {
    static var defaultValue: [Int] { [] }
    static func reduce(value: inout [Int], nextValue: () -> [Int]) {
        value.append(contentsOf: nextValue())
    }
}

@Observable
private final class PreferenceLayerModel {
    var value = 1
    var extra = 0
}

private final class PreferenceLayerCapture: @unchecked Sendable {
    var inner: [[Int]] = []
    var extras: [Int] = []
    var outer: [[Int]] = []
    var frames: [CGRect] = []
    var anchors: [CGPoint] = []
    var textBounds: [CGRect] = []
}

private struct PreferenceLayerPrimary: View {
    var model: PreferenceLayerModel
    var written: Bool

    var body: some View {
        Group {
            if written {
                Color.blue.preference(key: LayerSequenceKey.self, value: [model.value])
            } else {
                Color.blue
            }
        }.frame(width: 80, height: 40)
    }
}

private func preferenceLayerSecondary(
    _ value: [Int], _ capture: PreferenceLayerCapture, _ model: PreferenceLayerModel
) -> some View {
    let extra = model.extra
    capture.inner.append(value)
    capture.extras.append(extra)
    return Color.green.frame(width: CGFloat(12 + extra), height: 8)
        .preference(key: LayerSequenceKey.self, value: [9 + extra])
        .visualEffect { effect, proxy in
            let frame = proxy.frame(in: .global)
            if capture.frames.last != frame { capture.frames.append(frame) }
            return effect.offset(x: 0, y: 0)
        }
}

private final class PreferenceChildCapture {
    var attribute: Attribute<PreferenceChildProbe>?
    var constructions = 0
    var values: [[Int]] = []
    var transform: AGAttribute?
}

private struct PreferenceChildProbe: View, TestPrimitiveView {
    typealias Body = Never
    var capture: PreferenceChildCapture
    var values: [Int]

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let value = view._attribute.value
        value.capture.constructions += 1
        value.capture.attribute = view._attribute
        value.capture.transform = inputs.transform.identifier
        return _ViewOutputs()
    }
}

final class PreferenceLayerTests: XCTestCase {
    func testPublicLayersKeepReductionOrderAndObserveRetainedBuilders() throws {
        // ASSERTIONS secondaryPreferenceLayer27Observed
        // ASSERTIONS secondaryPreferenceObservation27Observed
        // ASSERTIONS groupPreferenceLayerRoot27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        for background in [false, true] {
            for written in [false, true] {
                let model = PreferenceLayerModel(), capture = PreferenceLayerCapture()
                let primary = PreferenceLayerPrimary(model: model, written: written)
                let layer = Group {
                    if background {
                        primary.backgroundPreferenceValue(LayerSequenceKey.self, alignment: .bottomTrailing) {
                            preferenceLayerSecondary($0, capture, model)
                        }
                    } else {
                        primary.overlayPreferenceValue(LayerSequenceKey.self, alignment: .bottomTrailing) {
                            preferenceLayerSecondary($0, capture, model)
                        }
                    }
                }.backgroundPreferenceValue(LayerSequenceKey.self) { values in
                    let _ = capture.outer.append(values)
                    Color.clear
                }
                let renderer = TestViewRendererHost()
                let host = ViewGraph(rootViewType: type(of: layer), content: layer, rendererHost: renderer)
                renderer.storage = host
                host.setSize(CGSize(width: 80, height: 40))
                host.updateOutputs(at: .zero)
                host.data.withCurrent { _ = host.displayList() }
                model.value = 2
                host.data.withCurrent { host.data.graph.inbox.drain() }
                host.updateOutputs(at: Time(seconds: 1))
                host.data.withCurrent { _ = host.displayList() }
                model.extra = 3
                host.data.withCurrent { host.data.graph.inbox.drain() }
                host.updateOutputs(at: Time(seconds: 2))
                host.data.withCurrent { _ = host.displayList() }

                let values = written ? [[1], [2], [2]] : [[], []]
                let extras = written ? [0, 0, 3] : [0, 3]
                XCTAssertEqual(capture.inner, values, "background=\(background), written=\(written)")
                XCTAssertEqual(capture.extras, extras)
                XCTAssertEqual(capture.outer, zip(values, extras).map { value, extra in
                    background ? [9 + extra] + value : value + [9 + extra]
                })
                XCTAssertEqual(capture.frames, [CGRect(x: 68, y: 32, width: 12, height: 8),
                                                CGRect(x: 65, y: 32, width: 15, height: 8)])
            }
        }
    }

    func testSecondaryChildRetainsOptionalInputAndFiltersUnrequestedOutputs() throws {
        // ASSERTIONS secondaryPreferenceChildOwnership27Observed
        // ASSERTIONS secondaryPreferenceLayer27Observed
        let host = GraphHost()
        try host.data.withCurrent {
            let graph = host.data.graph
            for requested in [false, true] {
                for produced in [false, true] {
                    let capture = PreferenceChildCapture()
                    let modifier = graph.makeInput(value: _OverlayPreferenceModifier<LayerSequenceKey, PreferenceChildProbe>(
                        alignment: .bottomTrailing, transform: { value in
                            capture.values.append(value)
                            return PreferenceChildProbe(capture: capture, values: value)
                        }
                    ))
                    var inputs = makeInputs(graph)
                    if requested { inputs.preferences.add(LayerSequenceKey.self) }
                    let value = graph.makeInput(value: [1])
                    let layout = graph.makeInput(value: LayoutComputer.fixed(CGSize(width: 80, height: 40)))
                    var primaryCalls = 0
                    let outputs = makeSecondaryPreferenceView(modifier: modifier, inputs: inputs, body: { _, childInputs in
                        primaryCalls += 1
                        XCTAssertTrue(childInputs.preferences.keys.contains(LayerSequenceKey.self))
                        var preferences = PreferencesOutputs()
                        if produced { preferences.append(LayerSequenceKey.self, node: value.identifier) }
                        return _ViewOutputs(preferences: preferences, layoutComputer: OptionalAttribute(layout))
                    }, flipOrder: false)
                    let child = try XCTUnwrap(capture.attribute)
                    XCTAssertTrue(String(reflecting: child.identifier._bodyType).contains("SecondaryChild<"))
                    XCTAssertEqual(outputs._layoutComputer.attribute?.identifier, layout.identifier)
                    XCTAssertEqual(outputs.preferences.value(for: LayerSequenceKey.self),
                                   requested && produced ? value.identifier : nil)
                    XCTAssertEqual(capture.transform, inputs.transform.identifier)
                    XCTAssertEqual(child.value.values, produced ? [1] : [])
                    value.value = [2]
                    XCTAssertEqual(child.value.values, produced ? [2] : [])
                    XCTAssertEqual(capture.values, produced ? [[1], [2]] : [[]])
                    XCTAssertEqual(capture.constructions, 1)
                    XCTAssertEqual(primaryCalls, 1)
                }
            }
        }
    }

    func testSecondaryLayerReducesEveryPrimaryValueForTheRequestedKey() throws {
        let host = GraphHost()
        try host.data.withCurrent {
            let graph = host.data.graph
            let capture = PreferenceChildCapture()
            let modifier = graph.makeInput(
                value: _OverlayPreferenceModifier<
                    LayerSequenceKey,
                    PreferenceChildProbe
                >(
                    alignment: .center,
                    transform: { value in
                        capture.values.append(value)
                        return PreferenceChildProbe(
                            capture: capture,
                            values: value
                        )
                    }
                )
            )
            let first = graph.makeInput(value: [1])
            let second = graph.makeInput(value: [2])
            let outputs = makeSecondaryPreferenceView(
                modifier: modifier,
                inputs: makeInputs(graph),
                body: { _, _ in
                    var preferences = PreferencesOutputs()
                    preferences.append(
                        LayerSequenceKey.self,
                        node: first.identifier
                    )
                    preferences.append(
                        LayerSequenceKey.self,
                        node: second.identifier
                    )
                    return _ViewOutputs(preferences: preferences)
                },
                flipOrder: false
            )

            let child = try XCTUnwrap(capture.attribute)
            XCTAssertEqual(child.value.values, [1, 2])

            first.value = [3]
            XCTAssertEqual(child.value.values, [3, 2])
            second.value = [4]
            XCTAssertEqual(child.value.values, [3, 4])
            XCTAssertTrue(outputs.preferences.preferences.isEmpty)
        }
    }

    func testPublicTextLayoutConsumersResolveAnchorsInReceivingGeometry() throws {
        // ASSERTIONS secondaryPreferenceLayer27Observed
        // ASSERTIONS textLayoutAnchorTransform27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        var font = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { font.deleteLastPathComponent() }
        font.appendPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
        let matrices: [CGAffineTransform] = [.identity,
            .init(a: 0, b: 1, c: -1, d: 0, tx: 90, ty: 3),
            .init(a: -1, b: 0, c: 0, d: 1, tx: 85, ty: -2),
            .init(a: 1, b: 0.5, c: 0.25, d: 1, tx: 2, ty: 4)]
        for background in [false, true] {
            for matrix in matrices {
                let capture = PreferenceLayerCapture()
                let text = Text("A").font(.file(font, size: 23))
                    .frame(width: 64, alignment: .leading)
                    .padding(.leading, 11).padding(.top, 7)
                    .transformEffect(matrix).padding(.leading, 19).padding(.top, 17)
                let reader: (Text.LayoutKey.Value) -> AnyView = { layouts in
                    let layouts = UnsafeSendableBox(layouts)
                    return AnyView(Color.clear.visualEffect { effect, proxy in
                        capture.anchors = layouts.value.map { proxy[$0.origin] }
                        capture.textBounds = layouts.value.map { $0.layout[0].typographicBounds.rect }
                        return effect.offset(x: 0, y: 0)
                    })
                }
                let value = background
                    ? AnyView(text.backgroundPreferenceValue(Text.LayoutKey.self, reader))
                    : AnyView(text.overlayPreferenceValue(Text.LayoutKey.self, reader))
                let renderer = TestViewRendererHost()
                var environment = EnvironmentValues()
                environment.defaultFontRenderingMode = .vector()
                environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
                let host = ViewGraph(rootViewType: AnyView.self, content: value, rendererHost: renderer,
                                     initialEnvironment: environment)
                renderer.storage = host
                host.setSize(CGSize(width: 94, height: 51))
                host.updateOutputs(at: .zero)
                host.data.withCurrent { _ = host.displayList() }
                let transformed = CGPoint(x: 11, y: 7).applying(matrix)
                XCTAssertEqual(capture.anchors, [CGPoint(x: transformed.x + 19, y: transformed.y + 17)])
                XCTAssertEqual(capture.textBounds, [CGRect(x: 0, y: 0, width: 15.00390625, height: 27)])
            }
        }
    }

    private func makeInputs(_ graph: _AGGraph) -> _ViewInputs {
        _ViewInputs(base: _GraphInputs(time: graph.makeInput(value: Time.zero),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: EnvironmentValues()),
            transaction: graph.makeInput(value: Transaction())),
            customInputs: PropertyList(), preferences: PreferencesInputs(keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero), containerPosition: graph.makeInput(value: .zero),
            size: graph.makeInput(value: ViewSize(width: 80, height: 40)),
            safeAreaInsets: OptionalAttribute(), containerSize: OptionalAttribute(), stackOrientation: nil)
    }
}
