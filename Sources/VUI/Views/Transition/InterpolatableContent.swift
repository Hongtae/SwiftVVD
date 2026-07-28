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
        enum Phase: Hashable {
            case pending
            case first
            case second
            case running
        }

        // Current display-list payload tracked by an interpolation layer.
        struct Contents {
            var list: DisplayList
            var origin: CGPoint
            var rbList: (any RBDisplayListContents)?
            var nextTime: Time
            var numericValue: Float?

            // Backend-local state that remains outside the private five-field
            // recording carrier until its producers are modeled.
            var animation: InterpolatorAnimation?
            var contentsScale: Float
            var version: DisplayList.Version?

            var displayList: DisplayList {
                get { list }
                set {
                    list = newValue
                    rbList = nil
                    nextTime = .infinity
                }
            }

            init(
                displayList: DisplayList = DisplayList(),
                origin: CGPoint = .zero,
                numericValue: Float? = nil,
                animation: InterpolatorAnimation? = nil,
                contentsScale: Float = 1,
                version: DisplayList.Version? = nil
            ) {
                self.list = displayList
                self.origin = origin
                self.rbList = nil
                self.nextTime = .infinity
                self.numericValue = numericValue
                self.animation = animation
                self.contentsScale = contentsScale
                self.version = version
            }

            mutating func preparedList(
                using renderer: DisplayList.GraphicsRenderer,
                at time: Time
            ) -> DisplayList {
                if let rbList, time < nextTime,
                   let local = rbList as? DisplayList.LocalContents {
                    return local.list
                }

                var prepared = renderer.sample(list: list, at: time)
                prepared.numericValue = numericValue
                nextTime = renderer.nextTime
                let contents = DisplayList.LocalContents(list: prepared)
                rbList = contents
                return contents.list
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
        private(set) var renderer: DisplayList.GraphicsRenderer?
        private(set) var needsUpdate: Bool

        init() {
            self.contents = Contents()
            self.currentTime = .zero
            self.maxDuration = .infinity
            self.nextUpdateTime = .infinity
            self.removed = []
            self.renderer = nil
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
            animation: Animation? = nil,
            numericValue: Float? = nil
        ) {
            guard !contents.matches(list: list, origin: origin, version: version) else {
                contents.numericValue = numericValue
                return
            }

            if let removedState = state, !contents.displayList.isEmptyForInterpolation {
                // Coalesce an unprepared tail and keep the prepared history
                // bounded before appending the new removal.
                if removed.last?.phase == .pending {
                    removed.removeLast()
                } else if removed.count >= 8 {
                    remove(prefix: 0)
                }
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
                numericValue: numericValue,
                animation: animation.map { InterpolatorAnimation(animation: $0) },
                contentsScale: contents.contentsScale,
                version: version
            )
            if state == nil {
                // Layout can refine the endpoint during the preparation passes.
                // Only the last removal targets the current contents. Earlier
                // entries target the following retained contents and must keep
                // their historical endpoints across later refinements.
                removed.last?.interpolator?.setTo(list)
            }
            maxDuration = .infinity
            needsUpdate = true
        }

        mutating func updateInterpolators(
            contentsScale: Float,
            maxDuration: Double,
            time: Time = .zero
        ) {
            let timeChanged = currentTime.seconds != time.seconds
            self.contents.contentsScale = contentsScale
            self.maxDuration = maxDuration
            self.currentTime = time

            if timeChanged && !removed.isEmpty {
                needsUpdate = true
            }

            guard needsUpdate else { return }
            needsUpdate = false

            let renderer: DisplayList.GraphicsRenderer
            if let currentRenderer = self.renderer {
                renderer = currentRenderer
            } else {
                let currentRenderer = DisplayList.GraphicsRenderer()
                self.renderer = currentRenderer
                renderer = currentRenderer
            }

            // Each earlier removal contributes its sampled presentation to the
            // source of the following removal. Final output remains owned by
            // the last removal while the ordered entries keep independent timing.
            var composedPresentation: DisplayList?
            var index = removed.startIndex
            while index < removed.endIndex {
                switch removed[index].phase {
                case .pending:
                    removed[index].phase = .first
                    removed[index].startTime = currentTime
                case .first:
                    removed[index].phase = .second
                    removed[index].startTime = currentTime
                case .second:
                    removed[index].phase = .running
                    let preparationDuration = currentTime.seconds - removed[index].startTime.seconds
                    if preparationDuration > 1.0 / 30.0 {
                        removed[index].startTime = currentTime
                    }
                case .running:
                    break
                }

                if removed[index].activeDuration >= 0,
                   currentTime.seconds - removed[index].startTime.seconds >=
                    removed[index].activeDuration {
                    remove(prefix: index)
                    composedPresentation = nil
                    index = removed.startIndex
                    continue
                }

                let from = if let composedPresentation {
                    composedPresentation
                } else {
                    removed[index].contents.preparedList(
                        using: renderer,
                        at: currentTime
                    )
                }
                let hasFollowingRemoval =
                    index < removed.index(before: removed.endIndex)
                if let currentInterpolator = removed[index].interpolator {
                    let updatedInterpolator = currentInterpolator.copy()
                        as! RBDisplayListInterpolator
                    // Intermediate renderer contents are local to the following
                    // endpoint. Typed text lists retain scene coordinates here,
                    // so align that source before flattening its presentation.
                    let alignsIntermediateSource = hasFollowingRemoval &&
                        currentInterpolator.requiresIntermediateTextAlignment
                    updatedInterpolator.setFrom(
                        alignsIntermediateSource
                            ? from.aligningInterpolationCenter(
                                to: currentInterpolator.to
                            )
                            : from
                    )
                    removed[index].interpolator = updatedInterpolator
                } else {
                    let logicalFrom = if composedPresentation == nil {
                        from
                    } else {
                        removed[index].contents.preparedList(
                            using: renderer,
                            at: currentTime
                        )
                    }
                    let nextIndex = removed.index(after: index)
                    let to = if nextIndex < removed.endIndex {
                        removed[nextIndex].contents.preparedList(
                            using: renderer,
                            at: currentTime
                        )
                    } else {
                        contents.preparedList(
                            using: renderer,
                            at: currentTime
                        )
                    }
                    var options: [RBDisplayListInterpolatorOptionKey: Any] = [
                        .transition: removed[index].rbTransition,
                    ]
                    if let animation = removed[index].animation {
                        options[.animation] = animation.rbAnimation
                    }
                    let interpolator = RBDisplayListInterpolator(
                        from: logicalFrom,
                        to: to,
                        options: options
                    )
                    let alignsIntermediateSource = hasFollowingRemoval &&
                        interpolator.requiresIntermediateTextAlignment
                    if composedPresentation != nil || alignsIntermediateSource {
                        interpolator.setFrom(
                            alignsIntermediateSource
                                ? from.aligningInterpolationCenter(to: to)
                                : from
                        )
                    }
                    removed[index].interpolator = interpolator
                    let interpolatorDuration = removed[index].interpolator?.activeDuration ?? 0
                    let contentDuration = interpolatorDuration > 0
                        ? interpolatorDuration
                        : removed[index].interpolator?.animation?.activeDuration ?? 0
                    removed[index].activeDuration = min(
                        maxDuration,
                        contentDuration
                    )
                }
                if index < removed.index(before: removed.endIndex),
                   let interpolator = removed[index].interpolator {
                    let elapsed = Float(
                        max(
                            currentTime.seconds -
                                removed[index].startTime.seconds,
                            0
                        )
                    )
                    composedPresentation = interpolator
                        .copyContents(withProgress: elapsed)
                        .materializingInterpolationContents()
                }
                index = removed.index(after: index)
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

            if let removal = removed.last,
               !removal.state.transition.isIdentity,
               !removal.rbTransition.effects.isEmpty {
                let elapsed = Float(max(currentTime.seconds - removal.startTime.seconds, 0))
                let contents = removal.interpolator?.copyContents(withProgress: elapsed)
                    ?? removal.contents.displayList
                list.appendEffect(
                    .contentTransition(removal.state),
                    contents: contents
                )
            }
            return true
        }

        mutating func invalidateContentsScale() {
            contents.contentsScale = 0
            needsUpdate = true
        }

        mutating func remove(prefix: Int) {
            precondition(prefix >= removed.startIndex)
            precondition(prefix < removed.endIndex)
            removed.removeFirst(prefix + 1)
            // Every retained entry must be rebuilt from the new first source.
            for index in removed.indices {
                removed[index].interpolator = nil
            }
            needsUpdate = true
            updateNextUpdateTime()
        }

        private mutating func updateNextUpdateTime() {
            guard !removed.isEmpty else {
                nextUpdateTime = .infinity
                return
            }

            var nextTime = Time.infinity
            for removal in removed where removal.activeDuration >= 0 {
                let candidate = Time(seconds: removal.startTime.seconds + removal.activeDuration)
                if candidate < nextTime {
                    nextTime = candidate
                }
            }
            nextUpdateTime = nextTime
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
            transition: ContentTransition,
            supportsVFD: Bool,
            rasterizationOptions: RasterizationOptions
        ) {
        }

        func setCurrentContents(
            contentSeed: DisplayList.Seed,
            target: DisplayList,
            transition: ContentTransition,
            time: Time,
            supportsVFD: Bool,
            rasterizationOptions: RasterizationOptions
        ) {
            setCurrentContents(
                contentSeed: contentSeed,
                target: target,
                transition: transition,
                supportsVFD: supportsVFD,
                rasterizationOptions: rasterizationOptions
            )
            updateTime(time)
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
            if layer.removedCount > 0 {
                layer.remove(prefix: layer.removedCount - 1)
            }
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
            transition: ContentTransition,
            supportsVFD: Bool,
            rasterizationOptions: RasterizationOptions
        ) {
            lastContentSeed = contentSeed
            supportsVariableFrameDuration = supportsVFD
            self.rasterizationOptions = rasterizationOptions
            layer.setDisplayList(
                target,
                origin: .zero,
                version: DisplayList.Version(value: Int(contentSeed.value)),
                numericValue: transition.numericValue
            )
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
                version: DisplayList.Version(value: Int(previousContentSeed.value)),
                numericValue: layer.contents.numericValue
            )
            layer.setDisplayList(
                target,
                origin: .zero,
                version: DisplayList.Version(value: Int(contentSeed.value)),
                state: state,
                animation: state.animation,
                numericValue: state.transition.numericValue
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

enum _ShapeStyle_LayerID: Equatable {
    case styled(_ShapeStyle_Name, UInt16)
    case customStyle(UInt32)
    case named(String?)
    case unstyled
}

final class _ShapeStyle_InterpolatorGroup: DisplayList.InterpolatorGroup {
    struct Layer {
        var id: _ShapeStyle_LayerID
        var serial: UInt32
        var style: _ShapeStyle_Pack.Style?
        var state: DisplayList.InterpolatorLayer
        var isRemoved: Bool
    }

    private(set) var layers: [Layer] = []
    private(set) var contentsScale: Float = 1
    private(set) var rasterizationOptions = RasterizationOptions()
    private(set) var serial: UInt32 = 0
    private(set) var cursor: Int32 = 0

    override var hasActiveInterpolators: Bool {
        layers.contains { $0.state.removedCount > 0 }
    }

    override var activeSourceBounds: CGRect? {
        layers.lazy.compactMap {
            $0.state.removed.first?.interpolator?.from.interpolationBounds
        }.first
    }

    override func discardActiveInterpolators() {
        for index in layers.indices {
            let removedCount = layers[index].state.removedCount
            if removedCount > 0 {
                layers[index].state.remove(prefix: removedCount - 1)
            }
        }
    }

    override func nextUpdate(after time: Time) -> Time {
        layers.reduce(.infinity) { result, layer in
            let candidate = layer.state.removedCount == 0
                ? layer.state.currentTime
                : layer.state.nextUpdateTime
            return min(result, candidate)
        }
    }

    override func updateTime(_ time: Time) {
        for index in layers.indices {
            layers[index].state.updateInterpolators(
                contentsScale: contentsScale,
                maxDuration: maxDuration,
                time: time
            )
        }
        scheduleNextUpdate(after: time)
    }

    override func setCurrentContents(
        contentSeed: DisplayList.Seed,
        target: DisplayList,
        transition: ContentTransition,
        supportsVFD: Bool,
        rasterizationOptions: RasterizationOptions
    ) {
        let index = currentLayerIndex()
        self.rasterizationOptions = rasterizationOptions
        layers[index].state.setDisplayList(
            target,
            origin: .zero,
            version: DisplayList.Version(value: Int(contentSeed.value)),
            numericValue: transition.numericValue
        )
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
        let index = currentLayerIndex()
        rasterizationOptions = state.rasterizationOptions
        let previousVersion = layers[index].state.contents.version ?? DisplayList.Version()
        let previousNumericValue = layers[index].state.contents.numericValue

        layers[index].state.setDisplayList(
            current,
            origin: .zero,
            version: previousVersion,
            numericValue: previousNumericValue
        )
        layers[index].state.setDisplayList(
            target,
            origin: .zero,
            version: DisplayList.Version(value: Int(contentSeed.value)),
            state: state,
            animation: state.animation,
            numericValue: state.transition.numericValue
        )
        layers[index].state.updateInterpolators(
            contentsScale: contentsScale,
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

    override func apply(to list: DisplayList) -> DisplayList {
        var output = DisplayList()
        var replacedCurrent = false
        for index in layers.indices {
            replacedCurrent = layers[index].state.updateOutput(
                list: &output,
                frame: .zero,
                contentOffset: .zero,
                version: DisplayList.Version(value: Int(serial)),
                rasterizationOptions: rasterizationOptions
            ) || replacedCurrent
        }
        return replacedCurrent ? output : list
    }

    private func currentLayerIndex() -> Int {
        if layers.isEmpty {
            layers.append(
                Layer(
                    id: .unstyled,
                    serial: serial,
                    style: nil,
                    state: DisplayList.InterpolatorLayer(),
                    isRemoved: false
                )
            )
        }
        cursor = 0
        return 0
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

private extension DisplayList {
    var isEmptyForInterpolation: Bool {
        items.isEmpty && debugItems.isEmpty && effects.isEmpty && interpolationBounds == nil
    }

    func aligningInterpolationCenter(to target: DisplayList) -> DisplayList {
        guard let sourceBounds = interpolationBounds,
              let targetBounds = target.interpolationBounds else {
            return self
        }
        let offset = CGSize(
            width: targetBounds.midX - sourceBounds.midX,
            height: targetBounds.midY - sourceBounds.midY
        )
        guard offset.width != 0 || offset.height != 0 else {
            return self
        }
        return translated(by: offset)
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
    var animatedPosition: OptionalAttribute<CGPoint>
    var containerPosition: Attribute<CGPoint>
    var animatedSize: OptionalAttribute<ViewSize>
    var presentationDisplayList: OptionalAttribute<DisplayList>
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
        animatedPosition: OptionalAttribute<CGPoint>,
        containerPosition: Attribute<CGPoint>,
        animatedSize: OptionalAttribute<ViewSize>,
        presentationDisplayList: OptionalAttribute<DisplayList>,
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
        self.animatedPosition = animatedPosition
        self.containerPosition = containerPosition
        self.animatedSize = animatedSize
        self.presentationDisplayList = presentationDisplayList
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
        let currentTransaction = transaction.value
        let currentSize = size.value.value
        _ = phase.value
        let modelPosition = position.value
        let presentationPosition = animatedPosition.value ?? modelPosition
        _ = containerPosition.value
        let presentationSize = animatedSize.value?.value ?? currentSize
        _ = pixelLength.value
        let currentPresentationList = presentationDisplayList.value ?? targetList
        // The active interpolator keeps endpoint contents in model geometry.
        // Compensate the centered local size presentation before applying the
        // surrounding frame's presentation position.
        let localContentOffset = CGSize(
            width: (presentationSize.width - currentSize.width) * 0.5,
            height: (presentationSize.height - currentSize.height) * 0.5
        )
        let presentationOffset = CGSize(
            width: presentationPosition.x - modelPosition.x
                + localContentOffset.width,
            height: presentationPosition.y - modelPosition.y
                + localContentOffset.height
        )
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
        if transition.symbolReplaceConfiguration != nil {
            state.options.insert(.animatesDifferentContent)
        }
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

        var output: DisplayList
        if appliesTransition {
            output = group.update(
                contentSeed: contentSeed,
                current: previousList ?? targetList,
                target: targetList,
                state: state,
                time: time.value,
                animatesSize: animatesSize,
                defersRender: defersRender,
                supportsVFD: supportsVFD
            )
            .translated(by: presentationOffset)
        } else {
            group.setCurrentContents(
                contentSeed: contentSeed,
                target: targetList,
                transition: state.transition,
                supportsVFD: supportsVFD,
                rasterizationOptions: state.rasterizationOptions
            )
            if group.hasActiveInterpolators {
                group.updateTime(time.value)
            }
            output = group.hasActiveInterpolators
                ? group.apply(to: targetList).translated(by: presentationOffset)
                : currentPresentationList
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
        animatedPosition: Attribute<CGPoint>? = nil,
        animatedSize: Attribute<ViewSize>? = nil,
        presentationDisplayList: Attribute<DisplayList>? = nil,
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
                animatedPosition: OptionalAttribute(animatedPosition),
                containerPosition: inputs.containerPosition,
                animatedSize: OptionalAttribute(animatedSize),
                presentationDisplayList: OptionalAttribute(presentationDisplayList),
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
