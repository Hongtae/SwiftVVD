//
//  File: Label.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Label<Title, Icon>: View where Title: View, Icon: View {
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
    public init<S>(_ title: S, image name: String) where S: StringProtocol {
        self.title = Text(title)
        self.icon = Image(name)
    }
    public init<S>(_ title: S, systemImage name: String) where S: StringProtocol {
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

struct ResolvedLabelStyle: View {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let stack = inputs.base.customInputs.value(forKey: StyleInput<LabelStyleConfiguration>.self)
        let configuration = LabelStyleConfiguration()

        func wireBody(_ style: some LabelStyle, inputs: _ViewInputs) -> _ViewOutputs {
            let bodyAttr = graph.makeRule {
                _ = view._attribute.value
                return style.makeBody(configuration: configuration)
            }
            return makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
        }

        if let (head, tail) = stack.popping() {
            var poppedInputs = inputs
            poppedInputs.base.customInputs.setValue(tail, forKey: StyleInput<LabelStyleConfiguration>.self)
            let style = head.labelStyle ?? DefaultLabelStyle.automatic
            return wireBody(style, inputs: poppedInputs)
        }
        return wireBody(DefaultLabelStyle.automatic, inputs: inputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

extension ResolvedLabelStyle: _PrimitiveView {
}

