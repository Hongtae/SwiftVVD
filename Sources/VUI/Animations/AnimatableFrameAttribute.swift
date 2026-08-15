//
//  File: AnimatableFrameAttribute.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct AnimatedFrameAttributes {
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var frame: Attribute<ViewFrame>
}

private struct FrameVelocityFilter {
    var currentVelocity: Double?
    var previous: (time: Time, data: ViewFrame.AnimatableData)?

    mutating func addSample(
        _ data: ViewFrame.AnimatableData,
        time: Time
    ) {
        defer {
            previous = (time, data)
        }

        guard let previous, previous.time < time else {
            return
        }

        let elapsed = time.seconds - previous.time.seconds
        guard elapsed > 0 else { return }

        let observed = maxAbsVelocity(
            from: previous.data,
            to: data,
            elapsed: elapsed
        )
        if let currentVelocity {
            self.currentVelocity = currentVelocity + ((observed - currentVelocity) * 0.35)
        } else {
            self.currentVelocity = observed
        }
    }

    mutating func reset() {
        currentVelocity = nil
        previous = nil
    }

    private func maxAbsVelocity(
        from previous: ViewFrame.AnimatableData,
        to current: ViewFrame.AnimatableData,
        elapsed: Double
    ) -> Double {
        let reciprocal = 1.0 / elapsed
        let components = [
            Double(current.first.first - previous.first.first),
            Double(current.first.second - previous.first.second),
            Double(current.second.first - previous.second.first),
            Double(current.second.second - previous.second.second),
        ]
        return components.reduce(0) { partial, component in
            max(partial, abs(component * reciprocal))
        }
    }
}

private struct AnimatableFrameAttribute: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = ViewFrame

    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _pixelLength: Attribute<CGFloat>
    var _environment: Attribute<EnvironmentValues>
    var helper: AnimatableAttributeHelper<ViewFrame>
    var animationsDisabled: Bool

    init(
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        pixelLength: Attribute<CGFloat>,
        environment: Attribute<EnvironmentValues>,
        phase: Attribute<_GraphInputs.Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        animationsDisabled: Bool
    ) {
        self._position = position
        self._size = size
        self._pixelLength = pixelLength
        self._environment = environment
        self.helper = AnimatableAttributeHelper(
            _phase: phase,
            _time: time,
            _transaction: transaction
        )
        self.animationsDisabled = animationsDisabled
    }

    mutating func updateValue() {
        let position = _position.changedValue(options: [])
        let size = _size.changedValue(options: [])
        let pixelLength = _pixelLength.changedValue(options: [])
        var value = (
            value: roundedFrame(
                position: position.value,
                size: size.value,
                pixelLength: pixelLength.value
            ),
            changed: position.changed || size.changed || pixelLength.changed
        )
        if !animationsDisabled {
            helper.update(
                value: &value,
                defaultAnimation: nil,
                environment: _environment
            )
        }
        if value.changed || _AGGraph.currentStatefulOutput(ViewFrame.self) == nil {
            _AGGraph.setStatefulOutput(value.value)
        }
    }

    mutating func destroy() {
        helper.removeListeners()
    }

    private func roundedFrame(
        position: CGPoint,
        size: ViewSize,
        pixelLength: CGFloat
    ) -> ViewFrame {
        var frame = ViewFrame(origin: position, size: size)
        if pixelLength > 0, pixelLength.isFinite {
            frame.round(toMultipleOf: pixelLength)
        }
        return frame
    }

}

private struct AnimatableFrameAttributeVFD: StatefulRule, ObservedAttribute, AsyncAttribute {
    typealias Value = ViewFrame

    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _pixelLength: Attribute<CGFloat>
    var _environment: Attribute<EnvironmentValues>
    var helper: AnimatableAttributeHelper<ViewFrame>
    var velocityFilter = FrameVelocityFilter()
    var animationsDisabled: Bool

    init(
        position: Attribute<CGPoint>,
        size: Attribute<ViewSize>,
        pixelLength: Attribute<CGFloat>,
        environment: Attribute<EnvironmentValues>,
        phase: Attribute<_GraphInputs.Phase>,
        time: Attribute<Time>,
        transaction: Attribute<Transaction>,
        animationsDisabled: Bool
    ) {
        self._position = position
        self._size = size
        self._pixelLength = pixelLength
        self._environment = environment
        self.helper = AnimatableAttributeHelper(
            _phase: phase,
            _time: time,
            _transaction: transaction
        )
        self.animationsDisabled = animationsDisabled
    }

