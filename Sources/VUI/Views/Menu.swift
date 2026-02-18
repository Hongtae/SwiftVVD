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

    public var body: some View {
        ResolvedMenuStyle(primaryAction: primaryAction)
            .modifier(StaticSourceWriter<MenuStyleConfiguration.Label, Label>(source: self.label))
            .modifier(
                StaticSourceWriter<MenuStyleConfiguration.Content, ModifiedContent<Content, StyleContextWriter<MenuStyleContext>>>(
                source: self.content.modifier(StyleContextWriter(style: MenuStyleContext()))
                ))
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content()
        self.primaryAction = nil
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content) where Label == Text {
        self.label = Text(titleKey)
        self.content = content()
        self.primaryAction = nil
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where Label == Text, S: StringProtocol {
        self.label = Text(title)
        self.content = content()
        self.primaryAction = nil
    }
}

extension Menu {
    public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label, primaryAction: @escaping () -> Void) {
        self.label = label()
        self.content = content()
        self.primaryAction = primaryAction
    }

    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text {
        self.label = Text(titleKey)
        self.content = content()
        self.primaryAction = primaryAction
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content, primaryAction: @escaping () -> Void) where Label == Text, S: StringProtocol {
        self.label = Text(title)
        self.content = content()
        self.primaryAction = primaryAction
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
        self.primaryAction = configuration.primaryAction
    }
}


struct ResolvedMenuStyle: View {
    var _menuItemStyle = _MenuItemMenuStyle()
    var _style: any MenuStyle = DefaultMenuStyle.automatic
    var _configuration = MenuStyleConfiguration(nil, nil)
    var _primaryAction: (() -> Void)? = nil

    init(primaryAction: (() -> Void)? = nil) {
        self._primaryAction = primaryAction
    }

    var _body: any View {
        _style.makeBody(configuration: _configuration)
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let labelKey = ObjectIdentifier(MenuStyleConfiguration.Label.self)
        let contentKey = ObjectIdentifier(MenuStyleConfiguration.Content.self)

        var inputs = inputs
        let label = inputs.layouts.sourceWrites.removeValue(forKey: labelKey)
        let content = inputs.layouts.sourceWrites.removeValue(forKey: contentKey)
        let configuration = MenuStyleConfiguration(label, content)

        let explicitStyle = inputs.layouts.menuStyles.popLast()
        let isSubmenu = inputs.base.styleContext != nil
        let menuStyle: MenuStyleProxy? = isSubmenu ? MenuStyleProxy(view[\._menuItemStyle]) : explicitStyle
        let styleType = menuStyle?.type ?? DefaultMenuStyle.self

        func makeStyleBody<S: MenuStyle, T>(_: S.Type, graph: _GraphValue<T>, inputs: _ViewInputs) -> _ViewOutputs {
            S.Body._makeView(view: graph.unsafeCast(to: S.Body.self), inputs: inputs)
        }
        let outputs = makeStyleBody(styleType, graph: view[\._body], inputs: inputs)
        if let body = outputs.view {
            let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
                ResolvedMenuStyleViewContext(menuStyle: menuStyle,
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

extension ResolvedMenuStyle: _PrimitiveView {}

struct MenuDropdownModifier<MenuContent>: ViewModifier where MenuContent: View {
    typealias Body = Never
    let content: MenuContent
    var onHoverChanged: ((Bool) -> Void)? = nil
    var onMenuOpenChanged: ((Bool) -> Void)? = nil
}

extension MenuDropdownModifier {
    fileprivate var _gesture: MenuDropdownGesture { .init() }
    fileprivate var _scene: some Scene { AuxiliaryWindowScene(content: content) }
}

extension MenuDropdownModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                MenuDropdownViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: view)
        }
        return outputs
    }
}

private struct MenuDropdownGesture: Gesture {
    typealias Body = Never
    typealias Value = Void
    static func _makeGesture(gesture: _GraphValue<Self>, inputs: _GestureInputs) -> _GestureOutputs<Value> {
        fatalError()
    }
}

