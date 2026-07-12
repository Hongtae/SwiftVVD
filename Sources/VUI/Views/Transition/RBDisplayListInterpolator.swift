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
// The local operation stream preserves item roles without mirroring RenderBox's private C++ ABI.
final class RBDisplayListInterpolator: NSObject, NSCopying {
    private struct ItemInterpolationInput {
        var item: DisplayList.Item
        var command: DisplayList.ItemCommand
        var bounds: CGRect
    }

    private enum ItemInterpolationOperation {
        case paired(source: ItemInterpolationInput, target: ItemInterpolationInput)
        case removed(ItemInterpolationInput)
        case inserted(ItemInterpolationInput)
        case fallback(
            sourceItems: [DisplayList.Item],
            sourceBounds: CGRect,
            targetItems: [DisplayList.Item],
            targetBounds: CGRect
        )

        func reportedBounds(
            at progress: CGFloat,
            transition: RBTransition?
        ) -> CGRect? {
            switch self {
            case let .paired(source, target):
                // Paired commands use the mixed cross-fade path. Insertion and removal
                // event masks only govern unmatched operations.
                return RBDisplayListInterpolator.interpolatedBounds(
                    from: source.bounds,
                    to: target.bounds,
                    progress: progress
                )
            case let .removed(source):
                // A present transition owns one-sided lifetime. A nonmatching removal
                // event drops the old item instead of applying the generic cross-fade.
                guard let transition else { return source.bounds }
                guard !transition.isEmpty(for: 2) else { return nil }
                guard let results = transition.effectResults(
                    at: Float(progress),
                    event: 2,
                    bounds: source.bounds
                ) else { return source.bounds }
                return visibleBounds(from: results, fallback: source.bounds)
            case let .inserted(target):
                // Inserted items remain fully visible when a present transition does not
                // match insertion; matching effects wrap the target item below.
                guard let transition, !transition.isEmpty(for: 1) else {
                    return target.bounds
                }
                guard let results = transition.effectResults(
                    at: Float(progress),
                    event: 1,
                    bounds: target.bounds
                ) else { return target.bounds }
                return visibleBounds(from: results, fallback: target.bounds)
            case let .fallback(_, sourceBounds, _, targetBounds):
                return RBDisplayListInterpolator.interpolatedBounds(
                    from: sourceBounds,
                    to: targetBounds,
                    progress: progress
                )
            }
        }

        func append(
            at progress: CGFloat,
            transition: RBTransition?,
            into contents: inout DisplayList
        ) {
            switch self {
            case let .paired(source, target):
                if RBDisplayListInterpolator.isTextItemPair(
                    source.command,
                    target.command
                ) {
                    appendTextPair(
                        source: source,
                        target: target,
                        progress: progress,
                        into: &contents
                    )
                    return
                }
                guard let outputBounds = reportedBounds(
                    at: progress,
                    transition: transition
                ) else { return }
                contents.appendCrossFadeItem(
                    sourceItems: [source.item],
                    sourceBounds: source.bounds,
                    sourceOutputBounds: outputBounds,
                    targetItems: [target.item],
                    targetBounds: target.bounds,
                    targetOutputBounds: outputBounds,
                    bounds: outputBounds,
                    sourceFraction: Float(progress),
                    targetFraction: Float(progress)
                )
            case let .removed(source):
                guard let transition else {
                    appendRemovedCrossFade(source, progress: progress, into: &contents)
                    return
                }
                guard !transition.isEmpty(for: 2) else { return }
                guard let results = transition.effectResults(
                    at: Float(progress),
                    event: 2,
                    bounds: source.bounds
                ) else {
                    appendRemovedCrossFade(source, progress: progress, into: &contents)
                    return
                }
                appendTransitionedItem(source, results: results, into: &contents)
            case let .inserted(target):
                guard let transition else {
                    appendInsertedCrossFade(target, progress: progress, into: &contents)
                    return
                }
                guard !transition.isEmpty(for: 1) else {
                    contents.items.append(target.item)
                    return
                }
                guard let results = transition.effectResults(
                    at: Float(progress),
                    event: 1,
                    bounds: target.bounds
                ) else {
                    appendInsertedCrossFade(target, progress: progress, into: &contents)
                    return
                }
                appendTransitionedItem(target, results: results, into: &contents)
            case let .fallback(sourceItems, sourceBounds, targetItems, targetBounds):
                let outputBounds = reportedBounds(at: progress, transition: transition) ?? .zero
                contents.appendCrossFadeItem(
                    sourceItems: sourceItems,
                    sourceBounds: sourceBounds,
                    sourceOutputBounds: outputBounds,
                    targetItems: targetItems,
                    targetBounds: targetBounds,
                    targetOutputBounds: outputBounds,
                    bounds: outputBounds,
                    sourceFraction: Float(progress),
                    targetFraction: Float(progress)
                )
            }
        }

