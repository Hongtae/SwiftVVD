//
//  File: RefreshableModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct RefreshAction: Sendable {
    var action: @Sendable () async -> Void
    var id: UniqueID

    init(
        action: @escaping @Sendable () async -> Void,
        id: UniqueID
    ) {
        self.action = action
        self.id = id
    }

    public func callAsFunction() async {
        await action()
    }

    fileprivate struct Key: EnvironmentKey {
        static var defaultValue: RefreshAction? { nil }
    }
}

extension EnvironmentValues {
    public internal(set) var refresh: RefreshAction? {
        get { self[RefreshAction.Key.self] }
        set { self[RefreshAction.Key.self] = newValue }
    }
}

private struct RefreshableModifier: ViewModifier, _GraphInputsModifier {
    typealias Body = Never

    var action: @Sendable () async -> Void

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("\(Self.self)._makeInputs called outside an active _AGGraph context.")
        }
        let environment: Attribute<EnvironmentValues> = graph.makeRule(
            ChildEnvironment(
                _environment: inputs.cachedEnvironment.value.environment,
                _action: modifier[\.action]._attribute,
                actionID: UniqueID()
            )
        )
        inputs.cachedEnvironment = MutableBox(
            inputs.cachedEnvironment.value.replacingEnvironment(environment)
        )
    }

    private struct ChildEnvironment: Rule {
        typealias Value = EnvironmentValues

        var _environment: Attribute<EnvironmentValues>
        var _action: Attribute<@Sendable () async -> Void>
        var actionID: UniqueID

        var value: EnvironmentValues {
            var environment = _environment.value.trackingCopy()
            environment.refresh = RefreshAction(
                action: _action.value,
                id: actionID
            )
            return environment
        }
    }
}

extension View {
    nonisolated public func refreshable(
        @_inheritActorContext action: @escaping @Sendable () async -> Void
    ) -> some View {
        modifier(RefreshableModifier(action: action))
    }
}
