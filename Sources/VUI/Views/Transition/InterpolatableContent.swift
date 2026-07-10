//
//  File: InterpolatableContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Content values that can request display-list interpolation when their rendered value changes.
protocol InterpolatableContent {
    static var defaultTransition: ContentTransition { get }
    func requiresTransition(to target: Self) -> Bool
    var appliesTransitionsForSizeChanges: Bool { get }
    var addsDrawingGroup: Bool { get }
    func modifyTransition(state: inout ContentTransition.State, to target: Self)
    func defaultAnimation(to target: Self) -> Animation?
}

extension InterpolatableContent {
    static var defaultTransition: ContentTransition { .identity }
    var appliesTransitionsForSizeChanges: Bool { false }
    var addsDrawingGroup: Bool { false }

    func modifyTransition(state: inout ContentTransition.State, to target: Self) {
    }

    func defaultAnimation(to target: Self) -> Animation? {
        nil
    }
}

extension InterpolatableContent where Self: Equatable {
    func requiresTransition(to target: Self) -> Bool {
        self != target
    }
}

extension DisplayList {
    // Optional animation tag attached to interpolated display-list contents.
    struct InterpolatorAnimation {
        var value: StrongHash?
        var animation: Animation?

        init(value: StrongHash? = nil, animation: Animation? = nil) {
            self.value = value
            self.animation = animation
        }
    }

    // Stateful layer that retains removed contents and drives their display-list interpolators.
    struct InterpolatorLayer {
        // Lifecycle of a retained removed display-list entry.
        enum Phase: Equatable {
            case pending
            case animating
            case removed
        }

        // Current display-list payload tracked by an interpolation layer.
        struct Contents {
            var displayList: DisplayList
            var origin: CGPoint
            var animation: InterpolatorAnimation?
            var contentsScale: Float
            var version: DisplayList.Version?

            init(
                displayList: DisplayList = DisplayList(),
                origin: CGPoint = .zero,
                animation: InterpolatorAnimation? = nil,
                contentsScale: Float = 1,
                version: DisplayList.Version? = nil
            ) {
                self.displayList = displayList
                self.origin = origin
                self.animation = animation
                self.contentsScale = contentsScale
                self.version = version
            }
        }

        // Retained outgoing contents plus transition/interpolator state.
        struct Removed {
            var contents: Contents
            var state: ContentTransition.State
            var rbTransition: RBTransition
            var interpolator: RBDisplayListInterpolator?
            var animation: Animation?
            var startTime: Time
            var activeDuration: Double
            var phase: Phase
        }

        private(set) var contents: Contents
        private(set) var currentTime: Time
        private(set) var maxDuration: Double
        private(set) var nextUpdateTime: Time
        private(set) var removed: [Removed]
        private(set) var needsUpdate: Bool

        init() {
            self.contents = Contents()
            self.currentTime = .zero
            self.maxDuration = .infinity
            self.nextUpdateTime = .infinity
            self.removed = []
            self.needsUpdate = true
        }

        var removedCount: Int {
            removed.count
        }

        mutating func setDisplayList(
            _ list: DisplayList,
            origin: CGPoint,
            version: DisplayList.Version? = nil,
            state: ContentTransition.State? = nil,
            animation: Animation? = nil
        ) {
            guard !contents.matches(list: list, origin: origin, version: version) else {
                return
            }

            if let removedState = state, !contents.displayList.isEmptyForInterpolation {
                removed.append(
                    Removed(
                        contents: contents,
                        state: removedState,
                        rbTransition: removedState.transition.rbTransition,
                        interpolator: nil,
                        animation: animation,
                        startTime: .zero,
                        activeDuration: -1,
                        phase: .pending
                    )
                )
            }

            contents = Contents(
                displayList: list,
                origin: origin,
                animation: animation.map { InterpolatorAnimation(animation: $0) },
                contentsScale: contents.contentsScale,
                version: version
            )
            if state == nil {
                for index in removed.indices where removed[index].phase == .animating {
                    removed[index].interpolator?.setTo(list)
                }
            }
            maxDuration = .infinity
            needsUpdate = true
        }

