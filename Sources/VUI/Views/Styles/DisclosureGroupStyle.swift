//
//  File: DisclosureGroupStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol DisclosureGroupStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = DisclosureGroupStyleConfiguration
}

public struct DisclosureGroupStyleConfiguration {
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }

    public struct Content: View, ViewAlias {
        public typealias Body = Never
    }

    public let label: Label
    public let content: Content
    @Binding public var isExpanded: Bool

    init(isExpanded: Binding<Bool>) {
        label = Label()
        content = Content()
        _isExpanded = isExpanded
    }
}

extension DisclosureGroupStyleConfiguration.Label: PrimitiveView {}
extension DisclosureGroupStyleConfiguration.Content: PrimitiveView {}

struct DisclosureGroupStyleModifier<Style>: StyleModifier
    where Style: DisclosureGroupStyle
{
    typealias Body = Never
    typealias StyleConfiguration = DisclosureGroupStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(
        configuration: DisclosureGroupStyleConfiguration
    ) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

private struct DisclosureGroupStyleBody: View {
    let configuration: DisclosureGroupStyleConfiguration

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                configuration.isExpanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .frame(width: 12, height: 12)
                        .rotationEffect(
                            .degrees(configuration.isExpanded ? 90 : 0)
                        )
                    configuration.label
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if configuration.isExpanded {
                configuration.content
                    .padding(.leading, 18)
            }
        }
    }
}

struct LeadingAlignedDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        DisclosureGroupStyleBody(configuration: configuration)
    }
}

struct ListDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        DisclosureGroupStyleBody(configuration: configuration)
    }
}

struct AccessibilityDisclosureGroupStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        DisclosureGroupStyleBody(configuration: configuration)
    }
}

public struct AutomaticDisclosureGroupStyle: DisclosureGroupStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        DisclosureGroup(configuration)
            .modifier(
                StaticIf<
                    StyleContextAcceptsPredicate<(
                        PlainListStyleContext,
                        SidebarListStyleContext,
                        InsetListStyleContext,
                        BorderedListStyleContext,
                        SystemPreferencesSidebarListStyleContext,
                        TableStyleContext
                    )>,
                    DisclosureGroupStyleModifier<ListDisclosureGroupStyle>,
                    EmptyModifier
                >(
                    trueBody: DisclosureGroupStyleModifier(
                        style: ListDisclosureGroupStyle()
                    ),
                    falseBody: EmptyModifier()
                )
            )
            .modifier(
                StaticIf<
                    StyleContextAcceptsPredicate<
                        AccessibilityRepresentableStyleContext
                    >,
                    DisclosureGroupStyleModifier<
                        AccessibilityDisclosureGroupStyle
                    >,
                    EmptyModifier
                >(
                    trueBody: DisclosureGroupStyleModifier(
                        style: AccessibilityDisclosureGroupStyle()
                    ),
                    falseBody: EmptyModifier()
                )
            )
            .modifier(
                DisclosureGroupStyleModifier(
                    style: LeadingAlignedDisclosureGroupStyle()
                )
            )
    }
}

extension DisclosureGroupStyle where Self == AutomaticDisclosureGroupStyle {
    public static var automatic: AutomaticDisclosureGroupStyle {
        AutomaticDisclosureGroupStyle()
    }
}

extension View {
    public func disclosureGroupStyle<S>(_ style: S) -> some View
        where S: DisclosureGroupStyle
    {
        modifier(DisclosureGroupStyleModifier(style: style))
    }
}

struct IsExpandedTraitKey: _ViewTraitKey {
    static var defaultValue: Bool { false }
}

struct ResolvedDisclosureGroupStyle: StyleableView {
    typealias Configuration = DisclosureGroupStyleConfiguration
    var configuration: DisclosureGroupStyleConfiguration

    var body: some View {
        DisclosureGroup(configuration)
            ._trait(IsExpandedTraitKey.self, configuration.isExpanded)
    }

    typealias DefaultStyleModifier = DisclosureGroupStyleModifier<
        AutomaticDisclosureGroupStyle
    >

    static var defaultStyleModifier: DefaultStyleModifier {
        DisclosureGroupStyleModifier(style: AutomaticDisclosureGroupStyle())
    }
}
