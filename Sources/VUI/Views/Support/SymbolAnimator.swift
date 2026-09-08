//
//  File: SymbolAnimator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

final class SymbolAnimator {
    private struct ReplacementTimeline {
        var duration: Double
        var sourceLevelCount: Int
        var targetLevelCount: Int
        var sourceDrawDuration: Double?
        var targetDrawDuration: Double?
    }

    private struct ActiveReplacement {
        var source: ImageDrawing
        var configuration: RBSymbolReplacementConfiguration
        var timeline: ReplacementTimeline
        var presentationStart: ImageViewChild.PresentationStart
        var completionTokens: [AnimationCompletionToken]
    }

    private struct LevelPresentation {
        var source: ImageDrawing
            .SymbolReplacementLevelPresentation
        var target: ImageDrawing
            .SymbolReplacementLevelPresentation
    }

    private var image: ImageDrawing
    private var activeReplacements: [ActiveReplacement] = []
    private(set) var version: UInt32 = 0

    init(image: ImageDrawing) {
        self.image = image
    }

    var isAnimating: Bool {
        !activeReplacements.isEmpty
    }

    func update(
        image target: ImageDrawing,
        state: ContentTransition.State,
        transaction: Transaction
    ) {
        defer {
            image = target
        }

        guard image.symbol?.identity != target.symbol?.identity else {
            return
        }

        guard !transaction.disablesAnimations,
              state.animation != nil || transaction.animation != nil,
              let configuration =
                state.transition.rbTransition.symbolReplacementConfiguration,
              let sourceSymbol = image.symbol,
              let targetSymbol = target.symbol else {
            version &+= 1
            return
        }

        let completionTokens = replacementCompletionTokens(for: transaction)
        completionTokens.forEach { $0.start() }
        activeReplacements.append(ActiveReplacement(
            source: image,
            configuration: configuration,
            timeline: replacementTimeline(
                source: sourceSymbol,
                target: targetSymbol,
                configuration: configuration
            ),
            presentationStart: ImageViewChild.PresentationStart(),
            completionTokens: completionTokens
        ))
        version &+= 1
    }

    func presentation(
        at time: Time
    ) -> ImageDrawing.SymbolReplacementPresentation? {
        guard !activeReplacements.isEmpty else {
            return nil
        }
        activeReplacements.forEach {
            $0.presentationStart.activate(at: time)
        }
        retireCompletedReplacements(at: time)
        guard !activeReplacements.isEmpty else {
            return nil
        }

        var symbols: [
            ImageDrawing
                .SymbolReplacementSymbolPresentation
        ] = []
        if let active = activeReplacements.last {
            symbols.append(symbolPresentation(
                image: image,
                side: .target,
                active: active,
                at: time
            ))
        }
        symbols.append(contentsOf: activeReplacements.reversed().map { active in
            symbolPresentation(
                image: active.source,
                side: .source,
                active: active,
                at: time
            )
        })
        return ImageDrawing.SymbolReplacementPresentation(
            symbols: symbols
        )
    }

    func cancel() {
        finishAllReplacements()
    }

    private enum PresentationSide {
        case source
        case target
    }

    private func symbolPresentation(
        image: ImageDrawing,
        side: PresentationSide,
        active: ActiveReplacement,
        at time: Time
    ) -> ImageDrawing.SymbolReplacementSymbolPresentation {
        guard let start = active.presentationStart.time,
              let symbol = image.symbol else {
            preconditionFailure(
                "An active symbol replacement requires symbol input."
            )
        }
        let elapsedTime = max(time.seconds - start.seconds, 0)
        let levelCount: Int
        switch side {
        case .source:
            levelCount = active.timeline.sourceLevelCount
        case .target:
            levelCount = active.timeline.targetLevelCount
        }
        let levels = (0..<max(levelCount, 1)).map { level in
            let presentation = replacementLevelPresentation(
                elapsedTime: elapsedTime,
                level: level,
                timeline: active.timeline,
                configuration: active.configuration
            )
            switch side {
            case .source:
                return presentation.source
            case .target:
                return presentation.target
            }
        }
        let drawProgresses: [Double]?
        switch side {
        case .source:
            drawProgresses = active.timeline.sourceDrawDuration.map { _ in
                replacementDrawProgresses(
                    symbol: symbol,
                    elapsedTime: elapsedTime,
                    startsAt: 0,
                    appears: false
                )
            }
        case .target:
            drawProgresses = active.timeline.targetDrawDuration.map { _ in
                replacementDrawProgresses(
                    symbol: symbol,
                    elapsedTime: elapsedTime,
                    startsAt: 0.25,
                    appears: true
                )
            }
        }
        return ImageDrawing
            .SymbolReplacementSymbolPresentation(
            image: image,
            levels: levels,
            isLayered: active.configuration.isLayered,
            drawProgresses: drawProgresses
        )
    }

