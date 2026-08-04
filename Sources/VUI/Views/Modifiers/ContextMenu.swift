//
//  File: ContextMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Synchronization
import VVD

struct ContextMenuModifier<MenuContent>: ViewModifier, MultiViewModifier where MenuContent: View {
    typealias Body = Never
    
    let menuView: MenuContent
    var isPresented: Binding<Bool>? = nil
    var _keyboardPresentationDisabled: Environment<Bool> =
        Environment(\.contextMenuKeyboardPresentationDisabled)
}

public enum ContextMenuTriggerPolicy: Equatable, Sendable {
    case automatic
    case secondaryDown
    case secondaryUpInside
    case longPress
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

extension ContextMenuModifier {
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
        let responder = ContextMenuResponder(
            itemList: itemListAttr,
            isPresented: modifier[\.isPresented]._attribute.value,
            environment: inputs.base.cachedEnvironment.value.environment,
            phase: inputs.base.phase,
            transform: inputs.transform,
            size: inputs.size
        )
        let isPresentedAttr = modifier[\.isPresented]._attribute
        graph.makeSideEffectRule { [weak responder] in
            responder?.snapshotTransform = inputs.transform.value
            responder?.snapshotSize = inputs.size.value
            responder?.updatePresentation(isPresentedAttr.value)
        }

        let respondersAttr: Attribute<[ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)
        return outputs
    }

