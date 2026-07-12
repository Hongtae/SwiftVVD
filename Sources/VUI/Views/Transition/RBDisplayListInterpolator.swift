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
