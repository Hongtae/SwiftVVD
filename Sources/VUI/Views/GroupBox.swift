//
//  File: GroupBox.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct AccessibilityAttachmentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

struct RelationshipModifier<Value>: ViewModifier where Value: Hashable {
    var value: Value

    func body(content: Content) -> some View {
        content
    }
}

struct AccessibilityChildContainmentModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}

public struct GroupBox<Label, Content>: View
where Label: View, Content: View {
    let label: Label?
    let content: Content
    @Namespace private var namespace

    init(label: Label?, content: Content) {
        self.label = label
        self.content = content
    }

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(label: label(), content: content())
    }

    public var body: some View {
        let identifier = String(describing: namespace)
        return ResolvedGroupBoxStyle(
            configuration: GroupBoxStyleConfiguration()
        )
        .modifier(
            OptionalSourceWriter<
                GroupBoxStyleConfiguration.Label,
                ModifiedContent<
                    ModifiedContent<Label, AccessibilityAttachmentModifier>,
                    RelationshipModifier<String>
                >
            >(
                source: label.map {
                    $0.modifier(AccessibilityAttachmentModifier())
                        .modifier(
                            RelationshipModifier(
                                value: "label-\(identifier)"
                            )
                        )
                }
            )
        )
        .modifier(
            StaticSourceWriter<
                GroupBoxStyleConfiguration.Content,
                ModifiedContent<Content, RelationshipModifier<String>>
            >(
                source: content.modifier(
                    RelationshipModifier(
                        value: "content-\(identifier)"
                    )
                )
            )
        )
    }
}

extension GroupBox
where Label == GroupBoxStyleConfiguration.Label,
      Content == GroupBoxStyleConfiguration.Content {
    public init(_ configuration: GroupBoxStyleConfiguration) {
        self.init(
            label: configuration.label,
            content: configuration.content
        )
    }
}

extension GroupBox where Label == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(label: nil, content: content())
    }
}

extension GroupBox where Label == Text {
    public init(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label: Text(titleKey), content: content())
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        @ViewBuilder content: () -> Content
    ) {
        self.init(label: Text(titleResource), content: content())
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(label: Text(title), content: content())
    }
}