    mutating func updateValue() {
        let position = _position.changedValue(options: [])
        let size = _size.changedValue(options: [])
        let pixelLength = _pixelLength.changedValue(options: [])
        var value = (
            value: roundedFrame(
                position: position.value,
                size: size.value,
                pixelLength: pixelLength.value
            ),
            changed: position.changed || size.changed || pixelLength.changed
        )
        if !animationsDisabled {
            helper.update(
                value: &value,
                defaultAnimation: nil,
                environment: _environment,
                sampleCollector: { data, time in
                    velocityFilter.addSample(data, time: time)
                }
            )
        }

        if helper.isAnimating {
            scheduleMaxVelocity()
        } else {
            velocityFilter.reset()
        }
        if value.changed || _AGGraph.currentStatefulOutput(ViewFrame.self) == nil {
            _AGGraph.setStatefulOutput(value.value)
        }
    }

    mutating func destroy() {
        helper.removeListeners()
    }

    private func roundedFrame(
        position: CGPoint,
        size: ViewSize,
        pixelLength: CGFloat
    ) -> ViewFrame {
        var frame = ViewFrame(origin: position, size: size)
        if pixelLength > 0, pixelLength.isFinite {
            frame.round(toMultipleOf: pixelLength)
        }
        return frame
    }

    private mutating func scheduleMaxVelocity() {
        guard let viewGraph = GraphHost.currentHost as? ViewGraph else {
            fatalError("AnimatableFrameAttributeVFD.updateValue requires an active ViewGraph host.")
        }
        viewGraph.nextUpdate.views.maxVelocity(velocityFilter.currentVelocity ?? 0)
    }

}

func makeAnimatableFrameAttributes(
    in inputs: inout _GraphInputs,
    position: Attribute<CGPoint>,
    size: Attribute<ViewSize>,
    supportsVFD: Bool? = nil,
    animationsDisabled: Bool? = nil
) -> AnimatedFrameAttributes {
    guard let graph = _AGGraph.current else {
        fatalError("makeAnimatableFrameAttributes called outside an active _AGGraph context.")
    }

    var cachedEnvironment = inputs.cachedEnvironment.value
    let environment = cachedEnvironment.environment
    let pixelLength: Attribute<CGFloat> = cachedEnvironment.attribute(
        id: .pixelLength
    ) {
        $0.animationPixelLength
    }
    let disabled = animationsDisabled ?? inputs.options.contains(.animationsDisabled)
    let usesVFD = supportsVFD ?? inputs.options.contains(.supportsVariableFrameDuration)
    let frame: Attribute<ViewFrame>
    if usesVFD {
        frame = graph.makeStatefulRule(
            AnimatableFrameAttributeVFD(
                position: position,
                size: size,
                pixelLength: pixelLength,
                environment: environment,
                phase: inputs.phase,
                time: inputs.time,
                transaction: inputs.transaction,
                animationsDisabled: disabled
            )
        )
    } else {
        frame = graph.makeStatefulRule(
            AnimatableFrameAttribute(
                position: position,
                size: size,
                pixelLength: pixelLength,
                environment: environment,
                phase: inputs.phase,
                time: inputs.time,
                transaction: inputs.transaction,
                animationsDisabled: disabled
            )
        )
    }
    frame.flags = .transactional
    let animatedPosition: Attribute<CGPoint> = graph.subscriptNode(
        parent: frame,
        keyPath: \ViewFrame.origin
    )
    let animatedSize: Attribute<ViewSize> = graph.subscriptNode(
        parent: frame,
        keyPath: \ViewFrame.size
    )

    cachedEnvironment.animatedFrame = CachedEnvironment.AnimatedFrame(
        position: position,
        size: size,
        pixelLength: pixelLength,
        time: inputs.time,
        transaction: inputs.transaction,
        viewPhase: inputs.phase,
        animatedFrame: frame,
        _animatedPosition: animatedPosition,
        _animatedSize: animatedSize,
        _animatedCGSize: nil
    )
    inputs.cachedEnvironment = MutableBox(cachedEnvironment)

    return AnimatedFrameAttributes(
        position: animatedPosition,
        size: animatedSize,
        frame: frame
    )
}

