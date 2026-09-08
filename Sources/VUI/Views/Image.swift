//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

struct PlatformImageRepresentableContext {
    var image: ImageDrawing
    var tintColor: Color?
    var foregroundStyle: AnyShapeStyle?
}

struct PlatformNamedImageRepresentableContext {
    var image: Image
    var environment: EnvironmentValues
}

protocol PlatformImageRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool
    static func makeRepresentation(
        inputs: _ViewInputs,
        context: Attribute<PlatformImageRepresentableContext>,
        outputs: inout _ViewOutputs
    )
}

protocol PlatformNamedImageRepresentable {
    static func shouldMakeRepresentation(inputs: _ViewInputs) -> Bool
    static func makeRepresentation(
        inputs: _ViewInputs,
        context: Attribute<PlatformNamedImageRepresentableContext>,
        outputs: inout _ViewOutputs
    )
}

private struct ImageRepresentationKey: GraphInput {
    typealias Value = (any PlatformImageRepresentable.Type)?

    static var defaultValue: Value { nil }

    static func valuesEqual(_ a: Value, _ b: Value) -> Bool {
        switch (a, b) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            false
        }
    }
}

private struct NamedImageRepresentationKey: GraphInput {
    typealias Value = (any PlatformNamedImageRepresentable.Type)?

    static var defaultValue: Value { nil }

    static func valuesEqual(_ a: Value, _ b: Value) -> Bool {
        switch (a, b) {
        case (nil, nil):
            true
        case let (lhs?, rhs?):
            ObjectIdentifier(lhs) == ObjectIdentifier(rhs)
        default:
            false
        }
    }
}

extension _GraphInputs {
    var requestedImageRepresentation:
        (any PlatformImageRepresentable.Type)? {
        get { self[ImageRepresentationKey.self] }
        set { self[ImageRepresentationKey.self] = newValue }
    }

    var requestedNamedImageRepresentation:
        (any PlatformNamedImageRepresentable.Type)? {
        get { self[NamedImageRepresentationKey.self] }
        set { self[NamedImageRepresentationKey.self] = newValue }
    }
}

extension _ViewInputs {
    var requestedImageRepresentation:
        (any PlatformImageRepresentable.Type)? {
        get { base.requestedImageRepresentation }
        set { base.requestedImageRepresentation = newValue }
    }

    var requestedNamedImageRepresentation:
        (any PlatformNamedImageRepresentable.Type)? {
        get { base.requestedNamedImageRepresentation }
        set { base.requestedNamedImageRepresentation = newValue }
    }
}

class AnyImageProviderBox: @unchecked Sendable {
    var requiresBackendResolution: Bool { true }
    var usesSymbolFontMetrics: Bool { false }
    var resizingProvider: ResizableProvider? { nil }

    func makeGraphicsImage(_ context: GraphicsContext) -> GraphicsImage {
        if let symbol = makeVectorSymbol() {
            return GraphicsImage(symbol: symbol.applyingEffectiveFontMetrics(in: context.environment))
        }
        if let svg = makeSVG() {
            return GraphicsImage(svg: svg)
        }
        let texture = makeTexture(context)
        return GraphicsImage(texture: texture, scale: context.sceneResources.contentScaleFactor / scaleFactor)
    }

    func makeTexture(_ context: GraphicsContext) -> Texture? {
        nil
    }

    func makeVectorSymbol() -> ResolvedVectorSymbol? {
        nil
    }

    func makeSVG() -> SVG? {
        nil
    }

    var scaleFactor: CGFloat { 1 }

    func isEqual(to other: AnyImageProviderBox) -> Bool {
        return self === other
    }

    @TaskLocal
    fileprivate static var _preferredBundle: Bundle?
}

final class ResizableProvider: AnyImageProviderBox, @unchecked Sendable {
    let base: Image
    let capInsets: EdgeInsets
    let resizingMode: Image.ResizingMode

    init(
        base: Image,
        capInsets: EdgeInsets,
        resizingMode: Image.ResizingMode
    ) {
        self.base = base
        self.capInsets = capInsets
        self.resizingMode = resizingMode
    }

    override var requiresBackendResolution: Bool {
        base.provider.requiresBackendResolution
    }

    override var usesSymbolFontMetrics: Bool {
        base.provider.usesSymbolFontMetrics
    }

    override var resizingProvider: ResizableProvider? {
        self
    }

    override func makeGraphicsImage(_ context: GraphicsContext) -> GraphicsImage {
        var image = base.provider.makeGraphicsImage(context)
        image.resizingInfo = Image.ResizingInfo(capInsets: capInsets, mode: resizingMode)
        return image
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        base.provider.makeTexture(context)
    }

    override func makeVectorSymbol() -> ResolvedVectorSymbol? {
        base.provider.makeVectorSymbol()
    }

    override func makeSVG() -> SVG? {
        base.provider.makeSVG()
    }

    override var scaleFactor: CGFloat {
        base.provider.scaleFactor
    }

    override func isEqual(to other: AnyImageProviderBox) -> Bool {
        guard let other = other as? ResizableProvider else { return false }
        return base == other.base &&
            capInsets == other.capInsets &&
            resizingMode == other.resizingMode
    }
}

final class NamedImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let name: String
    let value: Float?
    let location: Bundle?
    let label: Text?
    var scale: CGFloat = 1.0

    init(name: String, value: Float?, location: Bundle?, label: Text?) {
        self.name = name
        self.value = value
        self.location = location
        self.label = label
    }

    override var scaleFactor: CGFloat {
        self.scale
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        let bundles: [Bundle]
        if let location = self.location {
            bundles = [location]
        } else {
            bundles = [
                Self._preferredBundle,
                Image._mainNamedBundle,
                .main
            ].compactMap(\.self)
        }

        for bundle in bundles {
            if let url = bundle.url(forResource: self.name,
                                    withExtension: nil,
                                    subdirectory: nil) {

                let sceneResources = context.sceneResources
                if let texture = sceneResources.cachedTextures[url.absoluteString] as? Texture {
                    self.scale = sceneResources.contentScaleFactor
                    return texture
                }

                var image: VVD.Image?
                do {
                    Log.debug("url: \(url)")
                    let data = try Data(contentsOf: url, options: [])
                    image = data.withUnsafeBytes { ptr in
                        VVD.Image(data: ptr)
                    }
                } catch {
                    Log.error("Error on loading data: \(error)")
                }
                if let texture = image?.makeTexture(commandQueue: context.commandQueue) {
                    // cache
                    sceneResources.cachedTextures[url.absoluteString] = texture
                    self.scale = sceneResources.contentScaleFactor
                    return texture
                }
                Log.error("Failed to create texture from image at url: \(url)")
                return nil
            }
        }
        return nil
    }

    override func isEqual(to other: AnyImageProviderBox) -> Bool {
        if let other = other as? Self {
            return self.name == other.name &&
            self.value == other.value &&
            self.location == other.location &&
            self.label == other.label
        }
        return false
    }
}

final class RenderedImageProviderBox: AnyImageProviderBox, @unchecked Sendable {
    let size: CGSize
    let label: Text?
    let opaque: Bool
    let colorMode: ColorRenderingMode
    let renderer: (inout GraphicsContext)->Void
    init(size: CGSize, label: Text?, opaque: Bool, colorMode: ColorRenderingMode, renderer: @escaping (inout GraphicsContext) -> Void) {
        self.size = size
        self.label = label
        self.opaque = opaque
        self.colorMode = colorMode
        self.renderer = renderer
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        if var context = context.makeLayerContext(self.size) {
            renderer(&context)
            return context.backdrop
        }
        return nil
    }
}

final class TextureImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let resource: ImageTexture
    let scale: CGFloat
    let orientation: Image.Orientation
    let label: Text?

    init(texture: Texture, scale: CGFloat, orientation: Image.Orientation, label: Text?) {
        self.resource = ImageTexture(texture)
        self.scale = scale
        self.orientation = orientation
        self.label = label
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        resource.texture
    }

    override func makeGraphicsImage(_ context: GraphicsContext) -> GraphicsImage {
        GraphicsImage(contents: .texture(resource), scale: scale,
                      unrotatedPixelSize: resource.pixelSize, orientation: orientation)
    }

    override var scaleFactor: CGFloat {
        self.scale
    }

    override func isEqual(to: AnyImageProviderBox) -> Bool {
        if let other = to as? Self {
            return resource == other.resource &&
            self.scale == other.scale &&
            orientation == other.orientation &&
            label == other.label
        }
        return false
    }
}

final class SymbolImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let name: String
    let variableValue: Double?
    let bundle: Bundle?
    let label: Text?

    init(name: String, variableValue: Double?, bundle: Bundle?, label: Text?) {
        self.name = name
        self.variableValue = variableValue
        self.bundle = bundle
        self.label = label
    }

    override var requiresBackendResolution: Bool { false }
    override var usesSymbolFontMetrics: Bool { true }

    override func makeVectorSymbol() -> ResolvedVectorSymbol? {
        SymbolAssetCatalog.resolve(
            name: name,
            variableValue: variableValue,
            bundle: bundle
        )
    }

    override func isEqual(to other: AnyImageProviderBox) -> Bool {
        guard let other = other as? SymbolImageProvider else { return false }
        return name == other.name &&
            variableValue == other.variableValue &&
            bundle == other.bundle &&
            label == other.label
    }
}

final class SVGImageProvider: AnyImageProviderBox, @unchecked Sendable {
    let svg: SVG
    let label: Text?

    init(svg: SVG, label: Text?) {
        self.svg = svg
        self.label = label
    }

    override var requiresBackendResolution: Bool { false }

    override func makeSVG() -> SVG? {
        svg
    }

    override func isEqual(to other: AnyImageProviderBox) -> Bool {
        guard let other = other as? SVGImageProvider else { return false }
        return svg == other.svg && label == other.label
    }
}

/// Adapts optional backend image resolution to the display-list transition contract.
///
/// Resolution can begin with a nil value, while interpolation requires stable
/// non-optional endpoints. Unresolved publication boundaries are ignored.
private struct ResolvedImageTransitionContent: InterpolatableContent {
    var image: ImageDrawing?

    static var defaultTransition: ContentTransition {
        ImageDrawing.defaultTransition
    }

    func requiresTransition(to target: Self) -> Bool {
        guard let image, let targetImage = target.image else { return false }
        return image.requiresTransition(to: targetImage)
    }

    func modifyTransition(state: inout ContentTransition.State, to target: Self) {
        guard let image, let targetImage = target.image else { return }
        image.modifyTransition(state: &state, to: targetImage)
    }
}

