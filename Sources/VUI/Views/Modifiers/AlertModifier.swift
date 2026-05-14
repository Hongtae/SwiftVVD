//
//  File: AlertModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// MARK: - BoundInputsView

// Placeholder for alert accessory inputs such as text fields.
// TextField-in-alert support is not implemented yet.
struct BoundInputsView {}

// MARK: - PlatformItemListFlags

// Controls which platform item types PlatformItemListGenerator collects from the content view.
protocol PlatformItemListFlags {
    static var installsPlatformItemButtonStyle: Bool { get }
}

extension PlatformItemListFlags {
    static var installsPlatformItemButtonStyle: Bool { false }
}

// Used for alert actions: collects all item types (buttons + text fields).
struct AllPlatformItemListFlags: PlatformItemListFlags {
    // Materialize Button values as platform items.
    static var installsPlatformItemButtonStyle: Bool { true }
}
// Used for alert message: collects text items only.
struct TextPlatformItemListFlags: PlatformItemListFlags {}
// Used by PlatformItemListMenuStyle / View.platformItemChildren for nested Menu content.
struct SelectionPlatformItemListFlags: PlatformItemListFlags {
    static var installsPlatformItemButtonStyle: Bool { true }
}

// MARK: - PlatformItemListGenerator

// Creates a subgraph for Content._makeView and collects PlatformItemList.Key preferences.
struct PlatformItemListGenerator<Flags: PlatformItemListFlags, Content: View>: StatefulRule {
    typealias Value = PlatformItemList

    // PlatformItemList.Key preference attribute IDs from Content._makeView subgraph.
    let preferenceNodes: [AGAttribute]
    // Cached item list from the most recent update.
    var itemList: Optional<PlatformItemList>

    init(content: Attribute<Content>, inputs: _ViewInputs, inputsIncludeGeometry: Bool) {
        guard let graph = AttributeGraph.current else {
            fatalError("PlatformItemListGenerator.init called outside AG context")
        }
        var itemInputs = inputs
        var keys = itemInputs.preferences.keys
        keys.insert(PlatformItemList.Key.self)
        itemInputs.preferences = PreferencesInputs(keys: keys,
                                                   hostKeys: itemInputs.preferences.hostKeys)
        // Request divider entries as platform item-list system items.
        itemInputs.requestedDividerRepresentation = PlatformItemListDividerRepresentable.self
        if Flags.installsPlatformItemButtonStyle {
            let styleAttr: Attribute<ButtonStyleModifier<PlatformItemListButtonStyle>> = graph.makeRule {
                ButtonStyleModifier(style: PlatformItemListButtonStyle())
            }
            let style = AnyStyleModifier(value: styleAttr.identifier,
                                         _type: StyleModifierType<ButtonStyleModifier<PlatformItemListButtonStyle>>.self)
            var stack = itemInputs.base.customInputs.value(
                forKey: StyleInput<PrimitiveButtonStyleConfiguration>.self)
            stack = .node(style, stack)
            itemInputs.base.customInputs.setValue(stack,
                                                  forKey: StyleInput<PrimitiveButtonStyleConfiguration>.self)
        }
        let view = _GraphValue<Content>(_attribute: content)
        let outputs = Content._makeView(view: view, inputs: itemInputs)
        self.preferenceNodes = outputs.preferences.values(for: PlatformItemList.Key.self)
        self.itemList = nil
    }

    // Explicit flags variant (used for TextPlatformItemListFlags message path).
    init(flags: Flags.Type, content: Attribute<Content>, inputs: _ViewInputs,
         inputsIncludeGeometry: Bool) {
        self.init(content: content, inputs: inputs, inputsIncludeGeometry: inputsIncludeGeometry)
    }

    mutating func updateValue() {
        var combined = PlatformItemList()
        for nodeID in preferenceNodes {
            combined.merge(Attribute<PlatformItemList>(nodeID).value)
        }
        itemList = combined
        AttributeGraph.setStatefulOutput(combined)
    }
}

// MARK: - ViewIdentity
// Stable no-argument identity used as a dictionary key for alert preferences.
struct ViewIdentity: Hashable {
    private static let counter = Atomic<UInt32>(0)
    let rawValue: UInt32

