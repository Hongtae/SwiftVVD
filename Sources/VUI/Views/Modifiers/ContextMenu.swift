//
//  File: ContextMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Observation
import VVD

struct ContextMenuModifier<MenuContent>: ViewModifier where MenuContent: View {
    let menuView: MenuContent
    var isPresented: Binding<Bool>? = nil
    @Environment(\.contextMenuKeyboardPresentationDisabled)
    private var keyboardPresentationDisabled

    func body(content: Content) -> some View {
        content.modifier(ContextMenuModifierCore(
            menuView: menuView,
            isPresented: isPresented,
            keyboardPresentationDisabled: keyboardPresentationDisabled
        ))
    }
}

struct ContextMenuModifierCore<MenuContent>: ViewModifier, MultiViewModifier
where MenuContent: View {
    typealias Body = Never

    let menuView: MenuContent
    var isPresented: Binding<Bool>?
    var keyboardPresentationDisabled: Bool
}

public enum ContextMenuTriggerPolicy: Equatable, Sendable {
    case automatic
    case secondaryDown
    case secondaryUpInside
    case longPress
}

struct ContextMenuEvent: EventType,
                         SpatialEventType,
                         HitTestableEventType,
                         Equatable {
    var timestamp: Time
    var binding: EventBinding?
    var location: CGPoint
    var globalLocation: CGPoint

    var phase: EventPhase { .ended }
    var radius: CGFloat { 0 }
    var kind: SpatialEvent.Kind? { nil }
}

extension View {
    public func contextMenu<MenuItems>(@ViewBuilder menuItems: () -> MenuItems) -> some View where MenuItems: View {
        let menuView = ZStack {
            menuItems()
                .modifier(StyleContextWriter<MenuStyleContext>())
        }
        return modifier(ContextMenuModifier(menuView: menuView))
    }
}

extension View {
    public func contextMenu<M, P>(@ViewBuilder menuItems: () -> M, @ViewBuilder preview: () -> P) -> some View where M: View, P: View {
        fatalError()
    }
}

extension ContextMenuModifierCore {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("ContextMenuModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)
        let wantsResponders = inputs.preferences.keys.contains(ViewRespondersKey.self)
        guard wantsResponders else {
            return outputs
        }

        // Build a live platform item list for this menu. The responder keeps the
        // item-list attribute so an already-open popup can refresh in place.
        let itemListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(
            PlatformItemListGenerator<AllPlatformItemListFlags, MenuContent>(
                content: modifier[\.menuView]._attribute,
                inputs: inputs,
                inputsIncludeGeometry: true
            )
        )
        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map { $0.value }
        let innerRespondersAttr: Attribute<[ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute(innerResponderNodes[0])
        } else {
            innerRespondersAttr = graph.makeRule {
                var combined = ViewRespondersKey.defaultValue
                for nodeID in innerResponderNodes {
                    let value = Attribute<[ViewResponder]>(nodeID).value
                    ViewRespondersKey.reduce(value: &combined) { value }
                }
                return combined
            }
        }

        let responder = ContextMenuResponder(
            inputs: inputs,
            itemList: itemListAttr.asWeak(),
            environment: inputs.base.cachedEnvironment.value.environment,
            phase: inputs.base.phase
        )
        let respondersAttr: Attribute<[ViewResponder]> = graph.makeStatefulRule(
            ContextMenuFilter(
                _isPresented: modifier[\.isPresented]._attribute,
                _keyboardPresentationDisabled:
                    modifier[\.keyboardPresentationDisabled]._attribute,
                _children: innerRespondersAttr,
                responder: responder
            )
        )

        outputs.preferences.preferences.removeAll {
            $0.key == ViewRespondersKey.self
        }
        outputs.preferences.append(
            ViewRespondersKey.self,
            node: respondersAttr.identifier
        )
        return outputs
    }

    // Keep the modifier attached to each materialized list element. Without this,
    // contextMenu disappears when applied to children inside HStack/VStack/etc.
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("ContextMenuModifierCore._makeViewList called outside AG context")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

struct ContextMenuFilter: StatefulRule {
    typealias Value = [ViewResponder]

    var _isPresented: Attribute<Binding<Bool>?>
    var _keyboardPresentationDisabled: Attribute<Bool>
    var _children: Attribute<[ViewResponder]>
    var responder: ContextMenuResponder

    mutating func updateValue() {
        responder.updateChildren((
            value: _children.value,
            changed: _AGGraph.currentStatefulInputChanged(_children.identifier)
        ))
        responder.updatePresentation(_isPresented.value)
        responder.keyboardPresentationDisabled =
            _keyboardPresentationDisabled.value
        if !context.hasValue {
            _AGGraph.setStatefulOutput([responder])
        }
    }
}

final class ContextMenuResponder: DefaultLayoutViewResponder {
    let itemList: WeakAttribute<PlatformItemList>
    private var isPresented: Binding<Bool>?
    private var activeSession: ContextMenuPresentationSession?
    let environment: Attribute<EnvironmentValues>
    let phase: Attribute<_GraphInputs.Phase>
    var keyboardPresentationDisabled = false

    init(inputs: _ViewInputs,
         itemList: WeakAttribute<PlatformItemList>,
         environment: Attribute<EnvironmentValues>,
         phase: Attribute<_GraphInputs.Phase>) {
        self.itemList = itemList
        self.environment = environment
        self.phase = phase
        super.init(inputs: inputs)
    }

    func updatePresentation(_ isPresented: Binding<Bool>?) {
        self.isPresented = isPresented
        activeSession?.updatePresentation(isPresented)
        if let isPresented, !isPresented.wrappedValue {
            activeSession?.dismissAll()
        }
    }

