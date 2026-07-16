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

private struct AnimatableFrameAttribute: StatefulRule {
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
        phase: Attribute<Phase>,
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
        guard let graph = _AGGraph.current else {
            fatalError("AnimatableFrameAttribute.updateValue called outside an active _AGGraph context.")
        }

        let target = roundedFrame(
            position: _position.value,
            size: _size.value,
            pixelLength: _pixelLength.value
        )
        if animationsDisabled {
            finishValue(target)
            return
        }

        var value = (value: target, changed: false)
        let update = helper.beginStandaloneUpdate(
            value: &value,
            defaultAnimation: nil,
            transactionForChangedTarget: {
                graph.transaction(for: _position.identifier) ??
                    graph.transaction(for: _size.identifier)
            }
        )

        let previousOutput: ViewFrame? = _AGGraph.currentStatefulOutput()

        if update.didReset || previousOutput == nil {
            finishValue(update.target)
            return
        }

        if let targetAnimationBranch = update.targetAnimationBranch {
            switch targetAnimationBranch {
            case .animated(let animation, let transaction, let time):
                // Frame rules do not maintain an outer completion-record list.
                // Let the helper install state listeners through the direct
                // state-owned path and only keep the sampled frame output here.
                helper.retargetStandaloneAnimation(
                    animation: animation,
                    start: previousOutput ?? update.target,
                    target: update.target,
                    transaction: transaction,
                    time: time,
                    environment: _environment
                )
                value.value = update.target
            case .noAnimation:
                finishValue(update.target)
                return
            }
        }

        guard helper.isAnimating else { return }
        helper.update(
            value: &value,
            environment: _environment,
            advancesDelayedSecondSample: true
        )
        _AGGraph.setStatefulOutput(value.value)
    }

    mutating func destroy() {
        helper.finishAndClearAnimatorState()
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

    private mutating func finishValue(_ value: ViewFrame) {
        helper.finishAndClearAnimatorState()
        helper.commitTarget(value)
        _AGGraph.setStatefulOutput(value)
    }
}

private struct AnimatableFrameAttributeVFD: StatefulRule {
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
        phase: Attribute<Phase>,
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
        guard let graph = _AGGraph.current else {
            fatalError("AnimatableFrameAttributeVFD.updateValue called outside an active _AGGraph context.")
        }

        let target = roundedFrame(
            position: _position.value,
            size: _size.value,
            pixelLength: _pixelLength.value
        )
        if animationsDisabled {
            finishValue(target)
            return
        }

        var value = (value: target, changed: false)
        let update = helper.beginStandaloneUpdate(
            value: &value,
            defaultAnimation: nil,
            transactionForChangedTarget: {
                graph.transaction(for: _position.identifier) ??
                    graph.transaction(for: _size.identifier)
            }
        )

        let previousOutput: ViewFrame? = _AGGraph.currentStatefulOutput()

        if update.didReset || previousOutput == nil {
            finishValue(update.target)
            return
        }

        if let targetAnimationBranch = update.targetAnimationBranch {
            switch targetAnimationBranch {
            case .animated(let animation, let transaction, let time):
                // The VFD lane follows the same standalone listener ownership as
                // the plain frame lane; velocity sampling remains a local add-on
                // after the helper has updated the frame value.
                helper.retargetStandaloneAnimation(
                    animation: animation,
                    start: previousOutput ?? update.target,
                    target: update.target,
                    transaction: transaction,
                    time: time,
                    environment: _environment
                )
                value.value = update.target
            case .noAnimation:
                finishValue(update.target)
                return
            }
        }

        guard helper.isAnimating else { return }
        helper.update(
            value: &value,
            environment: _environment,
            sampleCollector: { data, time in
                velocityFilter.addSample(data, time: time)
            },
            advancesDelayedSecondSample: true
        )
        _AGGraph.setStatefulOutput(value.value)

        if helper.isAnimating {
            scheduleMaxVelocity()
        } else {
            velocityFilter.reset()
        }
    }

    mutating func destroy() {
        helper.finishAndClearAnimatorState()
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

    private mutating func finishValue(_ value: ViewFrame) {
        helper.finishAndClearAnimatorState()
        helper.commitTarget(value)
        velocityFilter.reset()
        _AGGraph.setStatefulOutput(value)
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

    let environment = inputs.cachedEnvironment.value.environment
    let pixelLength: Attribute<CGFloat> = graph.makeRule {
        environment.value.animationPixelLength
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
    let animatedPosition: Attribute<CGPoint> = graph.subscriptNode(
        parent: frame,
        keyPath: \ViewFrame.origin
    )
    let animatedSize: Attribute<ViewSize> = graph.subscriptNode(
        parent: frame,
        keyPath: \ViewFrame.size
    )

    var cachedEnvironment = inputs.cachedEnvironment.value
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

// Thin owner for live animation state. Callers keep policy-heavy completion
// sorting outside this helper, while this type tracks source model changes,
// phase resets, and the currently active AnimatorState.
