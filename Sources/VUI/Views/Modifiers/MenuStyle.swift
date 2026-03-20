//
//  File: MenuStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import VVD

public protocol MenuStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = MenuStyleConfiguration
}

public struct MenuStyleConfiguration {
    public struct Label: View {
        public typealias Body = Never
    }

    public struct Content: View {
        public typealias Body = Never
    }

    public var label: MenuStyleConfiguration.Label { .init() }
    public var content: MenuStyleConfiguration.Content { .init() }

    let _primaryAction: (() -> Void)?

    init(primaryAction: (() -> Void)? = nil) {
        self._primaryAction = primaryAction
    }
}

extension MenuStyleConfiguration.Label: _PrimitiveView {}
extension MenuStyleConfiguration.Content: _PrimitiveView {}

struct _MenuStyleKey: PropertyItem {
    static var defaultValue: (any MenuStyle)? { nil }
    var description: String { "_MenuStyleKey" }
}

extension MenuStyleConfiguration.Label {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        guard case .node(let source, _) = inputs.base.customInputs.value(forKey: SourceInput<Self>.self) else {
            return _ViewOutputs()
        }
        let innerPosAttr = graph.makeInput(value: CGPoint.zero)
        let innerSizeAttr = graph.makeInput(value: ViewSize(.zero))
        var innerInputs = inputs
        innerInputs.position = innerPosAttr
        innerInputs.size = innerSizeAttr
        let innerOutputs = source.makeView(inputs: innerInputs)
        guard let innerLCAttr = innerOutputs._layoutComputer.attribute else {
            return innerOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let innerLC = innerLCAttr.value
            return LayoutComputer(
                sizeThatFits: innerLC._sizeThatFits,
                spacing: innerLC._spacing,
                dimensions: innerLC._dimensions,
                place: { position, anchor, proposal in
                    let size = innerLC.sizeThatFits(proposal)
                    let origin = CGPoint(x: position.x - size.width * anchor.x,
                                         y: position.y - size.height * anchor.y)
                    innerPosAttr.setValue(origin)
                    innerSizeAttr.setValue(ViewSize(size))
                    innerLC.place(at: position, anchor: anchor, proposal: proposal)
                }
            )
        }
        return _ViewOutputs(preferences: innerOutputs.preferences, layoutComputer: OptionalAttribute(lcAttr))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

extension MenuStyleConfiguration.Content {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        guard case .node(let source, _) = inputs.base.customInputs.value(forKey: SourceInput<Self>.self) else {
            return _ViewOutputs()
        }
        let innerPosAttr = graph.makeInput(value: CGPoint.zero)
        let innerSizeAttr = graph.makeInput(value: ViewSize(.zero))
        var innerInputs = inputs
        innerInputs.position = innerPosAttr
        innerInputs.size = innerSizeAttr
        let innerOutputs = source.makeView(inputs: innerInputs)
        guard let innerLCAttr = innerOutputs._layoutComputer.attribute else {
            return innerOutputs
        }
        let lcAttr: Attribute<LayoutComputer> = graph.makeRule {
            let innerLC = innerLCAttr.value
            return LayoutComputer(
                sizeThatFits: innerLC._sizeThatFits,
                spacing: innerLC._spacing,
                dimensions: innerLC._dimensions,
                place: { position, anchor, proposal in
                    let size = innerLC.sizeThatFits(proposal)
                    let origin = CGPoint(x: position.x - size.width * anchor.x,
                                         y: position.y - size.height * anchor.y)
                    innerPosAttr.setValue(origin)
                    innerSizeAttr.setValue(ViewSize(size))
                    innerLC.place(at: position, anchor: anchor, proposal: proposal)
                }
            )
        }
        return _ViewOutputs(preferences: innerOutputs.preferences, layoutComputer: OptionalAttribute(lcAttr))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }
}

public struct DefaultMenuStyle: MenuStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DefaultMenuStyleBody(configuration: configuration)
    }
}

private struct _DefaultMenuStyleBody: View {
    let configuration: MenuStyleConfiguration
    @State private var isLabelHovered = false
    @State private var isLabelPressing = false
    @State private var isArrowHovered = false
    @State private var isArrowPressing = false

