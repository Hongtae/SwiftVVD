import XCTest
@testable import VUI

private struct DisplayListEnvironmentProbeKey: EnvironmentKey {
    static let defaultValue = 0
}

private extension EnvironmentValues {
    var displayListEnvironmentProbe: Int {
        get { self[DisplayListEnvironmentProbeKey.self] }
        set { self[DisplayListEnvironmentProbeKey.self] = newValue }
    }
}

final class DisplayListGraphicsRendererTests: XCTestCase {
    func testTextRendererCarrierShapesAndLayoutCollectionsMatchObservedSurface() throws {
        XCTAssertEqual(MemoryLayout<TextProxy>.size, 8)
        XCTAssertEqual(MemoryLayout<Text.Layout>.size, 24)
        XCTAssertEqual(MemoryLayout<Text.Layout.Line>.size, 44)
        XCTAssertEqual(MemoryLayout<Text.Layout.Run>.size, 48)
        XCTAssertEqual(MemoryLayout<Text.Layout.RunSlice>.size, 64)
        XCTAssertEqual(MemoryLayout<Text.Layout.CharacterIndex>.size, 8)
        XCTAssertEqual(MemoryLayout<Text.Layout.TypographicBounds>.size, 48)
        XCTAssertEqual(MemoryLayout<Text.Layout.DrawingOptions>.size, 4)
        XCTAssertEqual(Text.Layout.DrawingOptions.disablesSubpixelQuantization.rawValue, 1)

        let face = TextRendererTestTypeface()
        var first = GraphicsContext.ResolvedText.Glyph(
            scalar: "A".unicodeScalars.first!,
            face: face
        )
        first.advance.width = 10
        first.ascender = 8
        first.descender = -2
        var attributes = _TextAttributeValues()
        attributes.set(_AnyTextAttribute(TextRendererTestAttribute(value: 7)))
        first.attributes = attributes

        var second = GraphicsContext.ResolvedText.Glyph(
            scalar: "B".unicodeScalars.first!,
            face: face
        )
        second.advance.width = 10
        second.ascender = 8
        second.descender = -2
        second.attributes = attributes

        let resolved = GraphicsContext.ResolvedText(runs: [], scaleFactor: 2)
        let layout = resolved.makeLayout(
            lineGlyphs: [GraphicsContext.ResolvedText.LineGlyphs(
                glyphs: [first, second],
                ascender: 8,
                descender: -2,
                width: 20
            )],
            layoutDirection: .leftToRight
        )

        XCTAssertEqual(layout.count, 1)
        XCTAssertFalse(layout.isTruncated)
        let line = try XCTUnwrap(layout.first)
        XCTAssertEqual(line.origin, CGPoint(x: 0, y: 4))
        XCTAssertEqual(line.typographicBounds.width, 10)
        XCTAssertEqual(line.count, 1)
        let run = try XCTUnwrap(line.first)
        XCTAssertEqual(run.count, 2)
        XCTAssertEqual(run.characterIndices.count, 2)
        XCTAssertEqual(run[TextRendererTestAttribute.self]?.value, 7)
        XCTAssertEqual(run.layoutDirection, .leftToRight)
        XCTAssertEqual(run.typographicBounds.width, 10)
        let slice = run[0..<1]
        XCTAssertEqual(slice.characterIndices.count, 1)
        XCTAssertEqual(slice[TextRendererTestAttribute.self]?.value, 7)
        XCTAssertEqual(slice.typographicBounds.width, 5)

        XCTAssertEqual(
            Mirror(reflecting: layout).children.compactMap(\.label),
            ["lines", "isTruncated", "numberOfLines"]
        )
        XCTAssertEqual(
            Mirror(reflecting: line).children.compactMap(\.label),
            ["_line", "origin", "drawingOptions"]
        )
        XCTAssertEqual(
            Mirror(reflecting: run).children.compactMap(\.label),
            ["line", "index", "lineOrigin", "baseDrawingOptions", "layoutRenderer"]
        )
    }