/// Publishes the specialized layout engine for a resolved image attribute.
private struct ResolvedImageLayoutComputer: StatefulRule, AsyncAttribute {
    typealias Value = LayoutComputer

    var _image: Attribute<ImageDrawing?>

    mutating func updateValue() {
        update(to: ResolvedImageLayoutEngine(image: _image.value))
    }
}

/// Measures a resolved image and exposes its direct layout characteristics.
private struct ResolvedImageLayoutEngine: LayoutEngine {
    var image: ImageDrawing?

    func spacing() -> Spacing {
        Spacing()
    }

    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        image?.sizeThatFits(proposal) ?? .zero
    }

    func lengthThatFits(_ proposal: _ProposedSize, in axis: Axis) -> CGFloat {
        let size = sizeThatFits(proposal)
        return axis == .horizontal ? size.width : size.height
    }

    func explicitAlignment(_ key: AlignmentKey, at size: ViewSize) -> CGFloat? {
        nil
    }
}

struct ImageViewChild: StatefulRule, AsyncAttribute {
    // Graph evaluation is serialized. Reference semantics let the presentation
    // rule seed this write-once clock without introducing a cross-rule lock.
    final class PresentationStart {
        private(set) var time: Time?
        private var continuations: [PresentationStart] = []

        func activate(at value: Time) {
            if time == nil {
                time = value
            }
            continuations.forEach { $0.activate(at: value) }
        }

        func append(_ continuation: PresentationStart) {
            continuations.append(continuation)
        }
    }

    private enum Source {
        case image(
            view: Attribute<Image>,
            backendSource: Attribute<Image?>,
            backendImage: Attribute<ImageDrawing?>
        )
        case resolved(Attribute<ImageDrawing?>)
    }

    struct ActivePulse {
        var id: Int
        var startTime: Time
        var cycleDuration: Double
        var cycleCount: Int?
        var repeatDelay: Double
        var isLayered: Bool
        var finishesAfterEffectRemoval = false
    }

    struct ActiveVariableColor {
        static let introDuration = 13.0 / 30.0
        static let outroDuration = 4.0 / 15.0
        static let stepDuration = 1.0 / 3.0

        var id: Int
        var startTime: Time
        var groupCount: Int
        var cycleCount: Int?
        var effectiveSpeed: Double
        var isReversing: Bool
        var isIterative: Bool
        var inactiveOpacity: Double
        var initialOpacities: [Double]
        var finishesAfterEffectRemoval = false

        var localDuration: Double {
            let count = Double(groupCount)
            switch (isIterative, isReversing) {
            case (false, false):
                return (count + 2) * Self.stepDuration
            case (false, true):
                return (2 * count + 1) * Self.stepDuration
            case (true, false):
                return (count + 1) * Self.stepDuration
            case (true, true):
                if groupCount <= 2 {
                    return 2 * Self.stepDuration
                }
                return 2 * Double(groupCount - 1) * Self.stepDuration
            }
        }
    }

    struct DrawLeg {
        var motionGroupTimings: [ResolvedVectorSymbol.DrawMotionGroupTiming]
        var pathStartOffsets: [Double]
        var opacityStartOffsets: [Double]
        var initialProgresses: [Double]
        var initialFallbackProgresses: [Double]
        var targetProgress: Double
        var effectiveSpeed: Double
        var isReversed: Bool
        var completionTokens: [AnimationCompletionToken]
    }

    struct DrawContinuation {
        var presentationStart: PresentationStart
        var leg: DrawLeg
    }

    struct ActiveDraw {
        var id: Int
        var presentationStart: PresentationStart
        var primary: DrawLeg
        var continuations: [DrawContinuation]
        var pathBaseIntervals:
            [[ResolvedVectorSymbol.DrawPathInterval]]?
        var fallbackBaseProgresses: [Double]
        var layerBehavior: DrawLayerBehavior
        var configuredReversed: Bool
        var usesOpacityFallback: Bool
        // A completed draw-to-hidden request keeps its terminal presentation,
        // but must no longer keep the frame-clock dependency alive.
        var isComplete = false

        var targetProgress: Double {
            continuations.last?.leg.targetProgress ?? primary.targetProgress
        }
    }

    struct DrawPresentation {
        var pathIntervals:
            [[ResolvedVectorSymbol.DrawPathInterval]]?
        var progresses: [Double]?
        var fallbackProgresses: [Double]?
        var fallbackOpacity: Double?
        var isReversed = false
        var isActive = false
    }

    struct DrawLegPresentation {
        var progresses: [Double]
        var fallbackProgresses: [Double]
        var fallbackStarted: [Bool]
        var isComplete: Bool
    }

    struct Phase {
        var effects: [IdentifiedSymbolEffect] = []
        var version: UInt32 = 0
        var hasResolvedEffects = false
        var activePulse: ActivePulse?
        var activeVariableColor: ActiveVariableColor?
        var activeDraw: ActiveDraw?
        // Resource publication may arrive after willAppear has already advanced
        // to identity. Preserve both the hidden boundary and the identity
        // transaction across that gap.
        fileprivate var pendingDrawTransitionStart: DrawRequest?
        fileprivate var pendingDrawTransitionTransaction: Transaction?
    }

    struct Value {
        var image: ImageDrawing?
        var symbolAnimator: SymbolAnimator?
        var symbolEffects: [IdentifiedSymbolEffect]
        var symbolEffectVersion: UInt32
        var symbolOpacity: Double
        var symbolLayerOpacities: [Double]?
        var symbolVariableColorOpacities: [Double]?
        var symbolDrawPathIntervals:
            [[ResolvedVectorSymbol.DrawPathInterval]]?
        var symbolDrawProgresses: [Double]?
        var symbolDrawFallbackProgresses: [Double]?
        var symbolDrawFallbackOpacity: Double?
        var symbolDrawsReversed: Bool
        var isSymbolEffectActive: Bool
        var retainsDrawHidePosition: Bool
        var drawPresentationStart: PresentationStart?
        var displayPosition: CGPoint?
        var displaySize: ViewSize?
    }

    private var source: Source
    var environment: Attribute<EnvironmentValues>
    var transaction: Attribute<Transaction>
    var time: Attribute<Time>
    var phase = Phase()
    private var symbolAnimator: SymbolAnimator?
    private var synchronousSource: Image?
    private var synchronousImage: ImageDrawing?
    private var synchronousVectorSymbol: ResolvedVectorSymbol?
    private var synchronousSymbolFont: Font?
    private var attemptedSynchronousResolution = false

    init(
        view: Attribute<Image>,
        backendSource: Attribute<Image?>,
        backendImage: Attribute<ImageDrawing?>,
        environment: Attribute<EnvironmentValues>,
        transaction: Attribute<Transaction>,
        time: Attribute<Time>
    ) {
        self.source = .image(
            view: view,
            backendSource: backendSource,
            backendImage: backendImage
        )
        self.environment = environment
        self.transaction = transaction
        self.time = time
    }

    init(
        resolvedImage: Attribute<ImageDrawing?>,
        environment: Attribute<EnvironmentValues>,
        transaction: Attribute<Transaction>,
        time: Attribute<Time>
    ) {
        self.source = .resolved(resolvedImage)
        self.environment = environment
        self.transaction = transaction
        self.time = time
    }