    private struct TriangleDown: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    var body: some View {
        if let primaryAction = configuration._primaryAction {
            HStack(spacing: 0) {
                let labelBg: Color = isLabelPressing ? Color.blue.opacity(0.8) : isLabelHovered ? Color(white: 0.85) : .clear
                let labelFg: Color = isLabelPressing ? .white : .primary
                configuration.label
                    .foregroundStyle(labelFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(labelBg, in: RoundedRectangle(cornerRadius: 5))
                    .onHover { isLabelHovered = $0 }
                    ._onButtonGesture(pressing: { isLabelPressing = $0 }, perform: primaryAction)
                
                Divider()
                
                let arrowBg: Color = isArrowPressing ? Color.blue.opacity(0.8) : isArrowHovered ? Color(white: 0.85) : .clear
                let arrowFg: Color = isArrowPressing ? .white : .primary
                TriangleDown()
                    .fill(arrowFg)
                    .frame(width: 8, height: 5)
                    .padding(.horizontal, 8)
                    .frame(maxHeight: .infinity)
                    .background(arrowBg, in: RoundedRectangle(cornerRadius: 5))
                    .modifier(MenuDropdownModifier(
                        content: configuration.content,
                        onHoverChanged: { isArrowHovered = $0 },
                        onPressingChanged: { isArrowPressing = $0 }
                    ))
            }
            .fixedSize()
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            }
        } else {
            let bg: Color = isLabelPressing ? Color.blue.opacity(0.8) : isLabelHovered ? Color(white: 0.85) : Color(white: 0.95)
            let fg: Color = isLabelPressing ? .white : .primary
            configuration.label
                .foregroundStyle(fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bg, in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                }
                .modifier(MenuDropdownModifier(
                    content: configuration.content,
                    onHoverChanged: { isLabelHovered = $0 },
                    onPressingChanged: { isLabelPressing = $0 }
                ))
        }
    }
}

extension MenuStyle where Self == DefaultMenuStyle {
    public static var automatic: DefaultMenuStyle { .init() }
}

public struct ButtonMenuStyle: MenuStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _ButtonMenuStyleBody(configuration: configuration)
    }
}

private struct _ButtonMenuStyleBody: View {
    let configuration: MenuStyleConfiguration
    @State private var isHovered = false
    @State private var isPressing = false

    var body: some View {
        let bg: Color = isPressing ? Color(white: 0.88)
                      : isHovered  ? Color(white: 0.93)
                      : Color(white: 0.97)
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(bg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(white: 0.7), lineWidth: 1)
            }
            .modifier(MenuDropdownModifier(
                content: configuration.content,
                onHoverChanged: { isHovered = $0 },
                onPressingChanged: { isPressing = $0 }
            ))
    }
}

extension MenuStyle where Self == ButtonMenuStyle {
    public static var button: ButtonMenuStyle { .init() }
}

struct _MenuItemMenuStyle: MenuStyle {
    func makeBody(configuration: Configuration) -> some View {
        _MenuItemMenuBody(configuration: configuration)
    }
}

private struct _MenuItemMenuBody: View {
    let configuration: MenuStyleConfiguration
    @State private var isHovered = false
    @State private var isMenuOpen = false

    private struct TriangleRight: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.closeSubpath()
            return path
        }
    }

    var body: some View {
        let bgColor: Color = isHovered ? .blue : isMenuOpen ? Color.blue.opacity(0.8) : .clear
        let fgColor: Color = (isHovered || isMenuOpen) ? .white : .black
        let arrowColor: Color = (isHovered || isMenuOpen) ? .white : Color(white: 0.4)
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(bgColor)
            HStack {
                configuration.label
                    .padding(.vertical, 4)
                    .padding(.leading, 8)
                Spacer()
                TriangleRight()
                    .fill(arrowColor)
                    .frame(width: 4, height: 7)
                    .padding(.trailing, 8)
            }
        }
        .foregroundStyle(fgColor)
        .modifier(MenuDropdownModifier(
            content: configuration.content,
            onHoverChanged: { isHovered = $0 },
            onMenuOpenChanged: { isMenuOpen = $0 }
        ))
        ._onButtonGesture(pressing: { _ in }, perform: { configuration._primaryAction?() })
        //.border(.red, width: 1)
    }
}

struct MenuStyleModifier<Style>: ViewModifier where Style: MenuStyle {
    let style: Style
    typealias Body = Never
}

extension MenuStyleModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        let styleExistential: (any MenuStyle)? = modifier._attribute.value.style
        inputs.base.customInputs.setValue(styleExistential, forKey: _MenuStyleKey.self)
        return body(_Graph(), inputs)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        let styleExistential: (any MenuStyle)? = modifier._attribute.value.style
        inputs.base.customInputs.setValue(styleExistential, forKey: _MenuStyleKey.self)
        return body(_Graph(), inputs)
    }
}

extension View {
    public func menuStyle<S>(_ style: S) -> some View where S: MenuStyle {
        modifier(MenuStyleModifier(style: style))
    }
}


/// Protocol for MenuStyleConfiguration components that contain a ViewProxy