    init() {
        rawValue = ViewIdentity.counter.wrappingAdd(1, ordering: .relaxed).newValue
    }

    private init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    // Tracks identity across phase changes using a zero-initialized state.
    struct Tracker {
        private var current = ViewIdentity(rawValue: 0)
        private var lastResetSeed: UInt32 = 0

        init() {}

        mutating func update(for phase: Phase) -> ViewIdentity {
            let resetSeed = phase.resetSeed
            if current.rawValue == 0 || lastResetSeed != resetSeed {
                current = ViewIdentity()
                lastResetSeed = resetSeed
            }
            return current
        }
    }
}

// MARK: - AlertStorage

// Stores the data needed by the overlay renderer.
struct AlertStorage: @unchecked Sendable {
    let preference: AlertPreference

    // Merge by ViewIdentity. nextValue wins on collision.
    struct PreferenceKey: HostPreferenceKey {
        typealias Value = [ViewIdentity: AlertStorage]
        static var defaultValue: Value { [:] }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

// MARK: - AlertPreference

// Alert presentation payload rendered directly by the overlay.
struct AlertPreference: @unchecked Sendable {
    let identity: ViewIdentity
    let title: Text
    let makeActions: () -> AnyView
    let actionsItemList: PlatformItemList?
    let makeMessage: (() -> AnyView)?
    let messageItemList: PlatformItemList?
    let isPresented: Binding<Bool>
    let severity: DialogSeverity
    // onDismiss support is not wired yet.
    let onDismiss: (() -> Void)?
    // Backend policy captured from the alert modifier's environment.
    // Default is overlay; editors can opt into platform modal windows.
    let usesPlatformWindow: Bool
}

// MARK: - MakeAlertStorage

// Builds the preference mutation for active alerts.
struct MakeAlertStorage<Actions: View, Message: View>: StatefulRule {
    typealias Value = (inout [ViewIdentity: AlertStorage]) -> Void

    // Core inputs used to build the alert preference.
    let environment:     Attribute<EnvironmentValues>
    let modifier:        Attribute<AlertModifier<Actions, Message>>
    let actionsItemList: WeakAttribute<PlatformItemList>
    let messageItemList: WeakAttribute<PlatformItemList>
    let phase:           Attribute<Phase>
    var identityTracker: ViewIdentity.Tracker

    // Reserved change-detection cache for future platform alert updates.
    // The current overlay renderer does not use these fields.
    var lastTitle:                    Optional<String>
    var lastColorScheme:              Optional<ColorScheme>
    var lastIcon:                     Optional<Image>
    var lastTintColor:                Optional<Color.Resolved>
    var lastSeverity:                 DialogSeverity
    var lastSuppressionConfiguration: Optional<DialogSuppressionConfiguration>
    var lastAccessibilityTitle:       Optional<NSAttributedString>
    var lastDialogPreventsTermination: Optional<Bool>

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("MakeAlertStorage.updateValue called outside AG context")
        }
        let environment = environment.value
        var actionsList: PlatformItemList?
        var messageList: PlatformItemList?
        if actionsItemList.isValid(in: graph) {
            actionsList = actionsItemList.toStrong().value
        }
        if messageItemList.isValid(in: graph) {
            messageList = messageItemList.toStrong().value
        }
        let m = modifier.value
        let identity = identityTracker.update(for: phase.value)
        guard m.isPresented.wrappedValue else {
            let id = identity
            AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: AlertStorage]) in
                dict.removeValue(forKey: id)
            } as Value)
            return
        }
        let pref = AlertPreference(
            identity: identity,
            title: m.title,
            makeActions: { AnyView(m.actions) },
            actionsItemList: actionsList,
            makeMessage: { AnyView(m.message) },
            messageItemList: messageList,
            isPresented: m.isPresented,
            severity: m.severity,
            onDismiss: nil,
            usesPlatformWindow: environment.modalSessionUsingPlatformWindow
        )
        let storage = AlertStorage(preference: pref)
        let id = identity
        AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: AlertStorage]) in
            dict[id] = storage
        } as Value)
    }
}

// MARK: - PlatformItemList

// PlatformItemList for alert and confirmation-dialog actions.
struct PlatformItemList {
    struct Item: Identifiable {
        enum SystemItem: Int, Sendable {
            case divider = 3
        }

