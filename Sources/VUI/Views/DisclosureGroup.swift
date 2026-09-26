//
//  File: DisclosureGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct DisclosureGroupConfiguration<Label, Content>
    where Label: View, Content: View
{
    let content: Content
    let isExpanded: Binding<Bool>
    let label: Label
}

struct AccessibilityApplyDisclosureIndicator: ViewModifier {
    let isExpanded: Binding<Bool>

    func body(content: Content) -> some View {
        content
    }
}

struct HideNavigationLinkDisclosureIndicator: ViewInputBoolFlag {}

public struct DisclosureGroup<Label, Content>: View
    where Label: View, Content: View
{
    let label: Label
    let content: Content
    @StateOrBinding var isExpanded: Bool

    public init(
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.content = content()
        _isExpanded = StateOrBinding(wrappedValue: false)
    }

    public init(
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.label = label()
        self.content = content()
        _isExpanded = StateOrBinding(isExpanded)
    }

    init(_ configuration: DisclosureGroupConfiguration<Label, Content>) {
        label = configuration.label
        content = configuration.content
        _isExpanded = StateOrBinding(configuration.isExpanded)
    }

    public var body: some View {
        ResolvedDisclosureGroupStyle(
            configuration: DisclosureGroupStyleConfiguration(
                isExpanded: $isExpanded
            )
        )
        .modifier(
            StaticSourceWriter<
                DisclosureGroupStyleConfiguration.Label,
                Label
            >(source: label)
        )
        .modifier(
            StaticSourceWriter<
                DisclosureGroupStyleConfiguration.Content,
                Content
            >(source: content)
        )
        .modifier(
            AccessibilityApplyDisclosureIndicator(
                isExpanded: $isExpanded
            )
        )
        .input(HideNavigationLinkDisclosureIndicator.self)
    }
}

extension DisclosureGroup
    where Label == DisclosureGroupStyleConfiguration.Label,
          Content == DisclosureGroupStyleConfiguration.Content
{
    init(_ configuration: DisclosureGroupStyleConfiguration) {
        label = configuration.label
        content = configuration.content
        _isExpanded = StateOrBinding(configuration.$isExpanded)
    }
}

extension DisclosureGroup where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(content: content) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(content: content) {
            Text(titleResource)
        }
    }

    public init(
        _ titleKey: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(isExpanded: isExpanded, content: content) {
            Text(titleKey)
        }
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(isExpanded: isExpanded, content: content) {
            Text(titleResource)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ label: S,
        @ViewBuilder content: @escaping () -> Content
    ) where S: StringProtocol {
        self.init(content: content) {
            Text(label)
        }
    }

    @_disfavoredOverload
    public init<S>(
        _ label: S,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) where S: StringProtocol {
        self.init(isExpanded: isExpanded, content: content) {
            Text(label)
        }
    }
}
