//
//  File: Label.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct Label<Title, Icon> : View where Title : View, Icon : View {
    let title: Title
    let icon: Icon
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }

    public var body: some View {
        ResolvedLabelStyle()
            .modifier(StaticSourceWriter<LabelStyleConfiguration.Icon, Icon>(source: self.icon))
            .modifier(StaticSourceWriter<LabelStyleConfiguration.Title, Title>(source: self.title))
    }
}

extension Label where Title == Text, Icon == Image {
    public init(_ titleKey: LocalizedStringKey, image name: String) {
        self.title = Text(titleKey)
        self.icon = Image(name)
    }
    public init(_ titleKey: LocalizedStringKey, systemImage name: String) {
        self.title = Text(titleKey)
        self.icon = Image(systemName: name)
    }
    public init<S>(_ title: S, image name: String) where S : StringProtocol {
        self.title = Text(title)
        self.icon = Image(name)
    }
    public init<S>(_ title: S, systemImage name: String) where S : StringProtocol {
        self.title = Text(title)
        self.icon = Image(systemName: name)
    }
}

extension Label where Title == LabelStyleConfiguration.Title, Icon == LabelStyleConfiguration.Icon {
    public init(_ configuration: LabelStyleConfiguration) {
        self.title = configuration.title
        self.icon = configuration.icon
    }
}

extension LabelStyle {
    func _makeBodyView(configuration: Configuration, inputs: _ViewInputs) -> _ViewOutputs {
        let view = self.makeBody(configuration: configuration)
        return Self.Body._makeView(view: _GraphValue(view), inputs: inputs)
    }
    func _makeBodyViewList(configuration: Configuration, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = self.makeBody(configuration: configuration)
        return Self.Body._makeViewList(view: _GraphValue(view), inputs: inputs)
    }
}

struct ResolvedLabelStyle: View {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let title = inputs.sourceWrites[ObjectIdentifier(LabelStyleConfiguration.Title.self)] as? AnyView
        let icon = inputs.sourceWrites[ObjectIdentifier(LabelStyleConfiguration.Icon.self)] as? AnyView
        let configuration = LabelStyleConfiguration(title, icon)

        // resolve sytle
        if let style = inputs.labelStyles.last {
            var inputs = inputs
            inputs.labelStyles.removeLast()
            return style._makeBodyView(configuration: configuration, inputs: inputs)
        }
        return DefaultLabelStyle.automatic._makeBodyView(configuration: configuration, inputs: inputs)
    }
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let title = inputs.inputs.sourceWrites[ObjectIdentifier(LabelStyleConfiguration.Title.self)] as? AnyView
        let icon = inputs.inputs.sourceWrites[ObjectIdentifier(LabelStyleConfiguration.Icon.self)] as? AnyView
        let configuration = LabelStyleConfiguration(title, icon)

        // resolve sytle
        if let style = inputs.inputs.labelStyles.last {
            var inputs = inputs
            inputs.inputs.labelStyles.removeLast()
            return style._makeBodyViewList(configuration: configuration, inputs: inputs)
        }
        return DefaultLabelStyle.automatic._makeBodyViewList(configuration: configuration, inputs: inputs)
    }
}

extension ResolvedLabelStyle: _PrimitiveView {
}
