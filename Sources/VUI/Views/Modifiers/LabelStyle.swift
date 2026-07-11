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
extension LabelStyleConfiguration.Title: PrimitiveView {}
extension LabelStyleConfiguration.Icon: PrimitiveView {}


extension LabelStyleConfiguration.Title {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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

extension LabelStyleConfiguration.Icon {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
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

// EffectiveLabelStyle: subset of LabelStyle that can be expressed as an enum.
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

// Context-specific label styles used in DefaultLabelStyle.makeBody's dispatch chain.
// These context-specific helper styles currently use minimal functional implementations.

// ListLabelStyle: used in PlainList, InsetList, BorderedList contexts.
struct ListLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

// SidebarLabelStyle: used in Sidebar context.
struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

// GroupedFormLabelStyle: used in GroupedForm and Table contexts.
struct GroupedFormLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

// SystemPreferencesSidebarLabelStyle: used in system preferences sidebar.
struct SystemPreferencesSidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

// TextInputSuggestionLabelStyle: used in text input suggestions context.
struct TextInputSuggestionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

// ToolbarItemLabelStyle: used in toolbar contexts.
struct ToolbarItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

// AccessibilityLabelStyle: used in accessibility representable contexts.
struct AccessibilityLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center) {
            configuration.icon
            configuration.title
        }
    }
}

