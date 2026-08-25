//
//  File: ScrollTransition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct ScrollTransitionConfiguration {
    fileprivate var threshold: Threshold
    fileprivate var mode: Mode

    fileprivate enum Mode {
        case animated(animation: Animation)
        case interactive(timingCurve: UnitCurve, animation: Animation?)
        case identity
    }

    public static func animated(
        _ animation: Animation = .default
    ) -> ScrollTransitionConfiguration {
        ScrollTransitionConfiguration(
            threshold: .visible(0.5),
            mode: .animated(animation: animation)
        )
    }

    nonisolated(unsafe) public static let animated: ScrollTransitionConfiguration = .animated()

    public static func interactive(
        timingCurve: UnitCurve = .easeInOut
    ) -> ScrollTransitionConfiguration {
        ScrollTransitionConfiguration(
            threshold: .visible,
            mode: .interactive(timingCurve: timingCurve, animation: nil)
        )
    }

    nonisolated(unsafe) public static let interactive: ScrollTransitionConfiguration = .interactive()

    nonisolated(unsafe) public static let identity = ScrollTransitionConfiguration(
        threshold: .visible,
        mode: .identity
    )

    public func animation(
        _ animation: Animation
    ) -> ScrollTransitionConfiguration {
        var configuration = self
        switch mode {
        case .animated:
            configuration.mode = .animated(animation: animation)
        case let .interactive(timingCurve, _):
            configuration.mode = .interactive(
                timingCurve: timingCurve,
                animation: animation
            )
        case .identity:
            break
        }
        return configuration
    }

    public func threshold(
        _ threshold: Threshold
    ) -> ScrollTransitionConfiguration {
        var configuration = self
        configuration.threshold = threshold
        return configuration
    }
}

@available(*, unavailable)
extension ScrollTransitionConfiguration: Sendable {
}

extension ScrollTransitionConfiguration {
    public struct Threshold {
        fileprivate var storage: Storage

        fileprivate indirect enum Storage {
            case visibility(Double)
            case inset(Double, Storage)
            case mix(from: Storage, to: Storage, amount: Double)
            case center

            func resolve(
                targetLength: Double,
                containerLength: Double
            ) -> Double {
                switch self {
                case let .visibility(amount):
                    return (targetLength + containerLength) * 0.5
                        - targetLength * amount
                case let .inset(distance, base):
                    return max(
                        base.resolve(
                            targetLength: targetLength,
                            containerLength: containerLength
                        ) - distance,
                        0
                    )
                case let .mix(from, to, amount):
                    let start = from.resolve(
                        targetLength: targetLength,
                        containerLength: containerLength
                    )
                    let end = to.resolve(
                        targetLength: targetLength,
                        containerLength: containerLength
                    )
                    return start + (end - start) * amount
                case .center:
                    return 0
                }
            }
        }

        nonisolated(unsafe) public static let visible = Threshold(storage: .visibility(1))
        nonisolated(unsafe) public static let hidden = Threshold(storage: .visibility(0))

        public static var centered: Threshold {
            Threshold(storage: .center)
        }

        public static func visible(_ amount: Double) -> Threshold {
            Threshold(storage: .visibility(amount))
        }

        public func interpolated(
            towards other: Threshold,
            amount: Double
        ) -> Threshold {
            Threshold(storage: .mix(
                from: storage,
                to: other.storage,
                amount: amount
            ))
        }

        public func inset(by distance: Double) -> Threshold {
            Threshold(storage: .inset(distance, storage))
        }
    }
}

@available(*, unavailable)
extension ScrollTransitionConfiguration.Threshold: Sendable {
}

public enum ScrollTransitionPhase: Equatable, Hashable {
    case topLeading
    case identity
    case bottomTrailing

    public var isIdentity: Bool {
        self == .identity
    }

    public var value: Double {
        switch self {
        case .topLeading:
            return -1
        case .identity:
            return 0
        case .bottomTrailing:
            return 1
        }
    }
}

@available(*, unavailable)
extension ScrollTransitionPhase: Sendable {
}

