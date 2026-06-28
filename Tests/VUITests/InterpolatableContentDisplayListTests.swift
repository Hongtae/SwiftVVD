import XCTest
@testable import VUI

private enum InterpolatableContentProbeLog {
    nonisolated(unsafe) static var modifyTransitionCalls = 0
    nonisolated(unsafe) static var defaultAnimationCalls = 0

    static func reset() {
        modifyTransitionCalls = 0
        defaultAnimationCalls = 0
    }
}

private struct ProbeInterpolatableContent: Equatable, InterpolatableContent {
    var value: Int

    func modifyTransition(state: inout ContentTransition.State, to target: Self) {
        InterpolatableContentProbeLog.modifyTransitionCalls += 1
    }

    func defaultAnimation(to target: Self) -> Animation? {
        InterpolatableContentProbeLog.defaultAnimationCalls += 1
        return .linear(duration: 0.25)
    }
}

private struct VersionedTransitionContent: Equatable, InterpolatableContent {
    static var defaultTransition: ContentTransition { .opacity }

    var value: Int
}

final class InterpolatableContentDisplayListTests: XCTestCase {
    func testDisplayListSeedSurface() {
        XCTAssertEqual(DisplayList.Seed().value, 0)
        XCTAssertEqual(DisplayList.Seed(decodedValue: 42).value, 42)
        XCTAssertEqual(DisplayList.Seed.undefined.value, 2)
        XCTAssertEqual(DisplayList.Seed(DisplayList.Version(value: 0)).value, 0)
        XCTAssertEqual(DisplayList.Seed(DisplayList.Version(value: 1)).value, 3)
        XCTAssertEqual(DisplayList.Seed(DisplayList.Version(value: 0x0001_0000)).value, 0x0043)

        var zero = DisplayList.Seed()
        zero.invalidate()
        XCTAssertEqual(zero.value, 0)

        var undefined = DisplayList.Seed.undefined
        undefined.invalidate()
        XCTAssertEqual(undefined.value, 0xfffd)
        undefined.invalidate()
        XCTAssertEqual(undefined.value, 3)
    }

    func testDisplayListRenderTraversalIncludesContentTransitionEffects() {
        var list = makeDisplayList(debugItemCount: 1, itemCount: 2)
        let retained = makeDisplayList(debugItemCount: 2, itemCount: 1)
        let ignored = makeDisplayList(debugItemCount: 3, itemCount: 3)

        list.effects.append(
            DisplayList.EffectItem(
                effect: .contentTransition(ContentTransition.State(transition: .opacity)),
                contents: retained
            )
        )
        list.effects.append(
            DisplayList.EffectItem(
                effect: .state(StrongHash(words: (1, 2, 3, 4, 5))),
                contents: ignored
            )
        )

        var renderItemCount = 0
        list.forEachRenderItem { _ in
            renderItemCount += 1
        }

        XCTAssertEqual(renderItemCount, 6)
    }

    func testInterpolatorAnimationAndEffectCarrierSurface() {
        let hash = StrongHash(words: (1, 2, 3, 4, 5))
        let animation = DisplayList.InterpolatorAnimation(value: hash, animation: .linear(duration: 0.25))
        XCTAssertEqual(animation.value, hash)
        XCTAssertNotNil(animation.animation)

        let group = DisplayList.InterpolatorGroup()
        switch DisplayList.Effect.interpolatorRoot(group, CGPoint(x: 1, y: 2), CGSize(width: 3, height: 4)) {
        case let .interpolatorRoot(storedGroup, origin, offset):
            XCTAssertTrue(storedGroup === group)
            XCTAssertEqual(origin, CGPoint(x: 1, y: 2))
            XCTAssertEqual(offset, CGSize(width: 3, height: 4))
        default:
            XCTFail("missing interpolator root carrier")
        }

        switch DisplayList.Effect.interpolatorLayer(group, 7) {
        case let .interpolatorLayer(storedGroup, serial):
            XCTAssertTrue(storedGroup === group)
            XCTAssertEqual(serial, 7)
        default:
            XCTFail("missing interpolator layer carrier")
        }

        switch DisplayList.Effect.interpolatorAnimation(animation) {
        case let .interpolatorAnimation(stored):
            XCTAssertEqual(stored.value, hash)
            XCTAssertNotNil(stored.animation)
        default:
            XCTFail("missing interpolator animation carrier")
        }
    }

