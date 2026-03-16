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
                role: role,
                label: PrimitiveButtonStyleConfiguration.Label(),
                action: action))
        .modifier(StaticSourceWriter<PrimitiveButtonStyleConfiguration.Label, Label>(source: label))
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

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let isPressingAttr: Attribute<Bool> = graph.makeInput(value: false)
        let stack = inputs.base.customInputs.value(forKey: StyleInput<PrimitiveButtonStyleConfiguration>.self)

        func wirePressingBody<S: PrimitiveButtonStyleWithPressingBody>(_ style: S, inputs: _ViewInputs) -> _ViewOutputs {
            let bodyAttr = graph.makeRule {
                let rs = view._attribute.value
                let config = PrimitiveButtonStyleConfiguration(
                    role: rs.configuration.role,
                    label: rs.configuration.label,
                    action: rs.configuration.action)
                let isPressing = isPressingAttr.value
                return style.makeBody(configuration: config, isPressing: isPressing, callback: { v in
                    isPressingAttr.setValue(v)
                })
            }
            return makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
        }

        func wireBody(_ style: some PrimitiveButtonStyle, inputs: _ViewInputs) -> _ViewOutputs {
            if let sp = style as? any PrimitiveButtonStyleWithPressingBody {
                return wirePressingBody(sp, inputs: inputs)
            }
            let bodyAttr = graph.makeRule {
                let rs = view._attribute.value
                let config = PrimitiveButtonStyleConfiguration(
                    role: rs.configuration.role,
                    label: rs.configuration.label,
                    action: rs.configuration.action)
                return style.makeBody(configuration: config)
            }
            return makeView(view: _GraphValue(_attribute: bodyAttr), inputs: inputs)
        }

        if let (head, tail) = stack.popping() {
            var poppedInputs = inputs
            poppedInputs.base.customInputs.setValue(tail, forKey: StyleInput<PrimitiveButtonStyleConfiguration>.self)
            let style = head.primStyle ?? DefaultButtonStyle.automatic
            return wireBody(style, inputs: poppedInputs)
        }
        return wireBody(DefaultButtonStyle.automatic, inputs: inputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

extension ResolvedButtonStyle: _PrimitiveView {
}