    // Keep the modifier attached to each materialized list element. Without this,
    // contextMenu disappears when applied to children inside HStack/VStack/etc.
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard _AGGraph.current != nil else {
            fatalError("ContextMenuModifier._makeViewList called outside AG context")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

extension ContextMenuModifier {
    fileprivate var _scene: some Scene {
        _EmptyScene()
    }
}

private let _contextMenuResponderNextKey = Mutex<UInt32>(0x90000000)

final class ContextMenuResponder: ViewResponder {
    let hitTestKey: UInt32

    let itemList: Attribute<PlatformItemList>
    private var isPresented: Binding<Bool>?
    private var activeSession: ContextMenuPresentationSession?
    let environment: Attribute<EnvironmentValues>
    let phase: Attribute<Phase>
    let transform: Attribute<ViewTransform>
    let size: Attribute<ViewSize>

    var snapshotTransform: ViewTransform = .identity
    var snapshotSize: ViewSize = ViewSize(.zero)

    init(itemList: Attribute<PlatformItemList>,
         isPresented: Binding<Bool>?,
         environment: Attribute<EnvironmentValues>,
         phase: Attribute<Phase>,
         transform: Attribute<ViewTransform>,
         size: Attribute<ViewSize>) {
        self.hitTestKey = _contextMenuResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.itemList = itemList
        self.isPresented = isPresented
        self.environment = environment
        self.phase = phase
        self.transform = transform
        self.size = size
        super.init()
    }

    override func hitTestPolicy(options: ViewResponder.ContainsPointsOptions) -> ViewResponder.HitTestPolicy {
        .include
    }

    override func containsGlobalPoints(_ points: [CGPoint],
                                       cacheKey: UInt32?,
                                       options: ViewResponder.ContainsPointsOptions) -> ViewResponder.ContainsPointsResult {
        let sz = snapshotSize.value
        var localPts = Array(points.prefix(64))
        snapshotTransform.convertGlobal(to: .local, points: &localPts)
        let bounds = CGRect(origin: .zero, size: sz)
        var mask = BitVector64()
        for (i, point) in localPts.enumerated() {
            mask[i] = bounds.contains(point)
        }
        guard !mask.isEmpty else { return .stop }
        return ViewResponder.ContainsPointsResult(mask: mask, priority: 16.0, children: [])
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
        let viewPhase = ViewGraphHost.Phase(base: phase.value)
        // Flush pending item-list mutations before taking the initial popup
        // snapshot. The open menu should start from the same source state that
        // future live refreshes will observe.
        graph.inbox.drain()
        graph.drainActions()
        parent.dismissAllPresentationChildren()
        let session = ContextMenuPresentationSession()
        let actions = ContextMenuPopupActions()
        let initialItems = self.itemList.value.menuItems
        let liveContentSubgraph = AGSubgraph()
        AGSubgraph.withCurrent(liveContentSubgraph) {
            // Update the already-open popup root content when the collected
            // item-list source invalidates. The session owns this subgraph so
            // dismissing the menu also stops the source-graph side effect.
            graph.makeSideEffectRule { [weak session] in
                let items = self.itemList.value.menuItems
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
        let usesPlatformWindow = environment.value.presentationChildUsingPlatformWindow
        let ctrl = ContextMenuWindowController(content: contextMenuPopupContent(items: initialItems,
                                                                                actions: actions),
                                               environment: environment.value.untrackedCopy(),
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

    func resolvedTriggerPolicy(for device: MouseEventDevice) -> ContextMenuTriggerPolicy {
        let policy = environment.value.contextMenuTriggerPolicy
        guard policy == .automatic else {
            return policy
        }
        switch device {
        case .touch, .stylus:
            return .longPress
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
    private weak var sourceGraph: _AGGraph?
    private var liveContentSubgraph: AGSubgraph?
    private var isPresented: Binding<Bool>?
    private var didFinish = false

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

final class ContextMenuPopupActions {
    var openSubmenu: ((PlatformItemList.Item, CGPoint) -> Void)?
    var closeSubmenus: (() -> Void)?
    var dismiss: (() -> Void)?
}

struct ContextMenuSubmenuPlacement {
    var fallbackRightOrigin: CGPoint
}

// Context menus are popup presentation children, not a separate window family.
// PopupWindowController supplies the .popupWindow style plus parent
// deactivate/move dismissal policy; this subclass only owns menu-session state,
// submenu fan-out, and context-menu-specific teardown.
final class ContextMenuWindowController: PopupWindowController, @unchecked Sendable {
    private var contentAttr: Attribute<AnyView>?
    private let popupActions: ContextMenuPopupActions
    private let menuSession: ContextMenuPresentationSession
    private let submenuPlacement: ContextMenuSubmenuPlacement?
    private var menuItems: [PlatformItemList.Item]
    private var openedSubmenuID: AnyHashable?
    private weak var openedSubmenu: ContextMenuWindowController?

    init<Content: View>(content: Content,
         environment: EnvironmentValues,
         viewPhase: ViewGraphHost.Phase,
         scene: WindowKey,
         anchor: CGPoint,
         items: [PlatformItemList.Item],
         actions: ContextMenuPopupActions,
         usesPlatformWindow: Bool,
         session: ContextMenuPresentationSession,
         submenuPlacement: ContextMenuSubmenuPlacement? = nil) {
        self.popupActions = actions
        self.menuSession = session
        self.submenuPlacement = submenuPlacement
        self.menuItems = items
        let frame = CGRect(origin: anchor, size: .zero)
        super.init(content: content,
                   environment: environment,
                   viewPhase: viewPhase,
                   scene: scene,
                   usesPlatformWindow: usesPlatformWindow,
                   frameInParent: frame)
        self.contentAttr = viewGraph.rootAnyViewContentInput
    }

    func openSubmenu(_ item: PlatformItemList.Item, at origin: CGPoint) {
        guard item.isEnabled, !item.children.isEmpty else { return }
        guard openedSubmenuID != item.id else { return }
        guard _AGGraph.current != nil else {
            fatalError("ContextMenuWindowController.openSubmenu called outside AG context")
        }
        guard let phase = viewGraph.phaseAttr else {
            fatalError("ContextMenuWindowController.openSubmenu requires an instantiated ViewGraph")
        }
        let viewPhase = ViewGraphHost.Phase(base: phase.value)
        openedSubmenuID = item.id
        openedSubmenu = nil
        dismissAllPresentationChildren()

        let actions = ContextMenuPopupActions()
        let child = ContextMenuWindowController(content: ContextMenuPopupView(items: item.children,
                                                                              actions: actions),
                                                environment: environment.untrackedCopy(),
                                                viewPhase: viewPhase,
                                                scene: scene,
                                                anchor: origin,
                                                items: item.children,
                                                actions: actions,
                                                usesPlatformWindow: prefersPlatformWindowPresentation,
                                                session: menuSession,
                                                submenuPlacement: ContextMenuSubmenuPlacement(fallbackRightOrigin: origin))
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
    }

    override func presentationFrame(forContentSize size: CGSize) -> CGRect {
        guard let submenuPlacement else {
            return super.presentationFrame(forContentSize: size)
        }
        let rightOrigin = rightSubmenuOrigin(for: submenuPlacement)
        let rightFrame = CGRect(origin: rightOrigin, size: size)
        let leftFrame = CGRect(origin: CGPoint(x: contextMenuPopupSubmenuOverlap - size.width,
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
        // Keep the right side preferred, flip only when the left side has enough
        // room, and otherwise choose the side with more available horizontal
        // room while increasing overlap only by the missing amount.
        if rightOverflow == 0 {
            fittedFrame = rightFrame
            fittedComparisonFrame = rightComparisonFrame
        } else if leftOverflow == 0 {
            fittedFrame = leftFrame
            fittedComparisonFrame = leftComparisonFrame
        } else if rightOverflow <= leftOverflow {
            fittedFrame = rightFrame.offsetBy(dx: -rightOverflow, dy: 0)
            fittedComparisonFrame = rightComparisonFrame.offsetBy(dx: -rightOverflow, dy: 0)
        } else {
            fittedFrame = leftFrame.offsetBy(dx: leftOverflow, dy: 0)
            fittedComparisonFrame = leftComparisonFrame.offsetBy(dx: leftOverflow, dy: 0)
        }
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
        return CGPoint(x: parentWidth - contextMenuPopupSubmenuOverlap,
                       y: fallback.y)
    }

    // Keep already-open child popups in step with the in-place root item-list
    // refresh instead of rebuilding the whole menu presentation.
    func replaceMenuItems(_ items: [PlatformItemList.Item]) {
        menuItems = items
        replaceMenuContent(with: items)
        refreshOpenedSubmenu()
    }

    func closeSubmenus() {
        openedSubmenuID = nil
        openedSubmenu = nil
        dismissAllPresentationChildren()
    }

    private func replaceMenuContent(with items: [PlatformItemList.Item]) {
        guard let contentAttr else { return }
        let graph = viewGraph.graph
        let content = UnsafeBox(AnyView(contextMenuPopupContent(items: items,
                                                                actions: popupActions)))
        // Replace child root content through the child graph inbox. The source
        // graph may be evaluating the item list when this refresh is requested.
        graph.inbox.enqueue {
            contentAttr.setValue(content.value)
        }
    }

    private func refreshOpenedSubmenu() {
        guard let openedSubmenuID else { return }
        guard let item = menuItems.first(where: { $0.id == openedSubmenuID }),
              item.isEnabled,
              !item.children.isEmpty else {
            closeSubmenus()
            return
        }
        openedSubmenu?.replaceMenuItems(item.children)
    }


    override func endPresentationSession() {
        super.endPresentationSession()
        if menuSession.root === self {
            menuSession.finish()
        }
    }

    override func onPresentationChildWindowInactivated() {
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

private let contextMenuPopupPanelPadding: CGFloat = 5
private let contextMenuPopupRowHeight: CGFloat = 24
// Separators allocate a full row separately from the visible hairline.
private let contextMenuPopupDividerHeight: CGFloat = 11
private let contextMenuPopupDividerLineHeight: CGFloat = 1
private let contextMenuPopupDividerHorizontalInset: CGFloat = 16
private let contextMenuPopupSubmenuOverlap: CGFloat = 5
// The row layout is content-driven. Coordinates below are popup-edge based and
// are converted into row-local positions by subtracting the panel padding.
private let contextMenuPopupEmptyTitleWidth: CGFloat = 16
private let contextMenuPopupPlainTitleOrigin: CGFloat = 17
private let contextMenuPopupStateTitleOrigin: CGFloat = 25
private let contextMenuPopupImageTitleOrigin: CGFloat = 37
private let contextMenuPopupStateImageTitleOrigin: CGFloat = 45
private let contextMenuPopupPlainTrailingPadding: CGFloat = 17
private let contextMenuPopupTrailingGap: CGFloat = 25.5
private let contextMenuPopupTrailingPadding: CGFloat = 15
private let contextMenuPopupStateSlotOrigin: CGFloat = 8
private let contextMenuPopupImageSlotOrigin: CGFloat = 15
private let contextMenuPopupStateImageSlotOrigin: CGFloat = 23
private let contextMenuPopupSectionHeaderFontSize: CGFloat = 12
private let contextMenuPopupSectionHeaderYOffset: CGFloat = 2.5
private let contextMenuPopupCheckmarkWidth: CGFloat = 12
private let contextMenuPopupImageWidth: CGFloat = 16
private let contextMenuPopupTrailingAccessorySpacing: CGFloat = 8
private let contextMenuPopupSubmenuIndicatorWidth: CGFloat = 5.5
private let contextMenuPopupSubmenuIndicatorHeight: CGFloat = 9.5
private let contextMenuPopupActionForeground = Color(.sRGB, white: 60.0 / 255.0)
private let contextMenuPopupDisabledForeground = Color(.sRGB, white: 135.0 / 255.0)
private let contextMenuPopupHighlightedForeground = Color(.sRGB, white: 252.0 / 255.0)
private let contextMenuPopupHighlightBackground = Color(.sRGB,
                                                        red: 63.0 / 255.0,
                                                        green: 146.0 / 255.0,
                                                        blue: 252.0 / 255.0)
private let contextMenuPopupSeparatorColor = Color(.sRGB, white: 156.0 / 255.0)
private let contextMenuPopupChromeFill = Color(.sRGB, white: 0.96)
private let contextMenuPopupChromeStroke = Color(.sRGB, white: 0.62, opacity: 0.45)

// The state/check column is menu-wide, while the image column resets across
// separator-delimited groups.
private struct ContextMenuPopupLayout {
    var showsStateColumn: Bool
    var showsImageColumn: Bool

    static let empty = ContextMenuPopupLayout(showsStateColumn: false,
                                              showsImageColumn: false)

    static func make(for items: [PlatformItemList.Item],
                     showsStateColumn: Bool? = nil) -> ContextMenuPopupLayout {
        var groupShowsStateColumn = false
        var showsImageColumn = false
        for item in items where item.systemItem == nil {
            if item.image != nil {
                showsImageColumn = true
            }
            // Toggle rows reserve the state column even when the current state is off.
            if item.selectionBehavior != nil {
                groupShowsStateColumn = true
            }
        }
        return ContextMenuPopupLayout(showsStateColumn: showsStateColumn ?? groupShowsStateColumn,
                                      showsImageColumn: showsImageColumn)
    }

    static func makeRowLayouts(for items: [PlatformItemList.Item]) -> [AnyHashable: ContextMenuPopupLayout] {
        var result: [AnyHashable: ContextMenuPopupLayout] = [:]
        var group: [PlatformItemList.Item] = []
        let menuShowsStateColumn = items.contains {
            $0.systemItem == nil && $0.selectionBehavior != nil
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
            if item.systemItem != nil {
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
            by: CGSize(width: 10, height: contextMenuPopupDividerHeight)
        )
        return CGSize(width: max(0, size.width),
                      height: max(0, size.height))
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lineHeight = min(contextMenuPopupDividerLineHeight, rect.height)
        let y = rect.midY - lineHeight * 0.5
        let lineRect = CGRect(
            x: rect.minX + contextMenuPopupDividerHorizontalInset,
            y: y,
            width: max(0, rect.width - contextMenuPopupDividerHorizontalInset * 2),
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
            popupOrigin = contextMenuPopupStateImageTitleOrigin
        case (true, false):
            popupOrigin = contextMenuPopupStateTitleOrigin
        case (false, true):
            popupOrigin = contextMenuPopupImageTitleOrigin
        case (false, false):
            popupOrigin = contextMenuPopupPlainTitleOrigin
        }
        return popupOrigin - contextMenuPopupPanelPadding
    }

    private var stateSlotOrigin: CGFloat {
        contextMenuPopupStateSlotOrigin - contextMenuPopupPanelPadding
    }

    private var imageSlotOrigin: CGFloat {
        let popupOrigin = layout.showsStateColumn
            ? contextMenuPopupStateImageSlotOrigin
            : contextMenuPopupImageSlotOrigin
        return popupOrigin - contextMenuPopupPanelPadding
    }

    private var plainTrailingPadding: CGFloat {
        contextMenuPopupPlainTrailingPadding - contextMenuPopupPanelPadding
    }

    private var trailingPadding: CGFloat {
        contextMenuPopupTrailingPadding - contextMenuPopupPanelPadding
    }

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let intrinsic = intrinsicSize(subviews: subviews)
        let width = proposal.width.map { proposed in
            proposed.isFinite ? max(proposed, intrinsic.width) : intrinsic.width
        } ?? intrinsic.width
        return CGSize(width: width, height: contextMenuPopupRowHeight)
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
                proposal: ProposedViewSize(width: contextMenuPopupCheckmarkWidth,
                                           height: contextMenuPopupCheckmarkWidth)
            )
        }
        if layout.showsImageColumn, subviews.indices.contains(imageIndex) {
            subviews[imageIndex].place(
                at: CGPoint(x: bounds.minX + imageSlotOrigin, y: midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: contextMenuPopupImageWidth,
                                           height: contextMenuPopupImageWidth)
            )
        }
        if subviews.indices.contains(titleIndex) {
            subviews[titleIndex].place(
                at: CGPoint(x: bounds.minX + titleOrigin,
                            y: midY + (isSectionHeader ? contextMenuPopupSectionHeaderYOffset : 0)),
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
                (submenuWidth > 0 ? submenuWidth + contextMenuPopupTrailingAccessorySpacing : 0)
            subviews[shortcutIndex].place(
                at: CGPoint(x: right, y: midY),
                anchor: .trailing,
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func intrinsicSize(subviews: Subviews) -> CGSize {
        guard subviews.indices.contains(titleIndex) else {
            return CGSize(width: 0, height: contextMenuPopupRowHeight)
        }
        let titleWidth = subviews[titleIndex].sizeThatFits(.unspecified).width
        let trailingWidth = self.trailingWidth(subviews: subviews)
        let rowWidth: CGFloat
        if titleWidth <= 0,
           trailingWidth <= 0,
           !layout.showsStateColumn,
           !layout.showsImageColumn {
            rowWidth = contextMenuPopupEmptyTitleWidth - contextMenuPopupPanelPadding * 2
        } else {
            let titleRight = titleOrigin + titleWidth
            if trailingWidth > 0 {
                rowWidth = titleRight + contextMenuPopupTrailingGap + trailingWidth + trailingPadding
            } else {
                rowWidth = titleRight + plainTrailingPadding
            }
        }
        return CGSize(width: max(0, rowWidth), height: contextMenuPopupRowHeight)
    }

    private func trailingWidth(subviews: Subviews) -> CGFloat {
        var width: CGFloat = 0
        if hasShortcut, subviews.indices.contains(shortcutIndex) {
            width += subviews[shortcutIndex].sizeThatFits(.unspecified).width
        }
        if hasSubmenu, subviews.indices.contains(submenuIndex) {
            if width > 0 {
                width += contextMenuPopupTrailingAccessorySpacing
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

func contextMenuPopupContent(items: [PlatformItemList.Item],
                             actions: ContextMenuPopupActions) -> some View {
    ContextMenuPopupView(items: items, actions: actions)
}

private func contextMenuPopupRenderedItems(_ items: [PlatformItemList.Item]) -> [PlatformItemList.Item] {
    var result: [PlatformItemList.Item] = []
    var previousWasDivider = false
    for item in items {
        let isDivider = item.systemItem != nil
        // The collected item model can contain consecutive or edge separators.
        // The popup renderer collapses consecutive separators to a single row
        // and suppresses edge separators from visible height.
        if isDivider && (previousWasDivider || result.isEmpty) {
            continue
        }
        result.append(item)
        previousWasDivider = isDivider
    }
    while result.last?.systemItem != nil {
        result.removeLast()
    }
    return result
}

private struct ContextMenuPopupView: View {
    let items: [PlatformItemList.Item]
    let actions: ContextMenuPopupActions
    @State private var activeSubmenuID: AnyHashable?

    var body: some View {
        let activeSubmenuID = activeSubmenuID.flatMap { id in
            items.contains {
                $0.id == id && $0.isEnabled && !$0.children.isEmpty
            } ? id : nil
        }
        ContextMenuPopupPanel(
            items: items,
            activeItemID: activeSubmenuID,
            dismiss: {
                actions.dismiss?()
            },
            openSubmenu: { item, origin in
                guard item.isEnabled, !item.children.isEmpty else { return }
                self.activeSubmenuID = item.id
                actions.openSubmenu?(item, origin)
            },
            clearSubmenus: {
                if activeSubmenuID != nil {
                    self.activeSubmenuID = nil
                }
                actions.closeSubmenus?()
            }
        )
        .fixedSize()
    }
}

private struct ContextMenuPopupPanel: View {
    let items: [PlatformItemList.Item]
    let activeItemID: AnyHashable?
    let dismiss: () -> Void
    let openSubmenu: (PlatformItemList.Item, CGPoint) -> Void
    let clearSubmenus: () -> Void
    private var renderedItems: [PlatformItemList.Item] {
        contextMenuPopupRenderedItems(items)
    }
    private var rowLayouts: [AnyHashable: ContextMenuPopupLayout] {
        ContextMenuPopupLayout.makeRowLayouts(for: renderedItems)
    }

    private func rowTopOffset(for id: AnyHashable) -> CGFloat {
        var offset = contextMenuPopupPanelPadding
        for item in renderedItems {
            if item.id == id { return offset }
            offset += item.systemItem == nil
                ? contextMenuPopupRowHeight
                : contextMenuPopupDividerHeight
        }
        return contextMenuPopupPanelPadding
    }

    private func submenuOrigin(for item: PlatformItemList.Item) -> CGPoint {
        let provisionalPopupWidth = contextMenuPopupPlainTitleOrigin +
            contextMenuPopupTrailingGap +
            contextMenuPopupSubmenuIndicatorWidth +
            contextMenuPopupTrailingPadding
        return CGPoint(x: provisionalPopupWidth - contextMenuPopupSubmenuOverlap,
                       y: rowTopOffset(for: item.id))
    }

    var body: some View {
        let renderedItems = self.renderedItems
        let rowLayouts = self.rowLayouts
        ContextMenuPopupColumnLayout {
            ForEach(renderedItems) { item in
                ContextMenuPopupRow(item: item,
                                    layout: rowLayouts[item.id] ?? .empty,
                                    isSubmenuOpen: activeItemID == item.id,
                                    submenuOrigin: submenuOrigin(for: item),
                                    dismiss: dismiss,
                                    openSubmenu: openSubmenu,
                                    clearSubmenus: clearSubmenus)
            }
        }
        .padding(contextMenuPopupPanelPadding)
        .background(contextMenuPopupChromeFill, in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(contextMenuPopupChromeStroke, lineWidth: 1)
        }
        .fixedSize()
    }
}

private struct ContextMenuPopupRow: View {
    let item: PlatformItemList.Item
    let layout: ContextMenuPopupLayout
    let isSubmenuOpen: Bool
    let submenuOrigin: CGPoint
    let dismiss: () -> Void
    let openSubmenu: (PlatformItemList.Item, CGPoint) -> Void
    let clearSubmenus: () -> Void
    @State private var isPressed = false
    @State private var isHovered = false

    private var hasSubmenu: Bool {
        item.secondaryNavigationBehavior == .submenu && !item.children.isEmpty
    }

    private var isSectionHeader: Bool {
        item.presentationRole == .sectionHeader
    }

    private var isToggleOn: Bool {
        if case let .toggle(value)? = item.selectionBehavior {
            return value
        }
        return false
    }

    private var shortcutLabel: String? {
        guard let keyboardShortcut = item.keyboardShortcut else {
            return nil
        }
        return keyboardShortcut.displayLabel
    }

    private var rowBackground: Color {
        if isHighlighted {
            return contextMenuPopupHighlightBackground
        }
        return .clear
    }

    private var rowForeground: Color {
        if isHighlighted {
            return contextMenuPopupHighlightedForeground
        }
        if isSectionHeader || !item.isEnabled {
            // Static Text/Label menu rows are disabled platform items and render
            // with disabled foreground, not a normal actionable-row foreground.
            return contextMenuPopupDisabledForeground
        }
        return contextMenuPopupActionForeground
    }

    private var isHighlighted: Bool {
        guard item.systemItem == nil, !isSectionHeader, item.isEnabled else {
            return false
        }
        return isHovered || isPressed || (isSubmenuOpen && hasSubmenu)
    }

    var body: some View {
        if item.systemItem != nil {
            ContextMenuDividerShape()
                .fill(contextMenuPopupSeparatorColor)
                .frame(height: contextMenuPopupDividerHeight)
        } else {
            ContextMenuPopupRowLayout(layout: layout,
                                      hasShortcut: shortcutLabel != nil,
                                      hasSubmenu: hasSubmenu,
                                      isSectionHeader: isSectionHeader) {
                if layout.showsStateColumn {
                    ContextMenuCheckmarkShape()
                        .stroke(isToggleOn ? rowForeground : .clear,
                                style: StrokeStyle(lineWidth: 1.6,
                                                   lineCap: .round,
                                                   lineJoin: .round))
                        .frame(width: contextMenuPopupCheckmarkWidth,
                               height: contextMenuPopupCheckmarkWidth,
                               alignment: .center)
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
                if layout.showsImageColumn {
                    if let image = item.image {
                        image
                            .frame(width: contextMenuPopupImageWidth,
                                   height: contextMenuPopupImageWidth,
                                   alignment: .center)
                    } else {
                        Color.clear
                            .frame(width: contextMenuPopupImageWidth,
                                   height: contextMenuPopupImageWidth)
                    }
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
                item.label
                    .font(isSectionHeader ? .system(size: contextMenuPopupSectionHeaderFontSize) : nil)
                    .fixedSize(horizontal: true, vertical: false)
                if let shortcutLabel {
                    Text(shortcutLabel)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
                if hasSubmenu {
                    ContextMenuSubmenuIndicatorShape()
                        .fill(rowForeground)
                        .frame(width: contextMenuPopupSubmenuIndicatorWidth,
                               height: contextMenuPopupSubmenuIndicatorHeight)
                } else {
                    Color.clear
                        .frame(width: 0, height: 0)
                }
            }
            .foregroundStyle(rowForeground)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 4))
            ._onButtonGesture(pressing: { pressing in
                guard !isSectionHeader else {
                    isPressed = false
                    return
                }
                isPressed = pressing
                if pressing, item.isEnabled, hasSubmenu {
                    openSubmenu(item, submenuOrigin)
                }
            }, perform: {
                guard !isSectionHeader, item.isEnabled else { return }
                if hasSubmenu {
                    openSubmenu(item, submenuOrigin)
                    // Submenu primary-action split is not wired yet.
                    return
                }
                clearSubmenus()
                guard let action = item.action else { return }
                action()
                dismiss()
            })
            .onHover { hovering in
                guard !isSectionHeader, item.isEnabled else {
                    isHovered = false
                    return
                }
                isHovered = hovering
                guard hovering else { return }
                if hasSubmenu {
                    openSubmenu(item, submenuOrigin)
                } else {
                    clearSubmenus()
                }
            }
            .environment(\.isEnabled, item.isEnabled)
        }
    }
}
