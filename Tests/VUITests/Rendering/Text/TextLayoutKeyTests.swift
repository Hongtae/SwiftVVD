import Foundation
import XCTest
@testable import VUI

final class TextLayoutKeyTests: XCTestCase {
    private var fontURL: URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf")
    }

    func testRequestedLayoutsKeepLocalMetricsAndSelectTheirOwner() throws {
        // ASSERTIONS textLayoutKeyPreference27Observed
        // ASSERTIONS textLayoutQueryOwnership27Observed
        // ASSERTIONS textPreferredManagerInput27Observed
        // ASSERTIONS textPreferredManagerSelection27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        for sample in ["", "A", "AB CD EF GH", "A\nB"] {
            for custom in [false, true] {
                for limited in [false, true] {
                    for requested in [false, true] {
                        for preference in 0..<3 {
                            let rendererHost = TestViewRendererHost()
                            let host = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(),
                                rendererHost: rendererHost, requestedOutputs: [])
                            rendererHost.storage = host
                            try host.data.withCurrent {
                                let graph = host.data.graph
                                var inputs = makeInputs(graph)
                                if requested { inputs.preferences.keys.add(Text.LayoutKey.self) }
                                let text = Text(verbatim: sample).font(.file(fontURL, size: 23))
                                    .lineLimit(limited ? 1 : nil)
                                let rendered = custom ? AnyView(text.textRenderer(LayoutKeyRenderer())) : AnyView(text)
                                let value = preference == 0 ? rendered : preference == 1
                                    ? AnyView(rendered.preferTextLayoutManager())
                                    : AnyView(rendered.contentTransitionPrefersCharacterOrder())
                                let outputs = AnyView._makeView(view: _GraphValue(_attribute: graph.makeInput(value: value)), inputs: inputs)
                                let computer = try XCTUnwrap(outputs._layoutComputer.attribute).value
                                let engine = try XCTUnwrap(computer.box as? LayoutEngineBox<StyledTextLayoutEngine>).engine
                                XCTAssertEqual(engine.text is ResolvedStyledText.TextLayoutManager, custom || requested || preference != 0)
                                XCTAssertEqual(engine.text.features.contains(.produceTextLayout), custom || requested)
                                XCTAssertEqual(engine.text.features.contains(.useTextLayoutManager), preference != 0)
                                XCTAssertEqual(engine.text.features.contains(.customRenderer), custom)
                                XCTAssertTrue(engine.text.features.contains(.useTextSuffix))
                                let node = outputs.preferences.value(for: Text.LayoutKey.self)
                                if !requested {
                                    XCTAssertNil(node)
                                    return
                                }
                                let size = computer.sizeThatFits(_ProposedSize(width: 64, height: nil))
                                inputs.size.value = ViewSize(size, proposal: _ProposedSize(width: 64, height: nil))
                                let values = Attribute<Text.LayoutKey.Value>(try XCTUnwrap(node)).value
                                let layout = try XCTUnwrap(values.first).layout
                                let label = "\(sample.debugDescription), custom=\(custom), limited=\(limited), preference=\(preference)"
                                XCTAssertEqual(values.count, 1, label)
                                let lines = sample.isEmpty ? 0 : limited || sample == "A" ? 1 : sample == "AB CD EF GH" ? 3 : 2
                                XCTAssertEqual(layout.count, lines, label)
                                XCTAssertEqual(layout.isTruncated, sample == "AB CD EF GH" && limited, label)
                                for (index, line) in layout.enumerated() {
                                    XCTAssertEqual(line.origin, CGPoint(x: 0, y: 21 + index * 27), label)
                                    XCTAssertEqual(line.typographicBounds.rect.minY, CGFloat(index * 27), label)
                                }
                                XCTAssertEqual(values[0].origin.box.convert(to: .identity), .zero, label)
                            }
                        }
                    }
                }
            }
        }
    }

    func testPreferredManagerFollowsGroupChildrenWithoutChangingSiblingInputs() throws {
        // ASSERTIONS textPreferredManagerInput27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        XCTAssertFalse(PreferTextLayoutManagerInput.defaultValue)
        let capture = PreferredManagerScopeCapture()
        let text = Text("A").font(.file(fontURL, size: 23))
        let value = VStack {
            Group {
                text.modifier(PreferredManagerScopeReader(id: 0, capture: capture))
                text.modifier(PreferredManagerScopeReader(id: 1, capture: capture))
            }.preferTextLayoutManager()
            text.modifier(PreferredManagerScopeReader(id: 2, capture: capture))
                .contentTransitionPrefersCharacterOrder()
            text.modifier(PreferredManagerScopeReader(id: 3, capture: capture))
        }
        try withMounted(value, size: CGSize(width: 64, height: 150)) {
            XCTAssertEqual(capture.preferred, [0: true, 1: true, 2: true, 3: false])
            XCTAssertEqual(capture.manager, [0: true, 1: true, 2: true, 3: false])
            XCTAssertEqual(capture.produced, [0: false, 1: false, 2: false, 3: false])
        }
    }

    func testAnchoredLayoutsSeparateLocalMetricsFromAncestorTransforms() throws {
        // ASSERTIONS textLayoutAnchorOrigin27Observed
        // ASSERTIONS textLayoutAnchorTransform27Observed
        // ASSERTIONS textLayoutRootCoordinateOwners27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        let matrices: [CGAffineTransform] = [
            .identity, .init(a: 0, b: 1, c: -1, d: 0, tx: 90, ty: 3),
            .init(a: -1, b: 0, c: 0, d: 1, tx: 85, ty: -2),
            .init(a: 1, b: 0.5, c: 0.25, d: 1, tx: 2, ty: 4),
        ]
        for matrix in matrices {
            for outer in [false, true] {
                let capture = LayoutKeyCapture()
                let base = Text("A").font(.file(fontURL, size: 23))
                    .frame(width: 64, alignment: .leading)
                    .padding(.leading, 11).padding(.top, 7)
                let value = outer
                    ? AnyView(base.transformEffect(matrix).padding(.leading, 19).padding(.top, 17)
                        .modifier(LayoutKeyObserver(capture: capture)))
                    : AnyView(base.modifier(LayoutKeyObserver(capture: capture)).transformEffect(matrix)
                        .padding(.leading, 19).padding(.top, 17))
                try withMounted(value, size: CGSize(width: 94, height: 51)) {
                    let values = try XCTUnwrap(capture.values?.value)
                    let proxy = try XCTUnwrap(capture.proxy)
                    XCTAssertEqual(values.count, 1)
                    let transformed = CGPoint(x: 11, y: 7).applying(matrix)
                    let expected = outer ? CGPoint(x: transformed.x + 19, y: transformed.y + 17)
                        : CGPoint(x: 11, y: 7)
                    let point = proxy[values[0].origin]
                    XCTAssertEqual(point.x, expected.x, accuracy: 1e-9)
                    XCTAssertEqual(point.y, expected.y, accuracy: 1e-9)
                    XCTAssertEqual(values[0].layout[0].origin, CGPoint(x: 0, y: 21))
                    XCTAssertEqual(values[0].layout[0].typographicBounds.rect,
                        CGRect(x: 0, y: 0, width: 15.00390625, height: 27))
                }
            }
        }
    }

    func testRootPlacementChangesInvalidateAnchorsWithoutChangingLocalLayout() throws {
        // ASSERTIONS textLayoutQueryOwnership27Observed
        // ASSERTIONS textLayoutRootCoordinateOwners27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        let capture = LayoutKeyCapture()
        let content = Text("A").font(.file(fontURL, size: 23))
            .frame(width: 64, alignment: .leading)
            .padding(.leading, 11).padding(.top, 7)
            .modifier(LayoutKeyObserver(capture: capture))
        try withMounted(content, size: CGSize(width: 75, height: 34)) {
            let host = try XCTUnwrap(GraphHost.currentHost as? ViewGraph)
            let original = try XCTUnwrap(capture.values?.value?.first)
            let proxy = try XCTUnwrap(capture.proxy)
            XCTAssertEqual(original.origin.box.convert(to: ViewTransform()), CGPoint(x: 11, y: 7))
            try XCTUnwrap(host.sizeAttr).setValue(ViewSize(CGSize(width: 175, height: 134)))
            let shifted = try XCTUnwrap(capture.values?.value?.first)
            XCTAssertNotEqual(original.origin, shifted.origin)
            XCTAssertEqual(shifted.origin.box.convert(to: ViewTransform()), CGPoint(x: 61, y: 57))
            XCTAssertEqual(proxy[shifted.origin], CGPoint(x: 11, y: 7))
            XCTAssertEqual(shifted.layout[0].origin, original.layout[0].origin)
            XCTAssertEqual(shifted.layout[0].typographicBounds.rect, original.layout[0].typographicBounds.rect)
        }
    }

    func testSiblingReductionPreservesOrderAndBothEqualityComponents() throws {
        // ASSERTIONS textLayoutKeyPreference27Observed
        // ASSERTIONS textLayoutAnchorOrigin27Observed
        let previous = appContext
        appContext = StyleTestAppContext()
        defer { appContext = previous }
        XCTAssertTrue(Text.LayoutKey.defaultValue.isEmpty)
        for reversed in [false, true] {
            for shifted in [false, true] {
                let capture = LayoutKeyCapture()
                let small = Text("A").font(.file(fontURL, size: 23))
                let large = Text("BC").font(.file(fontURL, size: 31))
                let value = VStack(alignment: .leading, spacing: 5) {
                    if reversed { large; small } else { small; large }
                }.offset(x: shifted ? 13 : 0, y: shifted ? -4 : 0)
                    .padding(.leading, 11).padding(.top, 7)
                    .modifier(LayoutKeyObserver(capture: capture))
                try withMounted(value, size: CGSize(width: 50.5, height: 76)) {
                    let values = try XCTUnwrap(capture.values?.value)
                    let proxy = try XCTUnwrap(capture.proxy)
                    XCTAssertEqual(values.count, 2)
                    let dx = shifted ? 13 : 0, dy = shifted ? -4 : 0
                    XCTAssertEqual(proxy[values[0].origin], CGPoint(x: 11 + dx, y: 7 + dy))
                    XCTAssertEqual(proxy[values[1].origin], CGPoint(x: 11 + dx, y: (reversed ? 49 : 39) + dy))
                    XCTAssertEqual(values.map { $0.layout[0].typographicBounds.rect.width },
                        reversed ? [39.49169921875, 15.00390625] : [15.00390625, 39.49169921875])
                    var reduced = [values[0]]
                    var calls = 0
                    Text.LayoutKey.reduce(value: &reduced) { calls += 1; return [values[1]] }
                    XCTAssertEqual(calls, 1)
                    XCTAssertEqual(reduced, values)
                    var changed = values[0]
                    changed.origin = values[1].origin
                    XCTAssertNotEqual(changed, values[0])
                    changed = values[0]
                    changed.layout = values[1].layout
                    XCTAssertNotEqual(changed, values[0])
                }
            }
        }
    }

    func testAnchorPointConversionsKeepTraversalAndFoldedOnlyBoundaries() {
        // ASSERTIONS anchorPointConversion27Observed
        var chain = ViewTransform()
        chain.appendTranslation(CGSize(width: 300, height: 300))
        chain.appendSizedSpace(name: "outer", size: CGSize(width: 200, height: 200))
        chain.appendTranslation(CGSize(width: 100, height: 100))
        chain.appendSizedSpace(name: "inner", size: CGSize(width: 50, height: 50))
        chain.appendTranslation(CGSize(width: -25, height: -40))
        var folded = ViewTransform()
        folded.appendPosition(CGPoint(x: 17, y: 11))
        let expected: [[CGPoint]] = [
            [.init(x: 25, y: 40), .init(x: 25, y: 40), .init(x: -350, y: -320), .init(x: 400, y: 400)],
            [.init(x: 400, y: 400), .init(x: -350, y: -320), .init(x: 25, y: 40), .init(x: 25, y: 40)],
            [.init(x: 325, y: 340), .init(x: -275, y: -260), .init(x: -50, y: -20), .init(x: 100, y: 100)],
            [.init(x: 425, y: 440), .init(x: -375, y: -360), .init(x: 50, y: 80), .zero],
            [.init(x: 400, y: 400), .init(x: 25, y: 40), .init(x: -350, y: -320), .init(x: 25, y: 40)],
        ]
        let spaces: [CoordinateSpace] = [.global, .local, .named("outer"), .named("inner"), .named("missing")]
        for (transformIndex, transform) in [chain, folded].enumerated() {
            for (index, space) in spaces.enumerated() {
                for method in 0..<4 {
                    var point = CGPoint(x: 25, y: 40)
                    switch method {
                    case 0: point.convertGlobal(to: space, transform: transform)
                    case 1: point.convertGlobal(from: space, transform: transform)
                    case 2: point.convert(to: space, transform: transform)
                    default: point.convert(from: space, transform: transform)
                    }
                    XCTAssertEqual(point, transformIndex == 0 ? expected[index][method] : CGPoint(x: 25, y: 40),
                        "transform=\(transformIndex), space=\(index), method=\(method)")
                }
            }
        }
    }

    private func withMounted<Content: View>(_ content: Content, size: CGSize,
                                           _ body: () throws -> Void) throws {
        let rendererHost = TestViewRendererHost()
        var environment = EnvironmentValues()
        environment.displayScale = 2
        environment.defaultFontRenderingMode = .vector()
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        let host = ViewGraph(rootViewType: Content.self, content: content,
            rendererHost: rendererHost, initialEnvironment: environment)
        rendererHost.storage = host
        host.setSize(size)
        host.updateOutputs(at: .zero)
        try host.data.withCurrent(body)
    }

    private func makeInputs(_ graph: _AGGraph) -> _ViewInputs {
        var environment = EnvironmentValues()
        environment.displayScale = 2
        environment.defaultFontRenderingMode = .vector()
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        return _ViewInputs(base: _GraphInputs(
            time: graph.makeInput(value: Time(seconds: 0)),
            phase: graph.makeInput(value: _GraphInputs.Phase()),
            environment: graph.makeInput(value: environment), transaction: graph.makeInput(value: Transaction())),
            customInputs: PropertyList(), preferences: PreferencesInputs(keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint(x: 11, y: 7)),
            containerPosition: graph.makeInput(value: .zero),
            size: graph.makeInput(value: ViewSize(width: 64, height: 100)),
            safeAreaInsets: OptionalAttribute(), containerSize: OptionalAttribute(), stackOrientation: nil)
    }
}

