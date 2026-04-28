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
protocol PlatformItemListFlags {}
// Used for alert actions: collects all item types (buttons + text fields).
struct AllPlatformItemListFlags: PlatformItemListFlags {}
// Used for alert message: collects text items only.
struct TextPlatformItemListFlags: PlatformItemListFlags {}

// MARK: - PlatformItemListGenerator

// Creates a subgraph for Content._makeView and collects PlatformItemList.Key preferences.
struct PlatformItemListGenerator<Flags: PlatformItemListFlags, Content: View>: StatefulRule {
    typealias Value = PlatformItemList

    // PlatformItemList.Key preference attribute IDs from Content._makeView subgraph.
    let preferenceNodes: [AGAttribute]
    // Cached item list from the most recent update.
    var itemList: Optional<PlatformItemList>

    init(content: Attribute<Content>, inputs: _ViewInputs, inputsIncludeGeometry: Bool) {
        var itemInputs = inputs
        var keys = itemInputs.preferences.keys
        keys.insert(PlatformItemList.Key.self)
        itemInputs.preferences = PreferencesInputs(keys: keys,
                                                   hostKeys: itemInputs.preferences.hostKeys)
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

// Stable per-modifier-instance identity used as a preference dictionary key.
struct ViewIdentity: Hashable {
    private static let counter = Atomic<UInt64>(0)
    let id: UInt64
    init() { id = ViewIdentity.counter.wrappingAdd(1, ordering: .relaxed).newValue }

    // Tracks identity across phase changes.
    struct Tracker {
        private var current: ViewIdentity?

        init() {}

        mutating func update(for phase: Phase) -> ViewIdentity {
            if current == nil || phase.isInserted {
                current = ViewIdentity()
            }
            return current!
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
    let title: Text
    let makeActions: () -> AnyView
    let actionsItemList: PlatformItemList?
    let makeMessage: (() -> AnyView)?
    let messageItemList: PlatformItemList?
    let isPresented: Binding<Bool>
    let severity: DialogSeverity
    // onDismiss support is not wired yet.
    let onDismiss: (() -> Void)?
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
        _ = environment.value
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
            title: m.title,
            makeActions: { AnyView(m.actions) },
            actionsItemList: actionsList,
            makeMessage: { AnyView(m.message) },
            messageItemList: messageList,
            isPresented: m.isPresented,
            severity: m.severity,
            onDismiss: nil
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
        var id: AnyHashable
        var label: AnyView
        var action: (() -> Void)?
        var role: ButtonRole?
        var keyboardShortcut: KeyboardShortcut?
        var isEnabled: Bool

        init(id: AnyHashable = UUID(),
             label: AnyView,
             action: (() -> Void)?,
             role: ButtonRole?,
             keyboardShortcut: KeyboardShortcut? = nil,
             isEnabled: Bool = true) {
            self.id = id
            self.label = label
            self.action = action
            self.role = role
            self.keyboardShortcut = keyboardShortcut
            self.isEnabled = isEnabled
        }
    }

    var buttonItems: [Item] = []
    var textFieldItems: [AnyView] = []

    var flattenedItems: [Item] { buttonItems }
    var mergedContentItem: Item? { buttonItems.first }

    mutating func append(_ item: Item) {
        buttonItems.append(item)
    }

    mutating func merge(_ other: PlatformItemList) {
        buttonItems.append(contentsOf: other.buttonItems)
        textFieldItems.append(contentsOf: other.textFieldItems)
    }

    mutating func modify(_ transform: (inout Item) -> Void) {
        for index in buttonItems.indices {
            transform(&buttonItems[index])
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

struct PlatformItemListButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PlatformItemListButtonBody(configuration: configuration)
    }
}

private struct PlatformItemListButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled: Bool

    var body: some View {
        configuration.label
            .preference(key: PlatformItemList.Key.self, value: itemList)
            ._onButtonGesture(pressing: { _ in }, perform: { configuration.trigger() })
    }

    private var itemList: PlatformItemList {
        var list = PlatformItemList()
        list.append(PlatformItemList.Item(
            label: AnyView(configuration.label),
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
//   - Only first 3 items are materialized.
//   - 2 items -> HStack: cancel on left, default on right.
//   - 3 items -> VStack: default/custom top, destructive middle, cancel bottom.
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
            alertPanel
        }
    }

    private var alertPanel: some View {
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                preference.title
                    .font(.headline)
                if let makeMessage = preference.makeMessage {
                    makeMessage()
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            Divider()

            actions
                .padding(8)
        }
        .frame(width: 280)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actions: some View {
        if let list = preference.actionsItemList, !list.buttonItems.isEmpty {
            let items = Array(orderedItems(list.buttonItems).prefix(3))
            if items.count == 2 {
                HStack(spacing: 8) {
                    actionButton(items[0])
                    actionButton(items[1])
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(0..<items.count, id: \.self) { i in
                        actionButton(items[i])
                    }
                }
            }
        } else {
            preference.makeActions()
        }
    }

    // 2-button HStack: cancel first (left), default second (right).
    // 3-button VStack: other/default top, destructive middle, cancel bottom.
    private func orderedItems(_ items: [PlatformItemList.Item]) -> [PlatformItemList.Item] {
        let cancel      = items.filter { $0.role == .cancel }
        let destructive = items.filter { $0.role == .destructive }
        let other       = items.filter { $0.role != .cancel && $0.role != .destructive }
        if items.count == 2 {
            return cancel + other + destructive
        }
        return other + destructive + cancel
    }

    private func actionButton(_ item: PlatformItemList.Item) -> some View {
        Button(role: item.role, action: {
            guard item.isEnabled else { return }
            item.action?()
            preference.isPresented.wrappedValue = false
        }) {
            item.label
                .frame(maxWidth: .infinity)
        }
        .environment(\.isEnabled, item.isEnabled)
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
        if let data {
            return AnyView(modifier(AlertModifier(presentedValue: gated.wrappedValue,
                                                  isPresented: gated,
                                                  title: title,
                                                  actions: actions(data).modifier(ActionsModifier()),
                                                  message: EmptyView(),
                                                  auxiliaryContent: nil,
                                                  representsError: false,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(presentedValue: gated.wrappedValue,
                                              isPresented: gated,
                                              title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              auxiliaryContent: nil,
                                              representsError: false,
                                              severity: .automatic)))
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
        if let data {
            return AnyView(modifier(AlertModifier(presentedValue: gated.wrappedValue,
                                                  isPresented: gated,
                                                  title: title,
                                                  actions: actions(data).modifier(ActionsModifier()),
                                                  message: message(data),
                                                  auxiliaryContent: nil,
                                                  representsError: false,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(presentedValue: gated.wrappedValue,
                                              isPresented: gated,
                                              title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              auxiliaryContent: nil,
                                              representsError: false,
                                              severity: .automatic)))
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