    func present(from parent: WindowController, at location: CGPoint) {
        guard let graph = _AGGraph.current else {
            fatalError("ContextMenuResponder.present called outside AG context")
        }
        guard let initialItemList = itemList.value else { return }
        let viewPhase = ViewGraphHost.Phase(base: phase.value)
        // Flush pending item-list mutations before taking the initial popup
        // snapshot. The open menu should start from the same source state that
        // future live refreshes will observe.
        graph.inbox.drain()
        graph.drainActions()
        parent.dismissAllPresentationChildren()
        let session = ContextMenuPresentationSession()
        let actions = ContextMenuPopupActions()
        let initialItems = contextMenuPresentationItems(
            initialItemList.menuItems
        )
        let liveContentSubgraph = AGSubgraph()
        AGSubgraph.withCurrent(liveContentSubgraph) {
            // Update the already-open popup root content when the collected
            // item-list source invalidates. The session owns this subgraph so
            // dismissing the menu also stops the source-graph side effect.
            graph.makeSideEffectRule { [weak session] in
                guard let itemList = self.itemList.value else {
                    session?.dismissAll()
                    return
                }
                let items = contextMenuPresentationItems(
                    itemList.menuItems
                )
                let environment = self.environment.value.untrackedCopy()
                let viewPhase = ViewGraphHost.Phase(base: self.phase.value)
                session?.root?.replaceMenuItems(items)
                session?.root?.setPresentationEnvironment(
                    environment,
                    viewPhase: viewPhase
                )
            }
        }
        session.installLiveContent(sourceGraph: graph, subgraph: liveContentSubgraph)
        session.updatePresentation(isPresented)
        session.markPresented()
        session.onFinish = { [weak self, weak session] in
            guard self?.activeSession === session else { return }
            self?.activeSession = nil
        }
        activeSession = session
        let presentationEnvironment = environment.value
        let usesPlatformWindow = presentationEnvironment.resolvedUsesPlatformWindow(
            \.presentationChildUsingPlatformWindow
        )
        let ctrl = ContextMenuWindowController(content: contextMenuPopupContent(items: initialItems,
                                                                                actions: actions),
                                               environment: presentationEnvironment.untrackedCopy(),
                                               viewPhase: viewPhase,
                                               scene: parent.scene,
                                               anchor: location,
                                               items: initialItems,
                                               actions: actions,
                                               usesPlatformWindow: usesPlatformWindow,
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

    func resolvedTriggerPolicy(
        for device: MouseEventDevice,
        buttonID: Int
    ) -> ContextMenuTriggerPolicy {
        let policy = environment.value.contextMenuTriggerPolicy
        guard policy == .automatic else {
            return policy
        }
        switch device {
        case .touch:
            return .longPress
        case .stylus:
            return buttonID == 1 ? .secondaryDown : .longPress
        case .genericMouse, .unknown:
            return .secondaryDown
        }
    }
}

private struct ContextMenuTriggerPolicyKey: EnvironmentKey {
    static let defaultValue: ContextMenuTriggerPolicy = .automatic
}

public extension EnvironmentValues {
    var contextMenuTriggerPolicy: ContextMenuTriggerPolicy {
        get { self[ContextMenuTriggerPolicyKey.self] }
        set { self[ContextMenuTriggerPolicyKey.self] = newValue }
    }
}

final class ContextMenuPresentationSession {
    weak var root: ContextMenuWindowController?
    var onFinish: (() -> Void)?
    private weak var activatedMenu: ContextMenuWindowController?
    private weak var sourceGraph: _AGGraph?
    private var liveContentSubgraph: AGSubgraph?
    private var isPresented: Binding<Bool>?
    private var didFinish = false

    var isActive: Bool { !didFinish }

    func installLiveContent(sourceGraph: _AGGraph, subgraph: AGSubgraph) {
        self.sourceGraph = sourceGraph
        self.liveContentSubgraph = subgraph
    }

    func updatePresentation(_ isPresented: Binding<Bool>?) {
        self.isPresented = isPresented
    }

    func markPresented() {
        isPresented?.wrappedValue = true
    }

    func activateMenu(_ menu: ContextMenuWindowController) {
        guard !didFinish, activatedMenu !== menu else { return }
        activatedMenu?.setActivated(false)
        activatedMenu = menu
        menu.setActivated(true)
    }

    func dismissAll() {
        if let root {
            root.dismiss()
        } else {
            finish()
        }
    }

    func finish() {
        guard !didFinish else { return }
        didFinish = true
        activatedMenu = nil
        isPresented?.wrappedValue = false
        tearDownLiveContent()
        onFinish?()
        onFinish = nil
        root = nil
    }

    private func tearDownLiveContent() {
        guard let subgraph = liveContentSubgraph else { return }
        liveContentSubgraph = nil
        if let sourceGraph {
            // The live refresh rule belongs to the source graph, not the popup
            // child graph. Bind that graph while invalidating so weak handles and
            // deferred graph actions resolve against the owner.
            _AGGraph.withCurrent(sourceGraph) {
                subgraph.invalidate()
            }
        }
        subgraph.removeFromParent()
    }
}

struct ContextMenuPresentationItem: Identifiable {
    struct ID: Hashable {
        enum Source: Hashable {
            case platformIdentifier(String)
            case indexPath([Int])
        }

        enum Role: Hashable {
            case item
            case sectionLeadingDivider
            case sectionHeader
            case sectionTrailingDivider
        }

        var source: Source
        var role: Role
    }

    enum Kind {
        case item
        case sectionHeader
        case divider
    }

    var id: ID
    var item: PlatformItemList.Item
    var kind: Kind
    var children: [ContextMenuPresentationItem]

    var isDivider: Bool {
        if case .divider = kind {
            return true
        }
        return false
    }

    var isSectionHeader: Bool {
        if case .sectionHeader = kind {
            return true
        }
        return false
    }

    var isMenu: Bool {
        if case .menu? = item.systemItem {
            return true
        }
        return false
    }

    var hasImage: Bool {
        item.namedResolvedImage != nil || item.resolvedImage != nil
    }

    @ViewBuilder
    var image: some View {
        if let image = item.namedResolvedImage {
            image
        } else if let image = item.resolvedImage {
            PlatformItemResolvedImageView(image: image)
        } else {
            EmptyView()
        }
    }
}

func contextMenuPresentationItems(
    _ items: [PlatformItemList.Item],
    parentPath: [Int] = []
) -> [ContextMenuPresentationItem] {
    var result: [ContextMenuPresentationItem] = []
    for (index, sourceItem) in items.enumerated() {
        var item = sourceItem
        item.resolveInterfaceValidation()
        if item.systemItem == nil,
           item.selectionBehavior?.onSelect == nil {
            item.isEnabled = false
        }
        let path = parentPath + [index]
        let source: ContextMenuPresentationItem.ID.Source
        if let platformIdentifier = item.platformIdentifier {
            source = .platformIdentifier(platformIdentifier)
        } else {
            source = .indexPath(path)
        }

        if case .section? = item.systemItem {
            var divider = PlatformItemList.Item(systemItem: .divider)
            divider.isEnabled = false
            result.append(
                ContextMenuPresentationItem(
                    id: .init(
                        source: source,
                        role: .sectionLeadingDivider
                    ),
                    item: divider,
                    kind: .divider,
                    children: []
                )
            )
            if item.label != nil || item.text != nil {
                result.append(
                    ContextMenuPresentationItem(
                        id: .init(
                            source: source,
                            role: .sectionHeader
                        ),
                        item: item,
                        kind: .sectionHeader,
                        children: []
                    )
                )
            }
            if let children = item.children {
                result.append(
                    contentsOf: contextMenuPresentationItems(
                        children.items,
                        parentPath: path + [0]
                    )
                )
            }
            result.append(
                ContextMenuPresentationItem(
                    id: .init(
                        source: source,
                        role: .sectionTrailingDivider
                    ),
                    item: divider,
                    kind: .divider,
                    children: []
                )
            )
            continue
        }

        let kind: ContextMenuPresentationItem.Kind
        if case .divider? = item.systemItem {
            kind = .divider
        } else {
            kind = .item
        }
        let children = item.children.map {
            contextMenuPresentationItems(
                $0.items,
                parentPath: path + [0]
            )
        } ?? []
        result.append(
            ContextMenuPresentationItem(
                id: .init(source: source, role: .item),
                item: item,
                kind: kind,
                children: children
            )
        )
    }
    return result
}

@Observable
private final class MenuPopupActivationState {
    var isActivated = false
}

final class ContextMenuPopupActions {
    var openSubmenu: ((ContextMenuPresentationItem, CGPoint) -> Void)?
    var closeSubmenus: (() -> Void)?
    var dismiss: (() -> Void)?
    var pointerInteractionBegan: (() -> Void)?
    var menuHoverChanged: ((Bool) -> Void)?
    var submenuRowHoverChanged:
        ((ContextMenuPresentationItem.ID, Bool) -> Void)?
    private let activationState = MenuPopupActivationState()

    var isActivated: Bool { activationState.isActivated }

    func setActivated(_ activated: Bool) {
        activationState.isActivated = activated
    }
}

struct ContextMenuSubmenuPlacement {
    var fallbackRightOrigin: CGPoint
}

// Context menus are popup presentation children, not a separate window family.
// PopupWindowController supplies the .popupWindow style plus parent
// deactivate/move dismissal policy; this subclass only owns menu-session state,
// submenu fan-out, and context-menu-specific teardown.
final class ContextMenuWindowController: PopupWindowController, @unchecked Sendable {
    private struct KeyboardStream: Hashable {
        var deviceID: Int
        var key: VirtualKey
    }

    // Window diagnostics can obscure transient menu content. Menu popup trees
    // inherit every other window policy, but remove the parent's debug override
    // at this boundary. Leaving the fields nil is important: it keeps a menu's
    // own base or future local policy effective.
    override var inheritedValues: InheritedValues {
        get { super.inheritedValues }
        set {
            var filteredValues = newValue
            filteredValues.configurationOverride.drawDebugInfo = nil
            filteredValues.configurationOverride.drawDebugInfoPlacement = nil
            super.inheritedValues = filteredValues
        }
    }

    // Window shape and border belong to the platform window when one exists.
    // Draw this chrome only through the overlay presentation path, which is
    // selected from the resolved attachment rather than the requested mode.
    override func drawOverlayPresentationChrome(
        in frame: CGRect,
        context: GraphicsContext
    ) {
        super.drawOverlayPresentationChrome(in: frame, context: context)

        let shape = RoundedRectangle(cornerRadius: 6)
        context.fill(
            shape.path(in: frame),
            with: .color(menuPopupAppearance.palette.chromeFill)
        )
        context.stroke(
            shape.inset(by: 0.5).path(in: frame),
            with: .color(menuPopupAppearance.palette.chromeStroke),
            lineWidth: 1
        )
    }

    private var contentAttr: Attribute<AnyView>?
    private let popupActions: ContextMenuPopupActions
    private let menuSession: ContextMenuPresentationSession
    private let submenuPlacement: ContextMenuSubmenuPlacement?
    private let allowsParentKeyboardTraversal: Bool
    private var menuItems: [ContextMenuPresentationItem]
    private var openedSubmenuID: ContextMenuPresentationItem.ID?
    private weak var openedSubmenu: ContextMenuWindowController?
    private var menuHoverGeneration: UInt64 = 0
    private var submenuRowHoverGeneration: UInt64 = 0
    private var submenuPresentsToRight = true
    private(set) var isActivated = false
    private(set) var keyboardSelectionID:
        ContextMenuPresentationItem.ID?
    private var consumedKeyboardStreams: Set<KeyboardStream> = []

    init<Content: View>(content: Content,
         environment: EnvironmentValues,
         viewPhase: ViewGraphHost.Phase,
         scene: WindowKey,
         anchor: CGPoint,
         items: [ContextMenuPresentationItem],
         actions: ContextMenuPopupActions,
         usesPlatformWindow: Bool,
         session: ContextMenuPresentationSession,
         submenuPlacement: ContextMenuSubmenuPlacement? = nil,
         keyboardSelectionID: ContextMenuPresentationItem.ID? = nil,
         allowsParentKeyboardTraversal: Bool = false) {
        self.popupActions = actions
        self.menuSession = session
        self.submenuPlacement = submenuPlacement
        self.allowsParentKeyboardTraversal = allowsParentKeyboardTraversal
        self.menuItems = items
        self.keyboardSelectionID = keyboardSelectionID
        let frame = CGRect(origin: anchor, size: .zero)
        super.init(content: content,
                   environment: environment,
                   viewPhase: viewPhase,
                   scene: scene,
                   usesPlatformWindow: usesPlatformWindow,
                   frameInParent: frame)
        popupActions.pointerInteractionBegan = { [weak self] in
            self?.setKeyboardSelection(nil)
        }
        popupActions.menuHoverChanged = { [weak self] hovering in
            self?.menuHoverChanged(hovering)
        }
        popupActions.submenuRowHoverChanged = { [weak self] id, hovering in
            self?.submenuRowHoverChanged(id, hovering: hovering)
        }

        // A platform popup clears its rectangular render target with the menu
        // surface color. Window shape, border, and shadow remain the platform's
        // responsibility; overlay presentations draw those separately.
        var configuration = baseConfiguration
        configuration.backgroundColor = menuPopupAppearance.palette.windowBackground
        baseConfiguration = configuration
        self.contentAttr = viewGraph.rootAnyViewContentInput
    }

    func setActivated(_ activated: Bool) {
        guard isActivated != activated else { return }
        isActivated = activated
        // Activation changes only the active/inactive row colors. Keep the
        // popup root and any open overlay child mounted while that visual state
        // invalidates through observation.
        popupActions.setActivated(activated)
    }

    private func menuHoverChanged(_ hovering: Bool) {
        if hovering {
            // Geometry changes can refresh a responder with an older pointer
            // snapshot after a descendant popup has already received newer
            // raw input. Activation is therefore owned exclusively by
            // handleMouseHover; this callback only supplies the exit edge.
            return
        }

        menuHoverGeneration &+= 1
        let generation = menuHoverGeneration
        // Parent-window exit and child-window enter may arrive through
        // different platform event callbacks. Resolve the exit from this
        // controller's next input snapshot so a child enter from the same
        // pointer transition can transfer activation first.
        enqueueInputAction { [weak self] in
            self?.resolveMenuHoverExit(generation: generation)
        }
        requestUpdate(after: 0)
    }

    private func resolveMenuHoverExit(generation: UInt64) {
        guard menuSession.isActive,
              menuHoverGeneration == generation else {
            return
        }
        if !isActivated,
           openedSubmenu?.containsActivatedMenu == true {
            return
        }
        closeSubmenus()
    }

    private func submenuRowHoverChanged(
        _ id: ContextMenuPresentationItem.ID,
        hovering: Bool
    ) {
        submenuRowHoverGeneration &+= 1
        guard !hovering else { return }

        let generation = submenuRowHoverGeneration
        // The popup panel includes chrome padding outside every row. Defer a
        // submenu-row exit so a child popup entered by the same pointer move
        // can take activation before an otherwise provisional branch closes.
        enqueueInputAction { [weak self] in
            self?.resolveSubmenuRowHoverExit(
                id: id,
                generation: generation
            )
        }
        requestUpdate(after: 0)
    }

    private func resolveSubmenuRowHoverExit(
        id: ContextMenuPresentationItem.ID,
        generation: UInt64
    ) {
        guard menuSession.isActive,
              submenuRowHoverGeneration == generation,
              openedSubmenuID == id else {
            return
        }
        if !isActivated,
           openedSubmenu?.containsActivatedMenu == true {
            return
        }
        closeSubmenus()
    }

    private func pointerEnteredPopup() {
        guard menuSession.isActive else { return }
        // A platform-window input reset drops the dispatcher binding without
        // ending the view responder's hover phase. Use the raw popup boundary
        // as the activation source so re-entering the same responder still
        // transfers ownership and cancels any deferred exit decision.
        menuHoverGeneration &+= 1
        setKeyboardSelection(nil)
        menuSession.activateMenu(self)
    }

    private var containsActivatedMenu: Bool {
        isActivated || openedSubmenu?.containsActivatedMenu == true
    }

    override func onTopMostMouseHover(
        at location: CGPoint,
        deviceID: Int,
        at time: Time
    ) {
        super.onTopMostMouseHover(
            at: location,
            deviceID: deviceID,
            at: time
        )
        if CGRect(origin: .zero, size: cachedContentSize).contains(location) {
            // Popup chrome and panel padding form part of the menu-tracking
            // region even when no row responder occupies that exact point.
            pointerEnteredPopup()
            if window == nil,
               let openedSubmenuID,
               interactiveItemID(atY: location.y) != openedSubmenuID {
                // Descendant routing has already established that the child
                // does not own this sample. Close an overlay branch when the
                // parent regains raw ownership outside its opened row, even if
                // a replaced View hover responder misses the corresponding
                // exit callback at the popup's diagonal corner.
                closeSubmenus()
            }
        }
    }

    override func overlayHitTest(_ locationInParent: CGPoint) -> Bool {
        super.overlayHitTest(locationInParent) ||
            submenuBridgeHoverLocation(from: locationInParent) != nil
    }

    override func handleMouseHover(
        at location: CGPoint,
        deviceID: Int,
        isTopMost: Bool,
        at time: Time
    ) -> Bool {
        // A submenu overlaps its parent to avoid a diagonal tracking gap at
        // their shared edge. Route that external strip to the nearest child
        // row edge so the hover and submenu-placement overlap use one metric.
        let bridgeLocation = submenuBridgeHoverLocation(from: location)
        let routedLocation = bridgeLocation ?? location
        return super.handleMouseHover(
            at: routedLocation,
            deviceID: deviceID,
            isTopMost: isTopMost,
            at: time
        )
    }

    private func submenuBridgeHoverLocation(
        from location: CGPoint
    ) -> CGPoint? {
        guard window == nil,
              submenuPlacement != nil,
              interactiveRowContains(y: location.y) else {
            return nil
        }
        let overlap = menuPopupAppearance.metrics.submenuOverlap
        if submenuPresentsToRight {
            guard location.x >= -overlap, location.x < 0 else {
                return nil
            }
            return CGPoint(x: 0, y: location.y)
        }
        let width = cachedContentSize.width
        guard location.x >= width,
              location.x < width + overlap else {
            return nil
        }
        return CGPoint(x: max(0, width.nextDown), y: location.y)
    }

    private func interactiveRowContains(y: CGFloat) -> Bool {
        interactiveItemID(atY: y) != nil
    }

    private func interactiveItemID(
        atY y: CGFloat
    ) -> ContextMenuPresentationItem.ID? {
        var rowOrigin = menuPopupAppearance.metrics.panelPadding
        for item in contextMenuPopupRenderedItems(menuItems) {
            let rowHeight = item.isDivider
                ? menuPopupAppearance.metrics.dividerHeight
                : menuPopupAppearance.metrics.rowHeight
            defer { rowOrigin += rowHeight }
            guard y >= rowOrigin, y < rowOrigin + rowHeight else {
                continue
            }
            guard !item.isDivider,
                  !item.isSectionHeader,
                  item.item.isEnabled else {
                return nil
            }
            return item.id
        }
        return nil
    }

    func openSubmenu(
        _ item: ContextMenuPresentationItem,
        at origin: CGPoint,
        selectsFirstItem: Bool = false
    ) {
        // Hover callbacks are queued Update actions. A primary row action ends
        // tracking before invoking its closure, but a hover action from the
        // submenu's final frame may already be queued. Finished-session input
        // is inert; the ID/controller invariant below applies only while the
        // menu tree is still tracking.
        guard menuSession.isActive else { return }
        guard item.item.isEnabled,
              item.isMenu,
              !item.children.isEmpty else {
            return
        }
        if openedSubmenuID == item.id {
            guard let submenu = openedSubmenu,
                  submenu.parentWindow === self else {
                fatalError("ContextMenuWindowController.openSubmenu lost its active submenu")
            }
            if selectsFirstItem {
                submenu.selectFirstKeyboardItem()
            }
            // The platform finishes ordering the clicked parent after this
            // callback. Reassert the existing submenu on the next main-actor
            // turn so that ordering cannot put its parent above it. Overlay
            // children already render above their parent and have no window.
            Task { @MainActor [weak submenu] in
                submenu?.window?.activate()
            }
            return
        }
        let viewPhase = viewGraph.data.withCurrent {
            guard let phase = viewGraph.phaseAttr else {
                fatalError("ContextMenuWindowController.openSubmenu requires an instantiated ViewGraph")
            }
            return ViewGraphHost.Phase(base: phase.value)
        }
        openedSubmenuID = item.id
        openedSubmenu = nil
        dismissAllPresentationChildren()

        let actions = ContextMenuPopupActions()
        let initialKeyboardSelectionID = selectsFirstItem
            ? contextMenuKeyboardSelectableItems(item.children).first?.id
            : nil
        let child = ContextMenuWindowController(content: contextMenuPopupContent(
                                                    items: item.children,
                                                    actions: actions,
                                                    keyboardSelectionID:
                                                        initialKeyboardSelectionID
                                                ),
                                                environment: environment.untrackedCopy(),
                                                viewPhase: viewPhase,
                                                scene: scene,
                                                anchor: origin,
                                                items: item.children,
                                                actions: actions,
                                                usesPlatformWindow: prefersPlatformWindowPresentation,
                                                session: menuSession,
                                                submenuPlacement: ContextMenuSubmenuPlacement(fallbackRightOrigin: origin),
                                                    keyboardSelectionID:
                                                        initialKeyboardSelectionID,
                                                    allowsParentKeyboardTraversal:
                                                    allowsParentKeyboardTraversal)
        openedSubmenu = child
        actions.openSubmenu = { [weak child] item, origin in
            child?.openSubmenu(item, at: origin)
        }
        actions.closeSubmenus = { [weak child] in
            child?.closeSubmenus()
        }
        actions.dismiss = { [weak menuSession] in
            menuSession?.dismissAll()
        }
        addPresentationChild(child: child) { [weak child] attach in
            child?.resolvePresentationWindowAttachment(attach)
        }
        replaceMenuContent(with: menuItems)
    }

    override func presentationFrame(forContentSize size: CGSize) -> CGRect {
        guard let submenuPlacement else {
            return super.presentationFrame(forContentSize: size)
        }
        let rightOrigin = rightSubmenuOrigin(for: submenuPlacement)
        let rightFrame = CGRect(origin: rightOrigin, size: size)
        let leftFrame = CGRect(origin: CGPoint(x: menuPopupAppearance.metrics.submenuOverlap - size.width,
                                               y: rightOrigin.y),
                               size: size)
        guard let available = availableFrameForPresentationPlacement(),
              let rightComparisonFrame = comparisonFrameForPresentationPlacement(rightFrame),
              let leftComparisonFrame = comparisonFrameForPresentationPlacement(leftFrame) else {
            return rightFrame
        }
        let rightOverflow = max(0, rightComparisonFrame.maxX - available.maxX)
        let leftOverflow = max(0, available.minX - leftComparisonFrame.minX)
        let fittedFrame: CGRect
        let fittedComparisonFrame: CGRect
        let presentsToRight: Bool
        // Keep the right side preferred, flip only when the left side has enough
        // room, and otherwise choose the side with more available horizontal
        // room while increasing overlap only by the missing amount.
        if rightOverflow == 0 {
            fittedFrame = rightFrame
            fittedComparisonFrame = rightComparisonFrame
            presentsToRight = true
        } else if leftOverflow == 0 {
            fittedFrame = leftFrame
            fittedComparisonFrame = leftComparisonFrame
            presentsToRight = false
        } else if rightOverflow <= leftOverflow {
            fittedFrame = rightFrame.offsetBy(dx: -rightOverflow, dy: 0)
            fittedComparisonFrame = rightComparisonFrame.offsetBy(dx: -rightOverflow, dy: 0)
            presentsToRight = true
        } else {
            fittedFrame = leftFrame.offsetBy(dx: leftOverflow, dy: 0)
            fittedComparisonFrame = leftComparisonFrame.offsetBy(dx: leftOverflow, dy: 0)
            presentsToRight = false
        }
        submenuPresentsToRight = presentsToRight
        return frameByFittingPresentationFrame(fittedFrame,
                                               comparisonFrame: fittedComparisonFrame,
                                               availableFrame: available,
                                               axes: .vertical)
    }

    private func rightSubmenuOrigin(for placement: ContextMenuSubmenuPlacement) -> CGPoint {
        let fallback = placement.fallbackRightOrigin
        guard let parentWidth = parentWindow?.cachedContentSize.width,
              parentWidth > 0 else {
            return fallback
        }
        // Submenu popup windows overlap their parent by only a few points. Use
        // the laid-out parent popup width because shortcut/title columns resolve
        // after the row callback's provisional origin is built.
        return CGPoint(x: parentWidth - menuPopupAppearance.metrics.submenuOverlap,
                       y: fallback.y)
    }

    // Keep already-open child popups in step with the in-place root item-list
    // refresh instead of rebuilding the whole menu presentation.
    func replaceMenuItems(_ items: [ContextMenuPresentationItem]) {
        menuItems = items
        if let keyboardSelectionID,
           !contextMenuKeyboardSelectableItems(items).contains(where: {
               $0.id == keyboardSelectionID
           }) {
            self.keyboardSelectionID = contextMenuKeyboardSelectableItems(
                items
            ).first?.id
        }
        replaceMenuContent(with: items)
        refreshOpenedSubmenu()
    }

    func closeSubmenus() {
        let hadSubmenu = openedSubmenuID != nil || openedSubmenu != nil
        openedSubmenuID = nil
        openedSubmenu = nil
        dismissAllPresentationChildren()
        if hadSubmenu {
            replaceMenuContent(with: menuItems)
        }
    }

    private func replaceMenuContent(
        with items: [ContextMenuPresentationItem]
    ) {
        guard let contentAttr else { return }
        let graph = viewGraph.graph
        let content = UnsafeSendableBox(AnyView(contextMenuPopupContent(
            items: items,
            actions: popupActions,
            keyboardSelectionID: keyboardSelectionID,
            presentedSubmenuID: openedSubmenuID
        )))
        // Replace child root content through the child graph inbox. The source
        // graph may be evaluating the item list when this refresh is requested.
        graph.inbox.enqueue {
            contentAttr.setValue(content.value)
        }
    }

    private func refreshOpenedSubmenu() {
        guard let openedSubmenuID else { return }
        guard let item = menuItems.first(where: {
            $0.id == openedSubmenuID
        }),
              item.item.isEnabled,
              item.isMenu,
              !item.children.isEmpty else {
            closeSubmenus()
            return
        }
        openedSubmenu?.replaceMenuItems(item.children)
    }

    override func handleKeyboardEvent(
        event: KeyboardEvent,
        at time: Time
    ) -> Bool {
        let stream = KeyboardStream(
            deviceID: event.deviceID,
            key: event.key
        )
        if event.type == .keyUp,
           consumedKeyboardStreams.remove(stream) != nil {
            return true
        }

        // Let the deepest open submenu own the key before this popup examines
        // its own selection. Popup rows use the semantic item model for this
        // route, so the inherited responder dispatch remains only a fallback
        // when no submenu tree is active.
        let routedToSubmenu = openedSubmenu != nil
        if openedSubmenu?.handleKeyboardEvent(event: event, at: time) == true {
            return true
        }
        if event.type == .keyDown,
           handleMenuKeyboardEvent(event) {
            consumedKeyboardStreams.insert(stream)
            return true
        }
        if routedToSubmenu {
            return false
        }
        return super.handleKeyboardEvent(event: event, at: time)
    }

    private func handleMenuKeyboardEvent(_ event: KeyboardEvent) -> Bool {
        let navigationModifiers = event.modifiers.subtracting([
            .capsLock,
            .numericPad,
            .function,
        ])
        if navigationModifiers.isEmpty {
            switch event.key {
            case .up:
                return moveKeyboardSelection(by: -1)
            case .down:
                return moveKeyboardSelection(by: 1)
            case .home:
                return selectKeyboardItem(at: .first)
            case .end:
                return selectKeyboardItem(at: .last)
            case .return, .enter, .space:
                return activateKeyboardSelection()
            case .right:
                if openSelectedKeyboardSubmenu() {
                    return true
                }
                return allowsParentKeyboardTraversal
                    ? forwardMenuBoundaryKeyboardEvent(event)
                    : true
            case .left:
                if let parent = parentWindow
                    as? ContextMenuWindowController {
                    parent.closeKeyboardSubmenu(self)
                    return true
                }
                return allowsParentKeyboardTraversal
                    ? forwardMenuBoundaryKeyboardEvent(event)
                    : true
            case .escape:
                if let parent = parentWindow
                    as? ContextMenuWindowController {
                    parent.closeKeyboardSubmenu(self)
                    return true
                }
                if allowsParentKeyboardTraversal {
                    return forwardMenuBoundaryKeyboardEvent(event)
                }
                menuSession.dismissAll()
                return true
            default:
                break
            }
        }

        let accessModifiers = navigationModifiers.subtracting(.shift)
        guard accessModifiers.isEmpty,
              let character = event.key.shortcutCharacter
                ?? event.text.first,
              let item = keyboardItem(forAccessKey: character) else {
            return false
        }
        setKeyboardSelection(item.id)
        if item.isMenu && !item.children.isEmpty {
            openSubmenu(
                item,
                at: keyboardSubmenuOrigin(for: item),
                selectsFirstItem: true
            )
            return true
        }
        return activateKeyboardSelection()
    }

    private enum KeyboardSelectionEdge {
        case first
        case last
    }

    private func selectKeyboardItem(
        at edge: KeyboardSelectionEdge
    ) -> Bool {
        let items = contextMenuKeyboardSelectableItems(menuItems)
        guard let item = edge == .first ? items.first : items.last else {
            return false
        }
        closeSubmenus()
        setKeyboardSelection(item.id)
        return true
    }

    private func selectFirstKeyboardItem() {
        _ = selectKeyboardItem(at: .first)
    }

    private func moveKeyboardSelection(by offset: Int) -> Bool {
        let items = contextMenuKeyboardSelectableItems(menuItems)
        guard !items.isEmpty else { return false }
        let index = keyboardSelectionID.flatMap { selectedID in
            items.firstIndex(where: { $0.id == selectedID })
        } ?? (offset > 0 ? -1 : 0)
        let nextIndex = (index + offset + items.count) % items.count
        closeSubmenus()
        setKeyboardSelection(items[nextIndex].id)
        return true
    }

    private func setKeyboardSelection(
        _ id: ContextMenuPresentationItem.ID?
    ) {
        guard keyboardSelectionID != id else { return }
        keyboardSelectionID = id
        replaceMenuContent(with: menuItems)
    }

    private func activateKeyboardSelection() -> Bool {
        guard let item = selectedKeyboardItem else { return false }
        if item.isMenu && !item.children.isEmpty {
            openSubmenu(
                item,
                at: keyboardSubmenuOrigin(for: item),
                selectsFirstItem: true
            )
            return true
        }
        guard let action = item.item.selectionBehavior?.onSelect else {
            return false
        }
        closeSubmenus()
        Update.enqueueAction { [weak menuSession] in
            action()
            menuSession?.dismissAll()
        }
        return true
    }

    private func openSelectedKeyboardSubmenu() -> Bool {
        guard let item = selectedKeyboardItem,
              item.isMenu,
              !item.children.isEmpty else {
            return false
        }
        openSubmenu(
            item,
            at: keyboardSubmenuOrigin(for: item),
            selectsFirstItem: true
        )
        return true
    }

    private var selectedKeyboardItem: ContextMenuPresentationItem? {
        guard let keyboardSelectionID else { return nil }
        return contextMenuKeyboardSelectableItems(menuItems).first {
            $0.id == keyboardSelectionID
        }
    }

    private func keyboardItem(
        forAccessKey character: Character
    ) -> ContextMenuPresentationItem? {
        let items = contextMenuKeyboardSelectableItems(menuItems)
        let accessKeys = resolvedMenuAccessKeys(for: items.map { item in
            (
                id: item.id,
                title: (item.item.label ?? item.item.text)?.string ?? ""
            )
        })
        return items.first { item in
            accessKeys[item.id].map {
                menuCharactersAreEquivalent($0, character)
            } == true
        }
    }

    private func keyboardSubmenuOrigin(
        for selectedItem: ContextMenuPresentationItem
    ) -> CGPoint {
        var y = menuPopupAppearance.metrics.panelPadding
        for item in contextMenuPopupRenderedItems(menuItems) {
            if item.id == selectedItem.id { break }
            y += item.isDivider
                ? menuPopupAppearance.metrics.dividerHeight
                : menuPopupAppearance.metrics.rowHeight
        }
        let provisionalPopupWidth = menuPopupAppearance.metrics.plainTitleOrigin
            + menuPopupAppearance.metrics.trailingGap
            + menuPopupAppearance.metrics.submenuIndicatorWidth
            + menuPopupAppearance.metrics.trailingPadding
        return CGPoint(
            x: provisionalPopupWidth - menuPopupAppearance.metrics.submenuOverlap,
            y: y
        )
    }

    private func closeKeyboardSubmenu(
        _ child: ContextMenuWindowController
    ) {
        guard openedSubmenu === child else { return }
        closeSubmenus()
    }

    private func forwardMenuBoundaryKeyboardEvent(
        _ event: KeyboardEvent
    ) -> Bool {
        var owner = parentWindow
        while let menu = owner as? ContextMenuWindowController {
            owner = menu.parentWindow
        }
        return owner?.handleMenuBoundaryKeyboardEvent(event) == true
    }


    override func endPresentationSession() {
        super.endPresentationSession()
        if menuSession.root === self {
            menuSession.finish()
        }
    }

    override func onPresentationChildWindowInactivated() {
        // A menu and its submenus participate in one tracking session. Moving
        // activation back to an ancestor in that session must not dismiss the
        // child; the root still handles activation outside the menu tree.
        if let parent = parentWindow as? ContextMenuWindowController,
           parent.menuSession === menuSession {
            return
        }
        dismiss()
    }
}

private struct ContextMenuKeyboardPresentationDisabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var contextMenuKeyboardPresentationDisabled: Bool {
        get { self[ContextMenuKeyboardPresentationDisabledKey.self] }
        set { self[ContextMenuKeyboardPresentationDisabledKey.self] = newValue }
    }
}

// Keep popup geometry and colors behind one value boundary so a future menu
// appearance can replace them without rewriting the renderer calculations.
private struct MenuPopupAppearance {
    struct Metrics {
        let panelPadding: CGFloat = 5
        let rowHeight: CGFloat = 24
        // Separators allocate a full row separately from the visible hairline.
        let dividerHeight: CGFloat = 11
        let dividerLineHeight: CGFloat = 1
        let dividerHorizontalInset: CGFloat = 16
        let submenuOverlap: CGFloat = 5

