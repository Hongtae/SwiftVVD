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
                numericValue: Float? = nil
            ) {
                self.list = displayList
                self.origin = origin
                self.rbList = nil
                self.nextTime = .infinity
                self.numericValue = numericValue
            }

            mutating func preparedList(
                using renderer: DisplayList.GraphicsRenderer,
                at time: Time
            ) -> DisplayList {
                if let rbList, time < nextTime,
                   let local = rbList as? DisplayList.LocalContents {
                    return local.list
                }

                var prepared = renderer.sample(list: list, at: time).translated(
                    by: CGSize(width: origin.x, height: origin.y)
                )
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
            var interpolator: RBDisplayListInterpolator?
            var transition: RBTransition?
            var animation: RBAnimation
            var listener: AnimationListener?
            var begin: Time
            var duration: Double
            var phase: Phase
        }

        fileprivate(set) var contents: Contents
        fileprivate(set) var removed: [Removed]
        fileprivate(set) var time: Time
        fileprivate(set) var renderer: DisplayList.GraphicsRenderer?
        fileprivate(set) var contentSeed: DisplayList.Seed
        fileprivate(set) var supportsVFD: Bool
        fileprivate(set) var needsUpdate: Bool

        init() {
            self.contents = Contents()
            self.removed = []
            self.time = .zero
            self.renderer = nil
            self.contentSeed = DisplayList.Seed()
            self.supportsVFD = false
            self.needsUpdate = true
        }

        var removedCount: Int {
            removed.count
        }

        var nextUpdateTime: Time {
            removed.reduce(.infinity) { result, removal in
                guard removal.duration >= 0 else {
                    return result
                }
                return min(
                    result,
                    Time(seconds: removal.begin.seconds + removal.duration)
                )
            }
        }

        mutating func setDisplayList(
            _ list: DisplayList,
            origin: CGPoint
        ) {
            guard contents.list != list || contents.origin != origin else {
                return
            }

            contents = Contents(
                displayList: list,
                origin: origin,
                numericValue: contents.numericValue
            )
            if !removed.isEmpty {
                removed[removed.index(before: removed.endIndex)].interpolator = nil
            }
            needsUpdate = true
        }

        mutating func updateInterpolators(
            contentsScale: Float,
            maxDuration: Double
        ) {
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
                    removed[index].begin = time
                case .first:
                    removed[index].phase = .second
                    removed[index].begin = time
                case .second:
                    removed[index].phase = .running
                    let preparationDuration = time.seconds - removed[index].begin.seconds
                    if preparationDuration > 1.0 / 30.0 {
                        removed[index].begin = time
                    }
                case .running:
                    break
                }

                if removed[index].duration >= 0,
                   time.seconds - removed[index].begin.seconds >=
                    removed[index].duration {
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
                        at: time
                    )
                }
                if let currentInterpolator = removed[index].interpolator {
                    let updatedInterpolator = currentInterpolator.copy()
                        as! RBDisplayListInterpolator
                    updatedInterpolator.setFrom(from)
                    removed[index].interpolator = updatedInterpolator
                } else {
                    let logicalFrom = if composedPresentation == nil {
                        from
                    } else {
                        removed[index].contents.preparedList(
                            using: renderer,
                            at: time
                        )
                    }
                    let nextIndex = removed.index(after: index)
                    let to = if nextIndex < removed.endIndex {
                        removed[nextIndex].contents.preparedList(
                            using: renderer,
                            at: time
                        )
                    } else {
                        contents.preparedList(
                            using: renderer,
                            at: time
                        )
                    }
                    var options: [RBDisplayListInterpolatorOptionKey: Any] = [
                        .animation: removed[index].animation,
                    ]
                    if let transition = removed[index].transition {
                        options[.transition] = transition
                    }
                    let interpolator = RBDisplayListInterpolator(
                        from: logicalFrom,
                        to: to,
                        options: options
                    )
                    if composedPresentation != nil {
                        interpolator.setFrom(from)
                    }
                    removed[index].interpolator = interpolator
                    let interpolatorDuration = interpolator.activeDuration
                    let contentDuration = interpolatorDuration > 0
                        ? interpolatorDuration
                        : interpolator.animation?.activeDuration ?? 0
                    removed[index].duration = min(
                        maxDuration,
                        contentDuration
                    )
                }
                if index < removed.index(before: removed.endIndex),
                   let interpolator = removed[index].interpolator {
                    let elapsed = Float(
                        max(
                            time.seconds -
                                removed[index].begin.seconds,
                            0
                        )
                    )
                    composedPresentation = interpolator
                        .copyContents(withProgress: elapsed)
                        .materializingInterpolationContents()
                }
                index = removed.index(after: index)
            }
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

            let index = removed.index(before: removed.endIndex)
            if removed.count == 1,
               removed[index].interpolator?.onlyFades != false,
               idsAreDisjoint(
                   removed[index].contents.list,
                   contents.list
               ) {
                let progress = removed[index].animation.evaluateAtTime(
                    time.seconds - removed[index].begin.seconds
                )
                let oldOrigin = CGPoint(
                    x: contentOffset.width +
                        removed[index].contents.origin.x -
                        contents.origin.x,
                    y: contentOffset.height +
                        removed[index].contents.origin.y -
                        contents.origin.y
                )
                let currentOrigin = CGPoint(
                    x: contentOffset.width,
                    y: contentOffset.height
                )
                var output = DisplayList()
                output.appendEffect(
                    .opacity(1 - progress),
                    contents: removed[index].contents.list,
                    frame: CGRect(origin: oldOrigin, size: frame.size),
                    version: version
                )
                output.appendEffect(
                    .opacity(progress),
                    contents: contents.list,
                    frame: CGRect(origin: currentOrigin, size: frame.size),
                    version: version
                )
                output.numericValue = contents.numericValue
                list = output
                return true
            }

            guard let interpolator = removed[index].interpolator else {
                list = DisplayList()
                return true
            }

            let elapsed = Float(max(time.seconds - removed[index].begin.seconds, 0))
            let sampledBounds = interpolator.boundingRect(
                withProgress: elapsed
            )
            let bounds = (
                sampledBounds.isNull ? CGRect.zero : sampledBounds
            ).integral
            let sampled = interpolator
                .copyContents(withProgress: elapsed)
            if supportsVFD,
               let viewGraph = GraphHost.currentHost as? ViewGraph {
                viewGraph.nextUpdate.views.maxVelocity(
                    interpolator.maxAbsoluteVelocity(
                        withProgress: elapsed
                    )
                )
            }

            var options = rasterizationOptions
            options.flags.insert(.rgbaContext)
            let content = DisplayList.Content(
                drawing: DisplayList.LocalContents(list: sampled),
                origin: bounds.origin,
                options: options,
                seed: DisplayList.Seed(version)
            )
            let outputOffset = CGSize(
                width: contentOffset.width - contents.origin.x,
                height: contentOffset.height - contents.origin.y
            )
            let outputFrame = bounds.offsetBy(
                dx: outputOffset.width,
                dy: outputOffset.height
            )
            var output = DisplayList()
            output.items.append(DisplayList.Item(
                content: content,
                frame: outputFrame,
                identity: .none,
                version: version
            ))
            output.interpolationBounds = outputFrame
            output.numericValue = sampled.numericValue
            list = output
            return true
        }

        mutating func reset() {
            for removal in removed {
                removal.listener?.animationWasRemoved()
            }
            removed.removeAll(keepingCapacity: true)
            renderer = nil
            needsUpdate = true
        }

        mutating func invalidateContentsScale() {
            contents.rbList = nil
            contents.nextTime = .infinity
            for index in removed.indices {
                removed[index].contents.rbList = nil
                removed[index].contents.nextTime = .infinity
                removed[index].interpolator = nil
            }
            needsUpdate = true
        }

        mutating func remove(prefix: Int) {
            precondition(prefix >= removed.startIndex)
            precondition(prefix < removed.endIndex)
            for removal in removed[...prefix] {
                removal.listener?.animationWasRemoved()
            }
            removed.removeFirst(prefix + 1)
            // Every retained entry must be rebuilt from the new first source.
            for index in removed.indices {
                removed[index].interpolator = nil
            }
            needsUpdate = true
        }

    }

    class InterpolatorGroup {
        var maxDuration: Double

        var features: DisplayList.Features {
            []
        }

        var properties: DisplayList.Properties {
            []
        }

        init(maxDuration: Double = .infinity) {
            self.maxDuration = maxDuration
        }

        func reset() {
        }

        func nextUpdate(after time: Time) -> Time {
            .infinity
        }

        func update(
            contentSeed: DisplayList.Seed,
            transition: ContentTransition,
            animation: Animation?,
            listener: AnimationListener?,
            contentsScale: Float,
            rasterizationOptions: RasterizationOptions,
            supportsVFD: Bool
        ) {
        }

        func rewriteInterpolation(
            serial: UInt32,
            list: inout DisplayList,
            time: Attribute<Time>,
            frame: CGRect,
            contentOrigin: CGPoint,
            contentOffset: CGSize,
            version: DisplayList.Version
        ) -> Bool {
            false
        }

        func apply(to item: inout DisplayList.Item) {
        }
    }

    final class UnaryInterpolatorGroup: InterpolatorGroup {
        private(set) var layer = InterpolatorLayer()
        private(set) var contentSeed = DisplayList.Seed()
        private(set) var contentsScale: Float = 0
        private(set) var rasterizationOptions = RasterizationOptions()

        override var features: DisplayList.Features {
            var result = layer.contents.list.interpolationFeatures
            for removal in layer.removed {
                result.formUnion(removal.contents.list.interpolationFeatures)
            }
            return result
        }

        override var properties: DisplayList.Properties {
            []
        }

        override func reset() {
            layer.reset()
        }

        override func nextUpdate(after time: Time) -> Time {
            layer.removed.isEmpty ? layer.time : layer.nextUpdateTime
        }

        override func update(
            contentSeed: DisplayList.Seed,
            transition: ContentTransition,
            animation: Animation?,
            listener: AnimationListener?,
            contentsScale: Float,
            rasterizationOptions: RasterizationOptions,
            supportsVFD: Bool
        ) {
            if layer.contentSeed != contentSeed, let animation {
                if layer.removed.last?.phase == .pending {
                    layer.remove(prefix: layer.removed.index(before: layer.removed.endIndex))
                } else if layer.removed.count >= 8 {
                    layer.remove(prefix: layer.removed.startIndex)
                }

                listener?.animationWasAdded()
                layer.removed.append(
                    InterpolatorLayer.Removed(
                        contents: layer.contents,
                        interpolator: nil,
                        transition: transition.rbTransition,
                        animation: animation.rbAnimation,
                        listener: listener,
                        begin: .zero,
                        duration: -1,
                        phase: .pending
                    )
                )
                layer.needsUpdate = true
            }

            layer.contentSeed = contentSeed
            layer.supportsVFD = supportsVFD
            layer.contents.numericValue = transition.numericValue
            self.contentSeed = contentSeed
            if self.contentsScale != contentsScale {
                self.contentsScale = contentsScale
                layer.invalidateContentsScale()
            }
            self.rasterizationOptions = rasterizationOptions
        }

        override func rewriteInterpolation(
            serial: UInt32,
            list: inout DisplayList,
            time: Attribute<Time>,
            frame: CGRect,
            contentOrigin: CGPoint,
            contentOffset: CGSize,
            version: DisplayList.Version
        ) -> Bool {
            layer.setDisplayList(list, origin: contentOrigin)
            guard !layer.removed.isEmpty else {
                return false
            }

            let currentTime = time.value
            if layer.time != currentTime {
                layer.time = currentTime
                layer.needsUpdate = true
            }
            guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
                fatalError(
                    "UnaryInterpolatorGroup.rewriteInterpolation requires an active ViewGraph host."
                )
            }
            viewGraph.nextUpdate.views.at(currentTime)
            layer.updateInterpolators(
                contentsScale: contentsScale,
                maxDuration: maxDuration
            )
            return layer.updateOutput(
                list: &list,
                frame: frame,
                contentOffset: contentOffset,
                version: version,
                rasterizationOptions: rasterizationOptions
            )
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
    enum AddLayerResult {
        case direct(
            group: _ShapeStyle_InterpolatorGroup,
            serial: UInt32
        )
        case replacement(
            style: _ShapeStyle_Pack.Style?,
            group: _ShapeStyle_InterpolatorGroup,
            serial: UInt32
        )
    }

    struct Layer {
        var id: _ShapeStyle_LayerID
        var serial: UInt32
        var style: _ShapeStyle_Pack.Style?
        var state: DisplayList.InterpolatorLayer
        var isRemoved: Bool
    }

    private(set) var layers: [Layer] = []
    private(set) var contentsScale: Float = 0
    private(set) var rasterizationOptions = RasterizationOptions()
    private(set) var serial: UInt32 = 0
    private(set) var cursor: Int32 = 0

    override var features: DisplayList.Features {
        layers.reduce(into: DisplayList.Features()) { result, layer in
            result.formUnion(layer.state.contents.list.interpolationFeatures)
            for removal in layer.state.removed {
                result.formUnion(removal.contents.list.interpolationFeatures)
            }
        }
    }

    override var properties: DisplayList.Properties {
        []
    }

    override func reset() {
        for index in layers.indices {
            layers[index].state.reset()
        }
    }

    override func nextUpdate(after time: Time) -> Time {
        layers.reduce(.infinity) { result, layer in
            let candidate = layer.state.removedCount == 0
                ? layer.state.time
                : layer.state.nextUpdateTime
            return min(result, candidate)
        }
    }

    func addLayer(
        id: _ShapeStyle_LayerID,
        style: _ShapeStyle_Pack.Style?
    ) -> AddLayerResult {
        let index = Int(cursor)
        cursor += 1

        if index == layers.count {
            let layerSerial = serial
            serial &+= 1
            layers.append(
                Layer(
                    id: id,
                    serial: layerSerial,
                    style: style,
                    state: DisplayList.InterpolatorLayer(),
                    isRemoved: false
                )
            )
            return .direct(group: self, serial: layerSerial)
        }

        precondition(index < layers.count)
        guard layers[index].id == id else {
            layers[index].isRemoved = true
            return .replacement(
                style: layers[index].style,
                group: self,
                serial: layers[index].serial
            )
        }
        layers[index].style = style
        layers[index].isRemoved = false
        return .direct(group: self, serial: layers[index].serial)
    }

    func nextTrailingLayer() -> (
        style: _ShapeStyle_Pack.Style?,
        group: _ShapeStyle_InterpolatorGroup,
        serial: UInt32
    )? {
        let index = Int(cursor)
        guard index < layers.count else {
            return nil
        }
        cursor += 1
        layers[index].isRemoved = true
        return (layers[index].style, self, layers[index].serial)
    }

    func resetLayerCursor() {
        cursor = 0
    }

    override func update(
        contentSeed: DisplayList.Seed,
        transition: ContentTransition,
        animation: Animation?,
        listener: AnimationListener?,
        contentsScale: Float,
        rasterizationOptions: RasterizationOptions,
        supportsVFD: Bool
    ) {
        var index = layers.startIndex
        while index < layers.endIndex {
            if layers[index].state.contentSeed != contentSeed,
               let animation {
                if layers[index].state.removed.last?.phase == .pending {
                    let last = layers[index].state.removed.index(
                        before: layers[index].state.removed.endIndex
                    )
                    layers[index].state.remove(prefix: last)
                } else if layers[index].state.removed.count >= 8 {
                    layers[index].state.remove(
                        prefix: layers[index].state.removed.startIndex
                    )
                }

                listener?.animationWasAdded()
                layers[index].state.removed.append(
                    DisplayList.InterpolatorLayer.Removed(
                        contents: layers[index].state.contents,
                        interpolator: nil,
                        transition: transition.rbTransition,
                        animation: animation.rbAnimation,
                        listener: listener,
                        begin: .zero,
                        duration: -1,
                        phase: .pending
                    )
                )
                layers[index].state.needsUpdate = true
            }
            layers[index].state.contentSeed = contentSeed
            layers[index].state.supportsVFD = supportsVFD
            layers[index].state.contents.numericValue = transition.numericValue

            if self.contentsScale != contentsScale {
                layers[index].state.invalidateContentsScale()
            }
            if layers[index].isRemoved &&
                layers[index].state.removedCount == 0 {
                layers.remove(at: index)
                continue
            }
            index += 1
        }
        self.contentsScale = contentsScale
        self.rasterizationOptions = rasterizationOptions
    }

    override func rewriteInterpolation(
        serial: UInt32,
        list: inout DisplayList,
        time: Attribute<Time>,
        frame: CGRect,
        contentOrigin: CGPoint,
        contentOffset: CGSize,
        version: DisplayList.Version
    ) -> Bool {
        guard let index = layers.firstIndex(where: { $0.serial == serial }) else {
            list = DisplayList()
            return false
        }

        layers[index].state.setDisplayList(list, origin: contentOrigin)
        guard !layers[index].state.removed.isEmpty else {
            return false
        }

        let currentTime = time.value
        if layers[index].state.time != currentTime {
            layers[index].state.time = currentTime
            layers[index].state.needsUpdate = true
        }
        guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
            fatalError(
                "_ShapeStyle_InterpolatorGroup.rewriteInterpolation requires an active ViewGraph host."
            )
        }
        viewGraph.nextUpdate.views.at(currentTime)
        layers[index].state.updateInterpolators(
            contentsScale: contentsScale,
            maxDuration: maxDuration
        )
        return layers[index].state.updateOutput(
            list: &list,
            frame: frame,
            contentOffset: contentOffset,
            version: version,
            rasterizationOptions: rasterizationOptions
        )
    }
}

