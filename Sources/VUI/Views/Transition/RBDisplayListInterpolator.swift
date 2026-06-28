//
//  File: RBDisplayListInterpolator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// String-backed option keys passed into the display-list interpolator.
struct RBDisplayListInterpolatorOptionKey: RawRepresentable, Hashable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let transition = RBDisplayListInterpolatorOptionKey(rawValue: "transition")
    static let animation = RBDisplayListInterpolatorOptionKey(rawValue: "animation")
    static let animationSequencer = RBDisplayListInterpolatorOptionKey(rawValue: "animationSequencer")
    static let fadeInOutFraction = RBDisplayListInterpolatorOptionKey(rawValue: "fadeInOutFraction")
    static let colorSpace = RBDisplayListInterpolatorOptionKey(rawValue: "colorSpace")
    static let rasterizationScale = RBDisplayListInterpolatorOptionKey(rawValue: "rasterizationscale")
}

// Interpolates between two DisplayList values for content-transition layers.
// The current implementation uses local bounds and closure replay until typed command storage exists.
final class RBDisplayListInterpolator: NSObject, NSCopying {
    var from: DisplayList
    let to: DisplayList
    let options: [RBDisplayListInterpolatorOptionKey: Any]

    init(
        from: DisplayList,
        to: DisplayList,
        options: [RBDisplayListInterpolatorOptionKey: Any] = [:]
    ) {
        self.from = from
        self.to = to
        self.options = options
        super.init()
    }

    var activeDuration: Double {
        guard transition != nil, hasChangedDisplayLists else {
            return 0
        }
        if let animation {
            return animation.activeDuration
        }
        if let sequencerDuration = animationSequencerActiveDuration {
            return sequencerDuration
        }
        return 1
    }

    var isIdentity: Bool {
        false
    }

    var onlyFades: Bool {
        guard let transition else { return true }
        return transition.effects.isEmpty || transition.effects.allSatisfy {
            $0.type == ContentTransition.EffectType.opacity.type
        }
    }

    var transition: RBTransition? {
        options[.transition] as? RBTransition
    }

    var animation: RBAnimation? {
        options[.animation] as? RBAnimation
    }

    var animationSequencer: RBAnimationSequencer? {
        options[.animationSequencer] as? RBAnimationSequencer
    }

    func setFrom(_ displayList: DisplayList) {
        from = displayList
    }

    func boundingRect(withProgress progress: Float) -> CGRect {
        interpolatedBounds(at: progress) ?? .null
    }

    func maxAbsoluteVelocity(withProgress progress: Float) -> Double {
        0
    }

    func copyContents(withProgress progress: Float) -> DisplayList {
        let resolvedProgress = resolvedProgress(at: progress)
        if resolvedProgress >= 1 {
            return to
        }
        if resolvedProgress <= 0 {
            return from
        }
        return interpolatedContents(forResolvedProgress: resolvedProgress)
    }

    func contents(withProgress progress: Float) -> DisplayList {
        copyContents(withProgress: progress)
    }

    func copy(with zone: NSZone? = nil) -> Any {
        RBDisplayListInterpolator(
            from: from,
            to: to,
            options: options
        )
    }

    private func resolvedProgress(at time: Float) -> Float {
        guard let animation else {
            return time
        }
        return animation.evaluateAtTime(Double(time))
    }

    private func interpolatedBounds(at time: Float) -> CGRect? {
        interpolatedBounds(forResolvedProgress: resolvedProgress(at: time))
    }

    private func interpolatedBounds(forResolvedProgress progress: Float) -> CGRect? {
        guard let fromBounds = from.interpolationBounds,
              let toBounds = to.interpolationBounds else {
            return nil
        }
        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        return CGRect(
            x: interpolate(fromBounds.origin.x, toBounds.origin.x, by: clampedProgress),
            y: interpolate(fromBounds.origin.y, toBounds.origin.y, by: clampedProgress),
            width: interpolate(fromBounds.size.width, toBounds.size.width, by: clampedProgress),
            height: interpolate(fromBounds.size.height, toBounds.size.height, by: clampedProgress)
        )
    }

