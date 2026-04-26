//
//  File: AlertModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// MARK: - ViewIdentity
// Stable per-modifier-instance identity used as a dictionary key.
struct ViewIdentity: Hashable {
    private static let counter = Atomic<UInt64>(0)
    let id: UInt64
    init() { id = ViewIdentity.counter.wrappingAdd(1, ordering: .relaxed).newValue }

    // Tracker owns a stable identity for one modifier instance.
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

// MARK: - AlertPreference
// Runtime data needed to render an alert overlay.
struct AlertPreference: @unchecked Sendable {
    let title: Text
    let makeActions: () -> AnyView
    let actionsItemList: PlatformItemList?
    let makeMessage: (() -> AnyView)?
    let messageItemList: PlatformItemList?
    let isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let severity: DialogSeverity
}

// MARK: - AlertStorage
// Stores the alert preference written into host preferences.
struct AlertStorage: @unchecked Sendable {
    let preference: AlertPreference

    // Merges alert storage by identity. The next value wins on collision.
    struct PreferenceKey: HostPreferenceKey {
        typealias Value = [ViewIdentity: AlertStorage]
        static var defaultValue: Value { [:] }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

// MARK: - MakeAlertStorage
// StatefulRule that produces the preference mutation closure.
struct MakeAlertStorage<Actions: View, Message: View>: StatefulRule {
    typealias Value = (inout [ViewIdentity: AlertStorage]) -> Void

    let environment: Attribute<EnvironmentValues>
    let modifier: Attribute<AlertModifier<Actions, Message>>
    let actionsItemList: AGWeakAttribute
    let messageItemList: AGWeakAttribute
    let phase: Attribute<Phase>
    var identityTracker: ViewIdentity.Tracker

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("MakeAlertStorage.updateValue called outside AG context")
        }
        _ = environment.value
        var actionsList: PlatformItemList?
        var messageList: PlatformItemList?
        if actionsItemList.isValid(in: graph) {
            actionsList = Attribute<PlatformItemList>(actionsItemList.toStrong()).value
        }
        if messageItemList.isValid(in: graph) {
            messageList = Attribute<PlatformItemList>(messageItemList.toStrong()).value
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
            makeMessage: (m.message is EmptyView) ? nil : { AnyView(m.message) },
            messageItemList: messageList,
            isPresented: m.isPresented,
            onDismiss: nil,
            severity: m.severity
        )
        let storage = AlertStorage(preference: pref)
        let id = identity
        AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: AlertStorage]) in
            dict[id] = storage
        } as Value)
    }
}

// MARK: - PlatformItemList

// Collects button and text-field descriptors before MakeAlertStorage consumes them.
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
// Pass-through modifier for alert actions rendered directly in the overlay.
struct ActionsModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle()))
        // TextFieldStyleModifier<PlatformItemListTextFieldStyle> is still pending:
        // TextField/TextFieldStyle infrastructure is not implemented yet.
    }
}

// MARK: - AlertModifier
// ViewModifier for presenting an alert when isPresented is true.
struct AlertModifier<Actions: View, Message: View>: ViewModifier {
    typealias Body = Never

    let title: Text
    let actions: Actions
    let message: Message
    let isPresented: Binding<Bool>
    let severity: DialogSeverity
}

