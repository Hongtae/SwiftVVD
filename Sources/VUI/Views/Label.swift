//
//  File: Label.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
    var _style: any LabelStyle = DefaultLabelStyle.automatic
    var _menuItemStyle = _MenuItemLabelStyle()
    var _configuration = LabelStyleConfiguration(nil, nil)
    var _body: any View {
        _style.makeBody(configuration: self._configuration)
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let titleKey = ObjectIdentifier(LabelStyleConfiguration.Title.self)
        let iconKey = ObjectIdentifier(LabelStyleConfiguration.Icon.self)

        var inputs = inputs
        let title = inputs.layouts.sourceWrites.removeValue(forKey: titleKey)
        let icon = inputs.layouts.sourceWrites.removeValue(forKey: iconKey)
        let configuration = LabelStyleConfiguration(title, icon)

        let style = inputs.layouts.labelStyles.popLast()
        let isInMenu = inputs.base.styleContext != nil
        let effectiveStyle = isInMenu ? LabelStyleProxy(view[\._menuItemStyle]) : style
        let styleType = effectiveStyle?.type ?? DefaultLabelStyle.self

        func makeStyleBody<S: LabelStyle, T>(_: S.Type, graph: _GraphValue<T>, inputs: _ViewInputs) -> _ViewOutputs {
            S.Body._makeView(view: graph.unsafeCast(to: S.Body.self), inputs: inputs)
        }
        let outputs = makeStyleBody(styleType, graph: view[\._body], inputs: inputs)
        if let body = outputs.view {
            let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
                ResolvedLabelStyleViewContext(labelStyle: effectiveStyle,
                                              configuration: configuration,
                                              graph: graph,
                                              body: body.makeView(),
                                              inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        return outputs
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let outputs = Self._makeView(view: view, inputs: inputs.inputs)
        return _ViewListOutputs(views: .staticList(outputs.view))
    }
}

extension ResolvedLabelStyle: _PrimitiveView {
}

private class ResolvedLabelStyleViewContext: GenericViewContext<ResolvedLabelStyle> {
    let labelStyle: LabelStyleProxy?
    let configuration: LabelStyleConfiguration

    init(labelStyle: LabelStyleProxy?, configuration: LabelStyleConfiguration, graph: _GraphValue<ResolvedLabelStyle>, body: ViewContext, inputs: _GraphInputs) {
        self.labelStyle = labelStyle
        self.configuration = configuration
        super.init(graph: graph, body: body, inputs: inputs)
    }

    override func updateView(_ view: inout ResolvedLabelStyle) {
        if let labelStyle {
            guard let style = labelStyle.resolve(self) else {
                fatalError("Unable to resolve label style")
            }
            view._style = style
        }
        view._configuration = configuration
    }
    
    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = super.sizeThatFits(proposal)
        if let styleContext {
            if let proposedWidth = proposal.width,
               proposedWidth.isFinite, proposedWidth > 0 {
                var result = CGSize.clamp(size,
                                          min: styleContext.minimumViewSize,
                                          max: styleContext.maximumViewSize)
                result.width = proposedWidth
                return result
            }
            return size
        }
        return size
    }
}
