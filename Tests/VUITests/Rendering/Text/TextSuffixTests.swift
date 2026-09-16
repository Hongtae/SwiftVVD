import Foundation
import XCTest
import VVD
@testable import VUI

final class TextSuffixTests: XCTestCase {
    // ASSERTIONS textSuffixNativeProductionObserved
    func testModesPreserveTheirPayloadAndResolveOnlyOnePhysicalLine() throws {
        let text = Text(verbatim: " more")
        XCTAssertEqual(Text.Suffix.truncated(text), .truncated(text))
        XCTAssertNotEqual(Text.Suffix.truncated(text), .alwaysVisible(text))
        XCTAssertNotEqual(Text.Suffix.automatic, .none)
        XCTAssertNil(Text.Suffix.automatic.text)
        XCTAssertNil(Text.Suffix.none.text)
        XCTAssertEqual(Text.Suffix.alwaysVisible(text).text, text)

        try withGraph { graph, inputs, _ in
            for payload in ["", "X\nY", " more"] {
                for mode in [Text.Suffix.truncated(Text(verbatim: payload)), .alwaysVisible(Text(verbatim: payload))] {
                    var child = inputs
                    TextSuffixModifier._makeInputs(modifier: _GraphValue(_attribute:
                        graph.makeInput(value: TextSuffixModifier(suffix: mode))), inputs: &child)
                    let suffix = child.cachedEnvironment.value.environment.value[TextSuffixKey.self]
                    if payload == " more" {
                        XCTAssertNotNil(suffix.line)
                        XCTAssertGreaterThan(try XCTUnwrap(suffix.line).typographicBounds.width, 0)
                        XCTAssertEqual(suffix.styles, [])
                        switch (mode.storage, suffix) {
                        case (.truncated, .truncated), (.alwaysVisible, .alwaysVisible): break
                        default: XCTFail("The resolved mode must retain its original case")
                        }
                    } else {
                        XCTAssertEqual(suffix, .none, payload.debugDescription)
                    }
                    XCTAssertEqual(mode.resolve(text: nil), .none)
                }
            }
        }
    }

    // ASSERTIONS textSuffixModifierGraphObserved
    func testModifierKeepsSeparateRulesAndReusesResolutionAcrossModeChanges() throws {
        try withGraph { graph, inputs, _ in
            let payload = Text(verbatim: " more")
            let modifier = graph.makeInput(value: TextSuffixModifier(suffix: .truncated(payload)))
            let parent = inputs.cachedEnvironment
            var inputs = inputs
            inputs.changedDebugProperties = 0
            let options = inputs.options
            TextSuffixModifier._makeInputs(modifier: _GraphValue(_attribute: modifier), inputs: &inputs)
            XCTAssertFalse(parent === inputs.cachedEnvironment)
            XCTAssertEqual(inputs.changedDebugProperties, 0x20)
            XCTAssertEqual(inputs.options, options)
            XCTAssertEqual(parent.value.environment.value[TextSuffixKey.self], .none)

            let childAttribute = inputs.cachedEnvironment.value.environment
            let child = try rule(childAttribute, as: TextSuffixModifier.ChildEnvironment.self)
            XCTAssertEqual(child._environment.identifier, parent.value.environment.identifier)
            let suffix = try rule(child._suffix, as: TextSuffixModifier.ResolvedTextSuffixFilter.self)
            XCTAssertEqual(suffix._modifier.identifier, modifier.identifier)
            let resolved = try rule(suffix._text, as: ResolvedOptionalTextFilter.self)
            let optional = try rule(resolved._text, as: TextSuffixModifier.OptionalText.self)
            XCTAssertEqual(optional._modifier.identifier, modifier.identifier)
            XCTAssertEqual(resolved._environment.identifier, parent.value.environment.identifier)
            XCTAssertEqual(resolved.helper._time.identifier, inputs.time.identifier)
            XCTAssertTrue(resolved.helper.includeDefaultAttributes)
            XCTAssertTrue(resolved.helper.allowsKeyColors)
            XCTAssertEqual(resolved.helper.features, .produceTextLayout)
            XCTAssertFalse(resolved.helper.features.contains(.useTextSuffix))

            let first = try XCTUnwrap(suffix._text.value)
            XCTAssertTrue(first is ResolvedStyledText.TextLayoutManager)
            let firstLine = try XCTUnwrap(childAttribute.value[TextSuffixKey.self].line)
            XCTAssertEqual(firstLine.drawingOptions.rawValue, 0)
            modifier.value = TextSuffixModifier(suffix: .alwaysVisible(payload))
            if case .alwaysVisible = childAttribute.value[TextSuffixKey.self] {} else { XCTFail() }
            XCTAssertTrue(suffix._text.value === first)

            for mode: Text.Suffix in [.none, .automatic, .truncated(payload), .none] {
                modifier.value = TextSuffixModifier(suffix: mode)
                let value = childAttribute.value[TextSuffixKey.self]
                if mode.text == nil {
                    XCTAssertEqual(value, .none)
                    XCTAssertNil(suffix._text.value)
                    XCTAssertNil(try rule(suffix._text, as: ResolvedOptionalTextFilter.self).helper.lastText)
                } else {
                    XCTAssertNotNil(value.line)
                    XCTAssertNotNil(suffix._text.value)
                }
            }
        }
    }

