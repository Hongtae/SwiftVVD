//
//  File: LabelStyle.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol LabelStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = LabelStyleConfiguration
}

public struct LabelStyleConfiguration {
    public struct Title: ViewAlias {
        public typealias Body = Never
    }
    public struct Icon: ViewAlias {
        public typealias Body = Never
    }
    public var title: LabelStyleConfiguration.Title { .init() }
    public var icon: LabelStyleConfiguration.Icon { .init() }
}

extension LabelStyleConfiguration.Title: View {}
extension LabelStyleConfiguration.Icon: View {}
extension LabelStyleConfiguration.Title: _PrimitiveView {}
extension LabelStyleConfiguration.Icon: _PrimitiveView {}


extension LabelStyleConfiguration.Title {
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
        let innerOutputs = source.makeView(view: view, inputs: innerInputs)
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

extension LabelStyleConfiguration.Icon {
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
        let innerOutputs = source.makeView(view: view, inputs: innerInputs)
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

// EffectiveLabelStyle — subset of LabelStyle that can be expressed as an enum.
// Set in EffectiveLabelStyle environment key alongside StyleInput<LabelStyleConfiguration>.
enum EffectiveLabelStyle: Equatable, Sendable {
    case titleAndIcon
    case titleOnly
    case iconOnly
}

struct EffectiveLabelStyleKey: EnvironmentKey {
    static var defaultValue: EffectiveLabelStyle? { nil }
}

extension EnvironmentValues {
    var effectiveLabelStyle: EffectiveLabelStyle? {
        get { self[EffectiveLabelStyleKey.self] }
        set { self[EffectiveLabelStyleKey.self] = newValue }
    }
}

// TitleAndIconLabelStyle internal environment keys
struct LabelReservedIconWidthKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}
struct LabelIconToTitleSpacingKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}
struct LabelDefaultIconToTitleSpacingKey: EnvironmentKey {
    static var defaultValue: CGFloat? { nil }
}

extension EnvironmentValues {
    var _reservedIconWidth: CGFloat? {
        get { self[LabelReservedIconWidthKey.self] }
        set { self[LabelReservedIconWidthKey.self] = newValue }
    }
    var _iconToTitleSpacing: CGFloat? {
        get { self[LabelIconToTitleSpacingKey.self] }
        set { self[LabelIconToTitleSpacingKey.self] = newValue }
    }
    var _defaultIconToTitleSpacing: CGFloat? {
        get { self[LabelDefaultIconToTitleSpacingKey.self] }
        set { self[LabelDefaultIconToTitleSpacingKey.self] = newValue }
    }
}

public struct DefaultLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.icon
            configuration.title
        }
    }
}

public struct IconOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

// LabelItemRole — internal enum for tagging label components in multi-view contexts.
// Used via _ContainerValueWritingModifier in TitleAndIconLabelStyle.makeBody.
enum LabelItemRole {
    case icon
    case title
}

extension ContainerValues {
    var labelItemRole: LabelItemRole? {
        get { self[LabelItemRoleKey.self] }
        set { self[LabelItemRoleKey.self] = newValue }
    }
}

private struct LabelItemRoleKey: ContainerValueKey {
    static var defaultValue: LabelItemRole? { nil }
}

// LabelIconPlatformItemModifier — zero-size ViewModifier applied to the icon
// in TitleAndIconLabelStyle.makeBody. Handles platform-specific icon rendering
// adjustments (foreground style, rendering mode, etc.).
struct LabelIconPlatformItemModifier: ViewModifier {
    typealias Body = Never

    static func _makeView(
        modifier: _GraphValue<Self>,
        inputs: _ViewInputs,
        body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs
    ) -> _ViewOutputs {
        body(_Graph(), inputs)
    }

