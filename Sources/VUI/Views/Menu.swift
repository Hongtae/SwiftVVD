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
        ResolvedMenuStyle(
            primaryAction: primaryAction,
            onPresentationChanged: onPresentationChanged
        )
            .viewAlias(MenuStyleConfiguration.Label.self) {
                label
            }
            .viewAlias(MenuStyleConfiguration.Content.self) {
                content
                    .modifier(
                        SectionStyleModifier(
                            style: DefaultSectionStyle()
                        )
                    )
                    .modifier(
                        LabelStyleWritingModifier(
                            style: DefaultLabelStyle()
                        )
                    )
                    .environment(
                        \.menuIndicatorVisibility,
                        .automatic
                    )
                    .input(LabelVisibilityConfigured.self)
                    .modifier(
                        StyleContextWriter<MenuStyleContext>()
                    )
            }
            .modifier(
                StaticIf<
                    StyleContextAcceptsPredicate<MenuStyleContext>,
                    MenuStyleModifier<PlatformItemListMenuStyle>,
                    EmptyModifier
                >(
                    trueBody: MenuStyleModifier(
                        style: PlatformItemListMenuStyle()
                    ),
                    falseBody: EmptyModifier()
                )
            )
    }
}

struct LabelVisibilityConfigured: ViewInputBoolFlag {
    typealias Value = Bool
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


struct ResolvedMenuStyle: StyleableView {
    typealias Configuration = MenuStyleConfiguration
    var configuration: MenuStyleConfiguration

    init(primaryAction: (() -> Void)? = nil,
         onPresentationChanged: ((Bool) -> Void)? = nil) {
        self.configuration = MenuStyleConfiguration(
            primaryAction: primaryAction,
            onPresentationChanged: onPresentationChanged
        )
    }

    var body: some View {
        Menu(configuration)
    }

