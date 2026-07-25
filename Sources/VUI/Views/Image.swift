//
//  File: Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

class AnyImageProviderBox: @unchecked Sendable {
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
    let texture: Texture
    let scale: CGFloat
    let orientation: Image.Orientation
    let label: Text?

    init(texture: Texture, scale: CGFloat, orientation: Image.Orientation, label: Text?) {
        self.texture = texture
        self.scale = scale
        self.orientation = orientation
        self.label = label
    }

    override func makeTexture(_ context: GraphicsContext) -> Texture? {
        self.texture
    }

    override var scaleFactor: CGFloat {
        self.scale
    }

    override func isEqual(to: AnyImageProviderBox) -> Bool {
        if let other = to as? Self {
            return self.texture === other.texture &&
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

    override func makeSVG() -> SVG? {
        svg
    }

    override func isEqual(to other: AnyImageProviderBox) -> Bool {
        guard let other = other as? SVGImageProvider else { return false }
        return svg == other.svg && label == other.label
    }
}

// Image resolution is published asynchronously by the backend resource pass, while the
// display-list interpolation lane requires a stable non-optional content value. This adapter
// ignores the initial unresolved-to-resolved publication and delegates real image changes to
// the resolved-image transition contract.
private struct ResolvedImageTransitionContent: InterpolatableContent {
    var image: GraphicsContext.ResolvedImage?

    static var defaultTransition: ContentTransition {
        GraphicsContext.ResolvedImage.defaultTransition
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

struct ImageViewChild: StatefulRule, AsyncAttribute {
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

    struct ActiveDraw {
        var id: Int
        var startTime: Time
        var motionGroupDurations: [Double]
        var initialProgresses: [Double]
        var targetProgress: Double
        var effectiveSpeed: Double
        var layerBehavior: DrawLayerBehavior
        var isReversed: Bool
        var usesOpacityFallback: Bool
        // Symbol draw timing is renderer-owned, so these tokens keep transition
        // completion tied to the draw presentation instead of the outer curve.
        var completionTokens: [AnimationCompletionToken]
    }

    struct DrawPresentation {
        var progresses: [Double]?
        var fallbackOpacity: Double?
        var isReversed = false
        var isActive = false
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
        var image: GraphicsContext.ResolvedImage?
        var symbolEffects: [IdentifiedSymbolEffect]
        var symbolEffectVersion: UInt32
        var symbolOpacity: Double
        var symbolLayerOpacities: [Double]?
        var symbolVariableColorOpacities: [Double]?
        var symbolDrawProgresses: [Double]?
        var symbolDrawFallbackOpacity: Double?
        var symbolDrawsReversed: Bool
        var isSymbolEffectActive: Bool
        var retainsDrawHidePosition: Bool
        var displayPosition: CGPoint?
        var displaySize: ViewSize?
    }

    var resolvedImage: Attribute<GraphicsContext.ResolvedImage?>
    var environment: Attribute<EnvironmentValues>
    var transaction: Attribute<Transaction>
    var time: Attribute<Time>
    var position: Attribute<CGPoint>?
    var size: Attribute<ViewSize>?
    var phase = Phase()
    private var previousTargetPosition: CGPoint?
    private var retainedDrawHidePosition: CGPoint?

    init(
        resolvedImage: Attribute<GraphicsContext.ResolvedImage?>,
        environment: Attribute<EnvironmentValues>,
        transaction: Attribute<Transaction>,
        time: Attribute<Time>,
        position: Attribute<CGPoint>? = nil,
        size: Attribute<ViewSize>? = nil
    ) {
        self.resolvedImage = resolvedImage
        self.environment = environment
        self.transaction = transaction
        self.time = time
        self.position = position
        self.size = size
    }

    mutating func updateValue() {
        let image = resolvedImage.value
        let now = time.value
        let environmentEffects = environment.value.symbolEffects
        let transaction = transaction.value
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
                        at: now,
                        immediate: !shouldAnimateFromHidden
                    )
                } else {
                    if drawRequest(in: phase.effects) != nextDrawRequest {
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
                    at: now,
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
        let targetPosition = image == nil ? nil : position?.value
        let displaySize = image == nil ? nil : size?.value
        let displayPosition: CGPoint?
        if let targetPosition {
            // Draw-to-hidden keeps the symbol at its pre-update origin while
            // surrounding layout commits. Restore and other effects follow
            // the current layout position.
            if retainsDrawHidePosition {
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
        if isActive,
           let ref = _AGGraphContext.current,
           let viewGraph = ref.context as? ViewGraph {
            viewGraph.nextUpdate.views.at(now + 1.0 / 120.0)
        }

        _AGGraph.setStatefulOutput(Value(
            image: image,
            symbolEffects: phase.effects,
            symbolEffectVersion: phase.version,
            symbolOpacity: pulse.opacity,
            symbolLayerOpacities: pulse.layerOpacities,
            symbolVariableColorOpacities: variableColor.opacities,
            symbolDrawProgresses: draw.progresses,
            symbolDrawFallbackOpacity: draw.fallbackOpacity,
            symbolDrawsReversed: draw.isReversed,
            isSymbolEffectActive: isActive,
            retainsDrawHidePosition: retainsDrawHidePosition,
            displayPosition: displayPosition,
            displaySize: displaySize
        ))
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
        guard var active = phase.activeDraw,
              !active.completionTokens.isEmpty else {
            return
        }
        let tokens = active.completionTokens
        active.completionTokens.removeAll()
        phase.activeDraw = active
        enqueueAnimationCompletionActions(finishDrawCompletionTokens(tokens))
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
        let elapsed = max(time.seconds - active.startTime.seconds, 0) *
            active.effectiveSpeed
        var progresses = active.initialProgresses
        var isComplete = true

        func resolvedProgress(
            initial: Double,
            duration: Double,
            elapsed: Double
        ) -> Double {
            let distance = abs(active.targetProgress - initial)
            let scaledDuration = duration * distance
            guard scaledDuration > .ulpOfOne else {
                return active.targetProgress
            }
            let linearProgress = min(max(elapsed / scaledDuration, 0), 1)
            if linearProgress < 1 {
                isComplete = false
            }
            return drawMix(
                initial,
                active.targetProgress,
                progress: drawEase(linearProgress)
            )
        }

        switch active.layerBehavior {
        case .byLayer:
            for index in progresses.indices {
                progresses[index] = resolvedProgress(
                    initial: active.initialProgresses[index],
                    duration: active.motionGroupDurations[index],
                    elapsed: elapsed
                )
            }
        case .wholeSymbol:
            let duration = active.motionGroupDurations.max() ?? 0
            let distance = active.initialProgresses.map {
                abs(active.targetProgress - $0)
            }.max() ?? 0
            let scaledDuration = duration * distance
            let linearProgress = scaledDuration > .ulpOfOne
                ? min(max(elapsed / scaledDuration, 0), 1)
                : 1
            isComplete = linearProgress >= 1
            let easedProgress = drawEase(linearProgress)
            for index in progresses.indices {
                progresses[index] = drawMix(
                    active.initialProgresses[index],
                    active.targetProgress,
                    progress: easedProgress
                )
            }
        case .individually:
            let forwardOrder = Array(progresses.indices)
            let order = active.isReversed
                ? Array(forwardOrder.reversed())
                : forwardOrder
            var start = 0.0
            for index in order {
                let initial = active.initialProgresses[index]
                let duration = active.motionGroupDurations[index] *
                    abs(active.targetProgress - initial)
                if elapsed <= start {
                    progresses[index] = initial
                    if duration > .ulpOfOne {
                        isComplete = false
                    }
                } else if elapsed >= start + duration {
                    progresses[index] = active.targetProgress
                } else {
                    progresses[index] = drawMix(
                        initial,
                        active.targetProgress,
                        progress: drawEase((elapsed - start) / duration)
                    )
                    isComplete = false
                }
                start += duration
            }
        }

        if isComplete {
            let tokens = active.completionTokens
            active.completionTokens.removeAll()
            enqueueAnimationCompletionActions(finishDrawCompletionTokens(tokens))
            if active.targetProgress >= 1 {
                phase.activeDraw = nil
                return DrawPresentation()
            }
            phase.activeDraw = active
        }
        if active.usesOpacityFallback {
            return DrawPresentation(
                progresses: nil,
                fallbackOpacity: progresses.first ?? active.targetProgress,
                isReversed: active.isReversed,
                isActive: !isComplete
            )
        }
        return DrawPresentation(
            progresses: progresses,
            fallbackOpacity: nil,
            isReversed: active.isReversed,
            isActive: !isComplete
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
    if let nextRequest {
        return drawAnimation(
            for: nextRequest,
            symbol: symbol,
            initialProgresses: initialProgresses,
            transaction: transaction,
            at: time,
            immediate: nextRequest.isTransition && !hasResolvedEffects
        )
    }
    if var previousRequest {
        previousRequest.targetProgress = 1
        return drawAnimation(
            for: previousRequest,
            symbol: symbol,
            initialProgresses: initialProgresses,
            transaction: transaction,
            at: time
        )
    }
    return current
}

private func drawAnimation(
    for request: DrawRequest,
    symbol: ResolvedVectorSymbol,
    initialProgresses: [Double]?,
    transaction: Transaction,
    at time: Time,
    immediate: Bool = false
) -> ImageViewChild.ActiveDraw {
    let measuredDurations = symbol.drawMotionGroupDurations
    let usesOpacityFallback = measuredDurations.isEmpty
    let durations = usesOpacityFallback ? [0.8] : measuredDurations
    let initial = immediate
        ? [Double](repeating: request.targetProgress, count: durations.count)
        : initialProgresses.flatMap {
            $0.count == durations.count ? $0 : nil
        } ?? [Double](repeating: 1, count: durations.count)
    let hasMotion = zip(initial, durations).contains { initial, duration in
        duration * abs(request.targetProgress - initial) > .ulpOfOne
    }
    let completionTokens = hasMotion
        ? drawCompletionTokens(for: transaction)
        : []
    completionTokens.forEach { $0.start() }
    return ImageViewChild.ActiveDraw(
        id: request.id,
        startTime: time,
        motionGroupDurations: durations,
        initialProgresses: initial,
        targetProgress: request.targetProgress,
        effectiveSpeed: request.effectiveSpeed,
        layerBehavior: request.layerBehavior,
        isReversed: request.isReversed,
        usesOpacityFallback: usesOpacityFallback,
        completionTokens: completionTokens
    )
}

private func drawCompletionTokens(
    for transaction: Transaction
) -> [AnimationCompletionToken] {
    var tokens: [AnimationCompletionToken] = []
    if let listener = transaction.animationListener {
        tokens.append(AnimationCompletionToken(listener: listener, criteria: .removed))
    }
    if let listener = transaction.animationLogicalListener {
        tokens.append(
            AnimationCompletionToken(listener: listener, criteria: .logicallyComplete)
        )
    }
    return tokens
}

private func finishDrawCompletionTokens(
    _ tokens: [AnimationCompletionToken]
) -> [() -> Void] {
    let removed = tokens.filter { $0.criteria == .removed }
    let remaining = tokens.filter { $0.criteria != .removed }
    return (removed + remaining).flatMap { $0.finish() }
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

        // 1. Internal state nodes for communication between the resource and layout passes.
        // Caches the fully resolved image object (including GPU texture).
        let resolvedImageAttr = graph.makeInput(value: GraphicsContext.ResolvedImage?.none)
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
                context.environment = renderEnvironment
                AnyImageProviderBox.$_preferredBundle.withValue(bundle) {
                    // 1. [Synchronous Loading] Resolve the image (loads data and creates texture).
                    let resolved = context.resolve(image)
                    let boxedResolved = UnsafeBox(resolved)
                    let boxedTransaction = UnsafeBox(resourceTransaction)

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
                resolvedImage: resolvedImageAttr,
                environment: envAttr,
                transaction: inputs.base.transaction,
                time: inputs.base.time,
                position: positionAttr,
                size: sizeAttr
            )
        )
        let transitionContentAttr: Attribute<ResolvedImageTransitionContent> = graph.makeRule {
            ResolvedImageTransitionContent(image: resolvedImageAttr.value)
        }

        // 3. Layout pass (Layout Rule)
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            // Intrinsic size depends only on the resolved resource. Depending on
            // presentation state here would make framed images read their own
            // placement while the parent layout computer is still being built.
            let resolved = resolvedImageAttr.value
            if resolved == nil {
                // Establish the stateful effect environment before deferred
                // resource publication promotes the image to its first frame.
                _ = imageViewChildAttr.value
            }

            return LayoutComputer(
                sizeThatFits: { _ in resolved?.size ?? .zero }
            )
        }

        // 4. Drawing pass (DisplayList Rule)
        let dlAttr: Attribute<DisplayList> = graph.makeRule {
            let _ = view._attribute.value // Dependency: image changes
            let presentation = imageViewChildAttr.value
            let position = presentation.displayPosition ?? positionAttr.value
            let viewSize = (presentation.displaySize ?? sizeAttr.value).value
            let environment = envAttr.value.untrackedCopy()

            var list = DisplayList()
            if var resolved = presentation.image {
                let frame = CGRect(origin: position, size: viewSize)
                var imageList = DisplayList()
                resolved.symbolLayerOpacities = presentation.symbolLayerOpacities
                resolved.symbolVariableColorOpacities =
                    presentation.symbolVariableColorOpacities
                resolved.symbolDrawProgresses = presentation.symbolDrawProgresses
                resolved.symbolDrawFallbackOpacity =
                    presentation.symbolDrawFallbackOpacity
                resolved.symbolDrawsReversed = presentation.symbolDrawsReversed
                imageList.appendImageItem(
                    resolved,
                    bounds: frame,
                    environment: environment
                )
                if presentation.isSymbolEffectActive,
                   presentation.symbolOpacity != 1 {
                    list.appendOpacityItem(
                        bounds: frame,
                        opacity: presentation.symbolOpacity,
                        contents: imageList
                    )
                } else {
                    list = imageList
                }
            }
            return list
        }

        var outputs = _ViewOutputs()
        outputs._layoutComputer = OptionalAttribute(lcAttr)

        // 5. Propagate ResourceList and DisplayList upwards via the Preference channel!
        outputs.preferences.append(ResourceList.Key.self, node: resourceAttr.identifier)
        outputs.preferences.append(DisplayList.Key.self, node: dlAttr.identifier)
        var interpolatorInputs = inputs
        interpolatorInputs.base.transaction = resolvedImageTransactionAttr
        outputs.applyInterpolatorGroup(
            DisplayList.UnaryInterpolatorGroup(),
            content: transitionContentAttr,
            inputs: interpolatorInputs,
            animatesSize: false,
            defersRender: false
        )

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
