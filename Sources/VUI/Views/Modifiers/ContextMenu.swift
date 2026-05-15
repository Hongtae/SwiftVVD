//
//  File: ContextMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        guard let graph = AttributeGraph.current else {
            fatalError("ContextMenuModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)
        let wantsResponders = inputs.preferences.keys.contains(ViewRespondersKey.self)
        guard wantsResponders else {
            return outputs
        }

        // Build context menu content into a platform item list and store a weak
        // reference on the responder.
        let itemListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(
            PlatformItemListGenerator<AllPlatformItemListFlags, MenuContent>(
                content: modifier[\.menuView]._attribute,
                inputs: inputs,
                inputsIncludeGeometry: true
            )
        )
        let responder = ContextMenuResponder(
            itemList: itemListAttr,
            environment: inputs.base.cachedEnvironment.value.environment,
            transform: inputs.transform,
            size: inputs.size
        )
        graph.makeSideEffectRule { [weak responder] in
            responder?.snapshotTransform = inputs.transform.value
            responder?.snapshotSize = inputs.size.value
        }

        let respondersAttr: Attribute<[any ViewResponder]> = graph.makeInput(value: [responder])
        outputs.preferences.append(ViewRespondersKey.self, node: respondersAttr.identifier)
        return outputs
    }

    // Keep the modifier attached to each materialized list element. Without this,
    // contextMenu disappears when applied to children inside HStack/VStack/etc.
    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("ContextMenuModifier._makeViewList called outside AG context")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

extension ContextMenuModifier {
    fileprivate var _gesture: ContextMenuGesture {
        .init()
    }

    fileprivate var _scene: some Scene {
        AuxiliaryWindowScene(content: menuView)
    }
}

private let _contextMenuResponderNextKey = Mutex<UInt32>(0x90000000)

final class ContextMenuResponder: ViewResponder {
    let hitTestKey: UInt32
    weak var nextResponder: ResponderNode?
    var gestureContainer: AnyObject? { nil }

    let itemList: Attribute<PlatformItemList>
    let environment: Attribute<EnvironmentValues>
    let transform: Attribute<ViewTransform>
    let size: Attribute<ViewSize>

    var snapshotTransform: ViewTransform = .identity
    var snapshotSize: ViewSize = ViewSize(.zero)

    init(itemList: Attribute<PlatformItemList>,
         environment: Attribute<EnvironmentValues>,
         transform: Attribute<ViewTransform>,
         size: Attribute<ViewSize>) {
        self.hitTestKey = _contextMenuResponderNextKey.withLock { key in
            defer { key &+= 1 }
            return key
        }
        self.itemList = itemList
        self.environment = environment
        self.transform = transform
        self.size = size
    }

    func hitTestPolicy(options: ContainsPointsOptions) -> HitTestPolicy {
        .include
    }

    func containsGlobalPoints(_ points: [CGPoint],
                              cacheKey: UInt32?,
                              options: ContainsPointsOptions) -> ContainsPointsResult {
        let sz = snapshotSize.value
        var localPts = Array(points.prefix(64))
        snapshotTransform.convertGlobal(to: .local, points: &localPts)
        let bounds = CGRect(origin: .zero, size: sz)
        var mask: UInt64 = 0
        for (i, point) in localPts.enumerated() {
            if bounds.contains(point) { mask |= (1 << i) }
        }
        guard mask != 0 else { return .stop }
        return ContainsPointsResult(mask: mask, priority: 16.0, children: [])
    }

    func present(from parent: WindowController, at location: CGPoint) {
        guard let graph = AttributeGraph.current else {
            fatalError("ContextMenuResponder.present called outside AG context")
        }
        parent.dismissAllAuxiliaryWindows()
        let contentAttr: Attribute<AnyView> = graph.makeRule { [weak parent] in
            AnyView(ContextMenuPopupView(items: self.itemList.value.menuItems) {
                parent?.dismissAllAuxiliaryWindows()
            })
        }
        // WindowController.init(crossGraphContent:) requires a cached source value
        // before the child ViewGraph installs its cross-graph reference.
        _ = contentAttr.value
        let ctrl = ContextMenuWindowController(crossGraphContent: contentAttr,
                                               sourceGraph: graph,
                                               scene: parent.scene,
                                               anchor: location)
        parent.addAuxiliary(child: ctrl)
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

final class ContextMenuWindowController: WindowController, @unchecked Sendable {
    override var observesRootFittedSizeForLayoutUpdates: Bool { true }

    private let anchor: CGPoint
    private var frameInParent: CGRect = .zero

    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: AttributeGraph,
         scene: WindowKey,
         anchor: CGPoint) {
        self.anchor = anchor
        super.init(crossGraphContent: contentAttr,
                   sourceGraph: sourceGraph,
                   scene: scene)
    }

    override func onViewLayoutUpdated() {
        guard let layoutComputer = viewGraph.rootLayoutComputer else { return }
        let fittedSize = viewGraph.rootFittedSize?.value ??
            layoutComputer.value.sizeThatFits(.unspecified)
        let size = CGSize(width: max(1, fittedSize.width),
                          height: max(1, fittedSize.height))
        frameInParent = CGRect(origin: anchor, size: size)
        sharedContext.contentBounds.size = size
        viewGraph.sizeAttr?.setValue(ViewSize(size))
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        layoutComputer.value.place(at: center,
                                   anchor: .center,
                                   proposal: ProposedViewSize(width: size.width,
                                                              height: size.height))
        parentWindow?.updateAuxiliary(child: self, frame: frameInParent)
    }

    override func layoutContentSize(from contentSize: CGSize) -> CGSize {
        frameInParent.size == .zero ? contentSize : frameInParent.size
    }

    override func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        super.drawFrame(offset: offset + frameInParent.origin, context)
    }