    func testInterpolatorGroupClassSurface() {
        let group = DisplayList.InterpolatorGroup()
        XCTAssertTrue(group.maxDuration.isInfinite)
        XCTAssertTrue(group.nextUpdate(after: .zero).seconds.isInfinite)

        group.maxDuration = 0.25
        XCTAssertEqual(group.maxDuration, 0.25)

        let unary = DisplayList.UnaryInterpolatorGroup()
        let base: DisplayList.InterpolatorGroup = unary
        XCTAssertTrue(base === unary)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 0)

        unary.updateTime(Time(seconds: 1.25))
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 1.25)

        unary.maxDuration = 0.5
        unary.reset()
        XCTAssertTrue(unary.maxDuration.isInfinite)
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertFalse(unary.supportsVariableFrameDuration)
    }

    func testDisplayListInterpolationBoundsSurface() {
        var first = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let second = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )

        first.append(contentsOf: second)
        XCTAssertEqual(first.debugItems.count, 2)
        XCTAssertEqual(first.interpolationBounds, CGRect(x: 0, y: 0, width: 50, height: 45))
    }

    func testRBDisplayListInterpolatorCarrierSurface() {
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.transition.rawValue, "transition")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.animation.rawValue, "animation")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.animationSequencer.rawValue, "animationSequencer")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.fadeInOutFraction.rawValue, "fadeInOutFraction")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.colorSpace.rawValue, "colorSpace")
        XCTAssertEqual(RBDisplayListInterpolatorOptionKey.rasterizationScale.rawValue, "rasterizationscale")

        let from = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let to = makeDisplayList(
            debugItemCount: 2,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )
        let opacity = ContentTransition.opacity.rbTransition
        let interpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .transition: opacity,
                .rasterizationScale: Float(2),
            ]
        )

        XCTAssertEqual(interpolator.from.debugItems.count, 1)
        XCTAssertEqual(interpolator.to.debugItems.count, 2)
        XCTAssertTrue((interpolator.options[.transition] as? RBTransition) === opacity)
        XCTAssertEqual(interpolator.options[.rasterizationScale] as? Float, 2)
        XCTAssertEqual(interpolator.activeDuration, 1)
        XCTAssertFalse(interpolator.isIdentity)
        XCTAssertTrue(interpolator.onlyFades)
        XCTAssertEqual(interpolator.maxAbsoluteVelocity(withProgress: 0.5), 0)
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0), CGRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0.5), CGRect(x: 10, y: 2.5, width: 20, height: 30))
        XCTAssertEqual(interpolator.boundingRect(withProgress: 1), CGRect(x: 20, y: 5, width: 30, height: 40))
        XCTAssertEqual(interpolator.copyContents(withProgress: 0).debugItems.count, 1)
        XCTAssertEqual(
            interpolator.copyContents(withProgress: 0.5).interpolationBounds,
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(interpolator.copyContents(withProgress: 0.5).debugItems.count, 1)
        XCTAssertEqual(interpolator.contents(withProgress: 1).debugItems.count, 2)

        let drawableFrom = makeDisplayList(
            debugItemCount: 1,
            itemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let drawableTo = makeDisplayList(
            debugItemCount: 2,
            itemCount: 1,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )
        let drawableInterpolator = RBDisplayListInterpolator(
            from: drawableFrom,
            to: drawableTo,
            options: [.transition: opacity]
        )
        let drawableMidpoint = drawableInterpolator.copyContents(withProgress: 0.5)
        XCTAssertEqual(drawableMidpoint.items.count, 1)
        XCTAssertEqual(drawableMidpoint.debugItems.count, 1)
        XCTAssertEqual(
            drawableMidpoint.interpolationBounds,
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(drawableInterpolator.copyContents(withProgress: 0).items.count, 1)
        XCTAssertEqual(drawableInterpolator.copyContents(withProgress: 1).items.count, 1)

        let renderOptionInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .transition: opacity,
                .fadeInOutFraction: Float(0.33),
                .rasterizationScale: Float(3),
                .colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
            ]
        )
        XCTAssertEqual(renderOptionInterpolator.options[.fadeInOutFraction] as? Float, 0.33)
        XCTAssertEqual(renderOptionInterpolator.options[.rasterizationScale] as? Float, 3)
        XCTAssertEqual(renderOptionInterpolator.activeDuration, 1)
        XCTAssertEqual(
            renderOptionInterpolator.boundingRect(withProgress: 0.5),
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )
        XCTAssertEqual(renderOptionInterpolator.maxAbsoluteVelocity(withProgress: 0.5), 0)

        let retargetedFrom = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 10, y: 10, width: 10, height: 10)
        )
        interpolator.setFrom(retargetedFrom)
        XCTAssertEqual(interpolator.from.interpolationBounds, retargetedFrom.interpolationBounds)
        XCTAssertEqual(interpolator.boundingRect(withProgress: 0), CGRect(x: 10, y: 10, width: 10, height: 10))

        let animationOnly = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [.animation: Animation.linear(duration: 0.5).rbAnimation]
        )
        XCTAssertEqual(animationOnly.activeDuration, 0)

        let copied = interpolator.copy() as? RBDisplayListInterpolator
        XCTAssertFalse(copied === interpolator)
        XCTAssertEqual(copied?.from.debugItems.count, 1)
        XCTAssertEqual(copied?.to.debugItems.count, 2)
        XCTAssertTrue(copied?.onlyFades ?? false)

        let sameCountMoved = RBDisplayListInterpolator(
            from: makeDisplayList(
                debugItemCount: 1,
                bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
            ),
            to: makeDisplayList(
                debugItemCount: 1,
                bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
            ),
            options: [.transition: opacity]
        )
        XCTAssertEqual(sameCountMoved.activeDuration, 1)

        let animatedInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [
                .transition: opacity,
                .animation: Animation.linear(duration: 2).rbAnimation,
            ]
        )
        XCTAssertEqual(animatedInterpolator.activeDuration, 2)
        XCTAssertEqual(
            animatedInterpolator.boundingRect(withProgress: 1),
            CGRect(x: 10, y: 2.5, width: 20, height: 30)
        )

        let customEffect = ContentTransition.Effect(
            type: ContentTransition.EffectType(type: 3),
            begin: 0,
            duration: 0,
            events: 3
        )
        let customTransition = ContentTransition(method: .diff, effects: [customEffect]).rbTransition
        let customInterpolator = RBDisplayListInterpolator(
            from: from,
            to: to,
            options: [.transition: customTransition]
        )
        XCTAssertFalse(customInterpolator.onlyFades)

        let effectSamples: [(ContentTransition.EffectType, Bool)] = [
            (.opacity, true),
            (.scale(0.5), false),
            (.translation(CGSize(width: 40, height: -10)), false),
            (.blur(radius: 12), false),
            (.translation(scale: CGSize(width: 0.5, height: 0.25)), false),
            (.relativeBlur(scale: CGSize(width: 0.5, height: 0.25)), false),
        ]
        for (effectType, expectedOnlyFades) in effectSamples {
            let transition = ContentTransition(
                method: .diff,
                effects: [
                    ContentTransition.Effect(
                        type: effectType,
                        begin: 0,
                        duration: 0,
                        events: 3
                    ),
                ]
            ).rbTransition
            let effectInterpolator = RBDisplayListInterpolator(
                from: drawableFrom,
                to: drawableTo,
                options: [.transition: transition]
            )
            let midpoint = effectInterpolator.copyContents(withProgress: 0.5)

            XCTAssertEqual(effectInterpolator.activeDuration, 1)
            XCTAssertEqual(effectInterpolator.onlyFades, expectedOnlyFades)
            XCTAssertEqual(effectInterpolator.maxAbsoluteVelocity(withProgress: 0.5), 0)
            XCTAssertEqual(midpoint.items.count, drawableMidpoint.items.count)
            XCTAssertEqual(midpoint.debugItems.count, drawableMidpoint.debugItems.count)
            XCTAssertEqual(midpoint.interpolationBounds, drawableMidpoint.interpolationBounds)
        }
    }

    func testRBAnimationAndSequencerCarrierSurface() {
        let linear = Animation.linear(duration: 0.25).rbAnimation
        XCTAssertEqual(linear.activeDuration, 0.25)
        XCTAssertEqual(linear.evaluateAtTime(0), 0)
        XCTAssertEqual(linear.evaluateAtTime(0.25), 1)
        XCTAssertEqual(linear.evaluateAtTime(0.125), 0.5, accuracy: 0.001)

        let delayed = Animation.linear(duration: 0.25).delay(0.5).rbAnimation
        XCTAssertEqual(delayed.activeDuration, 0.75)
        XCTAssertEqual(delayed.evaluateAtTime(0.5), 0)
        XCTAssertEqual(delayed.evaluateAtTime(0.625), 0.5, accuracy: 0.001)

        let sped = Animation.linear(duration: 0.25).speed(2).rbAnimation
        XCTAssertEqual(sped.activeDuration, 0.125)
        XCTAssertEqual(sped.evaluateAtTime(0.0625), 0.5, accuracy: 0.001)

        let repeated = Animation.linear(duration: 0.25).repeatCount(2).rbAnimation
        XCTAssertEqual(repeated.activeDuration, 0.5)
        XCTAssertEqual(repeated.evaluateAtTime(0.375), 0.5, accuracy: 0.001)
        XCTAssertEqual(repeated.evaluateAtTime(0.5), 0)

        let effects = RBAnimationSequencerEffects()
        effects.delayOffset = 0.25
        effects.delayScale = 2

        let sequencer = RBAnimationSequencer()
        sequencer.distanceMode = 1
        sequencer.sequencesGlyphs = true
        sequencer.startPoint = CGPoint(x: 1, y: 2)
        sequencer.endPoint = CGPoint(x: 3, y: 4)
        sequencer.added = effects

        XCTAssertEqual(sequencer.distanceMode, 1)
        XCTAssertTrue(sequencer.sequencesGlyphs)
        XCTAssertEqual(sequencer.startPoint, CGPoint(x: 1, y: 2))
        XCTAssertEqual(sequencer.endPoint, CGPoint(x: 3, y: 4))
        XCTAssertEqual(sequencer.added?.delayOffset, 0.25)
        XCTAssertEqual(sequencer.added?.delayScale, 2)
    }

    func testRBDisplayListInterpolatorSequencerDurationSurface() {
        let from = makeDisplayList(
            debugItemCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 20)
        )
        let to = makeDisplayList(
            debugItemCount: 2,
            bounds: CGRect(x: 20, y: 5, width: 30, height: 40)
        )
        let transition = ContentTransition(
            method: .diff,
            effects: [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: 40, height: -10)),
                    begin: 0,
                    duration: 0,
                    events: 3
                ),
            ]
        ).rbTransition

        func makeEffects(offset: Float, scale: Float) -> RBAnimationSequencerEffects {
            let effects = RBAnimationSequencerEffects()
            effects.delayOffset = offset
            effects.delayScale = scale
            return effects
        }

        func makeSequencer(
            distanceMode: Int32 = 1,
            endPoint: CGPoint = CGPoint(x: 100, y: 50),
            added: RBAnimationSequencerEffects? = nil,
            mixed: RBAnimationSequencerEffects? = nil,
            removed: RBAnimationSequencerEffects? = nil
        ) -> RBAnimationSequencer {
            let sequencer = RBAnimationSequencer()
            sequencer.distanceMode = distanceMode
            sequencer.sequencesGlyphs = true
            sequencer.startPoint = .zero
            sequencer.endPoint = endPoint
            sequencer.added = added
            sequencer.mixed = mixed
            sequencer.removed = removed
            return sequencer
        }

        func makeInterpolator(_ sequencer: RBAnimationSequencer) -> RBDisplayListInterpolator {
            RBDisplayListInterpolator(
                from: from,
                to: to,
                options: [
                    .transition: transition,
                    .animationSequencer: sequencer,
                ]
            )
        }

        XCTAssertEqual(makeInterpolator(makeSequencer()).activeDuration, 1)
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(added: makeEffects(offset: 0.25, scale: 2))
            ).activeDuration,
            1
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(removed: makeEffects(offset: 0.25, scale: 2))
            ).activeDuration,
            1
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.25, scale: 0))
            ).activeDuration,
            1.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.5, scale: 0))
            ).activeDuration,
            1.5,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2))
            ).activeDuration,
            2.0194153785705566,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    distanceMode: 0,
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            2.009999990463257,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(
                    endPoint: CGPoint(x: 10, y: 0),
                    mixed: makeEffects(offset: 0.25, scale: 2)
                )
            ).activeDuration,
            3.25,
            accuracy: 0.0005
        )
        XCTAssertEqual(
            makeInterpolator(
                makeSequencer(mixed: makeEffects(offset: 0.25, scale: 2))
            ).maxAbsoluteVelocity(withProgress: 0.5),
            0
        )
    }

    func testUnaryInterpolatorGroupTracksLayerState() {
        let unary = DisplayList.UnaryInterpolatorGroup()
        let current = makeDisplayList(debugItemCount: 1)
        let target = makeDisplayList(debugItemCount: 2)
        var state = ContentTransition.State(
            transition: .opacity,
            options: .addsDrawingGroup
        )
        state.animation = .linear(duration: 0.2)

        let output = unary.update(
            contentSeed: DisplayList.Seed(decodedValue: 5),
            current: current,
            target: target,
            state: state,
            time: Time(seconds: 2),
            animatesSize: false,
            defersRender: false,
            supportsVFD: true
        )

        XCTAssertEqual(unary.lastContentSeed, DisplayList.Seed(decodedValue: 5))
        XCTAssertTrue(unary.supportsVariableFrameDuration)
        XCTAssertTrue(unary.rasterizationOptions.isAccelerated)
        XCTAssertEqual(unary.layer.contents.displayList.debugItems.count, 2)
        XCTAssertEqual(unary.layer.removedCount, 1)
        XCTAssertEqual(unary.layer.removed.first?.rbTransition.method, ContentTransition.Method.diff.method)
        XCTAssertEqual(unary.layer.removed.first?.rbTransition.effects.first?.type, ContentTransition.EffectType.opacity.type)
        XCTAssertEqual(unary.layer.currentTime.seconds, 2)
        XCTAssertEqual(unary.layer.removed.first?.startTime.seconds, 2)
        XCTAssertNotNil(unary.layer.removed.first?.interpolator)
        XCTAssertTrue(unary.layer.removed.first?.interpolator?.onlyFades ?? false)
        XCTAssertNotNil(unary.layer.removed.first?.interpolator?.options[.transition])
        XCTAssertNotNil(unary.layer.removed.first?.interpolator?.animation)
        XCTAssertNil(unary.layer.removed.first?.interpolator?.options[.rasterizationScale])
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.animation?.activeDuration, 0.2)
        XCTAssertEqual(unary.layer.removed.first?.activeDuration, 0.2)
        XCTAssertEqual(unary.layer.nextUpdateTime.seconds, 2.2, accuracy: 0.000_001)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.2, accuracy: 0.000_001)
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.copyContents(withProgress: 0).debugItems.count, 1)
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.copyContents(withProgress: 0.1).debugItems.count, 1)
        XCTAssertEqual(unary.layer.removed.first?.interpolator?.contents(withProgress: 0.2).debugItems.count, 2)
        XCTAssertFalse(unary.layer.needsUpdate)
        XCTAssertEqual(output.effects.count, 1)

        unary.updateTime(Time(seconds: 2.1))
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.2, accuracy: 0.000_001)

        unary.updateTime(Time(seconds: 2.2))
        let completedOutput = unary.apply(to: target)
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertTrue(unary.layer.nextUpdateTime.seconds.isInfinite)
        XCTAssertEqual(unary.nextUpdate(after: Time(seconds: 9)).seconds, 2.2, accuracy: 0.000_001)
        XCTAssertTrue(completedOutput.effects.isEmpty)

        unary.reset()
        XCTAssertEqual(unary.layer.removedCount, 0)
        XCTAssertFalse(unary.supportsVariableFrameDuration)
    }

    func testInterpolatorLayerOnlyRetainsWhenTransitionStateIsSupplied() {
        var layer = DisplayList.InterpolatorLayer()
        let first = makeDisplayList(debugItemCount: 1)
        let second = makeDisplayList(debugItemCount: 1)

        layer.setDisplayList(
            first,
            origin: .zero,
            version: DisplayList.Version(value: 1)
        )
        layer.setDisplayList(
            second,
            origin: .zero,
            version: DisplayList.Version(value: 2)
        )

        XCTAssertEqual(layer.removedCount, 0)
        XCTAssertEqual(layer.contents.version?.value, 2)

        layer.setDisplayList(
            first,
            origin: .zero,
            version: DisplayList.Version(value: 3),
            state: ContentTransition.State(transition: .opacity)
        )

        XCTAssertEqual(layer.removedCount, 1)
        XCTAssertEqual(layer.removed.first?.contents.version?.value, 2)
        XCTAssertEqual(layer.contents.version?.value, 3)
    }

    func testInterpolatedDisplayListRetainsPreviousListOnFirstSameSurfaceChange() throws {
        let graph = AttributeGraph()

        try AttributeGraph.$current.withValue(graph) {
            let firstList = makeDisplayList(debugItemCount: 1)
            let secondList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: firstList)
            let content = graph.makeInput(value: VersionedTransitionContent(value: 0))
            let group = DisplayList.UnaryInterpolatorGroup()
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 0)
            XCTAssertEqual(group.layer.contents.version?.value, 1)

            displayList.setValue(secondList)
            content.setValue(VersionedTransitionContent(value: 1))
            let updated = output.value

            XCTAssertEqual(updated.effects.count, 1)
            XCTAssertEqual(updated.effects.first?.contents.debugItems.count, 1)
            XCTAssertEqual(group.lastContentSeed.value, 2)
            XCTAssertEqual(group.layer.removedCount, 1)
            XCTAssertEqual(group.layer.removed.first?.contents.version?.value, 1)
            XCTAssertEqual(group.layer.contents.version?.value, 2)
            XCTAssertEqual(group.layer.removed.first?.interpolator?.from.debugItems.count, 1)
            XCTAssertEqual(group.layer.removed.first?.interpolator?.to.debugItems.count, 1)
        }
    }

    func testInterpolatedDisplayListIdentityTransitionSyncsCurrentWithoutRemoval() throws {
        let graph = AttributeGraph()
        InterpolatableContentProbeLog.reset()

        try AttributeGraph.$current.withValue(graph) {
            let firstList = makeDisplayList(debugItemCount: 1)
            let secondList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: firstList)
            let content = graph.makeInput(value: ProbeInterpolatableContent(value: 0))
            let group = DisplayList.UnaryInterpolatorGroup()
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                group,
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 0)

            displayList.setValue(secondList)
            content.setValue(ProbeInterpolatableContent(value: 1))
            let updated = output.value

            XCTAssertEqual(InterpolatableContentProbeLog.modifyTransitionCalls, 1)
            XCTAssertEqual(InterpolatableContentProbeLog.defaultAnimationCalls, 1)
            XCTAssertEqual(updated.effects.count, 0)
            XCTAssertEqual(group.layer.removedCount, 0)
            XCTAssertEqual(group.layer.contents.version?.value, 2)
            XCTAssertEqual(group.layer.contents.displayList.debugItems.count, 1)
        }
    }

    func testUnaryInterpolatorGroupSchedulesViewGraphLayerDeadline() {
        let rendererHost = TestViewRendererHost()
        let viewGraph = ViewGraph(rootViewType: EmptyView.self, content: EmptyView(), rendererHost: rendererHost)
        rendererHost.storage = viewGraph

        let unary = DisplayList.UnaryInterpolatorGroup()
        let current = makeDisplayList(debugItemCount: 1)
        let target = makeDisplayList(debugItemCount: 2)
        var state = ContentTransition.State(transition: .opacity)
        state.animation = .linear(duration: 0.2)

        viewGraph.data.withCurrent {
            _ = unary.update(
                contentSeed: DisplayList.Seed(decodedValue: 7),
                current: current,
                target: target,
                state: state,
                time: Time(seconds: 2),
                animatesSize: false,
                defersRender: false,
                supportsVFD: false
            )
        }

        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2.2, accuracy: 0.000_001)

        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
        viewGraph.data.withCurrent {
            unary.updateTime(Time(seconds: 2.1))
        }
        XCTAssertEqual(viewGraph.nextUpdate.views.time.seconds, 2.2, accuracy: 0.000_001)

        viewGraph.nextUpdate = (ViewGraph.NextUpdate(), ViewGraph.NextUpdate())
        viewGraph.data.withCurrent {
            unary.updateTime(Time(seconds: 2.2))
            _ = unary.apply(to: target)
        }
        XCTAssertTrue(viewGraph.nextUpdate.views.time.seconds.isInfinite)
    }

    func testResolvedImageInterpolatableContentSurface() {
        let previousSemantics = Semantics.overrides
        defer { Semantics.overrides = previousSemantics }

        Semantics.overrides = Semantics.Overrides()
        XCTAssertEqual(GraphicsContext.ResolvedImage.defaultTransition, .interpolate)

        Semantics.overrides = Semantics.Overrides(
            build: _SemanticFeature<Semantics_v4>.prior,
            runtime: previousSemantics.runtime
        )
        XCTAssertEqual(GraphicsContext.ResolvedImage.defaultTransition, .identity)

        let image = makeResolvedImage()
        XCTAssertFalse(image.requiresTransition(to: makeResolvedImage()))
        XCTAssertTrue(image.requiresTransition(to: makeResolvedImage(baseline: 2)))
        XCTAssertTrue(
            image.requiresTransition(
                to: makeResolvedImage(textureTransform: CGAffineTransform(translationX: 1, y: 0))
            )
        )
        XCTAssertTrue(image.requiresTransition(to: makeResolvedImage(scaleFactor: 2)))

        var unchangedState = ContentTransition.State(transition: .interpolate)
        image.modifyTransition(state: &unchangedState, to: makeResolvedImage())
        XCTAssertEqual(unchangedState.transition, .interpolate)

        var changedState = ContentTransition.State(transition: .interpolate)
        image.modifyTransition(state: &changedState, to: makeResolvedImage(baseline: 2))
        XCTAssertEqual(changedState.transition, .opacity)

        var protectedState = ContentTransition.State(
            transition: .interpolate,
            options: .animatesDifferentContent
        )
        image.modifyTransition(state: &protectedState, to: makeResolvedImage(baseline: 2))
        XCTAssertEqual(protectedState.transition, .interpolate)
    }

    func testResolvedStyledTextInterpolatableContentSurface() {
        let previousSemantics = Semantics.overrides
        defer { Semantics.overrides = previousSemantics }

        Semantics.overrides = Semantics.Overrides()
        XCTAssertEqual(ResolvedStyledText.defaultTransition, .interpolate)

        Semantics.overrides = Semantics.Overrides(
            build: _SemanticFeature<Semantics_v4>.prior,
            runtime: previousSemantics.runtime
        )
        XCTAssertEqual(ResolvedStyledText.defaultTransition, .identity)

        let text = ResolvedStyledText(version: 1)
        XCTAssertFalse(text.requiresTransition(to: ResolvedStyledText(version: 1)))
        XCTAssertTrue(text.requiresTransition(to: ResolvedStyledText(version: 2)))
        XCTAssertFalse(
            ResolvedStyledText(version: 1, transitionText: "Hello")
                .requiresTransition(to: ResolvedStyledText(version: 2, transitionText: "Hello"))
        )
        XCTAssertTrue(
            ResolvedStyledText(version: 1, transitionText: "Hello")
                .requiresTransition(to: ResolvedStyledText(version: 2, transitionText: "World"))
        )
        XCTAssertTrue(text.appliesTransitionsForSizeChanges)
        XCTAssertFalse(text.addsDrawingGroup)
        XCTAssertTrue(ResolvedStyledText(version: 1, needsDrawingGroup: true).addsDrawingGroup)

        var unchangedState = ContentTransition.State(transition: .interpolate)
        text.modifyTransition(state: &unchangedState, to: ResolvedStyledText(version: 1))
        XCTAssertEqual(unchangedState.transition, .interpolate)

        var changedState = ContentTransition.State(transition: .interpolate)
        text.modifyTransition(state: &changedState, to: ResolvedStyledText(version: 2))
        XCTAssertEqual(changedState.transition, .text)

        var sameTextState = ContentTransition.State(transition: .interpolate)
        ResolvedStyledText(version: 1, transitionText: "Hello")
            .modifyTransition(
                state: &sameTextState,
                to: ResolvedStyledText(version: 2, transitionText: "Hello")
            )
        XCTAssertEqual(sameTextState.transition, .interpolate)

        var protectedState = ContentTransition.State(
            transition: .interpolate,
            options: .animatesDifferentContent
        )
        text.modifyTransition(state: &protectedState, to: ResolvedStyledText(version: 2))
        XCTAssertEqual(protectedState.transition, .interpolate)

        let environment = EnvironmentValues()
        XCTAssertEqual(Text(verbatim: "A")._resolveTransitionText(in: environment), "A")
        XCTAssertEqual((Text(verbatim: "A") + Text(verbatim: "B"))._resolveTransitionText(in: environment), "AB")
        XCTAssertNil(Text(Image(systemName: "star"))._resolveTransitionText(in: environment))
    }

    func testApplyInterpolatorGroupReplacesDisplayListOutput() throws {
        let graph = AttributeGraph()

        try AttributeGraph.$current.withValue(graph) {
            let sourceList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: sourceList)
            let content = graph.makeInput(value: ProbeInterpolatableContent(value: 0))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                DisplayList.InterpolatorGroup(),
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: true,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            XCTAssertNotEqual(outputID.rawValue, displayList.identifier.rawValue)
            let output = Attribute<DisplayList>(outputID).value
            XCTAssertEqual(output.debugItems.count, sourceList.debugItems.count)
        }
    }

    func testTextMakeViewAppliesResolvedStyledTextInterpolator() throws {
        let graph = AttributeGraph()

        try AttributeGraph.$current.withValue(graph) {
            let text = graph.makeInput(value: Text("Hello"))
            let outputs = Text._makeView(
                view: _GraphValue(_attribute: text),
                inputs: makeViewInputs(graph: graph)
            )

            XCTAssertEqual(outputs.preferences.values(for: ResourceList.Key.self).count, 1)
            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            XCTAssertTrue(graph.debugDescription(for: outputID).contains("(stateful)"))
            XCTAssertEqual(Attribute<DisplayList>(outputID).value.items.count, 0)
        }
    }

    func testResolvedStyledTextInterpolatorEmitsContentTransitionEffect() throws {
        let graph = AttributeGraph()

        try AttributeGraph.$current.withValue(graph) {
            let sourceList = makeDisplayList(debugItemCount: 1)
            let displayList = graph.makeInput(value: sourceList)
            let content = graph.makeInput(value: ResolvedStyledText(version: 0))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                DisplayList.InterpolatorGroup(),
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: false
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 0)

            content.setValue(ResolvedStyledText(version: 1))
            let updated = output.value
            XCTAssertEqual(updated.debugItems.count, 0)
            XCTAssertEqual(updated.effects.count, 1)
            XCTAssertEqual(updated.effects.first?.contents.debugItems.count, sourceList.debugItems.count)
            var renderItemCount = 0
            updated.forEachRenderItem { _ in
                renderItemCount += 1
            }
            XCTAssertEqual(renderItemCount, sourceList.debugItems.count)
            switch updated.effects.first?.effect {
            case let .some(.contentTransition(state)):
                XCTAssertEqual(state.transition, .text)
            case .none:
                XCTFail("missing content-transition effect")
            default:
                XCTFail("unexpected content-transition effect")
            }
        }
    }

    func testInterpolatedDisplayListReadsContentTransitionFallbackPath() throws {
        let graph = AttributeGraph()
        InterpolatableContentProbeLog.reset()

        try AttributeGraph.$current.withValue(graph) {
            let displayList = graph.makeInput(value: makeDisplayList(debugItemCount: 1))
            let content = graph.makeInput(value: ProbeInterpolatableContent(value: 0))
            var outputs = _ViewOutputs()
            outputs.preferences.append(DisplayList.Key.self, node: displayList.identifier)

            outputs.applyInterpolatorGroup(
                DisplayList.InterpolatorGroup(),
                content: content,
                inputs: makeViewInputs(graph: graph),
                animatesSize: false,
                defersRender: true
            )

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)

            _ = output.value
            XCTAssertEqual(InterpolatableContentProbeLog.modifyTransitionCalls, 0)
            XCTAssertEqual(InterpolatableContentProbeLog.defaultAnimationCalls, 0)

            content.setValue(ProbeInterpolatableContent(value: 1))
            let updated = output.value

            XCTAssertEqual(InterpolatableContentProbeLog.modifyTransitionCalls, 1)
            XCTAssertEqual(InterpolatableContentProbeLog.defaultAnimationCalls, 1)
            XCTAssertEqual(updated.effects.count, 0)
        }
    }

    private func makeDisplayList(
        debugItemCount: Int,
        itemCount: Int = 0,
        bounds: CGRect = CGRect(x: 0, y: 0, width: 10, height: 10)
    ) -> DisplayList {
        var list = DisplayList()
        for _ in 0..<debugItemCount {
            list.debugItems.append { _ in }
        }
        for _ in 0..<itemCount {
            list.items.append { _ in }
        }
        if debugItemCount > 0 || itemCount > 0 {
            list.recordInterpolationBounds(bounds)
        }
        return list
    }

    private func makeResolvedImage(
        baseline: CGFloat = 1,
        textureTransform: CGAffineTransform = .identity,
        scaleFactor: CGFloat = 1
    ) -> GraphicsContext.ResolvedImage {
        GraphicsContext.ResolvedImage(
            baseline: baseline,
            shading: nil,
            texture: nil,
            textureTransform: textureTransform,
            scaleFactor: scaleFactor
        )
    }

    private func makeViewInputs(graph: AttributeGraph) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let base = _GraphInputs(
            customInputs: PropertyList(),
            time: graph.makeInput(value: Time(seconds: 0)),
            cachedEnvironment: MutableBox(CachedEnvironment(environment: environment)),
            phase: graph.makeInput(value: Phase()),
            transaction: graph.makeInput(value: Transaction()),
            changedDebugProperties: 0,
            options: [],
            mergedInputs: []
        )
        return _ViewInputs(
            base: base,
            customInputs: PropertyList(),
            preferences: PreferencesInputs(
                keys: PreferenceKeys(),
                hostKeys: graph.makeInput(value: PreferenceKeys())
            ),
            transform: graph.makeInput(value: ViewTransform()),
            position: graph.makeInput(value: CGPoint.zero),
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 10, height: 10)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
