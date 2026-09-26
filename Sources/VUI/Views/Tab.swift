//
//  File: Tab.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct TabRole: Hashable, Sendable {
    enum Role: Hashable, Sendable {
        case search
        case prominent
    }

    var role: Role

    public static var search: TabRole {
        TabRole(role: .search)
    }

    public static var prominent: TabRole {
        TabRole(role: .prominent)
    }
}

public struct DefaultTabLabel: View {
    var base: Label<Text, Image>?
    var role: TabRole?

    init<S>(_ title: S, image name: String, role: TabRole?)
    where S: StringProtocol {
        base = Label(title, image: name)
        self.role = role
    }

    init<S>(_ title: S, systemImage name: String, role: TabRole?)
    where S: StringProtocol {
        base = Label(title, systemImage: name)
        self.role = role
    }

    init(
        _ titleKey: LocalizedStringKey,
        image name: String,
        role: TabRole?
    ) {
        base = Label(titleKey, image: name)
        self.role = role
    }

    init(
        _ titleKey: LocalizedStringKey,
        systemImage name: String,
        role: TabRole?
    ) {
        base = Label(titleKey, systemImage: name)
        self.role = role
    }

    init(
        _ titleResource: LocalizedStringResource,
        image name: String,
        role: TabRole?
    ) {
        base = Label {
            Text(titleResource)
        } icon: {
            Image(name)
        }
        self.role = role
    }

    init(
        _ titleResource: LocalizedStringResource,
        systemImage name: String,
        role: TabRole?
    ) {
        base = Label {
            Text(titleResource)
        } icon: {
            Image(systemName: name)
        }
        self.role = role
    }

    init(role: TabRole?) {
        base = nil
        self.role = role
    }

    @ViewBuilder
    public var body: some View {
        if let base {
            base
        } else if role == .search {
            Label("Search", systemImage: "magnifyingglass")
        } else {
            EmptyView()
        }
    }
}

struct TabItemPresentation {
    var label: AnyView
    var role: TabRole?
}

struct TabItemTraitKey: _ViewTraitKey {
    static var defaultValue: TabItemPresentation? { nil }
}

public struct Tab<Value, Content, Label> {
    var _value: Value?
    var role: TabRole?
    var content: Content
    var tabItem: Label

    private init(
        tabValue: Value?,
        role: TabRole?,
        content: Content,
        tabItem: Label
    ) {
        _value = tabValue
        self.role = role
        self.content = content
        self.tabItem = tabItem
    }
}

extension Tab: TabContent
where Value: Hashable, Content: View, Label: View {
    public typealias TabValue = Value

    struct TabIdentifiedView: View {
        let tab: Tab

        var body: some View {
            tab.content._trait(
                TabItemTraitKey.self,
                TabItemPresentation(
                    label: AnyView(tab.tabItem),
                    role: tab.role
                )
            )
        }
    }

    public var _identifiedView: some View {
        TabIdentifiedView(tab: self)._trait(
            TagValueTraitKey<Value>.self,
            _value.map(TagValueTraitKey<Value>.Value.tagged) ?? .untagged
        )
    }

    public var body: Self { self }
}

extension Tab
where Value: Hashable, Content: View, Label == DefaultTabLabel {
    @_disfavoredOverload
    public init<S>(
        _ title: S,
        image name: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(title, image: name, role: nil)
        )
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        image name: String,
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(title, image: name, role: role)
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        image name: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, image: name, role: nil)
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        image name: String,
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, image: name, role: role)
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        image name: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(titleResource, image: name, role: nil)
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        image name: String,
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleResource, image: name, role: role)
        )
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        systemImage name: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(title, systemImage: name, role: nil)
        )
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        systemImage name: String,
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(title, systemImage: name, role: role)
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage name: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, systemImage: name, role: nil)
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage name: String,
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, systemImage: name, role: role)
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        systemImage name: String,
        value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(
                titleResource,
                systemImage: name,
                role: nil
            )
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        systemImage name: String,
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(
                titleResource,
                systemImage: name,
                role: role
            )
        )
    }

    public init(
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(role: role)
        )
    }
}

extension Tab
where Value: Hashable, Content: View, Label == EmptyView {
    public init(
        value: Value,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: EmptyView()
        )
    }
}

extension Tab where Value: Hashable, Content: View, Label: View {
    public init(
        value: Value,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: label()
        )
    }

    public init(
        value: Value,
        role: TabRole?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: label()
        )
    }
}