    typealias DefaultStyleModifier = MenuStyleModifier<DefaultMenuStyle>
    static var defaultStyleModifier: MenuStyleModifier<DefaultMenuStyle> {
        MenuStyleModifier(style: DefaultMenuStyle())
    }
}

struct MenuControlModifier<MenuContent>: ViewModifier, MultiViewModifier where MenuContent: View {
    typealias Body = Never
    let content: MenuContent
    var primaryAction: (() -> Void)? = nil
    var menuIndicatorWidth: CGFloat = 0
    var onMenuOpenChanged: ((Bool) -> Void)? = nil
    var onPrimaryPressingChanged: ((Bool) -> Void)? = nil
    var onMenuPressingChanged: ((Bool) -> Void)? = nil
    var onPresentationChanged: ((Bool) -> Void)? = nil
}

extension MenuControlModifier {
    fileprivate var _scene: some Scene { _EmptyScene() }
}

extension MenuControlModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("MenuControlModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)
        guard inputs.preferences.keys.contains(ViewRespondersKey.self) else {
            return outputs
        }

        let innerResponderNodes = outputs.preferences.preferences
            .filter { $0.key == ViewRespondersKey.self }
            .map { $0.value }

        let innerRespondersAttr: Attribute<[ViewResponder]>
        if innerResponderNodes.isEmpty {
            innerRespondersAttr = graph.makeInput(value: [])
        } else if innerResponderNodes.count == 1 {
            innerRespondersAttr = Attribute<[ViewResponder]>(innerResponderNodes[0])
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

        let itemListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(
            PlatformItemListGenerator<AllPlatformItemListFlags, MenuContent>(
                content: modifier[\.content]._attribute,
                inputs: inputs,
                inputsIncludeGeometry: true
            )
        )
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let responderAttr: Attribute<[ViewResponder]> = graph.makeStatefulRule(
            MenuControlResponderFilter(
                _modifier: modifier._attribute,
                _itemList: itemListAttr,
                _environment: environmentAttr,
                _phase: inputs.base.phase,
                _position: inputs.position,
                _size: inputs.size,
                _transform: inputs.transform,
                _children: innerRespondersAttr,
                _responder: nil
            )
        )

        // Standalone Menu installs a dropdown responder; nested Menu under
        // MenuStyleContext remains PlatformItemListMenuStyle collection.
        outputs.preferences.preferences.removeAll { $0.key == ViewRespondersKey.self }
        outputs.preferences.append(ViewRespondersKey.self, node: responderAttr.identifier)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("MenuControlModifier._makeViewList called outside AG context")
        }
        // Keep the control modifier attached when a Menu style body is
        // materialized as a list child.
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

private let _menuControlResponderNextKey = Mutex<UInt32>(0x91000000)

struct MenuControlResponderFilter<MenuContent: View>: StatefulRule {
    typealias Value = [ViewResponder]

    var _modifier: Attribute<MenuControlModifier<MenuContent>>
    var _itemList: Attribute<PlatformItemList>
    var _environment: Attribute<EnvironmentValues>
    var _phase: Attribute<_GraphInputs.Phase>
    var _position: Attribute<CGPoint>
    var _size: Attribute<ViewSize>
    var _transform: Attribute<ViewTransform>
    var _children: Attribute<[ViewResponder]>
    var _responder: MenuControlResponder?

    mutating func updateValue() {
        let isInitialValue = !context.hasValue
        if _responder == nil {
            _responder = MenuControlResponder(
                itemList: _itemList,
                environment: _environment,
                phase: _phase
            )
        }
        guard let responder = _responder else {
            fatalError("MenuControlResponderFilter failed to create its responder")
        }

        let modifier = _modifier.value
        let environment = _environment.value
        responder.helper.update(
            data: (
                value: TrivialContentResponder(),
                changed: false
            ),
            size: (
                value: _size.value,
                changed: _AGGraph.currentStatefulInputChanged(_size.identifier)
            ),
            position: (
                value: _position.value,
                changed: _AGGraph.currentStatefulInputChanged(_position.identifier)
            ),
            transform: (
                value: _transform.value,
                changed: _AGGraph.currentStatefulInputChanged(_transform.identifier)
            ),
            parent: responder
        )
        responder.isEnabled = environment.isEnabled
        responder.primaryAction = modifier.primaryAction
        responder.menuIndicatorWidth = modifier.menuIndicatorWidth
        responder.onMenuOpenChanged = modifier.onMenuOpenChanged
        responder.onPrimaryPressingChanged = modifier.onPrimaryPressingChanged
        responder.onMenuPressingChanged = modifier.onMenuPressingChanged
        responder.onPresentationChanged = modifier.onPresentationChanged

        let childrenChanged = isInitialValue
            || _AGGraph.currentStatefulInputChanged(_children.identifier)
        if childrenChanged {
            responder.updateChildren((
                value: _children.value,
                changed: true
            ))
        }
        _AGGraph.setStatefulOutput([responder])
    }
}

final class MenuControlResponder: MultiViewResponder,
    ExclusiveResponderEventConsumer {
    private enum EventSessionKind {
        case primaryAction
        case menu
        case dismissMenu
    }

    private struct EventSession {
        var eventID: EventID
        var kind: EventSessionKind
    }

    let hitTestKey: UInt32

    let itemList: Attribute<PlatformItemList>
    let environment: Attribute<EnvironmentValues>
    let phase: Attribute<_GraphInputs.Phase>

    var helper = ContentResponderHelper<TrivialContentResponder>()
    var isEnabled: Bool?
    var primaryAction: (() -> Void)?
    var menuIndicatorWidth: CGFloat = 0
    var onMenuOpenChanged: ((Bool) -> Void)?
    var onPrimaryPressingChanged: ((Bool) -> Void)?
    var onMenuPressingChanged: ((Bool) -> Void)?
    var onPresentationChanged: ((Bool) -> Void)?

    private var isMenuOpen = false
    private(set) var isPrimaryPressing = false
    private(set) var isMenuPressing = false
    private var eventSession: EventSession?
    private var activeSession: ContextMenuPresentationSession?

    init(itemList: Attribute<PlatformItemList>,
         environment: Attribute<EnvironmentValues>,
         phase: Attribute<_GraphInputs.Phase>) {
        self.hitTestKey = _menuControlResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.itemList = itemList
        self.environment = environment
        self.phase = phase
        super.init()
    }

    override func hitTestPolicy(options: ViewResponder.ContainsPointsOptions) -> ViewResponder.HitTestPolicy {
        isEnabled != false || options.contains(.allowDisabledViews)
            ? .include
            : .exclude
    }

    override func containsGlobalPoints(_ points: [CGPoint],
                                       cacheKey: UInt32?,
                                       options: ViewResponder.ContainsPointsOptions) -> ViewResponder.ContainsPointsResult {
        guard hitTestPolicy(options: options) != .exclude else {
            return .stop
        }
        return helper.containsGlobalPoints(
            points,
            cacheKey: cacheKey,
            options: options,
            children: children
        )
    }

    override var features: Features {
        [.platformViews, .gestures]
    }

    var menuIsOpen: Bool {
        isMenuOpen
    }

    func acceptsEventType(_ eventType: Any.Type) -> Bool {
        guard isEnabled != false else { return false }
        return eventType == MouseEvent.self || eventType == TouchEvent.self
    }

    func exclusivelyConsumes(_ event: any EventType) -> Bool {
        controlPointerEvent(event) != nil
    }

    func consumeEvents(
        _ events: [EventID: any EventType],
        at _: Time
    ) -> GesturePhase<Void> {
        guard let parent = host as? WindowController else {
            resetEventSession()
            return .failed
        }

        var result: GesturePhase<Void> = .possible(nil)
        parent.viewGraph.data.withCurrent {
            for (eventID, event) in events.sorted(by: {
                $0.key.serial < $1.key.serial
            }) {
                guard let pointer = controlPointerEvent(event) else {
                    continue
                }
                let phase = consumePointerEvent(
                    id: eventID,
                    phase: pointer.phase,
                    location: pointer.location,
                    parent: parent
                )
                if phase.isActive {
                    result = phase
                } else if phase.isEnded && !result.isActive {
                    result = phase
                } else if phase.isFailed && result.isPossible {
                    result = phase
                }
            }
        }
        return result
    }

    func resetEventSession() {
        guard let eventSession else { return }
        self.eventSession = nil
        switch eventSession.kind {
        case .primaryAction:
            setPrimaryPressing(false)
        case .menu:
            setMenuPressing(false)
        case .dismissMenu:
            break
        }
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
        guard isEnabled != false else { return }
        guard let graph = _AGGraph.current else {
            fatalError("MenuControlResponder.present called outside AG context")
        }
        let viewPhase = ViewGraphHost.Phase(base: phase.value)

        graph.inbox.drain()
        graph.drainActions()
        parent.dismissAllPresentationChildren()

        let session = ContextMenuPresentationSession()
        let actions = ContextMenuPopupActions()
        let initialItems = contextMenuPresentationItems(
            itemList.value.menuItems
        )
        let liveContentSubgraph = AGSubgraph()
        AGSubgraph.withCurrent(liveContentSubgraph) {
            graph.makeSideEffectRule { [weak session] in
                let items = contextMenuPresentationItems(
                    self.itemList.value.menuItems
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
        session.onFinish = { [weak self, weak session] in
            guard let self, self.activeSession === session else { return }
            self.activeSession = nil
            self.setMenuOpen(false)
        }
        activeSession = session
        setMenuOpen(true)

        let ctrl = ContextMenuWindowController(content: contextMenuPopupContent(items: initialItems,
                                                                                actions: actions),
                                               environment: environment.value.untrackedCopy(),
                                               viewPhase: viewPhase,
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
        let hasPrimaryAction = primaryAction != nil
        let indicatorWidth = min(
            max(menuIndicatorWidth, 0),
            helper.size.width
        )
        // Split controls present from the indicator segment and overlap the
        // control edge slightly. A menu-only control keeps its full-control
        // anchor.
        var points = [CGPoint(
            x: hasPrimaryAction
                ? helper.size.width - indicatorWidth
                : 0,
            y: hasPrimaryAction
                ? max(0, helper.size.height - 3)
                : helper.size.height
        )]
        helper.transform.convertGlobal(from: .local, points: &points)
        return points[0]
    }

    private func setMenuOpen(_ open: Bool) {
        guard isMenuOpen != open else { return }
        isMenuOpen = open
        onMenuOpenChanged?(open)
        setMenuPressing(open)
        onPresentationChanged?(open)
    }

    private func controlPointerEvent(
        _ event: any EventType
    ) -> (phase: EventPhase, location: CGPoint)? {
        if let event = event as? MouseEvent {
            guard event.button == .primary else { return nil }
            return (event.phase, event.globalLocation)
        }
        if let event = event as? TouchEvent {
            return (event.phase, event.globalLocation)
        }
        return nil
    }

    private func consumePointerEvent(
        id eventID: EventID,
        phase: EventPhase,
        location: CGPoint,
        parent: WindowController
    ) -> GesturePhase<Void> {
        switch phase {
        case .began:
            if let eventSession, eventSession.eventID != eventID {
                resetEventSession()
            }
            guard eventSession == nil else { return .active(()) }

            if isMenuOpen {
                eventSession = EventSession(
                    eventID: eventID,
                    kind: .dismissMenu
                )
                dismissMenu()
                return .active(())
            }

            if primaryAction != nil && containsPrimarySegment(location) {
                eventSession = EventSession(
                    eventID: eventID,
                    kind: .primaryAction
                )
                setPrimaryPressing(true)
                return .active(())
            }

            eventSession = EventSession(eventID: eventID, kind: .menu)
            present(from: parent)
            return .active(())

        case .active:
            guard let eventSession, eventSession.eventID == eventID else {
                return .possible(nil)
            }
            if eventSession.kind == .primaryAction {
                setPrimaryPressing(
                    isEnabled != false && containsPrimarySegment(location)
                )
            }
            return .active(())

        case .ended:
            guard let eventSession, eventSession.eventID == eventID else {
                return .possible(nil)
            }
            self.eventSession = nil
            switch eventSession.kind {
            case .primaryAction:
                let performsAction = isEnabled != false &&
                    containsPrimarySegment(location)
                setPrimaryPressing(false)
                if performsAction {
                    primaryAction?()
                }
            case .menu, .dismissMenu:
                break
            }
            return .ended(())

        case .failed:
            guard let eventSession, eventSession.eventID == eventID else {
                return .possible(nil)
            }
            resetEventSession()
            return .ended(())
        }
    }

    private func containsPrimarySegment(_ globalLocation: CGPoint) -> Bool {
        guard primaryAction != nil else { return false }
        var points = [globalLocation]
        helper.transform.convertGlobal(to: .local, points: &points)
        guard let point = points.first,
              CGRect(origin: .zero, size: helper.size).contains(point) else {
            return false
        }
        let indicatorWidth = min(
            max(menuIndicatorWidth, 0),
            helper.size.width
        )
        return point.x < helper.size.width - indicatorWidth
    }

    private func setPrimaryPressing(_ pressing: Bool) {
        guard isPrimaryPressing != pressing else { return }
        isPrimaryPressing = pressing
        onPrimaryPressingChanged?(pressing)
    }

    private func setMenuPressing(_ pressing: Bool) {
        guard isMenuPressing != pressing else { return }
        isMenuPressing = pressing
        onMenuPressingChanged?(pressing)
    }
}
