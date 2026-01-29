//
//  File: SheetPresentationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private protocol _SheetModifier<SheetContent>: ViewModifier {
    var onDismiss: (() -> Void)? { get }

    associatedtype SheetContent: View
    var _scene: ModalWindowScene<SheetContent> { get }
}

struct SheetPresentationModifier<Content>: ViewModifier where Content: View {
    typealias Body = Never

    let _isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let sheetContent: () -> Content
}

struct ItemSheetPresentationModifier<Item, Content>: ViewModifier where Item: Identifiable, Content: View {
    typealias Body = Never

    let _item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> Content
}

extension SheetPresentationModifier: _SheetModifier {
    fileprivate var _scene: ModalWindowScene<Content> {
        ModalWindowScene {
            sheetContent()
        }
    }
}

extension ItemSheetPresentationModifier: _SheetModifier {
    fileprivate var _scene: ModalWindowScene<Content> {
        ModalWindowScene {
            sheetContent(_item.wrappedValue!)
        }
    }
}

extension View {
    public func sheet<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View where Item: Identifiable, Content: View {
        self.modifier(
            ItemSheetPresentationModifier(_item: item,
                                          onDismiss: onDismiss,
                                          sheetContent: content)
        )
    }
  
    public func sheet<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View where Content: View {
        self.modifier(
            SheetPresentationModifier(_isPresented: isPresented,
                                      onDismiss: onDismiss,
                                      sheetContent: content)
        )
    }
}

extension SheetPresentationModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                SheetPresentationViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: .init(view))
        }
        return outputs
    }
}

extension ItemSheetPresentationModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                ItemSheetPresentationViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: .init(view))
        }
        return outputs
    }
}

private class SheetModifierViewContext<SheetModifier>: ViewModifierContext<SheetModifier>, @unchecked Sendable where SheetModifier: _SheetModifier {
    enum SheetAction {
        case present
        case dismiss
        case update
    }

    var dynamicPropertyData: _DynamicPropertyDataStorage<SheetModifier>
    var sceneContext: ModalWindowSceneContext<SheetModifier.SheetContent>!
    var actionRequired: Bool = false

    struct _SceneRoot<T: _SheetModifier>: SceneRoot {
        typealias Root = T
        var root: Root {
            view.modifier!
        }
        var graph: _GraphValue<Root> {
            view.graph
        }
        var app: AppContext {
            view.sharedContext.app
        }
        unowned let view: SheetModifierViewContext<T>
    }

    override init(graph: _GraphValue<SheetModifier>, body: ViewContext, inputs: _GraphInputs) {
        var inputs = inputs
        self.dynamicPropertyData = _DynamicPropertyDataStorage(graph: graph, inputs: &inputs)
        super.init(graph: graph, body: body, inputs: inputs)

        let sceneRoot = _SceneRoot<SheetModifier>(view: self)
        let sceneInputs = _SceneInputs(root: sceneRoot, environment: self.environment,
                                       modifiers: self.inputs.modifiers,
                                       _modifierTypeGraphs: self.inputs._modifierTypeGraphs)

        func makeScene<T: Scene>(scene: _GraphValue<T>, inputs: _SceneInputs) -> _SceneOutputs {
            T._makeScene(scene: scene, inputs: inputs)
        }
        let sceneOutputs = makeScene(scene: graph[\._scene], inputs: sceneInputs)
        self.sceneContext = sceneOutputs.scene?.makeScene() as? ModalWindowSceneContext<SheetModifier.SheetContent>
        assert(self.sceneContext != nil, "Failed to create ModalWindowSceneContext")
        
        self.dynamicPropertyData.tracker = { [weak self] in
            Log.debug("Update sheet binding!")
            self?.actionRequired = true
        }
    }

    override func updateView(_ modifier: inout SheetModifier) {
        super.updateView(&modifier)
        self.dynamicPropertyData.bind(container: &modifier, view: self)
        self.dynamicPropertyData.update(container: &modifier)
    }

    func presentSheet() {
        guard let sceneContext = self.sceneContext else {
            Log.error("SheetModifierViewContext: sceneContext is nil")
            return
        }
        
        let context = self.sharedContext
        
        Task { @MainActor in
            let presented = sceneContext.present(context: context, withAnimation: true) { [weak self] response in
                guard let self else { return }
                switch response {
                case .dismissed:
                    self.onSheetDismissed()
                case .userAction:
                    self.onSheetDismissedByUserAction()
                case .byParent:
                    self.onSheetDismissedByParent()
                case .cancelled:
                    self.onSheetPresentationCancelled()
                }
            }
            if presented == false {
                Log.error("SheetModifierViewContext: failed to present sheet scene")
            }
        }
    }