extension Tab
where Value: Hashable, Content: View, Label == DefaultTabLabel {
    @_disfavoredOverload
    public init<S, T>(
        _ title: S,
        image name: String,
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, S: StringProtocol, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(title, image: name, role: nil)
        )
    }

    @_disfavoredOverload
    public init<S, T>(
        _ title: S,
        image name: String,
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, S: StringProtocol, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(title, image: name, role: role)
        )
    }

    public init<T>(
        _ titleKey: LocalizedStringKey,
        image name: String,
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, image: name, role: nil)
        )
    }

    public init<T>(
        _ titleKey: LocalizedStringKey,
        image name: String,
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, image: name, role: role)
        )
    }

    @_disfavoredOverload
    public init<T>(
        _ titleResource: LocalizedStringResource,
        image name: String,
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(titleResource, image: name, role: nil)
        )
    }

    @_disfavoredOverload
    public init<T>(
        _ titleResource: LocalizedStringResource,
        image name: String,
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleResource, image: name, role: role)
        )
    }

    @_disfavoredOverload
    public init<S, T>(
        _ title: S,
        systemImage name: String,
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, S: StringProtocol, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(title, systemImage: name, role: nil)
        )
    }

    @_disfavoredOverload
    public init<S, T>(
        _ title: S,
        systemImage name: String,
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, S: StringProtocol, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(title, systemImage: name, role: role)
        )
    }

    public init<T>(
        _ titleKey: LocalizedStringKey,
        systemImage name: String,
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, systemImage: name, role: nil)
        )
    }

    public init<T>(
        _ titleKey: LocalizedStringKey,
        systemImage name: String,
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, systemImage: name, role: role)
        )
    }

    @_disfavoredOverload
    public init<T>(
        _ titleResource: LocalizedStringResource,
        systemImage name: String,
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: DefaultTabLabel(
                titleResource,
                systemImage: name,
                role: nil
            )
        )
    }

    @_disfavoredOverload
    public init<T>(
        _ titleResource: LocalizedStringResource,
        systemImage name: String,
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(
                titleResource,
                systemImage: name,
                role: role
            )
        )
    }

    public init<T>(
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(role: role)
        )
    }
}

extension Tab
where Value: Hashable, Content: View, Label == EmptyView {
    public init<T>(
        value: T,
        @ViewBuilder content: () -> Content
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: EmptyView()
        )
    }
}

extension Tab where Value: Hashable, Content: View, Label: View {
    public init<T>(
        value: T,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: nil,
            content: content(),
            tabItem: label()
        )
    }

    public init<T>(
        value: T,
        role: TabRole?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) where Value == T?, T: Hashable {
        self.init(
            tabValue: .some(value),
            role: role,
            content: content(),
            tabItem: label()
        )
    }
}

extension Tab
where Value == Never, Content: View, Label == DefaultTabLabel {
    @_disfavoredOverload
    public init<S>(
        _ title: S,
        image name: String,
        role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(title, image: name, role: role)
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        image name: String,
        role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, image: name, role: role)
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        image name: String,
        role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleResource, image: name, role: role)
        )
    }

    @_disfavoredOverload
    public init<S>(
        _ title: S,
        systemImage name: String,
        role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) where S: StringProtocol {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(title, systemImage: name, role: role)
        )
    }

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage name: String,
        role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(titleKey, systemImage: name, role: role)
        )
    }

    @_disfavoredOverload
    public init(
        _ titleResource: LocalizedStringResource,
        systemImage name: String,
        role: TabRole? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(
                titleResource,
                systemImage: name,
                role: role
            )
        )
    }

    public init(
        role: TabRole?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: DefaultTabLabel(role: role)
        )
    }
}

extension Tab where Value == Never, Content: View, Label == EmptyView {
    public init(@ViewBuilder content: () -> Content) {
        self.init(
            tabValue: nil,
            role: nil,
            content: content(),
            tabItem: EmptyView()
        )
    }
}

extension Tab where Value == Never, Content: View, Label: View {
    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            tabValue: nil,
            role: nil,
            content: content(),
            tabItem: label()
        )
    }

    public init(
        role: TabRole?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder label: () -> Label
    ) {
        self.init(
            tabValue: nil,
            role: role,
            content: content(),
            tabItem: label()
        )
    }
}

extension View {
    public func tabItem<Label>(
        @ViewBuilder _ label: () -> Label
    ) -> some View where Label: View {
        _trait(
            TabItemTraitKey.self,
            TabItemPresentation(label: AnyView(label()), role: nil)
        )
    }
}