    private func interpolatedContents(forResolvedProgress progress: Float) -> DisplayList {
        guard let fromBounds = from.interpolationBounds,
              let toBounds = to.interpolationBounds,
              let outputBounds = interpolatedBounds(forResolvedProgress: progress) else {
            return from
        }

        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        var contents = DisplayList()
        contents.interpolationBounds = outputBounds
        contents.effects = from.effects

        if !from.items.isEmpty || !to.items.isEmpty {
            let fromItems = from.items
            let toItems = to.items
            contents.items.append { context in
                Self.drawInterpolatedItems(
                    fromItems,
                    sourceBounds: fromBounds,
                    outputBounds: outputBounds,
                    opacity: 1 - Double(clampedProgress),
                    in: context
                )
                Self.drawInterpolatedItems(
                    toItems,
                    sourceBounds: toBounds,
                    outputBounds: outputBounds,
                    opacity: Double(clampedProgress),
                    in: context
                )
            }
        }

        if !from.debugItems.isEmpty || !to.debugItems.isEmpty {
            let fromDebugItems = from.debugItems
            let toDebugItems = to.debugItems
            contents.debugItems.append { context in
                Self.drawInterpolatedItems(
                    fromDebugItems,
                    sourceBounds: fromBounds,
                    outputBounds: outputBounds,
                    opacity: 1 - Double(clampedProgress),
                    in: context
                )
                Self.drawInterpolatedItems(
                    toDebugItems,
                    sourceBounds: toBounds,
                    outputBounds: outputBounds,
                    opacity: Double(clampedProgress),
                    in: context
                )
            }
        }

        return contents
    }

    private static func drawInterpolatedItems(
        _ items: [DisplayList.Item],
        sourceBounds: CGRect,
        outputBounds: CGRect,
        opacity: Double,
        in context: GraphicsContext
    ) {
        guard !items.isEmpty,
              opacity > 0,
              let transform = interpolationTransform(from: sourceBounds, to: outputBounds) else {
            return
        }

        var context = context
        context.opacity *= opacity
        guard context.opacity > 0 else { return }

        context.drawLayer { layerContext in
            layerContext.concatenate(transform)
            for item in items {
                item(layerContext)
            }
        }
    }

    private static func interpolationTransform(
        from sourceBounds: CGRect,
        to outputBounds: CGRect
    ) -> CGAffineTransform? {
        guard sourceBounds.width.magnitude > .ulpOfOne,
              sourceBounds.height.magnitude > .ulpOfOne else {
            return nil
        }

        let scaleX = outputBounds.width / sourceBounds.width
        let scaleY = outputBounds.height / sourceBounds.height
        return CGAffineTransform(
            a: scaleX,
            b: 0,
            c: 0,
            d: scaleY,
            tx: outputBounds.minX - sourceBounds.minX * scaleX,
            ty: outputBounds.minY - sourceBounds.minY * scaleY
        )
    }

    private func interpolate(_ from: CGFloat, _ to: CGFloat, by progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private var animationSequencerActiveDuration: Double? {
        guard let sequencer = animationSequencer,
              let effects = sequencer.mixed else {
            return nil
        }
        let delayFactor = sequencerDelayFactor(sequencer)
        return 1 + Double(effects.delayOffset) + Double(effects.delayScale) * delayFactor
    }

    private func sequencerDelayFactor(_ sequencer: RBAnimationSequencer) -> Double {
        guard let bounds = to.interpolationBounds ?? from.interpolationBounds else {
            return 0
        }
        let distance = hypot(
            sequencer.endPoint.x - sequencer.startPoint.x,
            sequencer.endPoint.y - sequencer.startPoint.y
        )
        guard distance > 0 else {
            return 0
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rawFactor = hypot(
            center.x - sequencer.startPoint.x,
            center.y - sequencer.startPoint.y
        ) / distance
        let clamped = min(max(rawFactor, 0), 1)
        if sequencer.distanceMode == 0 {
            return floor(Double(clamped) * 100) / 100
        }
        return Double(clamped)
    }

    private var hasChangedDisplayLists: Bool {
        from.items.count != to.items.count ||
            from.debugItems.count != to.debugItems.count ||
            from.effects.count != to.effects.count ||
            from.interpolationBounds != to.interpolationBounds
    }
}