    private func retireCompletedReplacements(at time: Time) {
        var retained: [ActiveReplacement] = []
        retained.reserveCapacity(activeReplacements.count)
        for var active in activeReplacements {
            guard let start = active.presentationStart.time,
                  time.seconds - start.seconds >= active.timeline.duration else {
                retained.append(active)
                continue
            }
            let tokens = active.completionTokens
            active.completionTokens.removeAll()
            tokens.forEach { $0.finish() }
        }
        activeReplacements = retained
    }

    private func finishAllReplacements() {
        let active = activeReplacements
        activeReplacements.removeAll()
        for var replacement in active {
            let tokens = replacement.completionTokens
            replacement.completionTokens.removeAll()
            tokens.forEach { $0.finish() }
        }
    }

    private func replacementTimeline(
        source: ResolvedVectorSymbol,
        target: ResolvedVectorSymbol,
        configuration: RBSymbolReplacementConfiguration
    ) -> ReplacementTimeline {
        let sourceLevelCount = configuration.isLayered
            ? max(source.replacementLevelCount, 1)
            : 1
        let targetLevelCount = configuration.isLayered
            ? max(target.replacementLevelCount, 1)
            : 1
        let sourceDrawDuration = source.drawMotionGroupDurations.max()
        let targetDrawDuration = target.drawMotionGroupDurations.max()
        let specializedSourceDuration: Double?
        let specializedTargetDuration: Double?
        if configuration.isAutomaticStyle,
           sourceDrawDuration != nil,
           targetDrawDuration == nil {
            specializedSourceDuration = sourceDrawDuration
            specializedTargetDuration = nil
        } else if configuration.isAutomaticStyle,
                  sourceDrawDuration == nil,
                  targetDrawDuration != nil {
            specializedSourceDuration = nil
            specializedTargetDuration = targetDrawDuration
        } else {
            specializedSourceDuration = nil
            specializedTargetDuration = nil
        }
        let specializedDuration: Double
        if let specializedSourceDuration {
            specializedDuration = specializedSourceDuration + 0.25
        } else if let specializedTargetDuration {
            specializedDuration = 0.25 + specializedTargetDuration
        } else {
            specializedDuration = 0
        }
        return ReplacementTimeline(
            duration: max(configuration.duration, specializedDuration),
            sourceLevelCount: sourceLevelCount,
            targetLevelCount: targetLevelCount,
            sourceDrawDuration: specializedSourceDuration,
            targetDrawDuration: specializedTargetDuration
        )
    }

    private func replacementDrawProgresses(
        symbol: ResolvedVectorSymbol,
        elapsedTime: Double,
        startsAt startTime: Double,
        appears: Bool
    ) -> [Double] {
        symbol.drawMotionGroupDurations.map { duration in
            let progress = min(max((elapsedTime - startTime) / duration, 0), 1)
            let eased = (1 - cos(progress * .pi)) * 0.5
            return appears ? eased : 1 - eased
        }
    }