    // ASSERTIONS textOptionalResolutionInvalidationObserved
    func testOptionalResolverTracksUsedEnvironmentValuesAndTextChanges() throws {
        try withGraph { graph, inputs, _ in
            let text = graph.makeInput(value: Optional(Text(verbatim: "more")))
            let environment = inputs.cachedEnvironment.value.environment
            let output = graph.makeStatefulRule(ResolvedOptionalTextFilter(
                _text: text, _environment: environment,
                helper: ResolvedTextHelper(_time: inputs.time, features: .produceTextLayout)))
            let first = try XCTUnwrap(output.value)
            let width = first.sizeThatFits(.unspecified).width
            // Isolate the rule's used-value gate from conservative comparison
            // of non-Equatable foreground-style environment values.
            output.mutateBody(as: ResolvedOptionalTextFilter.self, invalidating: false) { body in
                body.helper.tracker = PropertyList.Tracker()
                let tracked = EnvironmentValues(environment.value._plist, tracker: body.helper.tracker)
                _ = tracked.font
            }
            var unusedChange = environment.value
            unusedChange[UnusedSuffixTestKey.self] = 17
            environment.value = unusedChange
            XCTAssertTrue(output.value === first)

            var fontChange = environment.value
            fontChange.font = testFont(size: 31)
            environment.value = fontChange
            let larger = try XCTUnwrap(output.value)
            XCTAssertFalse(larger === first)
            XCTAssertGreaterThan(larger.sizeThatFits(.unspecified).width, width)
            text.value = Text(verbatim: "more more")
            let longer = try XCTUnwrap(output.value)
            XCTAssertGreaterThan(longer.sizeThatFits(.unspecified).width, larger.sizeThatFits(.unspecified).width)
            text.value = nil
            XCTAssertNil(output.value)
            // Updating an initialized nil value must not leave the previous owner installed.
            output.invalidateValue()
            XCTAssertNil(output.value)
            text.value = Text(verbatim: "more")
            XCTAssertEqual(try XCTUnwrap(output.value).sizeThatFits(.unspecified), larger.sizeThatFits(.unspecified))
        }
    }