        // The row layout is content-driven. Coordinates below are popup-edge
        // based and are converted into row-local positions by subtracting the
        // panel padding.
        let emptyTitleWidth: CGFloat = 16
        let plainTitleOrigin: CGFloat = 17
        let stateTitleOrigin: CGFloat = 25
        let imageTitleOrigin: CGFloat = 37
        let stateImageTitleOrigin: CGFloat = 45
        let plainTrailingPadding: CGFloat = 17
        let trailingGap: CGFloat = 25.5
        let trailingPadding: CGFloat = 15
        let stateSlotOrigin: CGFloat = 8
        let imageSlotOrigin: CGFloat = 15
        let stateImageSlotOrigin: CGFloat = 23
        let sectionHeaderFontSize: CGFloat = 12
        let sectionHeaderYOffset: CGFloat = 2.5
        let checkmarkWidth: CGFloat = 12
        let imageWidth: CGFloat = 16
        let trailingAccessorySpacing: CGFloat = 8
        let submenuIndicatorWidth: CGFloat = 5.5
        let submenuIndicatorHeight: CGFloat = 9.5
    }

    struct Palette {
        let actionForeground = Color(.sRGB, white: 60.0 / 255.0)
        let disabledForeground = Color(.sRGB, white: 135.0 / 255.0)
        let highlightedForeground = Color(.sRGB, white: 252.0 / 255.0)
        let highlightBackground = Color(.sRGB,
                                        red: 63.0 / 255.0,
                                        green: 146.0 / 255.0,
                                        blue: 252.0 / 255.0)
        let inactiveSubmenuBackground = Color(
            .sRGB,
            red: 215.0 / 255.0,
            green: 220.0 / 255.0,
            blue: 225.0 / 255.0
        )
        let separator = Color(.sRGB, white: 156.0 / 255.0)
        let chromeFill = Color(.sRGB, white: 0.96)
        let chromeStroke = Color(.sRGB, white: 0.62, opacity: 0.45)
        let windowBackground = BackendColor(white: 0.96)
    }