extension CachedEnvironment {
    mutating func animatedPosition(
        for inputs: _ViewInputs
    ) -> Attribute<CGPoint> {
        guard inputs.needsGeometry else { return inputs.position }
        return animatedFrame(for: inputs)._animatedPosition!
    }

    mutating func animatedSize(
        for inputs: _ViewInputs
    ) -> Attribute<ViewSize> {
        guard inputs.needsGeometry else { return inputs.size }
        return animatedFrame(for: inputs)._animatedSize!
    }

    mutating func animatedCGSize(
        for inputs: _ViewInputs
    ) -> Attribute<CGSize> {
        guard let graph = _AGGraph.current else {
            fatalError("CachedEnvironment.animatedCGSize(for:) called outside an active _AGGraph context.")
        }
        if !inputs.needsGeometry {
            return graph.subscriptNode(parent: inputs.size, keyPath: \ViewSize.value)
        }

        let frame = animatedFrame(for: inputs)
        if let size = frame._animatedCGSize {
            return size
        }
        let size = graph.subscriptNode(
            parent: frame._animatedSize!,
            keyPath: \ViewSize.value
        )
        animatedFrame?._animatedCGSize = size
        return size
    }

    private mutating func animatedFrame(
        for inputs: _ViewInputs
    ) -> AnimatedFrame {
        guard let graph = _AGGraph.current else {
            fatalError("CachedEnvironment.animatedFrame(for:) called outside an active _AGGraph context.")
        }

        let pixelLength: Attribute<CGFloat> = attribute(
            id: .pixelLength
        ) {
            $0.animationPixelLength
        }
        let transaction = inputs.geometryTransaction()
        if let cached = animatedFrame,
           cached.position.identifier == inputs.position.identifier,
           cached.size.identifier == inputs.size.identifier,
           cached.pixelLength.identifier == pixelLength.identifier,
           cached.time.identifier == inputs.base.time.identifier,
           cached.transaction.identifier == transaction.identifier,
           cached.viewPhase.identifier == inputs.base.phase.identifier,
           cached._animatedPosition != nil,
           cached._animatedSize != nil {
            return cached
        }

        let environment = environment
        let disabled = inputs.base.options.contains(.animationsDisabled)
        let frame: Attribute<ViewFrame>
        if inputs.supportsVFD {
            frame = graph.makeStatefulRule(
                AnimatableFrameAttributeVFD(
                    position: inputs.position,
                    size: inputs.size,
                    pixelLength: pixelLength,
                    environment: environment,
                    phase: inputs.base.phase,
                    time: inputs.base.time,
                    transaction: transaction,
                    animationsDisabled: disabled
                )
            )
        } else {
            frame = graph.makeStatefulRule(
                AnimatableFrameAttribute(
                    position: inputs.position,
                    size: inputs.size,
                    pixelLength: pixelLength,
                    environment: environment,
                    phase: inputs.base.phase,
                    time: inputs.base.time,
                    transaction: transaction,
                    animationsDisabled: disabled
                )
            )
        }
        frame.flags = .transactional
        let position = graph.subscriptNode(
            parent: frame,
            keyPath: \ViewFrame.origin
        )
        let size = graph.subscriptNode(
            parent: frame,
            keyPath: \ViewFrame.size
        )
        let result = AnimatedFrame(
            position: inputs.position,
            size: inputs.size,
            pixelLength: pixelLength,
            time: inputs.base.time,
            transaction: transaction,
            viewPhase: inputs.base.phase,
            animatedFrame: frame,
            _animatedPosition: position,
            _animatedSize: size,
            _animatedCGSize: nil
        )
        animatedFrame = result
        return result
    }
}

extension _ViewInputs {
    func animatedPosition() -> Attribute<CGPoint> {
        let cachedEnvironmentAttribute = base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let position = cachedEnvironment.animatedPosition(for: self)
        cachedEnvironmentAttribute.value = cachedEnvironment
        return position
    }

    func animatedSize() -> Attribute<ViewSize> {
        let cachedEnvironmentAttribute = base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let size = cachedEnvironment.animatedSize(for: self)
        cachedEnvironmentAttribute.value = cachedEnvironment
        return size
    }
}