        private func appendRemovedCrossFade(
            _ source: ItemInterpolationInput,
            progress: CGFloat,
            into contents: inout DisplayList
        ) {
            contents.appendCrossFadeItem(
                sourceItems: [source.item],
                sourceBounds: source.bounds,
                sourceOutputBounds: source.bounds,
                targetItems: [],
                targetBounds: nil,
                targetOutputBounds: nil,
                bounds: source.bounds,
                sourceFraction: Float(progress),
                targetFraction: 0
            )
        }

        private func appendInsertedCrossFade(
            _ target: ItemInterpolationInput,
            progress: CGFloat,
            into contents: inout DisplayList
        ) {
            contents.appendCrossFadeItem(
                sourceItems: [],
                sourceBounds: nil,
                sourceOutputBounds: nil,
                targetItems: [target.item],
                targetBounds: target.bounds,
                targetOutputBounds: target.bounds,
                bounds: target.bounds,
                sourceFraction: 0,
                targetFraction: Float(progress)
            )
        }

        private func appendTransitionedItem(
            _ input: ItemInterpolationInput,
            results: RBTransitionEffectResults,
            into contents: inout DisplayList
        ) {
            guard results.alpha > 0 else { return }

            var resolved = DisplayList()
            resolved.items = [input.item]
            resolved.interpolationBounds = input.bounds
            var resolvedBounds = input.bounds

            if !results.transform.isIdentity {
                var transformed = DisplayList()
                for item in resolved.items {
                    transformed.appendTransformedItem(
                        item,
                        affineTransform: results.transform
                    )
                }
                resolved = transformed
                resolvedBounds = input.bounds.applying(results.transform).standardized
            }

            if results.alpha < 1 {
                var faded = DisplayList()
                faded.appendOpacityItem(
                    bounds: resolvedBounds,
                    opacity: Double(results.alpha),
                    contents: resolved
                )
                resolved = faded
            }

            if results.hasBlur, results.blurRadius > 0 {
                var blurred = DisplayList()
                blurred.appendBlurItem(
                    bounds: results.bounds ?? resolvedBounds,
                    radius: results.blurRadius,
                    isOpaque: false,
                    contents: resolved
                )
                resolved = blurred
            }

            contents.items.append(contentsOf: resolved.items)
        }

        private func visibleBounds(
            from results: RBTransitionEffectResults,
            fallback: CGRect
        ) -> CGRect? {
            guard results.alpha > 0 else { return nil }
            let bounds = results.bounds ?? fallback
            guard !bounds.isNull,
                  bounds.width > 0,
                  bounds.height > 0 else {
                return nil
            }
            return bounds
        }

