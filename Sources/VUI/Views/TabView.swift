//
//  File: TabView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

struct ContainerStyleContext: StyleContext {}

struct DisableNavigationDestination: ViewInputBoolFlag {
    typealias Value = Bool
    var description: String { "DisableNavigationDestination" }
}

public struct TabView<SelectionValue, Content>: View
where SelectionValue: Hashable, Content: View {
    var selection: Binding<SelectionValue>?
    var content: Content

    public init(
        selection: Binding<SelectionValue>?,
        @ViewBuilder content: () -> Content
    ) {
        self.selection = selection
        self.content = content()
    }

    public init<C>(
        selection: Binding<SelectionValue>,
        @TabContentBuilder<SelectionValue> content: () -> C
    ) where
        Content == TabContentBuilder<SelectionValue>.Content<C>,
        C: TabContent<SelectionValue>
    {
        self.selection = selection
        self.content = TabContentBuilder<SelectionValue>.Content(content())
    }

    public var body: some View {
        ResolvedTabView(
            configuration: TabViewStyleConfiguration(
                selection: selection,
                content: TabViewStyleConfiguration<SelectionValue>.Content()
            )
        )
        .viewAlias(TabViewStyleConfiguration<SelectionValue>.Content.self) {
            content.modifier(StyleContextWriter<ContainerStyleContext>())
        }
        .modifier(
            ViewInputFlagModifier(flag: DisableNavigationDestination())
        )
    }
}

extension TabView where SelectionValue == Int {
    public init(@ViewBuilder content: () -> Content) {
        selection = nil
        self.content = content()
    }
}

extension TabView {
    public init<C>(
        @TabContentBuilder<Never> content: () -> C
    ) where
        SelectionValue == Never,
        Content == TabContentBuilder<Never>.Content<C>,
        C: TabContent<Never>
    {
        selection = nil
        self.content = TabContentBuilder<Never>.Content(content())
    }
}

@available(*, unavailable)
extension TabView: Sendable {}
