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
    var _menuItemStyle = _MenuItemButtonStyle()
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
        fatalError("Implement with AG")
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }
}

extension ResolvedButtonStyle: _PrimitiveView {
}

