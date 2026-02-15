//
//  File: AlertModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct ActionsModifier: ViewModifier {
    typealias Body = Never

    let canPresent: Bool
}

protocol _AlertActionsView: View {
    associatedtype ActualContent: View
    var _canPresent: Bool { get }
    var _content: ActualContent { get }
}

extension ModifiedContent: _AlertActionsView where Modifier == ActionsModifier, Content: View {
    typealias ActualContent = Content
    var _canPresent: Bool { modifier.canPresent }
    var _content: Content { content }
}

struct AlertModifier<Actions, Message>: ViewModifier where Actions: _AlertActionsView, Message: View {
    typealias Body = Never

    let title: Text
    let actions: Actions
    let message: Message
    fileprivate let isPresented: Binding<Bool>  // mirrored for DynamicProperty tracking
}

extension View {
    public func alert<A>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where A: View {
        self.alert(Text(titleKey), isPresented: isPresented, actions: actions)
    }

    public func alert<S, A>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where S: StringProtocol, A: View {
        self.alert(Text(title), isPresented: isPresented, actions: actions)
    }

    public func alert<A>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A) -> some View where A: View {
        let actionsView = Optional(actions())
            .modifier(ActionsModifier(canPresent: true))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: EmptyView(), isPresented: isPresented))
    }
}

extension View {
    public func alert<A, M>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View where A: View, M: View {
        self.alert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<S, A, M>(_ title: S, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View where S: StringProtocol, A: View, M: View {
        self.alert(Text(title), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<A, M>(_ title: Text, isPresented: Binding<Bool>, @ViewBuilder actions: () -> A, @ViewBuilder message: () -> M) -> some View where A: View, M: View {
        let actionsView = Optional(actions())
            .modifier(ActionsModifier(canPresent: true))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: message(), isPresented: isPresented))
    }
}

extension View {
    public func alert<A, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where A: View {
        self.alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions)
    }

    public func alert<S, A, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where S: StringProtocol, A: View {
        self.alert(Text(title), isPresented: isPresented, presenting: data, actions: actions)
    }

    public func alert<A, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A) -> some View where A: View {
        let actionsView = data.map(actions)
            .modifier(ActionsModifier(canPresent: data != nil))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: EmptyView(), isPresented: isPresented))
    }
}

extension View {
    public func alert<A, M, T>(_ titleKey: LocalizedStringKey, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where A: View, M: View {
        self.alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }

    public func alert<S, A, M, T>(_ title: S, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where S: StringProtocol, A: View, M: View {
        self.alert(Text(title), isPresented: isPresented, presenting: data, actions: actions, message: message)
    }

    public func alert<A, M, T>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?, @ViewBuilder actions: (T) -> A, @ViewBuilder message: (T) -> M) -> some View where A: View, M: View {
        let actionsView = data.map(actions)
            .modifier(ActionsModifier(canPresent: data != nil))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: data.map(message), isPresented: isPresented))
    }
}

extension View {
    public func alert<E, A>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: () -> A) -> some View where E: LocalizedError, A: View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        let actionsView = Optional(actions())
            .modifier(ActionsModifier(canPresent: error != nil))
        let messageView = error.map { e in
            Text([e.failureReason, e.recoverySuggestion].compactMap { $0 }.joined(separator: "\n"))
        }
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: messageView, isPresented: isPresented))
    }

    public func alert<E, A, M>(isPresented: Binding<Bool>, error: E?, @ViewBuilder actions: (E) -> A, @ViewBuilder message: (E) -> M) -> some View where E: LocalizedError, A: View, M: View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        let actionsView = error.map(actions)
            .modifier(ActionsModifier(canPresent: error != nil))
        return self.modifier(AlertModifier(title: title, actions: actionsView,
                                          message: error.map(message), isPresented: isPresented))
    }
}

private struct AlertContentView<Actions: View, Message: View>: View {
    let title: Text
    let actions: Actions
    let message: Message

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                title.font(.headline)
                message
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()

            actions
                .padding(8)
        }
        .frame(width: 280)
    }
}

private protocol _AlertModifier<AlertContent>: ViewModifier {
    associatedtype AlertContent: View
    var _scene: ModalWindowScene<AlertContent> { get }
    var isPresented: Binding<Bool> { get }
    var canPresent: Bool { get }
}

extension AlertModifier: _AlertModifier {
    fileprivate var _scene: ModalWindowScene<AlertContentView<Actions.ActualContent, Message>> {
        ModalWindowScene {
            AlertContentView(title: self.title, actions: self.actions._content, message: self.message)
        }
    }
    fileprivate var canPresent: Bool { actions._canPresent }
}

extension ActionsModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        body(_Graph(), inputs)
    }
}

