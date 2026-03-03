//
//  File: AlertModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ActionsModifier: ViewModifier {
    typealias Body = Never

    let canPresent: Bool
}

protocol _AlertActionsView: View {
    associatedtype ActualContent: View
    var _canPresent: Bool { get }
    var _content: ActualContent { get }
}

extension ModifiedContent: _AlertActionsView where Modifier == ActionsModifier, Content: View {
    typealias ActualContent = Content
    var _canPresent: Bool { modifier.canPresent }
    var _content: Content { content }
}

struct AlertModifier<Actions, Message>: ViewModifier where Actions: _AlertActionsView, Message: View {
    typealias Body = Never

    let title: Text
    let actions: Actions
    let message: Message
    fileprivate let isPresented: Binding<Bool>  // mirrored for DynamicProperty tracking
}

extension View {
    public func alert<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where A: View {
        self.alert(Text(titleKey), isPresented: isPresented, actions: actions)
    }

    public func alert<S, A>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where S: StringProtocol, A: View {
        self.alert(Text(title), isPresented: isPresented, actions: actions)
    }

    public func alert<A>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where A: View {
        let actionsView = Optional(actions())
            .modifier(ActionsModifier(canPresent: true))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: EmptyView(), isPresented: isPresented))
    }
}

extension View {
    public func alert<A, M>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View where A: View, M: View {
        self.alert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<S, A, M>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View where S: StringProtocol, A: View, M: View {
        self.alert(Text(title), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<A, M>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View where A: View, M: View {
        let actionsView = Optional(actions())
            .modifier(ActionsModifier(canPresent: true))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: message(), isPresented: isPresented))
    }
}

extension View {
    public func alert<A, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where A: View {
        self.alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions)
    }

    public func alert<S, A, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where S: StringProtocol, A: View {
        self.alert(Text(title), isPresented: isPresented, presenting: data, actions: actions)
    }

    public func alert<A, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where A: View {
        let actionsView = data.map(actions)
            .modifier(ActionsModifier(canPresent: data != nil))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: EmptyView(), isPresented: isPresented))
    }
}

extension View {
    public func alert<A, M, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where A: View, M: View {
        self.alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }

    public func alert<S, A, M, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where S: StringProtocol, A: View, M: View {
        self.alert(Text(title), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }

    public func alert<A, M, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where A: View, M: View {
        let actionsView = data.map(actions)
            .modifier(ActionsModifier(canPresent: data != nil))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: data.map(message), isPresented: isPresented))
    }
}

extension View {
    public func alert<E, A>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: () -> A) -> some View where E: LocalizedError, A: View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        let actionsView = Optional(actions())
            .modifier(ActionsModifier(canPresent: error != nil))
        let messageView = error.map { e in
            Text([e.failureReason, e.recoverySuggestion].compactMap { $0 }.joined(separator: "\n"))
        }
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: messageView, isPresented: isPresented))
    }

    public func alert<E, A, M>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: (E) -> A, @ViewBuilder message: (E) -> M) -> some View where E: LocalizedError, A: View, M: View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        let actionsView = error.map(actions)
            .modifier(ActionsModifier(canPresent: error != nil))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: error.map(message), isPresented: isPresented))
    }
}

private struct AlertContentView<Actions: View, Message: View>: View {
    let title: Text
    let actions: Actions
    let message: Message

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                title.font(.headline)
                message
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()

            actions
                .padding(8)
        }
        .frame(width: 280)
    }
}

extension ActionsModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

extension AlertModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}
