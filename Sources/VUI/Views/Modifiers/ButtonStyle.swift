//
//  File: ButtonStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol PrimitiveButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = PrimitiveButtonStyleConfiguration
}

public struct ButtonRole: Equatable, Sendable {
    public static let destructive = ButtonRole(_role: .destructive)
    public static let cancel = ButtonRole(_role: .cancel)

    enum Role: UInt8 {
        case destructive = 1
        case cancel = 4
    }
    let _role: Role
}

typealias ButtonAction = ()->Void

public struct PrimitiveButtonStyleConfiguration {
    public struct Label: View {
        public typealias Body = Never
        let view: ViewProxy?
    }
    public let role: ButtonRole?
    public let label: Label
    let action: ButtonAction
    public func trigger() {
        action()
    }
}

extension PrimitiveButtonStyleConfiguration.Label {
    init(_ view: ViewProxy? = nil) {
        self.view = view
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            PrimitiveButtonStyleConfigurationLabelViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            PrimitiveButtonStyleConfigurationLabelViewContext(graph: graph, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
    }
}

extension PrimitiveButtonStyleConfiguration.Label: _PrimitiveView {}

protocol PrimitiveButtonStyleWithPressingBody {
    associatedtype PressingBody: View
    @ViewBuilder func makeBody(configuration: PrimitiveButtonStyleConfiguration,
                               isPressing: Bool,
                               callback: ((Bool)->Void)?) -> Self.PressingBody
}

public struct DefaultButtonStyle: PrimitiveButtonStyle, PrimitiveButtonStyleWithPressingBody {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration: configuration, isPressing: false)
    }

    func buttonColor(isPressed: Bool) -> Color {
        isPressed ? Color(hue: 1, saturation: 0, brightness: 0.9) : .white
    }

    func textColor(isPressed: Bool) -> Color {
        .black
    }

    func makeBody(configuration: Configuration, isPressing: Bool, callback: ((Bool)->Void)? = nil) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).inset(by: 0.1).fill(buttonColor(isPressed: isPressing))
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            .foregroundStyle(textColor(isPressed: isPressing))
            ._onButtonGesture(pressing: { isPressed in
                callback?(isPressed)
            }, perform: {
                configuration.trigger()
            })
            .hoverBackground {
                RoundedRectangle(cornerRadius: 4).inset(by: -2).fill(.blue.opacity(0.7))
            }
    }
}

public struct BorderlessButtonStyle: PrimitiveButtonStyle, PrimitiveButtonStyleWithPressingBody {
    public init() {}

    func textColor(isPressed: Bool) -> Color {
        isPressed ?
            .black : .gray
    }

    public func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration: configuration, isPressing: false)
    }

    func makeBody(configuration: Configuration, isPressing: Bool, callback: ((Bool)->Void)? = nil) -> some View {
        configuration.label
            .padding(4)
            .foregroundStyle(textColor(isPressed: isPressing))
            ._onButtonGesture(pressing: { isPressed in
                callback?(isPressed)
            }, perform: {
                configuration.trigger()
            })
    }
}

public struct LinkButtonStyle: PrimitiveButtonStyle, PrimitiveButtonStyleWithPressingBody {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration: configuration, isPressing: false)
    }

    func makeBody(configuration: Configuration, isPressing: Bool, callback: ((Bool)->Void)? = nil) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            ._onButtonGesture(pressing: { isPressed in
                callback?(isPressed)
            }, perform: {
                configuration.trigger()
            })
    }
}

public struct PlainButtonStyle: PrimitiveButtonStyle, PrimitiveButtonStyleWithPressingBody {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration: configuration, isPressing: false)
    }

    func makeBody(configuration: Configuration, isPressing: Bool, callback: ((Bool)->Void)? = nil) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            ._onButtonGesture(pressing: { isPressed in
                callback?(isPressed)
            }, perform: {
                configuration.trigger()
            })
    }
}

public struct BorderedButtonStyle: PrimitiveButtonStyle, PrimitiveButtonStyleWithPressingBody {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration: configuration, isPressing: false)
    }

    func buttonColor(isPressed: Bool) -> Color {
        isPressed ? Color(hue: 1, saturation: 0, brightness: 0.9) : .white
    }

    func textColor(isPressed: Bool) -> Color {
        .black
    }

    func makeBody(configuration: Configuration, isPressing: Bool, callback: ((Bool)->Void)? = nil) -> some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius:4).inset(by: 0.1).fill(buttonColor(isPressed: isPressing))
                RoundedRectangle(cornerRadius:4).strokeBorder(.black)
            }
            .foregroundStyle(textColor(isPressed: isPressing))
            ._onButtonGesture(pressing: { isPressed in
                callback?(isPressed)
            }, perform: {
                configuration.trigger()
            })
    }
}

struct _MenuItemButtonStyle: PrimitiveButtonStyle, PrimitiveButtonStyleWithPressingBody {
    func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration: configuration, isPressing: false, callback: nil)
    }

    func makeBody(configuration: Configuration, isPressing: Bool, callback: ((Bool)->Void)? = nil) -> some View {
        _MenuItemButtonBody(configuration: configuration, isPressing: isPressing, callback: callback)
    }
}