private extension DisplayList {
    func forEachIdentity(
        _ body: (_DisplayList_Identity, inout Bool) -> Void
    ) -> Bool {
        for item in items where !item.forEachIdentity(body) {
            return false
        }
        return true
    }

    var interpolationFeatures: Features {
        items.reduce(into: Features()) { result, item in
            result.formUnion(item.interpolationFeatures)
        }
    }
}

private extension DisplayList.Item {
    func forEachIdentity(
        _ body: (_DisplayList_Identity, inout Bool) -> Void
    ) -> Bool {
        if identity != .none {
            var stop = false
            body(identity, &stop)
            if stop {
                return false
            }
        }

        switch value {
        case let .content(content):
            switch content.value {
            case let .flattened(contents, _, _):
                return contents.forEachIdentity(body)
            case .backend, .color, .shape, .image, .style, .crossFade,
                 .text, .drawing:
                return true
            }
        case let .effect(effect, contents):
            if case let .mask(mask, _) = effect,
               !mask.forEachIdentity(body) {
                return false
            }
            return contents.forEachIdentity(body)
        case let .states(states):
            for (_, contents) in states where !contents.forEachIdentity(body) {
                return false
            }
            return true
        case .empty:
            return true
        }
    }

    var interpolationFeatures: DisplayList.Features {
        switch value {
        case .content:
            return []
        case let .effect(effect, contents):
            var result = contents.interpolationFeatures
            switch effect {
            case .animation:
                result.insert(.animations)
            case .state:
                result.insert(.stateEffects)
            case .interpolatorRoot:
                result.insert(.interpolatorRoots)
            case .interpolatorLayer:
                result.insert(.interpolatorLayers)
            default:
                break
            }
            return result
        case let .states(states):
            return states.reduce(into: [.states]) { result, state in
                result.formUnion(state.1.interpolationFeatures)
            }
        case .empty:
            return []
        }
    }
}

