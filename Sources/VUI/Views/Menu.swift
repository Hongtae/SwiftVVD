//
//  File: Menu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

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
            // Install PlatformItemListMenuStyle inside MenuStyleContext so nested
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
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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

extension ResolvedMenuStyle: PrimitiveView {}

struct MenuDropdownModifier<MenuContent>: ViewModifier, MultiViewModifier where MenuContent: View {
    typealias Body = Never
    let content: MenuContent
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onMenuOpenChanged: ((Bool) -> Void)? = nil
    var onPressingChanged: ((Bool) -> Void)? = nil
    var onPresentationChanged: ((Bool) -> Void)? = nil
}

extension MenuDropdownModifier {
    fileprivate var _scene: some Scene { _EmptyScene() }
}

extension MenuDropdownModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("MenuDropdownModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map { $0.value }

        let innerRespondersAttr: Attribute<[any ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute<[any ViewResponder]>(innerResponderNodes[0])
        } else {
            innerRespondersAttr = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for nodeID in innerResponderNodes {
                    let value = Attribute<[any ViewResponder]>(nodeID).value
                    ViewRespondersKey.reduce(value: &combined) { value }
                }
                return combined
            }
        }

        let itemListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(
            PlatformItemListGenerator<AllPlatformItemListFlags, MenuContent>(
                content: modifier[\.content]._attribute,
                inputs: inputs,
                inputsIncludeGeometry: true
            )
        )
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let value = modifier._attribute.value
        let responder = MenuDropdownResponder(
            itemList: itemListAttr,
            environment: environmentAttr,
            transform: inputs.transform,
            size: inputs.size,
            onHoverChanged: value.onHoverChanged,
            onMenuOpenChanged: value.onMenuOpenChanged,
            onPressingChanged: value.onPressingChanged,
            onPresentationChanged: value.onPresentationChanged,
            innerResponders: innerRespondersAttr.value
        )
        graph.makeSideEffectRule { [weak responder] in
            guard let responder else { return }
            let value = modifier._attribute.value
            responder.snapshotTransform = inputs.transform.value
            responder.snapshotSize = inputs.size.value
            responder.snapshotIsEnabled = environmentAttr.value.isEnabled
            responder.onHoverChanged = value.onHoverChanged
            responder.onMenuOpenChanged = value.onMenuOpenChanged
            responder.onPressingChanged = value.onPressingChanged
            responder.onPresentationChanged = value.onPresentationChanged
            responder.innerResponders = innerRespondersAttr.value
        }

        // Standalone Menu installs a dropdown responder; nested Menu under
        // MenuStyleContext remains PlatformItemListMenuStyle collection.
        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("MenuDropdownModifier._makeViewList called outside AG context")
        }
        // Keep the dropdown modifier attached when a Menu trigger is materialized
        // as a list child, such as the arrow segment inside a primary-action HStack.
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

private let _menuDropdownResponderNextKey = Mutex<UInt32>(0x91000000)

final class MenuDropdownResponder: AnyHoverResponder {
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    let itemList: Attribute<PlatformItemList>
    let environment: Attribute<EnvironmentValues>
    let transform: Attribute<ViewTransform>
    let size: Attribute<ViewSize>

    var snapshotTransform: ViewTransform = .identity
    var snapshotSize: ViewSize = .zero
    var snapshotIsEnabled: Bool = true
    var onHoverChanged: ((Bool) -> Void)?
    var onMenuOpenChanged: ((Bool) -> Void)?
    var onPressingChanged: ((Bool) -> Void)?
    var onPresentationChanged: ((Bool) -> Void)?
    var innerResponders: [any ViewResponder]

    private var isHovered = false
    private var isMenuOpen = false
    private var activeSession: ContextMenuPresentationSession?