    // ASSERTIONS textOptionalResolutionInvalidationObserved
    func testOptionalResolverReusesItsValueUntilTheDynamicDeadlineAndClearsNil() throws {
        try withGraph { graph, inputs, host in
            let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
            let reference = graph.makeInput(value: Optional(start))
            inputs.time.value = Time(seconds: 100)
            let text = graph.makeInput(value: Optional(Text(start.addingTimeInterval(4.25), style: .timer)))
            let output = graph.makeStatefulRule(ResolvedOptionalTextFilter(
                _text: text, _environment: inputs.cachedEnvironment.value.environment,
                helper: ResolvedTextHelper(_time: inputs.time, _referenceDate: reference.asWeak(),
                                           features: .produceTextLayout)))
            let first = try XCTUnwrap(output.value)
            guard case let .time(deadline) = try rule(output, as: ResolvedOptionalTextFilter.self).helper.nextUpdate else {
                return XCTFail("The timer must publish its next deadline")
            }
            XCTAssertEqual(deadline.seconds, 100.25, accuracy: 1e-9)
            XCTAssertEqual(host.viewGraph.nextUpdate.views.time, deadline)
            inputs.time.value = Time(seconds: 100.125)
            XCTAssertTrue(output.value === first)
            reference.value = start.addingTimeInterval(0.25)
            inputs.time.value = deadline
            let updated = try XCTUnwrap(output.value)
            XCTAssertFalse(updated === first)
            XCTAssertEqual(updated.storage?.string,
                text.value?._resolveText(in: inputs.cachedEnvironment.value.environment.value,
                                        referenceDate: start.addingTimeInterval(0.25)))
            host.viewGraph.nextUpdate.views = .init()
            text.value = nil
            XCTAssertNil(output.value)
            if case .none = try rule(output, as: ResolvedOptionalTextFilter.self).helper.nextUpdate {} else { XCTFail() }
            XCTAssertEqual(host.viewGraph.nextUpdate.views.time, .infinity)
        }
    }

    // ASSERTIONS textSuffixModifierGraphObserved
    func testNestedModifierOverridesOnlyItsChildEnvironmentAndPreservesPalette() throws {
        try withGraph { graph, inputs, _ in
            var outer = inputs
            TextSuffixModifier._makeInputs(modifier: _GraphValue(_attribute: graph.makeInput(value:
                TextSuffixModifier(suffix: .truncated(Text(verbatim: "outer"))))), inputs: &outer)
            let child = try rule(outer.cachedEnvironment.value.environment, as: TextSuffixModifier.ChildEnvironment.self)
            let filter = try rule(child._suffix, as: TextSuffixModifier.ResolvedTextSuffixFilter.self)
            let owner = try XCTUnwrap(filter._text.value)
            owner.styles = [_ShapeStyle_Pack.Style(.color(VUI.Color.red.resolveHDR(in: EnvironmentValues())))]
            let outerSuffix = outer.cachedEnvironment.value.environment.value[TextSuffixKey.self]
            XCTAssertNotNil(outerSuffix.line)
            XCTAssertEqual(outerSuffix.styles.count, 1)
            var inner = outer
            let modifier = graph.makeInput(value: TextSuffixModifier(suffix: .none))
            TextSuffixModifier._makeInputs(modifier: _GraphValue(_attribute: modifier), inputs: &inner)
            XCTAssertEqual(inner.cachedEnvironment.value.environment.value[TextSuffixKey.self], .none)
            XCTAssertEqual(outer.cachedEnvironment.value.environment.value[TextSuffixKey.self], outerSuffix)
            XCTAssertEqual(inputs.cachedEnvironment.value.environment.value[TextSuffixKey.self], .none)
            modifier.value = TextSuffixModifier(suffix: .truncated(Text(verbatim: "inner")))
            let innerSuffix = inner.cachedEnvironment.value.environment.value[TextSuffixKey.self]
            XCTAssertNotNil(innerSuffix.line)
            XCTAssertTrue(innerSuffix.styles.isEmpty)
            XCTAssertEqual(outer.cachedEnvironment.value.environment.value[TextSuffixKey.self], outerSuffix)
        }
    }

