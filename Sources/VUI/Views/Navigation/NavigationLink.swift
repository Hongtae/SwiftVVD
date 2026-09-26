//
//  File: NavigationLink.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol AnyNavigationLinkPresentedValueStorageProtocol {
    var item: NavigationPathItem { get }
}

final class AnyNavigationLinkPresentedValueStorage<Value>:
    AnyNavigationLinkPresentedValueStorageProtocol
where Value: Hashable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    var item: NavigationPathItem {
        NavigationPath.item(value)
    }
}

final class AnyNavigationLinkCodablePresentedValueStorage<Value>:
    AnyNavigationLinkPresentedValueStorageProtocol
where Value: Codable & Hashable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }

    var item: NavigationPathItem {
        NavigationPath.item(value)
    }
}

struct AnyNavigationLinkPresentedValue {
    var storage: any AnyNavigationLinkPresentedValueStorageProtocol

    init<Value>(_ value: Value) where Value: Hashable {
        storage = AnyNavigationLinkPresentedValueStorage(value)
    }

    init<Value>(codable value: Value) where Value: Codable & Hashable {
        storage = AnyNavigationLinkCodablePresentedValueStorage(value)
    }
}

enum NavigationLinkPresentedValue {
    case v4(AnyNavigationLinkPresentedValue)
    case disabledByClient
}

struct NavigationAuthority {
}

struct NavigationListKey {
}

struct NavigationStackKey {
}

struct NavigationDestinationPayload<Destination> where Destination: View {
    var destination: Destination?
    var presentedValue: NavigationLinkPresentedValue?
    var linkID: Namespace.ID
    var isDetail: Bool
    var deprecated_isActiveStateOrBinding: StateOrBinding<Bool>
    var authority: NavigationAuthority?
    var listKey: NavigationListKey?
    var stackKey: NavigationStackKey?
}

public struct NavigationLink<Label, Destination>: View
where Label: View, Destination: View {
    @StateOrBinding private var deprecated_isActive: Bool
    var label: Label
    var destination: Destination?
    var isDetailLink: Bool
    var presentedValue: NavigationLinkPresentedValue?
    @State private var _triggerUpdateSeed: UInt32 = 0
    @Namespace private var namespace
    @State private var _isPresentingViewDestinationView = false

    public init(
        @ViewBuilder destination: () -> Destination,
        @ViewBuilder label: () -> Label
    ) {
        _deprecated_isActive = StateOrBinding(wrappedValue: false)
        self.label = label()
        self.destination = destination()
        isDetailLink = true
        presentedValue = nil
    }

    public var body: some View {
        PrimitiveNavigationLink(
            label: label,
            payload: NavigationDestinationPayload(
                destination: destination,
                presentedValue: presentedValue,
                linkID: namespace,
                isDetail: isDetailLink,
                deprecated_isActiveStateOrBinding: _deprecated_isActive,
                authority: nil,
                listKey: nil,
                stackKey: nil
            ),
            isPresentingViewDestinationView: $_isPresentingViewDestinationView,
            legacy_updateSeed: $_triggerUpdateSeed
        )
    }
}

@available(*, unavailable)
extension NavigationLink: Sendable {
}

extension NavigationLink where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder destination: () -> Destination
    ) {
        self.init(destination: destination) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        @ViewBuilder destination: () -> Destination
    ) {
        self.init(destination: destination) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        @ViewBuilder destination: () -> Destination
    ) where S: StringProtocol {
        self.init(destination: destination) {
            Text(title)
        }
    }
}

extension NavigationLink where Destination == Never {
    @_disfavoredOverload
    public init<Value>(
        value: Value?,
        @ViewBuilder label: () -> Label
    ) where Value: Hashable {
        _deprecated_isActive = StateOrBinding(wrappedValue: false)
        self.label = label()
        destination = nil
        isDetailLink = true
        presentedValue = value.map {
            .v4(AnyNavigationLinkPresentedValue($0))
        }
    }

    public init<Value>(
        value: Value?,
        @ViewBuilder label: () -> Label
    ) where Value: Codable & Hashable {
        _deprecated_isActive = StateOrBinding(wrappedValue: false)
        self.label = label()
        destination = nil
        isDetailLink = true
        presentedValue = value.map {
            .v4(AnyNavigationLinkPresentedValue(codable: $0))
        }
    }
}

