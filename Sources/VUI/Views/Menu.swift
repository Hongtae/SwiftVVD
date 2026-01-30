//
//  File: Menu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//


public struct Menu<Label, Content>: View where Label: View, Content: View {
    let label: Label
    let content: Content

    public var body: some View {
        ResolvedMenuStyle()
            .modifier(StaticSourceWriter<MenuStyleConfiguration.Label, Label>(source: self.label))
            .modifier(StaticSourceWriter<MenuStyleConfiguration.Content, Content>(source: self.content))
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
    }
    
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text {
        self.label = Text(titleKey)
        self.content = content()
    }
    
    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text, S: StringProtocol {
        self.label = Text(title)
        self.content = content()
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping () -> Void) {
        fatalError()
    }
    
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text {
        fatalError()
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text, S: StringProtocol {
        fatalError()
    }
}

extension Menu where Label == VUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content) {
        self.init {
            content()
        } label: {
            Label(titleKey, systemImage: systemImage)
        }
    }

    public init<S>(_ title: S, systemImage: String, @ViewBuilder content: () -> Content) where S : StringProtocol {
        self.init {
            content()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) {
        self.init {
            content()
        } label: {
            Label(titleKey, systemImage: systemImage)
        } primaryAction: {
            primaryAction()
        }
    }
}

extension Menu where Label == MenuStyleConfiguration.Label, Content == MenuStyleConfiguration.Content {
    public init(_ configuration: MenuStyleConfiguration) {
        fatalError()
    }
}


struct ResolvedMenuStyle: View {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError()
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }
}

extension ResolvedMenuStyle: _PrimitiveView {
}