    func testSuffixRulesDoNotRetainTheirGraphOrResolvedFont() throws {
        weak var hostReference: TestViewRendererHost?
        weak var graphReference: _AGGraph?
        weak var ownerReference: ResolvedStyledText?
        weak var fontReference: AnyObject?
        try withGraph { graph, inputs, host in
            hostReference = host
            graphReference = graph
            var inputs = inputs
            TextSuffixModifier._makeInputs(modifier: _GraphValue(_attribute: graph.makeInput(value:
                TextSuffixModifier(suffix: .truncated(Text(verbatim: "more"))))), inputs: &inputs)
            let child = try rule(inputs.cachedEnvironment.value.environment, as: TextSuffixModifier.ChildEnvironment.self)
            let suffix = try rule(child._suffix, as: TextSuffixModifier.ResolvedTextSuffixFilter.self)
            XCTAssertNotNil(child._suffix.value.line)
            let owner = try XCTUnwrap(suffix._text.value)
            ownerReference = owner
            if case let .styledText(faces, _, _, _) = owner.resolvedText?.runs.first {
                fontReference = faces.first.map { $0 as AnyObject }
            }
            XCTAssertNotNil(fontReference)
        }
        XCTAssertNil(hostReference)
        XCTAssertNil(graphReference)
        XCTAssertNil(ownerReference)
        XCTAssertNil(fontReference)
    }

    // ASSERTIONS textSuffixBodyOptionsObserved
    // ASSERTIONS textSuffixManagerSelectionObserved
    // ASSERTIONS textSuffixManagerOwnershipObserved
    func testBodyOptionsGateSuffixAndPaletteIndependentlyAndSelectManager() throws {
        try withGraph { _, inputs, host in
            var environment = inputs.cachedEnvironment.value.environment.value
            let context = GraphTextResolutionContext(environment: environment, sceneResources: host.sceneResources)
            let payload = try XCTUnwrap(Text(verbatim: " more").font(testFont(size: 11)).foregroundColor(.red)
                ._resolveStyledText(context: context, referenceDate: Date(), archiveOptions: .init(),
                                    features: .produceTextLayout, sizeFitting: false))
            let palette = [_ShapeStyle_Pack.Style(.color(VUI.Color.red.resolveHDR(in: environment)))]
            payload.styles = palette
            for mode in [Text.Suffix.none, .automatic, .truncated(Text(" more")), .alwaysVisible(Text(" more"))] {
                environment[TextSuffixKey.self] = mode.resolve(text: payload)
                for options: Text.ResolveOptions in [[], .allowsKeyColors, .allowsTextSuffix, [.allowsKeyColors, .allowsTextSuffix]] {
                    let enabled = options.contains(.allowsTextSuffix) && mode.text != nil
                    let resolved = try XCTUnwrap(Text(verbatim: "AB")._resolveStyledText(
                        context: GraphTextResolutionContext(environment: environment, sceneResources: host.sceneResources),
                        referenceDate: Date(), archiveOptions: .init(), features: [], sizeFitting: false, options: options))
                    XCTAssertEqual(resolved is ResolvedStyledText.TextLayoutManager, enabled)
                    let properties = try XCTUnwrap(resolved.resolvedText?.resolvedProperties)
                    XCTAssertEqual(properties.suffix, enabled ? environment[TextSuffixKey.self] : .none)
                    XCTAssertEqual(properties.styles, enabled && options.contains(.allowsKeyColors) ? palette : [])
                    XCTAssertEqual(properties.features.contains(.keyColor), enabled && options.contains(.allowsKeyColors))
                    XCTAssertFalse(properties.features.contains(.attachments))
                    if let manager = resolved as? ResolvedStyledText.TextLayoutManager {
                        XCTAssertEqual(manager.suffix, properties.suffix)
                        XCTAssertEqual(manager.attachments, properties.customAttachments)
                    }
                }
            }
            // The shared graph helper enables body suffixes, but suffix resolution itself does not.
            var helper = ResolvedTextHelper(_time: inputs.time, allowsKeyColors: true, features: .useTextSuffix)
            let owner = try XCTUnwrap(helper.resolve(Text(verbatim: "AB"), with: environment, sizeFitting: false))
            XCTAssertEqual(owner.storage?.string, "AB\u{fffc}")
            helper.features = .produceTextLayout
            XCTAssertEqual(helper.resolve(Text(verbatim: "AB"), with: environment, sizeFitting: false)?.storage?.string, "AB")
        }
    }