        var id: AnyHashable
        var label: AnyView
        var action: (() -> Void)?
        var role: ButtonRole?
        var keyboardShortcut: KeyboardShortcut?
        var isEnabled: Bool
        var systemItem: SystemItem?
        var children: [Item]
        var selectionBehavior: SelectionBehavior?
        var secondaryNavigationBehavior: SecondaryNavigationBehavior?

        enum SelectionBehavior: Sendable {
            case none
            case toggle(Bool)
        }

        enum SecondaryNavigationBehavior: Sendable {
            case none
            case submenu
        }

        init(id: AnyHashable = UUID(),
             label: AnyView,
             action: (() -> Void)?,
             role: ButtonRole?,
             keyboardShortcut: KeyboardShortcut? = nil,
             isEnabled: Bool = true,
             systemItem: SystemItem? = nil,
             children: [Item] = [],
             selectionBehavior: SelectionBehavior? = nil,
             secondaryNavigationBehavior: SecondaryNavigationBehavior? = nil) {
            self.id = id
            self.label = label
            self.action = action
            self.role = role
            self.keyboardShortcut = keyboardShortcut
            self.isEnabled = isEnabled
            self.systemItem = systemItem
            self.children = children
            self.selectionBehavior = selectionBehavior
            self.secondaryNavigationBehavior = secondaryNavigationBehavior
        }

        init(systemItem: SystemItem) {
            self.init(label: AnyView(EmptyView()),
                      action: nil,
                      role: nil,
                      systemItem: systemItem)
        }
    }

    private var items: [Item] = []
    var textFieldItems: [AnyView] = []

    var flattenedItems: [Item] { items }
    var buttonItems: [Item] { items.filter { $0.systemItem == nil } }
    var menuItems: [Item] { items }
    var mergedContentItem: Item? { items.first }

    mutating func append(_ item: Item) {
        items.append(item)
    }

    mutating func merge(_ other: PlatformItemList) {
        items.append(contentsOf: other.items)
        textFieldItems.append(contentsOf: other.textFieldItems)
    }

    mutating func modify(_ transform: (inout Item) -> Void) {
        for index in items.indices {
            transform(&items[index])
        }
    }

    struct Key: PreferenceKey {
        typealias Value = PlatformItemList
        static var defaultValue: PlatformItemList { PlatformItemList() }

        static func reduce(value: inout PlatformItemList, nextValue: () -> PlatformItemList) {
            value.merge(nextValue())
        }
    }
}

// Overlay helper shared by alert and confirmationDialog.
// Cancel is placed last, non-cancel actions keep source order, a leading nil-role
// action is styled as the default action, and up to four actions are displayed.
struct DialogOverlayAction {
    let item: PlatformItemList.Item
    let isDefaultAction: Bool
}

func orderedDialogOverlayActions(_ items: [PlatformItemList.Item],
                                 maxVisibleCount: Int = 4) -> [DialogOverlayAction] {
    guard maxVisibleCount > 0 else { return [] }
    let ordered = items.enumerated().map { offset, item in
        DialogOverlayAction(item: item,
                            isDefaultAction: offset == 0 && item.role == nil)
    }
    let nonCancel = ordered.filter { $0.item.role != .cancel }
    let cancel    = ordered.filter { $0.item.role == .cancel }
    let orderedActions = nonCancel + cancel
    guard orderedActions.count > maxVisibleCount else {
        return orderedActions
    }
    if let firstCancel = cancel.first {
        return Array(nonCancel.prefix(maxVisibleCount - 1)) + [firstCancel]
    }
    return Array(nonCancel.prefix(maxVisibleCount))
}

struct DialogOverlayActionButtonStyle: PrimitiveButtonStyle {
    var role: ButtonRole?
    var isDefaultAction: Bool

    func makeBody(configuration: Configuration) -> some View {
        DialogOverlayActionButtonBody(configuration: configuration,
                                      role: role,
                                      isDefaultAction: isDefaultAction)
    }
}