        mutating func updateInterpolators(
            contentsScale: Float,
            maxDuration: Double,
            time: Time = .zero
        ) {
            self.contents.contentsScale = contentsScale
            self.maxDuration = maxDuration
            self.currentTime = time

            guard needsUpdate else { return }
            needsUpdate = false

            foldActivePresentationIntoPendingRemoval()

            for index in removed.indices {
                if removed[index].phase == .pending {
                    var options: [RBDisplayListInterpolatorOptionKey: Any] = [
                        .transition: removed[index].rbTransition,
                    ]
                    if let animation = removed[index].animation {
                        options[.animation] = animation.rbAnimation
                    }
                    removed[index].interpolator = RBDisplayListInterpolator(
                        from: removed[index].contents.displayList,
                        to: contents.displayList,
                        options: options
                    )
                    let interpolatorDuration = removed[index].interpolator?.activeDuration ?? 0
                    let contentDuration = interpolatorDuration > 0
                        ? interpolatorDuration
                        : removed[index].interpolator?.animation?.activeDuration ?? 0
                    removed[index].activeDuration = min(
                        maxDuration,
                        contentDuration
                    )
                    removed[index].startTime = currentTime
                    removed[index].phase = .animating
                }
            }
            updateNextUpdateTime()
        }

        mutating func updateOutput(
            list: inout DisplayList,
            frame: CGRect,
            contentOffset: CGSize,
            version: DisplayList.Version,
            rasterizationOptions: RasterizationOptions
        ) -> Bool {
            guard !removed.isEmpty else {
                return false
            }

            let expiredPrefix = removed.prefix { removal in
                guard removal.activeDuration >= 0 else {
                    return false
                }
                return currentTime.seconds - removal.startTime.seconds >= removal.activeDuration
            }.count
            remove(prefix: expiredPrefix)

            guard !removed.isEmpty else {
                return false
            }

            if let removal = removed.last,
               !removal.state.transition.isIdentity,
               !removal.rbTransition.effects.isEmpty {
                let elapsed = Float(max(currentTime.seconds - removal.startTime.seconds, 0))
                let contents = removal.interpolator?.copyContents(withProgress: elapsed)
                    ?? removal.contents.displayList
                list.appendEffect(.contentTransition(removal.state), contents: contents)
            }
            return true
        }

        mutating func invalidateContentsScale() {
            contents.contentsScale = 0
            needsUpdate = true
        }

        mutating func remove(prefix: Int) {
            guard prefix > 0 else { return }
            removed.removeFirst(min(prefix, removed.count))
            updateNextUpdateTime()
        }

        private mutating func updateNextUpdateTime() {
            guard !removed.isEmpty else {
                nextUpdateTime = .infinity
                return
            }

            var nextTime = Time.infinity
            for removal in removed where removal.phase == .animating && removal.activeDuration >= 0 {
                let candidate = Time(seconds: removal.startTime.seconds + removal.activeDuration)
                if candidate < nextTime {
                    nextTime = candidate
                }
            }
            nextUpdateTime = nextTime
        }

        private mutating func foldActivePresentationIntoPendingRemoval() {
            guard removed.count > 1,
                  let pendingIndex = removed.lastIndex(where: { $0.phase == .pending }),
                  pendingIndex > 0 else {
                return
            }

            // The renderer composes earlier removals before advancing to the
            // next entry. Materialize that presentation for the closure-backed
            // display-list carrier so the new interpolation starts without a jump.
            let previous = removed[pendingIndex - 1]
            let elapsed = Float(max(currentTime.seconds - previous.startTime.seconds, 0))
            removed[pendingIndex].contents.displayList = previous.interpolator?
                .copyContents(withProgress: elapsed) ?? previous.contents.displayList
            removed.removeFirst(pendingIndex)
        }
    }

