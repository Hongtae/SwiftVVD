//
//  File: LabeledContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum AccessibilityLabelPresentation {
    case label
}

public struct LabeledContent<Label, Content>
where Label: View, Content: View {
    let label: Label
    let content: Content
    let accessibilityPresentation: AccessibilityLabelPresentation?

    init(
        label: Label,
        content: Content,
        accessibilityPresentation: AccessibilityLabelPresentation? = nil
    ) {
        self.label = label
        self.content = content
        self.accessibilityPresentation = accessibilityPresentation
    }
}

extension LabeledContent: View {
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(label: label(), content: content())
    }

    public var body: some View {
        ResolvedLabeledContent(
            configuration: LabeledContentStyleConfiguration(
                accessibilityPresentation: accessibilityPresentation
            )
        )
        .modifier(
            StaticSourceWriter<
                LabeledContentStyleConfiguration.Label,
                Label
            >(source: label)
        )
        .modifier(
            StaticSourceWriter<
                LabeledContentStyleConfiguration.Content,
                Content
            >(source: content)
        )
    }
}

extension LabeledContent where Label == Text, Content: View {
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label: Text(titleKey), content: content())
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(label: Text(title), content: content())
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label: Text(titleResource), content: content())
    }
}

extension LabeledContent where Label == Text, Content == Text {
    public init<S>(
        _ titleKey: LocalizedStringKey,
        value: S
    ) where S: StringProtocol {
        self.init(label: Text(titleKey), content: Text(value))
    }

    @_disfavoredOverload
    public init<S1, S2>(
        _ title: S1,
        value: S2
    ) where S1: StringProtocol, S2: StringProtocol {
        self.init(label: Text(title), content: Text(value))
    }

    @_disfavoredOverload
    public init<S>(
        _ titleResource: LocalizedStringResource,
        value: S
    ) where S: StringProtocol {
        self.init(label: Text(titleResource), content: Text(value))
    }

    public init<F>(
        _ titleKey: LocalizedStringKey,
        value: F.FormatInput,
        format: F
    ) where F: FormatStyle, F.FormatInput: Equatable,
            F.FormatOutput == String {
        self.init(
            label: Text(titleKey),
            content: Text(value, format: format)
        )
    }

    @_disfavoredOverload
    public init<S, F>(
        _ title: S,
        value: F.FormatInput,
        format: F
    ) where S: StringProtocol, F: FormatStyle,
            F.FormatInput: Equatable, F.FormatOutput == String {
        self.init(
            label: Text(title),
            content: Text(value, format: format)
        )
    }

    @_disfavoredOverload
    public init<F>(
        _ titleResource: LocalizedStringResource,
        value: F.FormatInput,
        format: F
    ) where F: FormatStyle, F.FormatInput: Equatable,
            F.FormatOutput == String {
        self.init(
            label: Text(titleResource),
            content: Text(value, format: format)
        )
    }
}

extension LabeledContent
where Label == LabeledContentStyleConfiguration.Label,
      Content == LabeledContentStyleConfiguration.Content {
    public init(_ configuration: LabeledContentStyleConfiguration) {
        self.init(
            label: configuration.label,
            content: configuration.content,
            accessibilityPresentation: configuration.accessibilityPresentation
        )
    }
}