    static func _makeViewList(
        modifier: _GraphValue<Self>,
        inputs: _ViewListInputs,
        body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs
    ) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

public struct TitleAndIconLabelStyle: LabelStyle {
    @Environment(\._reservedIconWidth) var _reservedIconWidth: CGFloat?
    @Environment(\._iconToTitleSpacing) var _iconToTitleSpacing: CGFloat?
    @Environment(\._defaultIconToTitleSpacing) var _defaultIconToTitleSpacing: CGFloat?

    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        _staticIf(MultiViewLabel.self) {
            TupleView((
                configuration.icon
                    .modifier(_ContainerValueWritingModifier(keyPath: \.labelItemRole, value: LabelItemRole?.some(.icon))),
                configuration.title
                    .modifier(_ContainerValueWritingModifier(keyPath: \.labelItemRole, value: LabelItemRole?.some(.title)))
            ))
        } falseContent: {
            _staticIf(InterfaceIdiomPredicate<VisionInterfaceIdiom>.self) {
                HStack(alignment: .center, spacing: _iconToTitleSpacing ?? _defaultIconToTitleSpacing) {
                    configuration.icon
                        .modifier(LabelIconPlatformItemModifier())
                        .frame(width: _reservedIconWidth, alignment: .center)
                    configuration.title
                        .environment(\.multilineTextAlignment, .leading)
                }
            } falseContent: {
                HStack(alignment: .center, spacing: _iconToTitleSpacing ?? _defaultIconToTitleSpacing) {
                    configuration.icon
                        .modifier(LabelIconPlatformItemModifier())
                        .frame(width: _reservedIconWidth, alignment: .center)
                    configuration.title
                        .environment(\.multilineTextAlignment, .leading)
                }
            }
        }
    }
}

public struct TitleOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.title
    }
}

// FallbackLabelStyle — internal zero-size style applied unconditionally as the
// last item in DefaultLabelStyle.makeBody's dispatch chain.
// Handles generic label rendering when no style context is active.
struct FallbackLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

struct _MenuItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.clear)
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }
}

extension LabelStyle where Self == DefaultLabelStyle {
    public static var automatic: DefaultLabelStyle { .init() }
}

extension LabelStyle where Self == IconOnlyLabelStyle {
  public static var iconOnly: IconOnlyLabelStyle { .init() }
}

extension LabelStyle where Self == TitleAndIconLabelStyle {
    public static var titleAndIcon: TitleAndIconLabelStyle { .init() }
}

extension LabelStyle where Self == TitleOnlyLabelStyle {
    public static var titleOnly: TitleOnlyLabelStyle { .init() }
}

// LabelStyleModifier<S> — ViewModifier that pushes S onto the
// StyleInput<LabelStyleConfiguration> custom-inputs stack.
struct LabelStyleModifier<S: LabelStyle>: ViewModifier {
    var style: S
    typealias Body = Never

    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let styleAttr: Attribute<LabelStyleModifier<S>> = graph.makeInput(
            value: modifier._attribute.value)
        let anyMod = AnyStyleModifier(
            value: styleAttr.identifier,
            _type: StyleModifierType<LabelStyleModifier<S>>.self)
        var inputs = inputs
        let stack = inputs.base.customInputs.value(forKey: StyleInput<LabelStyleConfiguration>.self)
        inputs.base.customInputs.setValue(stack.pushing(anyMod), forKey: StyleInput<LabelStyleConfiguration>.self)
        return body(_Graph(), inputs)
    }

    static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs, body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        let styleAttr: Attribute<LabelStyleModifier<S>> = graph.makeInput(
            value: modifier._attribute.value)
        let anyMod = AnyStyleModifier(
            value: styleAttr.identifier,
            _type: StyleModifierType<LabelStyleModifier<S>>.self)
        var inputs = inputs
        let stack = inputs.base.customInputs.value(forKey: StyleInput<LabelStyleConfiguration>.self)
        inputs.base.customInputs.setValue(stack.pushing(anyMod), forKey: StyleInput<LabelStyleConfiguration>.self)
        return body(_Graph(), inputs)
    }
}

extension LabelStyleModifier: _HasLabelStyle {
    func _labelStyle() -> any LabelStyle { style }
}

// LabelStyleWritingModifier<S> — public-facing ViewModifier applied by .labelStyle(_:).
// body(content:) composes LabelStyleModifier (style stack push) with
// environment(\.effectiveLabelStyle, ...) for the three concrete built-in styles.
struct LabelStyleWritingModifier<Style: LabelStyle>: ViewModifier {
    let style: Style

    func body(content: Content) -> some View {
        content
            .modifier(LabelStyleModifier(style: style))
            .environment(\.effectiveLabelStyle, Self.effectiveLabelStyleValue(for: style))
    }

    private static func effectiveLabelStyleValue(for style: Style) -> EffectiveLabelStyle? {
        if style is TitleAndIconLabelStyle { return .titleAndIcon }
        if style is TitleOnlyLabelStyle { return .titleOnly }
        if style is IconOnlyLabelStyle { return .iconOnly }
        return nil
    }
}

extension View {
    public func labelStyle<S>(_ style: S) -> some View where S: LabelStyle {
        modifier(LabelStyleWritingModifier(style: style))
    }
}
