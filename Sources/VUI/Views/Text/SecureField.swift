//
//  File: SecureField.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct SecureField<Label>: View where Label: View {
    var _text: Binding<String>
    var prompt: Text?
    var deprecatedActions: TextFieldState.DeprecatedActions?
    var label: Label

    init(
        text: Binding<String>,
        prompt: Text?,
        deprecatedActions: TextFieldState.DeprecatedActions?,
        label: Label
    ) {
        _text = text
        self.prompt = prompt
        self.deprecatedActions = deprecatedActions
        self.label = label
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            text: text,
            prompt: prompt,
            deprecatedActions: nil,
            label: label()
        )
    }

    public var body: some View {
        TextField(
            text: _text,
            isSecure: true,
            label: label,
            axis: .horizontal,
            prompt: prompt,
            state: StateOrBinding(wrappedValue: TextFieldState(
                displayText: _text.wrappedValue,
                deprecatedActions: deprecatedActions
            )),
            selection: nil
        )
    }
}

extension SecureField where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        prompt: Text?
    ) {
        self.init(text: text, prompt: prompt) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        text: Binding<String>,
        prompt: Text?
    ) {
        self.init(text: text, prompt: prompt) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        text: Binding<String>,
        prompt: Text?
    ) where S: StringProtocol {
        self.init(text: text, prompt: prompt) {
            Text(title)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>
    ) {
        self.init(
            text: text,
            prompt: nil,
            deprecatedActions: TextFieldState.DeprecatedActions(
                editingChanged: { _ in },
                commit: {}
            ),
            label: Text(titleKey)
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        text: Binding<String>
    ) {
        self.init(text: text) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        text: Binding<String>
    ) where S: StringProtocol {
        self.init(
            text: text,
            prompt: nil,
            deprecatedActions: TextFieldState.DeprecatedActions(
                editingChanged: { _ in },
                commit: {}
            ),
            label: Text(title)
        )
    }
}
