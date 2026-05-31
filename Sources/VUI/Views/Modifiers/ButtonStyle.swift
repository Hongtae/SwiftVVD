//
//  File: ButtonStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
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
    public static let confirm = ButtonRole(_role: .confirm)
    public static let close = ButtonRole(_role: .close)

    enum Role: UInt8 {
        case destructive = 1
        case cancel = 4
        case confirm = 5
        case close = 6
    }
    let _role: Role
}

// LinkDestination stores URL/navigation button destinations.
struct LinkDestination {
    let url: URL
}

// ButtonAction: multi-payload enum, 3 cases.
// Internal type. Public callers use PrimitiveButtonStyleConfiguration.trigger().
enum ButtonAction {
    // case 0: standard action closure
    case handler(() -> Void)
    // case 1: URL/navigation destination (internal, used by Link-style buttons)
    case destination(LinkDestination)
    // case 2: App Intents action payload. This path is inert in the local runtime.
    case appIntentAction(_AppIntentActionStorage)

    func callAsFunction() {
        switch self {
        case .handler(let fn): fn()
        case .destination, .appIntentAction: break
        }
    }
}

// _AppIntentActionStorage: fixed-size storage for App Intents ButtonAction payload.
struct _AppIntentActionStorage {
    private let _storage: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64) = (0,0,0,0,0,0)
}

public struct PrimitiveButtonStyleConfiguration {
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }
    public let role: ButtonRole?
    public let label: Label
    let action: ButtonAction
    public func trigger() {
        action.callAsFunction()
    }
}

extension PrimitiveButtonStyleConfiguration.Label {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        guard let source = inputs.base.customInputs.value(forKey: SourceInput<Self>.self).top else {
            return _ViewOutputs()
        }
        let innerPosAttr = graph.makeInput(value: CGPoint.zero)
        let innerSizeAttr = graph.makeInput(value: ViewSize(.zero))
        var innerInputs = inputs
        innerInputs.position = innerPosAttr
        innerInputs.size = innerSizeAttr
        let innerOutputs = source.makeView(view: view, inputs: innerInputs)
        guard let innerLCAttr = innerOutputs._layoutComputer.attribute else {
            return innerOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let innerLC = innerLCAttr.value
            return LayoutComputer(
                sizeThatFits: { innerLC.sizeThatFits($0) },
                spacing: innerLC.spacing,
                place: { position, anchor, proposal in
                    let size = innerLC.sizeThatFits(proposal)
                    let origin = CGPoint(x: position.x - size.width * anchor.x,
                                         y: position.y - size.height * anchor.y)
                    innerPosAttr.setValue(origin)
                    innerSizeAttr.setValue(ViewSize(size))
                    innerLC.place(at: position, anchor: anchor, proposal: proposal)
                },
                explicitAlignment: { innerLC.explicitAlignment($0, at: $1) }
            )
        }
        return _ViewOutputs(preferences: innerOutputs.preferences, layoutComputer: OptionalAttribute(lcAttr))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension PrimitiveButtonStyleConfiguration.Label: _PrimitiveView {}

// PrimitiveButtonStyle built-in implementations

public struct DefaultButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DefaultButtonStyleBody(configuration: configuration)
    }
}

private struct _DefaultButtonStyleBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @State private var isPressed = false

    var body: some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 4).inset(by: 0.1)
                    .fill(isPressed ? Color(hue: 1, saturation: 0, brightness: 0.9) : .white)
                RoundedRectangle(cornerRadius: 4).strokeBorder(.black)
            }
            .foregroundStyle(Color.black)
            ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }
}

public struct BorderlessButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _BorderlessButtonStyleBody(configuration: configuration)
    }
}

private struct _BorderlessButtonStyleBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @State private var isPressed = false

    var body: some View {
        configuration.label
            .padding(4)
            .foregroundStyle(isPressed ? Color.black : Color.gray)
            ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }
}

public struct LinkButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _LinkButtonStyleBody(configuration: configuration)
    }
}

private struct _LinkButtonStyleBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @State private var isPressed = false

    var body: some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 4).strokeBorder(.black)
            }
            ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }
}

public struct PlainButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Button(configuration).buttonStyle(PlainButtonStyleBase())
    }
}

private struct PlainButtonStyleBase: ButtonStyle {
    @Environment(\.isEnabled) var _isEnabled: Bool
    @Environment(\.isFocused) var _isFocused: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) { configuration.label }
            .opacity(_isEnabled ? (configuration.isPressed ? 0.75 : 1.0) : 0.5)
    }
}