    let metrics = Metrics()
    let palette = Palette()
}

private let menuPopupAppearance = MenuPopupAppearance()

// The state/check column is menu-wide, while the image column resets across
// separator-delimited groups.
private struct ContextMenuPopupLayout {
    var showsStateColumn: Bool
    var showsImageColumn: Bool

    static let empty = ContextMenuPopupLayout(showsStateColumn: false,
                                              showsImageColumn: false)

    static func make(for items: [ContextMenuPresentationItem],
                     showsStateColumn: Bool? = nil) -> ContextMenuPopupLayout {
        var groupShowsStateColumn = false
        var showsImageColumn = false
        for item in items where !item.isDivider {
            if item.hasImage {
                showsImageColumn = true
            }
            // Toggle rows reserve the state column even when the current state is off.
            if item.item.toggleState != nil {
                groupShowsStateColumn = true
            }
        }
        return ContextMenuPopupLayout(showsStateColumn: showsStateColumn ?? groupShowsStateColumn,
                                      showsImageColumn: showsImageColumn)
    }

    static func makeRowLayouts(
        for items: [ContextMenuPresentationItem]
    ) -> [ContextMenuPresentationItem.ID: ContextMenuPopupLayout] {
        var result:
            [ContextMenuPresentationItem.ID: ContextMenuPopupLayout] = [:]
        var group: [ContextMenuPresentationItem] = []
        let menuShowsStateColumn = items.contains {
            !$0.isDivider && $0.item.toggleState != nil
        }

        func flushGroup() {
            guard !group.isEmpty else { return }
            let layout = make(for: group,
                              showsStateColumn: menuShowsStateColumn)
            for item in group {
                result[item.id] = layout
            }
            group.removeAll()
        }

        // Only the image column resets per displayed separator group.
        for item in items {
            if item.isDivider {
                flushGroup()
            } else {
                group.append(item)
            }
        }
        flushGroup()
        return result
    }
}

private struct ContextMenuCheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12,
                              y: rect.minY + rect.height * 0.58))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.42,
                                 y: rect.minY + rect.height * 0.86))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.90,
                                 y: rect.minY + rect.height * 0.18))
        return path
    }
}

