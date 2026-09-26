//
//  File: NavigationSplitView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct NavigationSplitViewVisibility: Equatable, Codable, Sendable {
    enum Kind: UInt8, Codable, Sendable {
        case detailOnly
        case doubleColumn
        case all
    }

    var kind: Kind
    var isAutomatic: Bool

    private init(kind: Kind, isAutomatic: Bool = false) {
        self.kind = kind
        self.isAutomatic = isAutomatic
    }

    public static var detailOnly: NavigationSplitViewVisibility {
        NavigationSplitViewVisibility(kind: .detailOnly)
    }

    public static var doubleColumn: NavigationSplitViewVisibility {
        NavigationSplitViewVisibility(kind: .doubleColumn)
    }

    public static var all: NavigationSplitViewVisibility {
        NavigationSplitViewVisibility(kind: .all)
    }

    public static var automatic: NavigationSplitViewVisibility {
        NavigationSplitViewVisibility(
            kind: .doubleColumn,
            isAutomatic: true
        )
    }
}

public struct NavigationSplitViewColumn: Hashable, Sendable {
    enum Tag: UInt8, Hashable, Sendable {
        case sidebar
        case content
        case detail
    }

    var tag: Tag

    private init(tag: Tag) {
        self.tag = tag
    }

    public static var sidebar: NavigationSplitViewColumn {
        NavigationSplitViewColumn(tag: .sidebar)
    }

    public static var content: NavigationSplitViewColumn {
        NavigationSplitViewColumn(tag: .content)
    }

    public static var detail: NavigationSplitViewColumn {
        NavigationSplitViewColumn(tag: .detail)
    }
}

@propertyWrapper
enum StateOrBinding<Value>: DynamicProperty {
    case state(State<Value>)
    case binding(Binding<Value>)

    init(wrappedValue: Value) {
        self = .state(State(wrappedValue: wrappedValue))
    }

    init(_ binding: Binding<Value>) {
        self = .binding(binding)
    }

    var wrappedValue: Value {
        get {
            switch self {
            case let .state(state):
                state.wrappedValue
            case let .binding(binding):
                binding.wrappedValue
            }
        }
        nonmutating set {
            switch self {
            case let .state(state):
                state.wrappedValue = newValue
            case let .binding(binding):
                binding.wrappedValue = newValue
            }
        }
    }

    var projectedValue: Binding<Value> {
        switch self {
        case let .state(state):
            state.projectedValue
        case let .binding(binding):
            binding
        }
    }

    static func _makeProperty<V>(
        in buffer: inout _DynamicPropertyBuffer,
        container: _GraphValue<V>,
        fieldOffset: Int,
        inputs: inout _GraphInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError(
                "\(Self.self)._makeProperty called outside an active "
                    + "_AGGraph context."
            )
        }

        let wiringSubgraph = AGSubgraph.current
        let signal: Attribute<Void> = AGSubgraph.withCurrent(wiringSubgraph) {
            graph.makeInput(value: ())
        }
        let mountedLocation = MutableBox<AnyLocation<Value>?>(nil)

        buffer.properties.append(.init(type: Self.self, offset: fieldOffset))
        buffer.contexts[fieldOffset] = {
            (pointer: UnsafeMutableRawPointer) in
            var property = pointer
                .assumingMemoryBound(to: StateOrBinding<Value>.self)
                .pointee

            guard case let .state(currentState) = property else {
                return
            }

            _ = signal.value
            var state = currentState
            if let location = mountedLocation.value {
                state._value = location.update().0
                state._location = location
            } else {
                let location = StoredLocation<Value>(
                    initialValue: state._value,
                    host: GraphHost.currentHost,
                    signal: signal.asWeak().base
                )
                mountedLocation.value = location
                state._value = location.update().0
                state._location = location
            }
            property = .state(state)
            pointer
                .assumingMemoryBound(to: StateOrBinding<Value>.self)
                .pointee = property
        }
    }
}

struct AnyNavigationSplitVisibility: Equatable {
    enum Kind: Equatable {
        case deprecatedTwoColumn(visibility: Visibility)
        case twoColumn(visibility: NavigationSplitViewVisibility)
        case threeColumn(visibility: NavigationSplitViewVisibility)
    }

    var kind: Kind

    static func twoColumn(
        _ visibility: NavigationSplitViewVisibility
    ) -> AnyNavigationSplitVisibility {
        AnyNavigationSplitVisibility(kind: .twoColumn(visibility: visibility))
    }

    static func threeColumn(
        _ visibility: NavigationSplitViewVisibility
    ) -> AnyNavigationSplitVisibility {
        AnyNavigationSplitVisibility(
            kind: .threeColumn(visibility: visibility)
        )
    }