    func testCustomRendererTextUsesDisplayPaddingAndBypassesStaticDrawingCache() throws {
        let resolved = GraphicsContext.ResolvedText(runs: [], scaleFactor: 1)
        let styledText = ResolvedStyledText.StringDrawing(resolvedText: resolved, version: 1)
        let box = TextRendererTestBox()
        let view = StyledTextContentView(text: styledText, renderer: box)
        let seed = DisplayList.Seed(DisplayList.Version(forUpdate: ()))
        let frame = CGRect(x: 20, y: 30, width: 40, height: 15)
        let displayBounds = CGRect(x: 13, y: 25, width: 58, height: 27)
        var list = DisplayList()
        list.appendTextItem(
            view,
            size: frame.size,
            foreground: .color(.red),
            bounds: frame,
            displayBounds: displayBounds,
            seed: seed
        )

        let item = try XCTUnwrap(list.items.first)
        guard case let .content(content) = item.value,
              case let .text(text) = content.value else {
            return XCTFail("missing typed text content")
        }
        XCTAssertEqual(text.frame, frame)
        XCTAssertEqual(text.command.bounds, displayBounds)
        XCTAssertNil(text.makeDrawing())

        let renderer = DisplayList.GraphicsRenderer()
        renderer.beginPass(at: .zero)
        XCTAssertNil(renderer.resolveTextCallback(text, seed: seed, scale: 1))
        renderer.endPass()
        XCTAssertEqual(renderer.textCallbackCount, 0)
    }

    func testDynamicTextProducesPlaceholderAndBypassesStaticDrawingCache() throws {
        let face = TextRendererTestTypeface()
        let resolved = GraphicsContext.ResolvedText(
            runs: [.text([face], "dynamic")],
            scaleFactor: 1
        )
        let storage = NSMutableAttributedString(attributedString: resolved.attributedStorage)
        storage.addAttribute(
            .updateSchedule,
            value: true,
            range: NSRange(location: 0, length: storage.length)
        )
        let styledText = ResolvedStyledText.StringDrawing(
            storage: storage,
            resolvedText: resolved,
            version: 1
        )
        let view = StyledTextContentView(text: styledText, renderer: nil)
        let seed = DisplayList.Seed(DisplayList.Version(forUpdate: ()))
        var list = DisplayList()
        list.appendTextItem(
            view,
            size: CGSize(width: 80, height: 20),
            foreground: .color(.red),
            bounds: CGRect(x: 0, y: 0, width: 80, height: 20),
            seed: seed
        )
        let item = try XCTUnwrap(list.items.first)
        guard case let .content(content) = item.value,
              case let .text(text) = content.value else {
            return XCTFail("missing typed text content")
        }

        let renderer = DisplayList.GraphicsRenderer()
        renderer.beginPass(at: .zero)
        let placeholder = try XCTUnwrap(renderer.resolveDynamicTextPlaceholder(text))
        XCTAssertTrue(placeholder.text === styledText)
        XCTAssertEqual(placeholder.size, CGSize(width: 80, height: 20))
        XCTAssertNil(renderer.resolveTextCallback(text, seed: seed, scale: 2))
        renderer.endPass()
        XCTAssertEqual(renderer.textCallbackCount, 0)
    }

    func testDisplayListVersionAllocatesMonotonicUpdateTokens() {
        let first = DisplayList.Version(forUpdate: ())
        let second = DisplayList.Version(forUpdate: ())
        XCTAssertGreaterThan(second.value, first.value)

        let decoded = DisplayList.Version(decodedValue: second.value + 100)
        let afterDecoded = DisplayList.Version(forUpdate: ())
        XCTAssertGreaterThan(afterDecoded.value, decoded.value)
    }

