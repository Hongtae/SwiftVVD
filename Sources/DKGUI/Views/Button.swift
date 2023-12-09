//
//  File: Button.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

public struct Button<Label> : View where Label : View {
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
            configuration:PrimitiveButtonStyleConfiguration(
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
    public init<S>(_ title: S, action: @escaping () -> Void) where S : StringProtocol {
        self.role = nil
        self.action = action
        self.label = Text(title)
    }
}

extension Button where Label == DKGUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) {
        self.init(action: action) {
            Label(titleKey, systemImage: systemImage)
        }
    }
    public init<S>(_ title: S, systemImage: String, action: @escaping () -> Void) where S : StringProtocol {
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
    public init<S>(_ title: S, role: ButtonRole?, action: @escaping () -> Void) where S : StringProtocol {
        self.label = Text(title)
        self.role = role
        self.action = action
    }
}

extension Button where Label == DKGUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            Label(titleKey, systemImage: systemImage)
        }
    }
    public init<S>(_ title: S, systemImage: String, role: ButtonRole?, action: @escaping () -> Void) where S : StringProtocol {
        self.init(role: role, action: action) {
            Label(title, systemImage: systemImage)
        }
    }
}

struct ResolvedButtonStyle: View {
    typealias Body = Never
    var body: Never {
        fatalError()
    }

    init(configuration: PrimitiveButtonStyleConfiguration) {
    }
}

extension ResolvedButtonStyle: _PrimitiveView {
}

extension ResolvedButtonStyle: _ViewProxyProvider {
    func makeViewProxy(inputs: _ViewInputs) -> ViewProxy {
        ButtonProxy(inputs: inputs)
    }
}

class ButtonProxy: ViewProxy {
    init(inputs: _ViewInputs) {
        super.init(inputs: inputs)
    }

    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        CGSize(width: 100, height: 40)
    }

    override func draw(frame: CGRect, context: GraphicsContext) {
        if self.frame.width > 0 && self.frame.height > 0 {
            context.fill(Path(frame), with: .color(.red))
        }
    }

    override func processMouseEvent(type: MouseEventType,
                                    deviceType: MouseEventDevice,
                                    deviceID: Int,
                                    buttonID: Int,
                                    location: CGPoint,
                                    dedicated: Bool) -> Bool {
        if (super.processMouseEvent(type: type,
                                    deviceType: deviceType,
                                    deviceID: deviceID,
                                    buttonID: buttonID,
                                    location: location,
                                    dedicated: dedicated)) {
            return true
        }
        if type == .buttonDown {
            _ = self.captureMouse(withDeviceID: deviceID)
        } else if type == .buttonUp {
            if self.hasCapturedMouse(withDeviceID: deviceID) {
                if (self.frame.contains(location)) {
                    Log.debug("Mouse Click: \(location)")
                } else {
                    Log.debug("Mouse Click: \(location) - Cancelled / Touch Up Outside")
                }
                self.releaseMouse(withDeviceID: deviceID)
            }
        }
        return false
    }
}