public struct BorderedButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _BorderedButtonStyleBody(configuration: configuration)
    }
}

private struct _BorderedButtonStyleBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @State private var isPressed = false

    var body: some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 4).inset(by: 0.1)
                    .fill(isPressed ? Color(hue: 1, saturation: 0, brightness: 0.9) : .white)
                RoundedRectangle(cornerRadius: 4).strokeBorder(.black)
            }
            .foregroundStyle(Color.black)
            ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }
}

public struct BorderedProminentButtonStyle: PrimitiveButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _BorderedProminentButtonStyleBody(configuration: configuration)
    }
}

private struct _BorderedProminentButtonStyleBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @State private var isPressed = false

    var body: some View {
        configuration.label
            .padding(4)
            .background {
                RoundedRectangle(cornerRadius: 4).inset(by: 0.1)
                    .fill(isPressed ? Color(hue: 1, saturation: 0, brightness: 0.9) : .blue)
                RoundedRectangle(cornerRadius: 4).strokeBorder(.black)
            }
            .foregroundStyle(Color.white)
            ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }
}

struct _MenuItemButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        _MenuItemButtonBody(configuration: configuration)
    }
}

private struct _MenuItemButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isHovered ? Color.blue : Color.clear)
            configuration.label
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .foregroundStyle(isHovered ? Color.white : Color.black)
        ._onButtonGesture(pressing: { _ in }, perform: { configuration.trigger() })
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

extension PrimitiveButtonStyle where Self == BorderedProminentButtonStyle {
    public static var borderedProminent: BorderedProminentButtonStyle { .init() }
}

// ButtonStyle (high-level, wraps PrimitiveButtonStyle)

public protocol ButtonStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ButtonStyleConfiguration
}

public struct ButtonStyleConfiguration {
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }
    public let role: ButtonRole?
    public let label: ButtonStyleConfiguration.Label
    public let isPressed: Bool
}

extension ButtonStyleConfiguration.Label {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        guard let source = inputs.base.customInputs.value(forKey: SourceInput<PrimitiveButtonStyleConfiguration.Label>.self).top else {
            return _ViewOutputs()
        }
        let innerPosAttr = graph.makeInput(value: CGPoint.zero)
        let innerSizeAttr = graph.makeInput(value: ViewSize(.zero))
        var innerInputs = inputs
        innerInputs.position = innerPosAttr
        innerInputs.size = innerSizeAttr
        let innerOutputs = source.makeView(view: view, inputs: innerInputs)
        guard let innerLCAttr = innerOutputs._layoutComputer.attribute else {
            return innerOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let innerLC = innerLCAttr.value
            return LayoutComputer(
                sizeThatFits: { innerLC.sizeThatFits($0) },
                spacing: innerLC.spacing,
                place: { position, anchor, proposal in
                    let size = innerLC.sizeThatFits(proposal)
                    let origin = CGPoint(x: position.x - size.width * anchor.x,
                                         y: position.y - size.height * anchor.y)
                    innerPosAttr.setValue(origin)
                    innerSizeAttr.setValue(ViewSize(size))
                    innerLC.place(at: position, anchor: anchor, proposal: proposal)
                },
                explicitAlignment: { innerLC.explicitAlignment($0, at: $1) }
            )
        }
        return _ViewOutputs(preferences: innerOutputs.preferences, layoutComputer: OptionalAttribute(lcAttr))
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ButtonStyleConfiguration.Label: _PrimitiveView {}

// WrappedButtonStyle: ButtonStyle-to-PrimitiveButtonStyle adapter

struct WrappedButtonStyle<S: ButtonStyle>: PrimitiveButtonStyle {
    let style: S

    func makeBody(configuration: PrimitiveButtonStyleConfiguration) -> some View {
        WrappedButtonStyleBody(style: style, configuration: configuration)
    }
}

// WrappedButtonStyleBody tracks isPressed state and calls S.makeBody(configuration:)
struct WrappedButtonStyleBody<S: ButtonStyle>: View {
    let style: S
    let configuration: PrimitiveButtonStyleConfiguration

    var body: some View {
        ButtonBehavior(
            action: configuration.trigger,
            content: { isPressed in
                style.resolvedBody(configuration: ButtonStyleConfiguration(
                    role: configuration.role,
                    label: ButtonStyleConfiguration.Label(),
                    isPressed: isPressed
                ))
            }
        )
    }
}

// ButtonBehavior manages pressing state and attaches gesture.
// WrappedButtonStyleBody.body returns ButtonBehavior<ResolvedButtonStyleBody<S>>.
struct ButtonBehavior<V: View>: View {
    let action: () -> Void
    let content: (Bool) -> V
    @State private var isPressed: Bool = false

