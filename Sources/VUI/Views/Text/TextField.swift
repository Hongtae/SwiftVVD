//
//  File: TextField.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private struct TextFieldCursorEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// Whether text fields request an I-beam cursor while hovered.
    var isTextFieldCursorEnabled: Bool {
        get { self[TextFieldCursorEnabledKey.self] }
        set { self[TextFieldCursorEnabledKey.self] = newValue }
    }
}

public enum TextSelectionAffinity: Equatable, Hashable, Sendable {
    case automatic
    case upstream
    case downstream
}

public struct TextSelection: Equatable, Hashable {
    public enum Indices: Equatable, Hashable {
        case selection(Range<String.Index>)
        case multiSelection(RangeSet<String.Index>)
    }

    public var indices: Indices
    public var affinity: TextSelectionAffinity

    public init(range: Range<String.Index>) {
        indices = .selection(range)
        affinity = .automatic
    }

    public init(ranges: RangeSet<String.Index>) {
        indices = .multiSelection(ranges)
        affinity = .automatic
    }

    public init(insertionPoint: String.Index) {
        indices = .selection(insertionPoint..<insertionPoint)
        affinity = .automatic
    }

    public var isInsertion: Bool {
        switch indices {
        case .selection(let range):
            range.isEmpty
        case .multiSelection:
            false
        }
    }
}

struct OptionalViewAlias<Alias> {
    init() {}
}

extension EnvironmentValues {
    struct TextInputSuggestions {}
}

struct SearchFieldConfiguration {
    struct Suggestions {
        init() {}
    }
}

struct TextFieldState {
    struct FormatActions {}

    struct DeprecatedActions {
        var editingChanged: (Bool) -> Void
        var commit: () -> Void
    }

    var displayText: String
    var formatActions: FormatActions?
    var deprecatedActions: DeprecatedActions?
    var shouldOverrideValidation: Bool
    var selection: ViewIdentity?
    var hasSuggestions: Bool?
    var isPresentingSuggestions: Bool
    var isEditing: Bool

    init(
        displayText: String,
        formatActions: FormatActions? = nil,
        deprecatedActions: DeprecatedActions? = nil,
        shouldOverrideValidation: Bool = false,
        selection: ViewIdentity? = nil,
        hasSuggestions: Bool? = nil,
        isPresentingSuggestions: Bool = false,
        isEditing: Bool = false
    ) {
        self.displayText = displayText
        self.formatActions = formatActions
        self.deprecatedActions = deprecatedActions
        self.shouldOverrideValidation = shouldOverrideValidation
        self.selection = selection
        self.hasSuggestions = hasSuggestions
        self.isPresentingSuggestions = isPresentingSuggestions
        self.isEditing = isEditing
    }
}

public struct TextField<Label>: View where Label: View {
    var _text: Binding<String>
    var isSecure: Bool
    var label: Label
    var axis: Axis
    var prompt: Text?
    @StateOrBinding var state: TextFieldState
    var selection: Binding<TextSelection?>?
    var _suggestions: OptionalViewAlias<EnvironmentValues.TextInputSuggestions>
    var suggestionsViewAlias: SearchFieldConfiguration.Suggestions

    init(
        text: Binding<String>,
        isSecure: Bool,
        label: Label,
        axis: Axis,
        prompt: Text?,
        state: StateOrBinding<TextFieldState>,
        selection: Binding<TextSelection?>?
    ) {
        _text = text
        self.isSecure = isSecure
        self.label = label
        self.axis = axis
        self.prompt = prompt
        _state = state
        self.selection = selection
        _suggestions = OptionalViewAlias()
        suggestionsViewAlias = SearchFieldConfiguration.Suggestions()
    }

    public init(
        text: Binding<String>,
        prompt: Text? = nil,
        axis: Axis = .horizontal,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            text: text,
            isSecure: false,
            label: label(),
            axis: axis,
            prompt: prompt,
            state: StateOrBinding(wrappedValue: TextFieldState(
                displayText: text.wrappedValue
            )),
            selection: nil
        )
    }

    public init(
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis? = nil,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            text: text,
            isSecure: false,
            label: label(),
            axis: axis ?? .horizontal,
            prompt: prompt,
            state: StateOrBinding(wrappedValue: TextFieldState(
                displayText: text.wrappedValue
            )),
            selection: selection
        )
    }

    public var body: some View {
        ResolvedTextFieldStyle(configuration: TextField<_TextFieldStyleLabel>(
            text: _text,
            isSecure: isSecure,
            label: _TextFieldStyleLabel(),
            axis: axis,
            prompt: prompt,
            state: StateOrBinding($state),
            selection: selection
        ))
        .modifier(
            StaticSourceWriter<_TextFieldStyleLabel, Label>(source: label)
        )
    }
}

