//
//  File: TextEditorStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TextEditorStyleConfiguration {
    var storage: TextEditor.Storage

    init(storage: TextEditor.Storage) {
        self.storage = storage
    }
}

public protocol TextEditorStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = TextEditorStyleConfiguration
}

public struct AutomaticTextEditorStyle: TextEditorStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> Body {
        Body(configuration: configuration)
    }

    public struct Body: View {
        var configuration: TextEditorStyleConfiguration

        public var body: some View {
            TextEditor(configuration: configuration)
                .textEditorStyle(SystemTextEditorStyle())
        }
    }
}

public struct PlainTextEditorStyle: TextEditorStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        TextEditorControl(
            configuration: configuration,
            drawsBackground: false
        )
        .scrollContentBackground(.hidden)
    }
}

extension TextEditorStyle where Self == AutomaticTextEditorStyle {
    public static var automatic: AutomaticTextEditorStyle {
        AutomaticTextEditorStyle()
    }
}

extension TextEditorStyle where Self == PlainTextEditorStyle {
    public static var plain: PlainTextEditorStyle {
        PlainTextEditorStyle()
    }
}

extension View {
    nonisolated public func textEditorStyle(
        _ style: some TextEditorStyle
    ) -> some View {
        modifier(TextEditorStyleModifier(style: style))
    }
}

private struct SystemTextEditorStyle: TextEditorStyle {
    func makeBody(configuration: Configuration) -> some View {
        TextEditorControl(
            configuration: configuration,
            drawsBackground: true
        )
    }
}

private struct TextEditorControl: View {
    var configuration: TextEditorStyleConfiguration
    var drawsBackground: Bool

    @State private var inputState = TextEditorInputState()
    @State private var selectionLayout = TextEditorSelectionLayoutStorage()
    @FocusState private var isFocused: Bool
    @Environment(\.scrollContentBackground)
    private var contentBackground
    @Environment(\.textFieldCaretBlinkInterval)
    private var caretBlinkInterval

    private let contentInsets = EdgeInsets(
        top: 5,
        leading: 5,
        bottom: 5,
        trailing: 5
    )

    var body: some View {
        ScrollablePreferenceKey._delay { scrollables in
            styledEditor
                .modifier(inputModifier(scrollables: scrollables.attribute))
                .focused($isFocused)
        }
    }

    @ViewBuilder
    private var styledEditor: some View {
        if drawsBackground && contentBackground.visibility != .hidden {
            editor.background(BackgroundStyle())
        } else {
            editor
        }
    }

    private var editor: some View {
        ScrollView(.vertical, showsIndicators: true) {
            document
                .padding(contentInsets)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 32, minHeight: 36)
    }

    @ViewBuilder
    private var document: some View {
        if inputState.isFocused,
           !inputState.hasSelection,
           inputState.compositionRange == nil,
           TextFieldCaret.resolvedBlinkInterval(caretBlinkInterval) > 0 {
            let start = Date()
            TimelineView(.periodic(
                from: start,
                by: TextFieldCaret.resolvedBlinkInterval(caretBlinkInterval)
            )) { (context: TimelineViewDefaultContext) in
                renderedText(caretVisible: TextFieldCaret.isBlinkVisible(
                    at: context.date,
                    from: start,
                    interval: caretBlinkInterval
                ))
            }
            .id(inputState.blinkResetID)
        } else {
            renderedText(caretVisible: inputState.isFocused)
        }
    }

    private func renderedText(caretVisible: Bool) -> some View {
        Text(verbatim: TextEditorSelectionLayout.displayText(for: text.wrappedValue))
            .lineLimit(nil)
            .textRenderer(TextEditorRenderer(
                selectionLayout: selectionLayout,
                inputState: inputState,
                drawsCaret: caretVisible
            ))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var text: Binding<String> {
        switch configuration.storage {
        case .string(let payload):
            payload.0
        }
    }

    private var selection: Binding<TextSelection?>? {
        switch configuration.storage {
        case .string(let payload):
            payload.1
        }
    }

    private func inputModifier(
        scrollables: WeakAttribute<[any Scrollable]>
    ) -> TextEditorInputModifier {
        TextEditorInputModifier(
            text: text,
            selection: selection,
            selectionValue: selection?.wrappedValue,
            inputState: $inputState,
            selectionLayout: selectionLayout,
            scrollables: scrollables,
            contentInsets: contentInsets
        )
    }
}
