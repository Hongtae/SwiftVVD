//
//  File: AlertModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct AlertModifier<Actions, Message>: ViewModifier where Actions: View, Message: View {
    typealias Body = Never
    
    var presentedValue: Bool = false
    let isPresented: Binding<Bool>
    let title: Text
    let actions: Actions
    let message: Message
}

extension View {
    public func alert<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where A: View {
        self.alert(Text(titleKey), isPresented: isPresented, actions: actions)
    }
    
    public func alert<S, A>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where S: StringProtocol, A: View {
        self.alert(Text(title), isPresented: isPresented, actions: actions)
    }
    
    public func alert<A>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where A: View {
        self.modifier(
            AlertModifier(isPresented: isPresented,
                          title: title,
                          actions: actions(),
                          message: EmptyView())
        )
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
        self.modifier(
            AlertModifier(isPresented: isPresented,
                          title: title,
                          actions: actions(),
                          message: message())
        )
    }
}

extension View {
    public func alert<A, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where A: View {
        fatalError()
    }
    
    public func alert<S, A, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where S: StringProtocol, A: View {
        fatalError()
    }
    
    public func alert<A, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where A: View {
        fatalError()
    }
}

extension View {
    public func alert<A, M, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where A: View, M: View {
        fatalError()
    }
    
    public func alert<S, A, M, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where S: StringProtocol, A: View, M: View {
        fatalError()
    }
    
    public func alert<A, M, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where A: View, M: View {
        fatalError()
    }
}

extension View {
    public func alert<E, A>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: () -> A) -> some View where E: LocalizedError, A: View {
        fatalError()
    }
    
    public func alert<E, A, M>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: (E) -> A, @ViewBuilder message: (E) -> M) -> some View where E: LocalizedError, A: View, M: View {
        fatalError()
    }
}