    mutating func updateValue() {
        let currentEnvironment = environment.value
        let image = resolvedImage(in: currentEnvironment)
        let environmentEffects = currentEnvironment.symbolEffects
        let transaction = transaction.value
        let symbolAnimator = updateSymbolAnimator(
            image: image,
            state: currentEnvironment.contentTransitionState,
            transaction: transaction
        )
        let pendingDrawTransition = updatePendingDrawTransition(
            effects: environmentEffects,
            hasResolvedImage: image != nil,
            hasResolvedSymbol: image?.symbol != nil,
            transaction: transaction
        )
        let nextEffects = image?.symbol == nil ? [] : environmentEffects
        let nextDrawRequest = drawRequest(in: nextEffects)
        let matchingPendingDrawTransition:
            (start: DrawRequest, transaction: Transaction?)?
        if let pendingDrawTransition,
           let nextDrawRequest,
           pendingDrawTransition.start.matchesTransition(nextDrawRequest) {
            matchingPendingDrawTransition = pendingDrawTransition
        } else {
            matchingPendingDrawTransition = nil
        }
        let effectsChanged = !symbolEffectListsEqual(phase.effects, nextEffects)

        // The semantic image consumer must not retain the frame clock while its
        // animator is idle. A time edge is installed only while an existing
        // presentation is active or while an effect change needs a start time;
        // the graph's dynamic-edge lifecycle removes it on the first idle pass.
        let needsPresentationTime = effectsChanged ||
            phase.activePulse != nil ||
            phase.activeVariableColor != nil ||
            phase.activeDraw?.isComplete == false
        let now = needsPresentationTime ? time.value : .zero
        let previousVariablePresentation = variableColorPresentation(at: now)
        let previousDrawPresentation = drawPresentation(at: now)

        if effectsChanged {
            if let activation = activatedPulse(
                previous: phase.effects,
                next: nextEffects,
                hasResolvedEffects: phase.hasResolvedEffects,
                at: now
            ) {
                if var active = phase.activePulse,
                   let activeCount = active.cycleCount,
                   let activationCount = activation.cycleCount,
                   canAppendPulse(
                    active: active,
                    activation: activation,
                    previous: phase.effects,
                    next: nextEffects
                   ) {
                    active.cycleCount = activeCount + activationCount
                    phase.activePulse = active
                } else {
                    phase.activePulse = activation
                }
            } else if let active = phase.activePulse {
                let old = phase.effects.first { $0.id == active.id }
                let new = nextEffects.first { $0.id == active.id }
                if let old, let new {
                    if !symbolEffectsEqual(old, new) {
                        phase.activePulse = nil
                    }
                } else if let old,
                          let finishing = pulseFinishingCurrentCycle(
                            active,
                            removedEffect: old,
                            at: now
                          ) {
                    phase.activePulse = finishing
                } else {
                    phase.activePulse = nil
                }
            }
            if let symbol = image?.symbol,
               let activation = activatedVariableColor(
                previous: phase.effects,
                next: nextEffects,
                hasResolvedEffects: phase.hasResolvedEffects,
                groupCount: symbol.variableColorLevelCount,
                initialOpacities: previousVariablePresentation.opacities,
                at: now
               ) {
                phase.activeVariableColor = activation
            } else if let active = phase.activeVariableColor {
                let old = phase.effects.first { $0.id == active.id }
                let new = nextEffects.first { $0.id == active.id }
                if let old, let new {
                    if !symbolEffectsEqual(old, new) {
                        phase.activeVariableColor = nil
                    }
                } else if let old,
                          let finishing = variableColorFinishingCurrentCycle(
                            active,
                            removedEffect: old,
                            at: now
                          ) {
                    phase.activeVariableColor = finishing
                } else {
                    phase.activeVariableColor = nil
                }
            }
            if let symbol = image?.symbol {
                if let pendingDrawTransition = matchingPendingDrawTransition,
                   let nextDrawRequest,
                   pendingDrawTransition.start.matchesTransition(nextDrawRequest) {
                    finishActiveDrawCompletionTokens()
                    let shouldAnimateFromHidden = nextDrawRequest.targetProgress >= 1
                    phase.activeDraw = drawAnimation(
                        for: nextDrawRequest,
                        symbol: symbol,
                        initialProgresses: shouldAnimateFromHidden
                            ? [Double](
                                repeating: 0,
                                count: max(symbol.drawMotionGroupDurations.count, 1)
                            )
                            : nil,
                        transaction: pendingDrawTransition.transaction ?? transaction,
                        immediate: !shouldAnimateFromHidden
                    )
                } else {
                    if drawRequest(in: phase.effects) != nextDrawRequest,
                       !canAppendOrdinaryDrawWave(
                        previous: phase.effects,
                        next: nextEffects,
                        current: phase.activeDraw
                       ) {
                        finishActiveDrawCompletionTokens()
                    }
                    phase.activeDraw = updatedDrawAnimation(
                        previous: phase.effects,
                        next: nextEffects,
                        current: phase.activeDraw,
                        presentation: previousDrawPresentation,
                        symbol: symbol,
                        hasResolvedEffects: phase.hasResolvedEffects,
                        transaction: transaction,
                        at: now
                    )
                }
            } else {
                finishActiveDrawCompletionTokens()
                phase.activeDraw = nil
            }
            phase.effects = nextEffects
            phase.version &+= 1
        }
        phase.hasResolvedEffects = true

        if image?.symbol == nil || transaction.disablesAnimations {
            phase.activePulse = nil
            phase.activeVariableColor = nil
        } else if let active = phase.activePulse,
                  !active.finishesAfterEffectRemoval,
                  !nextEffects.contains(where: { $0.id == active.id }) {
            phase.activePulse = nil
        }

        let drawTransaction =
            matchingPendingDrawTransition?.transaction ?? transaction
        if image?.symbol == nil || drawTransaction.disablesAnimations {
            finishActiveDrawCompletionTokens()
            if let symbol = image?.symbol,
               let request = drawRequest(in: nextEffects) {
                phase.activeDraw = drawAnimation(
                    for: request,
                    symbol: symbol,
                    initialProgresses: nil,
                    transaction: drawTransaction,
                    immediate: true
                )
            } else {
                phase.activeDraw = nil
            }
        }

        if let active = phase.activeVariableColor {
            if image?.symbol?.variableColorLevelCount != active.groupCount {
                phase.activeVariableColor = nil
            } else if !active.finishesAfterEffectRemoval,
                      !nextEffects.contains(where: { $0.id == active.id }) {
                phase.activeVariableColor = nil
            }
        }

        let pulse = pulsePresentation(at: now)
        let variableColor = variableColorPresentation(at: now)
        let draw = drawPresentation(at: now)
        let isActive = pulse.isActive || variableColor.isActive || draw.isActive
        let retainsDrawHidePosition = draw.isActive &&
            phase.activeDraw?.targetProgress == 0
        if isActive,
           let ref = _AGGraphContext.current,
           let viewGraph = ref.context as? ViewGraph {
            viewGraph.nextUpdate.views.at(now + 1.0 / 120.0)
        }

        _AGGraph.setStatefulOutput(Value(
            image: image,
            symbolAnimator: symbolAnimator,
            symbolEffects: phase.effects,
            symbolEffectVersion: phase.version,
            symbolOpacity: pulse.opacity,
            symbolLayerOpacities: pulse.layerOpacities,
            symbolVariableColorOpacities: variableColor.opacities,
            symbolDrawPathIntervals: draw.pathIntervals,
            symbolDrawProgresses: draw.progresses,
            symbolDrawFallbackProgresses: draw.fallbackProgresses,
            symbolDrawFallbackOpacity: draw.fallbackOpacity,
            symbolDrawsReversed: draw.isReversed,
            isSymbolEffectActive: isActive,
            retainsDrawHidePosition: retainsDrawHidePosition,
            drawPresentationStart: draw.isActive
                ? phase.activeDraw?.presentationStart
                : nil,
            displayPosition: nil,
            displaySize: nil
        ))
    }

    private mutating func updateSymbolAnimator(
        image: ImageDrawing?,
        state: ContentTransition.State,
        transaction: Transaction
    ) -> SymbolAnimator? {
        guard let image, image.symbol != nil else {
            symbolAnimator?.cancel()
            symbolAnimator = nil
            return nil
        }

        if let symbolAnimator {
            symbolAnimator.update(
                image: image,
                state: state,
                transaction: transaction
            )
            return symbolAnimator
        }

        let animator = SymbolAnimator(image: image)
        symbolAnimator = animator
        return animator
    }

    private mutating func resolvedImage(
        in environment: EnvironmentValues
    ) -> ImageDrawing? {
        switch source {
        case let .resolved(image):
            return image.value

        case let .image(view, backendSource, backendImage):
            let image = view.value
            guard !image.provider.requiresBackendResolution else {
                synchronousSource = nil
                synchronousImage = nil
                synchronousVectorSymbol = nil
                synchronousSymbolFont = nil
                attemptedSynchronousResolution = false
                guard backendSource.value == image else { return nil }
                return backendImage.value
            }

            let symbolFont = image.provider.usesSymbolFontMetrics
                ? (environment.font ?? .system(.body))
                : nil
            if attemptedSynchronousResolution,
               synchronousSource == image,
               synchronousSymbolFont == symbolFont {
                return synchronousImage
            }

            var resolved: ImageDrawing?
            if synchronousSource == image,
               let symbol = synchronousVectorSymbol {
                resolved = ImageDrawing(
                    symbol: symbol.applyingEffectiveFontMetrics(in: environment)
                )
            } else if let symbol = image.provider.makeVectorSymbol() {
                synchronousVectorSymbol = symbol
                resolved = ImageDrawing(
                    symbol: symbol.applyingEffectiveFontMetrics(in: environment)
                )
            } else if let svg = image.provider.makeSVG() {
                synchronousVectorSymbol = nil
                resolved = ImageDrawing(svg: svg)
            } else {
                synchronousVectorSymbol = nil
                resolved = nil
            }
            resolved?.applyResizingProvider(image.provider)
            synchronousSource = image
            synchronousImage = resolved
            synchronousSymbolFont = symbolFont
            attemptedSynchronousResolution = true
            return resolved
        }
    }

    private mutating func updatePendingDrawTransition(
        effects: [IdentifiedSymbolEffect],
        hasResolvedImage: Bool,
        hasResolvedSymbol: Bool,
        transaction: Transaction
    ) -> (start: DrawRequest, transaction: Transaction?)? {
        if hasResolvedImage {
            defer {
                phase.pendingDrawTransitionStart = nil
                phase.pendingDrawTransitionTransaction = nil
            }
            guard hasResolvedSymbol,
                  let start = phase.pendingDrawTransitionStart else {
                return nil
            }
            return (start, phase.pendingDrawTransitionTransaction)
        }

        guard let request = drawRequest(in: effects), request.isTransition else {
            phase.pendingDrawTransitionStart = nil
            phase.pendingDrawTransitionTransaction = nil
            return nil
        }
        if request.targetProgress <= 0 {
            phase.pendingDrawTransitionStart = request
            phase.pendingDrawTransitionTransaction = nil
        } else if phase.pendingDrawTransitionStart?.matchesTransition(request) == true {
            phase.pendingDrawTransitionTransaction = transaction
        } else {
            phase.pendingDrawTransitionStart = nil
            phase.pendingDrawTransitionTransaction = nil
        }
        return nil
    }

    private mutating func finishActiveDrawCompletionTokens() {
        guard var active = phase.activeDraw else { return }
        var tokens = active.primary.completionTokens
        active.primary.completionTokens.removeAll()
        for index in active.continuations.indices {
            var continuation = active.continuations[index]
            tokens.append(contentsOf: continuation.leg.completionTokens)
            continuation.leg.completionTokens.removeAll()
            active.continuations[index] = continuation
        }
        phase.activeDraw = active
        guard !tokens.isEmpty else { return }
        finishDrawCompletionTokens(tokens)
    }

    private mutating func pulsePresentation(
        at time: Time
    ) -> (opacity: Double, layerOpacities: [Double]?, isActive: Bool) {
        guard let pulse = phase.activePulse else { return (1, nil, false) }
        let cycleDuration = pulse.cycleDuration
        let elapsed = max(time.seconds - pulse.startTime.seconds, 0)
        let cycleStride = cycleDuration + pulse.repeatDelay
        if let cycleCount = pulse.cycleCount {
            let totalDuration = cycleDuration * Double(cycleCount) +
                pulse.repeatDelay * Double(max(cycleCount - 1, 0))
            if elapsed >= totalDuration {
                phase.activePulse = nil
                return (1, nil, false)
            }
        }
        let cycleElapsed = elapsed.truncatingRemainder(dividingBy: cycleStride)
        if cycleElapsed >= cycleDuration {
            return pulsePresentation(opacity: 1, pulse: pulse)
        }
        let progress = cycleElapsed / cycleDuration
        let opacity = 0.65 + 0.35 * cos(progress * 2.0 * .pi)
        return pulsePresentation(opacity: opacity, pulse: pulse)
    }

    private func pulsePresentation(
        opacity: Double,
        pulse: ActivePulse
    ) -> (opacity: Double, layerOpacities: [Double]?, isActive: Bool) {
        pulse.isLayered ? (1, [opacity], true) : (opacity, nil, true)
    }

    private mutating func variableColorPresentation(
        at time: Time
    ) -> (opacities: [Double]?, isActive: Bool) {
        guard let active = phase.activeVariableColor else {
            return (nil, false)
        }
        let elapsed = max(time.seconds - active.startTime.seconds, 0) *
            active.effectiveSpeed
        if elapsed < ActiveVariableColor.introDuration {
            return (variableColorIntroOpacities(at: elapsed, active: active), true)
        }

        let elapsedAfterIntro = elapsed - ActiveVariableColor.introDuration
        if let cycleCount = active.cycleCount {
            let localSpan = active.localDuration * Double(cycleCount)
            if elapsedAfterIntro >= localSpan {
                let outroTime = elapsedAfterIntro - localSpan
                if outroTime >= ActiveVariableColor.outroDuration {
                    phase.activeVariableColor = nil
                    return (nil, false)
                }
                return (
                    variableColorOutroOpacities(at: outroTime, active: active),
                    true
                )
            }
        }

        let localTime = elapsedAfterIntro.truncatingRemainder(
            dividingBy: active.localDuration
        )
        return (variableColorLocalOpacities(at: localTime, active: active), true)
    }