// DefaultLabelStyle.makeBody: 17 StaticIf dispatch chain + unconditional FallbackLabelStyle.
//   outermost modifier [16] is applied last, innermost [0] first.
//   The outermost StyleContext predicate wins over inner ones when active.
//
// Chain (outermost -> innermost):
//  [16] StyleContextAcceptsPredicate<(Plain, GroupedForm)>  -> GroupedFormLabelStyle
//  [15] StyleContextAcceptsPredicate<(Table, GroupedForm)>  -> GroupedFormLabelStyle
//  [14] StyleContextAcceptsPredicate<PlainList>              -> ListLabelStyle
//  [13] StyleContextAcceptsPredicate<SidebarList>            -> SidebarLabelStyle
//  [12] StyleContextAcceptsPredicate<InsetList>              -> ListLabelStyle
//  [11] StyleContextAcceptsPredicate<GroupedForm>            -> GroupedFormLabelStyle
//  [10] StyleContextAcceptsPredicate<BorderedList>           -> ListLabelStyle
//  [9]  StyleContextAcceptsPredicate<SystemPrefSidebar>      -> SystemPreferencesSidebarLabelStyle
//  [8]  StyleContextAcceptsPredicate<TextInputSuggestions>   -> TextInputSuggestionLabelStyle
//  [7]  And<IsDefaultButtonLabel, AnyPredicate<Toolbar>>     -> TitleOnlyLabelStyle
//  [6]  StyleContextAcceptsPredicate<Toolbar>                -> ToolbarItemLabelStyle
//  [5]  StyleContextAcceptsPredicate<SectionHeader>          -> TitleOnlyLabelStyle
//  [4]  StyleContextAcceptsPredicate<ListAccessoryBar>       -> IconOnlyLabelStyle
//  [3]  StyleContextAcceptsPredicate<SwipeActions>           -> TitleAndIconLabelStyle
//  [2]  StyleContextAcceptsPredicate<AccessibilityQuickAction> -> TitleAndIconLabelStyle
//  [1]  StyleContextAcceptsPredicate<AccessibilityRepresentable> -> AccessibilityLabelStyle
//  [0]  (unconditional)                                      -> FallbackLabelStyle
public struct DefaultLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        // Chain: innermost [16] is added first (.modifier first call),
        //        outermost [0] is added last (.modifier last call).
        // _makeView executes from outermost to innermost. The innermost modifier
        // pushes last onto the style stack, so innermost wins over outermost.
        // FallbackLabelStyle is outermost = default when no context matches.
        Label(configuration)
            // [16] innermost: (Plain, GroupedForm) -> GroupedFormLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<(PlainListStyleContext, GroupedFormStyleContext)>,
                          LabelStyleWritingModifier<GroupedFormLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: GroupedFormLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [15] (Table, GroupedForm) -> GroupedFormLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<(TableStyleContext, GroupedFormStyleContext)>,
                          LabelStyleWritingModifier<GroupedFormLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: GroupedFormLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [14] PlainList -> ListLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<PlainListStyleContext>,
                          LabelStyleWritingModifier<ListLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: ListLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [13] SidebarList -> SidebarLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<SidebarListStyleContext>,
                          LabelStyleWritingModifier<SidebarLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: SidebarLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [12] InsetList -> ListLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<InsetListStyleContext>,
                          LabelStyleWritingModifier<ListLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: ListLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [11] GroupedForm -> GroupedFormLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<GroupedFormStyleContext>,
                          LabelStyleWritingModifier<GroupedFormLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: GroupedFormLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [10] BorderedList -> ListLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<BorderedListStyleContext>,
                          LabelStyleWritingModifier<ListLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: ListLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [9] SystemPreferencesSidebar -> SystemPreferencesSidebarLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<SystemPreferencesSidebarListStyleContext>,
                          LabelStyleWritingModifier<SystemPreferencesSidebarLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: SystemPreferencesSidebarLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [8] TextInputSuggestions -> TextInputSuggestionLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<TextInputSuggestionsContext>,
                          LabelStyleWritingModifier<TextInputSuggestionLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: TextInputSuggestionLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [7] IsDefaultButtonLabel AND Toolbar -> TitleOnlyLabelStyle
            .modifier(
                StaticIf<AndOperationViewInputPredicate<IsDefaultButtonLabel, StyleContextAcceptsAnyPredicate<ToolbarStyleContext>>,
                          LabelStyleWritingModifier<TitleOnlyLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: TitleOnlyLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [6] Toolbar -> ToolbarItemLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<ToolbarStyleContext>,
                          LabelStyleWritingModifier<ToolbarItemLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: ToolbarItemLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [5] SectionHeader -> TitleOnlyLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<SectionHeaderStyleContext>,
                          LabelStyleWritingModifier<TitleOnlyLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: TitleOnlyLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [4] ListAccessoryBar -> IconOnlyLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<ListAccessoryBarStyleContext>,
                          LabelStyleWritingModifier<IconOnlyLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: IconOnlyLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [3] SwipeActions -> TitleAndIconLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<SwipeActionsStyleContext>,
                          LabelStyleWritingModifier<TitleAndIconLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: TitleAndIconLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [2] AccessibilityQuickAction -> TitleAndIconLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<AccessibilityQuickActionStyleContext>,
                          LabelStyleWritingModifier<TitleAndIconLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: TitleAndIconLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [1] AccessibilityRepresentable -> AccessibilityLabelStyle
            .modifier(
                StaticIf<StyleContextAcceptsPredicate<AccessibilityRepresentableStyleContext>,
                          LabelStyleWritingModifier<AccessibilityLabelStyle>, EmptyModifier>(
                    trueBody: LabelStyleWritingModifier(style: AccessibilityLabelStyle()),
                    falseBody: EmptyModifier()
                )
            )
            // [0] outermost: FallbackLabelStyle, default when no context matches.
            .modifier(LabelStyleWritingModifier(style: FallbackLabelStyle()))
    }
}

public struct IconOnlyLabelStyle: LabelStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.icon
    }
}

// LabelItemRole: internal enum for tagging label components in multi-view contexts.
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

// LabelIconPlatformItemModifier: zero-size ViewModifier applied to the icon
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

// FallbackLabelStyle: internal zero-size style applied unconditionally as the
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

// LabelStyleModifier<S>: StyleModifier pushes S onto the
// StyleInput<LabelStyleConfiguration> custom-inputs stack.
// _makeView/_makeViewList are provided by StyleModifier default extension.
struct LabelStyleModifier<S: LabelStyle>: StyleModifier {
    typealias Body = Never
    typealias StyleConfiguration = LabelStyleConfiguration
    typealias StyleBody = S.Body

    var style: S

    init(style: S) { self.style = style }

    func styleBody(configuration: LabelStyleConfiguration) -> S.Body {
        style.makeBody(configuration: configuration)
    }
}

extension LabelStyleModifier: _HasLabelStyle {
    func _labelStyle() -> any LabelStyle { style }
}

// LabelStyleWritingModifier<S>: public-facing ViewModifier applied by .labelStyle(_:).
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
