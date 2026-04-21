//
//  File: AlertModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// MARK: - ViewIdentity
// Stable per-modifier-instance identity used as a dictionary key.
struct ViewIdentity: Hashable {
    private static let counter = Atomic<UInt64>(0)
    let id: UInt64
    init() { id = ViewIdentity.counter.wrappingAdd(1, ordering: .relaxed).newValue }
}

// MARK: - AlertPreference
// Runtime data needed to render an alert overlay.
struct AlertPreference: @unchecked Sendable {
    let title: Text
    let makeActions: () -> AnyView
    let makeMessage: (() -> AnyView)?
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let severity: DialogSeverity
}

// MARK: - AlertStorage
// Stores the alert preference written into host preferences.
struct AlertStorage: @unchecked Sendable {
    let preference: AlertPreference

    // Merges alert storage by identity. The next value wins on collision.
    struct PreferenceKey: HostPreferenceKey {
        typealias Value = [ViewIdentity: AlertStorage]
        static var defaultValue: Value { [:] }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

// MARK: - MakeAlertStorage
// StatefulRule that produces the preference mutation closure.
struct MakeAlertStorage<Actions: View, Message: View>: StatefulRule {
    typealias Value = (inout [ViewIdentity: AlertStorage]) -> Void

    let modifier: Attribute<AlertModifier<Actions, Message>>
    // Stable identity assigned once and preserved across re-evaluations.
    let identity: ViewIdentity

    mutating func updateValue() {
        let m = modifier.value
        guard m.isPresented.wrappedValue else {
            let id = identity
            AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: AlertStorage]) in
                dict.removeValue(forKey: id)
            } as Value)
            return
        }
        let pref = AlertPreference(
            title: m.title,
            makeActions: { AnyView(m.actions) },
            makeMessage: (m.message is EmptyView) ? nil : { AnyView(m.message) },
            isPresented: m.isPresented,
            onDismiss: nil,
            severity: m.severity
        )
        let storage = AlertStorage(preference: pref)
        let id = identity
        AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: AlertStorage]) in
            dict[id] = storage
        } as Value)
    }
}

// MARK: - ActionsModifier
// Pass-through modifier for alert actions rendered directly in the overlay.
struct ActionsModifier: ViewModifier {
    typealias Body = Never
}

extension ActionsModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                          body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                     body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

// MARK: - AlertModifier
struct AlertModifier<Actions: View, Message: View>: ViewModifier {
    typealias Body = Never

    let title: Text
    let actions: Actions
    let message: Message
    let isPresented: Binding<Bool>
    let severity: DialogSeverity
}

extension AlertModifier {
    // Creates a stateful rule that produces the alert preference mutation.
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                          body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("AlertModifier._makeView called outside AG context")
        }
        let identity = ViewIdentity()
        let storageRule = MakeAlertStorage<Actions, Message>(
            modifier: modifier._attribute,
            identity: identity
        )
        let storageAttr: Attribute<MakeAlertStorage<Actions, Message>.Value> =
            graph.makeStatefulRule(storageRule)

        // Build AlertStorage.PreferenceKey preference from the mutation closure.
        let prefAttr: Attribute<AlertStorage.PreferenceKey.Value> = graph.makeRule {
            var dict = AlertStorage.PreferenceKey.defaultValue
            storageAttr.value(&dict)
            return dict
        }
        var outputs = body(_Graph(), inputs)
        outputs.preferences.append(AlertStorage.PreferenceKey.self,
                                   node: prefAttr.identifier)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                     body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

// MARK: - AlertOverlayView
// The view rendered inside the overlay WindowController for an alert.
struct AlertOverlayView: View {
    let preference: AlertPreference

    var body: some View {
        ZStack {
            // Dim background that absorbs taps outside the alert panel.
            Color.black.opacity(0.3)
                .onTapGesture {}

            // Alert panel
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    preference.title
                        .font(.headline)
                    if let makeMessage = preference.makeMessage {
                        makeMessage()
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)

                Divider()

                preference.makeActions()
                    .padding(8)
            }
            .frame(width: 280)
            .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - View.alert extensions

extension View {
    public func alert<A>(_ titleKey: LocalizedStringKey,
                         isPresented: Binding<Bool>,
                         @ViewBuilder actions: () -> A) -> some View where A: View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions)
    }