    private func variableColorIntroOpacities(
        at time: Double,
        active: ActiveVariableColor
    ) -> [Double] {
        let progress = variableColorEase(
            (time - 0.1) / ActiveVariableColor.stepDuration
        )
        return active.initialOpacities.map {
            variableColorMix(
                $0,
                active.inactiveOpacity,
                progress: progress
            )
        }
    }

    private func variableColorLocalOpacities(
        at time: Double,
        active: ActiveVariableColor
    ) -> [Double] {
        if active.isIterative && active.isReversing {
            return variableColorSequentialBounceOpacities(at: time, active: active)
        }

        let inactive = active.inactiveOpacity
        let step = ActiveVariableColor.stepDuration
        var result = [Double](repeating: inactive, count: active.groupCount)
        for level in result.indices {
            let activationStart = step * Double(level)
            let activation = variableColorEase(
                (time - activationStart) / step
            )
            result[level] = variableColorMix(
                inactive,
                1,
                progress: activation
            )
            if active.isIterative, level < result.count - 1 {
                let deactivation = variableColorEase(
                    (time - activationStart - step) / step
                )
                result[level] = variableColorMix(
                    result[level],
                    inactive,
                    progress: deactivation
                )
            }
        }

        let reverseStart = step * Double(
            active.groupCount + (active.isIterative ? 0 : 1)
        )
        for level in result.indices {
            let deactivationStart = active.isReversing
                ? reverseStart + step * Double(result.count - 1 - level)
                : reverseStart
            let deactivation = variableColorEase(
                (time - deactivationStart) / step
            )
            result[level] = variableColorMix(
                result[level],
                inactive,
                progress: deactivation
            )
        }
        return result
    }

    private func variableColorSequentialBounceOpacities(
        at time: Double,
        active: ActiveVariableColor
    ) -> [Double] {
        let inactive = active.inactiveOpacity
        var result = [Double](repeating: inactive, count: active.groupCount)
        guard active.groupCount > 1 else {
            result[0] = 1
            return result
        }

        let forward = Array(0..<active.groupCount)
        let path = forward + Array(
            forward.dropLast().dropFirst().reversed()
        ) + [0]
        let step = ActiveVariableColor.stepDuration
        let position = min(
            max(time / step, 0),
            Double(path.count - 1)
        )
        let segment = min(Int(position), path.count - 2)
        let progress = variableColorEase(position - Double(segment))
        let source = path[segment]
        let target = path[segment + 1]
        result[source] = variableColorMix(1, inactive, progress: progress)
        result[target] = variableColorMix(inactive, 1, progress: progress)
        return result
    }

    private func variableColorOutroOpacities(
        at time: Double,
        active: ActiveVariableColor
    ) -> [Double] {
        let progress = variableColorEase(
            time / ActiveVariableColor.outroDuration
        )
        return variableColorTerminalOpacities(active).map {
            variableColorMix($0, 1, progress: progress)
        }
    }

    private func variableColorTerminalOpacities(
        _ active: ActiveVariableColor
    ) -> [Double] {
        var result = [Double](
            repeating: active.inactiveOpacity,
            count: active.groupCount
        )
        if active.isIterative && active.isReversing {
            result[0] = 1
        }
        return result
    }

    private mutating func drawPresentation(at time: Time) -> DrawPresentation {
        guard var active = phase.activeDraw else {
            return DrawPresentation()
        }
        if active.isComplete {
            // Clearing a completed hide would restore the fully drawn symbol.
            // Publish the terminal value without sampling presentation time.
            let progresses = [Double](
                repeating: active.targetProgress,
                count: active.primary.initialProgresses.count
            )
            if active.usesOpacityFallback {
                return DrawPresentation(
                    progresses: nil,
                    fallbackOpacity: active.targetProgress,
                    isReversed: active.primary.isReversed,
                    isActive: false
                )
            }
            return DrawPresentation(
                pathIntervals: active.pathBaseIntervals.map {
                    $0.map { _ in [] }
                },
                progresses: progresses,
                fallbackProgresses: progresses,
                isReversed: active.primary.isReversed,
                isActive: false
            )
        }
        let startTime = active.presentationStart.time ?? time
        let primaryElapsed = max(time.seconds - startTime.seconds, 0) *
            active.primary.effectiveSpeed

        func resolvedProgress(
            initial: Double,
            target: Double,
            duration: Double,
            startOffset: Double,
            elapsed: Double
        ) -> (value: Double, isComplete: Bool, hasStarted: Bool) {
            let distance = abs(target - initial)
            let scaledDuration = duration * distance
            guard scaledDuration > .ulpOfOne else {
                return (target, true, true)
            }
            guard elapsed > startOffset else {
                return (initial, false, false)
            }
            let linearProgress = min(
                max((elapsed - startOffset) / scaledDuration, 0),
                1
            )
            return (
                drawMix(
                initial,
                    target,
                progress: drawEase(linearProgress)
                ),
                linearProgress >= 1,
                true
            )
        }

        func presentation(
            of leg: DrawLeg,
            elapsed: Double
        ) -> DrawLegPresentation {
            var progresses = leg.initialProgresses
            var fallbackProgresses = leg.initialFallbackProgresses
            var fallbackStarted = [Bool](
                repeating: false,
                count: leg.motionGroupTimings.count
            )
            var isComplete = true
            for index in leg.motionGroupTimings.indices {
                let timing = leg.motionGroupTimings[index]
                let path = resolvedProgress(
                    initial: leg.initialProgresses[index],
                    target: leg.targetProgress,
                    duration: timing.pathDuration ??
                        timing.opacityDuration ?? 0,
                    startOffset: leg.pathStartOffsets[index],
                    elapsed: elapsed
                )
                progresses[index] = path.value
                isComplete = isComplete && path.isComplete

                let fallback = resolvedProgress(
                    initial: leg.initialFallbackProgresses[index],
                    target: leg.targetProgress,
                    duration: timing.opacityDuration ??
                        timing.pathDuration ?? 0,
                    startOffset: leg.opacityStartOffsets[index],
                    elapsed: elapsed
                )
                fallbackProgresses[index] = fallback.value
                fallbackStarted[index] = fallback.hasStarted
                isComplete = isComplete && fallback.isComplete
            }
            return DrawLegPresentation(
                progresses: progresses,
                fallbackProgresses: fallbackProgresses,
                fallbackStarted: fallbackStarted,
                isComplete: isComplete
            )
        }

        var legPresentations = [presentation(
            of: active.primary,
            elapsed: primaryElapsed
        )]
        if legPresentations[0].isComplete,
           !active.primary.completionTokens.isEmpty {
            let tokens = active.primary.completionTokens
            active.primary.completionTokens.removeAll()
            finishDrawCompletionTokens(tokens)
        }

        for index in active.continuations.indices {
            var continuation = active.continuations[index]
            let elapsed = max(
                time.seconds -
                    (continuation.presentationStart.time ?? time).seconds,
                0
            ) * continuation.leg.effectiveSpeed
            let resolved = presentation(
                of: continuation.leg,
                elapsed: elapsed
            )
            if resolved.isComplete,
               !continuation.leg.completionTokens.isEmpty {
                let tokens = continuation.leg.completionTokens
                continuation.leg.completionTokens.removeAll()
                finishDrawCompletionTokens(tokens)
            }
            active.continuations[index] = continuation
            legPresentations.append(resolved)
        }

        while legPresentations.first?.isComplete == true,
              !active.continuations.isEmpty {
            let completedTarget = active.primary.targetProgress
            if let pathBaseIntervals = active.pathBaseIntervals {
                active.pathBaseIntervals = pathBaseIntervals.map { _ in
                    completedTarget >= 1
                        ? [ResolvedVectorSymbol.DrawPathInterval(from: 0, to: 1)]
                        : []
                }
            }
            active.fallbackBaseProgresses = [Double](
                repeating: completedTarget,
                count: active.fallbackBaseProgresses.count
            )
            let promoted = active.continuations.removeFirst()
            active.primary = promoted.leg
            active.presentationStart = promoted.presentationStart
            legPresentations.removeFirst()
        }

        let allComplete = legPresentations.allSatisfy(\.isComplete)
        if allComplete {
            if active.targetProgress >= 1 {
                phase.activeDraw = nil
                return DrawPresentation()
            }
            if let pathBaseIntervals = active.pathBaseIntervals {
                active.pathBaseIntervals = pathBaseIntervals.map { _ in [] }
            }
            active.fallbackBaseProgresses = [Double](
                repeating: 0,
                count: active.fallbackBaseProgresses.count
            )
            active.isComplete = true
            phase.activeDraw = active
            let progresses = [Double](
                repeating: 0,
                count: active.primary.initialProgresses.count
            )
            if active.usesOpacityFallback {
                return DrawPresentation(
                    fallbackOpacity: 0,
                    isActive: false
                )
            }
            return DrawPresentation(
                pathIntervals: active.pathBaseIntervals.map {
                    $0.map { _ in [] }
                },
                progresses: progresses,
                fallbackProgresses: progresses,
                isReversed: active.primary.isReversed,
                isActive: false
            )
        }

        let legs = [active.primary] +
            active.continuations.map(\.leg)
        var fallbackProgresses = active.fallbackBaseProgresses
        for legPresentation in legPresentations {
            for index in legPresentation.fallbackProgresses.indices
            where legPresentation.fallbackStarted[index] {
                fallbackProgresses[index] =
                    legPresentation.fallbackProgresses[index]
            }
        }

        var pathIntervals = active.pathBaseIntervals
        if var intervals = pathIntervals {
            for (leg, legPresentation) in zip(legs, legPresentations) {
                let makesVisible = leg.targetProgress >= 1
                for index in intervals.indices {
                    let value = legPresentation.progresses[index]
                    let frontProgress = makesVisible ? value : 1 - value
                    intervals[index] = applyingDrawPathWave(
                        to: intervals[index],
                        frontProgress: frontProgress,
                        makesVisible: makesVisible
                    )
                }
            }
            pathIntervals = intervals
        }
        phase.activeDraw = active

        if active.usesOpacityFallback {
            return DrawPresentation(
                progresses: nil,
                fallbackOpacity: fallbackProgresses.first ??
                    active.targetProgress,
                isReversed: legs.last?.isReversed ?? false,
                isActive: true
            )
        }
        return DrawPresentation(
            pathIntervals: pathIntervals,
            progresses: legPresentations.last?.progresses,
            fallbackProgresses: fallbackProgresses,
            isReversed: legs.last?.isReversed ?? false,
            isActive: true
        )
    }
}