private struct ContextMenuDividerShape: Shape {
    func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let size = proposal.replacingUnspecifiedDimensions(
            by: CGSize(width: 10,
                       height: menuPopupAppearance.metrics.dividerHeight)
        )
        return CGSize(width: max(0, size.width),
                      height: max(0, size.height))
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lineHeight = min(menuPopupAppearance.metrics.dividerLineHeight,
                             rect.height)
        let y = rect.midY - lineHeight * 0.5
        let lineRect = CGRect(
            x: rect.minX + menuPopupAppearance.metrics.dividerHorizontalInset,
            y: y,
            width: max(
                0,
                rect.width - menuPopupAppearance.metrics.dividerHorizontalInset * 2
            ),
            height: lineHeight
        )
        path.addRect(lineRect)
        return path
    }
}

// Separator items share the popup's resolved menu width even when their own
// content is only a hairline.
private struct ContextMenuPopupColumnLayout: Layout {
    typealias AnimatableData = EmptyAnimatableData

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let intrinsicWidth = sizes.map(\.width).reduce(0, max)
        let width: CGFloat
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            width = max(proposedWidth, intrinsicWidth)
        } else {
            width = intrinsicWidth
        }
        return CGSize(width: width,
                      height: sizes.map(\.height).reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY
        for subview in subviews {
            let rowProposal = ProposedViewSize(width: bounds.width, height: nil)
            let size = subview.sizeThatFits(rowProposal)
            subview.place(at: CGPoint(x: bounds.minX, y: y),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width,
                                                     height: size.height))
            y += size.height
        }
    }
}

