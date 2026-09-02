//
//  File: TextFieldStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _TextFieldStyleLabel: View, ViewAlias {
    public typealias Body = Never
}

extension _TextFieldStyleLabel: PrimitiveView {}

public protocol TextFieldStyle {
    associatedtype _Body: View
    @ViewBuilder func _body(configuration: TextField<Self._Label>) -> Self._Body
    typealias _Label = _TextFieldStyleLabel
}

public struct DefaultTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(
        configuration: TextField<_TextFieldStyleLabel>
    ) -> some View {
        TextFieldControl(configuration: configuration, drawsBorder: true)
    }
}

public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(
        configuration: TextField<_TextFieldStyleLabel>
    ) -> some View {
        TextFieldControl(configuration: configuration, drawsBorder: false)
    }
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

extension View {
    public func textFieldStyle<S>(_ style: S) -> some View
    where S: TextFieldStyle {
        modifier(TextFieldStyleModifier(style: style))
    }
}

private struct TextFieldControl: View {
    var configuration: TextField<_TextFieldStyleLabel>
    var drawsBorder: Bool
    @State private var inputState = TextFieldInputState()
    @FocusState private var isFocused: Bool
    @Environment(\.textFieldCompositionCaretStyle)
    private var compositionCaretStyle

    var body: some View {
        styledContent.onChange(of: configuration._text.wrappedValue) {
            _, projectedValue in
            synchronizeFormattedText(projectedValue)
        }
    }

    @ViewBuilder
    private var styledContent: some View {
        if drawsBorder {
            editorContent
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    Color.white,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(
                            inputState.isFocused
                                ? Color.blue
                                : Color(white: 0.72),
                            lineWidth: inputState.isFocused ? 2 : 1
                        )
                }
                .modifier(inputModifier)
                .focused($isFocused)
        } else {
            editorContent
                .modifier(inputModifier)
                .focused($isFocused)
        }
    }

    private func synchronizeFormattedText(_ projectedValue: String) {
        var state = configuration.state
        guard let formatActions = state.formatActions else { return }

        let representsProjectedValue = formatActions.finalize(
            state.displayText
        ) == projectedValue
        let acceptsExternalValue = !state.isEditing
            || formatActions.validate(state.displayText)
        guard acceptsExternalValue,
              !representsProjectedValue,
              state.displayText != projectedValue else {
            return
        }
        state.displayText = projectedValue
        configuration.$state.wrappedValue = state
    }

    @ViewBuilder
    private var editorContent: some View {
        let text = configuration.state.formatActions == nil
            ? configuration._text.wrappedValue
            : configuration.state.displayText
        let segments = inputState.displaySegments(in: text)
        let defaultCaretWidth: CGFloat = 1
        HStack(spacing: 0) {
            if text.isEmpty && inputState.composition.isEmpty {
                promptContent
                    .overlay(alignment: .leading) {
                        if inputState.isFocused {
                            TextFieldCaret(
                                compositionText: nil,
                                defaultWidth: defaultCaretWidth,
                                blinkResetID: inputState.caretOffset
                            )
                        }
                    }
            } else {
                Text(segments.leading)
                if segments.selected.isEmpty == false {
                    Text(segments.selected)
                        .foregroundStyle(Color.white)
                        .background(Color.blue)
                } else if inputState.composition.isEmpty == false {
                    TextFieldCaret(
                        compositionText: inputState.composition,
                        defaultWidth: defaultCaretWidth,
                        compositionStyle: compositionCaretStyle
                    )
                }
                Text(segments.trailing)
                    .overlay(alignment: .leading) {
                        if inputState.isFocused,
                           inputState.composition.isEmpty,
                           segments.selected.isEmpty {
                            TextFieldCaret(
                                compositionText: nil,
                                defaultWidth: defaultCaretWidth,
                                blinkResetID: inputState.caretOffset
                            )
                        }
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 18)
    }

    @ViewBuilder
    private var promptContent: some View {
        if let prompt = configuration.prompt {
            prompt.foregroundStyle(Color.secondary)
        } else {
            configuration.label.foregroundStyle(Color.secondary)
        }
    }

    private var inputModifier: TextFieldInputModifier {
        TextFieldInputModifier(
            text: configuration._text,
            selection: configuration.selection,
            selectionValue: configuration.selection?.wrappedValue,
            fieldState: configuration.$state,
            inputState: $inputState,
            contentLeadingInset: drawsBorder ? 6 : 0
        )
    }
}