struct ImageViewPresentation: StatefulRule, AsyncAttribute {
    typealias Value = ImageViewChild.Value

    var image: Attribute<ImageViewChild.Value>
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var time: Attribute<Time>
    private var previousTargetPosition: CGPoint?
    private var retainedDrawHidePosition: CGPoint?

    init(
        image: Attribute<ImageViewChild.Value>,
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        time: Attribute<Time>
    ) {
        self.image = image
        self.position = position
        self.size = size
        self.time = time
    }

    mutating func updateValue() {
        var presentation = image.value
        let needsPresentationTime =
            presentation.drawPresentationStart != nil ||
            presentation.symbolAnimator?.isAnimating == true
        let now = needsPresentationTime ? time.value : .zero
        presentation.drawPresentationStart?.activate(at: now)
        if let symbolAnimator = presentation.symbolAnimator,
           symbolAnimator.isAnimating,
           var image = presentation.image {
            image.symbolReplacementPresentation =
                symbolAnimator.presentation(at: now)
            presentation.image = image
            if symbolAnimator.isAnimating,
               let ref = _AGGraphContext.current,
               let viewGraph = ref.context as? ViewGraph {
                viewGraph.nextUpdate.views.at(now + 1.0 / 120.0)
            }
        }
        let targetPosition = presentation.image == nil ? nil : position.value
        let displaySize = presentation.image == nil ? nil : size.value
        let displayPosition: CGPoint?

        if let targetPosition {
            if presentation.retainsDrawHidePosition {
                if retainedDrawHidePosition == nil {
                    retainedDrawHidePosition =
                        previousTargetPosition ?? targetPosition
                }
                displayPosition = retainedDrawHidePosition ?? targetPosition
            } else {
                retainedDrawHidePosition = nil
                displayPosition = targetPosition
            }
            previousTargetPosition = targetPosition
        } else {
            retainedDrawHidePosition = nil
            previousTargetPosition = nil
            displayPosition = nil
        }

        presentation.displayPosition = displayPosition
        presentation.displaySize = displaySize
        _AGGraph.setStatefulOutput(presentation)
    }
}

private struct ResolvedImageContentView: ShapeStyledLeafView {
    struct UpdateData {
        var _time: Attribute<Time>
        var _position: Attribute<CGPoint>
        var _size: Attribute<ViewSize>
        var _pixelLength: Attribute<CGFloat>
        var needsPrepare: Bool
    }

    var presentation: ImageViewChild.Value
    var referencePosition: CGPoint
    var styleResolverMode: _ShapeStyle_ResolverMode

    static var animatesSize: Bool { false }
    static var hasBackground: Bool { true }

    func mustUpdate(
        data: UpdateData,
        position: Attribute<CGPoint>,
        environment: Attribute<EnvironmentValues>
    ) -> Bool {
        false
    }

    func shape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        let frame = CGRect(
            origin: presentation.displayPosition.map {
                CGPoint(
                    x: $0.x - referencePosition.x,
                    y: $0.y - referencePosition.y
                )
            } ?? .zero,
            size: presentation.displaySize?.value ?? size
        )
        guard var image = presentation.image else {
            return (.empty, frame)
        }
        image.symbolLayerOpacities = presentation.symbolLayerOpacities
        image.symbolVariableColorOpacities =
            presentation.symbolVariableColorOpacities
        image.symbolDrawPathIntervals = presentation.symbolDrawPathIntervals
        image.symbolDrawProgresses = presentation.symbolDrawProgresses
        image.symbolDrawFallbackProgresses =
            presentation.symbolDrawFallbackProgresses
        image.symbolDrawFallbackOpacity =
            presentation.symbolDrawFallbackOpacity
        image.symbolDrawsReversed = presentation.symbolDrawsReversed
        return (
            .image(
                image,
                opacity: presentation.isSymbolEffectActive
                    ? presentation.symbolOpacity
                    : 1
            ),
            frame
        )
    }

    func backgroundShape(
        in size: CGSize
    ) -> (shape: _ShapeStyle_RenderedShape.Shape, frame: CGRect) {
        (.empty, CGRect(origin: .zero, size: size))
    }

    func isClear(styles: _ShapeStyle_Pack) -> Bool {
        presentation.image == nil
    }

    static func resolverMode(
        for image: ImageDrawing?
    ) -> _ShapeStyle_ResolverMode {
        guard let symbol = image?.symbol else {
            return _ShapeStyle_ResolverMode()
        }
        let foregroundLevels = UInt16(clamping:
            (symbol.layers.map(\.semanticLevel).max() ?? 0) + 1
        )
        return _ShapeStyle_ResolverMode(
            foregroundLevels: foregroundLevels,
            options: foregroundLevels > 1 ? .foregroundPalette : []
        )
    }
}

fileprivate struct DrawRequest: Equatable {
    var id: Int
    var targetProgress: Double
    var effectiveSpeed: Double
    var layerBehavior: DrawLayerBehavior
    var isReversed: Bool
    var isTransition: Bool

    func matchesTransition(_ other: DrawRequest) -> Bool {
        id == other.id &&
            effectiveSpeed == other.effectiveSpeed &&
            layerBehavior == other.layerBehavior &&
            isReversed == other.isReversed &&
            isTransition && other.isTransition
    }
}

private func drawRequest(
    in effects: [IdentifiedSymbolEffect]
) -> DrawRequest? {
    for identified in effects.reversed() {
        let layerBehavior: DrawLayerBehavior
        let isReversed: Bool
        switch identified.effect.configuration.effect {
        case let .drawOn(configuration):
            layerBehavior = configuration.layerBehavior ?? .byLayer
            isReversed = false
        case let .drawOff(configuration):
            layerBehavior = configuration.layerBehavior ?? .byLayer
            isReversed = configuration.isReversed == true
        default:
            continue
        }

        let targetProgress: Double
        let isTransition: Bool
        switch identified.effect.trigger {
        case .indefinite:
            targetProgress = 0
            isTransition = false
        case let .transition(phase):
            targetProgress = phase.isIdentity ? 1 : 0
            isTransition = true
        case .value, .condition:
            continue
        }
        let speed = identified.effect.options.speed
        guard speed.isFinite else { continue }
        return DrawRequest(
            id: identified.id,
            targetProgress: targetProgress,
            effectiveSpeed: min(max(speed, 0.5), 2),
            layerBehavior: layerBehavior,
            isReversed: isReversed,
            isTransition: isTransition
        )
    }
    return nil
}

private func updatedDrawAnimation(
    previous: [IdentifiedSymbolEffect],
    next: [IdentifiedSymbolEffect],
    current: ImageViewChild.ActiveDraw?,
    presentation: ImageViewChild.DrawPresentation,
    symbol: ResolvedVectorSymbol,
    hasResolvedEffects: Bool,
    transaction: Transaction,
    at time: Time
) -> ImageViewChild.ActiveDraw? {
    let previousRequest = drawRequest(in: previous)
    let nextRequest = drawRequest(in: next)
    guard previousRequest != nextRequest else { return current }

    let initialProgresses = presentation.progresses ??
        presentation.fallbackOpacity.map { [$0] }
    let initialFallbackProgresses = presentation.fallbackProgresses ??
        presentation.fallbackOpacity.map { [$0] }
    let request: DrawRequest
    if let nextRequest {
        request = nextRequest
    } else if var previousRequest {
        previousRequest.targetProgress = 1
        request = previousRequest
    } else {
        return current
    }

    if var current,
       canAppendOrdinaryDrawWave(
        previous: previous,
        next: next,
        current: current
       ) {
        let canonicalStart = request.targetProgress >= 1 ? 0.0 : 1.0
        var continuation = drawLeg(
            for: request,
            symbol: symbol,
            initialProgresses: [Double](
                repeating: canonicalStart,
                count: current.primary.motionGroupTimings.count
            ),
            initialFallbackProgresses: [Double](
                repeating: canonicalStart,
                count: current.primary.motionGroupTimings.count
            ),
            transaction: transaction
        )
        let priorLegs = [(
            start: current.presentationStart.time ?? time,
            leg: current.primary
        )] + current.continuations.map {
            (
                start: $0.presentationStart.time ?? time,
                leg: $0.leg
            )
        }
        for index in continuation.opacityStartOffsets.indices {
            var completionTime = time.seconds
            for prior in priorLegs {
                guard prior.leg.motionGroupTimings.indices.contains(index),
                      let duration = prior.leg
                        .motionGroupTimings[index].opacityDuration else {
                    continue
                }
                let distance = abs(
                    prior.leg.targetProgress -
                        prior.leg.initialFallbackProgresses[index]
                )
                completionTime = max(
                    completionTime,
                    prior.start.seconds +
                        (
                            prior.leg.opacityStartOffsets[index] +
                                duration * distance
                        ) / prior.leg.effectiveSpeed
                )
            }
            let requiredOffset = max(
                completionTime - time.seconds,
                0
            ) * continuation.effectiveSpeed
            continuation.opacityStartOffsets[index] = max(
                continuation.opacityStartOffsets[index],
                requiredOffset
            )
        }
        let continuationStart = ImageViewChild.PresentationStart()
        current.presentationStart.append(continuationStart)
        current.continuations.append(ImageViewChild.DrawContinuation(
            presentationStart: continuationStart,
            leg: continuation
        ))
        current.isComplete = false
        return current
    }

    return drawAnimation(
        for: request,
        symbol: symbol,
        initialPathIntervals: presentation.pathIntervals,
        initialProgresses: initialProgresses,
        initialFallbackProgresses: initialFallbackProgresses,
        initialProgressesReversed: presentation.isReversed,
        transaction: transaction,
        immediate: request.isTransition && !hasResolvedEffects
    )
}