// Rows report an intrinsic content-driven width; the parent column layout then
// proposes the resolved menu width back so trailing glyphs share one right edge.
private struct ContextMenuPopupRowLayout: Layout {
    typealias AnimatableData = EmptyAnimatableData

    var layout: ContextMenuPopupLayout
    var hasShortcut: Bool
    var hasSubmenu: Bool
    var isSectionHeader: Bool

    private let stateIndex = 0
    private let imageIndex = 1
    private let titleIndex = 2
    private let shortcutIndex = 3
    private let submenuIndex = 4

    private var titleOrigin: CGFloat {
        let popupOrigin: CGFloat
        switch (layout.showsStateColumn, layout.showsImageColumn) {
        case (true, true):
            popupOrigin = menuPopupAppearance.metrics.stateImageTitleOrigin
        case (true, false):
            popupOrigin = menuPopupAppearance.metrics.stateTitleOrigin
        case (false, true):
            popupOrigin = menuPopupAppearance.metrics.imageTitleOrigin
        case (false, false):
            popupOrigin = menuPopupAppearance.metrics.plainTitleOrigin
        }
        return popupOrigin - menuPopupAppearance.metrics.panelPadding
    }

    private var stateSlotOrigin: CGFloat {
        menuPopupAppearance.metrics.stateSlotOrigin -
            menuPopupAppearance.metrics.panelPadding
    }

    private var imageSlotOrigin: CGFloat {
        let popupOrigin = layout.showsStateColumn
            ? menuPopupAppearance.metrics.stateImageSlotOrigin
            : menuPopupAppearance.metrics.imageSlotOrigin
        return popupOrigin - menuPopupAppearance.metrics.panelPadding
    }

    private var plainTrailingPadding: CGFloat {
        menuPopupAppearance.metrics.plainTrailingPadding -
            menuPopupAppearance.metrics.panelPadding
    }