private struct DialogOverlayActionButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let role: ButtonRole?
    let isDefaultAction: Bool
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            configuration.label
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            Spacer(minLength: 0)
        }
            .frame(minWidth: 88, maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background {
                RoundedRectangle(cornerRadius: 5).fill(background)
                RoundedRectangle(cornerRadius: 5).strokeBorder(border, lineWidth: 1)
            }
            ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }

    private var foreground: Color {
        if isDefaultAction {
            return .white
        }
        return role == .destructive ? Color(red: 1.0, green: 0.12, blue: 0.16) : .black
    }

    private var background: Color {
        if isDefaultAction {
            return isPressed
                ? Color(red: 0.0, green: 0.36, blue: 0.78)
                : Color(red: 0.0, green: 0.48, blue: 1.0)
        }
        if role == .destructive {
            return isPressed
                ? Color(red: 1.0, green: 0.62, blue: 0.64)
                : Color(red: 1.0, green: 0.76, blue: 0.78)
        }
        return Color(white: isPressed ? 0.82 : 0.92)
    }

    private var border: Color {
        if isDefaultAction {
            return .clear
        }
        return role == .destructive ? .clear : Color(white: 0.35)
    }
}

struct DialogOverlayPanel: View {
    let title: Text?
    let makeMessage: (() -> AnyView)?
    let buttonItems: [PlatformItemList.Item]?
    let makeActions: () -> AnyView
    let isPresented: Binding<Bool>

    var body: some View {
        VStack(spacing: 0) {
            if let title {
                VStack(alignment: .leading, spacing: 10) {
                    title
                        .font(.headline)
                    if let makeMessage {
                        makeMessage()
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 28)
                .padding(.top, 24)
                .padding(.bottom, 18)
            }

            actions
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private var actions: some View {
        if let buttonItems, !buttonItems.isEmpty {
            let items = orderedDialogOverlayActions(buttonItems)
            let reverseHorizontal = items.count == 2 && items.last?.item.role == .cancel
            DialogOverlayActionsLayout(reverseTwoButtonHorizontal: reverseHorizontal) {
                ForEach(0..<items.count, id: \.self) { i in
                    actionButton(items[i])
                }
            }
        } else {
            makeActions()
        }
    }

    private func actionButton(_ action: DialogOverlayAction) -> some View {
        let item = action.item
        return Button(role: item.role, action: {
            guard item.isEnabled else { return }
            item.action?()
            isPresented.wrappedValue = false
        }) {
            item.label
        }
        .buttonStyle(DialogOverlayActionButtonStyle(role: item.role,
                                                    isDefaultAction: action.isDefaultAction))
        .environment(\.isEnabled, item.isEnabled)
    }
}

struct PlatformItemListButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlatformItemListButtonBody(configuration: configuration)
    }
}

private func platformItemFallbackLabel(role: ButtonRole?) -> Text {
    switch role {
    case .cancel:
        return Text("Cancel")
    case .destructive:
        return Text("Delete")
    default:
        return Text("OK")
    }
}

private struct PlatformItemListButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled: Bool

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("PlatformItemListButtonBody._makeView called outside AG context")
        }

        let labelView = view[\.configuration][\.label]
        var outputs = PrimitiveButtonStyleConfiguration.Label._makeView(view: labelView, inputs: inputs)
        let configurationAttr = view[\.configuration]._attribute
        let environmentAttr = inputs.base.cachedEnvironment.value.environment
        let source = inputs.base.customInputs.value(forKey: SourceInput<PrimitiveButtonStyleConfiguration.Label>.self).top
        let preferenceAttr: Attribute<PlatformItemList> = graph.makeRule {
            let configuration = configurationAttr.value
            let label = source?.snapshot() ??
                AnyView(platformItemFallbackLabel(role: configuration.role))
            var list = PlatformItemList()
            list.append(PlatformItemList.Item(
                label: label,
                action: { configuration.trigger() },
                role: configuration.role,
                isEnabled: environmentAttr.value.isEnabled
            ))
            return list
        }
        outputs.preferences.append(PlatformItemList.Key.self, node: preferenceAttr.identifier)
        return outputs
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    var body: some View {
        configuration.label
            .preference(key: PlatformItemList.Key.self, value: itemList)
            ._onButtonGesture(pressing: { _ in }, perform: { configuration.trigger() })
    }

    private var itemList: PlatformItemList {
        var list = PlatformItemList()
        list.append(PlatformItemList.Item(
            label: AnyView(platformItemFallbackLabel(role: configuration.role)),
            action: { configuration.trigger() },
            role: configuration.role,
            isEnabled: isEnabled
        ))
        return list
    }
}