    // Base interpolator group hook installed on display-list output preferences.
    class InterpolatorGroup {
        var maxDuration: Double

        var hasActiveInterpolators: Bool {
            false
        }

        var activeSourceBounds: CGRect? {
            nil
        }

        init(maxDuration: Double = .infinity) {
            self.maxDuration = maxDuration
        }

        func nextUpdate(after time: Time) -> Time {
            Time(seconds: .infinity)
        }

        func updateTime(_ time: Time) {
        }

        func discardActiveInterpolators() {
        }

        func apply(to list: DisplayList) -> DisplayList {
            list
        }

        func setCurrentContents(
            contentSeed: DisplayList.Seed,
            target: DisplayList,
            time: Time,
            supportsVFD: Bool,
            rasterizationOptions: RasterizationOptions
        ) {
        }

        func update(
            contentSeed: DisplayList.Seed,
            current: DisplayList,
            target: DisplayList,
            state: ContentTransition.State,
            time: Time = .zero,
            animatesSize: Bool,
            defersRender: Bool,
            supportsVFD: Bool
        ) -> DisplayList {
            guard !state.transition.isIdentity else {
                return target
            }
            return DisplayList.effect(
                .contentTransition(state),
                contents: target
            )
        }
    }

    // Single-display-list interpolator group used by interpolatable content output rules.
    final class UnaryInterpolatorGroup: InterpolatorGroup {
        private(set) var layer = InterpolatorLayer()
        private(set) var features: UInt16 = 0
        private(set) var properties: UInt32 = 0
        private(set) var lastContentSeed = DisplayList.Seed()
        private(set) var supportsVariableFrameDuration = false
        private(set) var rasterizationOptions = RasterizationOptions()

        override init(maxDuration: Double = .infinity) {
            super.init(maxDuration: maxDuration)
        }

        override var hasActiveInterpolators: Bool {
            layer.removedCount > 0
        }

        override var activeSourceBounds: CGRect? {
            layer.removed.first?.interpolator?.from.interpolationBounds
        }

        override func discardActiveInterpolators() {
            layer.remove(prefix: layer.removedCount)
        }

        override func nextUpdate(after time: Time) -> Time {
            layer.removedCount == 0 ? layer.currentTime : layer.nextUpdateTime
        }

        func reset() {
            layer = InterpolatorLayer()
            features = 0
            properties = 0
            lastContentSeed = DisplayList.Seed()
            supportsVariableFrameDuration = false
            rasterizationOptions = RasterizationOptions()
            maxDuration = .infinity
        }

        override func updateTime(_ time: Time) {
            layer.updateInterpolators(
                contentsScale: layer.contents.contentsScale,
                maxDuration: maxDuration,
                time: time
            )
            scheduleNextUpdate(after: time)
        }

        override func setCurrentContents(
            contentSeed: DisplayList.Seed,
            target: DisplayList,
            time: Time,
            supportsVFD: Bool,
            rasterizationOptions: RasterizationOptions
        ) {
            lastContentSeed = contentSeed
            supportsVariableFrameDuration = supportsVFD
            self.rasterizationOptions = rasterizationOptions
            layer.setDisplayList(
                target,
                origin: .zero,
                version: DisplayList.Version(value: Int(contentSeed.value))
            )
            layer.updateInterpolators(
                contentsScale: layer.contents.contentsScale,
                maxDuration: maxDuration,
                time: time
            )
            scheduleNextUpdate(after: time)
        }