private struct ScrollTransitionModifier<Effect: VisualEffect>:
    ViewModifier,
    @unchecked Sendable
{
    var transition: @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> Effect
    var topLeading: ScrollTransitionConfiguration
    var bottomTrailing: ScrollTransitionConfiguration
    var axis: Axis?

    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ScrollTransitionModifier._makeView called outside an active _AGGraph context.")
        }

        let environment = inputs.base.cachedEnvironment.value.environment

        // Each edge owns its progress and transaction so asymmetric
        // configurations can animate independently.
        let topLeadingSource = graph.makeStatefulRule(
            StageProgress(
                stage: .topLeading,
                _container: modifier._attribute,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _environment: environment,
                _safeAreaInsets: inputs.safeAreaInsets,
                seed: 0
            )
        )
        let topLeadingTransaction = graph.makeRule(
            ConfigurationTransaction(
                _configuration: modifier[\.topLeading]._attribute,
                _transaction: inputs.base.transaction
            )
        )
        var topLeadingInputs = inputs.base
        topLeadingInputs.transaction = topLeadingTransaction
        var topLeadingProgress = _GraphValue(_attribute: topLeadingSource)
        ScrollTransitionProgress._makeAnimatable(
            value: &topLeadingProgress,
            inputs: topLeadingInputs
        )

        let bottomTrailingSource = graph.makeStatefulRule(
            StageProgress(
                stage: .bottomTrailing,
                _container: modifier._attribute,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _environment: environment,
                _safeAreaInsets: inputs.safeAreaInsets,
                seed: 0
            )
        )
        let bottomTrailingTransaction = graph.makeRule(
            ConfigurationTransaction(
                _configuration: modifier[\.bottomTrailing]._attribute,
                _transaction: inputs.base.transaction
            )
        )
        var bottomTrailingInputs = inputs.base
        bottomTrailingInputs.transaction = bottomTrailingTransaction
        var bottomTrailingProgress = _GraphValue(
            _attribute: bottomTrailingSource
        )
        ScrollTransitionProgress._makeAnimatable(
            value: &bottomTrailingProgress,
            inputs: bottomTrailingInputs
        )

        let effect = graph.makeStatefulRule(
            EffectRule(
                _topLeadingProgress: topLeadingProgress._attribute,
                _bottomTrailingProgress: bottomTrailingProgress._attribute,
                _container: modifier._attribute,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _environment: environment,
                _safeAreaInsets: inputs.safeAreaInsets
            )
        )
        return EffectApplicationModifier._makeView(
            modifier: _GraphValue(_attribute: effect),
            inputs: inputs,
            body: body
        )
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        makeMultiViewList(
            modifier: modifier,
            inputs: inputs,
            body: body
        )
    }

    private enum Stage {
        case topLeading
        case bottomTrailing
    }

    private struct StageProgress: StatefulRule, AsyncAttribute {
        typealias Value = ScrollTransitionProgress

        var stage: Stage
        var _container: Attribute<ScrollTransitionModifier>
        var _position: Attribute<CGPoint>
        var _size: Attribute<ViewSize>
        var _transform: Attribute<ViewTransform>
        var _environment: Attribute<EnvironmentValues>
        var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>
        var seed: UInt32

        mutating func updateValue() {
            seed &+= 1
            let geometryProxy = GeometryProxy(
                owner: context.attribute.identifier,
                size: _size,
                environment: _environment,
                transform: _transform,
                position: _position,
                safeAreaInsets: _safeAreaInsets.attribute,
                seed: seed
            )
            let container = self.container
            let configuration: ScrollTransitionConfiguration
            switch stage {
            case .topLeading:
                configuration = container.topLeading
            case .bottomTrailing:
                configuration = container.bottomTrailing
            }
            _AGGraph.setStatefulOutput(ScrollTransitionProgress(
                value: progress(
                    for: configuration,
                    geometryProxy: geometryProxy
                )
            ))
        }

        private var container: ScrollTransitionModifier {
            _container.value
        }

        private func progress(
            for configuration: ScrollTransitionConfiguration,
            geometryProxy: GeometryProxy
        ) -> Double {
            let axis: Axis
            if let configuredAxis = container.axis {
                axis = configuredAxis
            } else {
                // A bidirectional container follows the vertical fallback.
                // Only a purely horizontal container changes the inherited axis.
                axis = _environment.value.nearestScrollableAxes == .horizontal
                    ? .horizontal
                    : .vertical
            }

            switch configuration.mode {
            case .animated:
                return animatedProgress(
                    threshold: configuration.threshold,
                    axis: axis,
                    geometryProxy: geometryProxy
                )
            case let .interactive(timingCurve, _):
                return interactiveProgress(
                    threshold: configuration.threshold,
                    axis: axis,
                    timingCurve: timingCurve,
                    geometryProxy: geometryProxy
                )
            case .identity:
                return 1
            }
        }

        private func animatedProgress(
            threshold: ScrollTransitionConfiguration.Threshold,
            axis: Axis,
            geometryProxy: GeometryProxy
        ) -> Double {
            guard let bounds = geometryProxy.bounds(of: .scrollView(axis: axis)) else {
                return 0
            }
            let targetLength: Double
            let containerLength: Double
            let coordinate: Double
            switch axis {
            case .horizontal:
                targetLength = geometryProxy.size.width
                containerLength = bounds.width
                coordinate = bounds.minX
            case .vertical:
                targetLength = geometryProxy.size.height
                containerLength = bounds.height
                coordinate = bounds.minY
            }
            let resolvedThreshold = threshold.storage.resolve(
                targetLength: targetLength,
                containerLength: containerLength
            )
            let centerDelta = (targetLength - containerLength) * 0.5

            switch stage {
            case .topLeading:
                return coordinate <= centerDelta + resolvedThreshold ? 1 : 0
            case .bottomTrailing:
                return coordinate >= centerDelta - resolvedThreshold ? 1 : 0
            }
        }

        private func interactiveProgress(
            threshold: ScrollTransitionConfiguration.Threshold,
            axis: Axis,
            timingCurve: UnitCurve,
            geometryProxy: GeometryProxy
        ) -> Double {
            guard let bounds = geometryProxy.bounds(of: .scrollView(axis: axis)) else {
                return 0
            }
            let targetLength: Double
            let containerLength: Double
            let coordinate: Double
            switch axis {
            case .horizontal:
                targetLength = geometryProxy.size.width
                containerLength = bounds.width
                coordinate = bounds.minX
            case .vertical:
                targetLength = geometryProxy.size.height
                containerLength = bounds.height
                coordinate = bounds.minY
            }
            let resolvedThreshold = threshold.storage.resolve(
                targetLength: targetLength,
                containerLength: containerLength
            )
            let centerDelta = (targetLength - containerLength) * 0.5

            let lowerBound: Double
            let upperBound: Double
            switch stage {
            case .topLeading:
                lowerBound = centerDelta + resolvedThreshold
                upperBound = targetLength
            case .bottomTrailing:
                lowerBound = -containerLength
                upperBound = centerDelta - resolvedThreshold
            }
            guard lowerBound < upperBound else {
                return 0
            }

            let linearProgress: Double
            if coordinate < lowerBound {
                linearProgress = 0
            } else if coordinate >= upperBound {
                linearProgress = 1
            } else {
                linearProgress = (coordinate - lowerBound)
                    / (upperBound - lowerBound)
            }

            // Progress is the identity fraction. The leading stage approaches
            // identity in the opposite direction from the trailing stage.
            let identityProgress: Double
            switch stage {
            case .topLeading:
                identityProgress = 1 - linearProgress
            case .bottomTrailing:
                identityProgress = linearProgress
            }
            return timingCurve.value(at: identityProgress)
        }
    }

    private struct ConfigurationTransaction: Rule, AsyncAttribute {
        var _configuration: Attribute<ScrollTransitionConfiguration>
        var _transaction: Attribute<Transaction>

        var value: Transaction {
            var transaction = _transaction.value

            // The edge configuration animates only its progress node. The
            // combined visual effect suppresses any additional outer animation.
            switch _configuration.value.mode {
            case let .animated(animation):
                transaction.animation = animation
            case let .interactive(_, animation):
                if let animation {
                    transaction.animation = animation
                }
            case .identity:
                break
            }
            return transaction
        }
    }

    private struct EffectRule: StatefulRule, AsyncAttribute {
        typealias Value = EffectApplicationModifier

        var _topLeadingProgress: Attribute<ScrollTransitionProgress>
        var _bottomTrailingProgress: Attribute<ScrollTransitionProgress>
        var _container: Attribute<ScrollTransitionModifier>
        var _position: Attribute<CGPoint>
        var _size: Attribute<ViewSize>
        var _transform: Attribute<ViewTransform>
        var _environment: Attribute<EnvironmentValues>
        var _safeAreaInsets: OptionalAttribute<SafeAreaInsets>

        mutating func updateValue() {
            let container = _container.value
            _AGGraph.setStatefulOutput(EffectApplicationModifier(
                topLeadingProgress: _topLeadingProgress.value,
                bottomTrailingProgress: _bottomTrailingProgress.value,
                transition: container.transition
            ))
        }
    }

    private struct EffectApplicationModifier: ViewModifier, @unchecked Sendable {
        var topLeadingProgress: ScrollTransitionProgress
        var bottomTrailingProgress: ScrollTransitionProgress
        var transition: @Sendable (
            EmptyVisualEffect,
            ScrollTransitionPhase
        ) -> Effect

        func body(content: Content) -> some View {
            content.animation(nil) { content in
                content.visualEffect { _, geometryProxy in
                    effect(for: geometryProxy)
                }
            }
        }

        private func effect(for _: GeometryProxy) -> Effect {
            let topLeadingEffect = transition(
                EmptyVisualEffect(),
                .topLeading
            )
            var identityEffect = transition(
                EmptyVisualEffect(),
                .identity
            )
            let bottomTrailingEffect = transition(
                EmptyVisualEffect(),
                .bottomTrailing
            )

            let identityData = identityEffect.animatableData

            // Each stage progress is an identity fraction. Interpolate both
            // edge effects toward identity, then remove the duplicated identity
            // contribution. Keeping the identity effect as the result also
            // preserves its non-animatable fields.
            var topLeadingData = identityData
            topLeadingData -= topLeadingEffect.animatableData
            topLeadingData.scale(by: topLeadingProgress.value)
            topLeadingData += topLeadingEffect.animatableData

            var bottomTrailingData = identityData
            bottomTrailingData -= bottomTrailingEffect.animatableData
            bottomTrailingData.scale(by: bottomTrailingProgress.value)
            bottomTrailingData += bottomTrailingEffect.animatableData

            topLeadingData += bottomTrailingData
            topLeadingData -= identityData
            identityEffect.animatableData = topLeadingData
            return identityEffect
        }
    }
}

private struct ScrollTransitionProgress: Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
}

extension View {
    nonisolated public func scrollTransition<Effect: VisualEffect>(
        _ configuration: ScrollTransitionConfiguration = .interactive,
        axis: Axis? = nil,
        transition: @escaping @Sendable (
            EmptyVisualEffect,
            ScrollTransitionPhase
        ) -> Effect
    ) -> some View {
        modifier(ScrollTransitionModifier(
            transition: transition,
            topLeading: configuration,
            bottomTrailing: configuration,
            axis: axis
        ))
    }

    nonisolated public func scrollTransition<Effect: VisualEffect>(
        topLeading: ScrollTransitionConfiguration,
        bottomTrailing: ScrollTransitionConfiguration,
        axis: Axis? = nil,
        transition: @escaping @Sendable (
            EmptyVisualEffect,
            ScrollTransitionPhase
        ) -> Effect
    ) -> some View {
        modifier(ScrollTransitionModifier(
            transition: transition,
            topLeading: topLeading,
            bottomTrailing: bottomTrailing,
            axis: axis
        ))
    }
}