        private func appendTextPair(
            source: ItemInterpolationInput,
            target: ItemInterpolationInput,
            progress: CGFloat,
            into contents: inout DisplayList
        ) {
            let center = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
            let sourceOutputBounds = RBDisplayListInterpolator.centeredBounds(
                size: source.bounds.size,
                at: center
            )
            let targetOutputBounds = RBDisplayListInterpolator.centeredBounds(
                size: target.bounds.size,
                at: center
            )
            let crossFadeBounds: CGRect
            if progress <= 0 {
                crossFadeBounds = sourceOutputBounds
            } else if progress >= 1 {
                crossFadeBounds = targetOutputBounds
            } else {
                crossFadeBounds = sourceOutputBounds.union(targetOutputBounds)
            }
            contents.appendCrossFadeItem(
                sourceItems: [source.item],
                sourceBounds: source.bounds,
                sourceOutputBounds: sourceOutputBounds,
                targetItems: [target.item],
                targetBounds: target.bounds,
                targetOutputBounds: targetOutputBounds,
                bounds: crossFadeBounds,
                sourceFraction: Float(progress),
                targetFraction: Float(progress)
            )
        }
    }

    var from: DisplayList
    private(set) var to: DisplayList
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
            $0.semanticType == ContentTransition.EffectType.opacity.type
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