    func testTypedTextContentSurvivesAffineTransformation() {
        let styledText = ResolvedStyledText(version: 7, needsDrawingGroup: true)
        let view = StyledTextContentView(
            text: styledText,
            renderer: nil,
            needsDrawingGroup: true
        )
        let seed = DisplayList.Seed(DisplayList.Version(forUpdate: ()))
        let frame = CGRect(x: 5, y: 7, width: 80, height: 20)
        var source = DisplayList()
        source.appendTextItem(
            view,
            size: frame.size,
            foreground: .color(.red),
            bounds: frame,
            seed: seed
        )

        XCTAssertFalse(StyledTextContentView.animatesSize)
        XCTAssertEqual(source.items.count, 1)
        guard case let .content(sourceContent) = source.items[0].value,
              case let .text(sourceText) = sourceContent.value else {
            return XCTFail("text producer should emit typed text content")
        }
        XCTAssertTrue(sourceText.view.text === styledText)
        XCTAssertNil(sourceText.view.renderer)
        XCTAssertTrue(sourceText.view.needsDrawingGroup)
        XCTAssertEqual(sourceText.size, frame.size)
        XCTAssertTrue(sourceText.transform.isIdentity)

        let transform = CGAffineTransform(translationX: 11, y: 13)
        var transformed = DisplayList()
        transformed.appendTransformedItem(
            source.items[0],
            affineTransform: transform
        )

        guard case let .content(transformedContent) = transformed.items[0].value,
              case let .text(transformedText) = transformedContent.value else {
            return XCTFail("affine transformation should preserve typed text content")
        }
        XCTAssertEqual(transformedContent.seed, seed)
        XCTAssertEqual(transformedText.transform, transform)
        XCTAssertEqual(
            transformedText.command.bounds,
            frame.applying(transform).standardized
        )
    }

    func testGraphicsRendererPromotesReusesAndEvictsTextCallbacks() throws {
        let resolved = GraphicsContext.ResolvedText(runs: [], scaleFactor: 1)
        let styledText = ResolvedStyledText.StringDrawing(
            resolvedText: resolved,
            version: 1
        )
        let view = StyledTextContentView(
            text: styledText,
            renderer: nil
        )
        let seed = DisplayList.Seed(DisplayList.Version(forUpdate: ()))
        var list = DisplayList()
        list.appendTextItem(
            view,
            size: CGSize(width: 40, height: 20),
            foreground: .color(.red),
            bounds: CGRect(x: 0, y: 0, width: 40, height: 20),
            seed: seed
        )
        let item = try XCTUnwrap(list.items.first)
        guard case let .content(content) = item.value,
              case let .text(text) = content.value else {
            return XCTFail("missing typed text content")
        }

        let renderer = DisplayList.GraphicsRenderer()
        renderer.beginPass(at: .zero)
        let first = try XCTUnwrap(renderer.resolveTextCallback(
            text,
            seed: seed,
            scale: 1
        ))
        renderer.endPass()
        XCTAssertEqual(renderer.textCallbackCount, 1)

        renderer.beginPass(at: Time(seconds: 1))
        let reused = try XCTUnwrap(renderer.resolveTextCallback(
            text,
            seed: seed,
            scale: 1
        ))
        renderer.endPass()
        XCTAssertTrue(first === reused)
        XCTAssertEqual(renderer.textCallbackCount, 1)

        renderer.beginPass(at: Time(seconds: 2))
        let replaced = try XCTUnwrap(renderer.resolveTextCallback(
            text,
            seed: DisplayList.Seed(DisplayList.Version(forUpdate: ())),
            scale: 1
        ))
        renderer.endPass()
        XCTAssertFalse(reused === replaced)
        XCTAssertEqual(renderer.textCallbackCount, 1)

        renderer.beginPass(at: Time(seconds: 3))
        renderer.endPass()
        XCTAssertEqual(renderer.textCallbackCount, 0)
    }

    func testTextCallbackReplaysThroughCurrentStateWithinRoundedScaleBucket() throws {
        let resolved = GraphicsContext.ResolvedText(runs: [], scaleFactor: 1)
        let styledText = ResolvedStyledText.StringDrawing(resolvedText: resolved, version: 1)
        let view = StyledTextContentView(text: styledText, renderer: nil)
        let seed = DisplayList.Seed(DisplayList.Version(forUpdate: ()))
        var list = DisplayList()
        list.appendTextItem(
            view,
            size: CGSize(width: 40, height: 20),
            foreground: .color(.red),
            bounds: CGRect(x: 0, y: 0, width: 40, height: 20),
            seed: seed
        )
        let item = try XCTUnwrap(list.items.first)
        guard case let .content(content) = item.value,
              case let .text(text) = content.value else {
            return XCTFail("missing typed text content")
        }

        var replayState = text
        replayState.frame.origin = CGPoint(x: 80, y: 30)
        replayState.shading = .color(.blue)
        replayState.transform = CGAffineTransform(
            translationX: 11,
            y: 13
        ).scaledBy(x: 1.2, y: 0.8)

        let renderer = DisplayList.GraphicsRenderer()
        renderer.beginPass(at: .zero)
        let firstBucket = try XCTUnwrap(renderer.resolveTextCallback(
            text,
            seed: seed,
            scale: 1.49
        ))
        renderer.endPass()

        renderer.beginPass(at: Time(seconds: 1))
        let replayedWithCurrentState = try XCTUnwrap(renderer.resolveTextCallback(
            replayState,
            seed: seed,
            scale: 0.2
        ))
        renderer.endPass()
        XCTAssertTrue(firstBucket === replayedWithCurrentState)

        renderer.beginPass(at: Time(seconds: 2))
        let secondBucket = try XCTUnwrap(renderer.resolveTextCallback(
            replayState,
            seed: seed,
            scale: 1.5
        ))
        renderer.endPass()
        XCTAssertFalse(replayedWithCurrentState === secondBucket)

        renderer.beginPass(at: Time(seconds: 3))
        let reusedSecondBucket = try XCTUnwrap(renderer.resolveTextCallback(
            text,
            seed: seed,
            scale: 2.49
        ))
        renderer.endPass()
        XCTAssertTrue(secondBucket === reusedSecondBucket)
    }

