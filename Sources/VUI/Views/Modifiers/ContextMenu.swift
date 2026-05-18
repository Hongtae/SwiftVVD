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
    fileprivate var _scene: some Scene {
        _EmptyScene()
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
        let usesPlatformWindow = environment.value.auxiliaryWindowUsingPlatformWindow
        let ctrl = ContextMenuWindowController(crossGraphContent: contentAttr,
                                               sourceGraph: graph,
                                               scene: parent.scene,
                                               anchor: location,
                                               usesPlatformWindow: usesPlatformWindow)
        parent.addAuxiliary(child: ctrl) { [weak ctrl] attach in
            ctrl?.resolveAuxiliaryWindowAttachment(attach)
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

final class ContextMenuWindowController: AuxiliaryWindowController, @unchecked Sendable {
    init(crossGraphContent contentAttr: Attribute<AnyView>,
         sourceGraph: AttributeGraph,
         scene: WindowKey,
         anchor: CGPoint,
         usesPlatformWindow: Bool) {
        let frame = CGRect(origin: anchor, size: .zero)
        super.init(crossGraphContent: contentAttr,
                   sourceGraph: sourceGraph,
                   scene: scene,
                   usesPlatformWindow: usesPlatformWindow,
                   dismissOnDeactivated: true,
                   frameInParent: frame)
    }

    override func onAuxiliaryWindowInactivated() {
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
