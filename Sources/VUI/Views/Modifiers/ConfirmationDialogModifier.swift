//
//  File: ConfirmationDialogModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// Confirmation dialogs are rendered as overlay content.

// MARK: - Visibility

public enum Visibility: Hashable, Sendable {
    case automatic
    case visible
    case hidden
}

// MARK: - ConfirmationDialogPreference

struct ConfirmationDialogPreference: @unchecked Sendable {
    let title: Text
    let titleVisibility: Visibility
    let makeActions: () -> AnyView
    let makeMessage: (() -> AnyView)?
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
}

// MARK: - ConfirmationDialogStorage

struct ConfirmationDialogStorage: @unchecked Sendable {
    let preference: ConfirmationDialogPreference

    struct PreferenceKey: HostPreferenceKey {
        typealias Value = [ViewIdentity: ConfirmationDialogStorage]
        static var defaultValue: Value { [:] }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

// MARK: - MakeConfirmationDialogStorage

struct MakeConfirmationDialogStorage<Actions: View, Message: View>: StatefulRule {
    typealias Value = (inout [ViewIdentity: ConfirmationDialogStorage]) -> Void

    let modifier: Attribute<ConfirmationDialogModifier<Actions, Message>>
    let identity: ViewIdentity

    mutating func updateValue() {
        let m = modifier.value
        guard m.isPresented.wrappedValue else {
            let id = identity
            AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: ConfirmationDialogStorage]) in
                dict.removeValue(forKey: id)
            } as Value)
            return
        }
        let pref = ConfirmationDialogPreference(
            title: m.title,
            titleVisibility: m.titleVisibility,
            makeActions: { AnyView(m.actions) },
            makeMessage: (m.message is EmptyView) ? nil : { AnyView(m.message) },
            isPresented: m.isPresented,
            onDismiss: nil
        )
        let storage = ConfirmationDialogStorage(preference: pref)
        let id = identity
        AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: ConfirmationDialogStorage]) in
            dict[id] = storage
        } as Value)
    }
}

// MARK: - ConfirmationDialogModifier

struct ConfirmationDialogModifier<Actions: View, Message: View>: ViewModifier {
    typealias Body = Never

    let title: Text
    let titleVisibility: Visibility
    let actions: Actions
    let message: Message
    let isPresented: Binding<Bool>
}

extension ConfirmationDialogModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                          body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ConfirmationDialogModifier._makeView called outside AG context")
        }
        let identity = ViewIdentity()
        let storageRule = MakeConfirmationDialogStorage<Actions, Message>(
            modifier: modifier._attribute,
            identity: identity
        )
        let storageAttr: Attribute<MakeConfirmationDialogStorage<Actions, Message>.Value> =
            graph.makeStatefulRule(storageRule)

        let prefAttr: Attribute<ConfirmationDialogStorage.PreferenceKey.Value> = graph.makeRule {
            var dict = ConfirmationDialogStorage.PreferenceKey.defaultValue
            storageAttr.value(&dict)
            return dict
        }
        var outputs = body(_Graph(), inputs)
        outputs.preferences.append(ConfirmationDialogStorage.PreferenceKey.self,
                                   node: prefAttr.identifier)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                     body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

// MARK: - ConfirmationDialogOverlayView

struct ConfirmationDialogOverlayView: View {
    let preference: ConfirmationDialogPreference

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .onTapGesture {}

            VStack(spacing: 0) {
                if preference.titleVisibility != .hidden {
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
                }

                preference.makeActions()
                    .padding(8)
            }
            .frame(width: 280)
            .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - View.confirmationDialog extensions

extension View {
    public func confirmationDialog<A: View>(_ titleKey: LocalizedStringKey,
                                            isPresented: Binding<Bool>,
                                            titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions)
    }