private func drawAnimation(
    for request: DrawRequest,
    symbol: ResolvedVectorSymbol,
    initialPathIntervals:
        [[ResolvedVectorSymbol.DrawPathInterval]]? = nil,
    initialProgresses: [Double]?,
    initialFallbackProgresses: [Double]? = nil,
    initialProgressesReversed: Bool? = nil,
    transaction: Transaction,
    immediate: Bool = false
) -> ImageViewChild.ActiveDraw {
    let usesOpacityFallback = symbol.drawMotionGroupCount == 0
    let pathComposition = !request.isReversed &&
        symbol.layers.contains {
            guard let draw = $0.draw else { return false }
            return !draw.guides.isEmpty
        }
    let timingCount = max(symbol.drawMotionGroupCount, 1)
    let pathBaseIntervals:
        [[ResolvedVectorSymbol.DrawPathInterval]]?
    if pathComposition {
        if let initialPathIntervals,
           initialPathIntervals.count == timingCount {
            pathBaseIntervals = initialPathIntervals
        } else if let initialProgresses,
                  initialProgresses.count == timingCount {
            let reversed = initialProgressesReversed ??
                (request.isReversed || request.targetProgress >= 1)
            pathBaseIntervals = initialProgresses.map { progress in
                let progress = min(max(progress, 0), 1)
                guard progress > 0 else { return [] }
                return [ResolvedVectorSymbol.DrawPathInterval(
                    from: reversed ? 1 - progress : 0,
                    to: reversed ? 1 : progress
                )]
            }
        } else {
            pathBaseIntervals = Array(
                repeating: [
                    ResolvedVectorSymbol.DrawPathInterval(from: 0, to: 1)
                ],
                count: timingCount
            )
        }
    } else {
        pathBaseIntervals = nil
    }
    let fallbackBaseProgresses = initialFallbackProgresses.flatMap {
        $0.count == timingCount ? $0 : nil
    } ?? initialProgresses.flatMap {
        $0.count == timingCount ? $0 : nil
    } ?? [Double](repeating: 1, count: timingCount)
    let legInitialProgresses: [Double]?
    if pathComposition {
        if initialPathIntervals == nil,
           initialProgresses == nil,
           request.targetProgress >= 1 {
            legInitialProgresses = [Double](
                repeating: 1,
                count: timingCount
            )
        } else {
            legInitialProgresses = [Double](
                repeating: request.targetProgress >= 1 ? 0 : 1,
                count: timingCount
            )
        }
    } else {
        legInitialProgresses = initialProgresses
    }
    let leg = drawLeg(
        for: request,
        symbol: symbol,
        initialProgresses: legInitialProgresses,
        initialFallbackProgresses: fallbackBaseProgresses,
        transaction: transaction,
        immediate: immediate
    )
    return ImageViewChild.ActiveDraw(
        id: request.id,
        presentationStart: ImageViewChild.PresentationStart(),
        primary: leg,
        continuations: [],
        pathBaseIntervals: pathBaseIntervals,
        fallbackBaseProgresses: fallbackBaseProgresses,
        layerBehavior: request.layerBehavior,
        configuredReversed: request.isReversed,
        usesOpacityFallback: usesOpacityFallback
    )
}

private func drawLeg(
    for request: DrawRequest,
    symbol: ResolvedVectorSymbol,
    initialProgresses: [Double]?,
    initialFallbackProgresses: [Double]?,
    transaction: Transaction,
    immediate: Bool = false
) -> ImageViewChild.DrawLeg {
    let appearing = request.targetProgress >= 1
    var timings = symbol.drawMotionGroupTimings(appearing: appearing)
    if timings.isEmpty {
        timings = [ResolvedVectorSymbol.DrawMotionGroupTiming(
            pathDuration: nil,
            opacityDuration: appearing ? 1.0 / 4.0 : 1.0 / 6.0
        )]
    }
    let initial = immediate
        ? [Double](repeating: request.targetProgress, count: timings.count)
        : initialProgresses.flatMap {
            $0.count == timings.count ? $0 : nil
        } ?? [Double](repeating: 1, count: timings.count)
    let initialFallback = immediate
        ? [Double](repeating: request.targetProgress, count: timings.count)
        : initialFallbackProgresses.flatMap {
            $0.count == timings.count ? $0 : nil
        } ?? initial
    let offsets = drawMotionGroupStartOffsets(
        timings: timings,
        initialProgresses: zip(initial, initialFallback).map {
            min($0.0, $0.1)
        },
        targetProgress: request.targetProgress,
        layerBehavior: request.layerBehavior,
        reversesGroupOrder: request.isReversed && !appearing,
        appearing: appearing
    )
    let hasMotion = timings.indices.contains { index in
        timings[index].duration * max(
            abs(request.targetProgress - initial[index]),
            abs(request.targetProgress - initialFallback[index])
        ) > .ulpOfOne
    }
    let completionTokens = hasMotion
        ? drawCompletionTokens(for: transaction)
        : []
    completionTokens.forEach { $0.start() }
    return ImageViewChild.DrawLeg(
        motionGroupTimings: timings,
        pathStartOffsets: offsets,
        opacityStartOffsets: offsets,
        initialProgresses: initial,
        initialFallbackProgresses: initialFallback,
        targetProgress: request.targetProgress,
        effectiveSpeed: request.effectiveSpeed,
        isReversed: request.isReversed || appearing,
        completionTokens: completionTokens
    )
}

private func drawMotionGroupStartOffsets(
    timings: [ResolvedVectorSymbol.DrawMotionGroupTiming],
    initialProgresses: [Double],
    targetProgress: Double,
    layerBehavior: DrawLayerBehavior,
    reversesGroupOrder: Bool,
    appearing: Bool
) -> [Double] {
    var offsets = [Double](repeating: 0, count: timings.count)
    let forwardOrder = Array(timings.indices)
    let order = reversesGroupOrder
        ? Array(forwardOrder.reversed())
        : forwardOrder
    guard order.count > 1 else { return offsets }

    switch layerBehavior {
    case .wholeSymbol:
        break
    case .byLayer:
        let overlap = appearing ? 0.18 : 0.38
        for pair in zip(order, order.dropFirst()) {
            let previousDuration = timings[pair.0].duration *
                abs(targetProgress - initialProgresses[pair.0])
            offsets[pair.1] = offsets[pair.0] +
                previousDuration * overlap
        }
    case .individually:
        for pair in zip(order, order.dropFirst()) {
            let previousDuration = timings[pair.0].duration *
                abs(targetProgress - initialProgresses[pair.0])
            offsets[pair.1] = offsets[pair.0] + previousDuration
        }
    }
    return offsets
}

private func canAppendOrdinaryDrawWave(
    previous: [IdentifiedSymbolEffect],
    next: [IdentifiedSymbolEffect],
    current: ImageViewChild.ActiveDraw?
) -> Bool {
    guard let current,
          current.pathBaseIntervals != nil,
          !current.configuredReversed,
          let previousRequest = drawRequest(in: previous) ??
            drawRequest(in: next) else {
        return false
    }
    var request: DrawRequest
    if let nextRequest = drawRequest(in: next) {
        request = nextRequest
    } else {
        request = previousRequest
        request.targetProgress = 1
    }
    return request.targetProgress != current.targetProgress &&
        !request.isReversed &&
        request.id == current.id &&
        request.effectiveSpeed == current.primary.effectiveSpeed &&
        request.layerBehavior == current.layerBehavior
}

private func drawCompletionTokens(
    for transaction: Transaction
) -> [AnimationCompletionToken] {
    var tokens: [AnimationCompletionToken] = []
    if let listener = transaction.animationListener {
        tokens.append(AnimationCompletionToken(listener: listener))
    }
    if let listener = transaction.animationLogicalListener {
        tokens.append(AnimationCompletionToken(listener: listener))
    }
    return tokens
}

private func finishDrawCompletionTokens(
    _ tokens: [AnimationCompletionToken]
) {
    tokens.forEach { $0.finish() }
}

private func drawEase(_ value: Double) -> Double {
    let progress = min(max(value, 0), 1)
    return (1 - cos(progress * .pi)) * 0.5
}

private func drawMix(
    _ from: Double,
    _ to: Double,
    progress: Double
) -> Double {
    from + (to - from) * progress
}

func applyingDrawPathWave(
    to intervals: [ResolvedVectorSymbol.DrawPathInterval],
    frontProgress: Double,
    makesVisible: Bool
) -> [ResolvedVectorSymbol.DrawPathInterval] {
    // Ordinary retargets do not reverse an earlier wave. Apply each wave in
    // trigger order so independently moving erase and restore fronts lower to
    // the exact visible path intervals for this frame.
    let boundary = 1 - min(max(frontProgress, 0), 1)
    var result: [ResolvedVectorSymbol.DrawPathInterval] = []
    result.reserveCapacity(intervals.count + (makesVisible ? 1 : 0))
    for interval in intervals {
        guard interval.from < boundary else { continue }
        let upperBound = min(interval.to, boundary)
        guard upperBound > interval.from else { continue }
        result.append(
            ResolvedVectorSymbol.DrawPathInterval(
                from: interval.from,
                to: upperBound
            )
        )
    }
    guard makesVisible, boundary < 1 else { return result }
    if let lastIndex = result.indices.last,
       result[lastIndex].to >= boundary - 0.000_000_001 {
        result[lastIndex].to = 1
    } else {
        result.append(
            ResolvedVectorSymbol.DrawPathInterval(
                from: boundary,
                to: 1
            )
        )
    }
    return result
}

private func canAppendPulse(
    active: ImageViewChild.ActivePulse,
    activation: ImageViewChild.ActivePulse,
    previous: [IdentifiedSymbolEffect],
    next: [IdentifiedSymbolEffect]
) -> Bool {
    guard active.id == activation.id,
          !active.finishesAfterEffectRemoval,
          active.cycleDuration == activation.cycleDuration,
          active.repeatDelay == activation.repeatDelay,
          active.cycleCount != nil,
          activation.cycleCount != nil,
          let old = previous.first(where: { $0.id == active.id }),
          let new = next.first(where: { $0.id == active.id }),
          old.effect.configuration == new.effect.configuration,
          old.effect.options == .nonRepeating,
          new.effect.options == .nonRepeating,
          case .value = old.effect.trigger,
          case .value = new.effect.trigger else {
        return false
    }
    return true
}

private func pulseFinishingCurrentCycle(
    _ active: ImageViewChild.ActivePulse,
    removedEffect: IdentifiedSymbolEffect,
    at time: Time
) -> ImageViewChild.ActivePulse? {
    guard active.cycleCount == nil,
          removedEffect.effect.options == .default,
          case .indefinite = removedEffect.effect.trigger else {
        return nil
    }
    let elapsed = max(time.seconds - active.startTime.seconds, 0)
    let cycleStride = active.cycleDuration + active.repeatDelay
    var finishing = active
    finishing.cycleCount = max(Int(ceil(elapsed / cycleStride)), 1)
    finishing.finishesAfterEffectRemoval = true
    return finishing
}