    func setTo(_ displayList: DisplayList) {
        to = displayList
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
        let resolvedAnimation = hasChangedDisplayLists
            ? checkedAnimationOption()
            : animation
        guard let animation = resolvedAnimation else {
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
        Self.interpolatedBounds(
            from: from,
            to: to,
            progress: resolvedProgress(at: time),
            transition: transition
        )
    }

    private func interpolatedContents(forResolvedProgress progress: Float) -> DisplayList {
        Self.interpolatedContents(
            from: from,
            to: to,
            progress: progress,
            transition: transition
        )
    }

    private var shouldMaterializeEndpointContents: Bool {
        hasChangedDisplayLists &&
            Self.canMaterializeInterpolatedContents(from: from, to: to)
    }

    private static func interpolatedContents(
        from: DisplayList,
        to: DisplayList,
        progress: Float,
        transition: RBTransition?
    ) -> DisplayList {
        guard let fromBounds = from.interpolationBounds,
              let toBounds = to.interpolationBounds,
              let outputBounds = interpolatedBounds(
                from: from,
                to: to,
                progress: progress,
                transition: transition
              ) else {
            return from
        }

        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        var contents = DisplayList()
        contents.interpolationBounds = outputBounds

        if !from.renderItems.isEmpty || !to.renderItems.isEmpty {
            appendInterpolatedItems(
                fromItems: from.renderItems,
                fromCommands: from.itemCommands,
                fromFallbackBounds: fromBounds,
                toItems: to.renderItems,
                toCommands: to.itemCommands,
                toFallbackBounds: toBounds,
                progress: clampedProgress,
                transition: transition,
                into: &contents
            )
        }

        if !from.debugItems.isEmpty || !to.debugItems.isEmpty {
            appendInterpolatedDebugItems(
                fromItems: from.debugItems,
                fromCommands: from.debugItemCommands,
                fromFallbackBounds: fromBounds,
                toItems: to.debugItems,
                toCommands: to.debugItemCommands,
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
            transition: transition,
            into: &contents
        )

        return contents
    }

    private static func appendInterpolatedItems(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        fromFallbackBounds: CGRect,
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand],
        toFallbackBounds: CGRect,
        progress: CGFloat,
        transition: RBTransition?,
        into contents: inout DisplayList
    ) {
        let operations = itemInterpolationOperations(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands,
            allowsCountMismatch: true
        ) ?? [
            .fallback(
                sourceItems: fromItems,
                sourceBounds: fromFallbackBounds,
                targetItems: toItems,
                targetBounds: toFallbackBounds
            ),
        ]
        for operation in operations {
            operation.append(
                at: progress,
                transition: transition,
                into: &contents
            )
        }
    }

    private static func isTextItemPair(
        _ source: DisplayList.ItemCommand,
        _ target: DisplayList.ItemCommand
    ) -> Bool {
        guard case .text = source, case .text = target else { return false }
        return true
    }

    private static func centeredBounds(size: CGSize, at center: CGPoint) -> CGRect {
        CGRect(
            x: center.x - size.width * 0.5,
            y: center.y - size.height * 0.5,
            width: size.width,
            height: size.height
        )
    }

    private static func appendInterpolatedDebugItems(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        fromFallbackBounds: CGRect,
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand],
        toFallbackBounds: CGRect,
        outputFallbackBounds: CGRect,
        progress: CGFloat,
        into contents: inout DisplayList
    ) {
        if canInterpolateMatchingRecordedItems(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands
        ) {
            let pairedCount = min(fromItems.count, toItems.count)
            for index in 0..<pairedCount {
                let sourceBounds = fromCommands[index].bounds!
                let targetBounds = toCommands[index].bounds!
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

    private static func appendInterpolatedEffects(
        from sourceEffects: [DisplayList.EffectItem],
        to targetEffects: [DisplayList.EffectItem],
        progress: Float,
        transition: RBTransition?,
        into contents: inout DisplayList
    ) {
        guard sourceEffects.count == targetEffects.count else {
            appendEffectItems(progress >= 1 ? targetEffects : sourceEffects, into: &contents)
            return
        }

        for (source, target) in zip(sourceEffects, targetEffects) {
            guard source.effect.hasSameSurface(as: target.effect) else {
                let fallback = progress >= 1 ? target : source
                contents.appendEffect(fallback.effect, contents: fallback.contents)
                continue
            }

            contents.appendEffect(
                source.effect,
                contents: interpolatedContents(
                    from: source.contents,
                    to: target.contents,
                    progress: progress,
                    transition: transition
                )
            )
        }
    }

    private static func appendEffectItems(
        _ effectItems: [DisplayList.EffectItem],
        into contents: inout DisplayList
    ) {
        for effectItem in effectItems {
            contents.appendEffect(effectItem.effect, contents: effectItem.contents)
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
        progress: Float,
        transition: RBTransition?
    ) -> CGRect? {
        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        if let recordedBounds = interpolatedRecordedBounds(
            from: fromList,
            to: toList,
            progress: clampedProgress,
            transition: transition
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
        progress: CGFloat,
        transition: RBTransition?
    ) -> CGRect? {
        var bounds: CGRect?

        if !fromList.renderItems.isEmpty || !toList.renderItems.isEmpty {
            guard let itemBounds = interpolatedRecordedItemBounds(
                fromItems: fromList.renderItems,
                fromCommands: fromList.itemCommands,
                toItems: toList.renderItems,
                toCommands: toList.itemCommands,
                progress: progress,
                transition: transition,
                allowsCountMismatch: true
            ) else { return nil }
            bounds = union(bounds, itemBounds)
        }

        if !fromList.debugItems.isEmpty || !toList.debugItems.isEmpty {
            guard let debugBounds = interpolatedRecordedItemBounds(
                fromItems: fromList.debugItems,
                fromCommands: fromList.debugItemCommands,
                toItems: toList.debugItems,
                toCommands: toList.debugItemCommands,
                progress: progress,
                transition: nil,
                allowsCountMismatch: false
            ) else { return nil }
            bounds = union(bounds, debugBounds)
        }

        if !fromList.effects.isEmpty || !toList.effects.isEmpty {
            guard let effectBounds = interpolatedRecordedEffectBounds(
                from: fromList.effects,
                to: toList.effects,
                progress: progress,
                transition: transition
            ) else { return nil }
            bounds = union(bounds, effectBounds)
        }

        return bounds
    }

    private static func interpolatedRecordedEffectBounds(
        from sourceEffects: [DisplayList.EffectItem],
        to targetEffects: [DisplayList.EffectItem],
        progress: CGFloat,
        transition: RBTransition?
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
                    progress: progress,
                    transition: transition
                  ) ?? interpolatedBounds(
                    from: source.contents,
                    to: target.contents,
                    progress: Float(progress),
                    transition: transition
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
            fromItems: source.renderItems,
            fromCommands: source.itemCommands,
            toItems: target.renderItems,
            toCommands: target.itemCommands
        ) {
            return true
        }

        if canInterpolateMatchingRecordedItems(
            fromItems: source.debugItems,
            fromCommands: source.debugItemCommands,
            toItems: target.debugItems,
            toCommands: target.debugItemCommands
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
        fromCommands: [DisplayList.ItemCommand],
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand],
        progress: CGFloat,
        transition: RBTransition?,
        allowsCountMismatch: Bool
    ) -> CGRect? {
        guard let operations = itemInterpolationOperations(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands,
            allowsCountMismatch: allowsCountMismatch
        ) else {
            return nil
        }
        return operations.reduce(nil) { partial, operation in
            union(
                partial,
                operation.reportedBounds(
                    at: progress,
                    transition: transition
                )
            )
        }
    }

    private static func union(_ lhs: CGRect?, _ rhs: CGRect?) -> CGRect? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        return lhs.union(rhs)
    }

    private static func canInterpolateRecordedItems(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand]
    ) -> Bool {
        itemInterpolationOperations(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands,
            allowsCountMismatch: true
        ) != nil
    }

    private static func canInterpolateMatchingRecordedItems(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand]
    ) -> Bool {
        itemInterpolationOperations(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands,
            allowsCountMismatch: false
        ) != nil
    }

    private static func itemInterpolationOperations(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand],
        allowsCountMismatch: Bool
    ) -> [ItemInterpolationOperation]? {
        // Current runtime fixtures pin source-order pairing for this reduced carrier. Keeping
        // planning separate lets a future classifier/diff producer replace only this step.
        guard !fromItems.isEmpty,
              !toItems.isEmpty,
              allowsCountMismatch || fromItems.count == toItems.count,
              let sourceInputs = itemInterpolationInputs(
                items: fromItems,
                commands: fromCommands
              ),
              let targetInputs = itemInterpolationInputs(
                items: toItems,
                commands: toCommands
              ) else {
            return nil
        }

        let pairedCount = min(sourceInputs.count, targetInputs.count)
        var operations: [ItemInterpolationOperation] = []
        operations.reserveCapacity(max(sourceInputs.count, targetInputs.count))
        for index in 0..<pairedCount {
            operations.append(.paired(
                source: sourceInputs[index],
                target: targetInputs[index]
            ))
        }
        for input in sourceInputs[pairedCount...] {
            operations.append(.removed(input))
        }
        for input in targetInputs[pairedCount...] {
            operations.append(.inserted(input))
        }
        return operations
    }