    func testTransformedContentPreservesCacheIdentityAndChangeTokens() {
        let identity = _DisplayList_Identity(decodedValue: 37)
        let version = DisplayList.Version(value: 0x12345)
        let seed = DisplayList.Seed(version)
        let item = DisplayList.Item(
            command: .closure(bounds: CGRect(x: 2, y: 3, width: 4, height: 5)),
            identity: identity,
            version: version,
            seed: seed
        ) { _ in }
        let transform = CGAffineTransform(translationX: 11, y: 13)

        var list = DisplayList()
        list.appendTransformedItem(item, affineTransform: transform)
        list.appendTransformedDebugItem(item, affineTransform: transform)

        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.debugItems.count, 1)
        for transformed in [list.items[0], list.debugItems[0]] {
            XCTAssertEqual(transformed.identity, identity)
            XCTAssertEqual(transformed.version.value, version.value)
            guard case let .content(content) = transformed.value else {
                return XCTFail("transformed item should remain content")
            }
            XCTAssertEqual(content.seed, seed)
            XCTAssertEqual(
                content.command.bounds,
                CGRect(x: 13, y: 16, width: 4, height: 5)
            )
        }
    }

    func testTransformedContentPreservesDetachedRenderEnvironment() throws {
        var trackedEnvironment = EnvironmentValues.tracking()
        trackedEnvironment.displayListEnvironmentProbe = 37
        let renderEnvironment = trackedEnvironment.untrackedCopy()
        let bounds = CGRect(x: 2, y: 3, width: 4, height: 5)

        var source = DisplayList()
        source.appendItem(
            bounds: bounds,
            environment: renderEnvironment
        ) { _ in }

        let sourceItem = try XCTUnwrap(source.items.first)
        guard case let .content(sourceContent) = sourceItem.value else {
            return XCTFail("source item should carry content")
        }
        XCTAssertEqual(sourceContent.environment?.displayListEnvironmentProbe, 37)
        XCTAssertNil(sourceContent.environment?.tracker)

        var transformed = DisplayList()
        transformed.appendTransformedItem(
            sourceItem,
            affineTransform: CGAffineTransform(translationX: 11, y: 13)
        )

        let transformedItem = try XCTUnwrap(transformed.items.first)
        guard case let .content(transformedContent) = transformedItem.value else {
            return XCTFail("transformed item should carry content")
        }
        XCTAssertEqual(transformedContent.environment?.displayListEnvironmentProbe, 37)
        XCTAssertNil(transformedContent.environment?.tracker)
    }

    func testDisplayListPreservesUnifiedContentAndEffectOrder() {
        var nested = DisplayList()
        nested.appendItem(bounds: CGRect(x: 2, y: 3, width: 4, height: 5)) { _ in }

        var list = DisplayList()
        list.appendItem(bounds: CGRect(x: 0, y: 0, width: 1, height: 1)) { _ in }
        list.appendEffect(.opacity(0.5), contents: nested)
        list.appendItem(bounds: CGRect(x: 6, y: 7, width: 8, height: 9)) { _ in }

        XCTAssertEqual(list.items.count, 3)
        guard case .content = list.items[0].value else {
            return XCTFail("first item should remain content")
        }
        guard case .effect(.opacity(0.5), _) = list.items[1].value else {
            return XCTFail("second item should remain the opacity effect")
        }
        guard case .content = list.items[2].value else {
            return XCTFail("third item should remain content")
        }
        XCTAssertEqual(list.renderItems.count, 2)
        XCTAssertEqual(list.effects.count, 1)
    }

    func testGraphicsRendererReusesAnimatorByItemIndexUntilCompletion() {
        let renderer = DisplayList.GraphicsRenderer()
        let list = animationList(
            identity: _DisplayList_Identity(decodedValue: 41),
            from: 0,
            to: 1
        )

        let initial = renderer.sample(list: list, at: Time(seconds: 0))
        XCTAssertEqual(opacity(in: initial), 0, accuracy: 0.0001)
        XCTAssertEqual(renderer.animatorCount, 1)
        XCTAssertEqual(renderer.nextTime.seconds, 0, accuracy: 0.0001)

        let firstStateSample = renderer.sample(list: list, at: Time(seconds: 0.1))
        XCTAssertEqual(opacity(in: firstStateSample), 0, accuracy: 0.0001)
        XCTAssertEqual(renderer.animatorCount, 1)
        XCTAssertEqual(renderer.nextTime.seconds, 0.1, accuracy: 0.0001)

        let delayedStateSample = renderer.sample(list: list, at: Time(seconds: 0.2))
        XCTAssertEqual(opacity(in: delayedStateSample), 0, accuracy: 0.0001)

        let running = renderer.sample(list: list, at: Time(seconds: 0.3))
        XCTAssertGreaterThan(opacity(in: running), 0)
        XCTAssertLessThan(opacity(in: running), 1)

        let completed = renderer.sample(list: list, at: Time(seconds: 1.4))
        XCTAssertEqual(opacity(in: completed), 1, accuracy: 0.0001)
        XCTAssertEqual(renderer.animatorCount, 1)
        XCTAssertEqual(renderer.nextTime.seconds, .infinity)

        _ = renderer.sample(list: DisplayList(), at: Time(seconds: 1.5))
        XCTAssertEqual(renderer.animatorCount, 0)
    }

    func testGraphicsRendererSamplesAnimationsInsideTypedStyleContents() throws {
        let nested = animationList(
            identity: _DisplayList_Identity(decodedValue: 47),
            from: 0,
            to: 1
        )
        var list = DisplayList()
        list.appendOpacityItem(
            bounds: CGRect(x: 0, y: 0, width: 20, height: 10),
            opacity: 0.5,
            contents: nested
        )

        let renderer = DisplayList.GraphicsRenderer()
        for time in [0.0, 0.1, 0.2] {
            _ = renderer.sample(list: list, at: Time(seconds: time))
        }
        let running = renderer.sample(list: list, at: Time(seconds: 0.3))

        let item = try XCTUnwrap(running.items.first)
        guard case let .content(content) = item.value,
              case let .style(style) = content.value else {
            return XCTFail("sampled item should remain typed style content")
        }
        let nestedItem = try XCTUnwrap(style.contents.items.first)
        guard case let .effect(.opacity(value), _) = nestedItem.value else {
            return XCTFail("typed style contents should contain the sampled animation effect")
        }
        XCTAssertGreaterThan(value, 0)
        XCTAssertLessThan(value, 1)
        XCTAssertEqual(renderer.animatorCount, 1)
        XCTAssertEqual(renderer.nextTime.seconds, 0.3, accuracy: 0.0001)
    }

    func testGraphicsRendererSamplesAnimationsInsideTypedCrossFadeBranches() throws {
        let bounds = CGRect(x: 0, y: 0, width: 20, height: 10)
        let source = animationList(
            identity: _DisplayList_Identity(decodedValue: 49),
            from: 0,
            to: 1
        )
        var list = DisplayList()
        list.appendCrossFadeItem(
            sourceItems: source.items,
            sourceBounds: bounds,
            sourceOutputBounds: bounds,
            targetItems: [],
            targetBounds: nil,
            targetOutputBounds: nil,
            bounds: bounds,
            sourceFraction: 0.5,
            targetFraction: 0
        )

        let renderer = DisplayList.GraphicsRenderer()
        for time in [0.0, 0.1, 0.2] {
            _ = renderer.sample(list: list, at: Time(seconds: time))
        }
        let running = renderer.sample(list: list, at: Time(seconds: 0.3))

        let item = try XCTUnwrap(running.items.first)
        guard case let .content(content) = item.value,
              case let .crossFade(crossFade) = content.value else {
            return XCTFail("sampled item should remain typed cross-fade content")
        }
        let sourceItem = try XCTUnwrap(crossFade.source?.contents.items.first)
        guard case let .effect(.opacity(value), _) = sourceItem.value else {
            return XCTFail("typed cross-fade branch should contain the sampled animation effect")
        }
        XCTAssertGreaterThan(value, 0)
        XCTAssertLessThan(value, 1)
        XCTAssertNil(crossFade.target)
        XCTAssertEqual(renderer.animatorCount, 1)
        XCTAssertEqual(renderer.nextTime.seconds, 0.3, accuracy: 0.0001)
    }

    func testGraphicsRendererSeparatesAnimatorsByExplicitItemIdentity() {
        let first = animationItem(
            identity: _DisplayList_Identity(decodedValue: 51),
            from: 0,
            to: 1
        )
        let second = animationItem(
            identity: _DisplayList_Identity(decodedValue: 52),
            from: 1,
            to: 0
        )
        var list = DisplayList()
        list.items = [first, second]

        let renderer = DisplayList.GraphicsRenderer()
        let sampled = renderer.sample(list: list, at: Time(seconds: 0))

        XCTAssertEqual(renderer.animatorCount, 2)
        XCTAssertEqual(sampled.items.count, 2)
        XCTAssertEqual(opacity(in: sampled, item: 0), 0, accuracy: 0.0001)
        XCTAssertEqual(opacity(in: sampled, item: 1), 1, accuracy: 0.0001)
    }

    private func animationList(
        identity: _DisplayList_Identity,
        from: Double,
        to: Double
    ) -> DisplayList {
        var list = DisplayList()
        list.items = [animationItem(identity: identity, from: from, to: to)]
        return list
    }

    private func animationItem(
        identity: _DisplayList_Identity,
        from: Double,
        to: Double
    ) -> DisplayList.Item {
        var contents = DisplayList()
        contents.appendItem(bounds: CGRect(x: 0, y: 0, width: 20, height: 10)) { _ in }
        let animation = DisplayList.OpacityAnimation(
            from: _OpacityEffect(opacity: from),
            to: _OpacityEffect(opacity: to),
            animation: .linear(duration: 1)
        )
        return DisplayList.Item(
            effect: .animation(animation),
            contents: contents,
            identity: identity
        )
    }

    private func opacity(in list: DisplayList, item: Int = 0) -> Float {
        guard list.items.indices.contains(item),
              case let .effect(.opacity(value), _) = list.items[item].value
        else {
            XCTFail("sampled animation item should carry an opacity effect")
            return .nan
        }
        return value
    }
}