    public func alert<S: StringProtocol, A: View>(_ title: S,
                                                   isPresented: Binding<Bool>,
                                                   @ViewBuilder actions: () -> A) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions)
    }

    public func alert<A: View>(_ title: Text,
                                isPresented: Binding<Bool>,
                                @ViewBuilder actions: () -> A) -> some View {
        modifier(AlertModifier(title: title,
                               actions: actions().modifier(ActionsModifier()),
                               message: EmptyView(),
                               isPresented: isPresented,
                               severity: .automatic))
    }
}

extension View {
    public func alert<A: View, M: View>(_ titleKey: LocalizedStringKey,
                                         isPresented: Binding<Bool>,
                                         @ViewBuilder actions: () -> A,
                                         @ViewBuilder message: () -> M) -> some View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<S: StringProtocol, A: View, M: View>(_ title: S,
                                                             isPresented: Binding<Bool>,
                                                             @ViewBuilder actions: () -> A,
                                                             @ViewBuilder message: () -> M) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<A: View, M: View>(_ title: Text,
                                         isPresented: Binding<Bool>,
                                         @ViewBuilder actions: () -> A,
                                         @ViewBuilder message: () -> M) -> some View {
        modifier(AlertModifier(title: title,
                               actions: actions().modifier(ActionsModifier()),
                               message: message(),
                               isPresented: isPresented,
                               severity: .automatic))
    }
}

extension View {
    public func alert<A: View, T>(_ titleKey: LocalizedStringKey,
                                   isPresented: Binding<Bool>,
                                   presenting data: T?,
                                   @ViewBuilder actions: (T) -> A) -> some View {
        alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions)
    }

    public func alert<A: View, T>(_ title: Text,
                                   isPresented: Binding<Bool>,
                                   presenting data: T?,
                                   @ViewBuilder actions: (T) -> A) -> some View {
        // Gate isPresented on data != nil: alert only shows when both are true.
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let data {
            return AnyView(modifier(AlertModifier(title: title,
                                                  actions: actions(data).modifier(ActionsModifier()),
                                                  message: EmptyView(),
                                                  isPresented: gated,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              isPresented: gated,
                                              severity: .automatic)))
    }
}

extension View {
    public func alert<A: View, M: View, T>(_ titleKey: LocalizedStringKey,
                                            isPresented: Binding<Bool>,
                                            presenting data: T?,
                                            @ViewBuilder actions: (T) -> A,
                                            @ViewBuilder message: (T) -> M) -> some View {
        alert(Text(titleKey), isPresented: isPresented,
              presenting: data, actions: actions, message: message)
    }

    public func alert<A: View, M: View, T>(_ title: Text,
                                            isPresented: Binding<Bool>,
                                            presenting data: T?,
                                            @ViewBuilder actions: (T) -> A,
                                            @ViewBuilder message: (T) -> M) -> some View {
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let data {
            return AnyView(modifier(AlertModifier(title: title,
                                                  actions: actions(data).modifier(ActionsModifier()),
                                                  message: message(data),
                                                  isPresented: gated,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              isPresented: gated,
                                              severity: .automatic)))
    }
}

extension View {
    public func alert<E: LocalizedError, A: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: () -> A) -> some View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        return modifier(AlertModifier(title: title,
                                      actions: actions().modifier(ActionsModifier()),
                                      message: EmptyView(),
                                      isPresented: isPresented,
                                      severity: .automatic))
    }

    public func alert<E: LocalizedError, A: View, M: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: (E) -> A,
        @ViewBuilder message: (E) -> M) -> some View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        let gated = Binding<Bool>(get: { error != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let error {
            return AnyView(modifier(AlertModifier(title: title,
                                                  actions: actions(error).modifier(ActionsModifier()),
                                                  message: message(error),
                                                  isPresented: gated,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              isPresented: gated,
                                              severity: .automatic)))
    }
}