extension AlertModifier {
    // Creates a stateful rule that produces the alert preference mutation.
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                          body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("AlertModifier._makeView called outside AG context")
        }
        func makePlatformItemList<C: View>(view: _GraphValue<C>, inputs: _ViewInputs) -> Attribute<PlatformItemList> {
            var itemInputs = inputs
            var keys = itemInputs.preferences.keys
            keys.insert(PlatformItemList.Key.self)
            itemInputs.preferences = PreferencesInputs(keys: keys,
                                                       hostKeys: itemInputs.preferences.hostKeys)
            let outputs = C._makeView(view: view, inputs: itemInputs)
            let nodes = outputs.preferences.values(for: PlatformItemList.Key.self)
            return graph.makeRule {
                var combined = PlatformItemList.Key.defaultValue
                for nodeID in nodes {
                    let value = Attribute<PlatformItemList>(nodeID).value
                    PlatformItemList.Key.reduce(value: &combined) { value }
                }
                return combined
            }
        }

        let actionsItemList = makePlatformItemList(view: modifier[\.actions], inputs: inputs)
        let messageItemList = makePlatformItemList(view: modifier[\.message], inputs: inputs)
        let storageRule = MakeAlertStorage<Actions, Message>(
            environment: inputs.base.cachedEnvironment.value.environment,
            modifier: modifier._attribute,
            actionsItemList: actionsItemList.asWeak(),
            messageItemList: messageItemList.asWeak(),
            phase: inputs.base.phase,
            identityTracker: ViewIdentity.Tracker()
        )
        let storageAttr: Attribute<MakeAlertStorage<Actions, Message>.Value> =
            graph.makeStatefulRule(storageRule)

        // Build AlertStorage.PreferenceKey preference from the mutation closure.
        let prefAttr: Attribute<AlertStorage.PreferenceKey.Value> = graph.makeRule {
            var dict = AlertStorage.PreferenceKey.defaultValue
            storageAttr.value(&dict)
            return dict
        }
        var outputs = body(_Graph(), inputs)
        outputs.preferences.append(AlertStorage.PreferenceKey.self,
                                   node: prefAttr.identifier)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                     body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
    }
}

// MARK: - AlertOverlayView
// The view rendered inside the overlay WindowController for an alert.
struct AlertOverlayView: View {
    let preference: AlertPreference

    var body: some View {
        ZStack {
            // Dim background absorbs taps outside the alert panel.
            Color.black.opacity(0.3)
                .onTapGesture {}

            // Alert panel
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
    }

    @ViewBuilder
    private var actions: some View {
        if let list = preference.actionsItemList, !list.buttonItems.isEmpty {
            VStack(spacing: 8) {
                // Show only the first three action items.
                ForEach(Array(list.buttonItems.prefix(3))) { item in
                    Button(role: item.role, action: {
                        guard item.isEnabled else { return }
                        item.action?()
                        preference.isPresented.wrappedValue = false
                        preference.onDismiss?()
                    }) {
                        item.label
                    }
                    .environment(\.isEnabled, item.isEnabled)
                }
            }
        } else {
            preference.makeActions()
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
        modifier(AlertModifier(title: title,
                               actions: actions().modifier(ActionsModifier()),
                               message: EmptyView(),
                               isPresented: isPresented,
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
        modifier(AlertModifier(title: title,
                               actions: actions().modifier(ActionsModifier()),
                               message: message(),
                               isPresented: isPresented,
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
        // Gate isPresented on data != nil: alert only shows when both are true.
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let data {
            return AnyView(modifier(AlertModifier(title: title,
                                                  actions: actions(data).modifier(ActionsModifier()),
                                                  message: EmptyView(),
                                                  isPresented: gated,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              isPresented: gated,
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
            return AnyView(modifier(AlertModifier(title: title,
                                                  actions: actions(data).modifier(ActionsModifier()),
                                                  message: message(data),
                                                  isPresented: gated,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              isPresented: gated,
                                              severity: .automatic)))
    }
}

extension View {
    public func alert<E: LocalizedError, A: View>(
        isPresented: Binding<Bool>,
        error: E?,
        @ViewBuilder actions: () -> A) -> some View {
        let title = error.map { Text($0.errorDescription ?? $0.localizedDescription) } ?? Text("")
        return modifier(AlertModifier(title: title,
                                      actions: actions().modifier(ActionsModifier()),
                                      message: EmptyView(),
                                      isPresented: isPresented,
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
            return AnyView(modifier(AlertModifier(title: title,
                                                  actions: actions(error).modifier(ActionsModifier()),
                                                  message: message(error),
                                                  isPresented: gated,
                                                  severity: .automatic)))
        }
        return AnyView(modifier(AlertModifier(title: title,
                                              actions: EmptyView().modifier(ActionsModifier()),
                                              message: EmptyView(),
                                              isPresented: gated,
                                              severity: .automatic)))
    }
}