    init(itemList: Attribute<PlatformItemList>,
         environment: Attribute<EnvironmentValues>,
         transform: Attribute<ViewTransform>,
         size: Attribute<ViewSize>,
         onHoverChanged: ((Bool) -> Void)?,
         onMenuOpenChanged: ((Bool) -> Void)?,
         onPressingChanged: ((Bool) -> Void)?,
         onPresentationChanged: ((Bool) -> Void)?,
         innerResponders: [any ViewResponder]) {
        self.hitTestKey = _menuDropdownResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.itemList = itemList
        self.environment = environment
        self.transform = transform
        self.size = size
        self.snapshotTransform = transform.value
        self.snapshotSize = size.value
        self.snapshotIsEnabled = environment.value.isEnabled
        self.onHoverChanged = onHoverChanged
        self.onMenuOpenChanged = onMenuOpenChanged
        self.onPressingChanged = onPressingChanged
        self.onPresentationChanged = onPresentationChanged
        self.innerResponders = innerResponders
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func containsGlobalPoints(_ points: [CGPoint],
                              cacheKey: UInt32?,
                              options: ContainsPointsOptions) -> ContainsPointsResult {
        guard snapshotIsEnabled else { return .stop }
        var localPts = Array(points.prefix(64))
        snapshotTransform.convertGlobal(to: .local, points: &localPts)
        let bounds = CGRect(origin: .zero, size: snapshotSize.value)
        var mask: UInt64 = 0
        for (index, point) in localPts.enumerated() {
            if bounds.contains(point) { mask |= (1 << index) }
        }
        guard mask != 0 else { return .stop }
        return ContainsPointsResult(mask: mask,
                                    priority: 16.0,
                                    children: innerResponders)
    }

    func updateHover(isActive newValue: Bool, point: CGPoint?) -> (() -> Void)? {
        let active = snapshotIsEnabled && newValue
        guard isHovered != active else { return nil }
        isHovered = active
        let callback = onHoverChanged
        return { callback?(active) }
    }

    var menuIsOpen: Bool {
        isMenuOpen
    }

    func dismissMenu() {
        guard isMenuOpen else { return }
        if let activeSession {
            activeSession.dismissAll()
        } else {
            setMenuOpen(false)
        }
    }

    func present(from parent: WindowController) {
        guard snapshotIsEnabled else { return }
        guard let graph = _AGGraph.current else {
            fatalError("MenuDropdownResponder.present called outside AG context")
        }

        graph.inbox.drain()
        graph.drainActions()
        parent.dismissAllPresentationChildren()

        let session = ContextMenuPresentationSession()
        let actions = ContextMenuPopupActions()
        let initialItems = itemList.value.menuItems
        let liveContentSubgraph = AGSubgraph()
        AGSubgraph.withCurrent(liveContentSubgraph) {
            graph.makeSideEffectRule { [weak session] in
                let items = self.itemList.value.menuItems
                session?.root?.replaceMenuItems(items)
            }
        }
        session.installLiveContent(sourceGraph: graph, subgraph: liveContentSubgraph)
        session.onFinish = { [weak self, weak session] in
            guard let self, self.activeSession === session else { return }
            self.activeSession = nil
            self.setMenuOpen(false)
        }
        activeSession = session
        setMenuOpen(true)

        let ctrl = ContextMenuWindowController(content: contextMenuPopupContent(items: initialItems,
                                                                                actions: actions),
                                               scene: parent.scene,
                                               anchor: presentationAnchor(),
                                               items: initialItems,
                                               actions: actions,
                                               usesPlatformWindow: environment.value.presentationChildUsingPlatformWindow,
                                               session: session)
        session.root = ctrl
        actions.openSubmenu = { [weak ctrl] item, origin in
            ctrl?.openSubmenu(item, at: origin)
        }
        actions.closeSubmenus = { [weak ctrl] in
            ctrl?.closeSubmenus()
        }
        actions.dismiss = { [weak session] in
            session?.dismissAll()
        }
        parent.addPresentationChild(child: ctrl) { [weak ctrl] attach in
            ctrl?.resolvePresentationWindowAttachment(attach)
        }
    }

    private func presentationAnchor() -> CGPoint {
        var points = [CGPoint(x: 0, y: snapshotSize.value.height)]
        snapshotTransform.convertGlobal(from: .local, points: &points)
        return points[0]
    }

    private func setMenuOpen(_ open: Bool) {
        guard isMenuOpen != open else { return }
        isMenuOpen = open
        onMenuOpenChanged?(open)
        onPressingChanged?(open)
        onPresentationChanged?(open)
    }
}
