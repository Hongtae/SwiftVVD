import XCTest
@testable import VUI

private struct ProbeContentTransition: Transition {
    var effect: ContentTransition.Effect

    func body(content: Content, phase: TransitionPhase) -> Content {
        content
    }

    func _makeContentTransition(transition: inout _Transition_ContentTransition) {
        switch transition.operation {
        case .hasContentTransition:
            transition.result = .bool(true)
        case .effects:
            transition.result = .effects([effect])
        }
    }
}

private struct PlainContentTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> Content {
        content
    }
}

private typealias BlurReplaceBody = ModifiedContent<
    ModifiedContent<
        ModifiedContent<
            PlaceholderContentView<BlurReplaceTransition>,
            OpacityRendererEffect
        >,
        _BlurEffect
    >,
    _ScaleEffect
>

private struct CountingRendererEffect: _RendererEffect, MultiViewModifier {
    nonisolated(unsafe) static var effectValueCalls = 0

    var state: ContentTransition.State

    func effectValue(size: CGSize) -> DisplayList.Effect {
        Self.effectValueCalls += 1
        return .contentTransition(state)
    }

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        _RendererEffectSupport.makeView(
            effect: modifier,
            inputs: inputs,
            body: body
        )
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        _RendererEffectSupport.makeViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }
}

final class ContentTransitionHiddenSurfaceTests: XCTestCase {
    func testContentTransitionHiddenOptionsAndMethodConstants() {
        XCTAssertEqual(ContentTransition.Options.addsDrawingGroup.rawValue, 1)
        XCTAssertEqual(ContentTransition.Options.animatesDifferentContent.rawValue, 2)
        XCTAssertEqual(ContentTransition.Options.formsGroup.rawValue, 4)
        XCTAssertEqual(ContentTransition.Options.implicitGroup.rawValue, 8)
        XCTAssertEqual(ContentTransition.Options.inherited.rawValue, 1)

        XCTAssertEqual(ContentTransition.Method.diff.method, 1)
        XCTAssertEqual(ContentTransition.Method.forwards.method, 2)
        XCTAssertEqual(ContentTransition.Method.backwards.method, 3)
        XCTAssertEqual(ContentTransition.Method.prefix.method, 4)
        XCTAssertEqual(ContentTransition.Method.suffix.method, 5)
        XCTAssertEqual(ContentTransition.Method.binary.method, 6)
        XCTAssertEqual(ContentTransition.Method.none.method, 7)
        XCTAssertEqual(ContentTransition.Method.prefixAndSuffix.method, 8)

        XCTAssertEqual(ContentTransition.EffectType.opacity.type, 1)
        XCTAssertEqual(ContentTransition.EffectType.opacity.arg0, .none)
        XCTAssertEqual(ContentTransition.EffectType.opacity.arg1, .none)
        XCTAssertEqual(ContentTransition.EffectType.opacity(0), .opacity)
        XCTAssertEqual(ContentTransition.EffectType.opacity(0.25), .opacity)
        XCTAssertEqual(ContentTransition.EffectType.opacity(.nan), .opacity)
        XCTAssertEqual(ContentTransition.EffectType.matchMove.type, 5)
        XCTAssertEqual(ContentTransition.EffectType.matchMove.arg0, .none)
        XCTAssertEqual(ContentTransition.EffectType.matchMove.arg1, .none)

        var identity = ContentTransition.identity
        identity.applyEnvironmentValues(style: .animatedWidget, layoutDirection: .rightToLeft)
        XCTAssertTrue(identity.isIdentity)

        var opacity = ContentTransition.opacity
        opacity.applyEnvironmentValues(style: .animatedWidget, layoutDirection: .rightToLeft)
        XCTAssertFalse(opacity.isIdentity)
    }

    func testRasterizationOptionsSurface() {
        XCTAssertEqual(RasterizationOptions.Flags.isAccelerated.rawValue, 0x1)
        XCTAssertEqual(RasterizationOptions.Flags.isOpaque.rawValue, 0x2)
        XCTAssertEqual(RasterizationOptions.Flags.rendersAsynchronously.rawValue, 0x4)
        XCTAssertEqual(RasterizationOptions.Flags.prefersDisplayCompositing.rawValue, 0x8)
        XCTAssertEqual(RasterizationOptions.Flags.rendersFirstFrameAsync.rawValue, 0x10)
        XCTAssertEqual(RasterizationOptions.Flags.allowsPackedDrawable.rawValue, 0x20)
        XCTAssertEqual(RasterizationOptions.Flags.alphaOnly.rawValue, 0x40)
        XCTAssertEqual(RasterizationOptions.Flags.requiresLayer.rawValue, 0x80)
        XCTAssertEqual(RasterizationOptions.Flags.rgbaContext.rawValue, 0x100)
        XCTAssertEqual(RasterizationOptions.Flags.highRes.rawValue, 0x200)
        XCTAssertEqual(RasterizationOptions.Flags.fixedPixelFormat.rawValue, 0x400)
        XCTAssertEqual(RasterizationOptions.Flags.defaultFlags.rawValue, 0xA0)

        var options = RasterizationOptions()
        XCTAssertEqual(options.rbColorMode, -1)
        XCTAssertEqual(options.colorMode, .nonLinear)
        XCTAssertNil(options.allowedDynamicRange)
        XCTAssertEqual(options.maxDrawableCount, 3)
        XCTAssertEqual(options.flags, [.allowsPackedDrawable, .requiresLayer])
        XCTAssertFalse(options.isAccelerated)
        XCTAssertFalse(options.isOpaque)
        XCTAssertFalse(options.rendersAsynchronously)
        XCTAssertFalse(options.prefersDisplayCompositing)
        XCTAssertFalse(options.rendersFirstFrameAsynchronously)
        XCTAssertTrue(options.allowsPackedDrawable)
        XCTAssertTrue(options.requiresLayer)
        XCTAssertFalse(options.fixedPixelFormat)
        XCTAssertFalse(options.alphaOnly)
        XCTAssertEqual(options.resolvedColorMode, 0)

        options.isAccelerated = true
        options.isOpaque = true
        options.rendersAsynchronously = true
        options.prefersDisplayCompositing = true
        options.rendersFirstFrameAsynchronously = true
        options.allowsPackedDrawable = false
        options.requiresLayer = false
        options.fixedPixelFormat = true
        options.alphaOnly = true

        XCTAssertEqual(
            options.flags,
            [
                .isAccelerated,
                .isOpaque,
                .rendersAsynchronously,
                .prefersDisplayCompositing,
                .rendersFirstFrameAsync,
                .alphaOnly,
                .fixedPixelFormat,
            ]
        )
        XCTAssertEqual(options.resolvedColorMode, 9)

        options.colorMode = .linear
        XCTAssertEqual(options.resolvedColorMode, 10)
        options.colorMode = .extendedLinear
        XCTAssertEqual(options.resolvedColorMode, 10)
        options.rbColorMode = 42
        XCTAssertEqual(options.resolvedColorMode, 42)

        let dynamicRangeOptions = RasterizationOptions(allowedDynamicRange: .high)
        XCTAssertEqual(dynamicRangeOptions.allowedDynamicRange, .high)
        XCTAssertEqual(Image.DynamicRange.standard, .standard)
        XCTAssertNotEqual(Image.DynamicRange.standard, .high)
    }

