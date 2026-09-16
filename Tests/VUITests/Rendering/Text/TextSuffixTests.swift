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

    // ASSERTIONS textSuffixRetainedMetricsLayoutObserved
    // ASSERTIONS textSuffixLastRunAttributesObserved
    func testTruncatedSuffixRetainsSeparateFragmentsAndStartingAttributes() throws {
        let short = Text(verbatim: "A").foregroundColor(.blue) +
            Text(verbatim: "\nB").font(testFont(size: 31)).foregroundColor(.green)
        for alignment: TextAlignment in [.leading, .center, .trailing] {
            try withSuffixManager(short, alignment: alignment) { manager in
                let size = CGSize(width: 100, height: 120)
                let metrics = manager.computeMetrics(scale: 1, requestedSize: .init(size, majorAxis: .vertical),
                                                     minorAxisIsFlexible: false)
                let layout = try XCTUnwrap(metrics.layout)
                XCTAssertEqual(metrics.base.numberOfLines, 1)
                XCTAssertEqual(metrics.flags, .isTruncated)
                XCTAssertFalse(layout.isTruncated)
                XCTAssertEqual(layout.count, 3)
                guard layout.count == 3 else { return }
                XCTAssertEqual(layout[0].lastRunAttributes?.foregroundColor, .blue)
                XCTAssertEqual(layout[1].lastRunAttributes?.foregroundColor, .blue)
                XCTAssertEqual(layout[1].lastRunAttributes?.fontResource?.pointSize, 23)
                XCTAssertEqual(layout[2].lastRunAttributes?.foregroundColor, .red)
                XCTAssertEqual(layout[2].lastRunAttributes?.fontResource?.pointSize, 11)
                XCTAssertEqual(layout[2].drawingOptions.rawValue, 2)
                XCTAssertEqual(manager.suffix.line?.drawingOptions.rawValue, 0)
                XCTAssertEqual(layout[0].origin.y, layout[2].origin.y)
                XCTAssertEqual(layout[1].origin.x, layout[0].origin.x + layout[0].typographicBounds.width, accuracy: 1e-8)
                XCTAssertEqual(layout[2].origin.x, layout[1].origin.x + layout[1].typographicBounds.width, accuracy: 1e-8)
                let width = layout.reduce(0) { $0 + $1.typographicBounds.width }
                let factor: CGFloat = alignment == .center ? 0.5 : alignment == .trailing ? 1 : 0
                XCTAssertEqual(layout[0].origin.x, (100 - width) * factor, accuracy: 1e-8)
                XCTAssertEqual(metrics.base.size.width, ceil(width * 2) / 2)
                let placed = try XCTUnwrap(manager.makeLayout(in: CGRect(x: 17, y: 9, width: 100, height: 120),
                    with: size, shading: .foreground, layoutDirection: .leftToRight))
                XCTAssertEqual(placed.count, 3)
                XCTAssertFalse(placed.isTruncated)
                XCTAssertTrue(manager.cache.entries.isEmpty)
                for (raw, line) in zip(layout, placed) {
                    XCTAssertEqual(line.origin.x - raw.origin.x, 17 + manager.drawingMargins.leading, accuracy: 1e-8)
                    XCTAssertEqual(line.origin.y - raw.origin.y, 9 + manager.drawingMargins.top, accuracy: 1e-8)
                    XCTAssertEqual(line.drawingOptions, raw.drawingOptions)
                }
            }
        }
    }

    // ASSERTIONS textSuffixRetainedMetricsLayoutObserved
    func testSuffixRetruncationFailureAndScalarCacheSeparation() throws {
        for width: CGFloat in [8, 42, 70, 100, 150] {
            try withSuffixManager(Text(verbatim: "A A A A A A A A").foregroundColor(.blue), suffixSize: 23) { manager in
                let size = CGSize(width: width, height: 120)
                let scalar = manager.metrics(in: size, layoutMargins: nil)
                let cache = manager.cache
                let metrics = manager.computeMetrics(scale: 1, requestedSize: .init(size, majorAxis: .vertical),
                                                     minorAxisIsFlexible: false)
                if width == 8 {
                    XCTAssertNil(metrics.layout)
                } else {
                    let layout = try XCTUnwrap(metrics.layout)
                    XCTAssertEqual(layout.count, width < 100 ? 1 : 2)
                    XCTAssertTrue(layout.isTruncated)
                    XCTAssertEqual(metrics.base.numberOfLines, 1)
                    XCTAssertEqual(layout.last?.drawingOptions.rawValue, width < 100 ? 0 : 2)
                    if width == 100 {
                        XCTAssertEqual(layout[0].flatMap { $0.characterIndices }.count, 1)
                        XCTAssertEqual(layout[0].lastRunAttributes?.foregroundColor, .blue)
                    }
                }
                manager.resetCache()
                manager.glyphLayoutCache.purgeResources(reason: .lowMemory)
                let rebuilt = manager.computeMetrics(scale: 1, requestedSize: .init(size, majorAxis: .vertical),
                                                     minorAxisIsFlexible: false)
                XCTAssertEqual(metrics.base.size, rebuilt.base.size)
                XCTAssertEqual(metrics.layout?.count, rebuilt.layout?.count)
                XCTAssertEqual(manager.cache.entries.count, cache.entries.count)
                XCTAssertEqual(manager.cache.entries.first?.metrics.size, scalar.size)
                XCTAssertNil(manager.cache.ideal)
            }
        }
        try withSuffixManager(Text(verbatim: "A")) { manager in
            let metrics = manager.computeMetrics(scale: 1, requestedSize: .init(CGSize(width: 100, height: 120),
                majorAxis: .vertical), minorAxisIsFlexible: false)
            XCTAssertNil(metrics.layout)
            XCTAssertFalse(metrics.base.hasTruncatedRanges)
        }
    }

    // ASSERTIONS textSuffixLastRunAttributesObserved
    func testEmptyLineSuppliesAttributesWithoutPublicRuns() throws {
        try withSuffixManager(Text(verbatim: "\nB").foregroundColor(.blue)) { manager in
            let layout = try XCTUnwrap(manager.computeMetrics(scale: 1,
                requestedSize: .init(CGSize(width: 100, height: 120), majorAxis: .vertical),
                minorAxisIsFlexible: false).layout)
            XCTAssertEqual(layout.count, 3)
            guard layout.count == 3 else { return }
            XCTAssertTrue(layout[0].isEmpty)
            XCTAssertEqual(layout[0].typographicBounds.width, 0)
            XCTAssertEqual(layout[0].lastRunAttributes?.foregroundColor, .blue)
            XCTAssertEqual(layout[1].lastRunAttributes?.foregroundColor, .blue)
            XCTAssertFalse(layout.isTruncated)
        }
    }

    // ASSERTIONS textSuffixLastRunAttributesObserved
    func testStyledTrailingSpaceAndCoreLineAttributesKeepTheirOwnSelection() throws {
        let text = Text(verbatim: "AA").foregroundColor(.blue) +
            Text(verbatim: " ").font(testFont(size: 31)).foregroundColor(.green) +
            Text(verbatim: "\nB").foregroundColor(.blue)
        for alignment: TextAlignment in [.leading, .center, .trailing] {
            try withSuffixManager(text, alignment: alignment) { manager in
                let layout = try XCTUnwrap(manager.computeMetrics(scale: 1,
                    requestedSize: .init(CGSize(width: 100, height: 120), majorAxis: .vertical),
                    minorAxisIsFlexible: false).layout)
                XCTAssertEqual(layout.count, 3)
                guard layout.count == 3 else { return }
                XCTAssertEqual(layout[0].count, 2)
                XCTAssertEqual(layout[0].lastRunAttributes?.foregroundColor, .blue)
                XCTAssertEqual(layout[1].lastRunAttributes?.foregroundColor, .blue)
                let bodyWidth: CGFloat = 30.0078125
                let spaceWidth: CGFloat = 7.689453125
                let tokenWidth: CGFloat = 15.3857421875
                let suffixWidth: CGFloat = 28.10693359375
                let delta: CGFloat = (100 - bodyWidth - tokenWidth - suffixWidth) *
                    (alignment == .center ? 0.5 : alignment == .trailing ? 1 : 0)
                XCTAssertEqual(layout[0].typographicBounds.width,
                    bodyWidth + (alignment == .trailing ? 0 : spaceWidth), accuracy: 1 / 64)
                XCTAssertEqual(layout[0].origin.x, delta + (alignment == .trailing ? spaceWidth : 0), accuracy: 1 / 64)
                XCTAssertEqual(layout[1].origin.x, bodyWidth + delta, accuracy: 1 / 64)
                XCTAssertEqual(layout[2].origin.x, bodyWidth + tokenWidth + delta, accuracy: 1 / 64)
            }
        }
        try withSuffixManager(Text(verbatim: "AA AA AA AA").foregroundColor(.blue).kerning(2).underline().baselineOffset(3)) { manager in
            let layout = try XCTUnwrap(manager.computeMetrics(scale: 1,
                requestedSize: .init(CGSize(width: 100, height: 120), majorAxis: .vertical),
                minorAxisIsFlexible: false).layout)
            XCTAssertEqual(layout[0].lastRunAttributes?.kern, 2)
            XCTAssertEqual(layout[0].lastRunAttributes?.baselineOffset, 3)
            XCTAssertNotNil(layout[0].lastRunAttributes?.underlineStyle)
            XCTAssertEqual(layout.last?.lastRunAttributes?.foregroundColor, .red)
        }
    }

    // ASSERTIONS textSuffixRetainedMetricsLayoutObserved
    func testAlwaysVisibleContinuationKeepsLogicalCountAndUntruncatedLayoutFlag() throws {
        try withSuffixManager(Text(verbatim: "A A A A A A A A"), suffixSize: 23,
                              alwaysVisible: true, lineLimit: 2) { manager in
            let metrics = manager.computeMetrics(scale: 1,
                requestedSize: .init(CGSize(width: 100, height: 120), majorAxis: .vertical),
                minorAxisIsFlexible: false)
            let layout = try XCTUnwrap(metrics.layout)
            XCTAssertEqual(metrics.base.numberOfLines, 2)
            XCTAssertEqual(metrics.flags, .isTruncated)
            XCTAssertEqual(layout.count, 3)
            XCTAssertFalse(layout.isTruncated)
            XCTAssertEqual(layout.last?.drawingOptions.rawValue, 2)
        }
    }

    // ASSERTIONS textSuffixRetainedMetricsLayoutObserved
    func testReplacementPreservesEarlierLineAlignmentAndSourceCacheConfiguration() throws {
        for alignment: TextAlignment in [.center, .trailing] {
            try withSuffixManager(Text(verbatim: "A\nBB BB BB BB BB BB"), alignment: alignment, lineLimit: 2) { manager in
                let size = CGSize(width: 100, height: 120)
                let suffix = manager.suffix
                manager.suffix = .none
                let original = try XCTUnwrap(manager.makeLayout(in: .zero, with: size,
                    shading: .foreground, layoutDirection: .leftToRight))
                manager.suffix = suffix
                let layout = try XCTUnwrap(manager.makeLayout(in: .zero, with: size,
                    shading: .foreground, layoutDirection: .leftToRight))
                XCTAssertEqual(layout.count, 3)
                XCTAssertEqual(layout.first?.origin, original.first?.origin)
                XCTAssertEqual(layout.first?.typographicBounds, original.first?.typographicBounds)
                let raw = try XCTUnwrap(manager.prepareDrawing(in: .zero, with: size, applyingMarginOffsets: true))
                let atoms = try XCTUnwrap(raw.layout).glyphAtoms()
                XCTAssertTrue(atoms.contains { $0.scalar == "…" })
                XCTAssertEqual(String(String.UnicodeScalarView(atoms.suffix(5).map(\.scalar))), " more")
                XCTAssertTrue(manager.cache.entries.isEmpty)
            }
        }
    }

    private func withSuffixManager(_ text: Text, alignment: TextAlignment = .leading, suffixSize: CGFloat = 11,
                                   alwaysVisible: Bool = false, lineLimit: Int = 1,
                                   _ body: (ResolvedStyledText.TextLayoutManager) throws -> Void) throws {
        try withGraph { _, inputs, host in
            var environment = inputs.cachedEnvironment.value.environment.value
            environment.lineLimit = lineLimit
            environment.multilineTextAlignment = alignment
            let context = GraphTextResolutionContext(environment: environment, sceneResources: host.sceneResources)
            let suffix = Text(verbatim: " more").font(testFont(size: suffixSize)).foregroundColor(.red)
            let owner = try XCTUnwrap(suffix._resolveStyledText(context: context, referenceDate: Date(),
                archiveOptions: .init(), features: .produceTextLayout, sizeFitting: false))
            environment[TextSuffixKey.self] = (alwaysVisible ? Text.Suffix.alwaysVisible(suffix) : .truncated(suffix))
                .resolve(text: owner)
            let manager = try XCTUnwrap(text._resolveStyledText(context: GraphTextResolutionContext(
                environment: environment, sceneResources: host.sceneResources), referenceDate: Date(),
                archiveOptions: .init(), features: [], sizeFitting: false, options: .allowsTextSuffix)
                as? ResolvedStyledText.TextLayoutManager)
            try body(manager)
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