private struct TextRendererTestAttribute: TextAttribute {
    var value: Int
}

private final class TextRendererTestTypeface: Typeface {
    func glyph(for c: UnicodeScalar) -> TypefaceGlyph? { nil }
    func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint { .zero }
    func hasGlyph(for: UnicodeScalar) -> Bool { true }
    var lineHeight: CGFloat { 10 }
    var ascender: CGFloat { 8 }
    var descender: CGFloat { -2 }
    var identifier: String { "text-renderer-test" }
    func isEqual(to other: any Typeface) -> Bool { self === (other as AnyObject) }
    func hashIdentity(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    func purgeResources(reason: ResourcePurgeReason) {}
}

private final class TextRendererTestBox: TextRendererBoxBase {
    override var environment: EnvironmentValues { EnvironmentValues() }
    override func draw(layout: Text.Layout, in context: inout GraphicsContext) {}
    override func textLayoutBounds(size: CGSize, text: TextProxy) -> CGRect {
        CGRect(origin: .zero, size: size)
    }
    override func sizeThatFits(proposal: ProposedViewSize, text: TextProxy) -> CGSize {
        text.sizeThatFits(proposal)
    }
    override var displayPadding: EdgeInsets {
        EdgeInsets(top: 5, leading: 7, bottom: 7, trailing: 11)
    }
}