// MARK: - ActionsModifier

// Applies the button style that emits PlatformItemList entries.
// TextFieldStyleModifier is not implemented yet.
struct ActionsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle()))
    }
}

// MARK: - AlertModifier

// Modifier that records alert presentation state.
struct AlertModifier<Actions: View, Message: View>: ViewModifier, MultiViewModifier {
    typealias Body = Never

    let presentedValue: Bool
    let isPresented: Binding<Bool>
    let title: Text
    let actions: Actions
    let message: Message
    let auxiliaryContent: Optional<BoundInputsView>
    let representsError: Bool
    // Presentation severity for overlay rendering.
    let severity: DialogSeverity
}

extension AlertModifier {
    // Collect content outputs, build item lists, and register an alert preference.
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                          body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("AlertModifier._makeView called outside AG context")
        }

        // Step 1: content view outputs.
        var outputs = body(_Graph(), inputs)

        // Step 2: actions PlatformItemListGenerator.
        let actionsGenerator = PlatformItemListGenerator<AllPlatformItemListFlags, Actions>(
            content: modifier[\.actions]._attribute,
            inputs: inputs,
            inputsIncludeGeometry: true
        )
        let actionsListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(actionsGenerator)

        // Step 3: message PlatformItemListGenerator.
        let messageGenerator = PlatformItemListGenerator<TextPlatformItemListFlags, Message>(
            flags: TextPlatformItemListFlags.self,
            content: modifier[\.message]._attribute,
            inputs: inputs,
            inputsIncludeGeometry: true
        )
        let messageListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(messageGenerator)

        // Step 4: WeakAttribute<PlatformItemList> conversion.
        let actionsWeakAttr = actionsListAttr.asWeak()
        let messageWeakAttr = messageListAttr.asWeak()

        // Step 5: MakeAlertStorage AG node.
        let storageRule = MakeAlertStorage<Actions, Message>(
            environment: inputs.base.cachedEnvironment.value.environment,
            modifier: modifier._attribute,
            actionsItemList: actionsWeakAttr,
            messageItemList: messageWeakAttr,
            phase: inputs.base.phase,
            identityTracker: ViewIdentity.Tracker(),
            lastTitle:                    Optional<String>.none,
            lastColorScheme:              Optional<ColorScheme>.none,
            lastIcon:                     Optional<Image>.none,
            lastTintColor:                Optional<Color.Resolved>.none,
            lastSeverity:                 .standard,
            lastSuppressionConfiguration: Optional<DialogSuppressionConfiguration>.none,
            lastAccessibilityTitle:       Optional<NSAttributedString>.none,
            lastDialogPreventsTermination: Optional<Bool>.none
        )
        let storageAttr: Attribute<MakeAlertStorage<Actions, Message>.Value> =
            graph.makeStatefulRule(storageRule)

        // Step 6: AlertStorage.PreferenceKey output.
        // makeRule applies the mutation closure to get the final dictionary.
        let prefAttr: Attribute<AlertStorage.PreferenceKey.Value> = graph.makeRule {
            var dict = AlertStorage.PreferenceKey.defaultValue
            storageAttr.value(&dict)
            return dict
        }
        outputs.preferences.append(AlertStorage.PreferenceKey.self,
                                   node: prefAttr.identifier)
        return outputs
    }
}

// MARK: - AlertOverlayView
// The view rendered inside the overlay WindowController for an alert.
//
// Button layout rules:
//   - Up to four items are materialized.
//   - cancel is placed last; non-cancel actions keep source order.
//   - leading nil-role action is styled as the default action.
//   - Two items use an HStack with cancel on the left and default on the right.
//
// Keyboard shortcuts:
//   - ButtonRole.cancel -> Escape (.cancelAction)
//   - Default (nil role or .defaultAction) -> Return (.defaultAction)
//   - FIXME: Overlay keyboard shortcut handling is not yet wired to the render pipeline.
struct AlertOverlayView: View {
    let preference: AlertPreference

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .onTapGesture {}
            DialogOverlayPanel(title: preference.title,
                               makeMessage: preference.makeMessage,
                               buttonItems: preference.actionsItemList?.buttonItems,
                               makeActions: preference.makeActions,
                               isPresented: preference.isPresented)
        }
    }
}