    private var trailingPadding: CGFloat {
        menuPopupAppearance.metrics.trailingPadding -
            menuPopupAppearance.metrics.panelPadding
    }

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let intrinsic = intrinsicSize(subviews: subviews)
        let width = proposal.width.map { proposed in
            proposed.isFinite ? max(proposed, intrinsic.width) : intrinsic.width
        } ?? intrinsic.width
        return CGSize(width: width,
                      height: menuPopupAppearance.metrics.rowHeight)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let midY = bounds.midY
        if layout.showsStateColumn, subviews.indices.contains(stateIndex) {
            subviews[stateIndex].place(
                at: CGPoint(x: bounds.minX + stateSlotOrigin, y: midY),
                anchor: .leading,
                proposal: ProposedViewSize(
                    width: menuPopupAppearance.metrics.checkmarkWidth,
                    height: menuPopupAppearance.metrics.checkmarkWidth
                )
            )
        }
        if layout.showsImageColumn, subviews.indices.contains(imageIndex) {
            subviews[imageIndex].place(
                at: CGPoint(x: bounds.minX + imageSlotOrigin, y: midY),
                anchor: .leading,
                proposal: ProposedViewSize(
                    width: menuPopupAppearance.metrics.imageWidth,
                    height: menuPopupAppearance.metrics.imageWidth
                )
            )
        }
        if subviews.indices.contains(titleIndex) {
            subviews[titleIndex].place(
                at: CGPoint(x: bounds.minX + titleOrigin,
                            y: midY + (isSectionHeader
                                ? menuPopupAppearance.metrics.sectionHeaderYOffset
                                : 0)),
                anchor: .leading,
                proposal: .unspecified
            )
        }