    func dismissSheet() {
        guard let sceneContext = self.sceneContext else {
            return
        }
        Task { @MainActor in
            sceneContext.dismiss(withAnimation: true)
        }
    }

    // Called when the sheet is closed by dismiss() — programmatic dismissal.
    // Subclasses must override to reset their binding and call onDismiss.
    func onSheetDismissed() {}

    // Called when the sheet is closed by user action (e.g. gesture, close button).
    // Subclasses must override to reset their binding and call onDismiss.
    func onSheetDismissedByUserAction() {}

    // Called when the sheet is closed because its parent modal was dismissed.
    // Subclasses must override to reset their binding and call onDismiss.
    func onSheetDismissedByParent() {}

    // Called when the sheet was never shown — cancelled before being initiated.
    // Subclasses must override to reset their binding.
    // onDismiss should NOT be called in this case.
    func onSheetPresentationCancelled() {}

    func determineAction() -> SheetAction? {
        return nil  // Base implementation returns nil
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)

        if self.actionRequired {
            self.actionRequired = false

            if let action = self.determineAction() {
                Log.debug("SheetModifierViewContext: determined action: \(action)")
                switch action {
                case .present:
                    self.presentSheet()
                case .dismiss:
                    self.dismissSheet()
                case .update:
                    self.sceneContext.updateContent()
                }
            } else {
                Log.debug("SheetModifierViewContext: no action determined")
            }
        }
    }
}

private class SheetPresentationViewContext<Content>: SheetModifierViewContext<SheetPresentationModifier<Content>>, @unchecked Sendable where Content: View {
    var isPresented: Bool = false

    override func determineAction() -> SheetAction? {
        guard let modifier = self.modifier else { return nil }

        let shouldPresented = modifier._isPresented.wrappedValue
        defer { self.isPresented = shouldPresented }

        if isPresented {
            if shouldPresented == false {
                return .dismiss
            }
        } else {
            if shouldPresented {
                return .present
            }
        }
        return nil  // no change needed
    }

    override func onSheetDismissed() {
        Log.debug("onSheetDismissed()")
        // binding was already false when dismissSheet() was called — no need to reset.
        isPresented = false
        modifier?.onDismiss?()
    }

    override func onSheetDismissedByUserAction() {
        Log.debug("onSheetDismissedByUserAction()")
        modifier?._isPresented.wrappedValue = false
        isPresented = false
        modifier?.onDismiss?()
    }

    override func onSheetDismissedByParent() {
        Log.debug("onSheetDismissedByParent()")
        modifier?._isPresented.wrappedValue = false
        isPresented = false
        modifier?.onDismiss?()
    }

    override func onSheetPresentationCancelled() {
        Log.debug("onSheetPresentationCancelled()")
        modifier?._isPresented.wrappedValue = false
        isPresented = false
        // onDismiss is intentionally not called — sheet was never shown
    }
}

private class ItemSheetPresentationViewContext<Item, Content>: SheetModifierViewContext<ItemSheetPresentationModifier<Item, Content>>, @unchecked Sendable where Item: Identifiable, Content: View {
    var itemID: Item.ID? = nil

    override func determineAction() -> SheetAction? {
        guard let modifier = self.modifier else { return nil }

        let newItemID = modifier._item.wrappedValue?.id
        defer { self.itemID = newItemID }

        if let itemID {
            if let newItemID {
                if itemID != newItemID {
                    return .update
                }
            } else {
                return .dismiss
            }
        } else {
            if newItemID != nil {
                return .present
            }
        }
        return nil  // no change needed
    }

    override func onSheetDismissed() {
        Log.debug("onSheetDismissed()")
        // binding was already nil when dismissSheet() was called — no need to reset.
        itemID = nil
        modifier?.onDismiss?()
    }

    override func onSheetDismissedByUserAction() {
        Log.debug("onSheetDismissedByUserAction()")
        modifier?._item.wrappedValue = nil
        itemID = nil
        modifier?.onDismiss?()
    }

    override func onSheetDismissedByParent() {
        Log.debug("onSheetDismissedByParent()")
        modifier?._item.wrappedValue = nil
        itemID = nil
        modifier?.onDismiss?()
    }

    override func onSheetPresentationCancelled() {
        Log.debug("onSheetPresentationCancelled()")
        modifier?._item.wrappedValue = nil
        itemID = nil
        // onDismiss is intentionally not called — sheet was never shown
    }
}