    // ASSERTIONS textSuffixCustomAttachmentObserved
    func testAlwaysVisibleRegistersUTF16IndexAndInheritsFinalBodyAttributes() throws {
        try withGraph { _, inputs, host in
            var environment = inputs.cachedEnvironment.value.environment.value
            let context = GraphTextResolutionContext(environment: environment, sceneResources: host.sceneResources)
            let payload = try XCTUnwrap(Text(verbatim: " more").font(testFont(size: 11)).foregroundColor(.red)
                ._resolveStyledText(context: context, referenceDate: Date(), archiveOptions: .init(),
                                    features: .produceTextLayout, sizeFitting: false))
            environment[TextSuffixKey.self] = Text.Suffix.alwaysVisible(Text(" more")).resolve(text: payload)
            let suffixLine = try XCTUnwrap(environment[TextSuffixKey.self].line)
            let child = GraphTextResolutionContext(environment: environment, sceneResources: host.sceneResources)
            for string in ["", "AB", "A😀e\u{301}"] {
                let body = Text(verbatim: string).font(testFont(size: 23)).foregroundColor(.green)
                let source = try XCTUnwrap(body._resolve(context: child, referenceDate: Date(), options: .allowsTextSuffix))
                XCTAssertEqual(source.attributedStorage.string, string + "\u{fffc}")
                XCTAssertEqual(source.resolvedProperties?.customAttachments.characterIndices, [string.utf16.count])
                XCTAssertFalse(source.resolvedFeatures.contains(.attachments))
                let attributes = source.attributedStorage.attributes(at: string.utf16.count, effectiveRange: nil)
                let box = try XCTUnwrap(attributes[.customTextAttachment] as? ConcreteCustomTextAttachment<LineAttachment>)
                XCTAssertEqual(box.attachment.line, suffixLine)
                XCTAssertEqual(box.attachment.bounds, suffixLine.typographicBounds)
                XCTAssertEqual(box.length, suffixLine.typographicBounds.width)
                XCTAssertEqual(box.ascent, suffixLine.typographicBounds.ascent)
                XCTAssertEqual(box.descent, suffixLine.typographicBounds.descent)
                if string.isEmpty {
                    XCTAssertEqual(attributes.count, 1)
                } else {
                    let previous = source.attributedStorage.attributes(at: string.utf16.count - 1, effectiveRange: nil)
                    XCTAssertEqual(attributes[.coreFont] as? VUI.Font, previous[.coreFont] as? VUI.Font)
                    XCTAssertEqual(attributes[.coreForegroundColor] as? VUI.Color, .green)
                }
                let glyphs = source.unwrappedGlyphLines()
                let attachmentGlyph = try XCTUnwrap(glyphs.last?.glyphs.last)
                XCTAssertEqual(attachmentGlyph.advance.width / source.scaleFactor, box.length, accuracy: 1e-9)
                let drawing = source.makeDrawing(lineGlyphs: glyphs)
                XCTAssertEqual(drawing.customAttachments.count, 1)
                XCTAssertTrue(drawing.customAttachments[0].attachment === box)
                XCTAssertEqual(drawing.customAttachments[0].bounds.width, box.length)
                let layout = source.makeLayout(lineGlyphs: glyphs, layoutDirection: .leftToRight)
                let lastRun = try XCTUnwrap(layout.last?.last)
                XCTAssertEqual(lastRun.characterIndices, [.init(value: string.utf16.count)])
            }
            let mixed = Text(verbatim: "A").foregroundColor(.green) +
                Text(verbatim: "X").font(testFont(size: 17)).foregroundColor(.blue).underline()
            let source = try XCTUnwrap(mixed._resolve(context: child, referenceDate: Date(), options: .allowsTextSuffix))
            guard case let .styledText(_, _, _, previous) = source.runs[source.runs.count - 2],
                  case let .styledText(_, _, _, attachment) = source.runs.last else { return XCTFail() }
            XCTAssertEqual(attachment.fontResource?.pointSize, 17)
            XCTAssertEqual(attachment.foregroundColor, .blue)
            XCTAssertEqual(attachment.underlineStyle, previous.underlineStyle)
            XCTAssertEqual(attachment.fontResource, previous.fontResource)
        }
    }