        let trailingRight = bounds.maxX - trailingPadding
        if hasSubmenu, subviews.indices.contains(submenuIndex) {
            let size = subviews[submenuIndex].sizeThatFits(.unspecified)
            subviews[submenuIndex].place(
                at: CGPoint(x: trailingRight, y: midY),
                anchor: .trailing,
                proposal: ProposedViewSize(size)
            )
        }
        if hasShortcut, subviews.indices.contains(shortcutIndex) {
            let size = subviews[shortcutIndex].sizeThatFits(.unspecified)
            let submenuWidth = hasSubmenu && subviews.indices.contains(submenuIndex)
                ? subviews[submenuIndex].sizeThatFits(.unspecified).width
                : 0
            let right = trailingRight -
                (submenuWidth > 0
                    ? submenuWidth + menuPopupAppearance.metrics.trailingAccessorySpacing
                    : 0)
            subviews[shortcutIndex].place(
                at: CGPoint(x: right, y: midY),
                anchor: .trailing,
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func intrinsicSize(subviews: Subviews) -> CGSize {
        guard subviews.indices.contains(titleIndex) else {
            return CGSize(width: 0,
                          height: menuPopupAppearance.metrics.rowHeight)
        }
        let titleWidth = subviews[titleIndex].sizeThatFits(.unspecified).width
        let trailingWidth = self.trailingWidth(subviews: subviews)
        let rowWidth: CGFloat
        if titleWidth <= 0,
           trailingWidth <= 0,
           !layout.showsStateColumn,
           !layout.showsImageColumn {
            rowWidth = menuPopupAppearance.metrics.emptyTitleWidth -
                menuPopupAppearance.metrics.panelPadding * 2
        } else {
            let titleRight = titleOrigin + titleWidth
            if trailingWidth > 0 {
                rowWidth = titleRight + menuPopupAppearance.metrics.trailingGap +
                    trailingWidth + trailingPadding
            } else {
                rowWidth = titleRight + plainTrailingPadding
            }
        }
        return CGSize(width: max(0, rowWidth),
                      height: menuPopupAppearance.metrics.rowHeight)
    }

    private func trailingWidth(subviews: Subviews) -> CGFloat {
        var width: CGFloat = 0
        if hasShortcut, subviews.indices.contains(shortcutIndex) {
            width += subviews[shortcutIndex].sizeThatFits(.unspecified).width
        }
        if hasSubmenu, subviews.indices.contains(submenuIndex) {
            if width > 0 {
                width += menuPopupAppearance.metrics.trailingAccessorySpacing
            }
            width += subviews[submenuIndex].sizeThatFits(.unspecified).width
        }
        return width
    }
}

private struct ContextMenuSubmenuIndicatorShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

func contextMenuPopupContent(
    items: [ContextMenuPresentationItem],
    actions: ContextMenuPopupActions,
    keyboardSelectionID: ContextMenuPresentationItem.ID? = nil,
    presentedSubmenuID: ContextMenuPresentationItem.ID? = nil
) -> some View {
    ContextMenuPopupView(
        items: items,
        actions: actions,
        keyboardSelectionID: keyboardSelectionID,
        presentedSubmenuID: presentedSubmenuID
    )
}

private func contextMenuPopupRenderedItems(
    _ items: [ContextMenuPresentationItem]
) -> [ContextMenuPresentationItem] {
    var result: [ContextMenuPresentationItem] = []
    var previousWasDivider = false
    for item in items {
        let isDivider = item.isDivider
        // The collected item model can contain consecutive or edge separators.
        // The popup renderer collapses consecutive separators to a single row
        // and suppresses edge separators from visible height.
        if isDivider && (previousWasDivider || result.isEmpty) {
            continue
        }
        result.append(item)
        previousWasDivider = isDivider
    }
    while result.last?.isDivider == true {
        result.removeLast()
    }
    return result
}

func contextMenuKeyboardSelectableItems(
    _ items: [ContextMenuPresentationItem]
) -> [ContextMenuPresentationItem] {
    contextMenuPopupRenderedItems(items).filter { item in
        !item.isDivider
            && !item.isSectionHeader
            && !item.item.isHidden
            && item.item.isEnabled
    }
}

private struct ContextMenuPopupView: View {
    let items: [ContextMenuPresentationItem]
    let actions: ContextMenuPopupActions
    let keyboardSelectionID: ContextMenuPresentationItem.ID?
    let presentedSubmenuID: ContextMenuPresentationItem.ID?

    var body: some View {
        let activeSubmenuID = presentedSubmenuID.flatMap { id in
            items.contains { item in
                item.id == id
                    && item.item.isEnabled
                    && item.isMenu
                    && !item.children.isEmpty
            } ? id : nil
        }
        ContextMenuPopupPanel(
            items: items,
            activeItemID: activeSubmenuID,
            keyboardSelectionID: keyboardSelectionID,
            isActivated: actions.isActivated,
            dismiss: {
                actions.dismiss?()
            },
            pointerInteractionBegan: {
                actions.pointerInteractionBegan?()
            },
            openSubmenu: { item, origin in
                guard item.item.isEnabled,
                      item.isMenu,
                      !item.children.isEmpty else {
                    return
                }
                actions.openSubmenu?(item, origin)
            },
            clearSubmenus: {
                actions.closeSubmenus?()
            },
            menuHoverChanged: { hovering in
                actions.menuHoverChanged?(hovering)
            },
            submenuRowHoverChanged: { id, hovering in
                actions.submenuRowHoverChanged?(id, hovering)
            }
        )
        .fixedSize()
    }
}

private struct ContextMenuPopupPanel: View {
    let items: [ContextMenuPresentationItem]
    let activeItemID: ContextMenuPresentationItem.ID?
    let keyboardSelectionID: ContextMenuPresentationItem.ID?
    let isActivated: Bool
    let dismiss: () -> Void
    let pointerInteractionBegan: () -> Void
    let openSubmenu: (ContextMenuPresentationItem, CGPoint) -> Void
    let clearSubmenus: () -> Void
    let menuHoverChanged: (Bool) -> Void
    let submenuRowHoverChanged:
        (ContextMenuPresentationItem.ID, Bool) -> Void
    private var renderedItems: [ContextMenuPresentationItem] {
        contextMenuPopupRenderedItems(items)
    }
    private var rowLayouts:
        [ContextMenuPresentationItem.ID: ContextMenuPopupLayout] {
        ContextMenuPopupLayout.makeRowLayouts(for: renderedItems)
    }
    private var accessKeys:
        [ContextMenuPresentationItem.ID: Character] {
        resolvedMenuAccessKeys(for: renderedItems.compactMap { item in
            guard !item.isDivider, !item.isSectionHeader else { return nil }
            let title = (item.item.label ?? item.item.text)?.string ?? ""
            return (id: item.id, title: title)
        })
    }

    private func rowTopOffset(
        for id: ContextMenuPresentationItem.ID
    ) -> CGFloat {
        var offset = menuPopupAppearance.metrics.panelPadding
        for item in renderedItems {
            if item.id == id { return offset }
            offset += item.isDivider
                ? menuPopupAppearance.metrics.dividerHeight
                : menuPopupAppearance.metrics.rowHeight
        }
        return menuPopupAppearance.metrics.panelPadding
    }

    private func submenuOrigin(
        for item: ContextMenuPresentationItem
    ) -> CGPoint {
        let provisionalPopupWidth = menuPopupAppearance.metrics.plainTitleOrigin +
            menuPopupAppearance.metrics.trailingGap +
            menuPopupAppearance.metrics.submenuIndicatorWidth +
            menuPopupAppearance.metrics.trailingPadding
        return CGPoint(x: provisionalPopupWidth -
            menuPopupAppearance.metrics.submenuOverlap,
                       y: rowTopOffset(for: item.id))
    }

    var body: some View {
        let renderedItems = self.renderedItems
        let rowLayouts = self.rowLayouts
        let accessKeys = self.accessKeys
        ContextMenuPopupColumnLayout {
            ForEach(renderedItems) { item in
                ContextMenuPopupRow(item: item,
                                    layout: rowLayouts[item.id] ?? .empty,
                                    isSubmenuOpen: activeItemID == item.id,
                                    isMenuActivated: isActivated,
                                    isKeyboardSelected:
                                        keyboardSelectionID == item.id,
                                    accessKey: accessKeys[item.id],
                                    showsAccessKey:
                                        keyboardSelectionID != nil,
                                    submenuOrigin: submenuOrigin(for: item),
                                    dismiss: dismiss,
                                    pointerInteractionBegan:
                                        pointerInteractionBegan,
                                    openSubmenu: openSubmenu,
                                    clearSubmenus: clearSubmenus,
                                    submenuRowHoverChanged:
                                        submenuRowHoverChanged)
            }
        }
        // Rows own the horizontal panel padding as interaction space while
        // their visual backgrounds remain inset. Vertical padding stays
        // panel-only so moving above or below a row ends that row's hover.
        .padding(.vertical, menuPopupAppearance.metrics.panelPadding)
        .fixedSize()
        .onHover(perform: menuHoverChanged)
    }
}

private struct ContextMenuPopupRow: View {
    let item: ContextMenuPresentationItem
    let layout: ContextMenuPopupLayout
    let isSubmenuOpen: Bool
    let isMenuActivated: Bool
    let isKeyboardSelected: Bool
    let accessKey: Character?
    let showsAccessKey: Bool
    let submenuOrigin: CGPoint
    let dismiss: () -> Void
    let pointerInteractionBegan: () -> Void
    let openSubmenu: (ContextMenuPresentationItem, CGPoint) -> Void
    let clearSubmenus: () -> Void
    let submenuRowHoverChanged:
        (ContextMenuPresentationItem.ID, Bool) -> Void
    @State private var isPressed = false
    @State private var isHovered = false

    private var hasSubmenu: Bool {
        item.isMenu && !item.children.isEmpty
    }

    private var isSectionHeader: Bool {
        item.isSectionHeader
    }

    private var isToggleOn: Bool {
        item.item.toggleState == .on
    }

    private var shortcut: KeyboardShortcut? {
        item.item.resolvedKeyboardShortcut
    }

    private var rowBackground: Color {
        if isDirectlyHighlighted {
            return menuPopupAppearance.palette.highlightBackground
        }
        if isSubmenuOpen, !isMenuActivated {
            // The pointer is tracking a descendant popup. Its parent row keeps
            // an inactive selection instead of the accent-colored hover state.
            return menuPopupAppearance.palette.inactiveSubmenuBackground
        }
        return .clear
    }

    private var rowForeground: Color {
        if isDirectlyHighlighted {
            return menuPopupAppearance.palette.highlightedForeground
        }
        if isSectionHeader || !item.item.isEnabled {
            // Static Text/Label menu rows are disabled platform items and render
            // with disabled foreground, not a normal actionable-row foreground.
            return menuPopupAppearance.palette.disabledForeground
        }
        return menuPopupAppearance.palette.actionForeground
    }

    private var isDirectlyHighlighted: Bool {
        guard !item.isDivider,
              !isSectionHeader,
              item.item.isEnabled else {
            return false
        }
        if showsAccessKey {
            return isKeyboardSelected || (isSubmenuOpen && hasSubmenu)
        }
        // A row-local hover can outlive its platform window's event binding
        // while the pointer transfers into a child popup. Only the popup that
        // currently owns menu activation may draw that pointer highlight.
        return isMenuActivated && (isHovered || isPressed)
    }

    var body: some View {
        if item.isDivider {
            ContextMenuDividerShape()
                .fill(menuPopupAppearance.palette.separator)
                .frame(height: menuPopupAppearance.metrics.dividerHeight)
                .padding(.horizontal,
                         menuPopupAppearance.metrics.panelPadding)
        } else {
            ContextMenuPopupRowLayout(layout: layout,
                                      hasShortcut: shortcut != nil,
                                      hasSubmenu: hasSubmenu,
                                      isSectionHeader: isSectionHeader) {
                if layout.showsStateColumn {
                    ContextMenuCheckmarkShape()
                        .stroke(isToggleOn ? rowForeground : .clear,
                                style: StrokeStyle(lineWidth: 1.6,
                                                   lineCap: .round,
                                                   lineJoin: .round))
                        .frame(width: menuPopupAppearance.metrics.checkmarkWidth,
                               height: menuPopupAppearance.metrics.checkmarkWidth,
                               alignment: .center)
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
                if layout.showsImageColumn {
                    if item.hasImage {
                        item.image
                            .frame(width: menuPopupAppearance.metrics.imageWidth,
                                   height: menuPopupAppearance.metrics.imageWidth,
                                   alignment: .center)
                    } else {
                        Color.clear
                            .frame(width: menuPopupAppearance.metrics.imageWidth,
                                   height: menuPopupAppearance.metrics.imageWidth)
                    }
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
                menuItemTitle
                    .font(isSectionHeader
                        ? .system(size: menuPopupAppearance.metrics.sectionHeaderFontSize)
                        : nil)
                    .fixedSize(horizontal: true, vertical: false)
                if let shortcut {
                    MenuKeyboardShortcutLabel(shortcut: shortcut)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
                if hasSubmenu {
                    ContextMenuSubmenuIndicatorShape()
                        .fill(rowForeground)
                        .frame(width: menuPopupAppearance.metrics.submenuIndicatorWidth,
                               height: menuPopupAppearance.metrics.submenuIndicatorHeight)
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
            }
            .foregroundStyle(rowForeground)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 4))
            // Native menu row tracking extends horizontally beyond the
            // highlighted ink to the popup edges, but not vertically into the
            // panel's top or bottom padding.
            .padding(.horizontal, menuPopupAppearance.metrics.panelPadding)
            // The rounded highlight is visual only. Menu selection covers the
            // complete horizontally expanded row rectangle, including its
            // transparent corner pixels and side padding.
            .contentShape(Rectangle())
            ._onButtonGesture(pressing: { pressing in
                guard !isSectionHeader else {
                    isPressed = false
                    return
                }
                isPressed = pressing
                if pressing {
                    pointerInteractionBegan()
                }
                if pressing, item.item.isEnabled, hasSubmenu {
                    openSubmenu(item, submenuOrigin)
                }
            }, perform: {
                guard !isSectionHeader, item.item.isEnabled else {
                    return
                }
                if hasSubmenu {
                    // Plain submenu rows keep the current menu tree open. A
                    // collected parent selection is momentary: close the whole
                    // tree before invoking its primary action.
                    guard let action =
                        item.item.selectionBehavior?.onSelect else {
                        return
                    }
                    dismiss()
                    action()
                    return
                }
                clearSubmenus()
                guard let action =
                    item.item.selectionBehavior?.onSelect else {
                    return
                }
                action()
                dismiss()
            })
            .onHover { hovering in
                guard !isSectionHeader, item.item.isEnabled else {
                    isHovered = false
                    return
                }
                isHovered = hovering
                if hasSubmenu {
                    submenuRowHoverChanged(item.id, hovering)
                }
                guard hovering else { return }
                pointerInteractionBegan()
                if hasSubmenu {
                    openSubmenu(item, submenuOrigin)
                } else {
                    clearSubmenus()
                }
            }
            .environment(\.isEnabled, item.item.isEnabled)
        }
    }

    private var menuItemTitle: Text {
        guard showsAccessKey,
              let title = (item.item.label ?? item.item.text)?.string else {
            return platformItemText(item.item)
        }
        return menuAccessKeyText(
            title,
            accessKey: accessKey,
            showsAccessKey: true
        )
    }
}