    public func confirmationDialog<S: StringProtocol, A: View>(_ title: S,
                                                                isPresented: Binding<Bool>,
                                                                titleVisibility: Visibility = .automatic,
                                                                @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions)
    }

    public func confirmationDialog<A: View>(_ title: Text,
                                            isPresented: Binding<Bool>,
                                            titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: () -> A) -> some View {
        modifier(ConfirmationDialogModifier(title: title,
                                            titleVisibility: titleVisibility,
                                            actions: actions().modifier(ActionsModifier()),
                                            message: EmptyView(),
                                            isPresented: isPresented))
    }
}

extension View {
    public func confirmationDialog<A: View, M: View>(_ titleKey: LocalizedStringKey,
                                                      isPresented: Binding<Bool>,
                                                      titleVisibility: Visibility = .automatic,
                                                      @ViewBuilder actions: () -> A,
                                                      @ViewBuilder message: () -> M) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions, message: message)
    }

    public func confirmationDialog<S: StringProtocol, A: View, M: View>(_ title: S,
                                                                          isPresented: Binding<Bool>,
                                                                          titleVisibility: Visibility = .automatic,
                                                                          @ViewBuilder actions: () -> A,
                                                                          @ViewBuilder message: () -> M) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions, message: message)
    }

    public func confirmationDialog<A: View, M: View>(_ title: Text,
                                                      isPresented: Binding<Bool>,
                                                      titleVisibility: Visibility = .automatic,
                                                      @ViewBuilder actions: () -> A,
                                                      @ViewBuilder message: () -> M) -> some View {
        modifier(ConfirmationDialogModifier(title: title,
                                            titleVisibility: titleVisibility,
                                            actions: actions().modifier(ActionsModifier()),
                                            message: message(),
                                            isPresented: isPresented))
    }
}

extension View {
    public func confirmationDialog<A: View, T>(_ titleKey: LocalizedStringKey,
                                                isPresented: Binding<Bool>,
                                                titleVisibility: Visibility = .automatic,
                                                presenting data: T?,
                                                @ViewBuilder actions: (T) -> A) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility, presenting: data, actions: actions)
    }

    public func confirmationDialog<A: View, T>(_ title: Text,
                                                isPresented: Binding<Bool>,
                                                titleVisibility: Visibility = .automatic,
                                                presenting data: T?,
                                                @ViewBuilder actions: (T) -> A) -> some View {
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let data {
            return AnyView(modifier(ConfirmationDialogModifier(
                title: title, titleVisibility: titleVisibility,
                actions: actions(data).modifier(ActionsModifier()),
                message: EmptyView(), isPresented: gated)))
        }
        return AnyView(modifier(ConfirmationDialogModifier(
            title: title, titleVisibility: titleVisibility,
            actions: EmptyView().modifier(ActionsModifier()),
            message: EmptyView(), isPresented: gated)))
    }
}

extension View {
    public func confirmationDialog<A: View, M: View, T>(_ titleKey: LocalizedStringKey,
                                                         isPresented: Binding<Bool>,
                                                         titleVisibility: Visibility = .automatic,
                                                         presenting data: T?,
                                                         @ViewBuilder actions: (T) -> A,
                                                         @ViewBuilder message: (T) -> M) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility,
                           presenting: data, actions: actions, message: message)
    }

    public func confirmationDialog<A: View, M: View, T>(_ title: Text,
                                                         isPresented: Binding<Bool>,
                                                         titleVisibility: Visibility = .automatic,
                                                         presenting data: T?,
                                                         @ViewBuilder actions: (T) -> A,
                                                         @ViewBuilder message: (T) -> M) -> some View {
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let data {
            return AnyView(modifier(ConfirmationDialogModifier(
                title: title, titleVisibility: titleVisibility,
                actions: actions(data).modifier(ActionsModifier()),
                message: message(data), isPresented: gated)))
        }
        return AnyView(modifier(ConfirmationDialogModifier(
            title: title, titleVisibility: titleVisibility,
            actions: EmptyView().modifier(ActionsModifier()),
            message: EmptyView(), isPresented: gated)))
    }
}