    var columnCount: Int {
        switch kind {
        case .deprecatedTwoColumn, .twoColumn:
            2
        case .threeColumn:
            3
        }
    }

    var isSidebarVisible: Bool {
        switch kind {
        case let .deprecatedTwoColumn(visibility):
            visibility != .hidden
        case let .twoColumn(visibility):
            visibility.kind != .detailOnly
        case let .threeColumn(visibility):
            visibility.kind == .all
        }
    }

    mutating func toggleSidebar() {
        switch kind {
        case let .deprecatedTwoColumn(visibility):
            kind = .deprecatedTwoColumn(
                visibility: visibility == .hidden ? .visible : .hidden
            )
        case .twoColumn:
            kind = .twoColumn(
                visibility: isSidebarVisible ? .detailOnly : .all
            )
        case .threeColumn:
            kind = .threeColumn(
                visibility: isSidebarVisible ? .doubleColumn : .all
            )
        }
    }

    struct ToTwoColumns: Projection {
        func get(
            base: NavigationSplitViewVisibility
        ) -> AnyNavigationSplitVisibility {
            .twoColumn(base)
        }

        func set(
            base: inout NavigationSplitViewVisibility,
            newValue: AnyNavigationSplitVisibility
        ) {
            base = newValue.navigationSplitViewVisibility
        }
    }

    struct ToThreeColumns: Projection {
        func get(
            base: NavigationSplitViewVisibility
        ) -> AnyNavigationSplitVisibility {
            .threeColumn(base)
        }

        func set(
            base: inout NavigationSplitViewVisibility,
            newValue: AnyNavigationSplitVisibility
        ) {
            base = newValue.navigationSplitViewVisibility
        }
    }

    private var navigationSplitViewVisibility: NavigationSplitViewVisibility {
        switch kind {
        case let .deprecatedTwoColumn(visibility):
            switch visibility {
            case .automatic:
                .automatic
            case .visible:
                .all
            case .hidden:
                .detailOnly
            }
        case let .twoColumn(visibility), let .threeColumn(visibility):
            visibility
        }
    }
}

struct CompositeNavigationSplitViewVisibility {
    var readWrite: Binding<AnyNavigationSplitVisibility>
    var readOnly: NavigationSplitViewVisibility?
}

public struct NavigationSplitViewStyleConfiguration {
    struct Sidebar: View, ViewAlias {
        typealias Body = Never
    }

    struct Content: View, ViewAlias {
        typealias Body = Never
    }

    struct Detail: View, ViewAlias {
        typealias Body = Never
    }

    var sidebar = Sidebar()
    var content = Content()
    var detail = Detail()
    var visibility: CompositeNavigationSplitViewVisibility
    var columnCount: Int
    var preferredCompactColumn: Binding<NavigationSplitViewColumn>
}

extension NavigationSplitViewStyleConfiguration.Sidebar: PrimitiveView {}
extension NavigationSplitViewStyleConfiguration.Content: PrimitiveView {}
extension NavigationSplitViewStyleConfiguration.Detail: PrimitiveView {}

@available(*, unavailable)
extension NavigationSplitViewStyleConfiguration: Sendable {}

public protocol NavigationSplitViewStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(
        configuration: Self.Configuration
    ) -> Self.Body
    typealias Configuration = NavigationSplitViewStyleConfiguration
}

public struct NavigationSplitView<Sidebar, Content, Detail>: View
where Sidebar: View, Content: View, Detail: View {
    var sidebar: Sidebar
    var content: Content
    var detail: Detail
    @StateOrBinding var visibility: AnyNavigationSplitVisibility
    @StateOrBinding var preferredCompactColumn: NavigationSplitViewColumn
    var pureProgrammaticVisibility: NavigationSplitViewVisibility?

    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        _visibility = StateOrBinding(
            wrappedValue: .threeColumn(.automatic)
        )
        _preferredCompactColumn = StateOrBinding(wrappedValue: .sidebar)
        pureProgrammaticVisibility = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        _visibility = StateOrBinding(
            columnVisibility.projecting(
                AnyNavigationSplitVisibility.ToThreeColumns()
            )
        )
        _preferredCompactColumn = StateOrBinding(wrappedValue: .sidebar)
        pureProgrammaticVisibility = nil
    }

    public init(
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        _visibility = StateOrBinding(
            wrappedValue: .threeColumn(.automatic)
        )
        _preferredCompactColumn = StateOrBinding(preferredCompactColumn)
        pureProgrammaticVisibility = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        self.content = content()
        self.detail = detail()
        _visibility = StateOrBinding(
            columnVisibility.projecting(
                AnyNavigationSplitVisibility.ToThreeColumns()
            )
        )
        _preferredCompactColumn = StateOrBinding(preferredCompactColumn)
        pureProgrammaticVisibility = nil
    }

    public var body: some View {
        ResolvedNavigationSplitStyle(
            configuration: NavigationSplitViewStyleConfiguration(
                visibility: CompositeNavigationSplitViewVisibility(
                    readWrite: $visibility,
                    readOnly: pureProgrammaticVisibility
                ),
                columnCount: 3,
                preferredCompactColumn: $preferredCompactColumn
            )
        )
        .modifier(
            StaticSourceWriter<
                NavigationSplitViewStyleConfiguration.Sidebar,
                Sidebar
            >(source: sidebar)
        )
        .modifier(
            StaticSourceWriter<
                NavigationSplitViewStyleConfiguration.Content,
                Content
            >(source: content)
        )
        .modifier(
            StaticSourceWriter<
                NavigationSplitViewStyleConfiguration.Detail,
                Detail
            >(source: detail)
        )
    }
}