    // ASSERTIONS textSuffixCustomAttachmentObserved
    func testLineAttachmentAggregatesCustomAttributesWithoutReplacingItsLine() throws {
        try withGraph { _, inputs, host in
            let context = GraphTextResolutionContext(environment: inputs.cachedEnvironment.value.environment.value,
                                                      sceneResources: host.sceneResources)
            let text = Text(verbatim: "A").customAttribute(SuffixFirstAttribute()) +
                Text(verbatim: "B").customAttribute(SuffixSecondAttribute())
            let owner = try XCTUnwrap(text._resolveStyledText(context: context, referenceDate: Date(),
                archiveOptions: .init(), features: .produceTextLayout, sizeFitting: false))
            let line = try XCTUnwrap(Text.Suffix.truncated(text).resolve(text: owner).line)
            let attachment = LineAttachment(line: line, bounds: line.typographicBounds)
            XCTAssertNotNil(attachment.customAttributes.value(for: SuffixFirstAttribute.self))
            XCTAssertNotNil(attachment.customAttributes.value(for: SuffixSecondAttribute.self))
            XCTAssertEqual(attachment.line, line)
        }
    }

    private func rule<Value, Body>(_ attribute: Attribute<Value>, as type: Body.Type) throws -> Body {
        var visitor = SuffixRuleVisitor<Body>()
        attribute.visitBody(&visitor)
        return try XCTUnwrap(visitor.body)
    }

    private func testFont(size: CGFloat) -> VUI.Font {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        return .file(root.appendingPathComponent("Sources/VUI/Resources/Fonts/Roboto/Roboto-VariableFont_wdth,wght.ttf"), size: size)
    }

    private func withGraph(_ body: (_AGGraph, _GraphInputs, TestViewRendererHost) throws -> Void) throws {
        let previous = appContext
        appContext = SuffixTestAppContext()
        defer { appContext = previous }
        let host = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: host)
        host.storage = viewGraph
        var environment = EnvironmentValues()
        environment.font = testFont(size: 23)
        environment.defaultFontRenderingMode = .vector()
        environment.displayScale = 2
        environment.typesettingConfiguration.language = .explicit(Locale.Language(identifier: "en"))
        try viewGraph.data.withCurrent {
            let graph = viewGraph.data.graph
            let inputs = _GraphInputs(time: graph.makeInput(value: Time(seconds: 0)),
                phase: graph.makeInput(value: _GraphInputs.Phase()),
                environment: graph.makeInput(value: environment), transaction: graph.makeInput(value: Transaction()))
            try body(graph, inputs, host)
        }
    }
}

private struct SuffixFirstAttribute: TextAttribute {}
private struct SuffixSecondAttribute: TextAttribute {}

private struct SuffixRuleVisitor<Value>: AttributeBodyVisitor {
    var body: Value?
    mutating func visit<Body: _AttributeBody>(body: UnsafePointer<Body>) {
        self.body = body.pointee as? Value
    }
}

private struct UnusedSuffixTestKey: EnvironmentKey {
    static let defaultValue = 0
}

private final class SuffixTestAppContext: AppContext {
    let graphicsDeviceContext: GraphicsDeviceContext? = nil
    let audioDeviceContext: AudioDeviceContext? = nil
    var appWindowsController: AppWindowsController? { nil }
    func resourceData(forURL url: URL) -> (any DataProtocol)? { nil }
    func setResource(data: (any DataProtocol)?, forURL url: URL) {}
}