private struct _MenuItemButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let isPressing: Bool
    let callback: ((Bool)->Void)?

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.blue : Color.clear)
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .border(.red, width: 1)
        .foregroundStyle(isHovered ? Color.white : Color.black)
        ._onButtonGesture(pressing: { isPressed in
            callback?(isPressed)
        }, perform: {
            configuration.trigger()
        })
        .onHover { isHovered = $0 }
    }
}

extension PrimitiveButtonStyle where Self == DefaultButtonStyle {
    public static var automatic: DefaultButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == BorderlessButtonStyle {
    public static var borderless: BorderlessButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == LinkButtonStyle {
    public static var link: LinkButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == PlainButtonStyle {
    public static var plain: PlainButtonStyle { .init() }
}

extension PrimitiveButtonStyle where Self == BorderedButtonStyle {
    public static var bordered: BorderedButtonStyle { .init() }
}

public protocol ButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}

public struct ButtonStyleConfiguration {
    public struct Label: View {
        public typealias Body = Never
        let view: PrimitiveButtonStyleConfiguration.Label
    }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

extension ButtonStyleConfiguration.Label {
    init(_ view: PrimitiveButtonStyleConfiguration.Label) {
        self.view = view
    }
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        PrimitiveButtonStyleConfiguration.Label._makeView(view: view[\.view], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        PrimitiveButtonStyleConfiguration.Label._makeViewList(view: view[\.view], inputs: inputs)
    }
}

extension ButtonStyleConfiguration.Label: _PrimitiveView {}

struct _DefaultButtonWithButtonStyle<Style>: PrimitiveButtonStyle, PrimitiveButtonStyleWithPressingBody where Style: ButtonStyle {
    let style: Style

    func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration: configuration, isPressing: false, callback: nil)
    }

    func makeBody(configuration: PrimitiveButtonStyleConfiguration, isPressing: Bool, callback: ((Bool) -> Void)?) -> some View {
        let config = ButtonStyleConfiguration(role: configuration.role,
                                              label: .init(configuration.label),
                                              isPressed: isPressing)
        return self.style.makeBody(configuration: config)
            ._onButtonGesture(pressing: { isPressed in
                callback?(isPressed)
            }, perform: {
                configuration.trigger()
            })
    }
}

struct PrimitiveButtonStyleProxy {
    let type: any PrimitiveButtonStyle.Type
    let graph: _GraphValue<Any>
    init<S: PrimitiveButtonStyle>(_ graph: _GraphValue<S>) {
        self.type = S.self
        self.graph = graph.unsafeCast(to: Any.self)
    }
    func resolve(_ resolver: some _GraphValueResolver) -> (any PrimitiveButtonStyle)? {
        resolver.value(atPath: graph) as? (any PrimitiveButtonStyle)
    }
}

struct PrimitiveButtonStyleContainerModifier<Style>: ViewModifier where Style: PrimitiveButtonStyle {
    let style: Style
    typealias Body = Never
}

extension PrimitiveButtonStyleContainerModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs.layouts.buttonStyles.append(PrimitiveButtonStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs.layouts.buttonStyles.append(PrimitiveButtonStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }
}

struct ButtonStyleContainerModifier<Style>: ViewModifier where Style: ButtonStyle {
    let style: Style
    typealias Body = Never

    var primitiveButtonStyle: some PrimitiveButtonStyle {
        _DefaultButtonWithButtonStyle(style: style)
    }

    var modifier: some ViewModifier {
        PrimitiveButtonStyleContainerModifier(style: primitiveButtonStyle)
    }

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        func make<T: ViewModifier>(modifier: _GraphValue<T>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
            T._makeView(modifier: modifier, inputs: inputs, body: body)
        }
        return make(modifier: modifier[\.modifier], inputs: inputs, body: body)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        func make<T: ViewModifier>(modifier: _GraphValue<T>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
            T._makeViewList(modifier: modifier, inputs: inputs, body: body)
        }
        return make(modifier: modifier[\.modifier], inputs: inputs, body: body)
    }
}

extension View {
    public func buttonStyle<S>(_ style: S) -> some View where S: PrimitiveButtonStyle {
        modifier(PrimitiveButtonStyleContainerModifier(style: style))
    }

    public func buttonStyle<S>(_ style: S) -> some View where S: ButtonStyle {
        modifier(ButtonStyleContainerModifier(style: style))
    }
}

private class PrimitiveButtonStyleConfigurationLabelViewContext: DynamicViewContext<PrimitiveButtonStyleConfiguration.Label> {
    override func updateContent() {
        let oldProxy = self.view?.view
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateView(&view)
            self.requiresContentUpdates = false
            self.view = view
        }
        if let proxy = self.view?.view {
            if self.body == nil || proxy != oldProxy {
                let outputs = proxy.makeView(_Graph(), inputs: _ViewInputs(base: self.inputs))
                self.body = outputs.view?.makeView()
            }
            self.body?.updateContent()
        } else {
            self.invalidate()
            fatalError("Unable to recover view for \(graph)")
        }
        self.sharedContext.needsLayout = true
    }
}
