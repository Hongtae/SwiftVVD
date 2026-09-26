//
//  File: FormStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol FormStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Self.Configuration) -> Self.Body

    typealias Configuration = FormStyleConfiguration
}

public struct FormStyleConfiguration {
    public struct Content: View, ViewAlias, FormFooterBearing {
        public typealias Body = Never
    }

    struct Footer: View, ViewAlias {
        typealias Body = Never
    }

    public let content: Content
    let footer: Footer

    init() {
        content = Content()
        footer = Footer()
    }
}

extension FormStyleConfiguration.Content: PrimitiveView {}
extension FormStyleConfiguration.Footer: PrimitiveView {}

struct FormStyleModifier<Style>: StyleModifier where Style: FormStyle {
    typealias Body = Never
    typealias StyleConfiguration = FormStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(configuration: FormStyleConfiguration) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

struct FormStyleWritingModifier<Style>: StyleModifier where Style: FormStyle {
    typealias Body = Never
    typealias StyleConfiguration = FormStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(configuration: FormStyleConfiguration) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

struct ResolvedFormStyle: StyleableView {
    var configuration: FormStyleConfiguration

    typealias DefaultStyleModifier = FormStyleModifier<AutomaticFormStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        FormStyleModifier(style: AutomaticFormStyle())
    }
}

public struct AutomaticFormStyle: FormStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Form(configuration)
            .modifier(
                StaticIf<
                    StyleContextAcceptsPredicate<InspectorStyleContext>,
                    FormStyleWritingModifier<GroupedFormStyle>,
                    EmptyModifier
                >(
                    trueBody: FormStyleWritingModifier(
                        style: GroupedFormStyle()
                    ),
                    falseBody: EmptyModifier()
                )
            )
            .modifier(
                FormStyleWritingModifier(style: ColumnsFormStyle())
            )
    }
}

public struct ColumnsFormStyle: FormStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        FormVStack {
            configuration.content
                .modifier(StyleContextWriter<ColumnsFormStyleContext>())
                .modifier(
                    TextFieldLabelDisplayModeModifier(
                        mode: FormTextFieldLabelDisplayMode()
                    )
                )
        }
    }
}

public struct GroupedFormStyle: FormStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        UniversalGroupedForm(
            content: configuration.content,
            footer: configuration.footer
        )
        .input(MacIdiomGroupedFormInput.self)
    }
}

extension FormStyle where Self == AutomaticFormStyle {
    public static var automatic: AutomaticFormStyle {
        AutomaticFormStyle()
    }
}

extension FormStyle where Self == ColumnsFormStyle {
    public static var columns: ColumnsFormStyle {
        ColumnsFormStyle()
    }
}

extension FormStyle where Self == GroupedFormStyle {
    public static var grouped: GroupedFormStyle {
        GroupedFormStyle()
    }
}

extension View {
    public func formStyle<S>(_ style: S) -> some View where S: FormStyle {
        modifier(FormStyleModifier(style: style))
    }
}

struct _FormVStackLayout {
    var alignment: HorizontalAlignment
    var spacing: CGFloat?

    typealias Body = Never
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = _StackLayoutCache

    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat? = nil
    ) {
        self.alignment = alignment
        self.spacing = spacing
    }
}

extension _FormVStackLayout: _VariadicView_UnaryViewRoot {}
extension _FormVStackLayout: _VariadicView_ViewRoot {}
extension _FormVStackLayout: _VariadicView_ImplicitRoot {
    static var implicitRoot: Self { Self() }
}
extension _FormVStackLayout: Sendable {}

extension _FormVStackLayout: HVStack {
    typealias MinorAxisAlignment = HorizontalAlignment

    static var majorAxis: Axis { .vertical }
}

struct FormVStack<Content>: View where Content: View {
    var _tree: _VariadicView.Tree<_FormVStackLayout, Content>

    init(
        alignment: HorizontalAlignment = .leading,
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> Content
    ) {
        _tree = .init(
            root: _FormVStackLayout(
                alignment: alignment,
                spacing: spacing
            ),
            content: content()
        )
    }

    static func _makeView(
        view: _GraphValue<Self>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        _VariadicView.Tree<_FormVStackLayout, Content>._makeView(
            view: view[\._tree],
            inputs: inputs
        )
    }

    typealias Body = Never
}

extension FormVStack: PrimitiveView, UnaryView {}

struct UniversalGroupedForm<Content, Footer>: View
where Content: View, Footer: View {
    var content: Content
    var footer: Footer

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                content
                footer
            }
            .padding()
            .modifier(StyleContextWriter<GroupedFormStyleContext>())
        }
    }
}

struct MacIdiomGroupedFormInput: ViewInputBoolFlag {}

struct FormTextFieldLabelDisplayMode {}

struct TextFieldLabelDisplayModeModifier<Mode>: ViewModifier {
    var mode: Mode

    func body(content: Content) -> some View {
        content
    }
}