extension NavigationLink where Label == Text, Destination == Never {
    @_disfavoredOverload
    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Value?
    ) where Value: Hashable {
        self.init(value: value) { Text(titleKey) }
    }

    public init<Value>(
        _ titleKey: LocalizedStringKey,
        value: Value?
    ) where Value: Codable & Hashable {
        self.init(value: value) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<Value>(
        _ titleResource: LocalizedStringResource,
        value: Value?
    ) where Value: Hashable {
        self.init(value: value) { Text(titleResource) }
    }

    public init<Value>(
        _ titleResource: LocalizedStringResource,
        value: Value?
    ) where Value: Codable & Hashable {
        self.init(value: value) { Text(titleResource) }
    }

    @_disfavoredOverload
    public init<S, Value>(
        _ title: S,
        value: Value?
    ) where S: StringProtocol, Value: Hashable {
        self.init(value: value) { Text(title) }
    }

    public init<S, Value>(
        _ title: S,
        value: Value?
    ) where S: StringProtocol, Value: Codable & Hashable {
        self.init(value: value) { Text(title) }
    }
}

struct PrimitiveNavigationLink<Label, Destination>: View
where Label: View, Destination: View {
    var label: Label
    var payload: NavigationDestinationPayload<Destination>
    var isPresentingViewDestinationView: Binding<Bool>
    var legacy_updateSeed: Binding<UInt32>

    var body: some View {
        StaticIf<
            InvertedViewInputPredicate<DisableNavigationDestination>,
            NavigationLinkButton<Label, Destination>,
            Label
        >(
            trueBody: NavigationLinkButton(
                label: label,
                payload: payload,
                isPresentingViewDestinationView:
                    isPresentingViewDestinationView
            ),
            falseBody: label
        )
    }
}

private struct NavigationLinkButton<Label, Destination>: View
where Label: View, Destination: View {
    var label: Label
    var payload: NavigationDestinationPayload<Destination>
    var isPresentingViewDestinationView: Binding<Bool>
    @Environment(\.navigationStackContext) private var context

    private var canActivate: Bool {
        guard context != nil else { return false }
        if payload.destination != nil { return true }
        if case .v4? = payload.presentedValue { return true }
        return false
    }

    var body: some View {
        Button(action: activate) {
            label
        }
        .disabled(!canActivate)
        .modifier(NavigationLinkDestinationModifier(
            isPresented: isPresentingViewDestinationView,
            destination: payload.destination,
            namespace: payload.linkID
        ))
    }

    private func activate() {
        guard let context else { return }
        switch payload.presentedValue {
        case let .v4(value):
            context.append(value.storage.item)
        case .disabledByClient:
            return
        case nil:
            guard payload.destination != nil else { return }
            isPresentingViewDestinationView.wrappedValue = true
        }
    }
}

private struct NavigationLinkDestinationModifier<Destination>:
    ViewModifier,
    MultiViewModifier
where Destination: View {
    typealias Body = Never

    var isPresented: Binding<Bool>
    var destination: Destination?
    var namespace: Namespace.ID

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "NavigationLinkDestinationModifier._makeView called outside "
                    + "an active _AGGraph context."
            )
        }
        var graphInputs = inputs.base
        let fields = DynamicPropertyCache.fields(of: Self.self)
        let propertyBuffer = _DynamicPropertyBuffer(
            fields: fields,
            container: modifier,
            inputs: &graphInputs
        )
        let resolvedModifier: Attribute<Self> = graph.makeRule {
            var value = modifier._attribute.value
            propertyBuffer.applyContexts(to: &value)
            return value
        }
        var inputs = inputs
        inputs.base = graphInputs
        var outputs = body(_Graph(), inputs)
        guard !inputs[DisableNavigationDestination.self] else {
            return outputs
        }
        guard resolvedModifier.value.destination != nil else {
            return outputs
        }

        let preference: Attribute<ResolvedNavigationDestinations> =
            graph.makeRule {
                let value = resolvedModifier.value
                guard value.isPresented.wrappedValue,
                      let destination = value.destination else {
                    return ResolvedNavigationDestinations()
                }
                let binding = value.isPresented
                return ResolvedNavigationDestinations(presentations: [
                    NavigationDestinationPresentation(
                        id: AnyHashable(value.namespace),
                        content: AnyView(destination),
                        onDismiss: { binding.wrappedValue = false }
                    )
                ])
            }
        outputs.preferences.append(
            NavigationDestinationsKey.self,
            node: preference.identifier
        )
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}
