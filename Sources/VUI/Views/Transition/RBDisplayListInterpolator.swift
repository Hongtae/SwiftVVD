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
        guard hasChangedDisplayLists else {
            return 0
        }
        if let animation = checkedAnimationOption() {
            if let sequencerDelay = animationSequencerDelayDuration {
                return animation.activeDuration + sequencerDelay
            }
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
        guard let transition else {
            return !hasDisplayListContents
        }
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
        guard hasChangedDisplayLists,
              let animation = checkedAnimationOption(),
              let bounds = Self.unionBounds(from: from, to: to) else {
            return 0
        }
        let boundsSize = max(bounds.width, bounds.height)
        guard boundsSize.isFinite, boundsSize > 0 else { return 0 }
        return animation.speed(atTime: Double(progress)) * Double(boundsSize)
    }

    func copyContents(withProgress progress: Float) -> DisplayList {
        let resolvedProgress = resolvedProgress(at: progress)
        if resolvedProgress >= 1 {
            if shouldMaterializeEndpointContents {
                return interpolatedContents(forResolvedProgress: 1)
            }
            return to
        }
        if resolvedProgress <= 0 {
            if shouldMaterializeEndpointContents {
                return interpolatedContents(forResolvedProgress: 0)
            }
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
        let sequencedTime = Double(time) - (animationSequencerDelayDuration ?? 0)
        guard let animation else {
            return Float(sequencedTime)
        }
        return animation.evaluateAtTime(sequencedTime)
    }

    private func checkedAnimationOption() -> RBAnimation? {
        guard let value = options[.animation] else {
            return nil
        }
        guard let animation = value as? RBAnimation else {
            fatalError("RBDisplayListInterpolator animation option must be an RBAnimation.")
        }
        return animation
    }

    private func interpolatedBounds(at time: Float) -> CGRect? {
        Self.interpolatedBounds(from: from, to: to, progress: resolvedProgress(at: time))
    }

    private func interpolatedContents(forResolvedProgress progress: Float) -> DisplayList {
        Self.interpolatedContents(from: from, to: to, progress: progress)
    }

    private var shouldMaterializeEndpointContents: Bool {
        hasChangedDisplayLists &&
            Self.canMaterializeInterpolatedContents(from: from, to: to)
    }

    private static func interpolatedContents(
        from: DisplayList,
        to: DisplayList,
        progress: Float
    ) -> DisplayList {
        guard let fromBounds = from.interpolationBounds,
              let toBounds = to.interpolationBounds,
              let outputBounds = interpolatedBounds(from: from, to: to, progress: progress) else {
            return from
        }

        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        var contents = DisplayList()
        contents.interpolationBounds = outputBounds

        if !from.items.isEmpty || !to.items.isEmpty {
            appendInterpolatedItems(
                fromItems: from.items,
                fromRecords: from.itemRecords,
                fromFallbackBounds: fromBounds,
                toItems: to.items,
                toRecords: to.itemRecords,
                toFallbackBounds: toBounds,
                outputFallbackBounds: outputBounds,
                progress: clampedProgress,
                into: &contents
            )
        }

        if !from.debugItems.isEmpty || !to.debugItems.isEmpty {
            appendInterpolatedDebugItems(
                fromItems: from.debugItems,
                fromRecords: from.debugItemRecords,
                fromFallbackBounds: fromBounds,
                toItems: to.debugItems,
                toRecords: to.debugItemRecords,
                toFallbackBounds: toBounds,
                outputFallbackBounds: outputBounds,
                progress: clampedProgress,
                into: &contents
            )
        }

        appendInterpolatedEffects(
            from: from.effects,
            to: to.effects,
            progress: progress,
            into: &contents
        )

        return contents
    }

    private static func appendInterpolatedItems(
        fromItems: [DisplayList.Item],
        fromRecords: [DisplayList.ItemRecord],
        fromFallbackBounds: CGRect,
        toItems: [DisplayList.Item],
        toRecords: [DisplayList.ItemRecord],
        toFallbackBounds: CGRect,
        outputFallbackBounds: CGRect,
        progress: CGFloat,
        into contents: inout DisplayList
    ) {
        if canInterpolateRecordedItems(
            fromItems: fromItems,
            fromRecords: fromRecords,
            toItems: toItems,
            toRecords: toRecords
        ) {
            let pairedCount = min(fromItems.count, toItems.count)
            for index in 0..<pairedCount {
                let sourceBounds = fromRecords[index].bounds!
                let targetBounds = toRecords[index].bounds!
                let outputBounds = interpolatedBounds(
                    from: sourceBounds,
                    to: targetBounds,
                    progress: progress
                )
                let fromItem = fromItems[index]
                let toItem = toItems[index]
                contents.appendCrossFadeItem(
                    bounds: outputBounds,
                    sourceFraction: Float(progress),
                    targetFraction: Float(progress)
                ) { context in
                    drawInterpolatedItems(
                        [fromItem],
                        sourceBounds: sourceBounds,
                        outputBounds: outputBounds,
                        opacity: 1 - Double(progress),
                        in: context
                    )
                    drawInterpolatedItems(
                        [toItem],
                        sourceBounds: targetBounds,
                        outputBounds: outputBounds,
                        opacity: Double(progress),
                        in: context
                    )
                }
            }

            appendSourceExtraItems(
                fromItems[pairedCount...],
                records: fromRecords[pairedCount...],
                progress: progress,
                into: &contents
            )
            appendTargetExtraItems(
                toItems[pairedCount...],
                records: toRecords[pairedCount...],
                progress: progress,
                into: &contents
            )
            return
        }

        contents.appendCrossFadeItem(
            bounds: outputFallbackBounds,
            sourceFraction: Float(progress),
            targetFraction: Float(progress)
        ) { context in
            drawInterpolatedItems(
                fromItems,
                sourceBounds: fromFallbackBounds,
                outputBounds: outputFallbackBounds,
                opacity: 1 - Double(progress),
                in: context
            )
            drawInterpolatedItems(
                toItems,
                sourceBounds: toFallbackBounds,
                outputBounds: outputFallbackBounds,
                opacity: Double(progress),
                in: context
            )
        }
    }

    private static func appendInterpolatedDebugItems(
        fromItems: [DisplayList.Item],
        fromRecords: [DisplayList.ItemRecord],
        fromFallbackBounds: CGRect,
        toItems: [DisplayList.Item],
        toRecords: [DisplayList.ItemRecord],
        toFallbackBounds: CGRect,
        outputFallbackBounds: CGRect,
        progress: CGFloat,
        into contents: inout DisplayList
    ) {
        if canInterpolateMatchingRecordedItems(
            fromItems: fromItems,
            fromRecords: fromRecords,
            toItems: toItems,
            toRecords: toRecords
        ) {
            let pairedCount = min(fromItems.count, toItems.count)
            for index in 0..<pairedCount {
                let sourceBounds = fromRecords[index].bounds!
                let targetBounds = toRecords[index].bounds!
                let outputBounds = interpolatedBounds(
                    from: sourceBounds,
                    to: targetBounds,
                    progress: progress
                )
                let fromItem = fromItems[index]
                let toItem = toItems[index]
                contents.appendDebugItem(bounds: outputBounds) { context in
                    drawInterpolatedItems(
                        [fromItem],
                        sourceBounds: sourceBounds,
                        outputBounds: outputBounds,
                        opacity: 1 - Double(progress),
                        in: context
                    )
                    drawInterpolatedItems(
                        [toItem],
                        sourceBounds: targetBounds,
                        outputBounds: outputBounds,
                        opacity: Double(progress),
                        in: context
                    )
                }
            }
            return
        }

        contents.appendDebugItem(bounds: outputFallbackBounds) { context in
            drawInterpolatedItems(
                fromItems,
                sourceBounds: fromFallbackBounds,
                outputBounds: outputFallbackBounds,
                opacity: 1 - Double(progress),
                in: context
            )
            drawInterpolatedItems(
                toItems,
                sourceBounds: toFallbackBounds,
                outputBounds: outputFallbackBounds,
                opacity: Double(progress),
                in: context
            )
        }
    }

    private static func appendSourceExtraItems(
        _ items: ArraySlice<DisplayList.Item>,
        records: ArraySlice<DisplayList.ItemRecord>,
        progress: CGFloat,
        into contents: inout DisplayList
    ) {
        for (item, record) in zip(items, records) {
            let bounds = record.bounds!
            contents.appendCrossFadeItem(
                bounds: bounds,
                sourceFraction: Float(progress),
                targetFraction: 0
            ) { context in
                drawInterpolatedItems(
                    [item],
                    sourceBounds: bounds,
                    outputBounds: bounds,
                    opacity: 1 - Double(progress),
                    in: context
                )
            }
        }
    }

    private static func appendTargetExtraItems(
        _ items: ArraySlice<DisplayList.Item>,
        records: ArraySlice<DisplayList.ItemRecord>,
        progress: CGFloat,
        into contents: inout DisplayList
    ) {
        for (item, record) in zip(items, records) {
            let bounds = record.bounds!
            contents.appendCrossFadeItem(
                bounds: bounds,
                sourceFraction: 0,
                targetFraction: Float(progress)
            ) { context in
                drawInterpolatedItems(
                    [item],
                    sourceBounds: bounds,
                    outputBounds: bounds,
                    opacity: Double(progress),
                    in: context
                )
            }
        }
    }

    private static func appendInterpolatedEffects(
        from sourceEffects: [DisplayList.EffectItem],
        to targetEffects: [DisplayList.EffectItem],
        progress: Float,
        into contents: inout DisplayList
    ) {
        guard sourceEffects.count == targetEffects.count else {
            contents.effects = sourceEffects
            return
        }

        for (source, target) in zip(sourceEffects, targetEffects) {
            guard source.effect.hasSameSurface(as: target.effect) else {
                contents.appendEffect(source.effect, contents: source.contents)
                continue
            }

            contents.appendEffect(
                source.effect,
                contents: interpolatedContents(
                    from: source.contents,
                    to: target.contents,
                    progress: progress
                )
            )
        }
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

    private static func interpolatedBounds(
        from fromList: DisplayList,
        to toList: DisplayList,
        progress: Float
    ) -> CGRect? {
        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        if let recordedBounds = interpolatedRecordedBounds(
            from: fromList,
            to: toList,
            progress: clampedProgress
        ) {
            return recordedBounds
        }

        guard let fromBounds = fromList.interpolationBounds,
              let toBounds = toList.interpolationBounds else {
            return nil
        }
        return interpolatedBounds(from: fromBounds, to: toBounds, progress: clampedProgress)
    }

    private static func interpolatedRecordedBounds(
        from fromList: DisplayList,
        to toList: DisplayList,
        progress: CGFloat
    ) -> CGRect? {
        var bounds: CGRect?

        if !fromList.items.isEmpty || !toList.items.isEmpty {
            guard let itemBounds = interpolatedRecordedItemBounds(
                fromItems: fromList.items,
                fromRecords: fromList.itemRecords,
                toItems: toList.items,
                toRecords: toList.itemRecords,
                progress: progress,
                allowsCountMismatch: true
            ) else { return nil }
            bounds = union(bounds, itemBounds)
        }

        if !fromList.debugItems.isEmpty || !toList.debugItems.isEmpty {
            guard let debugBounds = interpolatedRecordedItemBounds(
                fromItems: fromList.debugItems,
                fromRecords: fromList.debugItemRecords,
                toItems: toList.debugItems,
                toRecords: toList.debugItemRecords,
                progress: progress,
                allowsCountMismatch: false
            ) else { return nil }
            bounds = union(bounds, debugBounds)
        }

        if !fromList.effects.isEmpty || !toList.effects.isEmpty {
            guard let effectBounds = interpolatedRecordedEffectBounds(
                from: fromList.effects,
                to: toList.effects,
                progress: progress
            ) else { return nil }
            bounds = union(bounds, effectBounds)
        }

        return bounds
    }

    private static func interpolatedRecordedEffectBounds(
        from sourceEffects: [DisplayList.EffectItem],
        to targetEffects: [DisplayList.EffectItem],
        progress: CGFloat
    ) -> CGRect? {
        guard !sourceEffects.isEmpty,
              sourceEffects.count == targetEffects.count else {
            return nil
        }

        var bounds: CGRect?
        for (source, target) in zip(sourceEffects, targetEffects) {
            guard source.effect.hasSameSurface(as: target.effect),
                  let effectBounds = interpolatedRecordedBounds(
                    from: source.contents,
                    to: target.contents,
                    progress: progress
                  ) ?? interpolatedBounds(
                    from: source.contents,
                    to: target.contents,
                    progress: Float(progress)
                  ) else {
                return nil
            }
            bounds = union(bounds, effectBounds)
        }
        return bounds
    }

    private static func canMaterializeInterpolatedContents(
        from source: DisplayList,
        to target: DisplayList
    ) -> Bool {
        guard source.interpolationBounds != nil,
              target.interpolationBounds != nil else {
            return false
        }

        if canInterpolateRecordedItems(
            fromItems: source.items,
            fromRecords: source.itemRecords,
            toItems: target.items,
            toRecords: target.itemRecords
        ) {
            return true
        }

        if canInterpolateMatchingRecordedItems(
            fromItems: source.debugItems,
            fromRecords: source.debugItemRecords,
            toItems: target.debugItems,
            toRecords: target.debugItemRecords
        ) {
            return true
        }

        return canMaterializeInterpolatedEffects(
            from: source.effects,
            to: target.effects
        )
    }

    private static func canMaterializeInterpolatedEffects(
        from sourceEffects: [DisplayList.EffectItem],
        to targetEffects: [DisplayList.EffectItem]
    ) -> Bool {
        guard !sourceEffects.isEmpty,
              sourceEffects.count == targetEffects.count else {
            return false
        }

        return zip(sourceEffects, targetEffects).contains { source, target in
            source.effect.hasSameSurface(as: target.effect) &&
                canMaterializeInterpolatedContents(
                    from: source.contents,
                    to: target.contents
                )
        }
    }

    private static func interpolatedRecordedItemBounds(
        fromItems: [DisplayList.Item],
        fromRecords: [DisplayList.ItemRecord],
        toItems: [DisplayList.Item],
        toRecords: [DisplayList.ItemRecord],
        progress: CGFloat,
        allowsCountMismatch: Bool
    ) -> CGRect? {
        let canInterpolate = allowsCountMismatch
            ? canInterpolateRecordedItems(
                fromItems: fromItems,
                fromRecords: fromRecords,
                toItems: toItems,
                toRecords: toRecords
            )
            : canInterpolateMatchingRecordedItems(
                fromItems: fromItems,
                fromRecords: fromRecords,
                toItems: toItems,
                toRecords: toRecords
            )
        guard canInterpolate else { return nil }

        let pairedCount = min(fromRecords.count, toRecords.count)
        var bounds = (0..<pairedCount).reduce(nil) { partial, index in
            let bounds = interpolatedBounds(
                from: fromRecords[index].bounds!,
                to: toRecords[index].bounds!,
                progress: progress
            )
            return union(partial, bounds)
        }
        bounds = fromRecords[pairedCount...].reduce(bounds) { partial, record in
            union(partial, record.bounds!)
        }
        bounds = toRecords[pairedCount...].reduce(bounds) { partial, record in
            union(partial, record.bounds!)
        }
        return bounds
    }

    private static func union(_ lhs: CGRect?, _ rhs: CGRect?) -> CGRect? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs.union(rhs)
    }

    private static func canInterpolateRecordedItems(
        fromItems: [DisplayList.Item],
        fromRecords: [DisplayList.ItemRecord],
        toItems: [DisplayList.Item],
        toRecords: [DisplayList.ItemRecord]
    ) -> Bool {
        guard !fromItems.isEmpty,
              !toItems.isEmpty,
              fromRecords.count == fromItems.count,
              toRecords.count == toItems.count else {
            return false
        }
        return fromRecords.allSatisfy { $0.bounds != nil } &&
            toRecords.allSatisfy { $0.bounds != nil }
    }

    private static func canInterpolateMatchingRecordedItems(
        fromItems: [DisplayList.Item],
        fromRecords: [DisplayList.ItemRecord],
        toItems: [DisplayList.Item],
        toRecords: [DisplayList.ItemRecord]
    ) -> Bool {
        fromItems.count == toItems.count &&
            canInterpolateRecordedItems(
                fromItems: fromItems,
                fromRecords: fromRecords,
                toItems: toItems,
                toRecords: toRecords
            )
    }

    private static func interpolatedBounds(
        from fromBounds: CGRect,
        to toBounds: CGRect,
        progress: CGFloat
    ) -> CGRect {
        return CGRect(
            x: interpolate(fromBounds.origin.x, toBounds.origin.x, by: progress),
            y: interpolate(fromBounds.origin.y, toBounds.origin.y, by: progress),
            width: interpolate(fromBounds.size.width, toBounds.size.width, by: progress),
            height: interpolate(fromBounds.size.height, toBounds.size.height, by: progress)
        )
    }

    private static func unionBounds(from fromList: DisplayList, to toList: DisplayList) -> CGRect? {
        guard let fromBounds = fromList.interpolationBounds,
              let toBounds = toList.interpolationBounds else {
            return nil
        }
        return fromBounds.union(toBounds)
    }

    private static func interpolate(_ from: CGFloat, _ to: CGFloat, by progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }

    private var animationSequencerActiveDuration: Double? {
        guard let sequencer = animationSequencer,
              let effects = sequencer.mixed else {
            return nil
        }
        guard let delayFactor = sequencerDelayFactor(sequencer) else {
            return 1
        }
        return 1 + Double(effects.delayOffset) + Double(effects.delayScale) * delayFactor
    }

    private var animationSequencerDelayDuration: Double? {
        guard let duration = animationSequencerActiveDuration else {
            return nil
        }
        return max(0, duration - 1)
    }

    private func sequencerDelayFactor(_ sequencer: RBAnimationSequencer) -> Double? {
        guard let bounds = to.interpolationBounds ?? from.interpolationBounds else {
            return nil
        }
        let distance = hypot(
            sequencer.endPoint.x - sequencer.startPoint.x,
            sequencer.endPoint.y - sequencer.startPoint.y
        )
        guard distance > 0 else {
            return nil
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rawFactor = hypot(
            center.x - sequencer.startPoint.x,
            center.y - sequencer.startPoint.y
        ) / distance
        let clamped = min(max(rawFactor, 0), 1)
        switch sequencer.distanceMode {
        case 0:
            return floor(Double(clamped) * 100) / 100
        case 1:
            return Double(clamped)
        default:
            return 0
        }
    }

    private var hasChangedDisplayLists: Bool {
        !from.hasSameInterpolationSurface(as: to)
    }

    private var hasDisplayListContents: Bool {
        Self.hasDisplayListContents(from) || Self.hasDisplayListContents(to)
    }

    private static func hasDisplayListContents(_ displayList: DisplayList) -> Bool {
        displayList.interpolationBounds != nil ||
            !displayList.items.isEmpty ||
            !displayList.debugItems.isEmpty ||
            !displayList.effects.isEmpty
    }
}
