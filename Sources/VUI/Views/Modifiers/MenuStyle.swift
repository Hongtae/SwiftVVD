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
        let view: ViewProxy?
    }

    public struct Content: View {
        public typealias Body = Never
        let view: ViewProxy?
    }

    public var label: MenuStyleConfiguration.Label { .init(view: _label) }
    public var content: MenuStyleConfiguration.Content { .init(view: _content) }

    let _label: ViewProxy?
    let _content: ViewProxy?
    let _primaryAction: (() -> Void)?

    init(_ label: ViewProxy?, _ content: ViewProxy?, primaryAction: (() -> Void)? = nil) {
        self._label = label
        self._content = content
        self._primaryAction = primaryAction
    }
}

extension MenuStyleConfiguration.Label: _PrimitiveView {}
extension MenuStyleConfiguration.Content: _PrimitiveView {}

extension MenuStyleConfiguration.Label {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationLabelViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationLabelViewContext(graph: graph, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
    }
}

extension MenuStyleConfiguration.Content {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationContentViewContext(graph: graph, inputs: inputs)
        }
        return _ViewOutputs(view: view)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let view = UnaryViewGenerator(graph: view, baseInputs: inputs.base) { graph, inputs in
            MenuStyleConfigurationContentViewContext(graph: graph, inputs: inputs)
        }
        return _ViewListOutputs(views: .staticList(view))
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

struct MenuStyleProxy {
    let type: any MenuStyle.Type
    let graph: _GraphValue<Any>
    init<S: MenuStyle>(_ graph: _GraphValue<S>) {
        self.type = S.self
        self.graph = graph.unsafeCast(to: Any.self)
    }
    func resolve(_ resolver: some _GraphValueResolver) -> (any MenuStyle)? {
        resolver.value(atPath: graph) as? (any MenuStyle)
    }
}

struct MenuStyleModifier<Style>: ViewModifier where Style: MenuStyle {
    let style: Style
    typealias Body = Never
}

extension MenuStyleModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        var inputs = inputs
        inputs.layouts.menuStyles.append(MenuStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        var inputs = inputs
        inputs.layouts.menuStyles.append(MenuStyleProxy(modifier[\.style]))
        return body(_Graph(), inputs)
    }
}

extension View {
    public func menuStyle<S>(_ style: S) -> some View where S: MenuStyle {
        modifier(MenuStyleModifier(style: style))
    }
}


/// Protocol for MenuStyleConfiguration components that contain a ViewProxy
private protocol MenuStyleConfigurationComponent: View {
    var view: ViewProxy? { get }
}

extension MenuStyleConfiguration.Label: MenuStyleConfigurationComponent {}
extension MenuStyleConfiguration.Content: MenuStyleConfigurationComponent {}

/// Base class for MenuStyleConfiguration component view contexts that manage ViewProxy resolution
private class MenuStyleConfigurationProxyViewContext<T>: DynamicViewContext<T> where T: MenuStyleConfigurationComponent {
    override func updateContent() {
        let oldProxy = self.view?.view
        self.view = nil
        if var view = value(atPath: self.graph) {
            self.resolveGraphInputs()
            self.updateView(&view)
            self.requiresContentUpdates = false
            self.view = view
        }
        if let view, let proxy = view.view {
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

private class MenuStyleConfigurationLabelViewContext: MenuStyleConfigurationProxyViewContext<MenuStyleConfiguration.Label> {
}

private class MenuStyleConfigurationContentViewContext: MenuStyleConfigurationProxyViewContext<MenuStyleConfiguration.Content> {
    override func sizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        var size = super.sizeThatFits(proposal)
        let menuStyle = MenuStyleContext()
        size.width = clamp(size.width,
                           min: menuStyle.minimumViewSize.width,
                           max: menuStyle.maximumViewSize.width)
        size.height = max(size.height, menuStyle.minimumViewSize.height)        
        return size
    }
}