private class MenuDropdownGestureHandler: _GestureHandler {
    var typeFilter: _PrimitiveGestureTypes = .all
    let gesture: MenuDropdownGesture
    var openMenuCallback: ((CGPoint) -> Void)? = nil
    var location: CGPoint = .zero

    override var type: _PrimitiveGestureTypes { .button }

    override var isValid: Bool {
        typeFilter.contains(self.type)
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting([.button, .tap, .longPress])
    }

    init(graph: _GraphValue<MenuDropdownGesture>, target: ViewContext?, gesture: MenuDropdownGesture) {
        self.gesture = gesture
        super.init(graph: graph, target: target)
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0, buttonID == 0 {
            self.location = self.locationInView(location)
            self.state = .processing
        } else {
            self.state = .failed
        }
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0, buttonID == 0 {
            self.location = self.locationInView(location)
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if deviceID == 0, buttonID == 0, self.state == .processing {
            self.state = .done
            self.openMenuCallback?(self.location)
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if deviceID == 0, buttonID == 0 {
            self.state = .cancelled
        }
    }

    override func reset() {
        self.state = .ready
    }
}

private class MenuDropdownViewContext<MenuContent>: ViewModifierContext<MenuDropdownModifier<MenuContent>> where MenuContent: View {
    typealias Modifier = MenuDropdownModifier<MenuContent>
    let gesture: _GraphValue<MenuDropdownGesture>
    let popupMenuContext = MenuContext()     // shared context for the popup level opened by this view
    var sceneContext: AuxiliaryWindowSceneContext<MenuContent>!
    var isMenuOpen = false
    var isMouseHovered = false
    var isPopupActivated = false

    override init(graph: _GraphValue<Modifier>, body: ViewContext, inputs: _GraphInputs) {
        self.gesture = graph[\._gesture]
        super.init(graph: graph, body: body, inputs: inputs)

        let sceneRoot = _SceneRoot(view: self)
        var popupEnvironment = self.environment
        popupEnvironment._menuContext = popupMenuContext
        let sceneInputs = _SceneInputs(root: sceneRoot, environment: popupEnvironment,
                                       modifiers: self.inputs.modifiers,
                                       _modifierTypeGraphs: self.inputs._modifierTypeGraphs)

        func makeScene<T: Scene>(scene: _GraphValue<T>, inputs: _SceneInputs) -> _SceneOutputs {
            T._makeScene(scene: scene, inputs: inputs)
        }
        let sceneOutputs = makeScene(scene: graph[\._scene], inputs: sceneInputs)
        self.sceneContext = sceneOutputs.scene?.makeScene() as? AuxiliaryWindowSceneContext<MenuContent>
        assert(self.sceneContext != nil, "Failed to create AuxiliaryWindowSceneContext for Menu")
    }

    override func updateContent() {
        super.updateContent()
        self.sceneContext.updateContent()
    }

    override func gestureHandlers(at location: CGPoint) -> GestureHandlerOutputs {
        let outputs = super.gestureHandlers(at: location)
        guard styleContext == nil else { return outputs }

        if self.bounds.contains(location), let gesture = self.modifier?._gesture {
            let handler = MenuDropdownGestureHandler(graph: self.gesture, target: self, gesture: gesture)
            handler.openMenuCallback = { [weak self] _ in
                guard let self else { return }
                let origin = CGPoint(x: self.bounds.minX, y: self.bounds.maxY)
                self.openMenu(at: origin)
            }
            let local = GestureHandlerOutputs(gestures: [handler],
                                              simultaneousGestures: [],
                                              highPriorityGestures: [])
            return outputs.merge(local)
        }
        return outputs
    }

    override func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        guard styleContext != nil else {
            return super.handleMouseHover(at: location, deviceID: deviceID, isTopMost: isTopMost)
        }

        _ = super.handleMouseHover(at: location, deviceID: deviceID, isTopMost: isTopMost)

        if deviceID == 0 {
            let wasHovered = self.isMouseHovered

            if isTopMost {
                self.isMouseHovered = self.hitTest(location) != nil
            } else {
                if isMenuOpen {
                    let wp = location.applying(self.transformToRoot)
                    if let frame = self.sceneContext?.auxiliaryWindowFrame(), frame.contains(wp) {
                        self.isPopupActivated = true
                    }
                }
                self.isMouseHovered = false
            }

            if wasHovered != self.isMouseHovered {
                if self.isMouseHovered {
                    self.isPopupActivated = false
                    if !self.isMenuOpen {
                        let origin = CGPoint(x: self.bounds.maxX, y: self.bounds.minY)
                        self.openMenu(at: origin)
                    }
                } else {
                    if !self.isPopupActivated {
                        self.closeMenu()
                    }
                }
                self.modifier?.onHoverChanged?(self.isMouseHovered)
                self.body.updateContent()
            }
        }
        return isMouseHovered
    }

    func openMenu(at localOrigin: CGPoint) {
        self.isPopupActivated = false

        if let ctx = self.environment._menuContext {
            ctx.activeSubmenuRegistration?.close()
            ctx.activeSubmenuRegistration = _SubmenuRegistration(
                close: { [weak self] in self?.closeMenu() },
                isHovered: { [weak self] in self?.isMouseHovered ?? false }
            )
        }

        let windowLocation = localOrigin.applying(self.transformToRoot)
        let sceneContext = self.sceneContext!
        let context = self.sharedContext
        Task { @MainActor in
            let activated = sceneContext.activate(at: windowLocation,
                                                  context: context,
                                                  dismissOnDeactivate: true)
            if activated == false {
                Log.error("MenuDropdownViewContext: failed to activate menu scene")
            }
        }
        self.isMenuOpen = true
        self.modifier?.onMenuOpenChanged?(true)
    }

    func closeMenu() {
        guard isMenuOpen else { return }
        self.sceneContext?.dismiss()
        self.isMenuOpen = false
        self.isPopupActivated = false
        self.environment._menuContext?.activeSubmenuRegistration = nil
        self.modifier?.onMenuOpenChanged?(false)
    }

    struct _SceneRoot: SceneRoot {
        typealias Root = MenuDropdownModifier<MenuContent>
        var root: Root { view.modifier! }
        var graph: _GraphValue<Root> { view.graph }
        var app: AppContext { view.sharedContext.app }
        unowned let view: MenuDropdownViewContext<MenuContent>
        
        func value<T>(atPath path: _GraphValue<T>) -> T? {
            if let v = graph.value(atPath: path, from: root) {
                return v
            }
            return view.value(atPath: path)
        }
    }
}

private class ResolvedMenuStyleViewContext: GenericViewContext<ResolvedMenuStyle> {
    let menuStyle: MenuStyleProxy?
    let configuration: MenuStyleConfiguration