private func activatedPulse(
    previous: [IdentifiedSymbolEffect],
    next: [IdentifiedSymbolEffect],
    hasResolvedEffects: Bool,
    at time: Time
) -> ImageViewChild.ActivePulse? {
    for identified in next.reversed() {
        guard case let .pulse(configuration) = identified.effect.configuration.effect else {
            continue
        }
        let options = identified.effect.options
        guard options.speed.isFinite,
              options.repeatDelay?.isFinite != false else {
            continue
        }
        let effectiveSpeed = max(options.speed, 0.5)

        let cycleCount: Int?
        let repeatDelay: Double
        switch identified.effect.trigger {
        case .indefinite:
            if options == .default {
                cycleCount = nil
                repeatDelay = 0
            } else {
                guard options.speed == 1,
                      options.repeat == .indefinite,
                      options.prefersContinuous,
                      options.repeatDelay == nil,
                      previous.first(where: { $0.id == identified.id }) == nil else {
                    continue
                }
                cycleCount = nil
                repeatDelay = 0
            }
            guard previous.first(where: { $0.id == identified.id }) == nil else {
                continue
            }
        case let .value(trigger):
            guard !options.prefersContinuous,
                  hasResolvedEffects,
                  let old = previous.first(where: { $0.id == identified.id }),
                  case let .value(oldTrigger) = old.effect.trigger,
                  !trigger.isEqual(to: oldTrigger) else {
                continue
            }
            switch options.repeat {
            case nil:
                guard options.repeatDelay == nil else { continue }
                cycleCount = 1
                repeatDelay = 0
            case let .count(count) where count > 0:
                let delay = options.repeatDelay ?? 0
                guard delay >= 0 else { continue }
                cycleCount = count
                repeatDelay = delay
            default:
                continue
            }
        case .condition, .transition:
            continue
        }
        return ImageViewChild.ActivePulse(
            id: identified.id,
            startTime: time,
            cycleDuration: 2.0 / effectiveSpeed,
            cycleCount: cycleCount,
            repeatDelay: repeatDelay,
            isLayered: configuration.isLayered != false
        )
    }
    return nil
}

private func variableColorFinishingCurrentCycle(
    _ active: ImageViewChild.ActiveVariableColor,
    removedEffect: IdentifiedSymbolEffect,
    at time: Time
) -> ImageViewChild.ActiveVariableColor? {
    guard active.cycleCount == nil,
          removedEffect.effect.options == .default,
          case .indefinite = removedEffect.effect.trigger else {
        return nil
    }
    let elapsed = max(time.seconds - active.startTime.seconds, 0) *
        active.effectiveSpeed
    var finishing = active
    if elapsed < ImageViewChild.ActiveVariableColor.introDuration {
        finishing.cycleCount = 1
    } else {
        let localElapsed = elapsed -
            ImageViewChild.ActiveVariableColor.introDuration
        finishing.cycleCount = max(
            Int(floor(localElapsed / active.localDuration)) + 1,
            1
        )
    }
    finishing.finishesAfterEffectRemoval = true
    return finishing
}

private func activatedVariableColor(
    previous: [IdentifiedSymbolEffect],
    next: [IdentifiedSymbolEffect],
    hasResolvedEffects: Bool,
    groupCount: Int,
    initialOpacities: [Double]?,
    at time: Time
) -> ImageViewChild.ActiveVariableColor? {
    guard groupCount > 0 else { return nil }
    for identified in next.reversed() {
        guard case let .variableColor(configuration) =
                identified.effect.configuration.effect else {
            continue
        }
        let options = identified.effect.options
        guard options.speed.isFinite,
              options.repeatDelay?.isFinite != false else {
            continue
        }

        let cycleCount: Int?
        switch identified.effect.trigger {
        case .indefinite:
            if options == .default {
                cycleCount = nil
            } else {
                guard options.speed == 1,
                      options.repeat == .indefinite,
                      options.prefersContinuous,
                      options.repeatDelay == nil else {
                    continue
                }
                cycleCount = nil
            }
            guard previous.first(where: { $0.id == identified.id }) == nil else {
                continue
            }
        case let .value(trigger):
            guard !options.prefersContinuous,
                  hasResolvedEffects,
                  let old = previous.first(where: { $0.id == identified.id }),
                  case let .value(oldTrigger) = old.effect.trigger,
                  !trigger.isEqual(to: oldTrigger),
                  options.repeatDelay == nil || options.repeatDelay == 0 else {
                continue
            }
            switch options.repeat {
            case nil:
                cycleCount = 1
            case let .count(count) where count > 0:
                cycleCount = count
            default:
                continue
            }
        case .condition, .transition:
            continue
        }

        let startingOpacities = initialOpacities.flatMap {
            $0.count == groupCount ? $0 : nil
        } ?? [Double](repeating: 1, count: groupCount)
        return ImageViewChild.ActiveVariableColor(
            id: identified.id,
            startTime: time,
            groupCount: groupCount,
            cycleCount: cycleCount,
            effectiveSpeed: min(max(options.speed, 0.5), 2),
            isReversing: configuration.isReversing == true,
            isIterative: configuration.isIterative == true,
            inactiveOpacity: configuration.hasReveal == true ? 0 : 0.3,
            initialOpacities: startingOpacities
        )
    }
    return nil
}

private func variableColorEase(_ value: Double) -> Double {
    let progress = min(max(value, 0), 1)
    return (1 - cos(progress * .pi)) * 0.5
}

private func variableColorMix(
    _ from: Double,
    _ to: Double,
    progress: Double
) -> Double {
    from + (to - from) * progress
}

private func symbolEffectListsEqual(
    _ lhs: [IdentifiedSymbolEffect],
    _ rhs: [IdentifiedSymbolEffect]
) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return zip(lhs, rhs).allSatisfy(symbolEffectsEqual)
}

private func symbolEffectsEqual(
    _ lhs: IdentifiedSymbolEffect,
    _ rhs: IdentifiedSymbolEffect
) -> Bool {
    lhs.id == rhs.id &&
        lhs.effect.configuration == rhs.effect.configuration &&
        lhs.effect.options == rhs.effect.options &&
        symbolEffectTriggersEqual(lhs.effect.trigger, rhs.effect.trigger)
}

private func symbolEffectTriggersEqual(
    _ lhs: ResolvedSymbolEffect.Trigger,
    _ rhs: ResolvedSymbolEffect.Trigger
) -> Bool {
    switch (lhs, rhs) {
    case (.indefinite, .indefinite):
        return true
    case let (.value(lhs), .value(rhs)):
        return lhs.isEqual(to: rhs)
    case let (.condition(lhs), .condition(rhs)):
        return lhs == rhs
    case let (.transition(lhs), .transition(rhs)):
        return lhs == rhs
    default:
        return false
    }
}

public struct Image: Equatable, Sendable {
    var provider: AnyImageProviderBox

    init(provider: AnyImageProviderBox) {
        self.provider = provider
    }

    public init(size: CGSize, label: Text? = nil, opaque: Bool = false, colorMode: ColorRenderingMode = .nonLinear, renderer: @escaping (inout GraphicsContext) -> Void) {
        self.provider = RenderedImageProviderBox(size: size,
                                                 label: label,
                                                 opaque: opaque,
                                                 colorMode: colorMode,
                                                 renderer: renderer)
    }

    public init(_ name: String, bundle: Bundle? = nil) {
        self.provider = NamedImageProvider(name: name, value: nil, location: bundle, label: nil)
    }

    public init(_ name: String, bundle: Bundle? = nil, label: Text) {
        self.provider = NamedImageProvider(name: name, value: nil, location: bundle, label: label)
    }

    public static func == (lhs: Image, rhs: Image) -> Bool {
        lhs.provider.isEqual(to: rhs.provider)
    }
}

final class _ImageResourceResolutionState {
    private var pendingImage: Image?
    private var pendingTransaction = Transaction()

    func transaction(for image: Image, candidate: Transaction) -> Transaction {
        guard pendingImage != image else {
            return pendingTransaction
        }
        pendingImage = image
        pendingTransaction = candidate
        return candidate
    }

    func didResolve(image: Image) {
        guard pendingImage == image else { return }
        pendingImage = nil
        pendingTransaction = Transaction()
    }
}

extension Image {
    struct ResizingInfo: Equatable {
        var capInsets: EdgeInsets
        var mode: ResizingMode
    }

    public enum Interpolation: Hashable, Sendable {
        case none
        case low
        case medium
        case high
    }
}


extension Image {
    public enum ResizingMode: Hashable, Sendable {
        case tile
        case stretch
    }

    public func resizable(
        capInsets: EdgeInsets = EdgeInsets(),
        resizingMode: ResizingMode = .stretch
    ) -> Image {
        Image(provider: ResizableProvider(
            base: self,
            capInsets: capInsets,
            resizingMode: resizingMode
        ))
    }
}

extension Image {
    public struct DynamicRange: Hashable, Sendable {
        enum Storage: UInt8, Hashable, Sendable {
            case standard
            case constrainedHigh
            case high
        }

        var storage: Storage

        init(_ storage: Storage) {
            self.storage = storage
        }

        public static let standard = DynamicRange(.standard)
        public static let constrainedHigh = DynamicRange(.constrainedHigh)
        public static let high = DynamicRange(.high)
    }
}

extension EnvironmentValues {
    private struct AllowedDynamicRangeKey: EnvironmentKey {
        static let defaultValue: Image.DynamicRange? = nil
    }

    struct MaxAllowedDynamicRangeKey: EnvironmentKey {
        static let defaultValue: Image.DynamicRange? = nil
    }

    public var allowedDynamicRange: Image.DynamicRange? {
        get { self[AllowedDynamicRangeKey.self] }
        set { self[AllowedDynamicRangeKey.self] = newValue }
    }

    var maxAllowedDynamicRange: Image.DynamicRange? {
        get { self[MaxAllowedDynamicRangeKey.self] }
        set { self[MaxAllowedDynamicRangeKey.self] = newValue }
    }

    func effectiveAllowedDynamicRange(
        hdrContent: Bool,
        explicitRange: Image.DynamicRange?
    ) -> Image.DynamicRange {
        guard hdrContent else {
            return .standard
        }
        return effectiveAllowedDynamicRange(explicitRange: explicitRange)
    }

    func effectiveAllowedDynamicRange(
        explicitRange: Image.DynamicRange?
    ) -> Image.DynamicRange {
        let requested = explicitRange ?? allowedDynamicRange ?? .high
        guard requested != .standard else {
            return .standard
        }
        guard let maximum = maxAllowedDynamicRange else {
            return requested
        }
        return requested.storage.rawValue < maximum.storage.rawValue
            ? requested
            : maximum
    }
}

extension View {
    @inlinable nonisolated
    public func allowedDynamicRange(
        _ range: Image.DynamicRange?
    ) -> some View {
        environment(\.allowedDynamicRange, range)
    }
}