    func testContentTransitionStateRasterizationOptions() {
        let defaultState = ContentTransition.State()
        let defaultOptions = defaultState.rasterizationOptions
        XCTAssertEqual(defaultOptions.rbColorMode, -1)
        XCTAssertEqual(defaultOptions.colorMode, .nonLinear)
        XCTAssertNil(defaultOptions.allowedDynamicRange)
        XCTAssertEqual(defaultOptions.maxDrawableCount, 3)
        XCTAssertEqual(defaultOptions.flags.rawValue, 0x20)
        XCTAssertFalse(defaultOptions.isAccelerated)
        XCTAssertFalse(defaultOptions.requiresLayer)
        XCTAssertTrue(defaultOptions.allowsPackedDrawable)

        let drawingGroupState = ContentTransition.State(options: .addsDrawingGroup)
        let drawingGroupOptions = drawingGroupState.rasterizationOptions
        XCTAssertEqual(drawingGroupOptions.flags.rawValue, 0x21)
        XCTAssertTrue(drawingGroupOptions.isAccelerated)
        XCTAssertFalse(drawingGroupOptions.requiresLayer)
        XCTAssertTrue(drawingGroupOptions.allowsPackedDrawable)
    }

    func testContentTransitionEffectRendererSurface() throws {
        var state = ContentTransition.State(
            transition: .opacity,
            style: .animatedWidget,
            animation: .linear(duration: 0.25),
            options: .addsDrawingGroup
        )
        state.applyDynamicTextAnimation(in: Transaction(animation: .easeIn))

        let effect = ContentTransitionEffect(state: state)
        switch effect.effectValue(size: CGSize(width: 20, height: 10)) {
        case let .contentTransition(value):
            XCTAssertEqual(value, state)
        default:
            XCTFail("unexpected renderer effect")
        }

        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let modifier = graph.makeInput(value: effect)
            var source = makeDisplayList(debugItemCount: 1)
            source.appendEffect(
                .contentTransition(ContentTransition.State(transition: .identity)),
                contents: DisplayList()
            )
            let sourceList = graph.makeInput(value: source)
            let outputs = ContentTransitionEffect._makeView(
                modifier: _GraphValue(_attribute: modifier),
                inputs: makeViewInputs(graph: graph)
            ) { _, _ in
                var outputs = _ViewOutputs()
                outputs.preferences.append(DisplayList.Key.self, node: sourceList.identifier)
                return outputs
            }

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID).value
            XCTAssertEqual(output.debugItems.count, 0)
            XCTAssertEqual(output.effects.count, 1)
            XCTAssertEqual(output.effects.first?.contents.debugItems.count, 1)
            XCTAssertEqual(output.effects.first?.contents.effects.count, 1)
            switch output.effects.first?.contents.effects.first?.effect {
            case let .some(.contentTransition(value)):
                XCTAssertEqual(value.transition, .identity)
            case .none:
                XCTFail("missing preserved content-transition effect")
            default:
                XCTFail("unexpected preserved effect")
            }
            switch output.effects.first?.effect {
            case let .some(.contentTransition(value)):
                XCTAssertEqual(value, state)
            case .none:
                XCTFail("missing content-transition effect")
            default:
                XCTFail("unexpected content-transition effect")
            }
        }
    }

    func testRendererEffectReadsAnimatedPositionProjection() throws {
        CountingRendererEffect.effectValueCalls = 0

        let graph = _AGGraph()
        try _AGGraph.withCurrent(graph) {
            let state = ContentTransition.State(transition: .opacity)
            let modifier = graph.makeInput(value: CountingRendererEffect(state: state))
            let sourceList = graph.makeInput(value: makeDisplayList(debugItemCount: 1))
            let normalPosition = graph.makeInput(value: CGPoint.zero)
            let animatedPosition = graph.makeInput(value: CGPoint(x: 2, y: 3))
            var inputs = makeViewInputs(graph: graph, position: normalPosition)
            var cachedEnvironment = inputs.base.cachedEnvironment.value
            cachedEnvironment.animatedFrame = CachedEnvironment.AnimatedFrame(
                position: normalPosition,
                size: inputs.size,
                pixelLength: graph.makeInput(value: CGFloat(1)),
                time: inputs.base.time,
                transaction: inputs.base.transaction,
                viewPhase: inputs.base.phase,
                animatedFrame: graph.makeInput(
                    value: ViewFrame(origin: .zero, size: ViewSize(width: 10, height: 10))
                ),
                _animatedPosition: animatedPosition,
                _animatedSize: inputs.size,
                _animatedCGSize: nil
            )
            inputs.base.cachedEnvironment = MutableBox(cachedEnvironment)

            let outputs = _RendererEffectSupport.makeView(
                effect: _GraphValue(_attribute: modifier),
                inputs: inputs
            ) { _, _ in
                var outputs = _ViewOutputs()
                outputs.preferences.append(DisplayList.Key.self, node: sourceList.identifier)
                return outputs
            }

            let outputID = try XCTUnwrap(outputs.preferences.value(for: DisplayList.Key.self))
            let output = Attribute<DisplayList>(outputID)
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(CountingRendererEffect.effectValueCalls, 1)

            normalPosition.setValue(CGPoint(x: 20, y: 30))
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(CountingRendererEffect.effectValueCalls, 1)

            animatedPosition.setValue(CGPoint(x: 40, y: 50))
            XCTAssertEqual(output.value.effects.count, 1)
            XCTAssertEqual(CountingRendererEffect.effectValueCalls, 2)
        }
    }

    func testBlurEffectSurface() {
        var effect = _BlurEffect(radius: 3, opaque: true)
        XCTAssertEqual(effect.radius, 3)
        XCTAssertTrue(effect.isOpaque)
        XCTAssertEqual(effect.animatableData, 3)

        effect.animatableData = 5
        XCTAssertEqual(effect.radius, 5)
        XCTAssertTrue(effect.isOpaque)
        XCTAssertEqual(effect, _BlurEffect(radius: 5, opaque: true))
        XCTAssertNotEqual(effect, _BlurEffect(radius: 5, opaque: false))
        XCTAssertNotEqual(effect, _BlurEffect(radius: 4, opaque: true))
    }

    func testContentTransitionHiddenStyleAndCustomTransitionStorage() {
        XCTAssertEqual(ContentTransition.Style.default.storage.rawValue, 0)
        XCTAssertEqual(ContentTransition.Style.sessionWidget.storage.rawValue, 1)
        XCTAssertEqual(ContentTransition.Style.animatedWidget.storage.rawValue, 2)

        let effect = ContentTransition.Effect(
            type: ContentTransition.EffectType(type: 3, arg0: .float(0.5), arg1: .int(7)),
            begin: 0.25,
            duration: 0.75,
            events: 3,
            flags: 1
        )
        let custom = ContentTransition(method: .prefixAndSuffix, effects: [effect])
        XCTAssertNotEqual(custom, .identity)
        XCTAssertEqual(effect.removeInverts(true).flags & 1, 1)
        XCTAssertEqual(effect.removeInverts(false).flags & 1, 0)

        let timelineBoth = ContentTransition.Effect(
            .matchMove,
            timeline: 0.25...0.75,
            appliesOnInsertion: true,
            appliesOnRemoval: true
        )
        XCTAssertEqual(timelineBoth.type, .matchMove)
        XCTAssertEqual(timelineBoth.begin, 0.25)
        XCTAssertEqual(timelineBoth.duration, 0.5)
        XCTAssertEqual(timelineBoth.events, 3)
        XCTAssertEqual(timelineBoth.flags, 0)

        XCTAssertEqual(
            ContentTransition.Effect(
                .opacity,
                timeline: 0.25...0.75,
                appliesOnInsertion: true,
                appliesOnRemoval: false
            ).events,
            1
        )
        XCTAssertEqual(
            ContentTransition.Effect(
                .opacity,
                timeline: 0.25...0.75,
                appliesOnInsertion: false,
                appliesOnRemoval: true
            ).events,
            2
        )
        XCTAssertEqual(
            ContentTransition.Effect(
                .opacity,
                timeline: 0.25...0.75,
                appliesOnInsertion: false,
                appliesOnRemoval: false
            ).events,
            0
        )
    }

    func testContentTransitionSequenceEffectSurface() {
        let directions: [(ContentTransition.SequenceDirection, Int32)] = [
            (.leading, 11),
            (.trailing, 12),
            (.up, 13),
            (.down, 14),
            (.forwards, 19),
            (.backwards, 20),
        ]

        for (direction, type) in directions {
            let effect = ContentTransition.Effect.sequence(
                direction: direction,
                delay: 0.25,
                maxAllowedDurationMultiple: 2,
                appliesOnInsertion: true,
                appliesOnRemoval: false
            )
            XCTAssertEqual(effect.type, ContentTransition.EffectType(type: type))
            XCTAssertEqual(effect.begin, 0.25)
            XCTAssertEqual(effect.duration, 0.5)
            XCTAssertEqual(effect.events, 3)
            XCTAssertEqual(effect.flags, 0)
        }

        let boolsIgnored = ContentTransition.Effect.sequence(
            direction: .leading,
            delay: 0.125,
            maxAllowedDurationMultiple: 4,
            appliesOnInsertion: false,
            appliesOnRemoval: false
        )
        XCTAssertEqual(boolsIgnored.type, ContentTransition.EffectType(type: 11))
        XCTAssertEqual(boolsIgnored.begin, 0.125)
        XCTAssertEqual(boolsIgnored.duration, 0.25)
        XCTAssertEqual(boolsIgnored.events, 3)
        XCTAssertEqual(boolsIgnored.flags, 0)
    }

    func testContentTransitionRBTransitionCarrierSurface() {
        for transition in [
            ContentTransition.identity,
            ContentTransition.opacity,
            ContentTransition.interpolate,
            ContentTransition.numericText(),
            ContentTransition.numericText(countsDown: true),
            ContentTransition.numericText(value: 12.5),
        ] {
            let rbTransition = transition.rbTransition
            XCTAssertEqual(rbTransition.method, ContentTransition.Method.diff.method)
            XCTAssertEqual(rbTransition.maxChanges, UInt32.max)
            XCTAssertFalse(rbTransition.isReplaceable)
            XCTAssertEqual(rbTransition.addRemoveDuration, 0.1254902, accuracy: 0.000001)
            XCTAssertNil(rbTransition.animation)
            XCTAssertEqual(rbTransition.effects.count, 1)
            XCTAssertEqual(rbTransition.effects[0].type, ContentTransition.EffectType.opacity.type)
            XCTAssertEqual(rbTransition.effects[0].beginTime, 0)
            XCTAssertEqual(rbTransition.effects[0].duration, 0)
            XCTAssertEqual(rbTransition.effects[0].events, 3)
            XCTAssertEqual(rbTransition.effects[0].flags, 0)
            XCTAssertEqual(rbTransition.effects[0].animationIndex, 0)
            XCTAssertEqual(rbTransition.effects[0].insertAnimationIndex, 0)
            XCTAssertEqual(rbTransition.effects[0].removeAnimationIndex, 0)
        }

        let effect = ContentTransition.Effect(
            type: ContentTransition.EffectType(type: 3, arg0: .float(0.5), arg1: .int(7)),
            begin: 0.25,
            duration: 0.75,
            events: 3,
            flags: 1
        )
        let custom = ContentTransition(method: .prefixAndSuffix, effects: [effect])
        let rbTransition = custom.rbTransition
        XCTAssertEqual(rbTransition.method, ContentTransition.Method.prefixAndSuffix.method)
        XCTAssertEqual(rbTransition.effects.count, 1)
        XCTAssertEqual(rbTransition.effects[0].type, 3)
        XCTAssertEqual(rbTransition.effects[0].argumentValue(atIndex: 0), 0.5)
        XCTAssertEqual(rbTransition.effects[0].integerArgumentValue(atIndex: 1), 7)
        XCTAssertEqual(rbTransition.effects[0].beginTime, Float(64) / 255, accuracy: 0.000001)
        XCTAssertEqual(rbTransition.effects[0].duration, Float(191) / 255, accuracy: 0.000001)
        XCTAssertEqual(rbTransition.effects[0].events, 3)
        XCTAssertEqual(rbTransition.effects[0].flags, 1)

        let copied = rbTransition.copy() as? RBTransition
        XCTAssertEqual(copied, rbTransition)
        XCTAssertFalse(copied === rbTransition)
        XCTAssertFalse(copied?.effects.first === rbTransition.effects.first)

        let animatedA = RBTransition()
        animatedA.animation = .linear(duration: 0.5)
        let animatedB = RBTransition()
        animatedB.animation = .linear(duration: 0.5)
        let animatedDifferentCurve = RBTransition()
        animatedDifferentCurve.animation = .easeInOut(duration: 0.5)
        let animatedDifferentDuration = RBTransition()
        animatedDifferentDuration.animation = .linear(duration: 1.0)
        let unanimated = RBTransition()

        XCTAssertEqual(animatedA, animatedB)
        XCTAssertEqual(animatedA.hash, animatedB.hash)
        XCTAssertNotEqual(animatedA, animatedDifferentCurve)
        XCTAssertNotEqual(animatedA, animatedDifferentDuration)
        XCTAssertNotEqual(animatedA, unanimated)

        let timingEffect = RBTransitionEffect()
        timingEffect.beginTime = 0.25
        timingEffect.duration = 0.75
        XCTAssertEqual(timingEffect.beginTime, Float(64) / 255, accuracy: 0.000001)
        XCTAssertEqual(timingEffect.duration, Float(191) / 255, accuracy: 0.000001)
        timingEffect.beginTime = -0.25
        timingEffect.duration = 1.25
        XCTAssertEqual(timingEffect.beginTime, 0)
        XCTAssertEqual(timingEffect.duration, 1)

        let animationModeEffect = RBTransitionEffect()
        animationModeEffect.beginTime = 0.25
        animationModeEffect.duration = 0.75
        animationModeEffect.insertAnimationIndex = 7
        XCTAssertEqual(animationModeEffect.insertAnimationIndex, 7)
        XCTAssertEqual(animationModeEffect.removeAnimationIndex, 0)
        XCTAssertEqual(animationModeEffect.animationIndex, 0)
        XCTAssertEqual(animationModeEffect.beginTime, 0)
        XCTAssertEqual(animationModeEffect.duration, 1)
        animationModeEffect.removeAnimationIndex = 9
        XCTAssertEqual(animationModeEffect.insertAnimationIndex, 7)
        XCTAssertEqual(animationModeEffect.removeAnimationIndex, 9)
        XCTAssertEqual(animationModeEffect.animationIndex, 0)
        animationModeEffect.beginTime = 0.5
        XCTAssertEqual(animationModeEffect.beginTime, Float(128) / 255, accuracy: 0.000001)
        XCTAssertEqual(animationModeEffect.duration, 1)
        XCTAssertEqual(animationModeEffect.insertAnimationIndex, 0)
        XCTAssertEqual(animationModeEffect.removeAnimationIndex, 0)
        animationModeEffect.duration = 0.25
        XCTAssertEqual(animationModeEffect.beginTime, Float(128) / 255, accuracy: 0.000001)
        XCTAssertEqual(animationModeEffect.duration, Float(64) / 255, accuracy: 0.000001)
        XCTAssertEqual(animationModeEffect.insertAnimationIndex, 0)
        XCTAssertEqual(animationModeEffect.removeAnimationIndex, 0)

        let singleAnimationEffect = RBTransitionEffect()
        singleAnimationEffect.animationIndex = 5
        XCTAssertEqual(singleAnimationEffect.animationIndex, 5)
        XCTAssertEqual(singleAnimationEffect.insertAnimationIndex, 5)
        XCTAssertEqual(singleAnimationEffect.removeAnimationIndex, 5)
        XCTAssertEqual(singleAnimationEffect.beginTime, 0)
        XCTAssertEqual(singleAnimationEffect.duration, 1)
        singleAnimationEffect.animationIndex = 300
        XCTAssertEqual(singleAnimationEffect.animationIndex, 44)
        XCTAssertEqual(singleAnimationEffect.insertAnimationIndex, 44)
        XCTAssertEqual(singleAnimationEffect.removeAnimationIndex, 44)

        let timingEquivalentEffect = RBTransitionEffect()
        timingEquivalentEffect.beginTime = 0
        timingEquivalentEffect.duration = 1
        let fullLaneAnimationEffect = RBTransitionEffect()
        fullLaneAnimationEffect.animationIndex = 255
        XCTAssertNotEqual(timingEquivalentEffect, fullLaneAnimationEffect)

        for nonGeometryType in [Int32(0), 1, 11, 14, 19] {
            let effect = RBTransitionEffect()
            effect.type = nonGeometryType
            XCTAssertFalse(effect.changesGeometry, "type \(nonGeometryType)")
        }
        let highBitOpacity = RBTransitionEffect()
        highBitOpacity.type = 0x100 | ContentTransition.EffectType.opacity.type
        XCTAssertFalse(highBitOpacity.changesGeometry)

        for geometryType in [Int32(2), 3, 4, 10, 15, 16, 17] {
            let effect = RBTransitionEffect()
            effect.type = geometryType
            XCTAssertTrue(effect.changesGeometry, "type \(geometryType)")
        }
        let highBitScale = RBTransitionEffect()
        highBitScale.type = 0x100 | ContentTransition.EffectType.scale(1).type
        XCTAssertTrue(highBitScale.changesGeometry)

        let timingTransition = RBTransition()
        timingTransition.addRemoveDuration = 0.25
        XCTAssertEqual(timingTransition.addRemoveDuration, Float(64) / 255, accuracy: 0.000001)
        timingTransition.addRemoveDuration = -0.25
        XCTAssertEqual(timingTransition.addRemoveDuration, 0)
        timingTransition.addRemoveDuration = 1.25
        XCTAssertEqual(timingTransition.addRemoveDuration, 1)

        let argumentEffect = RBTransitionEffect()
        argumentEffect.setArgumentValue(Float(bitPattern: 0x3f000000), atIndex: 0)
        XCTAssertEqual(argumentEffect.integerArgumentValue(atIndex: 0), 0x3f000000)
        argumentEffect.setIntegerArgumentValue(0x3f800000, atIndex: 1)
        XCTAssertEqual(argumentEffect.argumentValue(atIndex: 1), Float(bitPattern: 0x3f800000))
        argumentEffect.setArgumentValue(12, atIndex: 2)
        XCTAssertEqual(argumentEffect.argumentValue(atIndex: 2), 0)
        XCTAssertEqual(argumentEffect.integerArgumentValue(atIndex: 2), 0)

        let floatRaw = RBTransitionEffect()
        floatRaw.type = 2
        floatRaw.setArgumentValue(Float(bitPattern: 0x3f000000), atIndex: 0)
        let integerRaw = RBTransitionEffect()
        integerRaw.type = 2
        integerRaw.setIntegerArgumentValue(0x3f000000, atIndex: 0)
        XCTAssertEqual(floatRaw, integerRaw)
        XCTAssertEqual(floatRaw.hash, integerRaw.hash)

        let opacityIgnoredArguments = RBTransitionEffect()
        opacityIgnoredArguments.type = ContentTransition.EffectType.opacity.type
        opacityIgnoredArguments.setArgumentValue(0.25, atIndex: 0)
        opacityIgnoredArguments.setArgumentValue(0.75, atIndex: 1)
        let opacityIgnoredArgumentsPeer = RBTransitionEffect()
        opacityIgnoredArgumentsPeer.type = ContentTransition.EffectType.opacity.type
        opacityIgnoredArgumentsPeer.setArgumentValue(0.5, atIndex: 0)
        opacityIgnoredArgumentsPeer.setArgumentValue(1, atIndex: 1)
        XCTAssertEqual(opacityIgnoredArguments, opacityIgnoredArgumentsPeer)
        XCTAssertEqual(opacityIgnoredArguments.hash, opacityIgnoredArgumentsPeer.hash)

        let ignoredExtra = RBTransitionEffect()
        ignoredExtra.type = 3
        ignoredExtra.setArgumentValue(1, atIndex: 0)
        ignoredExtra.setArgumentValue(2, atIndex: 1)
        ignoredExtra.setArgumentValue(3, atIndex: 2)
        let ignoredExtraPeer = RBTransitionEffect()
        ignoredExtraPeer.type = 3
        ignoredExtraPeer.setArgumentValue(1, atIndex: 0)
        ignoredExtraPeer.setArgumentValue(2, atIndex: 1)
        ignoredExtraPeer.setArgumentValue(4, atIndex: 2)
        XCTAssertEqual(ignoredExtra, ignoredExtraPeer)

        let secondSlot = RBTransitionEffect()
        secondSlot.type = 2
        secondSlot.setArgumentValue(0.5, atIndex: 0)
        secondSlot.setArgumentValue(0.25, atIndex: 1)
        let secondSlotPeer = RBTransitionEffect()
        secondSlotPeer.type = 2
        secondSlotPeer.setArgumentValue(0.5, atIndex: 0)
        secondSlotPeer.setArgumentValue(0.75, atIndex: 1)
        XCTAssertEqual(secondSlot, secondSlotPeer)
        XCTAssertEqual(secondSlot.hash, secondSlotPeer.hash)

        let firstSlotPeer = RBTransitionEffect()
        firstSlotPeer.type = 2
        firstSlotPeer.setArgumentValue(0.75, atIndex: 0)
        firstSlotPeer.setArgumentValue(0.25, atIndex: 1)
        XCTAssertNotEqual(secondSlot, firstSlotPeer)

        let twoSlot = RBTransitionEffect()
        twoSlot.type = 3
        twoSlot.setArgumentValue(0.5, atIndex: 0)
        twoSlot.setArgumentValue(0.25, atIndex: 1)
        let twoSlotPeer = RBTransitionEffect()
        twoSlotPeer.type = 3
        twoSlotPeer.setArgumentValue(0.5, atIndex: 0)
        twoSlotPeer.setArgumentValue(0.75, atIndex: 1)
        XCTAssertNotEqual(twoSlot, twoSlotPeer)

        let highBitSecondSlot = RBTransitionEffect()
        highBitSecondSlot.type = 0x100 | ContentTransition.EffectType.scale(1).type
        highBitSecondSlot.setArgumentValue(0.5, atIndex: 0)
        highBitSecondSlot.setArgumentValue(0.25, atIndex: 1)
        let highBitSecondSlotPeer = RBTransitionEffect()
        highBitSecondSlotPeer.type = 0x100 | ContentTransition.EffectType.scale(1).type
        highBitSecondSlotPeer.setArgumentValue(0.5, atIndex: 0)
        highBitSecondSlotPeer.setArgumentValue(0.75, atIndex: 1)
        XCTAssertEqual(highBitSecondSlot, highBitSecondSlotPeer)
        XCTAssertEqual(highBitSecondSlot.hash, highBitSecondSlotPeer.hash)

        let differentRawType = RBTransitionEffect()
        differentRawType.type = ContentTransition.EffectType.scale(1).type
        differentRawType.setArgumentValue(0.5, atIndex: 0)
        differentRawType.setArgumentValue(0.25, atIndex: 1)
        XCTAssertNotEqual(highBitSecondSlot, differentRawType)
    }

    func testRBTransitionEffectDirectionAndCustomDurationHelpers() throws {
        let sequenceDuration = RBTransitionEffect()
        sequenceDuration.type = 0x100 | 17
        sequenceDuration.setArgumentValue(2, atIndex: 1)
        XCTAssertEqual(
            try XCTUnwrap(sequenceDuration.customDuration(for: 1)),
            0.125,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            try XCTUnwrap(sequenceDuration.customDuration(for: 2)),
            Float(1.0 / 12.0),
            accuracy: 0.000001
        )

        let scaleDuration = RBTransitionEffect()
        scaleDuration.type = 18
        scaleDuration.setIntegerArgumentValue(4, atIndex: 0)
        scaleDuration.setArgumentValue(2, atIndex: 1)
        XCTAssertEqual(
            try XCTUnwrap(scaleDuration.customDuration(for: 1)),
            0.125,
            accuracy: 0.000001
        )
        scaleDuration.setIntegerArgumentValue(3, atIndex: 0)
        XCTAssertEqual(
            try XCTUnwrap(scaleDuration.customDuration(for: 1)),
            0.25,
            accuracy: 0.000001
        )

        let nonDuration = RBTransitionEffect()
        nonDuration.type = 16
        XCTAssertNil(nonDuration.customDuration(for: 1))

        let anchor = RBTransitionEffect()
        anchor.type = 0x100 | 7
        XCTAssertEqual(anchor.anchorDirection(event: 1, isFlipped: false), 0)
        anchor.type = 0x100 | 10
        XCTAssertEqual(anchor.anchorDirection(event: 1, isFlipped: false), 3)
        anchor.type = 0x100 | 11
        XCTAssertNil(anchor.anchorDirection(event: 1, isFlipped: false))

        let flippedAnchor = RBTransitionEffect()
        flippedAnchor.type = 7
        flippedAnchor.flags = 2
        XCTAssertEqual(flippedAnchor.anchorDirection(event: 1, isFlipped: true), 1)
        flippedAnchor.flags = 1
        XCTAssertEqual(flippedAnchor.anchorDirection(event: 2, isFlipped: false), 1)
        flippedAnchor.flags = 3
        XCTAssertEqual(flippedAnchor.anchorDirection(event: 2, isFlipped: true), 0)

        let sequence = RBTransitionEffect()
        sequence.type = 0x100 | 11
        XCTAssertEqual(sequence.sequenceDirection(event: 1, isFlipped: false), 0)
        sequence.type = 0x100 | 14
        XCTAssertEqual(sequence.sequenceDirection(event: 1, isFlipped: false), 3)
        sequence.type = 0x100 | 15
        XCTAssertNil(sequence.sequenceDirection(event: 1, isFlipped: false))
        sequence.type = 0x100 | 19
        XCTAssertEqual(sequence.sequenceDirection(event: 1, isFlipped: false), 4)
        sequence.type = 0x100 | 20
        XCTAssertEqual(sequence.sequenceDirection(event: 1, isFlipped: false), 5)

        let flippedSequence = RBTransitionEffect()
        flippedSequence.type = 19
        flippedSequence.flags = 2
        XCTAssertEqual(flippedSequence.sequenceDirection(event: 1, isFlipped: true), 5)
        flippedSequence.flags = 1
        XCTAssertEqual(flippedSequence.sequenceDirection(event: 2, isFlipped: false), 5)
    }

    func testRBTransitionEffectTimeDecodingSurface() throws {
        let transition = RBTransition()

        let timingEffect = RBTransitionEffect()
        timingEffect.beginTime = 0.25
        timingEffect.duration = 0.5
        let activeMidpoint = timingEffect.beginTime + timingEffect.duration / 2

        XCTAssertEqual(
            try XCTUnwrap(timingEffect.effectTime(at: activeMidpoint, event: 1, transition: transition)),
            Float(0.5),
            accuracy: 0.000001
        )
        XCTAssertEqual(
            try XCTUnwrap(timingEffect.effectTime(at: 1 - activeMidpoint, event: 2, transition: transition)),
            Float(0.5),
            accuracy: 0.000001
        )
        XCTAssertEqual(
            try XCTUnwrap(timingEffect.effectTime(at: 0, event: 1, transition: transition)),
            Float(0),
            accuracy: 0.000001
        )
        XCTAssertEqual(
            try XCTUnwrap(timingEffect.effectTime(at: 1, event: 1, transition: transition)),
            Float(1),
            accuracy: 0.000001
        )

        let zeroDurationEffect = RBTransitionEffect()
        zeroDurationEffect.duration = 0
        transition.addRemoveDuration = 0.25
        let fallbackMidpoint = 1 - transition.addRemoveDuration / 2

        XCTAssertEqual(
            try XCTUnwrap(zeroDurationEffect.effectTime(
                at: 0.5,
                event: 1,
                transition: transition
            )),
            Float(0.5),
            accuracy: 0.000001
        )
        XCTAssertEqual(
            try XCTUnwrap(zeroDurationEffect.effectTime(
                at: fallbackMidpoint,
                event: 1,
                transition: transition,
                usesAddRemoveDurationFallback: true
            )),
            Float(0.5),
            accuracy: 0.000001
        )
        XCTAssertEqual(
            try XCTUnwrap(zeroDurationEffect.effectTime(
                at: transition.addRemoveDuration / 2,
                event: 2,
                transition: transition,
                usesAddRemoveDurationFallback: true
            )),
            Float(0.5),
            accuracy: 0.000001
        )

        let animationIndexEffect = RBTransitionEffect()
        animationIndexEffect.insertAnimationIndex = 0
        XCTAssertEqual(
            try XCTUnwrap(animationIndexEffect.effectTime(at: 0.35, event: 1, transition: transition)),
            Float(0.35),
            accuracy: 0.000001
        )
        XCTAssertEqual(
            try XCTUnwrap(animationIndexEffect.effectTime(at: 0.35, event: 2, transition: transition)),
            Float(0.65),
            accuracy: 0.000001
        )

        animationIndexEffect.insertAnimationIndex = 7
        XCTAssertNil(animationIndexEffect.effectTime(at: 0.35, event: 1, transition: transition))
        XCTAssertEqual(
            try XCTUnwrap(animationIndexEffect.effectTime(at: 0.35, event: 2, transition: transition)),
            Float(0.65),
            accuracy: 0.000001
        )

        animationIndexEffect.removeAnimationIndex = 9
        XCTAssertNil(animationIndexEffect.effectTime(at: 0.35, event: 2, transition: transition))
    }

    func testRBTransitionEmptyEventMatchingSurface() {
        let transition = RBTransition()
        XCTAssertTrue(transition.isEmpty(for: 0))
        XCTAssertTrue(transition.isEmpty(for: 1))

        let insertEffect = RBTransitionEffect()
        insertEffect.events = 1
        transition.addEffect(insertEffect)

        XCTAssertTrue(transition.isEmpty(for: 0))
        XCTAssertFalse(transition.isEmpty(for: 1))
        XCTAssertTrue(transition.isEmpty(for: 2))
        XCTAssertFalse(transition.isEmpty(for: 3))
        XCTAssertFalse(transition.isEmpty(for: 0x41))
        XCTAssertTrue(transition.isEmpty(for: 0x40))

        let removeEffect = RBTransitionEffect()
        removeEffect.events = 2
        transition.addEffect(removeEffect)

        XCTAssertFalse(transition.isEmpty(for: 2))
    }

    func testRBTransitionEffectResultSemantics() throws {
        let bounds = CGRect(x: 10, y: 20, width: 40, height: 10)

        let opacity = RBTransitionEffect()
        opacity.type = 0x100 | ContentTransition.EffectType.opacity.type
        opacity.duration = 1
        opacity.events = 3

        let opacityInsert = try XCTUnwrap(
            transitionEffectResults([opacity], progress: 0.25, event: 1, bounds: bounds)
        )
        XCTAssertEqual(opacityInsert.alpha, 0.25, accuracy: 0.000001)
        XCTAssertEqual(opacityInsert.bounds, bounds)

        let opacityRemove = try XCTUnwrap(
            transitionEffectResults([opacity], progress: 0.25, event: 2, bounds: bounds)
        )
        XCTAssertEqual(opacityRemove.alpha, 0.75, accuracy: 0.000001)

        let scale = RBTransitionEffect()
        scale.type = ContentTransition.EffectType.scale(0.5).type
        scale.setArgumentValue(0.5, atIndex: 0)
        scale.duration = 1
        scale.events = 3

        let scaleResults = try XCTUnwrap(
            transitionEffectResults([scale], progress: 0.5, event: 1, bounds: bounds)
        )
        XCTAssertEqual(scaleResults.transform.a, 0.75, accuracy: 0.000001)
        XCTAssertEqual(scaleResults.transform.d, 0.75, accuracy: 0.000001)
        XCTAssertEqual(scaleResults.transform.tx, 12.5, accuracy: 0.000001)
        XCTAssertEqual(scaleResults.transform.ty, 7.5, accuracy: 0.000001)
        XCTAssertEqual(
            try XCTUnwrap(scaleResults.bounds),
            CGRect(x: 20, y: 22.5, width: 30, height: 7.5)
        )

        scale.flags = 1
        let invertedScaleRemoval = try XCTUnwrap(
            transitionEffectResults([scale], progress: 0.25, event: 2, bounds: bounds)
        )
        XCTAssertEqual(invertedScaleRemoval.transform.a, 1.25, accuracy: 0.000001)
        XCTAssertEqual(invertedScaleRemoval.transform.d, 1.25, accuracy: 0.000001)
        XCTAssertEqual(invertedScaleRemoval.transform.tx, -12.5, accuracy: 0.000001)
        XCTAssertEqual(invertedScaleRemoval.transform.ty, -7.5, accuracy: 0.000001)
        XCTAssertEqual(
            try XCTUnwrap(invertedScaleRemoval.bounds),
            CGRect(x: 0, y: 17.5, width: 50, height: 12.5)
        )
        scale.flags = 0

        let translation = RBTransitionEffect()
        translation.type = ContentTransition.EffectType.translation(.zero).type
        translation.setArgumentValue(10, atIndex: 0)
        translation.setArgumentValue(-4, atIndex: 1)
        translation.duration = 1
        translation.events = 3

        let translationInsert = try XCTUnwrap(
            transitionEffectResults([translation], progress: 0.25, event: 1, bounds: bounds)
        )
        XCTAssertEqual(translationInsert.transform.tx, 7.5, accuracy: 0.000001)
        XCTAssertEqual(translationInsert.transform.ty, -3, accuracy: 0.000001)
        XCTAssertEqual(
            try XCTUnwrap(translationInsert.bounds),
            CGRect(x: 17.5, y: 17, width: 40, height: 10)
        )

        translation.flags = 1
        let invertedRemoval = try XCTUnwrap(
            transitionEffectResults([translation], progress: 0.25, event: 2, bounds: bounds)
        )
        XCTAssertEqual(invertedRemoval.transform.tx, -2.5, accuracy: 0.000001)
        XCTAssertEqual(invertedRemoval.transform.ty, 1, accuracy: 0.000001)

        let relativeTranslation = RBTransitionEffect()
        relativeTranslation.type = ContentTransition.EffectType.translation(scale: .zero).type
        relativeTranslation.setArgumentValue(0.5, atIndex: 0)
        relativeTranslation.setArgumentValue(0.25, atIndex: 1)
        relativeTranslation.duration = 1
        relativeTranslation.events = 3

        let relativeTranslationResults = try XCTUnwrap(
            transitionEffectResults([relativeTranslation], progress: 0.25, event: 1, bounds: bounds)
        )
        XCTAssertEqual(relativeTranslationResults.transform.tx, 15, accuracy: 0.000001)
        XCTAssertEqual(relativeTranslationResults.transform.ty, 1.875, accuracy: 0.000001)

        let blur = RBTransitionEffect()
        blur.type = ContentTransition.EffectType.blur(radius: 12).type
        blur.setArgumentValue(12, atIndex: 0)
        blur.duration = 1
        blur.events = 3

        let relativeBlur = RBTransitionEffect()
        relativeBlur.type = ContentTransition.EffectType.relativeBlur(scale: .zero).type
        relativeBlur.setArgumentValue(0.5, atIndex: 0)
        relativeBlur.setArgumentValue(0.25, atIndex: 1)
        relativeBlur.duration = 1
        relativeBlur.events = 3

        let blurResults = try XCTUnwrap(
            transitionEffectResults([blur, relativeBlur], progress: 0.25, event: 1, bounds: bounds)
        )
        XCTAssertTrue(blurResults.hasBlur)
        XCTAssertEqual(blurResults.blurRadius, 19.125, accuracy: 0.000001)
        let blurBounds = try XCTUnwrap(blurResults.bounds)
        XCTAssertEqual(blurBounds.minX, -43.55, accuracy: 0.000001)
        XCTAssertEqual(blurBounds.minY, -33.55, accuracy: 0.000001)
        XCTAssertEqual(blurBounds.width, 147.1, accuracy: 0.000001)
        XCTAssertEqual(blurBounds.height, 117.1, accuracy: 0.000001)

        let alphaBlurResults = try XCTUnwrap(
            transitionEffectResults([opacity, blur], progress: 0.25, event: 1, bounds: bounds)
        )
        XCTAssertEqual(alphaBlurResults.alpha, 0.25, accuracy: 0.000001)
        XCTAssertEqual(alphaBlurResults.blurRadius, 9, accuracy: 0.000001)
        let alphaBlurBounds = try XCTUnwrap(alphaBlurResults.bounds)
        XCTAssertEqual(alphaBlurBounds.minX, -2.6, accuracy: 0.000001)
        XCTAssertEqual(alphaBlurBounds.minY, 7.4, accuracy: 0.000001)
        XCTAssertEqual(alphaBlurBounds.width, 65.2, accuracy: 0.000001)
        XCTAssertEqual(alphaBlurBounds.height, 35.2, accuracy: 0.000001)

        let blurThenScaleResults = try XCTUnwrap(
            transitionEffectResults([blur, scale], progress: 0.5, event: 1, bounds: bounds)
        )
        XCTAssertEqual(blurThenScaleResults.blurRadius, 4.5, accuracy: 0.000001)
        let blurThenScaleBounds = try XCTUnwrap(blurThenScaleResults.bounds)
        XCTAssertEqual(blurThenScaleBounds.minX, 7.4, accuracy: 0.000001)
        XCTAssertEqual(blurThenScaleBounds.minY, 9.9, accuracy: 0.000001)
        XCTAssertEqual(blurThenScaleBounds.width, 55.2, accuracy: 0.000001)
        XCTAssertEqual(blurThenScaleBounds.height, 32.7, accuracy: 0.000001)

        let skippedEvent = RBTransitionEffect()
        skippedEvent.type = ContentTransition.EffectType.opacity.type
        skippedEvent.duration = 1
        skippedEvent.events = 1
        let skippedResults = try XCTUnwrap(
            transitionEffectResults([skippedEvent], progress: 0.25, event: 2, bounds: bounds)
        )
        XCTAssertEqual(skippedResults.alpha, 1, accuracy: 0.000001)

        let zeroEventResults = try XCTUnwrap(
            transitionEffectResults([opacity], progress: 0.25, event: 0, bounds: bounds)
        )
        XCTAssertEqual(zeroEventResults.alpha, 1, accuracy: 0.000001)

        let insertOnlyResults = try XCTUnwrap(
            transitionEffectResults([skippedEvent], progress: 0.25, event: 3, bounds: bounds)
        )
        XCTAssertEqual(insertOnlyResults.alpha, 0.25, accuracy: 0.000001)

        let animationIndexEffect = RBTransitionEffect()
        animationIndexEffect.type = ContentTransition.EffectType.opacity.type
        animationIndexEffect.events = 3
        animationIndexEffect.insertAnimationIndex = 7
        XCTAssertNil(
            transitionEffectResults([animationIndexEffect], progress: 0.25, event: 1, bounds: bounds)
        )
        XCTAssertNotNil(
            transitionEffectResults([animationIndexEffect], progress: 0.25, event: 2, bounds: bounds)
        )

        animationIndexEffect.events = 1
        let skippedAnimationIndexResults = try XCTUnwrap(
            transitionEffectResults([animationIndexEffect], progress: 0.25, event: 2, bounds: bounds)
        )
        XCTAssertEqual(skippedAnimationIndexResults.alpha, 1, accuracy: 0.000001)
    }

    func testTransitionContentTransitionOperationDispatch() {
        let defaultTransition = PlainContentTransition()
        XCTAssertFalse(defaultTransition.hasContentTransition)
        XCTAssertTrue(
            defaultTransition.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 10, height: 20)
            ).isEmpty
        )

        XCTAssertTrue(IdentityTransition().hasContentTransition)
        XCTAssertEqual(
            IdentityTransition().contentTransitionEffects(
                style: .default,
                size: CGSize(width: 10, height: 20)
            ),
            []
        )

        let effect = ContentTransition.Effect(
            type: ContentTransition.EffectType(type: 2),
            begin: 0,
            duration: 1,
            events: 0,
            flags: 0
        )
        let transition = ProbeContentTransition(effect: effect)

        XCTAssertTrue(transition.hasContentTransition)
        XCTAssertEqual(
            transition.contentTransitionEffects(
                style: .animatedWidget,
                size: CGSize(width: 10, height: 20)
            ),
            [effect]
        )
    }

    func testConcreteTransitionContentTransitionEffects() {
        let opacity = OpacityTransition()
        XCTAssertTrue(opacity.hasContentTransition)
        XCTAssertEqual(
            opacity.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 20, height: 10)
            ),
            [
                ContentTransition.Effect(
                    type: .opacity,
                    events: 3
                )
            ]
        )

        let move = MoveTransition(edge: .leading)
        XCTAssertTrue(move.hasContentTransition)
        XCTAssertEqual(
            move.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 20, height: 10)
            ),
            [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: -20, height: 0))
                )
            ]
        )

        let scale = ScaleTransition(0.4)
        XCTAssertTrue(scale.hasContentTransition)
        XCTAssertEqual(
            scale.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 20, height: 10)
            ),
            [ContentTransition.Effect(type: .scale(0.4))]
        )

        let offset = OffsetTransition(CGSize(width: 3, height: -4))
        XCTAssertTrue(offset.hasContentTransition)
        XCTAssertEqual(
            offset.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 20, height: 10)
            ),
            [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: 3, height: -4))
                )
            ]
        )

        let push = PushTransition(edge: .trailing)
        XCTAssertTrue(push.hasContentTransition)
        XCTAssertEqual(
            push.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 40, height: 20)
            ),
            [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: 40, height: 0)),
                    events: 1
                ),
                ContentTransition.Effect(
                    type: .translation(CGSize(width: -40, height: 0)),
                    events: 2
                ),
                ContentTransition.Effect(
                    type: .opacity,
                    events: 3
                ),
            ]
        )
        XCTAssertEqual(
            push.contentTransitionEffects(
                style: .animatedWidget,
                size: CGSize(width: 40, height: 20)
            ),
            [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: 16, height: 0)),
                    events: 1
                ),
                ContentTransition.Effect(
                    type: .translation(CGSize(width: -40, height: 0)),
                    events: 2
                ),
                ContentTransition.Effect(
                    type: .opacity,
                    begin: 0.4,
                    duration: 0.6,
                    events: 3
                ),
            ]
        )

        let blurReplace = BlurReplaceTransition(configuration: .downUp)
        let blurBegin = Float(bitPattern: 0x3EA8F5C3)
        let blurDuration = Float(bitPattern: 0x3F2B851E)
        let blurScale = CGFloat(Float(bitPattern: 0x3F666666))
        XCTAssertTrue(blurReplace.hasContentTransition)
        XCTAssertEqual(
            blurReplace.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 40, height: 20)
            ),
            [
                ContentTransition.Effect(
                    type: .opacity,
                    begin: blurBegin,
                    duration: blurDuration,
                    events: 3
                ),
                ContentTransition.Effect(
                    type: .blur(radius: 7),
                    begin: blurBegin,
                    duration: blurDuration,
                    events: 3
                ),
                ContentTransition.Effect(
                    type: .scale(blurScale),
                    begin: blurBegin,
                    duration: blurDuration,
                    events: 3
                ),
            ]
        )
        XCTAssertEqual(
            BlurReplaceTransition(configuration: .upUp).contentTransitionEffects(
                style: .default,
                size: CGSize(width: 40, height: 20)
            ).last?.flags,
            1
        )
    }

    func testTypedOffsetTransitionPublicSurfaceMatchesObservedAPI() {
        // ASSERTIONS transitionOffsetPublicSurfaceObserved
        let direct = OffsetTransition(CGSize(width: 3, height: -4))
        XCTAssertEqual(direct.offset, CGSize(width: 3, height: -4))

        let sized: OffsetTransition = .offset(CGSize(width: 5, height: 7))
        XCTAssertEqual(sized.offset, CGSize(width: 5, height: 7))

        let components: OffsetTransition = .offset(x: -2, y: 9)
        XCTAssertEqual(components.offset, CGSize(width: -2, height: 9))
    }

    func testBlurReplaceTransitionBodyShape() throws {
        let identityBody = BlurReplaceTransition(configuration: .downUp).body(
            content: PlaceholderContentView<BlurReplaceTransition>(),
            phase: .identity
        )
        let identity = try XCTUnwrap(identityBody as? BlurReplaceBody)
        XCTAssertEqual(identity.content.content.modifier.opacity, 1)
        XCTAssertEqual(identity.content.modifier, _BlurEffect(radius: 0, opaque: false))
        XCTAssertEqual(identity.modifier.scale, CGSize(width: 1, height: 1))
        XCTAssertEqual(identity.modifier.anchor, .center)

        let downRemovalBody = BlurReplaceTransition(configuration: .downUp).body(
            content: PlaceholderContentView<BlurReplaceTransition>(),
            phase: .didDisappear
        )
        let downRemoval = try XCTUnwrap(downRemovalBody as? BlurReplaceBody)
        XCTAssertEqual(downRemoval.content.content.modifier.opacity, 0)
        XCTAssertEqual(downRemoval.content.modifier, _BlurEffect(radius: 7, opaque: false))
        XCTAssertEqual(downRemoval.modifier.scale, CGSize(width: 0.9, height: 0.9))
        XCTAssertEqual(downRemoval.modifier.anchor, .center)

        let upRemovalBody = BlurReplaceTransition(configuration: .upUp).body(
            content: PlaceholderContentView<BlurReplaceTransition>(),
            phase: .didDisappear
        )
        let upRemoval = try XCTUnwrap(upRemovalBody as? BlurReplaceBody)
        XCTAssertEqual(upRemoval.content.content.modifier.opacity, 0)
        XCTAssertEqual(upRemoval.content.modifier, _BlurEffect(radius: 7, opaque: false))
        XCTAssertEqual(upRemoval.modifier.scale, CGSize(width: 1.1, height: 1.1))
        XCTAssertEqual(upRemoval.modifier.anchor, .center)
    }

    func testComposedTransitionContentTransitionQueriesForwardToChildren() {
        let asymmetric = AsymmetricTransition(
            insertion: MoveTransition(edge: .top),
            removal: ScaleTransition(0.5)
        )
        XCTAssertTrue(asymmetric.hasContentTransition)
        XCTAssertEqual(
            asymmetric.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 20, height: 10)
            ),
            [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: 0, height: -10))
                ),
                ContentTransition.Effect(type: .scale(0.5)),
            ]
        )

        let filtered = FilteredTransition(
            transition: MoveTransition(edge: .bottom),
            filter: { _, _ in }
        )
        XCTAssertTrue(filtered.hasContentTransition)
        XCTAssertEqual(
            filtered.contentTransitionEffects(
                style: .default,
                size: CGSize(width: 20, height: 10)
            ),
            [
                ContentTransition.Effect(
                    type: .translation(CGSize(width: 0, height: 10))
                )
            ]
        )
    }

    func testRetainedRemovalTransactionResolverPreservesFilterOwnership() {
        let plain = Transaction()
        let outer = Transaction(animation: .linear(duration: 0.25))

        XCTAssertEqual(
            retainedRemovalDurations(AnyTransition.opacity, from: outer),
            [0.25]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.opacity.animation(.linear(duration: 0.8)),
                from: plain
            ),
            [0.8]
        )
        XCTAssertEqual(
            retainedRemovalDurations(AnyTransition.opacity.animation(nil), from: outer),
            [nil]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.opacity
                    .animation(.linear(duration: 0.8))
                    .animation(nil),
                from: outer
            ),
            [0.8]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.opacity
                    .animation(nil)
                    .animation(.linear(duration: 0.8)),
                from: outer
            ),
            [nil]
        )

        let combined = AnyTransition.opacity
            .animation(nil)
            .combined(with: .scale.animation(.linear(duration: 0.7)))
        XCTAssertEqual(
            retainedRemovalDurations(combined, from: outer),
            [nil, 0.7]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.opacity
                    .animation(.linear(duration: 0.8))
                    .combined(with: .offset(x: -80, y: 0).animation(.linear(duration: 0.8))),
                from: plain
            ),
            [0.8]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.opacity
                    .animation(nil)
                    .combined(with: .offset(x: -80, y: 0).animation(.linear(duration: 0.8))),
                from: plain
            ),
            [nil]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.offset(x: -80, y: 0)
                    .animation(.linear(duration: 0.8))
                    .combined(with: .opacity.animation(nil)),
                from: plain
            ),
            [nil]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.opacity
                    .animation(nil)
                    .combined(with: .opacity.animation(.linear(duration: 0.8))),
                from: plain
            ),
            [nil, 0.8]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                AnyTransition.opacity
                    .animation(.linear(duration: 0.8))
                    .combined(with: .opacity.animation(nil)),
                from: plain
            ),
            [0.8, nil]
        )
    }

    func testRetainedRemovalTransactionResolverKeepsOffsetOnlyFilteredAnimationException() {
        let plain = Transaction()

        XCTAssertTrue(
            AnyTransition.offset(x: 12, y: -4)
                .animation(.linear(duration: 0.8))
                ._retainedRemovalTransactions(from: plain, phase: .didDisappear)
                .isEmpty
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                .scale(scale: 0.5).animation(.linear(duration: 0.8)),
                from: plain
            ),
            [0.8]
        )
        XCTAssertEqual(
            retainedRemovalDurations(
                .offset(x: 12, y: -4),
                from: Transaction(animation: .linear(duration: 0.3))
            ),
            [0.3]
        )
    }

    func testRetainedRemovalTransactionResolverUsesAsymmetricRemovalChildOnly() {
        let plain = Transaction()

        let insertingScaleRemovingNilOpacity = AnyTransition.asymmetric(
            insertion: .scale.animation(.linear(duration: 0.8)),
            removal: .opacity.animation(nil)
        )
        XCTAssertEqual(
            retainedRemovalDurations(insertingScaleRemovingNilOpacity, from: plain),
            [nil]
        )

        let insertingOffsetRemovingScale = AnyTransition.asymmetric(
            insertion: .offset(x: 12, y: -4).animation(.linear(duration: 0.8)),
            removal: .scale(scale: 0.5).animation(.linear(duration: 0.6))
        )
        XCTAssertEqual(
            retainedRemovalDurations(insertingOffsetRemovingScale, from: plain),
            [0.6]
        )

        let insertingScaleRemovingOffset = AnyTransition.asymmetric(
            insertion: .scale.animation(.linear(duration: 0.8)),
            removal: .offset(x: 12, y: -4).animation(.linear(duration: 0.6))
        )
        XCTAssertTrue(
            insertingScaleRemovingOffset
                ._retainedRemovalTransactions(from: plain, phase: .didDisappear)
                .isEmpty
        )
    }

    private func transitionEffectResults(
        _ effects: [RBTransitionEffect],
        progress: Float,
        event: UInt32,
        bounds: CGRect
    ) -> RBTransitionEffectResults? {
        let transition = RBTransition()
        for effect in effects {
            transition.addEffect(effect)
        }
        return transition.effectResults(at: progress, event: event, bounds: bounds)
    }

    private func retainedRemovalDurations(
        _ transition: AnyTransition,
        from transaction: Transaction
    ) -> [TimeInterval?] {
        transition
            ._retainedRemovalTransactions(from: transaction, phase: .didDisappear)
            .map { $0.effectiveAnimation?.box.duration }
    }

    private func makeDisplayList(debugItemCount: Int) -> DisplayList {
        var list = DisplayList()
        for _ in 0..<debugItemCount {
            list.appendDebugItem { _ in }
        }
        return list
    }

    private func makeViewInputs(
        graph: _AGGraph,
        position: Attribute<CGPoint>? = nil
    ) -> _ViewInputs {
        let environment = graph.makeInput(value: EnvironmentValues())
        let position = position ?? graph.makeInput(value: CGPoint.zero)
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
            position: position,
            containerPosition: graph.makeInput(value: CGPoint.zero),
            size: graph.makeInput(value: ViewSize(width: 10, height: 10)),
            safeAreaInsets: OptionalAttribute(),
            containerSize: OptionalAttribute(),
            stackOrientation: nil
        )
    }
}