extension TextField where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>
    ) {
        self.init(
            text: text,
            isSecure: false,
            label: Text(titleKey),
            axis: .horizontal,
            prompt: nil,
            state: StateOrBinding(wrappedValue: TextFieldState(
                displayText: text.wrappedValue,
                deprecatedActions: TextFieldState.DeprecatedActions(
                    editingChanged: { _ in },
                    commit: {}
                )
            )),
            selection: nil
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        prompt: Text?
    ) {
        self.init(text: text, prompt: prompt) {
            Text(titleKey)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        axis: Axis
    ) {
        self.init(text: text, axis: axis) {
            Text(titleKey)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        prompt: Text?,
        axis: Axis
    ) {
        self.init(text: text, prompt: prompt, axis: axis) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        text: Binding<String>
    ) where S: StringProtocol {
        self.init(
            text: text,
            isSecure: false,
            label: Text(title),
            axis: .horizontal,
            prompt: nil,
            state: StateOrBinding(wrappedValue: TextFieldState(
                displayText: text.wrappedValue,
                deprecatedActions: TextFieldState.DeprecatedActions(
                    editingChanged: { _ in },
                    commit: {}
                )
            )),
            selection: nil
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis? = nil
    ) {
        self.init(
            text: text,
            selection: selection,
            prompt: prompt,
            axis: axis
        ) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis? = nil
    ) {
        self.init(
            text: text,
            selection: selection,
            prompt: prompt,
            axis: axis
        ) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        text: Binding<String>,
        selection: Binding<TextSelection?>,
        prompt: Text? = nil,
        axis: Axis? = nil
    ) where S: StringProtocol {
        self.init(
            text: text,
            selection: selection,
            prompt: prompt,
            axis: axis
        ) {
            Text(title)
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

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        text: Binding<String>,
        axis: Axis
    ) where S: StringProtocol {
        self.init(text: text, axis: axis) {
            Text(title)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        text: Binding<String>,
        prompt: Text?,
        axis: Axis
    ) where S: StringProtocol {
        self.init(text: text, prompt: prompt, axis: axis) {
            Text(title)
        }
    }
}

public struct _TextFieldStyleLabel: View, ViewAlias {
    public typealias Body = Never
}

extension _TextFieldStyleLabel: PrimitiveView {}

public protocol TextFieldStyle {
    associatedtype _Body: View
    @ViewBuilder func _body(configuration: TextField<Self._Label>) -> Self._Body
    typealias _Label = _TextFieldStyleLabel
}

struct ResolvedTextFieldStyle: StyleableView {
    typealias Configuration = TextField<_TextFieldStyleLabel>
    var configuration: Configuration

    var body: some View {
        configuration
    }

    typealias DefaultStyleModifier =
        TextFieldStyleModifier<DefaultTextFieldStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        TextFieldStyleModifier(style: DefaultTextFieldStyle())
    }
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

public enum TextFieldCompositionCaretStyle: Hashable, Sendable {
    /// Draws the marked text normally followed by a nonblinking insertion
    /// caret.
    case insertionPoint
    /// Draws the marked text inside a nonblinking, color-inverted caret.
    case enclosing
}

private struct TextFieldCompositionCaretStyleKey: EnvironmentKey {
    static let defaultValue: TextFieldCompositionCaretStyle = .enclosing
}

extension EnvironmentValues {
    public var textFieldCompositionCaretStyle: TextFieldCompositionCaretStyle {
        get { self[TextFieldCompositionCaretStyleKey.self] }
        set { self[TextFieldCompositionCaretStyleKey.self] = newValue }
    }
}

extension View {
    public func textFieldCompositionCaretStyle(
        _ style: TextFieldCompositionCaretStyle
    ) -> some View {
        environment(\.textFieldCompositionCaretStyle, style)
    }
}

enum TextFieldInputResult: Equatable {
    case changed
    case submit
    case handled
}

struct TextFieldInputState: Equatable {
    var composition = ""
    var compositionReplacementRange: Range<Int>?
    var caretOffset = 0
    var selectionRange: Range<Int>?
    var selectionAffinity: TextSelectionAffinity = .automatic
    var isFocused = false

    var selectionOffsets: Range<Int> {
        selectionRange ?? caretOffset..<caretOffset
    }

    var hasSelection: Bool {
        selectionRange?.isEmpty == false
    }

    mutating func setFocused(_ focused: Bool, committedText: String) {
        isFocused = focused
        composition = ""
        compositionReplacementRange = nil
        if focused {
            caretOffset = committedText.count
            selectionRange = nil
            selectionAffinity = .upstream
        } else {
            clampCaret(to: committedText)
        }
    }

    mutating func setSelection(
        _ selection: TextSelection,
        committedText: String
    ) -> Bool {
        let offsets: Range<Int>
        switch selection.indices {
        case .selection(let range):
            offsets = committedText.distance(
                from: committedText.startIndex,
                to: range.lowerBound
            )..<committedText.distance(
                from: committedText.startIndex,
                to: range.upperBound
            )
        case .multiSelection:
            return false
        }
        return setSelection(
            offsets,
            affinity: selection.affinity,
            committedText: committedText
        )
    }

    @discardableResult
    mutating func setSelection(
        _ offsets: Range<Int>,
        affinity: TextSelectionAffinity,
        committedText: String
    ) -> Bool {
        let lower = min(max(offsets.lowerBound, 0), committedText.count)
        let upper = min(max(offsets.upperBound, lower), committedText.count)
        let oldOffsets = selectionOffsets
        let oldAffinity = selectionAffinity
        caretOffset = upper
        selectionRange = lower == upper ? nil : lower..<upper
        selectionAffinity = affinity
        composition = ""
        compositionReplacementRange = nil
        return oldOffsets != selectionOffsets || oldAffinity != affinity
    }

    mutating func collapseSelection(
        to offset: Int,
        affinity: TextSelectionAffinity,
        committedText: String
    ) {
        _ = setSelection(
            offset..<offset,
            affinity: affinity,
            committedText: committedText
        )
    }

    func textSelection(in committedText: String) -> TextSelection {
        let offsets = selectionOffsets
        let lower = committedText.index(
            committedText.startIndex,
            offsetBy: min(max(offsets.lowerBound, 0), committedText.count)
        )
        let upper = committedText.index(
            committedText.startIndex,
            offsetBy: min(max(offsets.upperBound, 0), committedText.count)
        )
        var selection = TextSelection(range: lower..<upper)
        selection.affinity = selectionAffinity
        return selection
    }

    mutating func replaceComposition(
        with text: String,
        committedText: String
    ) {
        clampCaret(to: committedText)
        if compositionReplacementRange == nil,
           text.isEmpty == false || hasSelection {
            compositionReplacementRange = selectionOffsets
        }
        if let replacement = compositionReplacementRange {
            caretOffset = min(
                replacement.lowerBound + text.count,
                committedText.count
            )
            selectionAffinity = text.isEmpty ? .downstream : .upstream
        }
        selectionRange = nil
        composition = text
    }

    mutating func handleTextInput(
        _ input: String,
        committedText: inout String
    ) -> TextFieldInputResult {
        clampCaret(to: committedText)
        if let replacement = compositionReplacementRange {
            caretOffset = replacement.upperBound
            selectionRange = replacement.isEmpty ? nil : replacement
        }
        compositionReplacementRange = nil

        switch input {
        case "\r", "\n":
            return .submit
        case "\t", "\u{1B}":
            return .handled
        case "\u{8}", "\u{7F}":
            if removeSelection(from: &committedText) {
                selectionAffinity = .downstream
                return .changed
            }
            guard caretOffset > 0 else { return .handled }
            let end = committedText.index(
                committedText.startIndex,
                offsetBy: caretOffset
            )
            let start = committedText.index(before: end)
            committedText.removeSubrange(start..<end)
            caretOffset -= 1
            selectionAffinity = .downstream
            return .changed
        case "\u{F728}":
            if removeSelection(from: &committedText) {
                selectionAffinity = .downstream
                return .changed
            }
            guard caretOffset < committedText.count else { return .handled }
            let start = committedText.index(
                committedText.startIndex,
                offsetBy: caretOffset
            )
            let end = committedText.index(after: start)
            committedText.removeSubrange(start..<end)
            selectionAffinity = .downstream
            return .changed
        default:
            _ = removeSelection(from: &committedText)
            let index = committedText.index(
                committedText.startIndex,
                offsetBy: caretOffset
            )
            committedText.insert(contentsOf: input, at: index)
            caretOffset += input.count
            selectionRange = nil
            selectionAffinity = .upstream
            return input.isEmpty ? .handled : .changed
        }
    }

    mutating func handleKeyDown(
        _ key: VirtualKey,
        committedText: inout String
    ) -> Bool {
        clampCaret(to: committedText)

        switch key {
        case .left:
            if let selectionRange {
                caretOffset = selectionRange.lowerBound
                self.selectionRange = nil
            } else {
                caretOffset = max(0, caretOffset - 1)
            }
            selectionAffinity = .downstream
        case .right:
            if let selectionRange {
                caretOffset = selectionRange.upperBound
                self.selectionRange = nil
            } else {
                caretOffset = min(committedText.count, caretOffset + 1)
            }
            selectionAffinity = .upstream
        case .home:
            caretOffset = 0
            selectionRange = nil
            selectionAffinity = .downstream
        case .end:
            caretOffset = committedText.count
            selectionRange = nil
            selectionAffinity = .upstream
        default:
            // Editing control characters are delivered through textInput.
            // Raw keys own physical caret navigation only.
            return false
        }
        return true
    }

    func segments(in committedText: String) -> (String, String) {
        let parts = displaySegments(in: committedText)
        return (parts.leading, parts.selected + parts.trailing)
    }

    func displaySegments(
        in committedText: String
    ) -> (leading: String, selected: String, trailing: String) {
        let offsets = compositionReplacementRange ?? selectionOffsets
        let lower = committedText.index(
            committedText.startIndex,
            offsetBy: min(max(offsets.lowerBound, 0), committedText.count)
        )
        let upper = committedText.index(
            committedText.startIndex,
            offsetBy: min(max(offsets.upperBound, 0), committedText.count)
        )
        return (
            String(committedText[..<lower]),
            compositionReplacementRange == nil
                ? String(committedText[lower..<upper])
                : "",
            String(committedText[upper...])
        )
    }

    func transformationRange(in committedText: String) -> Range<Int>? {
        if let selectionRange, selectionRange.isEmpty == false {
            return selectionRange
        }
        let characters = Array(committedText)
        guard characters.isEmpty == false else { return nil }

        let seed: Int
        if caretOffset < characters.count,
           Self.isWordCharacter(characters[caretOffset]) {
            seed = caretOffset
        } else if caretOffset > 0,
                  Self.isWordCharacter(characters[caretOffset - 1]) {
            seed = caretOffset - 1
        } else {
            return nil
        }

        var lower = seed
        var upper = seed + 1
        while lower > 0, Self.isWordCharacter(characters[lower - 1]) {
            lower -= 1
        }
        while upper < characters.count,
              Self.isWordCharacter(characters[upper]) {
            upper += 1
        }
        return lower..<upper
    }

    @discardableResult
    mutating func transformSelection(
        in committedText: inout String,
        transform: (String) -> String
    ) -> Bool {
        guard let offsets = transformationRange(in: committedText) else {
            return false
        }
        let lower = committedText.index(
            committedText.startIndex,
            offsetBy: offsets.lowerBound
        )
        let upper = committedText.index(
            committedText.startIndex,
            offsetBy: offsets.upperBound
        )
        let replacement = transform(String(committedText[lower..<upper]))
        committedText.replaceSubrange(lower..<upper, with: replacement)
        caretOffset = offsets.lowerBound + replacement.count
        selectionRange = offsets.lowerBound..<caretOffset
        selectionAffinity = .upstream
        compositionReplacementRange = nil
        return true
    }

    private mutating func clampCaret(to text: String) {
        caretOffset = min(max(caretOffset, 0), text.count)
        if let selectionRange {
            let lower = min(max(selectionRange.lowerBound, 0), text.count)
            let upper = min(max(selectionRange.upperBound, lower), text.count)
            self.selectionRange = lower == upper ? nil : lower..<upper
        }
        if let compositionReplacementRange {
            let lower = min(
                max(compositionReplacementRange.lowerBound, 0),
                text.count
            )
            let upper = min(
                max(compositionReplacementRange.upperBound, lower),
                text.count
            )
            self.compositionReplacementRange = lower..<upper
        }
    }

    private mutating func removeSelection(from text: inout String) -> Bool {
        guard let selectionRange, selectionRange.isEmpty == false else {
            return false
        }
        let lower = text.index(
            text.startIndex,
            offsetBy: selectionRange.lowerBound
        )
        let upper = text.index(
            text.startIndex,
            offsetBy: selectionRange.upperBound
        )
        text.removeSubrange(lower..<upper)
        caretOffset = selectionRange.lowerBound
        self.selectionRange = nil
        return true
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character == "_" || character.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
        }
    }
}

struct TextFieldCaretMetrics: Equatable {
    var compositionWidth: CGFloat?
    var fontLineHeight: CGFloat
    var defaultWidth: CGFloat

    var size: CGSize {
        CGSize(
            width: max(compositionWidth ?? 0, defaultWidth),
            height: fontLineHeight
        )
    }
}

private struct TextFieldCaretLayout: Layout {
    var usesCompositionWidth: Bool
    var defaultWidth: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let fontLineSize = subview.sizeThatFits(.unspecified)
        return TextFieldCaretMetrics(
            compositionWidth: usesCompositionWidth
                ? fontLineSize.width
                : nil,
            fontLineHeight: fontLineSize.height,
            defaultWidth: defaultWidth
        ).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let size = subview.sizeThatFits(.unspecified)
        subview.place(
            at: CGPoint(
                x: bounds.minX,
                y: bounds.minY + (bounds.height - size.height) * 0.5
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(size)
        )
    }
}

struct TextFieldCaret: View {
    static let blinkInterval: TimeInterval = 0.5

    enum Presentation: Equatable {
        case insertionPoint(compositionText: String?, blinks: Bool)
        case enclosing(String)
    }

    var compositionText: String?
    var defaultWidth: CGFloat
    var compositionStyle: TextFieldCompositionCaretStyle

    init(
        compositionText: String?,
        defaultWidth: CGFloat = 1,
        compositionStyle: TextFieldCompositionCaretStyle = .enclosing
    ) {
        self.compositionText = compositionText
        self.defaultWidth = defaultWidth
        self.compositionStyle = compositionStyle
    }

    @ViewBuilder
    var body: some View {
        switch Self.presentation(
            compositionText: compositionText,
            compositionStyle: compositionStyle
        ) {
        case .enclosing(let compositionText):
            caretContent(compositionText, usesCompositionWidth: true)
                .foregroundStyle(Color.white)
                .background(Color.blue)

        case .insertionPoint(let compositionText?, false):
            HStack(spacing: 0) {
                Text(compositionText)
                insertionCaret
            }

        case .insertionPoint(nil, true):
            let start = Date()
            TimelineView(.periodic(
                from: start,
                by: Self.blinkInterval
            )) { context in
                insertionCaret
                    .opacity(Self.isBlinkVisible(
                        at: context.date,
                        from: start
                    ) ? 1 : 0)
            }

        case .insertionPoint:
            insertionCaret
        }
    }

    static func presentation(
        compositionText: String?,
        compositionStyle: TextFieldCompositionCaretStyle
    ) -> Presentation {
        guard let compositionText, compositionText.isEmpty == false else {
            return .insertionPoint(compositionText: nil, blinks: true)
        }
        switch compositionStyle {
        case .insertionPoint:
            return .insertionPoint(
                compositionText: compositionText,
                blinks: false
            )
        case .enclosing:
            return .enclosing(compositionText)
        }
    }

    static func isBlinkVisible(
        at date: Date,
        from start: Date,
        interval: TimeInterval = blinkInterval
    ) -> Bool {
        precondition(interval > 0)
        let elapsed = max(date.timeIntervalSince(start), 0)
        return Int(floor(elapsed / interval)).isMultiple(of: 2)
    }

    private func caretContent(
        _ text: String,
        usesCompositionWidth: Bool
    ) -> some View {
        TextFieldCaretLayout(
            usesCompositionWidth: usesCompositionWidth,
            defaultWidth: defaultWidth
        ) {
            Text(text)
        }
    }

    private var insertionCaret: some View {
        caretContent("\u{200B}", usesCompositionWidth: false)
            .foregroundStyle(Color.clear)
            .background(Color.blue)
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

    @ViewBuilder
    private var editorContent: some View {
        let text = configuration._text.wrappedValue
        let segments = inputState.displaySegments(in: text)
        let defaultCaretWidth: CGFloat = 1
        HStack(spacing: 0) {
            if text.isEmpty && inputState.composition.isEmpty {
                if inputState.isFocused {
                    TextFieldCaret(
                        compositionText: nil,
                        defaultWidth: defaultCaretWidth
                    )
                }
                if let prompt = configuration.prompt {
                    prompt.foregroundStyle(Color.secondary)
                } else {
                    configuration.label.foregroundStyle(Color.secondary)
                }
            } else {
                Text(segments.leading)
                if segments.selected.isEmpty == false {
                    Text(segments.selected)
                        .foregroundStyle(Color.white)
                        .background(Color.blue)
                } else if inputState.composition.isEmpty {
                    if inputState.isFocused {
                        TextFieldCaret(
                            compositionText: nil,
                            defaultWidth: defaultCaretWidth
                        )
                    }
                } else {
                    TextFieldCaret(
                        compositionText: inputState.composition,
                        defaultWidth: defaultCaretWidth,
                        compositionStyle: compositionCaretStyle
                    )
                }
                Text(segments.trailing)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 18)
    }

    private var inputModifier: TextFieldInputModifier {
        TextFieldInputModifier(
            text: configuration._text,
            selection: configuration.selection,
            selectionValue: configuration.selection?.wrappedValue,
            fieldState: configuration.$state,
            inputState: $inputState
        )
    }
}

protocol TextInputResponder: AnyObject {
    func handleTextInputEvent(_ event: VVD.KeyboardEvent) -> Bool
    func textInputFocusDidChange(_ focused: Bool)
    func containsTextInputPoint(_ point: CGPoint) -> Bool
}

private struct TextFieldInputModifier: ViewModifier, MultiViewModifier {
    typealias Body = Never

    var text: Binding<String>
    var selection: Binding<TextSelection?>?
    var selectionValue: TextSelection?
    var fieldState: Binding<TextFieldState>
    var inputState: Binding<TextFieldInputState>

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TextFieldInputModifier._makeView called outside AG context"
            )
        }

        var outputs = body(_Graph(), inputs)
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map(\.value)
        let innerResponders: Attribute<[ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerResponders = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerResponders = Attribute(innerResponderNodes[0])
        } else {
            innerResponders = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for node in innerResponderNodes {
                    let value = Attribute<[ViewResponder]>(node).value
                    ViewRespondersKey.reduce(value: &combined) { value }
                }
                return combined
            }
        }

        let responder = graph.makeStatefulRule(
            TextFieldResponderFilter(
                modifier: modifier._attribute,
                environment: inputs.base.cachedEnvironment.value.environment,
                position: inputs.position,
                size: inputs.size,
                transform: inputs.transform,
                children: innerResponders,
                responder: nil
            )
        )
        outputs.preferences.preferences.removeAll {
            $0.key == ViewRespondersKey.self
        }
        outputs.preferences.append(
            ViewRespondersKey.self,
            node: responder.identifier
        )
        return outputs
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError(
                "TextFieldInputModifier._makeViewList called outside AG context"
            )
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

private struct TextFieldResponderFilter: StatefulRule, RemovableAttribute {
    typealias Value = [ViewResponder]

    var modifier: Attribute<TextFieldInputModifier>
    var environment: Attribute<EnvironmentValues>
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var transform: Attribute<ViewTransform>
    var children: Attribute<[ViewResponder]>
    var responder: TextFieldResponder?

    mutating func updateValue() {
        let isInitial = !context.hasValue
        if responder == nil {
            responder = TextFieldResponder()
        }
        guard let responder else {
            fatalError("TextFieldResponderFilter failed to create responder")
        }

        let modifier = modifier.value
        let environment = environment.value
        responder.text = modifier.text
        responder.selection = modifier.selection
        responder.fieldState = modifier.fieldState
        responder.inputState = modifier.inputState
        responder.isEnabled = environment.isEnabled
        responder.isTextFieldCursorEnabled = environment.isTextFieldCursorEnabled
        responder.synchronizeSelection(modifier.selectionValue)
        responder.helper.update(
            data: (value: TrivialContentResponder(), changed: false),
            size: (
                value: size.value,
                changed: _AGGraph.currentStatefulInputChanged(size.identifier)
            ),
            position: (
                value: position.value,
                changed: _AGGraph.currentStatefulInputChanged(position.identifier)
            ),
            transform: (
                value: transform.value,
                changed: _AGGraph.currentStatefulInputChanged(transform.identifier)
            ),
            parent: responder
        )
        responder.updateChildren((
            value: children.value,
            changed: isInitial
                || _AGGraph.currentStatefulInputChanged(children.identifier)
        ))

        if !environment.isEnabled {
            responder.resetHoverEvents()
            if let host = responder.host as? WindowController {
                host.resignTextInputFocus(responder)
            }
        }
        _AGGraph.setStatefulOutput([responder])
    }

    static func willRemove(attribute: AGAttribute) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TextFieldResponderFilter.willRemove called outside AG context"
            )
        }
        var responder: TextFieldResponder?
        graph.mutateStatefulRule(attribute, as: Self.self) { rule in
            responder = rule.responder
        }
        guard let responder else { return }
        responder.resetHoverEvents()
        guard let host = responder.host as? WindowController else { return }
        host.resignTextInputFocus(responder)
    }
}

final class TextFieldResponder: MultiViewResponder,
    ExclusiveResponderEventConsumer, TextInputResponder,
    TextEditingCommandResponder, HoverEventObserver {
    var helper = ContentResponderHelper<TrivialContentResponder>()
    var text: Binding<String>?
    var selection: Binding<TextSelection?>? {
        didSet {
            let location = selection.map {
                ObjectIdentifier($0.location)
            }
            if location != selectionLocation {
                selectionLocation = location
                selectionBindingValue = nil
                hasSelectionBindingValue = false
            }
        }
    }
    var fieldState: Binding<TextFieldState>?
    var inputState: Binding<TextFieldInputState>?
    var isEnabled = true
    var isTextFieldCursorEnabled = true {
        didSet {
            guard isTextFieldCursorEnabled != oldValue else { return }
            updateTextFieldCursor()
        }
    }
    private var selectionLocation: ObjectIdentifier?
    private var selectionBindingValue: TextSelection?
    private var hasSelectionBindingValue = false
    private var consumedKeyStreams: Set<KeyStream> = []
    private var cursorHoverEventIDs: Set<EventID> = []
    private var hasRequestedIBeamCursor = false

    private struct KeyStream: Hashable {
        var deviceID: Int
        var key: VirtualKey
    }

    override var features: Features {
        [.platformViews, .gestures]
    }

    override func hitTestPolicy(
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.HitTestPolicy {
        isEnabled || options.contains(.allowDisabledViews)
            ? .include
            : .exclude
    }

    override func containsGlobalPoints(
        _ points: [CGPoint],
        cacheKey: UInt32?,
        options: ViewResponder.ContainsPointsOptions
    ) -> ViewResponder.ContainsPointsResult {
        guard hitTestPolicy(options: options) != .exclude else {
            return .stop
        }
        return helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        isEnabled && (eventType == MouseEvent.self || eventType == TouchEvent.self)
    }

    func exclusivelyConsumes(_ event: any EventType) -> Bool {
        if let event = event as? MouseEvent {
            return event.button == .primary
        }
        return event is TouchEvent
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at _: Time
    ) -> GesturePhase<Void> {
        var result: GesturePhase<Void> = .possible(nil)
        for event in events.values {
            let phase: EventPhase?
            if let event = event as? MouseEvent,
               event.button == .primary {
                phase = event.phase
            } else if let event = event as? TouchEvent {
                phase = event.phase
            } else {
                phase = nil
            }
            guard let phase else { continue }
            switch phase {
            case .began:
                (host as? WindowController)?.focusTextInputResponder(self)
                result = .active(())
            case .active:
                result = .active(())
            case .ended:
                result = .ended(())
            case .failed:
                result = .failed
            }
        }
        return result
    }

    func resetEventSession() {}

    func containsTextInputPoint(_ point: CGPoint) -> Bool {
        helper.containsGlobalPoints(
            [point],
            cacheKey: nil,
            options: .platformDefault,
            children: children
        ).mask[0]
    }

    func updateHoverEvent(
        id: EventID,
        at _: CGPoint,
        time _: Time
    ) -> Bool {
        guard isEnabled else { return false }
        cursorHoverEventIDs.insert(id)
        updateTextFieldCursor()
        return isTextFieldCursorEnabled
    }

    func endHoverEvent(id: EventID, time _: Time) -> Bool {
        guard cursorHoverEventIDs.remove(id) != nil else { return false }
        updateTextFieldCursor()
        return isTextFieldCursorEnabled
    }

    func resetHoverEvents() {
        cursorHoverEventIDs.removeAll(keepingCapacity: true)
        updateTextFieldCursor()
    }

    private func updateTextFieldCursor() {
        let shouldRequestIBeam = isEnabled &&
            isTextFieldCursorEnabled &&
            !cursorHoverEventIDs.isEmpty
        guard shouldRequestIBeam != hasRequestedIBeamCursor else { return }
        hasRequestedIBeamCursor = shouldRequestIBeam
        (host as? WindowController)?.requestTextInputCursor(
            shouldRequestIBeam ? .iBeam : nil
        )
    }

    func textInputFocusDidChange(_ focused: Bool) {
        guard let text, let fieldState, let inputState else { return }
        Update.enqueueAction {
            var editing = inputState.wrappedValue
            editing.setFocused(focused, committedText: text.wrappedValue)
            if focused,
               let selection = self.selection?.wrappedValue {
                _ = editing.setSelection(
                    selection,
                    committedText: text.wrappedValue
                )
            } else if !focused {
                editing.collapseSelection(
                    to: 0,
                    affinity: .downstream,
                    committedText: text.wrappedValue
                )
            }
            inputState.wrappedValue = editing
            self.publishSelection(editing, committedText: text.wrappedValue)

            var state = fieldState.wrappedValue
            guard state.isEditing != focused else { return }
            state.isEditing = focused
            fieldState.wrappedValue = state
            state.deprecatedActions?.editingChanged(focused)
        }
    }

    func handleTextInputEvent(_ event: VVD.KeyboardEvent) -> Bool {
        guard isEnabled,
              let text,
              let fieldState,
              let inputState else {
            return false
        }

        switch event.type {
        case .textComposition:
            Update.enqueueAction {
                var editing = inputState.wrappedValue
                editing.replaceComposition(
                    with: event.text,
                    committedText: text.wrappedValue
                )
                inputState.wrappedValue = editing
                self.publishSelection(
                    editing,
                    committedText: text.wrappedValue
                )
            }
            return true

        case .textInput:
            Update.enqueueAction {
                var committedText = text.wrappedValue
                var editing = inputState.wrappedValue
                let result = editing.handleTextInput(
                    event.text,
                    committedText: &committedText
                )
                inputState.wrappedValue = editing
                if result == .changed {
                    text.wrappedValue = committedText
                    var state = fieldState.wrappedValue
                    state.displayText = committedText
                    fieldState.wrappedValue = state
                } else if result == .submit {
                    fieldState.wrappedValue.deprecatedActions?.commit()
                }
                self.publishSelection(
                    editing,
                    committedText: committedText
                )
            }
            return true

        case .keyDown:
            var previewText = text.wrappedValue
            var previewState = inputState.wrappedValue
            guard previewState.handleKeyDown(
                event.key,
                committedText: &previewText
            ) else {
                return false
            }
            consumedKeyStreams.insert(KeyStream(
                deviceID: event.deviceID,
                key: event.key
            ))
            Update.enqueueAction {
                var committedText = text.wrappedValue
                var editing = inputState.wrappedValue
                _ = editing.handleKeyDown(
                    event.key,
                    committedText: &committedText
                )
                inputState.wrappedValue = editing
                if text.wrappedValue != committedText {
                    text.wrappedValue = committedText
                    var state = fieldState.wrappedValue
                    state.displayText = committedText
                    fieldState.wrappedValue = state
                }
                self.publishSelection(
                    editing,
                    committedText: committedText
                )
            }
            return true

        case .keyUp:
            return consumedKeyStreams.remove(KeyStream(
                deviceID: event.deviceID,
                key: event.key
            )) != nil
        }
    }

    func canPerformTextEditingCommand(_ command: TextEditingCommand) -> Bool {
        guard isEnabled,
              let text,
              let inputState,
              inputState.wrappedValue.isFocused else {
            return false
        }
        switch command {
        case .jumpToSelection:
            return true
        case .makeUpperCase, .makeLowerCase, .capitalize:
            return inputState.wrappedValue.transformationRange(
                in: text.wrappedValue
            ) != nil
        default:
            return false
        }
    }

    func performTextEditingCommand(_ command: TextEditingCommand) {
        guard canPerformTextEditingCommand(command),
              let text,
              let fieldState,
              let inputState else {
            return
        }
        switch command {
        case .jumpToSelection:
            // The single-line renderer always keeps the complete value in its
            // current bounds, so there is no additional viewport transition.
            return

        case .makeUpperCase, .makeLowerCase, .capitalize:
            Update.enqueueAction {
                var committedText = text.wrappedValue
                var editing = inputState.wrappedValue
                let transformed = editing.transformSelection(
                    in: &committedText
                ) { value in
                    switch command {
                    case .makeUpperCase:
                        value.uppercased()
                    case .makeLowerCase:
                        value.lowercased()
                    case .capitalize:
                        value.capitalized
                    default:
                        value
                    }
                }
                guard transformed else { return }
                inputState.wrappedValue = editing
                text.wrappedValue = committedText
                var state = fieldState.wrappedValue
                state.displayText = committedText
                fieldState.wrappedValue = state
                self.publishSelection(
                    editing,
                    committedText: committedText
                )
            }

        default:
            return
        }
    }

    func synchronizeSelection(_ selectionValue: TextSelection?) {
        guard !hasSelectionBindingValue
                || selectionBindingValue != selectionValue else {
            return
        }
        selectionBindingValue = selectionValue
        hasSelectionBindingValue = true
        guard let selectionValue, let text,
              let inputState else {
            return
        }
        Update.enqueueAction {
            var editing = inputState.wrappedValue
            guard editing.setSelection(
                selectionValue,
                committedText: text.wrappedValue
            ) else {
                return
            }
            inputState.wrappedValue = editing
        }
    }

    private func publishSelection(
        _ inputState: TextFieldInputState,
        committedText: String
    ) {
        guard let selection else { return }
        let value = inputState.textSelection(
            in: committedText
        )
        selectionBindingValue = value
        hasSelectionBindingValue = true
        selection.wrappedValue = value
    }
}