extension Image {
    public enum Orientation: UInt8, CaseIterable, Hashable {
        case up
        case upMirrored
        case down
        case downMirrored
        case left
        case leftMirrored
        case right
        case rightMirrored
    }
}

extension Image {
    public init(_ texture: Texture, scale: CGFloat, orientation: Image.Orientation = .up, label: Text) {
        self.provider = TextureImageProvider(texture: texture, scale: scale, orientation: orientation, label: label)
    }
    public init(decorative texture: Texture, scale: CGFloat, orientation: Image.Orientation = .up) {
        self.provider = TextureImageProvider(texture: texture, scale: scale, orientation: orientation, label: nil)
    }
}

extension Image {
    public init(systemName: String) {
        self.provider = SymbolImageProvider(name: systemName, variableValue: nil, bundle: nil, label: nil)
    }
    public init(systemName: String, variableValue: Double?) {
        self.provider = SymbolImageProvider(name: systemName, variableValue: variableValue, bundle: nil, label: nil)
    }
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.provider = SymbolImageProvider(name: name, variableValue: variableValue, bundle: bundle, label: nil)
    }
    public init(_ name: String, variableValue: Double?, bundle: Bundle? = nil, label: Text) {
        self.provider = SymbolImageProvider(name: name, variableValue: variableValue, bundle: bundle, label: label)
    }
    public init(decorative name: String, variableValue: Double?, bundle: Bundle? = nil) {
        self.provider = SymbolImageProvider(name: name, variableValue: variableValue, bundle: bundle, label: nil)
    }
}

extension Image {
    public init(svg: SVG) {
        self.provider = SVGImageProvider(svg: svg, label: nil)
    }

    public init(svg: SVG, label: Text) {
        self.provider = SVGImageProvider(svg: svg, label: label)
    }

    public init(decorative svg: SVG) {
        self.provider = SVGImageProvider(svg: svg, label: nil)
    }
}

extension Image: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        // Backend-only image contents are published by the resource pass.
        // Portable vector contents resolve in ImageViewChild with the source image.
        let resolvedImageAttr = graph.makeInput(value: ImageDrawing?.none)
        let resolvedSourceAttr = graph.makeInput(value: Image?.none)
        let resolvedImageTransactionAttr = graph.makeInput(value: Transaction())
        let resourceResolutionState = _ImageResourceResolutionState()
        let inheritedTransactionAttr = inputs.base.transaction

        let inbox = graph.inbox
        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let sizeAttr = cachedEnvironment.animatedSize(for: inputs)
        let positionAttr = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment
        let envAttr = inputs.base.cachedEnvironment.value.environment

        // 2. Resource pass (Resource Rule)
        // Evaluated before drawing (in updateView) to upload the image texture to the GPU.
        let resourceAttr: Attribute<ResourceList> = graph.makeRule {
            let image = view._attribute.value // Dependency: image provider changes

            if !image.provider.requiresBackendResolution {
                resourceResolutionState.didResolve(image: image)
                return ResourceList()
            }

            // Optimization (Cache Hit): Return an empty list if the image is already cached.
            // Note: For a robust implementation, you might want to compare an image "version"
            // or use a caching mechanism within the ImageProvider.
            if resolvedSourceAttr.value == image, resolvedImageAttr.value != nil {
                resourceResolutionState.didResolve(image: image)
                return ResourceList()
            }

            let contextualTransaction = _AGGraph.currentRuleContextAttribute
                .flatMap { graph.transaction(for: $0) } ?? Transaction()
            let sourceTransaction = graph.transaction(
                for: view._attribute.identifier
            ) ?? Transaction()
            let inheritedTransaction = inheritedTransactionAttr.value
            let mutationTransaction = contextualTransaction.isEmpty
                ? sourceTransaction
                : contextualTransaction
            let candidateTransaction = mutationTransaction.isEmpty
                ? inheritedTransaction
                : mutationTransaction
            let resourceTransaction = resourceResolutionState.transaction(
                for: image,
                candidate: candidateTransaction
            )

            // If loading is required, create a new ResourceList(Task) to propagate upwards.
            let environment = envAttr.value
            let bundle = environment.resourceBundle  // Register AG dependency and capture for closure.
            let renderEnvironment = environment.untrackedCopy()
            var list = ResourceList()

            list.items.append(ResourceList.Task(transaction: resourceTransaction) { context in
                var context = context
                context.copyOnWrite()
                context.environment = renderEnvironment
                AnyImageProviderBox.$_preferredBundle.withValue(bundle) {
                    // 1. [Synchronous Loading] Resolve the image (loads data and creates texture).
                    let resolved = context.resolveImageDrawing(image)
                    let boxedResolved = UnsafeSendableBox(resolved)
                    let boxedTransaction = UnsafeSendableBox(resourceTransaction)

                    // 2. [State Invalidation] Notify completion and trigger a layout recomputation.
                    let publish: @Sendable () -> Void = {
                        resolvedImageTransactionAttr.setValue(boxedTransaction.value)
                        resolvedSourceAttr.setValue(
                            image,
                            transaction: boxedTransaction.value
                        )
                        resolvedImageAttr.setValue(
                            boxedResolved.value,
                            transaction: boxedTransaction.value
                        )
                    }
                    if _AGGraph.current === graph {
                        publish()
                    } else {
                        inbox.enqueue(transaction: resourceTransaction, publish)
                    }
                } // withValue
            })

            return list
        }

        let imageViewChildAttr: Attribute<ImageViewChild.Value> = graph.makeStatefulRule(
            ImageViewChild(
                view: view._attribute,
                backendSource: resolvedSourceAttr,
                backendImage: resolvedImageAttr,
                environment: envAttr,
                transaction: inputs.base.transaction,
                time: inputs.base.time
            )
        )
        // Consume image effects before the transaction advances to its next
        // phase, even when layout and display outputs have not been read yet.
        imageViewChildAttr.flags = .transactional
        let intrinsicImageAttr = graph.subscriptNode(
            parent: imageViewChildAttr,
            keyPath: \ImageViewChild.Value.image
        )
        let imagePresentationAttr: Attribute<ImageViewChild.Value> =
            graph.makeStatefulRule(
                ImageViewPresentation(
                    image: imageViewChildAttr,
                    position: positionAttr,
                    size: sizeAttr,
                    time: inputs.base.time
                )
            )
        let transitionContentAttr: Attribute<ResolvedImageTransitionContent> = graph.makeRule {
            ResolvedImageTransitionContent(image: imageViewChildAttr.value.image)
        }
        let imageTransactionAttr: Attribute<Transaction> = graph.makeRule {
            let image = view._attribute.value
            if image.provider.requiresBackendResolution {
                return resolvedImageTransactionAttr.value
            }
            return inheritedTransactionAttr.value
        }

        // 3. Layout pass (Layout Rule)
        let lcAttr: OptionalAttribute<LayoutComputer>
        if inputs.requestsLayoutComputer {
            let layoutComputer: Attribute<LayoutComputer> = graph.makeStatefulRule(
                ResolvedImageLayoutComputer(_image: intrinsicImageAttr)
            )
            lcAttr = OptionalAttribute(layoutComputer)
        } else {
            lcAttr = OptionalAttribute()
        }

        let imageContentAttr: Attribute<ResolvedImageContentView> =
            graph.makeRule {
            let presentation = imagePresentationAttr.value
            return ResolvedImageContentView(
                presentation: presentation,
                referencePosition: positionAttr.value,
                styleResolverMode: ResolvedImageContentView.resolverMode(
                    for: presentation.image
                )
            )
        }
        let styleResolverModeAttr = graph.subscriptNode(
            parent: imageContentAttr,
            keyPath: \ResolvedImageContentView.styleResolverMode
        )
        var imageCachedEnvironment = cachedEnvironmentAttribute.value
        let styles = imageCachedEnvironment.resolvedShapeStyles(
            for: inputs,
            role: .fill,
            mode: styleResolverModeAttr
        )
        cachedEnvironmentAttribute.value = imageCachedEnvironment
        let pixelLengthAttr: Attribute<CGFloat> = graph.makeRule {
            envAttr.value.animationPixelLength
        }
        let interpolatorGroup = _ShapeStyle_InterpolatorGroup()
        var leafInputs = inputs
        leafInputs.containerPosition = positionAttr
        var outputs = ResolvedImageContentView.makeLeafView(
            view: _GraphValue(_attribute: imageContentAttr),
            inputs: leafInputs,
            styles: styles,
            interpolatorGroup: interpolatorGroup,
            data: ResolvedImageContentView.UpdateData(
                _time: inputs.base.time,
                _position: positionAttr,
                _size: sizeAttr,
                _pixelLength: pixelLengthAttr,
                needsPrepare: false
            )
        )

        outputs._layoutComputer = lcAttr

        // 4. Propagate backend resource work alongside the common leaf output.
        outputs.preferences.append(ResourceList.Key.self, node: resourceAttr.identifier)
        var interpolatorInputs = inputs
        interpolatorInputs.base.transaction = imageTransactionAttr
        outputs.applyInterpolatorGroup(
            interpolatorGroup,
            content: transitionContentAttr,
            inputs: interpolatorInputs,
            animatesSize: false,
            defersRender: false
        )
        if let representable = inputs.requestedImageRepresentation,
           representable.shouldMakeRepresentation(inputs: inputs) {
            let context: Attribute<PlatformImageRepresentableContext> =
                graph.makeRule {
                    let image = intrinsicImageAttr.value
                        ?? ImageDrawing(
                            baseline: 0,
                            shading: nil,
                            texture: nil,
                            textureTransform: .identity,
                            scaleFactor: 1
                        )
                    let environment = envAttr.value
                    return PlatformImageRepresentableContext(
                        image: image,
                        tintColor: nil,
                        foregroundStyle:
                            environment.currentForegroundStyle
                    )
                }
            representable.makeRepresentation(
                inputs: inputs,
                context: context,
                outputs: &outputs
            )
        }
        if let representable = inputs.requestedNamedImageRepresentation,
           representable.shouldMakeRepresentation(inputs: inputs) {
            let context: Attribute<PlatformNamedImageRepresentableContext> =
                graph.makeRule {
                    PlatformNamedImageRepresentableContext(
                        image: view._attribute.value,
                        environment: envAttr.value
                    )
                }
            representable.makeRepresentation(
                inputs: inputs,
                context: context,
                outputs: &outputs
            )
        }

        return outputs
    }

    public static func _makeViewList(
        view: _GraphValue<Self>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    public static func _viewListCount(inputs: _ViewListCountInputs) -> Int? {
        1
    }

    public typealias Body = Never
}

extension Image: PrimitiveView {
}

extension Image {
    static let _mainNamedBundle: Bundle? = .main
}