    func pressing(_ value: Bool) {
        isPressed = value
    }

    func ended() {
        action()
    }

    var body: some View {
        content(isPressed)
            ._onButtonGesture(pressing: pressing, perform: ended)
    }
}

// ResolvedButtonStyleBody calls S.makeBody(configuration:) with isPressed from ButtonBehavior
struct ResolvedButtonStyleBody<S: ButtonStyle>: View {
    let style: S
    let configuration: ButtonStyleConfiguration

    var body: some View {
        style.makeBody(configuration: configuration)
    }
}

extension ButtonStyle {
    func resolvedBody(configuration: ButtonStyleConfiguration) -> ResolvedButtonStyleBody<Self> {
        ResolvedButtonStyleBody(style: self, configuration: configuration)
    }
}

// ButtonStyleWriter: _GraphInputsModifier that injects AnyButtonStyleType into ButtonStyleInput.
// Has no stored fields. The modifier instance is not used in _makeInputs.
// StyleInput stack push is handled by ButtonStyleModifier via StyleModifier._makeView default impl.
struct ButtonStyleWriter<S: PrimitiveButtonStyle>: _GraphInputsModifier, ViewModifier {
    typealias Body = Never

    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        let anyType = AnyButtonStyleType(S.self)
        inputs.customInputs.setValue(anyType, forKey: ButtonStyleInput.self)
        if anyType.isTopLevelStyle {
            inputs.customInputs.setValue(anyType, forKey: EffectiveButtonStyleInput.self)
        }
    }
}

// Container modifiers (body(content:) based)

struct PrimitiveButtonStyleContainerModifier<S: PrimitiveButtonStyle>: ViewModifier {
    let style: S

    func body(content: Content) -> some View {
        content
            .modifier(ButtonStyleModifier<S>(style: style))
            .modifier(ButtonStyleWriter<S>())
    }
}

struct ButtonStyleContainerModifier<S: ButtonStyle>: ViewModifier {
    let style: S

    func body(content: Content) -> some View {
        content
            .modifier(ButtonStyleModifier<WrappedButtonStyle<S>>(style: WrappedButtonStyle(style: style)))
            .modifier(ButtonStyleWriter<WrappedButtonStyle<S>>())
    }
}

// AnyButtonStyleType: type-erased PrimitiveButtonStyle type identity.
// `any PrimitiveButtonStyle.Type` existential metatype has exactly this layout.
// Stored by ButtonStyleWriter._makeInputs in ButtonStyleInput / EffectiveButtonStyleInput.
struct AnyButtonStyleType: Equatable {
    let _styleType: any PrimitiveButtonStyle.Type

    init<S: PrimitiveButtonStyle>(_ type: S.Type) {
        _styleType = type
    }

    var isTopLevelStyle: Bool { true }

    static func == (lhs: Self, rhs: Self) -> Bool {
        ObjectIdentifier(lhs._styleType as Any.Type) == ObjectIdentifier(rhs._styleType as Any.Type)
    }
}

// ButtonStyleInput: current active PrimitiveButtonStyle type for the view channel.
// Set by ButtonStyleWriter._makeInputs for every buttonStyle() application.
struct ButtonStyleInput: ViewInput {
    typealias Value = AnyButtonStyleType
    static var defaultValue: AnyButtonStyleType { AnyButtonStyleType(DefaultButtonStyle.self) }
    var description: String { "ButtonStyleInput" }
}

// EffectiveButtonStyleInput: top-level effective style type cache in the graph channel.
// Set by ButtonStyleWriter._makeInputs when isTopLevelStyle == true.
// No ViewInput conformance. Stored in the base channel.
struct EffectiveButtonStyleInput: GraphInput {
    typealias Value = AnyButtonStyleType
    static var defaultValue: AnyButtonStyleType { AnyButtonStyleType(DefaultButtonStyle.self) }
    var description: String { "EffectiveButtonStyleInput" }
}

extension View {
    public func buttonStyle<S>(_ style: S) -> some View where S: PrimitiveButtonStyle {
        modifier(PrimitiveButtonStyleContainerModifier(style: style))
    }

    public func buttonStyle<S>(_ style: S) -> some View where S: ButtonStyle {
        modifier(ButtonStyleContainerModifier(style: style))
    }
}