    private static func itemInterpolationInputs(
        items: [DisplayList.Item],
        commands: [DisplayList.ItemCommand]
    ) -> [ItemInterpolationInput]? {
        guard commands.count == items.count else { return nil }
        var inputs: [ItemInterpolationInput] = []
        inputs.reserveCapacity(items.count)
        for (item, command) in zip(items, commands) {
            guard let bounds = command.bounds else { return nil }
            inputs.append(ItemInterpolationInput(
                item: item,
                command: command,
                bounds: bounds
            ))
        }
        return inputs
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
              sequencer.mixed != nil else {
            return nil
        }
        guard let delay = sequencerDelay(sequencer, phase: .mixed) else {
            return 1
        }
        return 1 + max(0, delay)
    }

    private var animationSequencerDelayDuration: Double? {
        guard let duration = animationSequencerActiveDuration else {
            return nil
        }
        return max(0, duration - 1)
    }

    private func sequencerDelay(
        _ sequencer: RBAnimationSequencer,
        phase: RBAnimationSequencer.Phase
    ) -> Double? {
        guard let bounds = to.interpolationBounds ?? from.interpolationBounds else {
            return nil
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return sequencer.evalDelay(at: center, phase: phase)
    }

    private var hasChangedDisplayLists: Bool {
        !from.hasSameInterpolationSurface(as: to)
    }

    private var hasDisplayListContents: Bool {
        Self.hasDisplayListContents(from) || Self.hasDisplayListContents(to)
    }

    private static func hasDisplayListContents(_ displayList: DisplayList) -> Bool {
        displayList.interpolationBounds != nil ||
            !displayList.renderItems.isEmpty ||
            !displayList.debugItems.isEmpty ||
            !displayList.effects.isEmpty
    }
}