// Alert action layout used by the overlay renderer.
// Two short labels share one row, and long labels fall back to a vertical stack.
private struct DialogOverlayActionsLayout: Layout {
    typealias AnimatableData = EmptyAnimatableData
    typealias Cache = Void

    var reverseTwoButtonHorizontal: Bool

    private let horizontalSpacing: CGFloat = 10
    private let verticalSpacing: CGFloat = 8
    private let minimumButtonWidth: CGFloat = 104

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout Cache) -> CGSize {
        if usesHorizontalLayout(proposal: proposal, subviews: subviews) {
            return horizontalSize(proposal: proposal, subviews: subviews)
        }
        return verticalSize(proposal: proposal, subviews: subviews)
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout Cache) {
        if usesHorizontalLayout(proposal: ProposedViewSize(width: bounds.width, height: bounds.height),
                                subviews: subviews) {
            placeHorizontalSubviews(in: bounds, subviews: subviews)
        } else {
            placeVerticalSubviews(in: bounds, subviews: subviews)
        }
    }

    private func usesHorizontalLayout(proposal: ProposedViewSize, subviews: Subviews) -> Bool {
        guard subviews.count == 2 else { return false }
        guard let availableWidth = proposal.width, availableWidth.isFinite else { return true }
        let idealWidths = subviews.map { subview in
            max(minimumButtonWidth, subview.sizeThatFits(.unspecified).width)
        }
        return idealWidths.reduce(0, +) + horizontalSpacing <= availableWidth
    }

    private func horizontalSize(proposal: ProposedViewSize, subviews: Subviews) -> CGSize {
        if let availableWidth = proposal.width, availableWidth.isFinite {
            let buttonWidth = max(0, (availableWidth - horizontalSpacing) * 0.5)
            let height = subviews.map {
                $0.sizeThatFits(ProposedViewSize(width: buttonWidth, height: proposal.height)).height
            }.reduce(0, max)
            return CGSize(width: availableWidth, height: height)
        }

        let sizes = subviews.map { subview in
            let size = subview.sizeThatFits(.unspecified)
            return CGSize(width: max(minimumButtonWidth, size.width), height: size.height)
        }
        return CGSize(width: sizes.map(\.width).reduce(0, +) + horizontalSpacing,
                      height: sizes.map(\.height).reduce(0, max))
    }

    private func verticalSize(proposal: ProposedViewSize, subviews: Subviews) -> CGSize {
        let sizes = subviews.map {
            $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        }
        let width = proposal.width ?? sizes.map(\.width).reduce(0, max)
        let spacing = verticalSpacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: width, height: sizes.map(\.height).reduce(0, +) + spacing)
    }

    private func placeHorizontalSubviews(in bounds: CGRect, subviews: Subviews) {
        let buttonWidth = max(0, (bounds.width - horizontalSpacing) * 0.5)
        let order = reverseTwoButtonHorizontal ? [1, 0] : [0, 1]
        var x = bounds.minX
        for index in order {
            guard subviews.indices.contains(index) else { continue }
            subviews[index].place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: buttonWidth, height: bounds.height)
            )
            x += buttonWidth + horizontalSpacing
        }
    }

    private func placeVerticalSubviews(in bounds: CGRect, subviews: Subviews) {
        var y = bounds.minY
        for index in subviews.indices {
            let proposal = ProposedViewSize(width: bounds.width, height: nil)
            let size = subviews[index].sizeThatFits(proposal)
            subviews[index].place(
                at: CGPoint(x: bounds.minX, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
            y += size.height + verticalSpacing
        }
    }
}

// MARK: - View.alert extensions

extension View {
    public func alert<A>(_ titleKey: LocalizedStringKey,
                         isPresented: Binding<Bool>,
                         @ViewBuilder actions: () -> A) -> some View where A: View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions)
    }

    public func alert<S: StringProtocol, A: View>(_ title: S,
                                                   isPresented: Binding<Bool>,
                                                   @ViewBuilder actions: () -> A) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions)
    }

    public func alert<A: View>(_ title: Text,
                                isPresented: Binding<Bool>,
                                @ViewBuilder actions: () -> A) -> some View {
        modifier(AlertModifier(presentedValue: isPresented.wrappedValue,
                               isPresented: isPresented,
                               title: title,
                               actions: actions().modifier(ActionsModifier()),
                               message: EmptyView(),
                               auxiliaryContent: nil,
                               representsError: false,
                               severity: .automatic))
    }
}

