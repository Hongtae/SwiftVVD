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

        let graph = AttributeGraph()
        try AttributeGraph.$current.withValue(graph) {
            let modifier = graph.makeInput(value: effect)
            var source = makeDisplayList(debugItemCount: 1)
            source.effects.append(
                DisplayList.EffectItem(
                    effect: .contentTransition(ContentTransition.State(transition: .identity)),
                    contents: DisplayList()
                )
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
        XCTAssertEqual(rbTransition.effects[0].beginTime, 0.25)
        XCTAssertEqual(rbTransition.effects[0].duration, 0.75)
        XCTAssertEqual(rbTransition.effects[0].events, 3)
        XCTAssertEqual(rbTransition.effects[0].flags, 1)

        let copied = rbTransition.copy() as? RBTransition
        XCTAssertEqual(copied, rbTransition)
        XCTAssertFalse(copied === rbTransition)
        XCTAssertFalse(copied?.effects.first === rbTransition.effects.first)
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

        let offset = OffsetTransition(offset: CGSize(width: 3, height: -4))
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

    private func makeDisplayList(debugItemCount: Int) -> DisplayList {
        var list = DisplayList()
        for _ in 0..<debugItemCount {
            list.debugItems.append { _ in }
        }
        return list
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