        override func update(
            contentSeed: DisplayList.Seed,
            current: DisplayList,
            target: DisplayList,
            state: ContentTransition.State,
            time: Time = .zero,
            animatesSize: Bool,
            defersRender: Bool,
            supportsVFD: Bool
        ) -> DisplayList {
            let previousContentSeed = lastContentSeed
            lastContentSeed = contentSeed
            supportsVariableFrameDuration = supportsVFD
            rasterizationOptions = state.rasterizationOptions

            layer.setDisplayList(
                current,
                origin: .zero,
                version: DisplayList.Version(value: Int(previousContentSeed.value))
            )
            layer.setDisplayList(
                target,
                origin: .zero,
                version: DisplayList.Version(value: Int(contentSeed.value)),
                state: state,
                animation: state.animation
            )
            layer.updateInterpolators(
                contentsScale: 1,
                maxDuration: maxDuration,
                time: time
            )
            scheduleNextUpdate(after: time)

            _ = super.update(
                contentSeed: contentSeed,
                current: current,
                target: target,
                state: state,
                time: time,
                animatesSize: animatesSize,
                defersRender: defersRender,
                supportsVFD: supportsVFD
            )
            return apply(to: target)
        }

        func apply(to list: inout DisplayList.Item) {
        }

        override func apply(to list: DisplayList) -> DisplayList {
            var output = DisplayList()
            let replacedCurrent = layer.updateOutput(
                list: &output,
                frame: .zero,
                contentOffset: .zero,
                version: DisplayList.Version(value: 0),
                rasterizationOptions: rasterizationOptions
            )
            return replacedCurrent ? output : list
        }

        private func scheduleNextUpdate(after time: Time) {
            let nextTime = nextUpdate(after: time)
            guard time < nextTime,
                  nextTime.seconds.isFinite,
                  let viewGraph = _AGGraphContext.current?.context as? ViewGraph else {
                return
            }
            viewGraph.nextUpdate.views.at(nextTime)
        }
    }
}

private extension DisplayList {
    var isEmptyForInterpolation: Bool {
        items.isEmpty && debugItems.isEmpty && effects.isEmpty && interpolationBounds == nil
    }
}

private extension DisplayList.InterpolatorLayer.Contents {
    func matches(
        list: DisplayList,
        origin: CGPoint,
        version: DisplayList.Version?
    ) -> Bool {
        displayList.hasSameInterpolationSurface(as: list) &&
            self.origin == origin &&
            self.version?.value == version?.value
    }
}

// Stateful _AGGraph rule that observes content, transaction, time, and environment inputs
// and rewrites DisplayList.Key output when content transitions are active.
private struct InterpolatedDisplayList<Content: InterpolatableContent>: StatefulRule {
    typealias Value = DisplayList

    var group: DisplayList.InterpolatorGroup
    var displayList: Attribute<DisplayList>
    var content: Attribute<Content>
    var environment: Attribute<EnvironmentValues>
    var time: Attribute<Time>
    var phase: Attribute<Phase>
    var transaction: Attribute<Transaction>
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var pixelLength: Attribute<CGFloat>
    var animatesSize: Bool
    var defersRender: Bool
    var supportsVFD: Bool

    private var previousContent: Content?
    private var previousSize: CGSize?
    private var previousDisplayList: DisplayList?
    private var contentSeed = DisplayList.Seed()

    init(
        group: DisplayList.InterpolatorGroup,
        displayList: Attribute<DisplayList>,
        content: Attribute<Content>,
        environment: Attribute<EnvironmentValues>,
        time: Attribute<Time>,
        phase: Attribute<Phase>,
        transaction: Attribute<Transaction>,
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        pixelLength: Attribute<CGFloat>,
        animatesSize: Bool,
        defersRender: Bool,
        supportsVFD: Bool
    ) {
        self.group = group
        self.displayList = displayList
        self.content = content
        self.environment = environment
        self.time = time
        self.phase = phase
        self.transaction = transaction
        self.position = position
        self.size = size
        self.pixelLength = pixelLength
        self.animatesSize = animatesSize
        self.defersRender = defersRender
        self.supportsVFD = supportsVFD
    }

