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
    public struct Label: View, ViewAlias {
        public typealias Body = Never
    }

    public struct Content: View, ViewAlias {
        public typealias Body = Never
    }

    public var label: MenuStyleConfiguration.Label { .init() }
    public var content: MenuStyleConfiguration.Content { .init() }

    let _primaryAction: (() -> Void)?
    let _onPresentationChanged: ((Bool) -> Void)?

    init(primaryAction: (() -> Void)? = nil,
         onPresentationChanged: ((Bool) -> Void)? = nil) {
        self._primaryAction = primaryAction
        self._onPresentationChanged = onPresentationChanged
    }
}

extension MenuStyleConfiguration.Label: PrimitiveView {}
extension MenuStyleConfiguration.Content: PrimitiveView {}

struct _MenuStyleKey: GraphInput {
    static var defaultValue: (any MenuStyle)? { nil }
    static func valuesEqual(_ a: (any MenuStyle)?, _ b: (any MenuStyle)?) -> Bool { false }
    var description: String { "_MenuStyleKey" }
}

public struct DefaultMenuStyle: MenuStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        _DefaultMenuStyleBody(configuration: configuration)
    }
}

private struct MenuChevronDownShape: Shape {
    var glyphSize = CGSize(width: 8, height: 4)

    func path(in rect: CGRect) -> Path {
        let width = min(glyphSize.width, rect.width)
        let height = min(glyphSize.height, rect.height)
        let minX = rect.midX - width / 2
        let maxX = rect.midX + width / 2
        let topY = rect.midY - height / 2
        let bottomY = rect.midY + height / 2

        var path = Path()
        path.move(to: CGPoint(x: minX, y: topY))
        path.addLine(to: CGPoint(x: rect.midX, y: bottomY))
        path.addLine(to: CGPoint(x: maxX, y: topY))
        return path
    }
}

private struct _DefaultMenuStyleBody: View {
    let configuration: MenuStyleConfiguration
    @State private var isLabelHovered = false
    @State private var isLabelPressing = false
    @State private var isArrowHovered = false
    @State private var isArrowPressing = false

    var body: some View {
        if let primaryAction = configuration._primaryAction {
            // Standalone primary-action Menu is a split control: the label segment
            // performs the primary action, while the right-side indicator opens content.
            HStack(spacing: 0) {
                let labelBg: Color = isLabelPressing ? Color(white: 0.88) : isLabelHovered ? Color(white: 0.85) : .clear
                let labelFg: Color = .primary
                configuration.label
                    .foregroundStyle(labelFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(labelBg, in: RoundedRectangle(cornerRadius: 5))
                    .onHover { isLabelHovered = $0 }
                    ._onButtonGesture(pressing: { isLabelPressing = $0 }, perform: primaryAction)
                
                Divider()
                
                let arrowBg: Color = isArrowPressing ? Color(white: 0.88) : isArrowHovered ? Color(white: 0.85) : .clear
                let arrowFg: Color = .primary
                MenuChevronDownShape()
                    .stroke(arrowFg,
                            style: StrokeStyle(lineWidth: 1,
                                               lineCap: .round,
                                               lineJoin: .round))
                    .frame(width: 24, height: 28)
                    .background(arrowBg, in: RoundedRectangle(cornerRadius: 5))
                    .modifier(MenuDropdownModifier(
                        content: configuration.content,
                        onHoverChanged: { isArrowHovered = $0 },
                        onPressingChanged: { isArrowPressing = $0 },
                        onPresentationChanged: configuration._onPresentationChanged
                    ))
            }
            .fixedSize()
            .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
            }
        } else {
            let bg: Color = isLabelPressing ? Color(white: 0.88) : isLabelHovered ? Color(white: 0.85) : Color(white: 0.95)
            let fg: Color = .primary
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
                    onPressingChanged: { isLabelPressing = $0 },
                    onPresentationChanged: configuration._onPresentationChanged
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
    @State private var isLabelHovered = false
    @State private var isLabelPressing = false
    @State private var isMenuHovered = false
    @State private var isMenuPressing = false

    var body: some View {
        if let primaryAction = configuration._primaryAction {
            // Keep explicit ButtonMenuStyle on the same split trigger model as
            // the sampled standalone primary-action Menu path.
            HStack(spacing: 0) {
                let labelBg: Color = isLabelPressing ? Color(white: 0.88)
                                   : isLabelHovered ? Color(white: 0.93)
                                   : .clear
                configuration.label
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(labelBg, in: RoundedRectangle(cornerRadius: 7))
                    .onHover { isLabelHovered = $0 }
                    ._onButtonGesture(pressing: { isLabelPressing = $0 },
                                      perform: primaryAction)

                Divider()

                let menuBg: Color = isMenuPressing ? Color(white: 0.88)
                                  : isMenuHovered ? Color(white: 0.93)
                                  : .clear
                MenuChevronDownShape()
                    .stroke(Color.primary,
                            style: StrokeStyle(lineWidth: 1,
                                               lineCap: .round,
                                               lineJoin: .round))
                    .frame(width: 24, height: 28)
                    .background(menuBg, in: RoundedRectangle(cornerRadius: 7))
                    .modifier(MenuDropdownModifier(
                        content: configuration.content,
                        onHoverChanged: { isMenuHovered = $0 },
                        onPressingChanged: { isMenuPressing = $0 },
                        onPresentationChanged: configuration._onPresentationChanged
                    ))
            }
            .fixedSize()
            .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color(white: 0.7), lineWidth: 1)
            }
        } else {
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
                    onPressingChanged: { isPressing = $0 },
                    onPresentationChanged: configuration._onPresentationChanged
                ))
        }
    }
}

extension MenuStyle where Self == ButtonMenuStyle {
    public static var button: ButtonMenuStyle { .init() }
}

struct PlatformItemListMenuStyle: MenuStyle {
    @Namespace private var namespace
    @Environment(\.menuIndicatorVisibility)
    private var menuIndicatorVisibility
    @Environment(\.tintColor) private var tintColor

    func makeBody(configuration: Configuration) -> some View {
        _UnaryViewAdaptor(
            LabelGroup(content: configuration.label)
        )
        .platformItemIdentifier(String(describing: namespace))
        .platformItemTint(tintColor)
        .platformItemChildren(
            systemItem: .menu,
            primaryAction: configuration._primaryAction,
            menuIndicatorVisibility: menuIndicatorVisibility,
            controlSize: .regular
        ) {
            configuration.content
        }
    }
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
            onMenuOpenChanged: { isMenuOpen = $0 },
            onPresentationChanged: configuration._onPresentationChanged
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