    private func replacementLevelPresentation(
        elapsedTime: Double,
        level: Int,
        timeline: ReplacementTimeline,
        configuration: RBSymbolReplacementConfiguration
    ) -> LevelPresentation {
        let sourceStep = timeline.sourceLevelCount > 1
            ? min(0.05, 0.15 / Double(timeline.sourceLevelCount - 1))
            : 0
        let targetStep = timeline.targetLevelCount > 1
            ? min(0.05, 0.15 / Double(timeline.targetLevelCount - 1))
            : 0
        let sourceDelay = configuration.isLayered
            ? Double(max(timeline.sourceLevelCount - level - 1, 0)) *
                sourceStep
            : 0
        let targetForwardDelay = configuration.isLayered
            ? Double(level) * targetStep
            : 0
        let targetReverseDelay = configuration.isLayered
            ? Double(max(timeline.targetLevelCount - level - 1, 0)) *
                targetStep
            : 0
        let sourceEnd = 0.25
        let sourceProgress = normalizedReplacementProgress(
            elapsedTime,
            from: min(sourceDelay, sourceEnd),
            to: sourceEnd
        )

        let sourceScale: CGFloat
        let sourceOpacity: CGFloat
        let targetScale: CGFloat
        let targetOpacity: CGFloat
        switch configuration.style {
        case .downUp:
            let sourceCurve = replacementCurve(
                sourceProgress,
                controlPoint1: CGPoint(x: 0.75, y: 0),
                controlPoint2: CGPoint(x: 0.8, y: 1)
            )
            sourceScale = 1 - 0.5 * sourceCurve
            sourceOpacity = elapsedTime < sourceEnd ? 1 : 0
            let targetStart = timeline.sourceDrawDuration ?? 0.25
            let targetDuration = max(0.25 - targetReverseDelay, 0)
            let targetProgress = normalizedReplacementProgress(
                elapsedTime,
                from: targetStart,
                to: targetStart + targetDuration
            )
            let targetCurve = replacementCurve(
                targetProgress,
                controlPoint1: CGPoint(x: 0.2, y: 0),
                controlPoint2: CGPoint(x: 0.25, y: 1)
            )
            targetScale = 0.5 + 0.5 * targetCurve
            targetOpacity = elapsedTime > targetStart ? 1 : 0
        case .upUp:
            let sourceCurve = replacementCurve(
                sourceProgress,
                controlPoint1: CGPoint(x: 0.33, y: 0),
                controlPoint2: CGPoint(x: 0.83, y: 0.83)
            )
            sourceScale = 1 + 0.25 * sourceCurve
            sourceOpacity = 1 - sourceCurve
            let targetStart = 1.0 / 6.0 + targetForwardDelay
            let targetProgress = normalizedReplacementProgress(
                elapsedTime,
                from: targetStart,
                to: 0.5
            )
            let targetCurve = replacementCurve(
                targetProgress,
                controlPoint1: CGPoint(x: 0.17, y: 0.17),
                controlPoint2: CGPoint(x: 0.67, y: 1)
            )
            targetScale = 0.4 + 0.6 * targetCurve
            targetOpacity = targetCurve
        case .offUp:
            sourceScale = 1
            sourceOpacity = elapsedTime <= 0 ? 1 : 0
            let targetDuration = max(0.25 - targetReverseDelay, 0)
            let targetProgress = normalizedReplacementProgress(
                elapsedTime,
                from: 0,
                to: targetDuration
            )
            let targetScaleCurve = replacementCurve(
                targetProgress,
                controlPoint1: CGPoint(x: 0.2, y: 0),
                controlPoint2: CGPoint(x: 0.25, y: 1)
            )
            let targetOpacityCurve = replacementCurve(
                targetProgress,
                controlPoint1: CGPoint(x: 0.33, y: 0),
                controlPoint2: CGPoint(x: 0.67, y: 1)
            )
            targetScale = 0.5 + 0.5 * targetScaleCurve
            targetOpacity = targetOpacityCurve
        }
        return LevelPresentation(
            source: ImageDrawing
                .SymbolReplacementLevelPresentation(
                    scale: sourceScale,
                    opacity: Double(sourceOpacity)
                ),
            target: ImageDrawing
                .SymbolReplacementLevelPresentation(
                    scale: targetScale,
                    opacity: Double(targetOpacity)
                )
        )
    }

    private func normalizedReplacementProgress(
        _ value: Double,
        from start: Double,
        to end: Double
    ) -> CGFloat {
        guard end > start else { return value >= end ? 1 : 0 }
        return CGFloat(min(max((value - start) / (end - start), 0), 1))
    }

    private func replacementCurve(
        _ progress: CGFloat,
        controlPoint1: CGPoint,
        controlPoint2: CGPoint
    ) -> CGFloat {
        let solver = UnitCurve.CubicSolver(
            startControlPoint: UnitPoint(
                x: controlPoint1.x,
                y: controlPoint1.y
            ),
            endControlPoint: UnitPoint(
                x: controlPoint2.x,
                y: controlPoint2.y
            )
        )
        return solver.solve(x: min(max(progress, 0), 1))
    }
}

private func replacementCompletionTokens(
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