    init(menuStyle: MenuStyleProxy?, configuration: MenuStyleConfiguration,
         graph: _GraphValue<ResolvedMenuStyle>, body: ViewContext, inputs: _GraphInputs) {
        self.menuStyle = menuStyle
        self.configuration = configuration
        super.init(graph: graph, body: body, inputs: inputs)
    }

    override func updateView(_ view: inout ResolvedMenuStyle) {
        if let menuStyle {
            guard let style = menuStyle.resolve(self) else {
                fatalError("Unable to resolve menu style")
            }
            view._style = style
        }
        view._configuration = MenuStyleConfiguration(
            configuration._label,
            configuration._content,
            primaryAction: view._primaryAction
        )
    }

    override func handleMouseHover(at location: CGPoint, deviceID: Int, isTopMost: Bool) -> Bool {
        let result = super.handleMouseHover(at: location, deviceID: deviceID, isTopMost: isTopMost)
        if isTopMost, let ctx = self.environment._menuContext,
           let reg = ctx.activeSubmenuRegistration, !reg.isHovered() {
            reg.close()
            ctx.activeSubmenuRegistration = nil
        }
        return result
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        var size = super.sizeThatFits(proposal)
        if styleContext is MenuStyleContext {
            if let proposedWidth = proposal.width,
               proposedWidth.isFinite, proposedWidth > 0 {
                size.width = proposedWidth
            }
        }
        return size
    }
}