extension NavigationSplitView where Content == EmptyView {
    public init(
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        content = EmptyView()
        self.detail = detail()
        _visibility = StateOrBinding(
            wrappedValue: AnyNavigationSplitVisibility(
                kind: .deprecatedTwoColumn(visibility: .automatic)
            )
        )
        _preferredCompactColumn = StateOrBinding(wrappedValue: .sidebar)
        pureProgrammaticVisibility = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        content = EmptyView()
        self.detail = detail()
        _visibility = StateOrBinding(
            columnVisibility.projecting(
                AnyNavigationSplitVisibility.ToTwoColumns()
            )
        )
        _preferredCompactColumn = StateOrBinding(wrappedValue: .sidebar)
        pureProgrammaticVisibility = nil
    }

    public init(
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        content = EmptyView()
        self.detail = detail()
        _visibility = StateOrBinding(
            wrappedValue: AnyNavigationSplitVisibility(
                kind: .deprecatedTwoColumn(visibility: .automatic)
            )
        )
        _preferredCompactColumn = StateOrBinding(preferredCompactColumn)
        pureProgrammaticVisibility = nil
    }

    public init(
        columnVisibility: Binding<NavigationSplitViewVisibility>,
        preferredCompactColumn: Binding<NavigationSplitViewColumn>,
        @ViewBuilder sidebar: () -> Sidebar,
        @ViewBuilder detail: () -> Detail
    ) {
        self.sidebar = sidebar()
        content = EmptyView()
        self.detail = detail()
        _visibility = StateOrBinding(
            columnVisibility.projecting(
                AnyNavigationSplitVisibility.ToTwoColumns()
            )
        )
        _preferredCompactColumn = StateOrBinding(preferredCompactColumn)
        pureProgrammaticVisibility = nil
    }
}

extension NavigationSplitView
where
    Sidebar == NavigationSplitViewStyleConfiguration.Sidebar,
    Content == NavigationSplitViewStyleConfiguration.Content,
    Detail == NavigationSplitViewStyleConfiguration.Detail
{
    init(_ configuration: NavigationSplitViewStyleConfiguration) {
        sidebar = configuration.sidebar
        content = configuration.content
        detail = configuration.detail
        _visibility = StateOrBinding(configuration.visibility.readWrite)
        _preferredCompactColumn = StateOrBinding(
            configuration.preferredCompactColumn
        )
        pureProgrammaticVisibility = configuration.visibility.readOnly
    }
}

@available(*, unavailable)
extension NavigationSplitView: Sendable {}

private struct ResolvedNavigationSplitStyle: StyleableView {
    typealias Configuration = NavigationSplitViewStyleConfiguration
    var configuration: NavigationSplitViewStyleConfiguration

    var body: some View {
        NavigationSplitView(configuration)
    }

    typealias DefaultStyleModifier =
        NavigationSplitStyleModifier<AutomaticNavigationSplitViewStyle>

    static var defaultStyleModifier: DefaultStyleModifier {
        NavigationSplitStyleModifier(
            style: AutomaticNavigationSplitViewStyle()
        )
    }
}

struct NavigationSplitStyleModifier<Style: NavigationSplitViewStyle>:
    StyleModifier
{
    typealias Body = Never
    typealias StyleConfiguration = NavigationSplitViewStyleConfiguration
    typealias StyleBody = Style.Body

    var style: Style

    init(style: Style) {
        self.style = style
    }

    func styleBody(
        configuration: NavigationSplitViewStyleConfiguration
    ) -> Style.Body {
        style.makeBody(configuration: configuration)
    }
}

extension View {
    public func navigationSplitViewStyle<Style>(
        _ style: Style
    ) -> some View where Style: NavigationSplitViewStyle {
        modifier(NavigationSplitStyleModifier(style: style))
    }
}

public struct AutomaticNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}

    public func makeBody(
        configuration: Configuration
    ) -> some View {
        NavigationSplitView(configuration)
            .modifier(
                NavigationSplitStyleModifier(
                    style: BalancedNavigationSplitViewStyle()
                )
            )
    }
}