    mutating func updateValue() {
        let targetContent = content.value
        let targetList = displayList.value
        let currentEnvironment = environment.value
        let currentTime = time.value
        let currentTransaction = transaction.value
        let currentSize = size.value.value
        _ = phase.value
        _ = position.value
        _ = pixelLength.value

        var state = currentEnvironment.contentTransitionState
        var transition = currentTransaction.disablesContentTransitions
            ? ContentTransition.identity
            : currentEnvironment.contentTransition

        if transition == ContentTransition.defaultTransition {
            transition = Content.defaultTransition
        }
        transition.applyEnvironmentValues(
            style: state.style,
            layoutDirection: currentEnvironment.layoutDirection
        )
        state.transition = transition
        state.animation = currentTransaction.effectiveAnimation

        var appliesTransition = false
        var contentChanged = false
        var sizeChanged = false
        if let previousContent {
            contentChanged = previousContent.requiresTransition(to: targetContent)
            sizeChanged = previousSize.map { $0 != currentSize } ?? false
            let retargetsActiveSizeTransition = !contentChanged &&
                sizeChanged &&
                group.hasActiveInterpolators
            let shouldTransition = !currentTransaction.disablesContentTransitions
                && !retargetsActiveSizeTransition
                && (contentChanged || (sizeChanged && previousContent.appliesTransitionsForSizeChanges))

            if shouldTransition {
                var modifiedState = state
                previousContent.modifyTransition(state: &modifiedState, to: targetContent)
                if modifiedState.animation == nil {
                    modifiedState.animation = previousContent.defaultAnimation(to: targetContent)
                }
                if previousContent.addsDrawingGroup || currentEnvironment.contentTransitionAddsDrawingGroup {
                    modifiedState.options.insert(.addsDrawingGroup)
                }
                state = modifiedState
                appliesTransition = !modifiedState.transition.isIdentity &&
                    modifiedState.animation != nil
            }
        }

        let previousList = previousDisplayList
        let displayListChanged = previousList.map {
            !$0.hasSameInterpolationSurface(as: targetList)
        } ?? true
        if previousList == nil || contentChanged || sizeChanged || displayListChanged {
            contentSeed = DisplayList.Seed(decodedValue: contentSeed.value &+ 1)
        }

        let output: DisplayList
        if appliesTransition {
            output = group.update(
                contentSeed: contentSeed,
                current: previousList ?? targetList,
                target: targetList,
                state: state,
                time: currentTime,
                animatesSize: animatesSize,
                defersRender: defersRender,
                supportsVFD: supportsVFD
            )
        } else {
            group.setCurrentContents(
                contentSeed: contentSeed,
                target: targetList,
                time: currentTime,
                supportsVFD: supportsVFD,
                rasterizationOptions: state.rasterizationOptions
            )
            group.updateTime(currentTime)
            output = group.apply(to: targetList)
        }
        previousContent = targetContent
        previousSize = currentSize
        previousDisplayList = targetList
        _AGGraph.setStatefulOutput(output)
    }
}

extension _ViewOutputs {
    mutating func applyInterpolatorGroup<Content: InterpolatableContent>(
        _ group: DisplayList.InterpolatorGroup,
        content: Attribute<Content>,
        inputs: _ViewInputs,
        animatesSize: Bool,
        defersRender: Bool
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("_ViewOutputs.applyInterpolatorGroup called outside an active _AGGraph context.")
        }
        guard let displayList = preferences.reducedValue(for: DisplayList.Key.self, in: graph) else {
            return
        }

        let environment = inputs.base.cachedEnvironment.value.environment
        let pixelLength: Attribute<CGFloat> = graph.makeRule {
            environment.value.animationPixelLength
        }
        let interpolated = graph.makeStatefulRule(
            InterpolatedDisplayList(
                group: group,
                displayList: displayList,
                content: content,
                environment: environment,
                time: inputs.base.time,
                phase: inputs.base.phase,
                transaction: inputs.base.transaction,
                position: inputs.position,
                size: inputs.size,
                pixelLength: pixelLength,
                animatesSize: animatesSize,
                defersRender: defersRender,
                supportsVFD: inputs.supportsVFD
            )
        )
        preferences.setValue(interpolated.identifier, for: DisplayList.Key.self)
    }
}
