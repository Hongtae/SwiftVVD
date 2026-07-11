import XCTest
@testable import VUI

final class DisplayListGraphicsRendererTests: XCTestCase {
    func testDisplayListVersionAllocatesMonotonicUpdateTokens() {
        let first = DisplayList.Version(forUpdate: ())
        let second = DisplayList.Version(forUpdate: ())
        XCTAssertGreaterThan(second.value, first.value)

        let decoded = DisplayList.Version(decodedValue: second.value + 100)
        let afterDecoded = DisplayList.Version(forUpdate: ())
        XCTAssertGreaterThan(afterDecoded.value, decoded.value)
    }

    func testTextContentSeedChangesOnlyWithTypedContentInputs() {
        let state = _TextDisplayListContentState()
        let size = CGSize(width: 120, height: 30)
        let first = state.contentSeed(
            resolvedVersion: 10,
            size: size,
            needsDrawingGroup: false
        )
        let unchanged = state.contentSeed(
            resolvedVersion: 10,
            size: size,
            needsDrawingGroup: false
        )
        let resized = state.contentSeed(
            resolvedVersion: 10,
            size: CGSize(width: 121, height: 30),
            needsDrawingGroup: false
        )
        let regrouped = state.contentSeed(
            resolvedVersion: 10,
            size: CGSize(width: 121, height: 30),
            needsDrawingGroup: true
        )
        let replaced = state.contentSeed(
            resolvedVersion: 11,
            size: CGSize(width: 121, height: 30),
            needsDrawingGroup: true
        )

        XCTAssertEqual(unchanged, first)
        XCTAssertNotEqual(resized, unchanged)
        XCTAssertNotEqual(regrouped, resized)
        XCTAssertNotEqual(replaced, regrouped)
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
        let styledText = ResolvedStyledText(
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
