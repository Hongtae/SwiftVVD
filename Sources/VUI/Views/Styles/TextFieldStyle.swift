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
        TextFieldControl(
            configuration: configuration,
            drawsBorder: true,
            horizontalInset: 6
        )
    }
}

public struct PlainTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(
        configuration: TextField<_TextFieldStyleLabel>
    ) -> some View {
        TextFieldControl(
            configuration: configuration,
            drawsBorder: false,
            horizontalInset: 0
        )
    }
}

public struct RoundedBorderTextFieldStyle: TextFieldStyle {
    public init() {}

    public func _body(
        configuration: TextField<_TextFieldStyleLabel>
    ) -> some View {
        TextFieldControl(
            configuration: configuration,
            drawsBorder: true,
            horizontalInset: 4
        )
    }
}

extension TextFieldStyle where Self == DefaultTextFieldStyle {
    public static var automatic: DefaultTextFieldStyle { DefaultTextFieldStyle() }
}

extension TextFieldStyle where Self == PlainTextFieldStyle {
    public static var plain: PlainTextFieldStyle { PlainTextFieldStyle() }
}

extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
    public static var roundedBorder: RoundedBorderTextFieldStyle {
        RoundedBorderTextFieldStyle()
    }
}

extension View {
    public func textFieldStyle<S>(_ style: S) -> some View
    where S: TextFieldStyle {
        modifier(TextFieldStyleModifier(style: style))
    }
}

private struct TextFieldViewportLayout: Layout {
    var contentOffset: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let contentSize = subview.sizeThatFits(.unspecified)
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = max(proposedWidth, 0)
        } else {
            width = contentSize.width
        }
        return CGSize(width: width, height: contentSize.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let subview = subviews.first else { return }
        let contentSize = subview.sizeThatFits(.unspecified)
        let maximumOffset = max(contentSize.width - bounds.width, 0)
        let resolvedOffset = min(max(contentOffset, 0), maximumOffset)
        subview.place(
            at: CGPoint(
                x: bounds.minX - resolvedOffset,
                y: bounds.minY + (bounds.height - contentSize.height) * 0.5
            ),
            anchor: .topLeading,
            proposal: ProposedViewSize(contentSize)
        )
    }
}

private final class TextFieldViewportClipContainer: PlatformGroupFactory {
    var clipBounds = CGRect.zero

    var platformGroupContainer: AnyObject { self }

    func renderPlatformGroup(
        contents: DisplayList,
        in context: GraphicsContext,
        render: (DisplayList, GraphicsContext) -> Void
    ) {
        var context = context
        context.clip(to: Path(clipBounds))
        render(contents, context)
    }
}

private struct TextFieldViewportClipDisplayList: StatefulRule {
    typealias Value = DisplayList

    var identity: _DisplayList_Identity
    var position: Attribute<CGPoint>
    var size: Attribute<ViewSize>
    var containerPosition: Attribute<CGPoint>
    var content: OptionalAttribute<DisplayList>
    var options: DisplayList.Options
    var container: TextFieldViewportClipContainer?

    mutating func updateValue() {
        if container == nil {
            container = TextFieldViewportClipContainer()
        }
        guard let container else {
            fatalError("TextField viewport failed to create its clip owner")
        }

        let frame = CGRect(
            origin: CGPoint(
                x: position.value.x - containerPosition.value.x,
                y: position.value.y - containerPosition.value.y
            ),
            size: size.value.value
        )
        // The effect frame places this local platform group in its parent.
        // Both its contents and clip must therefore remain group-relative.
        container.clipBounds = CGRect(origin: .zero, size: frame.size)

        let contents = content.value ?? DisplayList()
        var item = DisplayList.Item(
            effect: .platformGroup(container),
            contents: contents,
            frame: frame,
            identity: identity,
            version: DisplayList.Version(forUpdate: ())
        )
        item.canonicalize(options: options)

        var result = DisplayList()
        result.items.append(item)
        result.recordInterpolationBounds(frame)
        result.numericValue = contents.numericValue
        _AGGraph.setStatefulOutput(result)
    }
}

private struct TextFieldViewportClipModifier: ViewModifier, MultiViewModifier {
    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError(
                "TextFieldViewportClipModifier._makeView called outside AG context"
            )
        }
        let cachedEnvironmentAttribute = inputs.base.cachedEnvironment
        var cachedEnvironment = cachedEnvironmentAttribute.value
        let position = cachedEnvironment.animatedPosition(for: inputs)
        let size = cachedEnvironment.animatedSize(for: inputs)
        cachedEnvironmentAttribute.value = cachedEnvironment

        var childInputs = inputs
        childInputs.containerPosition = position
        var outputs = body(_Graph(), childInputs)
        guard let content = outputs.preferences.reducedValue(
            for: DisplayList.Key.self,
            in: graph
        ) else {
            return outputs
        }

        var identityInputs = inputs
        let displayList = graph.makeStatefulRule(
            TextFieldViewportClipDisplayList(
                identity: identityInputs.pushIdentity(),
                position: position,
                size: size,
                containerPosition: inputs.containerPosition,
                content: OptionalAttribute(content),
                options: inputs[DisplayList.Options.self],
                container: nil
            )
        )
        outputs.preferences.setValue(
            displayList.identifier,
            for: DisplayList.Key.self
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
                "TextFieldViewportClipModifier._makeViewList called outside AG context"
            )
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

private struct TextFieldControl: View {
    var configuration: TextField<_TextFieldStyleLabel>
    var drawsBorder: Bool
    var horizontalInset: CGFloat
    @State private var inputState = TextFieldInputState()
    @State private var viewportState = TextFieldViewportState()
    @FocusState private var isFocused: Bool
    @Environment(\.textFieldCompositionCaretStyle)
    private var compositionCaretStyle

    var body: some View {
        styledContent.onChange(of: configuration._text.wrappedValue) {
            _, projectedValue in
            synchronizeFormattedText(projectedValue)
        }
    }

    private var resolvedCompositionCaretStyle: TextFieldCompositionCaretStyle {
        configuration.isSecure ? .insertionPoint : compositionCaretStyle
    }

    @ViewBuilder
    private var styledContent: some View {
        if drawsBorder {
            editorContent
                .padding(.horizontal, horizontalInset)
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
        let segments = inputState.displaySegments(
            in: text,
            isSecure: configuration.isSecure
        )
        let composition = TextFieldInputState.displayText(
            inputState.composition,
            isSecure: configuration.isSecure
        )
        let defaultCaretWidth: CGFloat = 1
        TextFieldViewportLayout(
            contentOffset: viewportState.contentOffset
        ) {
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
                    } else if composition.isEmpty == false {
                        TextFieldCaret(
                            compositionText: composition,
                            defaultWidth: defaultCaretWidth,
                            compositionStyle: resolvedCompositionCaretStyle
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
            .fixedSize(horizontal: true, vertical: false)
            .frame(minHeight: 18)
        }
        .modifier(TextFieldViewportClipModifier())
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
            isSecure: configuration.isSecure,
            selection: configuration.selection,
            selectionValue: configuration.selection?.wrappedValue,
            fieldState: configuration.$state,
            inputState: $inputState,
            viewportState: $viewportState,
            viewportValue: viewportState,
            contentLeadingInset: horizontalInset
        )
    }
}
