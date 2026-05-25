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
    var configuration: LabelStyleConfiguration = LabelStyleConfiguration()

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        var stack = inputs.base.customInputs.value(forKey: StyleInput<LabelStyleConfiguration>.self)
        let configuration = LabelStyleConfiguration()

        func wireBody(_ style: some LabelStyle, inputs: _ViewInputs) -> _ViewOutputs {
            let bodyAttr = graph.makeRule {
                _ = view._attribute.value
                return style.makeBody(configuration: configuration)
            }
            return makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
        }

        func appendPlatformItem(to outputs: inout _ViewOutputs) {
            guard platformItemListShouldCollectStaticItemContributors(inputs) else {
                return
            }
            let titleSource = inputs.base.customInputs
                .value(forKey: SourceInput<LabelStyleConfiguration.Title>.self).top
            let iconSource = inputs.base.customInputs
                .value(forKey: SourceInput<LabelStyleConfiguration.Icon>.self).top
            let itemID = PlatformItemList.stableID(view._attribute.identifier)
            let preferenceAttr: Attribute<PlatformItemList> = graph.makeRule {
                // Static Label rows are disabled menu items. Image icons are
                // preserved as image slots, but Text icons become the item title.
                let iconIsText = iconSource?.isSource(Text.self) == true
                let label: AnyView
                let image: AnyView?
                if iconIsText {
                    label = iconSource?.snapshot() ?? titleSource?.snapshot() ?? AnyView(EmptyView())
                    image = nil
                } else {
                    label = titleSource?.snapshot() ?? AnyView(EmptyView())
                    image = iconSource?.snapshot()
                }
                var list = PlatformItemList()
                list.append(PlatformItemList.Item(
                    id: itemID,
                    label: label,
                    image: image,
                    action: nil,
                    role: nil,
                    isEnabled: false
                ))
                return list
            }
            outputs.preferences.append(PlatformItemList.Key.self, node: preferenceAttr.identifier)
        }

        if platformItemListShouldCollectStaticItemContributors(inputs) {
            var outputs = _ViewOutputs(layoutComputer: OptionalAttribute(graph.makeRule {
                LayoutComputer.fixed(.zero)
            }))
            appendPlatformItem(to: &outputs)
            return outputs
        }

        let bodyInputs = platformItemListShouldCollectStaticItemContributors(inputs)
            ? platformItemListRenderOnlyInputs(inputs)
            : inputs
        var outputs: _ViewOutputs
        if let head = stack.pop() {
            var poppedInputs = inputs
            poppedInputs.base.customInputs.setValue(stack, forKey: StyleInput<LabelStyleConfiguration>.self)
            let style = head.labelStyle ?? DefaultLabelStyle.automatic
            if platformItemListShouldCollectStaticItemContributors(inputs) {
                var bodyPoppedInputs = bodyInputs
                bodyPoppedInputs.base.customInputs.setValue(stack, forKey: StyleInput<LabelStyleConfiguration>.self)
                outputs = wireBody(style, inputs: bodyPoppedInputs)
            } else {
                outputs = wireBody(style, inputs: poppedInputs)
            }
        } else {
            outputs = wireBody(DefaultLabelStyle.automatic, inputs: bodyInputs)
        }
        appendPlatformItem(to: &outputs)
        return outputs
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ResolvedLabelStyle: _PrimitiveView {}

extension ResolvedLabelStyle: StyleableView {
    typealias DefaultStyleModifier = LabelStyleModifier<DefaultLabelStyle>
    static var defaultStyleModifier: LabelStyleModifier<DefaultLabelStyle> {
        LabelStyleModifier(style: DefaultLabelStyle())
    }
}