    override func overlayHitTest(_ locationInParent: CGPoint) -> Bool {
        CGRect(origin: .zero, size: frameInParent.size).contains(locationInParent)
    }

    override func onGestureInitiated(from initiator: AnyObject?, location: CGPoint) {
        if initiator !== self {
            parentWindow?.removeAuxiliary(child: self)
        }
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

private struct ContextMenuPopupView: View {
    let items: [PlatformItemList.Item]
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                ContextMenuPopupRow(item: item, dismiss: dismiss)
            }
        }
        .padding(4)
        .background(Color(white: 0.98), in: RoundedRectangle(cornerRadius: 6))
        .border(Color(white: 0.55), width: 1)
        .fixedSize()
    }
}

private struct ContextMenuPopupRow: View {
    let item: PlatformItemList.Item
    let dismiss: () -> Void

    var body: some View {
        if item.systemItem != nil {
            Divider()
                .frame(minWidth: 160)
                .padding(.vertical, 3)
        } else {
            HStack(spacing: 8) {
                item.label
                    .environment(\.isEnabled, item.isEnabled)
                if !item.children.isEmpty {
                    Text(">")
                }
            }
            .frame(minWidth: 160, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .opacity(item.isEnabled ? 1.0 : 0.45)
            ._onButtonGesture(pressing: { _ in }, perform: {
                guard item.isEnabled else { return }
                guard let action = item.action else {
                    // TODO: open child items as a sibling submenu panel.
                    return
                }
                action()
                dismiss()
            })
        }
    }
}

private struct ContextMenuGesture: Gesture {
    static func _makeGesture(gesture: _GraphValue<ContextMenuGesture>, inputs: _GestureInputs) -> _GestureOutputs<Void> {
        fatalError()
    }
    
    typealias Body = Never
    typealias Value = Void
}

private class ContextMenuGestureHandler: _GestureHandler {
    var typeFilter: _PrimitiveGestureTypes = .all
    let gesture: ContextMenuGesture
    var openMenuOnButtonUp: Bool = false
    var openMenuCallback: ((CGPoint) -> Void)? = nil
    var modifierKeys: [VirtualKey] = []
    var buttonID: Int = 1
    var location: CGPoint = .zero

    override var type: _PrimitiveGestureTypes { .all }

    override var isValid: Bool {
        typeFilter.contains(self.type)
    }

    override func setTypeFilter(_ f: _PrimitiveGestureTypes) -> _PrimitiveGestureTypes {
        self.typeFilter = f
        return f.subtracting(.tap)
    }

    init(graph: _GraphValue<ContextMenuGesture>, target: Any?, gesture: ContextMenuGesture) {
        self.gesture = gesture
        super.init(graph: graph, target: target)
    }

    deinit {
        //Log.debug("ContextMenuGestureHandler: deinit")
    }

    override func began(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0 {
            if buttonID == 0 {
                // check 'control' key is pressing.
                let controlKeyPressed = modifierKeys.contains(.leftControl) || modifierKeys.contains(.rightControl)
                if controlKeyPressed {
                    self.state = .processing
                }
            } else if buttonID == 1 {
                // right mouse button
                self.state = .processing
            }
        }
        if self.state == .processing {
            self.buttonID = buttonID
            self.location = self.locationInView(location)
            if self.openMenuOnButtonUp == false {
                self.openMenuCallback?(location)
            }
            return
        }
        self.state = .failed
    }

    override func moved(deviceID: Int, buttonID: Int, location: CGPoint) {
        if deviceID == 0 && buttonID == self.buttonID {
            self.location = self.locationInView(location)
        }
    }

    override func ended(deviceID: Int, buttonID: Int) {
        if deviceID == 0 && buttonID == self.buttonID {
            if buttonID == 0 {
                let controlKeyPressed = modifierKeys.contains(.leftControl) || modifierKeys.contains(.rightControl)
                if controlKeyPressed == false {
                    self.state = .failed
                }
            }
            if self.state == .processing {
                self.state = .done
                if self.openMenuOnButtonUp {
                    self.openMenuCallback?(self.location)
                }
            }
        }
    }

    override func cancelled(deviceID: Int, buttonID: Int) {
        if deviceID == 0 && buttonID == self.buttonID {
            self.state = .cancelled
        }
    }

    override func reset() {
        self.state = .ready
        Log.debug("ContextMenuGestureHandler: reset")
    }
}
