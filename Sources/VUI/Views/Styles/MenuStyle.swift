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
            // Both segments share one control owner. The initial segment keeps
            // ownership through dragging and decides its result on release.
            HStack(spacing: 0) {
                let labelBg: Color = isLabelPressing
                    ? .primaryFill
                    : isLabelHovered ? .secondaryFill : .clear
                let labelFg: Color = .primary
                configuration.label
                    .foregroundStyle(labelFg)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(labelBg, in: RoundedRectangle(cornerRadius: 5))
                    .onHover { isLabelHovered = $0 }
                
                Divider()
                
                let arrowBg: Color = isArrowPressing
                    ? .primaryFill
                    : isArrowHovered ? .secondaryFill : .clear
                let arrowFg: Color = .primary
                MenuChevronDownShape()
                    .stroke(arrowFg,
                            style: StrokeStyle(lineWidth: 1,
                                               lineCap: .round,
                                               lineJoin: .round))
                    .frame(width: 24, height: 28)
                    .background(arrowBg, in: RoundedRectangle(cornerRadius: 5))
                    .onHover { isArrowHovered = $0 }
            }
            .fixedSize()
            .background(BackgroundStyle(), in: RoundedRectangle(cornerRadius: 5))
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondaryFill, lineWidth: 1)
            }
            .modifier(MenuControlModifier(
                content: configuration.content,
                primaryAction: primaryAction,
                menuIndicatorWidth: 24,
                onPrimaryPressingChanged: { isLabelPressing = $0 },
                onMenuPressingChanged: { isArrowPressing = $0 },
                onPresentationChanged: configuration._onPresentationChanged
            ))
        } else {
            let bg: Color = isLabelPressing
                ? .primaryFill
                : isLabelHovered ? .secondaryFill : .clear
            let fg: Color = .primary
            configuration.label
                .foregroundStyle(fg)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bg, in: RoundedRectangle(cornerRadius: 5))
                .background(BackgroundStyle(), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.secondaryFill, lineWidth: 1)
                }
                .modifier(MenuControlModifier(
                    content: configuration.content,
                    onMenuPressingChanged: { isLabelPressing = $0 },
                    onPresentationChanged: configuration._onPresentationChanged
                ))
                .onHover { isLabelHovered = $0 }
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
            // Explicit button styling retains the same single split-control
            // event owner as the default style.
            HStack(spacing: 0) {
                let labelBg: Color = isLabelPressing ? .primaryFill
                                   : isLabelHovered ? .secondaryFill
                                   : .clear
                configuration.label
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(labelBg, in: RoundedRectangle(cornerRadius: 7))
                    .onHover { isLabelHovered = $0 }

                Divider()

                let menuBg: Color = isMenuPressing ? .primaryFill
                                  : isMenuHovered ? .secondaryFill
                                  : .clear
                MenuChevronDownShape()
                    .stroke(Color.primary,
                            style: StrokeStyle(lineWidth: 1,
                                               lineCap: .round,
                                               lineJoin: .round))
                    .frame(width: 24, height: 28)
                    .background(menuBg, in: RoundedRectangle(cornerRadius: 7))
                    .onHover { isMenuHovered = $0 }
            }
            .fixedSize()
            .background(BackgroundStyle(), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.secondaryFill, lineWidth: 1)
            }
            .modifier(MenuControlModifier(
                content: configuration.content,
                primaryAction: primaryAction,
                menuIndicatorWidth: 24,
                onPrimaryPressingChanged: { isLabelPressing = $0 },
                onMenuPressingChanged: { isMenuPressing = $0 },
                onPresentationChanged: configuration._onPresentationChanged
            ))
        } else {
            let bg: Color = isPressing ? .primaryFill
                          : isHovered  ? .secondaryFill
                          : .clear
            configuration.label
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(bg, in: RoundedRectangle(cornerRadius: 7))
                .background(BackgroundStyle(), in: RoundedRectangle(cornerRadius: 7))
                .overlay(alignment: .center) {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.secondaryFill, lineWidth: 1)
                }
                .modifier(MenuControlModifier(
                    content: configuration.content,
                    onMenuPressingChanged: { isPressing = $0 },
                    onPresentationChanged: configuration._onPresentationChanged
                ))
                .onHover { isHovered = $0 }
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

struct MenuStyleModifier<Style>: StyleModifier where Style: MenuStyle {
    typealias Body = Never
    typealias StyleConfiguration = MenuStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(configuration: MenuStyleConfiguration) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

extension View {
    public func menuStyle<S>(_ style: S) -> some View where S: MenuStyle {
        modifier(MenuStyleModifier(style: style))
    }
}


/// Protocol for MenuStyleConfiguration components that contain a ViewProxy