@available(*, unavailable)
extension AutomaticNavigationSplitViewStyle: Sendable {}

extension NavigationSplitViewStyle
where Self == AutomaticNavigationSplitViewStyle {
    public static var automatic: AutomaticNavigationSplitViewStyle {
        AutomaticNavigationSplitViewStyle()
    }
}

public struct BalancedNavigationSplitViewStyle: NavigationSplitViewStyle {
    public init() {}

    public func makeBody(
        configuration: Configuration
    ) -> some View {
        NavigationSplitColumnsHost(
            configuration: configuration,
            leadingColumnBehavior: .balanced
        )
    }
}

@available(*, unavailable)
extension BalancedNavigationSplitViewStyle: Sendable {}

extension NavigationSplitViewStyle
where Self == BalancedNavigationSplitViewStyle {
    public static var balanced: BalancedNavigationSplitViewStyle {
        BalancedNavigationSplitViewStyle()
    }
}

public struct ProminentDetailNavigationSplitViewStyle:
    NavigationSplitViewStyle
{
    public init() {}

    public func makeBody(
        configuration: Configuration
    ) -> some View {
        NavigationSplitColumnsHost(
            configuration: configuration,
            leadingColumnBehavior: .prominentDetail
        )
    }
}

@available(*, unavailable)
extension ProminentDetailNavigationSplitViewStyle: Sendable {}

extension NavigationSplitViewStyle
where Self == ProminentDetailNavigationSplitViewStyle {
    public static var prominentDetail: ProminentDetailNavigationSplitViewStyle {
        ProminentDetailNavigationSplitViewStyle()
    }
}

private enum NavigationSplitLeadingColumnBehavior {
    case balanced
    case prominentDetail
}

private struct RootSidebarCommandContextFocusedValueKey: FocusedValueKey {
    typealias Value = RootSidebarCommandContext
}

struct RootSidebarCommandContext {
    var visibility: Binding<AnyNavigationSplitVisibility>

    var isSidebarVisible: Bool {
        visibility.wrappedValue.isSidebarVisible
    }

    func toggleSidebar() {
        var value = visibility.wrappedValue
        value.toggleSidebar()
        visibility.wrappedValue = value
    }
}

extension FocusedValues {
    var rootSidebarCommandContext: RootSidebarCommandContext? {
        get { self[RootSidebarCommandContextFocusedValueKey.self] }
        set { self[RootSidebarCommandContextFocusedValueKey.self] = newValue }
    }
}

private struct NavigationSplitColumnsHost: View {
    var configuration: NavigationSplitViewStyleConfiguration
    var leadingColumnBehavior: NavigationSplitLeadingColumnBehavior

    var body: some View {
        NavigationSplitColumns(
            configuration: configuration,
            leadingColumnBehavior: leadingColumnBehavior
        )
        .focusedSceneValue(
            \.rootSidebarCommandContext,
            RootSidebarCommandContext(
                visibility: configuration.visibility.readWrite
            )
        )
    }
}

private struct NavigationSplitColumns: View {
    var configuration: NavigationSplitViewStyleConfiguration
    var leadingColumnBehavior: NavigationSplitLeadingColumnBehavior

    private var visibility: AnyNavigationSplitVisibility {
        configuration.visibility.readWrite.wrappedValue
    }

    var body: some View {
        splitContent
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    @ViewBuilder private var splitContent: some View {
        switch visibleColumns {
        case .detailOnly:
            detailColumn
        case .twoColumn:
            HStack(spacing: 0) {
                leadingColumn
                Divider()
                detailColumn
            }
        case .threeColumn:
            HStack(spacing: 0) {
                sidebarColumn
                Divider()
                contentColumn
                Divider()
                detailColumn
            }
        }
    }

    private enum VisibleColumns {
        case detailOnly
        case twoColumn
        case threeColumn
    }

    private var visibleColumns: VisibleColumns {
        switch visibility.kind {
        case let .deprecatedTwoColumn(value):
            value == .hidden ? .detailOnly : .twoColumn
        case let .twoColumn(value):
            value.kind == .detailOnly ? .detailOnly : .twoColumn
        case let .threeColumn(value):
            switch value.kind {
            case .detailOnly:
                .detailOnly
            case .doubleColumn:
                .twoColumn
            case .all:
                .threeColumn
            }
        }
    }

    @ViewBuilder private var leadingColumn: some View {
        if configuration.columnCount == 2 {
            sidebarColumn
        } else {
            contentColumn
        }
    }

    private var sidebarColumn: some View {
        configuration.sidebar
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
    }

    private var contentColumn: some View {
        configuration.content
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
    }

    private var detailColumn: some View {
        configuration.detail
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
    }
}
