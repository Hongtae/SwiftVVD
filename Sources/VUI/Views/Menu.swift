//
//  File: Menu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct Menu<Label, Content>: View where Label: View, Content: View {
    let label: Label
    let content: Content
    let primaryAction: (() -> Void)?
    let onPresentationChanged: ((Bool) -> Void)?

    public var body: some View {
        ResolvedMenuStyle(primaryAction: primaryAction,
                          onPresentationChanged: onPresentationChanged)
            .modifier(StaticSourceWriter<MenuStyleConfiguration.Label, Label>(source: self.label))
            .modifier(
                StaticSourceWriter<MenuStyleConfiguration.Content, ModifiedContent<Content, StyleContextWriter<MenuStyleContext>>>(
                source: self.content.modifier(StyleContextWriter<MenuStyleContext>())
                ))
            // Install the item-list menu style inside MenuStyleContext so nested
            // Menu values become submenu platform items for context menus.
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<MenuStyleContext>,
                         MenuStyleModifier<PlatformItemListMenuStyle>,
                         EmptyModifier>(
                    trueBody: MenuStyleModifier(style: PlatformItemListMenuStyle()),
                    falseBody: EmptyModifier()
                )
            )
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
        self.primaryAction = nil
        self.onPresentationChanged = nil
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text {
        self.label = Text(titleKey)
        self.content = content()
        self.primaryAction = nil
        self.onPresentationChanged = nil
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text, S: StringProtocol {
        self.label = Text(title)
        self.content = content()
        self.primaryAction = nil
        self.onPresentationChanged = nil
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping () -> Void) {
        self.label = label()
        self.content = content()
        self.primaryAction = primaryAction
        self.onPresentationChanged = nil
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text {
        self.label = Text(titleKey)
        self.content = content()
        self.primaryAction = primaryAction
        self.onPresentationChanged = nil
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text, S: StringProtocol {
        self.label = Text(title)
        self.content = content()
        self.primaryAction = primaryAction
        self.onPresentationChanged = nil
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
        self.label = configuration.label
        self.content = configuration.content
        self.primaryAction = configuration._primaryAction
        self.onPresentationChanged = configuration._onPresentationChanged
    }
}


struct ResolvedMenuStyle: View {
    var _menuItemStyle = _MenuItemMenuStyle()
    var _style: any MenuStyle = DefaultMenuStyle.automatic
    var _configuration = MenuStyleConfiguration()
    var _primaryAction: (() -> Void)? = nil
    var _onPresentationChanged: ((Bool) -> Void)? = nil

    init(primaryAction: (() -> Void)? = nil,
         onPresentationChanged: ((Bool) -> Void)? = nil) {
        self._primaryAction = primaryAction
        self._onPresentationChanged = onPresentationChanged
    }

    var _body: any View {
        _style.makeBody(configuration: _configuration)
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let style: any MenuStyle =
            inputs.base.customInputs.value(forKey: _MenuStyleKey.self)
            ?? DefaultMenuStyle.automatic

        func wireBody(_ style: some MenuStyle) -> _ViewOutputs {
            let bodyAttr = graph.makeRule {
                let rs = view._attribute.value
                let config = MenuStyleConfiguration(primaryAction: rs._primaryAction,
                                                    onPresentationChanged: rs._onPresentationChanged)
                return style.makeBody(configuration: config)
            }
            return makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
        }
        return wireBody(style)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ResolvedMenuStyle: _PrimitiveView {}

struct MenuDropdownModifier<MenuContent>: ViewModifier where MenuContent: View {
    typealias Body = Never
    let content: MenuContent
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onMenuOpenChanged: ((Bool) -> Void)? = nil
    var onPressingChanged: ((Bool) -> Void)? = nil
}

extension MenuDropdownModifier {
    fileprivate var _scene: some Scene { _EmptyScene() }
}

extension MenuDropdownModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        // TODO: Requires standalone menu presentation on the auxiliary/menu path.
        // MenuDropdownModifier wraps the label view and, on press, opens an
        // auxiliary presentation containing the menu content.
        // For now, pass content through unchanged so the label is still rendered.
        body(_Graph(), inputs)
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}
