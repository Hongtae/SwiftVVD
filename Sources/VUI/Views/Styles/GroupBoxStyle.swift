//
//  File: GroupBoxStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private struct GroupBoxDisablePaddingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct GroupBoxDisableBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var groupBoxDisablePadding: Bool {
        get { self[GroupBoxDisablePaddingKey.self] }
        set { self[GroupBoxDisablePaddingKey.self] = newValue }
    }

    var groupBoxDisableBackground: Bool {
        get { self[GroupBoxDisableBackgroundKey.self] }
        set { self[GroupBoxDisableBackgroundKey.self] = newValue }
    }
}

public protocol GroupBoxStyle {
    associatedtype Body: View

    @ViewBuilder
    func makeBody(configuration: Self.Configuration) -> Self.Body

    typealias Configuration = GroupBoxStyleConfiguration
}

public struct GroupBoxStyleConfiguration {
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }

    public struct Content: View, ViewAlias {
        public typealias Body = Never
    }

    public let label: Label
    public let content: Content

    init() {
        label = Label()
        content = Content()
    }
}

extension GroupBoxStyleConfiguration.Label: PrimitiveView {}
extension GroupBoxStyleConfiguration.Content: PrimitiveView {}

struct GroupBoxStyleModifier<Style>: StyleModifier
where Style: GroupBoxStyle {
    typealias Body = Never
    typealias StyleConfiguration = GroupBoxStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(configuration: GroupBoxStyleConfiguration) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

struct ResolvedGroupBoxStyle: StyleableView {
    var configuration: GroupBoxStyleConfiguration

    var body: some View {
        GroupBox(configuration)
            .modifier(AccessibilityChildContainmentModifier())
    }

    typealias DefaultStyleModifier = GroupBoxStyleModifier<
        DefaultGroupBoxStyle
    >

    static var defaultStyleModifier: DefaultStyleModifier {
        GroupBoxStyleModifier(style: DefaultGroupBoxStyle())
    }
}

public struct DefaultGroupBoxStyle: GroupBoxStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        GroupBox(
            label: configuration.label,
            content: configuration.content.modifier(
                GroupBoxStyleModifier(style: self)
            )
        )
        .modifier(
            GroupBoxStyleModifier(style: MacIdiomGroupBoxStyle())
        )
    }
}

struct MacIdiomGroupBoxStyle: GroupBoxStyle {
    @Environment(\.groupBoxDisablePadding)
    private var disablePadding
    @Environment(\.groupBoxDisableBackground)
    private var disableBackground

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
            configuration.content
        }
        .padding(disablePadding ? 0 : 12)
        .background(
            disableBackground ? Color.clear : Color.quaternaryFill,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}

extension GroupBoxStyle where Self == DefaultGroupBoxStyle {
    public static var automatic: DefaultGroupBoxStyle {
        DefaultGroupBoxStyle()
    }
}

extension View {
    public func groupBoxStyle<S>(_ style: S) -> some View
    where S: GroupBoxStyle {
        modifier(GroupBoxStyleModifier(style: style))
    }
}