private struct LayoutKeyRenderer: TextRenderer {
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {}
}

private final class PreferredManagerScopeCapture {
    var preferred: [Int: Bool] = [:]
    var manager: [Int: Bool] = [:]
    var produced: [Int: Bool] = [:]
}

private struct PreferredManagerScopeReader: ViewModifier, PrimitiveViewModifier, MultiViewModifier {
    typealias Body = Never
    var id: Int
    var capture: PreferredManagerScopeCapture

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let value = modifier._attribute.value
        value.capture.preferred[value.id] = inputs[PreferTextLayoutManagerInput.self]
        let outputs = body(_Graph(), inputs)
        if let engine = outputs._layoutComputer.attribute?.value.box as? LayoutEngineBox<StyledTextLayoutEngine> {
            value.capture.manager[value.id] = engine.engine.text is ResolvedStyledText.TextLayoutManager
            value.capture.produced[value.id] = engine.engine.text.features.contains(.produceTextLayout)
        }
        return outputs
    }
}

private final class LayoutKeyCapture {
    var values: WeakAttribute<Text.LayoutKey.Value>?
    var proxy: GeometryProxy?
}

private struct LayoutKeyObserver: ViewModifier, PrimitiveViewModifier {
    typealias Body = Never
    var capture: LayoutKeyCapture

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var childInputs = inputs
        childInputs.preferences.keys.add(Text.LayoutKey.self)
        let outputs = body(_Graph(), childInputs)
        let capture = modifier._attribute.value.capture
        capture.values = outputs.preferences.value(for: Text.LayoutKey.self).map {
            Attribute<Text.LayoutKey.Value>($0).asWeak()
        }
        capture.proxy = GeometryProxy(owner: modifier._attribute.identifier, size: inputs.size,
            environment: inputs.base.cachedEnvironment.value.environment,
            transform: inputs.transform, position: inputs.position,
            safeAreaInsets: inputs.safeAreaInsets.attribute, seed: 0)
        return outputs
    }
}
