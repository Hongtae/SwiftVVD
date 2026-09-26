//
//  File: LabeledContentStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private struct LabelsVisibilityKey: EnvironmentKey {
    static let defaultValue: Visibility = .automatic
}

private struct LabeledContentIsSelectedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var labelsVisibility: Visibility {
        get { self[LabelsVisibilityKey.self] }
        set { self[LabelsVisibilityKey.self] = newValue }
    }

    var labeledContentIsSelected: Bool {
        get { self[LabeledContentIsSelectedKey.self] }
        set { self[LabeledContentIsSelectedKey.self] = newValue }
    }
}

public protocol LabeledContentStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Self.Configuration) -> Self.Body

    typealias Configuration = LabeledContentStyleConfiguration
}

public struct LabeledContentStyleConfiguration {
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }

    public struct Content: View, ViewAlias {
        public typealias Body = Never
    }

    public let label: Label
    public let content: Content
    let accessibilityPresentation: AccessibilityLabelPresentation?

    init(
        accessibilityPresentation: AccessibilityLabelPresentation? = nil
    ) {
        label = Label()
        content = Content()
        self.accessibilityPresentation = accessibilityPresentation
    }
}

extension LabeledContentStyleConfiguration.Label: PrimitiveView {}
extension LabeledContentStyleConfiguration.Content: PrimitiveView {}

struct _LabeledContentStyleModifier<Style>: StyleModifier
where Style: LabeledContentStyle {
    typealias Body = Never
    typealias StyleConfiguration = LabeledContentStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(
        configuration: LabeledContentStyleConfiguration
    ) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

struct ResolvedLabeledContent: StyleableView {
    var configuration: LabeledContentStyleConfiguration

    var body: some View {
        LabeledContent(configuration)
    }

    typealias DefaultStyleModifier = _LabeledContentStyleModifier<
        AutomaticLabeledContentStyle
    >

    static var defaultStyleModifier: DefaultStyleModifier {
        _LabeledContentStyleModifier(
            style: AutomaticLabeledContentStyle()
        )
    }

    struct _Body: View {
        var configuration: LabeledContentStyleConfiguration
        @Namespace private var namespace
        var spacing: CGFloat?

        init(
            configuration: LabeledContentStyleConfiguration,
            spacing: CGFloat? = 8
        ) {
            self.configuration = configuration
            self.spacing = spacing
        }

        var body: some View {
            HStack(spacing: spacing) {
                configuration.label
                Spacer(minLength: spacing)
                configuration.content
            }
        }
    }
}

struct FalseViewInputBoolFlagModifier<Flag>:
    PrimitiveViewModifier, _GraphInputsModifier
where Flag: ViewInputBoolFlag {
    typealias Body = Never

    static func _makeInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _GraphInputs
    ) {
        inputs[Flag.Input.self] = false
    }
}

struct DesktopInterfaceProfilePredicate: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool {
        inputs.cachedEnvironment.value.environment.value.interfaceProfile
            == .desktop
    }
}

struct MenuLabeledContentUsesSubtitle: ViewInputPredicate {
    static func evaluate(inputs: _GraphInputs) -> Bool { true }
}

public struct AutomaticLabeledContentStyle: LabeledContentStyle {
    @Environment(\.labelsVisibility)
    private var labelsVisibility

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        LabeledContent(
            label: StaticIf<
                LabelVisibilityConfigured,
                LabeledContentStyleConfiguration.Label?,
                LabeledContentStyleConfiguration.Label
            >(
                trueBody: labelsVisibility == .hidden
                    ? nil
                    : configuration.label,
                falseBody: configuration.label
            ),
            content: configuration.content
                .modifier(
                    _LabeledContentStyleModifier(style: self)
                )
                .modifier(
                    FalseViewInputBoolFlagModifier<
                        LabelVisibilityConfigured
                    >()
                ),
            accessibilityPresentation: configuration.accessibilityPresentation
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<AnyListStyleContext>,
                _LabeledContentStyleModifier<
                    LeadingTrailingLabeledContentStyle
                >,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: LeadingTrailingLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<FormBoxStyleContext>,
                _LabeledContentStyleModifier<FormBoxLabeledContentStyle>,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: FormBoxLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<
                    GroupedFormValueStyleContext
                >,
                _LabeledContentStyleModifier<FormBoxLabeledContentStyle>,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: FormBoxLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<GroupedFormStyleContext>,
                _LabeledContentStyleModifier<
                    GroupedFormLabeledContentStyle
                >,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: GroupedFormLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<ColumnsFormStyleContext>,
                _LabeledContentStyleModifier<ColumnarLabeledContentStyle>,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: ColumnarLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<
                    GroupedFormTextFieldStyleContext
                >,
                _LabeledContentStyleModifier<
                    GroupedFormTextFieldLabeledContentStyle
                >,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: GroupedFormTextFieldLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<RadioGroupStyleContext>,
                _LabeledContentStyleModifier<ColumnarLabeledContentStyle>,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: ColumnarLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<ToolbarStyleContext>,
                _LabeledContentStyleModifier<ToolbarLabeledContentStyle>,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: ToolbarLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                StyleContextAcceptsPredicate<
                    AccessibilityRepresentableStyleContext
                >,
                _LabeledContentStyleModifier<
                    AccessibilityLabeledContentStyle
                >,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: AccessibilityLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                DesktopInterfaceProfilePredicate,
                _LabeledContentStyleModifier<HStackLabeledContentStyle>,
                EmptyModifier
            >(
                trueBody: _LabeledContentStyleModifier(
                    style: HStackLabeledContentStyle()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            StaticIf<
                MenuLabeledContentUsesSubtitle,
                StaticIf<
                    StyleContextAcceptsPredicate<MenuStyleContext>,
                    _LabeledContentStyleModifier<
                        MenuLabeledContentStyle
                    >,
                    EmptyModifier
                >,
                EmptyModifier
            >(
                trueBody: StaticIf(
                    trueBody: _LabeledContentStyleModifier(
                        style: MenuLabeledContentStyle()
                    ),
                    falseBody: EmptyModifier()
                ),
                falseBody: EmptyModifier()
            )
        )
        .modifier(
            _LabeledContentStyleModifier(
                style: LeadingTrailingLabeledContentStyle()
            )
        )
    }
}

struct LeadingTrailingLabeledContentStyle: LabeledContentStyle {
    @Environment(\.labeledContentIsSelected)
    private var isSelected
    var spacing: CGFloat? = 8

    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(
            configuration: configuration,
            spacing: spacing
        )
    }
}

struct FormBoxLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

struct GroupedFormLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

struct ColumnarLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

struct GroupedFormTextFieldLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

struct ToolbarLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

struct AccessibilityLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

struct HStackLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

struct MenuLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        ResolvedLabeledContent._Body(configuration: configuration)
    }
}

extension LabeledContentStyle where Self == AutomaticLabeledContentStyle {
    public static var automatic: AutomaticLabeledContentStyle {
        AutomaticLabeledContentStyle()
    }
}

extension View {
    public func labeledContentStyle<S>(_ style: S) -> some View
    where S: LabeledContentStyle {
        modifier(_LabeledContentStyleModifier(style: style))
    }

    public func labelsHidden() -> some View {
        environment(\.labelsVisibility, .hidden)
            .input(LabelVisibilityConfigured.self)
    }
}
