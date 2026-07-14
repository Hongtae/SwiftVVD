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

    private struct ItemInterpolationOperation {
        private enum Kind {
            case paired(source: ItemInterpolationInput, target: ItemInterpolationInput)
            case removed(ItemInterpolationInput)
            case inserted(ItemInterpolationInput)
            case wholeRemoved(items: [DisplayList.Item], bounds: CGRect)
            case wholeInserted(items: [DisplayList.Item], bounds: CGRect)
            case fallback(
                sourceItems: [DisplayList.Item],
                sourceBounds: CGRect,
                targetItems: [DisplayList.Item],
                targetBounds: CGRect
            )
        }

        private var kind: Kind
        var animation = RBAnimationSequencer.OperationAnimationRecord(
            animationIndex: 0,
            delay: 0
        )

        static func paired(
            source: ItemInterpolationInput,
            target: ItemInterpolationInput
        ) -> Self {
            Self(kind: .paired(source: source, target: target))
        }

        static func removed(_ source: ItemInterpolationInput) -> Self {
            Self(kind: .removed(source))
        }

        static func inserted(_ target: ItemInterpolationInput) -> Self {
            Self(kind: .inserted(target))
        }

        static func wholeRemoved(items: [DisplayList.Item], bounds: CGRect) -> Self {
            Self(kind: .wholeRemoved(items: items, bounds: bounds))
        }

        static func wholeInserted(items: [DisplayList.Item], bounds: CGRect) -> Self {
            Self(kind: .wholeInserted(items: items, bounds: bounds))
        }

        static func fallback(
            sourceItems: [DisplayList.Item],
            sourceBounds: CGRect,
            targetItems: [DisplayList.Item],
            targetBounds: CGRect
        ) -> Self {
            Self(kind: .fallback(
                sourceItems: sourceItems,
                sourceBounds: sourceBounds,
                targetItems: targetItems,
                targetBounds: targetBounds
            ))
        }

        private var animatedOperationType: UInt8 {
            switch kind {
            case .removed, .wholeRemoved:
                return 0
            case .inserted, .wholeInserted:
                return 1
            case .paired, .fallback:
                return 2
            }
        }

        private var center: CGPoint? {
            let bounds: CGRect
            switch kind {
            case let .paired(_, target), let .inserted(target):
                bounds = target.bounds
            case let .removed(source):
                bounds = source.bounds
            case let .wholeRemoved(_, value), let .wholeInserted(_, value):
                bounds = value
            case let .fallback(_, _, _, targetBounds):
                bounds = targetBounds
            }
            guard !bounds.isNull else { return nil }
            return CGPoint(x: bounds.midX, y: bounds.midY)
        }

        mutating func resolveAnimation(
            table: inout RBAnimationTable,
            defaultAnimationIndex: Int32,
            sequencer: RBAnimationSequencer?
        ) {
            let itemAnimation: RBAnimation?
            switch kind {
            case let .paired(source, target):
                itemAnimation = RBDisplayListInterpolator.animationStyle(
                    from: source.item.styleChain,
                    to: target.item.styleChain
                )
            default:
                itemAnimation = nil
            }

            let resolvedAnimationIndex = itemAnimation.map {
                table.internAnimation($0)
            }
            // Transition animations are not universal secondary sequences. Their ownership
            // depends on the concrete operation family, so this plan resolves only the
            // operation's default or item-style animation.
            let sequencerDelay = center.flatMap {
                sequencer?.evalDelay(
                    at: $0,
                    animatedOperationType: animatedOperationType
                )
            }
            animation = RBAnimationSequencer.operationAnimationRecord(
                operationLowNibble: animatedOperationType,
                resolvedAnimationIndex: resolvedAnimationIndex,
                defaultAnimationIndex: defaultAnimationIndex,
                operationDelay: 0,
                sequencerDelay: sequencerDelay
            )
        }

        func resolvedProgress(at time: Float, table: RBAnimationTable) -> CGFloat {
            CGFloat(table.evaluate(
                animationIndex: animation.animationIndex,
                time: Double(time) - Double(animation.delay)
            ))
        }

        func transitionAnimationContext(
            at time: Float,
            table: RBAnimationTable
        ) -> RBTransitionAnimationContext {
            RBTransitionAnimationContext(
                animationTable: table,
                operation: animation,
                time: time
            )
        }

        func reportedBounds(
            at progress: CGFloat,
            transition: RBTransition?,
            animationContext: RBTransitionAnimationContext? = nil
        ) -> CGRect? {
            switch kind {
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
                    bounds: source.bounds,
                    animationContext: animationContext
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
                    bounds: target.bounds,
                    animationContext: animationContext
                ) else { return target.bounds }
                return visibleBounds(from: results, fallback: target.bounds)
            case let .wholeRemoved(_, bounds), let .wholeInserted(_, bounds):
                // Whole-list lifetime and geometry are separate. The interpolator keeps
                // reporting the non-empty side's geometry even when an event filter or
                // zero-alpha transition suppresses every rendered pixel.
                return bounds
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
            animationContext: RBTransitionAnimationContext? = nil,
            into contents: inout DisplayList
        ) {
            switch kind {
            case let .paired(source, target):
                if let mixedImage = RBDisplayListInterpolator.mixedImageItem(
                    from: source,
                    to: target,
                    progress: progress
                ) {
                    contents.items.append(mixedImage)
                    contents.recordInterpolationBounds(mixedImage.command.bounds)
                    return
                }
                if let mixedShape = RBDisplayListInterpolator.mixedShapeItem(
                    from: source,
                    to: target,
                    progress: progress
                ) {
                    contents.items.append(mixedShape)
                    contents.recordInterpolationBounds(mixedShape.command.bounds)
                    return
                }
                if let mixedShaderShape = RBDisplayListInterpolator.mixedShaderShapeItem(
                    from: source,
                    to: target,
                    progress: progress
                ) {
                    contents.items.append(mixedShaderShape)
                    contents.recordInterpolationBounds(mixedShaderShape.command.bounds)
                    return
                }
                if let mixedGradientShape = RBDisplayListInterpolator.mixedGradientShapeItem(
                    from: source,
                    to: target,
                    progress: progress
                ) {
                    contents.items.append(mixedGradientShape)
                    contents.recordInterpolationBounds(mixedGradientShape.command.bounds)
                    return
                }
                if let mixedMeshGradientShape = RBDisplayListInterpolator.mixedMeshGradientShapeItem(
                    from: source,
                    to: target,
                    progress: progress
                ) {
                    contents.items.append(mixedMeshGradientShape)
                    contents.recordInterpolationBounds(mixedMeshGradientShape.command.bounds)
                    return
                }
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
                    bounds: source.bounds,
                    animationContext: animationContext
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
                    bounds: target.bounds,
                    animationContext: animationContext
                ) else {
                    appendInsertedCrossFade(target, progress: progress, into: &contents)
                    return
                }
                appendTransitionedItem(target, results: results, into: &contents)
            case let .wholeRemoved(items, bounds):
                guard let transition else {
                    appendWholeListCrossFade(
                        sourceItems: items,
                        targetItems: [],
                        bounds: bounds,
                        progress: progress,
                        into: &contents
                    )
                    return
                }
                guard RBDisplayListInterpolator.usesWholeListOpacityEventRouting(transition) else {
                    appendWholeListCrossFade(
                        sourceItems: items,
                        targetItems: [],
                        bounds: bounds,
                        progress: progress,
                        into: &contents
                    )
                    return
                }
                guard !transition.isEmpty(for: 2),
                      let results = transition.effectResults(
                        at: Float(progress),
                        event: 2,
                        bounds: bounds,
                        animationContext: animationContext
                      ) else {
                    return
                }
                appendTransitionedItems(items, bounds: bounds, results: results, into: &contents)
            case let .wholeInserted(items, bounds):
                guard let transition else {
                    appendWholeListCrossFade(
                        sourceItems: [],
                        targetItems: items,
                        bounds: bounds,
                        progress: progress,
                        into: &contents
                    )
                    return
                }
                guard RBDisplayListInterpolator.usesWholeListOpacityEventRouting(transition) else {
                    appendWholeListCrossFade(
                        sourceItems: [],
                        targetItems: items,
                        bounds: bounds,
                        progress: progress,
                        into: &contents
                    )
                    return
                }
                guard !transition.isEmpty(for: 1) else {
                    contents.items.append(contentsOf: items)
                    return
                }
                guard let results = transition.effectResults(
                    at: Float(progress),
                    event: 1,
                    bounds: bounds,
                    animationContext: animationContext
                ) else {
                    return
                }
                appendTransitionedItems(items, bounds: bounds, results: results, into: &contents)
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
            appendTransitionedItems(
                [input.item],
                bounds: input.bounds,
                results: results,
                into: &contents
            )
        }

        private func appendTransitionedItems(
            _ items: [DisplayList.Item],
            bounds: CGRect,
            results: RBTransitionEffectResults,
            into contents: inout DisplayList
        ) {
            guard results.alpha > 0 else { return }

            var resolved = DisplayList()
            resolved.items = items
            resolved.interpolationBounds = bounds
            var resolvedBounds = bounds

            if !results.transform.isIdentity {
                var transformed = DisplayList()
                for item in resolved.items {
                    transformed.appendTransformedItem(
                        item,
                        affineTransform: results.transform
                    )
                }
                resolved = transformed
                resolvedBounds = bounds.applying(results.transform).standardized
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

        private func appendWholeListCrossFade(
            sourceItems: [DisplayList.Item],
            targetItems: [DisplayList.Item],
            bounds: CGRect,
            progress: CGFloat,
            into contents: inout DisplayList
        ) {
            contents.appendCrossFadeItem(
                sourceItems: sourceItems,
                sourceBounds: sourceItems.isEmpty ? nil : bounds,
                sourceOutputBounds: sourceItems.isEmpty ? nil : bounds,
                targetItems: targetItems,
                targetBounds: targetItems.isEmpty ? nil : bounds,
                targetOutputBounds: targetItems.isEmpty ? nil : bounds,
                bounds: bounds,
                sourceFraction: Float(progress),
                targetFraction: Float(progress)
            )
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

    private struct ItemOperationPlan {
        var operations: [ItemInterpolationOperation]
        var animationTable: RBAnimationTable

        var activeDuration: Double {
            operations.reduce(0) { duration, operation in
                max(
                    duration,
                    Double(operation.animation.delay) + animationTable.maximumDuration(
                        animationIndex: operation.animation.animationIndex
                    )
                )
            }
        }

        func maximumSpeed(at time: Double) -> Double {
            // Sequencer delay shifts presentation progress, but the velocity query samples
            // animation time directly from the caller's elapsed time.
            operations.reduce(0) { speed, operation in
                max(
                    speed,
                    animationTable.maxSpeed(
                        animationIndex: operation.animation.animationIndex,
                        time: time
                    )
                )
            }
        }
    }

    var from: DisplayList
    private(set) var to: DisplayList
    let options: [RBDisplayListInterpolatorOptionKey: Any]
    private var cachedItemOperationPlan: ItemOperationPlan?
    private var hasCachedItemOperationPlan = false

    init(
        from: DisplayList,
        to: DisplayList,
        options: [RBDisplayListInterpolatorOptionKey: Any] = [:]
    ) {
        self.from = from
        self.to = to
        self.options = options
        self.cachedItemOperationPlan = nil
        super.init()
    }

    var activeDuration: Double {
        guard hasChangedDisplayLists else {
            return 0
        }
        if isImmediateWholeListInsertion {
            return 0
        }
        if let itemOperationPlan = itemOperationPlan() {
            return itemOperationPlan.activeDuration
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
        invalidateItemOperationPlan()
    }

    func setTo(_ displayList: DisplayList) {
        to = displayList
        invalidateItemOperationPlan()
    }

    func boundingRect(withProgress progress: Float) -> CGRect {
        interpolatedBounds(at: progress) ?? .null
    }

    func maxAbsoluteVelocity(withProgress progress: Float) -> Double {
        guard hasChangedDisplayLists,
              let bounds = Self.unionBounds(from: from, to: to) else {
            return 0
        }
        let boundsSize = max(bounds.width, bounds.height)
        guard boundsSize.isFinite, boundsSize > 0 else { return 0 }
        if let itemOperationPlan = itemOperationPlan() {
            return itemOperationPlan.maximumSpeed(at: Double(progress)) * Double(boundsSize)
        }
        guard let animation = checkedAnimationOption() else { return 0 }
        return animation.speed(atTime: Double(progress)) * Double(boundsSize)
    }

    func copyContents(withProgress progress: Float) -> DisplayList {
        if progress >= Float(activeDuration) {
            if shouldMaterializeEndpointContents {
                return interpolatedContents(at: progress)
            }
            return to
        }
        if progress <= 0 {
            if shouldMaterializeEndpointContents {
                return interpolatedContents(at: 0)
            }
            return from
        }
        return interpolatedContents(at: progress)
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
        if let plan = itemOperationPlan(), !plan.operations.isEmpty {
            var bounds = plan.operations.reduce(nil) { partial, operation in
                Self.union(
                    partial,
                    operation.reportedBounds(
                        at: operation.resolvedProgress(
                            at: time,
                            table: plan.animationTable
                        ),
                        transition: transition,
                        animationContext: operation.transitionAnimationContext(
                            at: time,
                            table: plan.animationTable
                        )
                    )
                )
            }
            let auxiliaryProgress = CGFloat(min(max(resolvedProgress(at: time), 0), 1))
            if !from.debugItems.isEmpty || !to.debugItems.isEmpty {
                bounds = Self.union(
                    bounds,
                    Self.interpolatedRecordedItemBounds(
                        fromItems: from.debugItems,
                        fromCommands: from.debugItemCommands,
                        toItems: to.debugItems,
                        toCommands: to.debugItemCommands,
                        progress: auxiliaryProgress,
                        transition: nil,
                        allowsCountMismatch: false,
                        allowsWholeListOperations: false
                    )
                )
            }
            if !from.effects.isEmpty || !to.effects.isEmpty {
                bounds = Self.union(
                    bounds,
                    Self.interpolatedRecordedEffectBounds(
                        from: from.effects,
                        to: to.effects,
                        progress: auxiliaryProgress,
                        transition: transition
                    )
                )
            }
            return bounds
        }
        return Self.interpolatedBounds(
            from: from,
            to: to,
            progress: resolvedProgress(at: time),
            transition: transition
        )
    }

    private func interpolatedContents(at time: Float) -> DisplayList {
        guard let nonEmptyBounds = from.interpolationBounds ?? to.interpolationBounds,
              let outputBounds = interpolatedBounds(at: time) else {
            return from
        }
        let fromBounds = from.interpolationBounds ?? nonEmptyBounds
        let toBounds = to.interpolationBounds ?? nonEmptyBounds
        let auxiliaryProgress = CGFloat(min(max(resolvedProgress(at: time), 0), 1))
        var contents = DisplayList()
        contents.interpolationBounds = outputBounds

        if let plan = itemOperationPlan(), !plan.operations.isEmpty {
            for operation in plan.operations {
                operation.append(
                    at: operation.resolvedProgress(at: time, table: plan.animationTable),
                    transition: transition,
                    animationContext: operation.transitionAnimationContext(
                        at: time,
                        table: plan.animationTable
                    ),
                    into: &contents
                )
            }
        } else if !from.renderItems.isEmpty || !to.renderItems.isEmpty {
            Self.appendInterpolatedItems(
                fromItems: from.renderItems,
                fromCommands: from.itemCommands,
                fromFallbackBounds: fromBounds,
                toItems: to.renderItems,
                toCommands: to.itemCommands,
                toFallbackBounds: toBounds,
                allowsWholeListOperations: Self.allowsWholeListOperations(from: from, to: to),
                progress: auxiliaryProgress,
                transition: transition,
                into: &contents
            )
        }

        if !from.debugItems.isEmpty || !to.debugItems.isEmpty {
            Self.appendInterpolatedDebugItems(
                fromItems: from.debugItems,
                fromCommands: from.debugItemCommands,
                fromFallbackBounds: fromBounds,
                toItems: to.debugItems,
                toCommands: to.debugItemCommands,
                toFallbackBounds: toBounds,
                outputFallbackBounds: outputBounds,
                progress: auxiliaryProgress,
                into: &contents
            )
        }

        Self.appendInterpolatedEffects(
            from: from.effects,
            to: to.effects,
            progress: Float(auxiliaryProgress),
            transition: transition,
            into: &contents
        )
        contents.interpolationBounds = outputBounds
        return contents
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
        guard let nonEmptyBounds = from.interpolationBounds ?? to.interpolationBounds else {
            return from
        }
        let fromBounds = from.interpolationBounds ?? nonEmptyBounds
        let toBounds = to.interpolationBounds ?? nonEmptyBounds
        guard let outputBounds = interpolatedBounds(
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
                allowsWholeListOperations: allowsWholeListOperations(from: from, to: to),
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

        contents.interpolationBounds = outputBounds
        return contents
    }

    private static func appendInterpolatedItems(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        fromFallbackBounds: CGRect,
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand],
        toFallbackBounds: CGRect,
        allowsWholeListOperations: Bool,
        progress: CGFloat,
        transition: RBTransition?,
        into contents: inout DisplayList
    ) {
        let operations = itemInterpolationOperations(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands,
            allowsCountMismatch: true,
            allowsWholeListOperations: allowsWholeListOperations
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

    private static func mixedImageItem(
        from source: ItemInterpolationInput,
        to target: ItemInterpolationInput,
        progress: CGFloat
    ) -> DisplayList.Item? {
        guard case let .content(sourceContent) = source.item.value,
              case let .image(sourceImage) = sourceContent.value,
              case let .content(targetContent) = target.item.value,
              case let .image(targetImage) = targetContent.value,
              case let .image(sourceRecord, _) = source.command,
              case let .image(targetRecord, _) = target.command,
              sourceRecord.textureID != nil,
              imageRecordsMatchExceptShading(sourceRecord, targetRecord),
              sourceImage.frame == sourceRecord.placementRect,
              targetImage.frame == targetRecord.placementRect,
              let shadingMix = interpolatedImageShading(
                from: sourceRecord,
                to: targetRecord,
                progress: progress
              ),
              source.item.styleChain == target.item.styleChain else {
            return nil
        }
        if progress == 0 { return source.item }
        if progress == 1 { return target.item }

        let bounds = interpolatedBounds(
            from: source.bounds,
            to: target.bounds,
            progress: progress
        )
        let placementRect = interpolatedBounds(
            from: sourceRecord.placementRect,
            to: targetRecord.placementRect,
            progress: progress
        )
        var mixedRecord = sourceRecord
        mixedRecord.placementRect = placementRect
        mixedRecord.hasShading = shadingMix.shading != nil
        mixedRecord.shading = shadingMix.record
        let command = DisplayList.ItemCommand.image(mixedRecord, bounds: bounds)
        var content = sourceContent
        var image = sourceImage.image
        image.shading = shadingMix.shading
        content.value = .image(DisplayList.Content.ImageValue(
            image: image,
            frame: placementRect,
            transform: interpolatedTransform(
                from: sourceImage.transform,
                to: targetImage.transform,
                progress: progress
            ),
            command: command
        ))
        return DisplayList.Item(
            content: content,
            frame: bounds,
            identity: source.item.identity,
            version: source.item.version,
            opacity: interpolatedItemOpacity(
                from: source.item,
                to: target.item,
                progress: progress
            ),
            styleChain: source.item.styleChain
        )
    }

    private struct ImageShadingMix {
        var shading: GraphicsContext.Shading?
        var record: DisplayList.ItemRecord.ShadingRecord?
    }

    private static func imageRecordsMatchExceptShading(
        _ source: DisplayList.ItemRecord.ImageRecord,
        _ target: DisplayList.ItemRecord.ImageRecord
    ) -> Bool {
        source.baseline == target.baseline &&
            source.textureID == target.textureID &&
            source.textureTransform == target.textureTransform &&
            source.scaleFactor == target.scaleFactor
    }

    private static func interpolatedImageShading(
        from source: DisplayList.ItemRecord.ImageRecord,
        to target: DisplayList.ItemRecord.ImageRecord,
        progress: CGFloat
    ) -> ImageShadingMix? {
        let sourceTint: Color?
        switch (source.hasShading, source.shading) {
        case (false, _):
            sourceTint = nil
        case let (true, .some(.color(color))):
            sourceTint = color
        case (true, .none):
            return nil
        }

        let targetTint: Color?
        switch (target.hasShading, target.shading) {
        case (false, _):
            targetTint = nil
        case let (true, .some(.color(color))):
            targetTint = color
        case (true, .none):
            return nil
        }

        guard sourceTint != nil || targetTint != nil else {
            return ImageShadingMix(shading: nil, record: nil)
        }
        if let sourceTint, let targetTint,
           sourceTint.provider.colorSpace != targetTint.provider.colorSpace {
            return nil
        }
        let colorSpace = sourceTint?.provider.colorSpace ??
            targetTint?.provider.colorSpace ?? .sRGB
        let identityTint = Color(colorSpace, white: 1)
        guard let tint = interpolatedGradientColor(
            from: sourceTint ?? identityTint,
            to: targetTint ?? identityTint,
            progress: progress
        ) else {
            return nil
        }
        return ImageShadingMix(
            shading: .color(tint),
            record: .color(tint)
        )
    }

    private static func mixedShapeItem(
        from source: ItemInterpolationInput,
        to target: ItemInterpolationInput,
        progress: CGFloat
    ) -> DisplayList.Item? {
        guard case let .content(sourceContent) = source.item.value,
              case let .shape(sourceShape) = sourceContent.value,
              case let .content(targetContent) = target.item.value,
              case let .shape(targetShape) = targetContent.value,
              case let .shape(
                sourceRole,
                .some(.color(sourceColor)),
                sourceFillStyle,
                sourceStrokeStyle,
                _
              ) = source.command,
              case let .shape(
                targetRole,
                .some(.color(targetColor)),
                targetFillStyle,
                targetStrokeStyle,
                _
              ) = target.command,
              sourceRole == targetRole,
              sourceFillStyle == targetFillStyle,
              sourceStrokeStyle == targetStrokeStyle,
              sourceShape.fillStyle == targetShape.fillStyle,
              sourceShape.strokeStyle == targetShape.strokeStyle,
              (sourceRole == .stroke) == (sourceStrokeStyle != nil),
              source.item.styleChain == target.item.styleChain,
              sameSingleColor(sourceShape.shading, sourceColor),
              sameSingleColor(targetShape.shading, targetColor),
              let mixedColor = interpolatedShapeColor(
                from: sourceColor,
                to: targetColor,
                progress: progress
              ),
              let path = interpolatedPath(
                from: sourceShape.path,
                to: targetShape.path,
                progress: progress
              ) else {
            return nil
        }
        if progress == 0 { return source.item }
        if progress == 1 { return target.item }

        let bounds = interpolatedBounds(
            from: source.bounds,
            to: target.bounds,
            progress: progress
        )
        let command = DisplayList.ItemCommand.shape(
            role: sourceRole,
            style: .color(mixedColor),
            fillStyle: sourceFillStyle,
            strokeStyle: sourceStrokeStyle,
            bounds: bounds
        )
        var content = sourceContent
        content.value = .shape(DisplayList.Content.ShapeValue(
            path: path,
            shading: .color(mixedColor),
            fillStyle: sourceShape.fillStyle,
            strokeStyle: sourceShape.strokeStyle,
            transform: interpolatedTransform(
                from: sourceShape.transform,
                to: targetShape.transform,
                progress: progress
            ),
            command: command
        ))
        return DisplayList.Item(
            content: content,
            frame: bounds,
            identity: source.item.identity,
            version: source.item.version,
            opacity: interpolatedItemOpacity(
                from: source.item,
                to: target.item,
                progress: progress
            ),
            styleChain: source.item.styleChain
        )
    }

    private static func interpolatedShapeColor(
        from source: Color,
        to target: Color,
        progress: CGFloat
    ) -> Color? {
        if source == target { return source }
        guard let sourceLinear = linearSRGBComponents(of: source),
              let targetLinear = linearSRGBComponents(of: target),
              source.provider.alpha.isFinite,
              target.provider.alpha.isFinite else {
            return nil
        }

        let sourceAlpha = source.provider.alpha
        let targetAlpha = target.provider.alpha
        let fraction = Double(progress)
        let mixedAlpha = sourceAlpha + (targetAlpha - sourceAlpha) * fraction
        let sourceLab = oklabComponents(fromLinearSRGB: sourceLinear)
        let targetLab = oklabComponents(fromLinearSRGB: targetLinear)
        let mixedLab: SIMD3<Double>
        if sourceAlpha == targetAlpha {
            mixedLab = sourceLab + (targetLab - sourceLab) * fraction
        } else {
            let premultiplied = sourceLab * sourceAlpha
                + (targetLab * targetAlpha - sourceLab * sourceAlpha) * fraction
            if mixedAlpha == 0 || mixedAlpha == 1 {
                mixedLab = premultiplied
            } else {
                mixedLab = premultiplied / mixedAlpha
            }
        }

        let linearSRGB = linearSRGBComponents(fromOklab: mixedLab)
        let output = encodedComponents(
            linearSRGB,
            in: source.provider.colorSpace
        )
        return Color(
            source.provider.colorSpace,
            red: output.x,
            green: output.y,
            blue: output.z,
            opacity: mixedAlpha
        )
    }

    private static func mixedShaderShapeItem(
        from source: ItemInterpolationInput,
        to target: ItemInterpolationInput,
        progress: CGFloat
    ) -> DisplayList.Item? {
        guard case let .content(sourceContent) = source.item.value,
              case let .shape(sourceShape) = sourceContent.value,
              case let .content(targetContent) = target.item.value,
              case let .shape(targetShape) = targetContent.value,
              case let .shape(
                sourceRole,
                .some(.shader(sourceShader)),
                sourceFillStyle,
                sourceStrokeStyle,
                _
              ) = source.command,
              case let .shape(
                targetRole,
                .some(.shader(targetShader)),
                targetFillStyle,
                targetStrokeStyle,
                _
              ) = target.command,
              sourceRole == targetRole,
              sourceFillStyle == targetFillStyle,
              sourceStrokeStyle == targetStrokeStyle,
              sourceShape.fillStyle == targetShape.fillStyle,
              sourceShape.strokeStyle == targetShape.strokeStyle,
              (sourceRole == .stroke) == (sourceStrokeStyle != nil),
              source.item.styleChain == target.item.styleChain,
              let mixedShader = interpolatedShader(
                from: sourceShader,
                to: targetShader,
                progress: progress
              ),
              let shader = mixedShader.shader,
              let path = interpolatedPath(
                from: sourceShape.path,
                to: targetShape.path,
                progress: progress
              ) else {
            return nil
        }
        if progress == 0 { return source.item }
        if progress == 1 { return target.item }

        let bounds = interpolatedBounds(
            from: source.bounds,
            to: target.bounds,
            progress: progress
        )
        let command = DisplayList.ItemCommand.shape(
            role: sourceRole,
            style: .shader(mixedShader),
            fillStyle: sourceFillStyle,
            strokeStyle: sourceStrokeStyle,
            bounds: bounds
        )
        var content = sourceContent
        content.value = .shape(DisplayList.Content.ShapeValue(
            path: path,
            shading: .shader(shader, bounds: .null),
            fillStyle: sourceShape.fillStyle,
            strokeStyle: sourceShape.strokeStyle,
            transform: interpolatedTransform(
                from: sourceShape.transform,
                to: targetShape.transform,
                progress: progress
            ),
            command: command
        ))
        return DisplayList.Item(
            content: content,
            frame: bounds,
            identity: source.item.identity,
            version: source.item.version,
            opacity: interpolatedItemOpacity(
                from: source.item,
                to: target.item,
                progress: progress
            ),
            styleChain: source.item.styleChain
        )
    }

    private static func interpolatedShader(
        from source: Shader.ResolvedShader,
        to target: Shader.ResolvedShader,
        progress: CGFloat
    ) -> Shader.ResolvedShader? {
        guard let sourceValue = source.shader,
              let targetValue = target.shader,
              sourceValue.function == targetValue.function,
              source.options == target.options,
              source.maxSampleOffset == target.maxSampleOffset,
              shaderArgumentsAreInterpolationCompatible(
                sourceValue.arguments,
                targetValue.arguments
              ) else {
            return nil
        }
        var result = source
        result.animatableData.interpolate(
            towards: target.animatableData,
            amount: Double(progress)
        )
        return result
    }

    private static func shaderArgumentsAreInterpolationCompatible(
        _ source: [Shader.Argument],
        _ target: [Shader.Argument]
    ) -> Bool {
        guard source.count == target.count else { return false }
        return zip(source, target).allSatisfy { source, target in
            switch (source.storage, target.storage) {
            case (.float, .float),
                 (.float2, .float2),
                 (.float3, .float3),
                 (.float4, .float4),
                 (.boundsRect, .boundsRect):
                return true
            case let (.floatArray(source), .floatArray(target)):
                return source.count == target.count
            case (.color, .color),
                 (.resolvedColor, .resolvedColor),
                 (.color, .resolvedColor),
                 (.resolvedColor, .color):
                return true
            case let (.colorArray(source), .colorArray(target)):
                return source.count == target.count
            case let (.image(source), .image(target)):
                return source == target
            case let (.data(source), .data(target)):
                return source == target
            default:
                return false
            }
        }
    }

    private static func mixedGradientShapeItem(
        from source: ItemInterpolationInput,
        to target: ItemInterpolationInput,
        progress: CGFloat
    ) -> DisplayList.Item? {
        guard case let .content(sourceContent) = source.item.value,
              case let .shape(sourceShape) = sourceContent.value,
              case let .content(targetContent) = target.item.value,
              case let .shape(targetShape) = targetContent.value,
              case let .shape(
                sourceRole,
                .some(.gradient(sourceCommandGradient)),
                sourceFillStyle,
                sourceStrokeStyle,
                _
              ) = source.command,
              case let .shape(
                targetRole,
                .some(.gradient(targetCommandGradient)),
                targetFillStyle,
                targetStrokeStyle,
                _
              ) = target.command,
              sourceRole == targetRole,
              sourceFillStyle == targetFillStyle,
              sourceStrokeStyle == targetStrokeStyle,
              sourceShape.fillStyle == targetShape.fillStyle,
              sourceShape.strokeStyle == targetShape.strokeStyle,
              (sourceRole == .stroke) == (sourceStrokeStyle != nil),
              source.item.styleChain == target.item.styleChain,
              let sourceGradientShading = singleGradientShading(sourceShape.shading),
              let targetGradientShading = singleGradientShading(targetShape.shading),
              sourceCommandGradient == sourceGradientShading.gradient,
              targetCommandGradient == targetGradientShading.gradient,
              let mixedGradientShading = interpolatedGradientShading(
                from: sourceGradientShading,
                to: targetGradientShading,
                progress: progress
              ),
              let path = interpolatedPath(
                from: sourceShape.path,
                to: targetShape.path,
                progress: progress
              ) else {
            return nil
        }
        if progress == 0 { return source.item }
        if progress == 1 { return target.item }

        let bounds = interpolatedBounds(
            from: source.bounds,
            to: target.bounds,
            progress: progress
        )
        let command = DisplayList.ItemCommand.shape(
            role: sourceRole,
            style: .gradient(mixedGradientShading.gradient),
            fillStyle: sourceFillStyle,
            strokeStyle: sourceStrokeStyle,
            bounds: bounds
        )
        var content = sourceContent
        content.value = .shape(DisplayList.Content.ShapeValue(
            path: path,
            shading: mixedGradientShading.shading,
            fillStyle: sourceShape.fillStyle,
            strokeStyle: sourceShape.strokeStyle,
            transform: interpolatedTransform(
                from: sourceShape.transform,
                to: targetShape.transform,
                progress: progress
            ),
            command: command
        ))
        return DisplayList.Item(
            content: content,
            frame: bounds,
            identity: source.item.identity,
            version: source.item.version,
            opacity: interpolatedItemOpacity(
                from: source.item,
                to: target.item,
                progress: progress
            ),
            styleChain: source.item.styleChain
        )
    }

    private static func mixedMeshGradientShapeItem(
        from source: ItemInterpolationInput,
        to target: ItemInterpolationInput,
        progress: CGFloat
    ) -> DisplayList.Item? {
        guard case let .content(sourceContent) = source.item.value,
              case let .shape(sourceShape) = sourceContent.value,
              case let .content(targetContent) = target.item.value,
              case let .shape(targetShape) = targetContent.value,
              case let .shape(
                sourceRole,
                .some(.meshGradient(sourceCommandMesh)),
                sourceFillStyle,
                sourceStrokeStyle,
                _
              ) = source.command,
              case let .shape(
                targetRole,
                .some(.meshGradient(targetCommandMesh)),
                targetFillStyle,
                targetStrokeStyle,
                _
              ) = target.command,
              sourceRole == targetRole,
              sourceFillStyle == targetFillStyle,
              sourceStrokeStyle == targetStrokeStyle,
              sourceShape.fillStyle == targetShape.fillStyle,
              sourceShape.strokeStyle == targetShape.strokeStyle,
              (sourceRole == .stroke) == (sourceStrokeStyle != nil),
              source.item.styleChain == target.item.styleChain,
              let sourceMesh = singleMeshGradientShading(sourceShape.shading),
              let targetMesh = singleMeshGradientShading(targetShape.shading),
              sourceCommandMesh == sourceMesh,
              targetCommandMesh == targetMesh,
              let mixedMesh = interpolatedMeshGradient(
                from: sourceMesh,
                sourceEnvironment: sourceContent.environment ?? EnvironmentValues(),
                to: targetMesh,
                targetEnvironment: targetContent.environment ?? EnvironmentValues(),
                progress: progress
              ),
              let path = interpolatedPath(
                from: sourceShape.path,
                to: targetShape.path,
                progress: progress
              ) else {
            return nil
        }
        if progress == 0 { return source.item }
        if progress == 1 { return target.item }

        let bounds = interpolatedBounds(
            from: source.bounds,
            to: target.bounds,
            progress: progress
        )
        let command = DisplayList.ItemCommand.shape(
            role: sourceRole,
            style: .meshGradient(mixedMesh),
            fillStyle: sourceFillStyle,
            strokeStyle: sourceStrokeStyle,
            bounds: bounds
        )
        var content = sourceContent
        content.value = .shape(DisplayList.Content.ShapeValue(
            path: path,
            shading: .meshGradient(mixedMesh),
            fillStyle: sourceShape.fillStyle,
            strokeStyle: sourceShape.strokeStyle,
            transform: interpolatedTransform(
                from: sourceShape.transform,
                to: targetShape.transform,
                progress: progress
            ),
            command: command
        ))
        return DisplayList.Item(
            content: content,
            frame: bounds,
            identity: source.item.identity,
            version: source.item.version,
            opacity: interpolatedItemOpacity(
                from: source.item,
                to: target.item,
                progress: progress
            ),
            styleChain: source.item.styleChain
        )
    }

    private static func singleMeshGradientShading(
        _ shading: GraphicsContext.Shading
    ) -> MeshGradient? {
        guard shading.properties.count == 1 else { return nil }
        switch shading.properties[0] {
        case let .meshGradient(mesh):
            return mesh
        case let .style(style):
            if let mesh = style as? MeshGradient {
                return mesh
            }
            if let erased = style as? AnyShapeStyle {
                return singleMeshGradientStyle(erased.storage.box.style)
            }
            return nil
        default:
            return nil
        }
    }

    private static func singleMeshGradientStyle(
        _ style: any ShapeStyle
    ) -> MeshGradient? {
        if let mesh = style as? MeshGradient {
            return mesh
        }
        if let erased = style as? AnyShapeStyle {
            return singleMeshGradientStyle(erased.storage.box.style)
        }
        return nil
    }

    private static func interpolatedMeshGradient(
        from source: MeshGradient,
        sourceEnvironment: EnvironmentValues,
        to target: MeshGradient,
        targetEnvironment: EnvironmentValues,
        progress: CGFloat
    ) -> MeshGradient? {
        guard source.width == target.width,
              source.height == target.height,
              source.smoothsColors == target.smoothsColors,
              source.colorSpace == target.colorSpace,
              source.width > 1,
              source.height > 1,
              source.width <= Int.max / source.height else {
            return nil
        }
        let count = source.width * source.height
        let locations: MeshGradient.Locations
        switch (source.locations, target.locations) {
        case let (.points(sourcePoints), .points(targetPoints)):
            guard sourcePoints.count == count, targetPoints.count == count else {
                return nil
            }
            locations = .points(zip(sourcePoints, targetPoints).map {
                interpolatedMeshPoint(from: $0, to: $1, progress: progress)
            })
        case let (.bezierPoints(sourcePoints), .bezierPoints(targetPoints)):
            guard sourcePoints.count == count, targetPoints.count == count else {
                return nil
            }
            locations = .bezierPoints(zip(sourcePoints, targetPoints).map {
                MeshGradient.BezierPoint(
                    position: interpolatedMeshPoint(
                        from: $0.position,
                        to: $1.position,
                        progress: progress
                    ),
                    leadingControlPoint: interpolatedMeshPoint(
                        from: $0.leadingControlPoint,
                        to: $1.leadingControlPoint,
                        progress: progress
                    ),
                    topControlPoint: interpolatedMeshPoint(
                        from: $0.topControlPoint,
                        to: $1.topControlPoint,
                        progress: progress
                    ),
                    trailingControlPoint: interpolatedMeshPoint(
                        from: $0.trailingControlPoint,
                        to: $1.trailingControlPoint,
                        progress: progress
                    ),
                    bottomControlPoint: interpolatedMeshPoint(
                        from: $0.bottomControlPoint,
                        to: $1.bottomControlPoint,
                        progress: progress
                    )
                )
            })
        default:
            return nil
        }

        let sourceColors = resolvedMeshColors(source.colors, environment: sourceEnvironment)
        let targetColors = resolvedMeshColors(target.colors, environment: targetEnvironment)
        guard sourceColors.count == count, targetColors.count == count else {
            return nil
        }
        let colors = zip(sourceColors, targetColors).map {
            interpolatedMeshColor(from: $0, to: $1, progress: progress)
        }
        let background = interpolatedMeshColor(
            from: source.background.resolve(in: sourceEnvironment),
            to: target.background.resolve(in: targetEnvironment),
            progress: progress
        )
        return MeshGradient(
            width: source.width,
            height: source.height,
            locations: locations,
            colors: .resolvedColors(colors),
            background: Color(background),
            smoothsColors: source.smoothsColors,
            colorSpace: source.colorSpace
        )
    }

    private static func resolvedMeshColors(
        _ colors: MeshGradient.Colors,
        environment: EnvironmentValues
    ) -> [Color.Resolved] {
        switch colors {
        case let .colors(colors):
            return colors.map { $0.resolve(in: environment) }
        case let .resolvedColors(colors):
            return colors
        }
    }

    private static func interpolatedMeshPoint(
        from source: SIMD2<Float>,
        to target: SIMD2<Float>,
        progress: CGFloat
    ) -> SIMD2<Float> {
        source + (target - source) * Float(progress)
    }

    private static func interpolatedMeshColor(
        from source: Color.Resolved,
        to target: Color.Resolved,
        progress: CGFloat
    ) -> Color.Resolved {
        let progress = Float(progress)
        return Color.Resolved(
            colorSpace: .sRGBLinear,
            red: source.linearRed + (target.linearRed - source.linearRed) * progress,
            green: source.linearGreen + (target.linearGreen - source.linearGreen) * progress,
            blue: source.linearBlue + (target.linearBlue - source.linearBlue) * progress,
            opacity: source.opacity + (target.opacity - source.opacity) * progress
        )
    }

    private static func interpolatedItemOpacity(
        from source: DisplayList.Item,
        to target: DisplayList.Item,
        progress: CGFloat
    ) -> Float {
        source.opacity + (target.opacity - source.opacity) * Float(progress)
    }

    private enum GradientShadingPayload {
        case linear(
            gradient: Gradient,
            startPoint: CGPoint,
            endPoint: CGPoint,
            options: GraphicsContext.GradientOptions
        )
        case radial(
            gradient: Gradient,
            center: CGPoint,
            startRadius: CGFloat,
            endRadius: CGFloat,
            options: GraphicsContext.GradientOptions
        )
        case conic(
            gradient: Gradient,
            center: CGPoint,
            angle: Angle,
            options: GraphicsContext.GradientOptions
        )

        var gradient: Gradient {
            switch self {
            case let .linear(gradient, _, _, _),
                 let .radial(gradient, _, _, _, _),
                 let .conic(gradient, _, _, _):
                return gradient
            }
        }
    }

    private static func singleGradientShading(
        _ shading: GraphicsContext.Shading
    ) -> GradientShadingPayload? {
        guard shading.properties.count == 1 else { return nil }
        switch shading.properties[0] {
        case let .linearGradient(gradient, startPoint, endPoint, options):
            return .linear(
                gradient: gradient,
                startPoint: startPoint,
                endPoint: endPoint,
                options: options
            )
        case let .radialGradient(gradient, center, startRadius, endRadius, options):
            return .radial(
                gradient: gradient,
                center: center,
                startRadius: startRadius,
                endRadius: endRadius,
                options: options
            )
        case let .conicGradient(gradient, center, angle, options):
            return .conic(
                gradient: gradient,
                center: center,
                angle: angle,
                options: options
            )
        default:
            return nil
        }
    }

    private static func interpolatedGradientShading(
        from source: GradientShadingPayload,
        to target: GradientShadingPayload,
        progress: CGFloat
    ) -> (gradient: Gradient, shading: GraphicsContext.Shading)? {
        switch (source, target) {
        case let (
            .linear(sourceGradient, sourceStart, sourceEnd, sourceOptions),
            .linear(targetGradient, targetStart, targetEnd, targetOptions)
        ):
            guard sourceOptions == targetOptions,
                  let gradient = interpolatedGradient(
                    from: sourceGradient,
                    to: targetGradient,
                    progress: progress
                  ) else {
                return nil
            }
            return (
                gradient,
                .linearGradient(
                    gradient,
                    startPoint: interpolatedPoint(
                        from: sourceStart,
                        to: targetStart,
                        progress: progress
                    ),
                    endPoint: interpolatedPoint(
                        from: sourceEnd,
                        to: targetEnd,
                        progress: progress
                    ),
                    options: sourceOptions
                )
            )
        case let (
            .radial(
                sourceGradient,
                sourceCenter,
                sourceStartRadius,
                sourceEndRadius,
                sourceOptions
            ),
            .radial(
                targetGradient,
                targetCenter,
                targetStartRadius,
                targetEndRadius,
                targetOptions
            )
        ):
            guard sourceOptions == targetOptions,
                  let gradient = interpolatedGradient(
                    from: sourceGradient,
                    to: targetGradient,
                    progress: progress
                  ) else {
                return nil
            }
            return (
                gradient,
                .radialGradient(
                    gradient,
                    center: interpolatedPoint(
                        from: sourceCenter,
                        to: targetCenter,
                        progress: progress
                    ),
                    startRadius: interpolate(
                        sourceStartRadius,
                        targetStartRadius,
                        by: progress
                    ),
                    endRadius: interpolate(
                        sourceEndRadius,
                        targetEndRadius,
                        by: progress
                    ),
                    options: sourceOptions
                )
            )
        case let (
            .conic(sourceGradient, sourceCenter, sourceAngle, sourceOptions),
            .conic(targetGradient, targetCenter, targetAngle, targetOptions)
        ):
            guard sourceOptions == targetOptions,
                  let gradient = interpolatedGradient(
                    from: sourceGradient,
                    to: targetGradient,
                    progress: progress
                  ) else {
                return nil
            }
            return (
                gradient,
                .conicGradient(
                    gradient,
                    center: interpolatedPoint(
                        from: sourceCenter,
                        to: targetCenter,
                        progress: progress
                    ),
                    angle: Angle(radians: interpolate(
                        sourceAngle.radians,
                        targetAngle.radians,
                        by: progress
                    )),
                    options: sourceOptions
                )
            )
        default:
            return nil
        }
    }

    private static func interpolatedGradient(
        from source: Gradient,
        to target: Gradient,
        progress: CGFloat
    ) -> Gradient? {
        let sourceStops = source.stops.sorted { $0.location < $1.location }
        let targetStops = target.stops.sorted { $0.location < $1.location }
        guard !sourceStops.isEmpty,
              !targetStops.isEmpty,
              sourceStops.allSatisfy({ $0.location.isFinite }),
              targetStops.allSatisfy({ $0.location.isFinite }) else {
            return nil
        }

        if sourceStops.count == targetStops.count {
            var stops: [Gradient.Stop] = []
            stops.reserveCapacity(sourceStops.count)
            for (sourceStop, targetStop) in zip(sourceStops, targetStops) {
                guard let color = interpolatedGradientColor(
                    from: sourceStop.color,
                    to: targetStop.color,
                    progress: progress
                ) else {
                    return nil
                }
                stops.append(Gradient.Stop(
                    color: color,
                    location: interpolate(
                        sourceStop.location,
                        targetStop.location,
                        by: progress
                    )
                ))
            }
            return Gradient(stops: stops)
        }

        var locations = (sourceStops.map(\.location) + targetStops.map(\.location)).sorted()
        locations = locations.enumerated().compactMap { index, location in
            index == 0 || location != locations[index - 1] ? location : nil
        }
        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(locations.count)
        for location in locations {
            guard let sourceColor = gradientColor(in: sourceStops, at: location),
                  let targetColor = gradientColor(in: targetStops, at: location),
                  let color = interpolatedGradientColor(
                    from: sourceColor,
                    to: targetColor,
                    progress: progress
                  ) else {
                return nil
            }
            stops.append(Gradient.Stop(color: color, location: location))
        }
        return Gradient(stops: stops)
    }

    private static func gradientColor(
        in stops: [Gradient.Stop],
        at location: CGFloat
    ) -> Color? {
        guard var lower = stops.first else { return nil }
        if location <= lower.location { return lower.color }
        for upper in stops.dropFirst() {
            if location < upper.location {
                guard upper.location > lower.location else { return upper.color }
                return interpolatedGradientColor(
                    from: lower.color,
                    to: upper.color,
                    progress: (location - lower.location) / (upper.location - lower.location)
                )
            }
            lower = upper
        }
        return lower.color
    }

    private static func interpolatedGradientColor(
        from source: Color,
        to target: Color,
        progress: CGFloat
    ) -> Color? {
        if source == target { return source }
        guard let sourceLinear = linearSRGBComponents(of: source),
              let targetLinear = linearSRGBComponents(of: target),
              source.provider.alpha.isFinite,
              target.provider.alpha.isFinite else {
            return nil
        }

        let workingSpace = target.provider.colorSpace
        let sourceComponents = encodedComponents(sourceLinear, in: workingSpace)
        let targetComponents = encodedComponents(targetLinear, in: workingSpace)
        let sourceAlpha = source.provider.alpha
        let targetAlpha = target.provider.alpha
        let fraction = Double(progress)
        let mixedAlpha = sourceAlpha + (targetAlpha - sourceAlpha) * fraction
        let mixedComponents: SIMD3<Double>
        if sourceAlpha == targetAlpha {
            mixedComponents = sourceComponents + (targetComponents - sourceComponents) * fraction
        } else {
            let premultiplied = sourceComponents * sourceAlpha
                + (targetComponents * targetAlpha - sourceComponents * sourceAlpha) * fraction
            if mixedAlpha == 0 || mixedAlpha == 1 {
                mixedComponents = premultiplied
            } else {
                mixedComponents = premultiplied / mixedAlpha
            }
        }

        let workingColor = Color(
            workingSpace,
            red: mixedComponents.x,
            green: mixedComponents.y,
            blue: mixedComponents.z,
            opacity: mixedAlpha
        )
        guard let mixedLinear = linearSRGBComponents(of: workingColor) else { return nil }
        let output = encodedComponents(mixedLinear, in: source.provider.colorSpace)
        return Color(
            source.provider.colorSpace,
            red: output.x,
            green: output.y,
            blue: output.z,
            opacity: mixedAlpha
        )
    }

    private static func linearSRGBComponents(of color: Color) -> SIMD3<Double>? {
        var components = SIMD3(
            color.provider.red,
            color.provider.green,
            color.provider.blue
        )
        guard components.x.isFinite,
              components.y.isFinite,
              components.z.isFinite else {
            return nil
        }
        switch color.provider.colorSpace {
        case .sRGB:
            components = mappedComponents(components, decodeRGBComponent)
        case .sRGBLinear:
            break
        case .displayP3:
            components = mappedComponents(components, decodeRGBComponent)
            let xyz = SIMD3(
                0.4865709486482162 * components.x + 0.2656676931690931 * components.y + 0.1982172852343625 * components.z,
                0.2289745640697488 * components.x + 0.6917385218365064 * components.y + 0.0792869140937450 * components.z,
                0.0000000000000000 * components.x + 0.0451133818589026 * components.y + 1.0439443689009760 * components.z
            )
            components = SIMD3(
                3.2409699419045226 * xyz.x - 1.5373831775700940 * xyz.y - 0.4986107602930034 * xyz.z,
                -0.9692436362808796 * xyz.x + 1.8759675015077202 * xyz.y + 0.0415550574071756 * xyz.z,
                0.0556300796969937 * xyz.x - 0.2039769588889765 * xyz.y + 1.0569715142428786 * xyz.z
            )
        }
        return components
    }

    private static func encodedComponents(
        _ linearSRGB: SIMD3<Double>,
        in colorSpace: Color.RGBColorSpace
    ) -> SIMD3<Double> {
        switch colorSpace {
        case .sRGB:
            return mappedComponents(linearSRGB, encodeRGBComponent)
        case .sRGBLinear:
            return linearSRGB
        case .displayP3:
            let xyz = SIMD3(
                0.4123907992659595 * linearSRGB.x + 0.3575843393838780 * linearSRGB.y + 0.1804807884018343 * linearSRGB.z,
                0.2126390058715104 * linearSRGB.x + 0.7151686787677559 * linearSRGB.y + 0.0721923153607337 * linearSRGB.z,
                0.0193308187155919 * linearSRGB.x + 0.1191947797946260 * linearSRGB.y + 0.9505321522496607 * linearSRGB.z
            )
            return mappedComponents(SIMD3(
                2.4934969119414250 * xyz.x - 0.9313836179191240 * xyz.y - 0.4027107844507170 * xyz.z,
                -0.8294889695615750 * xyz.x + 1.7626640603183460 * xyz.y + 0.0236246858419440 * xyz.z,
                0.0358458302437840 * xyz.x - 0.0761723892680410 * xyz.y + 0.9568845240076870 * xyz.z
            ), encodeRGBComponent)
        }
    }

    private static func mappedComponents(
        _ components: SIMD3<Double>,
        _ transform: (Double) -> Double
    ) -> SIMD3<Double> {
        SIMD3(
            transform(components.x),
            transform(components.y),
            transform(components.z)
        )
    }

    private static func oklabComponents(
        fromLinearSRGB color: SIMD3<Double>
    ) -> SIMD3<Double> {
        let l = signedCubeRoot(
            0.4122214708 * color.x + 0.5363325363 * color.y + 0.0514459929 * color.z
        )
        let m = signedCubeRoot(
            0.2119034982 * color.x + 0.6806995451 * color.y + 0.1073969566 * color.z
        )
        let s = signedCubeRoot(
            0.0883024619 * color.x + 0.2817188376 * color.y + 0.6299787005 * color.z
        )
        return SIMD3(
            0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        )
    }

    private static func linearSRGBComponents(
        fromOklab color: SIMD3<Double>
    ) -> SIMD3<Double> {
        let l = pow(color.x + 0.3963377774 * color.y + 0.2158037573 * color.z, 3)
        let m = pow(color.x - 0.1055613458 * color.y - 0.0638541728 * color.z, 3)
        let s = pow(color.x - 0.0894841775 * color.y - 1.2914855480 * color.z, 3)
        return SIMD3(
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        )
    }

    private static func signedCubeRoot(_ value: Double) -> Double {
        value.sign == .minus ? -pow(-value, 1.0 / 3.0) : pow(value, 1.0 / 3.0)
    }

    private static func decodeRGBComponent(_ value: Double) -> Double {
        let magnitude = abs(value)
        let decoded = magnitude <= 0.04045
            ? magnitude / 12.92
            : pow((magnitude + 0.055) / 1.055, 2.4)
        return value.sign == .minus ? -decoded : decoded
    }

    private static func encodeRGBComponent(_ value: Double) -> Double {
        let magnitude = abs(value)
        let encoded = magnitude <= 0.0031308
            ? magnitude * 12.92
            : 1.055 * pow(magnitude, 1.0 / 2.4) - 0.055
        return value.sign == .minus ? -encoded : encoded
    }

    private static func sameSingleColor(
        _ shading: GraphicsContext.Shading,
        _ color: Color
    ) -> Bool {
        guard shading.properties.count == 1 else { return false }
        switch shading.properties[0] {
        case let .color(value):
            return value == color
        case let .style(style):
            return (style as? Color) == color
        default:
            return false
        }
    }

    private static func interpolatedPath(
        from source: Path,
        to target: Path,
        progress: CGFloat
    ) -> Path? {
        var sourceElements: [Path.Element] = []
        var targetElements: [Path.Element] = []
        source.forEach { sourceElements.append($0) }
        target.forEach { targetElements.append($0) }
        guard sourceElements.count == targetElements.count else { return nil }

        var output = Path()
        for (sourceElement, targetElement) in zip(sourceElements, targetElements) {
            switch (sourceElement, targetElement) {
            case let (.move(sourcePoint), .move(targetPoint)):
                output.move(to: interpolatedPoint(
                    from: sourcePoint,
                    to: targetPoint,
                    progress: progress
                ))
            case let (.line(sourcePoint), .line(targetPoint)):
                output.addLine(to: interpolatedPoint(
                    from: sourcePoint,
                    to: targetPoint,
                    progress: progress
                ))
            case let (
                .quadCurve(sourcePoint, sourceControl),
                .quadCurve(targetPoint, targetControl)
            ):
                output.addQuadCurve(
                    to: interpolatedPoint(
                        from: sourcePoint,
                        to: targetPoint,
                        progress: progress
                    ),
                    control: interpolatedPoint(
                        from: sourceControl,
                        to: targetControl,
                        progress: progress
                    )
                )
            case let (
                .curve(sourcePoint, sourceControl1, sourceControl2),
                .curve(targetPoint, targetControl1, targetControl2)
            ):
                output.addCurve(
                    to: interpolatedPoint(
                        from: sourcePoint,
                        to: targetPoint,
                        progress: progress
                    ),
                    control1: interpolatedPoint(
                        from: sourceControl1,
                        to: targetControl1,
                        progress: progress
                    ),
                    control2: interpolatedPoint(
                        from: sourceControl2,
                        to: targetControl2,
                        progress: progress
                    )
                )
            case (.closeSubpath, .closeSubpath):
                output.closeSubpath()
            default:
                return nil
            }
        }
        return output
    }

    private static func interpolatedPoint(
        from source: CGPoint,
        to target: CGPoint,
        progress: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: interpolate(source.x, target.x, by: progress),
            y: interpolate(source.y, target.y, by: progress)
        )
    }

    private static func interpolatedTransform(
        from source: CGAffineTransform,
        to target: CGAffineTransform,
        progress: CGFloat
    ) -> CGAffineTransform {
        CGAffineTransform(
            a: interpolate(source.a, target.a, by: progress),
            b: interpolate(source.b, target.b, by: progress),
            c: interpolate(source.c, target.c, by: progress),
            d: interpolate(source.d, target.d, by: progress),
            tx: interpolate(source.tx, target.tx, by: progress),
            ty: interpolate(source.ty, target.ty, by: progress)
        )
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
            if case let .mask(sourceMask, sourceOptions) = source.effect,
               case let .mask(targetMask, targetOptions) = target.effect {
                if sourceOptions.rawValue == targetOptions.rawValue {
                    let mask = preservesSourceMaskForIncompatibleCoverageFamily(
                        from: sourceMask,
                        to: targetMask
                    ) ? sourceMask : interpolatedContents(
                        from: sourceMask,
                        to: targetMask,
                        progress: progress,
                        transition: transition
                    )
                    contents.appendEffect(
                        .mask(mask, sourceOptions),
                        contents: interpolatedContents(
                            from: source.contents,
                            to: target.contents,
                            progress: progress,
                            transition: transition
                        )
                    )
                    continue
                }

                if canPreserveDifferentModeMaskBranches(
                    from: sourceMask,
                    to: targetMask
                ) {
                    var sourceBranch = DisplayList()
                    sourceBranch.appendEffect(source.effect, contents: source.contents)
                    var targetBranch = DisplayList()
                    targetBranch.appendEffect(target.effect, contents: target.contents)
                    contents.append(contentsOf: sourceBranch)
                    contents.append(contentsOf: targetBranch)
                    continue
                }
            }

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
                allowsCountMismatch: true,
                allowsWholeListOperations: allowsWholeListOperations(
                    from: fromList,
                    to: toList
                )
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
                allowsCountMismatch: false,
                allowsWholeListOperations: false
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
            if case let .mask(sourceMask, sourceOptions) = source.effect,
               case let .mask(targetMask, targetOptions) = target.effect {
                let effectBounds: CGRect
                if sourceOptions.rawValue == targetOptions.rawValue {
                    guard let maskBounds = interpolatedBounds(
                        from: sourceMask,
                        to: targetMask,
                        progress: Float(progress),
                        transition: transition
                    ), let contentBounds = interpolatedBounds(
                        from: source.contents,
                        to: target.contents,
                        progress: Float(progress),
                        transition: transition
                    ) else {
                        return nil
                    }
                    effectBounds = sourceOptions.contains(.inverse)
                        ? contentBounds
                        : contentBounds.intersection(maskBounds)
                } else {
                    guard canPreserveDifferentModeMaskBranches(
                        from: sourceMask,
                        to: targetMask
                    ),
                          let sourceBounds = maskEffectBounds(
                            mask: sourceMask,
                            contents: source.contents,
                            options: sourceOptions
                          ), let targetBounds = maskEffectBounds(
                            mask: targetMask,
                            contents: target.contents,
                            options: targetOptions
                          ) else {
                        return nil
                    }
                    effectBounds = sourceBounds.union(targetBounds)
                }
                bounds = union(bounds, effectBounds)
                continue
            }

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

    private static func maskEffectBounds(
        mask: DisplayList,
        contents: DisplayList,
        options: GraphicsContext.ClipOptions
    ) -> CGRect? {
        guard let contentBounds = contents.interpolationBounds else {
            return nil
        }
        guard !options.contains(.inverse) else {
            return contentBounds
        }
        guard let maskBounds = mask.interpolationBounds else {
            return .null
        }
        return contentBounds.intersection(maskBounds)
    }

    private static func canMaterializeInterpolatedContents(
        from source: DisplayList,
        to target: DisplayList
    ) -> Bool {
        guard source.interpolationBounds != nil || target.interpolationBounds != nil else {
            return false
        }

        if canInterpolateRecordedItems(
            fromItems: source.renderItems,
            fromCommands: source.itemCommands,
            toItems: target.renderItems,
            toCommands: target.itemCommands,
            allowsWholeListOperations: allowsWholeListOperations(
                from: source,
                to: target
            )
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
            if case let .mask(sourceMask, sourceOptions) = source.effect,
               case let .mask(targetMask, targetOptions) = target.effect {
                if sourceOptions.rawValue == targetOptions.rawValue {
                    return canMaterializeInterpolatedContents(
                        from: sourceMask,
                        to: targetMask
                    ) || canMaterializeInterpolatedContents(
                        from: source.contents,
                        to: target.contents
                    )
                }
                return canPreserveDifferentModeMaskBranches(
                    from: sourceMask,
                    to: targetMask
                )
            }
            return source.effect.hasSameSurface(as: target.effect) &&
                canMaterializeInterpolatedContents(
                    from: source.contents,
                    to: target.contents
                )
        }
    }

    private static func canPreserveDifferentModeMaskBranches(
        from source: DisplayList,
        to target: DisplayList
    ) -> Bool {
        source.hasSameInterpolationSurface(as: target) ||
            canMaterializeInterpolatedContents(from: source, to: target)
    }

    // A single incompatible coverage pair remains source-owned for the
    // interpolator lifetime instead of becoming a child-mask cross-fade.
    private static func preservesSourceMaskForIncompatibleCoverageFamily(
        from source: DisplayList,
        to target: DisplayList
    ) -> Bool {
        guard source.effects.isEmpty,
              target.effects.isEmpty,
              source.renderItems.count == 1,
              target.renderItems.count == 1,
              source.itemCommands.count == 1,
              target.itemCommands.count == 1,
              case let .shape(
                sourceRole,
                .some(.color(sourceColor)),
                sourceFillStyle,
                sourceStrokeStyle,
                sourceBounds
              ) = source.itemCommands[0],
              case let .shape(
                targetRole,
                .some(.color(targetColor)),
                targetFillStyle,
                targetStrokeStyle,
                targetBounds
              ) = target.itemCommands[0],
              sourceRole == targetRole,
              sourceColor == targetColor,
              sourceFillStyle == targetFillStyle,
              sourceStrokeStyle == targetStrokeStyle,
              sourceBounds == targetBounds,
              case let .content(sourceContent) = source.renderItems[0].value,
              case let .shape(sourceShape) = sourceContent.value,
              case let .content(targetContent) = target.renderItems[0].value,
              case let .shape(targetShape) = targetContent.value,
              sameSingleColor(sourceShape.shading, sourceColor),
              sameSingleColor(targetShape.shading, targetColor),
              sourceShape.fillStyle == targetShape.fillStyle,
              sourceShape.strokeStyle == targetShape.strokeStyle,
              sourceShape.transform == targetShape.transform else {
            return false
        }
        return interpolatedPath(
            from: sourceShape.path,
            to: targetShape.path,
            progress: 0.5
        ) == nil
    }

    private static func interpolatedRecordedItemBounds(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand],
        progress: CGFloat,
        transition: RBTransition?,
        allowsCountMismatch: Bool,
        allowsWholeListOperations: Bool
    ) -> CGRect? {
        guard let operations = itemInterpolationOperations(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands,
            allowsCountMismatch: allowsCountMismatch,
            allowsWholeListOperations: allowsWholeListOperations
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
        toCommands: [DisplayList.ItemCommand],
        allowsWholeListOperations: Bool
    ) -> Bool {
        itemInterpolationOperations(
            fromItems: fromItems,
            fromCommands: fromCommands,
            toItems: toItems,
            toCommands: toCommands,
            allowsCountMismatch: true,
            allowsWholeListOperations: allowsWholeListOperations
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
            allowsCountMismatch: false,
            allowsWholeListOperations: false
        ) != nil
    }

    private static func itemInterpolationOperations(
        fromItems: [DisplayList.Item],
        fromCommands: [DisplayList.ItemCommand],
        toItems: [DisplayList.Item],
        toCommands: [DisplayList.ItemCommand],
        allowsCountMismatch: Bool,
        allowsWholeListOperations: Bool
    ) -> [ItemInterpolationOperation]? {
        // This reduced carrier preserves source-order pairing. Keeping planning separate
        // lets a future classifier/diff producer replace only this step.
        guard allowsCountMismatch || fromItems.count == toItems.count else {
            return nil
        }

        if allowsWholeListOperations, fromItems.isEmpty, !toItems.isEmpty {
            guard let targetInputs = itemInterpolationInputs(
                items: toItems,
                commands: toCommands
            ), let bounds = unionBounds(of: targetInputs) else {
                return nil
            }
            return [.wholeInserted(items: toItems, bounds: bounds)]
        }

        if allowsWholeListOperations, !fromItems.isEmpty, toItems.isEmpty {
            guard let sourceInputs = itemInterpolationInputs(
                items: fromItems,
                commands: fromCommands
            ), let bounds = unionBounds(of: sourceInputs) else {
                return nil
            }
            return [.wholeRemoved(items: fromItems, bounds: bounds)]
        }

        guard !fromItems.isEmpty,
              !toItems.isEmpty,
              let sourceInputs = itemInterpolationInputs(
                items: fromItems,
                commands: fromCommands
              ), let targetInputs = itemInterpolationInputs(
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

    private func itemOperationPlan() -> ItemOperationPlan? {
        if !hasCachedItemOperationPlan {
            cachedItemOperationPlan = makeItemOperationPlan()
            hasCachedItemOperationPlan = true
        }
        return cachedItemOperationPlan
    }

    private func invalidateItemOperationPlan() {
        cachedItemOperationPlan = nil
        hasCachedItemOperationPlan = false
    }

    private func makeItemOperationPlan() -> ItemOperationPlan? {
        var animationTable = RBAnimationTable(defaultAnimationIndex: 0)
        let defaultAnimationIndex = animationTable.internAnimation(checkedAnimationOption())
        animationTable.defaultAnimationIndex = defaultAnimationIndex
        guard var operations = Self.itemInterpolationOperations(
            fromItems: from.renderItems,
            fromCommands: from.itemCommands,
            toItems: to.renderItems,
            toCommands: to.itemCommands,
            allowsCountMismatch: true,
            allowsWholeListOperations: Self.allowsWholeListOperations(from: from, to: to)
        ) else {
            return nil
        }
        for index in operations.indices {
            operations[index].resolveAnimation(
                table: &animationTable,
                defaultAnimationIndex: defaultAnimationIndex,
                sequencer: animationSequencer
            )
        }
        return ItemOperationPlan(
            operations: operations,
            animationTable: animationTable
        )
    }

    // Style identity is independent of the animation UUID. The outermost target style is
    // considered first, and non-selecting styles do not hide a matching inner style.
    private static func animationStyle(
        from source: DisplayList.StyleChain,
        to target: DisplayList.StyleChain
    ) -> RBAnimation? {
        let sourceStyles = source.commands.reversed().compactMap { command -> DisplayList.StyleCommand.AnimationStyle? in
            guard case let .animation(style) = command else { return nil }
            return style
        }
        for command in target.commands.reversed() {
            guard case let .animation(targetStyle) = command,
                  let sourceStyle = sourceStyles.first(where: {
                      $0.metadataIdentity.matches(targetStyle.metadataIdentity)
                  }) else {
                continue
            }
            switch targetStyle.flags & 0xf00 {
            case 0x200:
                return targetStyle.animation
            case 0x100 where sourceStyle.id == nil ||
                    targetStyle.id == nil ||
                    sourceStyle.id != targetStyle.id:
                return targetStyle.animation
            default:
                continue
            }
        }
        return nil
    }

    private static func unionBounds(
        of inputs: [ItemInterpolationInput]
    ) -> CGRect? {
        inputs.reduce(nil) { bounds, input in
            union(bounds, input.bounds)
        }
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
        guard let fromBounds = fromList.interpolationBounds ?? toList.interpolationBounds,
              let toBounds = toList.interpolationBounds ?? fromList.interpolationBounds else {
            return nil
        }
        return fromBounds.union(toBounds)
    }

    private static func allowsWholeListOperations(
        from source: DisplayList,
        to target: DisplayList
    ) -> Bool {
        (source.interpolationBounds == nil) != (target.interpolationBounds == nil)
    }

    private static func usesWholeListOpacityEventRouting(
        _ transition: RBTransition
    ) -> Bool {
        transition.effects.allSatisfy {
            $0.semanticType == ContentTransition.EffectType.opacity.type
        }
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

    private var isImmediateWholeListInsertion: Bool {
        guard from.interpolationBounds == nil,
              from.renderItems.isEmpty,
              from.debugItems.isEmpty,
              from.effects.isEmpty,
              !to.renderItems.isEmpty,
              to.debugItems.isEmpty,
              to.effects.isEmpty,
              let transition,
              Self.usesWholeListOpacityEventRouting(transition) else {
            return false
        }
        return transition.isEmpty(for: 1)
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