extension View {
    public func alert<A: View, M: View>(_ titleKey: LocalizedStringKey,
                                         isPresented: Binding<Bool>,
                                         @ViewBuilder actions: () -> A,
                                         @ViewBuilder message: () -> M) -> some View {
        alert(Text(titleKey), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<S: StringProtocol, A: View, M: View>(_ title: S,
                                                             isPresented: Binding<Bool>,
                                                             @ViewBuilder actions: () -> A,
                                                             @ViewBuilder message: () -> M) -> some View {
        alert(Text(title), isPresented: isPresented, actions: actions, message: message)
    }

    public func alert<A: View, M: View>(_ title: Text,
                                         isPresented: Binding<Bool>,
                                         @ViewBuilder actions: () -> A,
                                         @ViewBuilder message: () -> M) -> some View {
        modifier(AlertModifier(presentedValue: isPresented.wrappedValue,
                               isPresented: isPresented,
                               title: title,
                               actions: actions().modifier(ActionsModifier()),
                               message: message(),
                               auxiliaryContent: nil,
                               representsError: false,
                               severity: .automatic))
    }
}

extension View {
    public func alert<A: View, T>(_ titleKey: LocalizedStringKey,
                                   isPresented: Binding<Bool>,
                                   presenting data: T?,
                                   @ViewBuilder actions: (T) -> A) -> some View {
        alert(Text(titleKey), isPresented: isPresented, presenting: data, actions: actions)
    }

    public func alert<A: View, T>(_ title: Text,
                                   isPresented: Binding<Bool>,
                                   presenting data: T?,
                                   @ViewBuilder actions: (T) -> A) -> some View {
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        // Keep the outer AlertModifier shape stable with optional action views.
        return alert(title, isPresented: gated, actions: {
            data.map { actions($0) }
        })
    }
}

extension View {
    public func alert<A: View, M: View, T>(_ titleKey: LocalizedStringKey,
                                            isPresented: Binding<Bool>,
                                            presenting data: T?,
                                            @ViewBuilder actions: (T) -> A,
                                            @ViewBuilder message: (T) -> M) -> some View {
        alert(Text(titleKey), isPresented: isPresented,
              presenting: data, actions: actions, message: message)
    }

    public func alert<A: View, M: View, T>(_ title: Text,
                                            isPresented: Binding<Bool>,
                                            presenting data: T?,
                                            @ViewBuilder actions: (T) -> A,
                                            @ViewBuilder message: (T) -> M) -> some View {
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        // Keep the outer AlertModifier shape stable with optional action and message views.
        return alert(title, isPresented: gated, actions: {
            data.map { actions($0) }
        }, message: {
            data.map { message($0) }
        })
    }
}

extension View {
    public func alert<E: LocalizedError, A: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: () -> A) -> some View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        return modifier(AlertModifier(presentedValue: isPresented.wrappedValue,
                                      isPresented: isPresented,
                                      title: title,
                                      actions: actions().modifier(ActionsModifier()),
                                      message: EmptyView(),
                                      auxiliaryContent: nil,
                                      representsError: true,
                                      severity: .automatic))
    }

    public func alert<E: LocalizedError, A: View, M: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: (E) -> A,
        @ViewBuilder message: (E) -> M) -> some View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        let gated = Binding<Bool>(get: { error != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let error {
            return AnyView(modifier(AlertModifier(presentedValue: gated.wrappedValue,
                                                  isPresented: gated,
                                                  title: title,
                                                  actions: actions(error).modifier(ActionsModifier()),
                                                  message: message(error),
                                                  auxiliaryContent: nil,
                                                  representsError: true,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(presentedValue: gated.wrappedValue,
                                              isPresented: gated,
                                              title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              auxiliaryContent: nil,
                                              representsError: true,
                                              severity: .automatic)))
    }
}