extension AlertModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                AlertModifierViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: .init(view))
        }
        return outputs
    }
}

private class AlertModifierViewContext<AlertMod>: ViewModifierContext<AlertMod>, @unchecked Sendable where AlertMod: _AlertModifier {
    enum AlertAction {
        case present
        case dismiss
    }

    var dynamicPropertyData: _DynamicPropertyDataStorage<AlertMod>
    var sceneContext: ModalWindowSceneContext<AlertMod.AlertContent>!
    var actionRequired: Bool = false
    var isPresented: Bool = false

    struct _SceneRoot<T: _AlertModifier>: SceneRoot {
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
        unowned let view: AlertModifierViewContext<T>
    }

    override init(graph: _GraphValue<AlertMod>, body: ViewContext, inputs: _GraphInputs) {
        var inputs = inputs
        self.dynamicPropertyData = _DynamicPropertyDataStorage(graph: graph, inputs: &inputs)
        super.init(graph: graph, body: body, inputs: inputs)

        let sceneRoot = _SceneRoot<AlertMod>(view: self)
        let sceneInputs = _SceneInputs(root: sceneRoot, environment: self.environment,
                                       modifiers: self.inputs.modifiers,
                                       _modifierTypeGraphs: self.inputs._modifierTypeGraphs)

        func makeScene<T: Scene>(scene: _GraphValue<T>, inputs: _SceneInputs) -> _SceneOutputs {
            T._makeScene(scene: scene, inputs: inputs)
        }
        let sceneOutputs = makeScene(scene: graph[\._scene], inputs: sceneInputs)
        self.sceneContext = sceneOutputs.scene?.makeScene() as? ModalWindowSceneContext<AlertMod.AlertContent>
        assert(self.sceneContext != nil, "Failed to create ModalWindowSceneContext for alert")

        self.dynamicPropertyData.tracker = { [weak self] in
            Log.debug("Update alert binding!")
            self?.actionRequired = true
        }
    }

    override func updateView(_ modifier: inout AlertMod) {
        super.updateView(&modifier)
        self.dynamicPropertyData.bind(container: &modifier, view: self)
        self.dynamicPropertyData.update(container: &modifier)
    }

    func presentAlert() {
        guard let sceneContext = self.sceneContext else {
            Log.error("AlertModifierViewContext: sceneContext is nil")
            return
        }

        let context = self.sharedContext

        Task { @MainActor in
            let presented = sceneContext.present(context: context, withAnimation: true,
                                                 alertDismissAction: { [weak sceneContext] in
                sceneContext?.dismiss(withAnimation: true)
            }) { [weak self] response in
                guard let self else { return }
                switch response {
                case .dismissed:
                    self.onAlertDismissed()
                case .userAction:
                    self.onAlertDismissedByUserAction()
                case .byParent:
                    self.onAlertDismissedByParent()
                case .cancelled:
                    self.onAlertPresentationCancelled()
                }
            }
            if presented == false {
                Log.error("AlertModifierViewContext: failed to present alert scene")
            }
        }
    }

    func dismissAlert() {
        guard let sceneContext = self.sceneContext else { return }
        Task { @MainActor in
            sceneContext.dismiss(withAnimation: true)
        }
    }

    func determineAction() -> AlertAction? {
        guard let modifier = self.modifier else { return nil }

        let shouldPresented = modifier.isPresented.wrappedValue && modifier.canPresent
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
        return nil
    }

    // Called when the alert is dismissed programmatically (binding became false).
    // The binding is already false at this point — do not reset it again.
    func onAlertDismissed() {
        Log.debug("onAlertDismissed()")
        isPresented = false
    }

    // Called when the alert is dismissed by user action (e.g., button tap).
    func onAlertDismissedByUserAction() {
        Log.debug("onAlertDismissedByUserAction()")
        modifier?.isPresented.wrappedValue = false
        isPresented = false
    }

    // Called when the alert is dismissed because its parent was dismissed.
    func onAlertDismissedByParent() {
        Log.debug("onAlertDismissedByParent()")
        modifier?.isPresented.wrappedValue = false
        isPresented = false
    }

    // Called when the alert was never shown — presentation was cancelled.
    func onAlertPresentationCancelled() {
        Log.debug("onAlertPresentationCancelled()")
        modifier?.isPresented.wrappedValue = false
        isPresented = false
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        super.update(tick: tick, delta: delta, date: date)

        if self.actionRequired {
            self.actionRequired = false

            if let action = self.determineAction() {
                Log.debug("AlertModifierViewContext: determined action: \(action)")
                switch action {
                case .present:
                    self.presentAlert()
                case .dismiss:
                    self.dismissAlert()
                }
            } else {
                Log.debug("AlertModifierViewContext: no action determined")
            }
        }
    }
}