private func idsAreDisjoint(
    _ lhs: DisplayList,
    _ rhs: DisplayList
) -> Bool {
    var identities: [_DisplayList_Identity] = []
    _ = lhs.forEachIdentity { identity, _ in
        identities.append(identity)
    }
    guard !identities.isEmpty else {
        return true
    }
    identities = identities.enumerated().sorted {
        if $0.element.value != $1.element.value {
            return $0.element.value < $1.element.value
        }
        return $0.offset < $1.offset
    }.map(\.element)

    var disjoint = true
    _ = rhs.forEachIdentity { identity, stop in
        var lowerBound = identities.startIndex
        var upperBound = identities.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if identities[middle].value < identity.value {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        if lowerBound < identities.endIndex,
           identities[lowerBound] == identity {
            disjoint = false
            stop = true
        }
    }
    return disjoint
}

private struct InterpolatedDisplayList<Content: InterpolatableContent>: StatefulRule {
    typealias Value = DisplayList

    var group: DisplayList.InterpolatorGroup
    var _content: Attribute<Content>
    var _position: Attribute<CGPoint>
    var _animatedPosition: Attribute<CGPoint>
    var _containerPosition: Attribute<CGPoint>
    var _size: Attribute<CGSize>
    var _phase: Attribute<_GraphInputs.Phase>
    var _time: Attribute<Time>
    var _transaction: Attribute<Transaction>
    var _environment: Attribute<EnvironmentValues>
    var _pixelLength: Attribute<CGFloat>
    var _list: OptionalAttribute<DisplayList>
    var animatesSize: Bool
    var defersRender: Bool
    var supportsVFD: Bool
    var lastContent: Content?
    var lastSize: CGSize
    var resetSeed: UInt32
    var contentVersion: DisplayList.Version

    mutating func updateValue() {
        let currentResetSeed = _phase.value.resetSeed
        if resetSeed != currentResetSeed {
            resetSeed = currentResetSeed
            lastContent = nil
            contentVersion = DisplayList.Version()
            group.reset()
        }

        let targetContent = _content.value
        let targetSize = _size.value
        let environment = _environment.value
        let updateVersion = DisplayList.Version(forUpdate: ())

        var transitionState = environment.contentTransitionState
        var transition = environment.contentTransition
        if transition == ContentTransition.defaultTransition {
            transition = Content.defaultTransition
        }
        transitionState.transition = transition

        var animation: Animation?
        var listener: AnimationListener?
        let contentChanged = lastContent?.requiresTransition(
            to: targetContent
        ) ?? true
        let sizeChanged = lastContent != nil && lastSize != targetSize
        if contentChanged || sizeChanged {
            contentVersion = updateVersion
        }

        if let previous = lastContent,
           contentChanged ||
            (sizeChanged && previous.appliesTransitionsForSizeChanges) {
            let transaction = _transaction.value
            if !transaction.disablesContentTransitions {
                previous.modifyTransition(
                    state: &transitionState,
                    to: targetContent
                )
                animation = transaction.animation ??
                    previous.defaultAnimation(to: targetContent)
                if transitionState.transition.isIdentity {
                    animation = nil
                }
                if previous.addsDrawingGroup ||
                    environment.contentTransitionAddsDrawingGroup {
                    transitionState.options.insert(.addsDrawingGroup)
                }
                listener = transaction.combinedAnimationListener
            }
        }
        transitionState.animation = animation
        transitionState.transition.applyEnvironmentValues(
            style: transitionState.style,
            layoutDirection: environment.layoutDirection
        )
        lastContent = targetContent
        lastSize = targetSize

        let pixelLength = _pixelLength.value
        let contentsScale = Float(1 / pixelLength)
        group.update(
            contentSeed: DisplayList.Seed(contentVersion),
            transition: transitionState.transition,
            animation: animation,
            listener: listener,
            contentsScale: contentsScale,
            rasterizationOptions: transitionState.rasterizationOptions,
            supportsVFD: supportsVFD
        )

        let animatedPosition = _animatedPosition.value
        let containerPosition = _containerPosition.value
        let finalTranslation = CGSize(
            width: animatedPosition.x - containerPosition.x,
            height: animatedPosition.y - containerPosition.y
        )

        var contentOrigin = CGPoint.zero
        var contentOffset = CGSize.zero
        if !animatesSize {
            let position = _position.value
            let roundedPosition = CGPoint(
                x: Self.round(position.x, to: pixelLength),
                y: Self.round(position.y, to: pixelLength)
            )
            contentOrigin = CGPoint(
                x: roundedPosition.x - containerPosition.x,
                y: roundedPosition.y - containerPosition.y
            )
            contentOffset = CGSize(
                width: contentOrigin.x - finalTranslation.width,
                height: contentOrigin.y - finalTranslation.height
            )
        }

        var output = _list.value ?? DisplayList()
        let frame = CGRect(origin: contentOrigin, size: targetSize)
        if defersRender {
            output = DisplayList.effect(
                .interpolatorRoot(group, contentOrigin, contentOffset),
                contents: output
            )
        } else if output.interpolationFeatures.contains(.interpolatorLayers) {
            _ = output.rewriteInterpolation(
                group: group,
                time: _time,
                frame: frame,
                contentOrigin: contentOrigin,
                contentOffset: contentOffset,
                version: updateVersion
            )
        }
        output.translate(by: finalTranslation, version: updateVersion)
        _AGGraph.setStatefulOutput(output)
    }

    private static func round(
        _ value: CGFloat,
        to pixelLength: CGFloat
    ) -> CGFloat {
        floor((value + pixelLength * 0.5) / pixelLength) * pixelLength
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

        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let animatedPosition = cachedEnvironment.animatedPosition(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment
        let environment = cachedEnvironment.environment
        let size = graph.subscriptNode(
            parent: inputs.size,
            keyPath: \ViewSize.value
        )
        let pixelLength: Attribute<CGFloat> = graph.makeRule {
            environment.value.animationPixelLength
        }
        let interpolated = graph.makeStatefulRule(
            InterpolatedDisplayList(
                group: group,
                _content: content,
                _position: inputs.position,
                _animatedPosition: animatedPosition,
                _containerPosition: inputs.containerPosition,
                _size: size,
                _phase: inputs.base.phase,
                _time: inputs.base.time,
                _transaction: inputs.base.transaction,
                _environment: environment,
                _pixelLength: pixelLength,
                _list: OptionalAttribute(displayList),
                animatesSize: animatesSize,
                defersRender: defersRender,
                supportsVFD: inputs.supportsVFD,
                lastContent: nil,
                lastSize: .zero,
                resetSeed: 0,
                contentVersion: DisplayList.Version()
            )
        )
        interpolated.flags = .transactional
        preferences.setValue(interpolated.identifier, for: DisplayList.Key.self)
    }
}

private extension DisplayList {
    mutating func rewriteInterpolation(
        group: InterpolatorGroup,
        time: Attribute<Time>,
        frame: CGRect,
        contentOrigin: CGPoint,
        contentOffset: CGSize,
        version: Version
    ) -> Bool {
        var rewritten = false

        for index in items.indices {
            switch items[index].value {
            case let .effect(.interpolatorLayer(owner, serial), contents)
                where owner === group:
                var contents = contents
                rewritten = group.rewriteInterpolation(
                    serial: serial,
                    list: &contents,
                    time: time,
                    frame: items[index].frame,
                    contentOrigin: contentOrigin,
                    contentOffset: contentOffset,
                    version: version
                ) || rewritten
                items[index].value = .effect(.identity, contents)
            case let .effect(effect, contents):
                var contents = contents
                rewritten = contents.rewriteInterpolation(
                    group: group,
                    time: time,
                    frame: frame,
                    contentOrigin: contentOrigin,
                    contentOffset: contentOffset,
                    version: version
                ) || rewritten
                items[index].value = .effect(effect, contents)
            case let .states(states):
                var states = states
                for stateIndex in states.indices {
                    rewritten = states[stateIndex].1.rewriteInterpolation(
                        group: group,
                        time: time,
                        frame: frame,
                        contentOrigin: contentOrigin,
                        contentOffset: contentOffset,
                        version: version
                    ) || rewritten
                }
                items[index].value = .states(states)
            case .content, .empty:
                break
            }
            group.apply(to: &items[index])
        }
        return rewritten
    }

}

extension DisplayList {
    mutating func translate(by offset: CGSize, version: Version) {
        for index in items.indices {
            items[index].frame.origin.x += offset.width
            items[index].frame.origin.y += offset.height
            if items[index].version < version {
                items[index].version = version
            }
        }
        for index in debugItems.indices {
            debugItems[index].frame.origin.x += offset.width
            debugItems[index].frame.origin.y += offset.height
            if debugItems[index].version < version {
                debugItems[index].version = version
            }
        }
        interpolationBounds = interpolationBounds?.offsetBy(
            dx: offset.width,
            dy: offset.height
        )
    }
}
