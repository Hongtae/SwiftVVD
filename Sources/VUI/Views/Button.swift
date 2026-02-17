//
//  File: Button.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Button<Label>: View where Label: View {
    let role: ButtonRole?
    let action: ()->Void
    let label: Label

    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = nil
        self.label = label()
        self.action = action
    }

    public var body: some View {
        ResolvedButtonStyle(
            configuration: PrimitiveButtonStyleConfiguration(
                role: nil,
                label: PrimitiveButtonStyleConfiguration.Label(),
                action: action))
        .modifier(StaticSourceWriter<PrimitiveButtonStyleConfiguration.Label, Label>(source: label))
        .modifier(StaticSourceWriter<ButtonStyleConfiguration.Label, Label>(source: label))
    }
}

extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) {
        self.role = nil
        self.action = action
        self.label = Text(titleKey)
    }
    public init<S>(_ title: S, action: @escaping () -> Void) where S: StringProtocol {
        self.role = nil
        self.action = action
        self.label = Text(title)
    }
}

extension Button where Label == VUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) {
            Label(titleKey, systemImage: systemImage)
        }
    }
    public init<S>(_ title: S, systemImage: String, action: @escaping () -> Void) where S: StringProtocol {
        self.init(action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

extension Button where Label == PrimitiveButtonStyleConfiguration.Label {
    public init(_ configuration: PrimitiveButtonStyleConfiguration) {
        self.init(role: configuration.role, action: {
        }, label: {
            configuration.label
        })
    }
}

extension Button {
    public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.role = role
        self.action = action
        self.label = label()
    }
}

extension Button where Label == Text {
    public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void) {
        self.label = Text(titleKey)
        self.role = role
        self.action = action
    }
    public init<S>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) where S: StringProtocol {
        self.label = Text(title)
        self.role = role
        self.action = action
    }
}

extension Button where Label == VUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            Label(titleKey, systemImage: systemImage)
        }
    }
    public init<S>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) where S: StringProtocol {
        self.init(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

struct ResolvedButtonStyle: View {
    typealias Body = Never
    var configuration: PrimitiveButtonStyleConfiguration
    init(configuration: PrimitiveButtonStyleConfiguration) {
        self.configuration = configuration
    }

    var _isPressing = false
    var _style: any PrimitiveButtonStyle = DefaultButtonStyle.automatic
    var _pressingCallback: ((Bool) -> Void)? = nil
    var _body: any View {
        if let styleWithPressingBody = _style as? (any PrimitiveButtonStyleWithPressingBody) {
            return styleWithPressingBody.makeBody(configuration: self.configuration,
                                                  isPressing: self._isPressing,
                                                  callback: self._pressingCallback)
        } else {
            return _style.makeBody(configuration: self.configuration)
        }
    }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let primitiveButtonStyleLabelKey = ObjectIdentifier(PrimitiveButtonStyleConfiguration.Label.self)
        let buttonStyleLabelKey = ObjectIdentifier(ButtonStyleConfiguration.Label.self)

        var inputs = inputs
        let label1 = inputs.layouts.sourceWrites.removeValue(forKey: primitiveButtonStyleLabelKey)
        let label2 = inputs.layouts.sourceWrites.removeValue(forKey: buttonStyleLabelKey)
        let label = label1 ?? label2
        let style = inputs.layouts.buttonStyles.popLast()
        let styleType = style?.type ?? DefaultButtonStyle.self

        func makeStyleBody<S: PrimitiveButtonStyle, T>(_: S.Type, graph: _GraphValue<T>, inputs: _ViewInputs) -> _ViewOutputs {
            S.Body._makeView(view: graph.unsafeCast(to: S.Body.self), inputs: inputs)
        }
        let outputs = makeStyleBody(styleType, graph: view[\._body], inputs: inputs)
        
        if let body = outputs.view {
            let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
                ResolvedButtonStyleViewContext(buttonStyle: style,
                                               label: label,
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

extension ResolvedButtonStyle: _PrimitiveView {
}

private class ResolvedButtonStyleViewContext: GenericViewContext<ResolvedButtonStyle> {
    let buttonStyle: PrimitiveButtonStyleProxy?
    let label: ViewProxy?

    init(buttonStyle: PrimitiveButtonStyleProxy?, label: ViewProxy?, graph: _GraphValue<ResolvedButtonStyle>, body: ViewContext, inputs: _GraphInputs) {
        self.buttonStyle = buttonStyle
        self.label = label
        super.init(graph: graph, body: body, inputs: inputs)
    }

    override func updateView(_ view: inout ResolvedButtonStyle) {
        if let buttonStyle {
            guard let style = buttonStyle.resolve(self) else {
                fatalError("Unable to resolve button style")
            }
            view._style = style
        }
        let role = view.configuration.role
        let label = PrimitiveButtonStyleConfiguration.Label(label)
        let action = view.configuration.action
        let buttonAction: ButtonAction = { [weak self] in
            self?.onDispatchButtonAction(action)
        }
        view.configuration = PrimitiveButtonStyleConfiguration(role: role, label: label, action: buttonAction)
        view._isPressing = false
        view._pressingCallback = { [weak self] isPressed in
            self?.onButtonPressing(isPressed)
        }
    }

    func onButtonPressing(_ isPressed: Bool) {
        self.view?._isPressing = isPressed
        self.body.updateContent()
    }

    func onDispatchButtonAction(_ action: @escaping ButtonAction) {
        self.sharedContext.auxiliarySceneContext?.dismissPopup(withParentContext: true)
        self.sharedContext.alertDismissAction?()
        let box = UnsafeBox(action)
        Task { @MainActor in
            box.value()
        }
    }

}
