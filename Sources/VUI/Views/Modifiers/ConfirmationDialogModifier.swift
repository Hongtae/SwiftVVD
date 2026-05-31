//
//  File: ConfirmationDialogModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

// Workaround: `struct PreferenceKey: PreferenceKey` inside ConfirmationDialog would shadow
// the outer protocol name. Use a private typealias to keep the conformance unambiguous.
private typealias _PreferenceKeyProto = PreferenceKey

// Confirmation dialogs are emitted through preferences and rendered by the modal overlay path.
// Actions are collected directly into PlatformItemListButtonStyle-backed items.

// MARK: - ConfirmationDialogPreference

// Presentation preference used by the modal queue.
struct ConfirmationDialogPreference: @unchecked Sendable {
    let title: Text
    let titleVisibility: Visibility
    let actionsItemList: PlatformItemList?
    let makeActions: () -> AnyView
    let makeMessage: (() -> AnyView)?
    let messageItemList: PlatformItemList?
    let isPresented: Binding<Bool>
    // Used by the modal queue when the presentation is dismissed.
    let onDismiss: (() -> Void)?
    // Backend policy captured from the dialog modifier's environment.
    // Default is overlay; editors can opt into platform modal windows.
    let usesPlatformWindow: Bool
}

// MARK: - ConfirmationDialog

// Storage value emitted through preferences.
// Dictionary<ViewIdentity, ConfirmationDialog> is the preference value.
struct ConfirmationDialog: @unchecked Sendable {
    let preference: ConfirmationDialogPreference

    struct PreferenceKey: _PreferenceKeyProto {
        typealias Value = [ViewIdentity: ConfirmationDialog]
        static var defaultValue: Value { [:] }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

// MARK: - MakeConfirmationDialog

// Builds the preference mutation for active confirmation dialogs.
// Position, size, and transform are retained for popover-style anchor positioning.
// The current modal overlay path does not use those fields yet.
struct MakeConfirmationDialog<Actions: View, Message: View>: StatefulRule {
    typealias Value = (inout [ViewIdentity: ConfirmationDialog]) -> Void

    let environment: Attribute<EnvironmentValues>
    let modifier: Attribute<ConfirmationDialogModifier<Actions, Message>>
    let actionsItemList: WeakAttribute<PlatformItemList>
    let messageItemList: WeakAttribute<PlatformItemList>
    let phase: Attribute<Phase>
    // Passed through from _ViewInputs for future popover anchor support.
    let position: Attribute<CGPoint>
    // Extracted from Attribute<ViewSize>.value.
    let size: Attribute<CGSize>
    let transform: Attribute<ViewTransform>
    var identityTracker: ViewIdentity.Tracker

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("MakeConfirmationDialog.updateValue called outside AG context")
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
            AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: ConfirmationDialog]) in
                dict.removeValue(forKey: id)
            } as Value)
            return
        }
        let pref = ConfirmationDialogPreference(
            title: m.title,
            titleVisibility: m.titleVisibility,
            actionsItemList: actionsList,
            makeActions: { AnyView(m.actions) },
            makeMessage: (m.message is EmptyView) ? nil : { AnyView(m.message) },
            messageItemList: messageList,
            isPresented: m.isPresented,
            onDismiss: nil,
            usesPlatformWindow: environment.modalSessionUsingPlatformWindow
        )
        let storage = ConfirmationDialog(preference: pref)
        let id = identity
        AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: ConfirmationDialog]) in
            dict[id] = storage
        } as Value)
    }
}

// MARK: - ConfirmationDialogModifier

// MultiViewModifier that records confirmation-dialog presentation state.
struct ConfirmationDialogModifier<Actions: View, Message: View>: ViewModifier, MultiViewModifier {
    typealias Body = Never

    let presentedValue: Bool
    let title: Text
    let titleVisibility: Visibility
    let actions: Actions
    let message: Message
    let isPresented: Binding<Bool>
}

extension ConfirmationDialogModifier {
    // _makeView collects actions and message content into platform item lists.
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                          body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ConfirmationDialogModifier._makeView called outside AG context")
        }

        var outputs = body(_Graph(), inputs)

        // Use PlatformItemListGenerator for both actions and message content.
        let actionsGenerator = PlatformItemListGenerator<AllPlatformItemListFlags, Actions>(
            content: modifier[\.actions]._attribute,
            inputs: inputs,
            inputsIncludeGeometry: true
        )
        let actionsListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(actionsGenerator)

        let messageGenerator = PlatformItemListGenerator<TextPlatformItemListFlags, Message>(
            flags: TextPlatformItemListFlags.self,
            content: modifier[\.message]._attribute,
            inputs: inputs,
            inputsIncludeGeometry: true
        )
        let messageListAttr: Attribute<PlatformItemList> = graph.makeStatefulRule(messageGenerator)

        let sizeAttr: Attribute<CGSize> = graph.makeRule { inputs.size.value.value }
        let storageRule = MakeConfirmationDialog<Actions, Message>(
            environment: inputs.base.cachedEnvironment.value.environment,
            modifier: modifier._attribute,
            actionsItemList: actionsListAttr.asWeak(),
            messageItemList: messageListAttr.asWeak(),
            phase: inputs.base.phase,
            position: inputs.position,
            size: sizeAttr,
            transform: inputs.transform,
            identityTracker: ViewIdentity.Tracker()
        )
        let storageAttr: Attribute<MakeConfirmationDialog<Actions, Message>.Value> =
            graph.makeStatefulRule(storageRule)

        let prefAttr: Attribute<ConfirmationDialog.PreferenceKey.Value> = graph.makeRule {
            var dict = ConfirmationDialog.PreferenceKey.defaultValue
            storageAttr.value(&dict)
            return dict
        }
        outputs.preferences.append(ConfirmationDialog.PreferenceKey.self,
                                   node: prefAttr.identifier)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                     body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        guard AttributeGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active AttributeGraph context.")
        }
        var outputs = body(_Graph(), inputs)
        outputs.multiModifier(modifier, inputs: inputs)
        return outputs
    }
}

// MARK: - ConfirmationDialogOverlayView

struct ConfirmationDialogOverlayView: View {
    let preference: ConfirmationDialogPreference

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .onTapGesture {}
            alertPanel
        }
    }

    private var alertPanel: some View {
        VStack(spacing: 0) {
            if preference.titleVisibility != .hidden {
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
            }
            actions
                .padding(8)
        }
        .frame(width: 280)
        .background(Color(white: 0.97), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var actions: some View {
        if let list = preference.actionsItemList, !list.buttonItems.isEmpty {
            // Use at most three items.
            // 2 buttons -> HStack (cancel left / default right)
            // 3 buttons -> VStack sorted by role priority
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

    // Button display order: default/custom -> destructive -> cancel.
    // 2-button horizontal: cancel left, default right.
    private func orderedItems(_ items: [PlatformItemList.Item]) -> [PlatformItemList.Item] {
        let cancel = items.filter { $0.role == .cancel }
        let destructive = items.filter { $0.role == .destructive }
        let other = items.filter { $0.role != .cancel && $0.role != .destructive }
        if items.count == 2 {
            // HStack: cancel goes left (index 0), default goes right (index 1)
            return cancel + other + destructive
        }
        // VStack: default/custom top, destructive middle, cancel bottom.
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

// MARK: - View.confirmationDialog extensions

extension View {
    public func confirmationDialog<A: View>(_ titleKey: LocalizedStringKey,
                                            isPresented: Binding<Bool>,
                                            titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions)
    }

    public func confirmationDialog<S: StringProtocol, A: View>(_ title: S,
                                                                isPresented: Binding<Bool>,
                                                                titleVisibility: Visibility = .automatic,
                                                                @ViewBuilder actions: () -> A) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions)
    }

    public func confirmationDialog<A: View>(_ title: Text,
                                            isPresented: Binding<Bool>,
                                            titleVisibility: Visibility = .automatic,
                                            @ViewBuilder actions: () -> A) -> some View {
        // Wrap actions directly with the platform item-list button style.
        modifier(ConfirmationDialogModifier(
            presentedValue: isPresented.wrappedValue,
            title: title,
            titleVisibility: titleVisibility,
            actions: actions().modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle())),
            message: EmptyView(),
            isPresented: isPresented))
    }
}

extension View {
    public func confirmationDialog<A: View, M: View>(_ titleKey: LocalizedStringKey,
                                                      isPresented: Binding<Bool>,
                                                      titleVisibility: Visibility = .automatic,
                                                      @ViewBuilder actions: () -> A,
                                                      @ViewBuilder message: () -> M) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions, message: message)
    }

    public func confirmationDialog<S: StringProtocol, A: View, M: View>(_ title: S,
                                                                          isPresented: Binding<Bool>,
                                                                          titleVisibility: Visibility = .automatic,
                                                                          @ViewBuilder actions: () -> A,
                                                                          @ViewBuilder message: () -> M) -> some View {
        confirmationDialog(Text(title), isPresented: isPresented,
                           titleVisibility: titleVisibility, actions: actions, message: message)
    }

    public func confirmationDialog<A: View, M: View>(_ title: Text,
                                                      isPresented: Binding<Bool>,
                                                      titleVisibility: Visibility = .automatic,
                                                      @ViewBuilder actions: () -> A,
                                                      @ViewBuilder message: () -> M) -> some View {
        modifier(ConfirmationDialogModifier(
            presentedValue: isPresented.wrappedValue,
            title: title,
            titleVisibility: titleVisibility,
            actions: actions().modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle())),
            message: message(),
            isPresented: isPresented))
    }
}

extension View {
    public func confirmationDialog<A: View, T>(_ titleKey: LocalizedStringKey,
                                                isPresented: Binding<Bool>,
                                                titleVisibility: Visibility = .automatic,
                                                presenting data: T?,
                                                @ViewBuilder actions: (T) -> A) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility, presenting: data, actions: actions)
    }

    public func confirmationDialog<A: View, T>(_ title: Text,
                                                isPresented: Binding<Bool>,
                                                titleVisibility: Visibility = .automatic,
                                                presenting data: T?,
                                                @ViewBuilder actions: (T) -> A) -> some View {
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let data {
            return AnyView(modifier(ConfirmationDialogModifier(
                presentedValue: gated.wrappedValue,
                title: title,
                titleVisibility: titleVisibility,
                actions: actions(data).modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle())),
                message: EmptyView(),
                isPresented: gated)))
        }
        return AnyView(modifier(ConfirmationDialogModifier(
            presentedValue: gated.wrappedValue,
            title: title,
            titleVisibility: titleVisibility,
            actions: EmptyView().modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle())),
            message: EmptyView(),
            isPresented: gated)))
    }
}

extension View {
    public func confirmationDialog<A: View, M: View, T>(_ titleKey: LocalizedStringKey,
                                                         isPresented: Binding<Bool>,
                                                         titleVisibility: Visibility = .automatic,
                                                         presenting data: T?,
                                                         @ViewBuilder actions: (T) -> A,
                                                         @ViewBuilder message: (T) -> M) -> some View {
        confirmationDialog(Text(titleKey), isPresented: isPresented,
                           titleVisibility: titleVisibility,
                           presenting: data, actions: actions, message: message)
    }

    public func confirmationDialog<A: View, M: View, T>(_ title: Text,
                                                         isPresented: Binding<Bool>,
                                                         titleVisibility: Visibility = .automatic,
                                                         presenting data: T?,
                                                         @ViewBuilder actions: (T) -> A,
                                                         @ViewBuilder message: (T) -> M) -> some View {
        let gated = Binding<Bool>(get: { data != nil && isPresented.wrappedValue },
                                  set: { isPresented.wrappedValue = $0 })
        if let data {
            return AnyView(modifier(ConfirmationDialogModifier(
                presentedValue: gated.wrappedValue,
                title: title,
                titleVisibility: titleVisibility,
                actions: actions(data).modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle())),
                message: message(data),
                isPresented: gated)))
        }
        return AnyView(modifier(ConfirmationDialogModifier(
            presentedValue: gated.wrappedValue,
            title: title,
            titleVisibility: titleVisibility,
            actions: EmptyView().modifier(PrimitiveButtonStyleContainerModifier(style: PlatformItemListButtonStyle())),
            message: EmptyView(),
            isPresented: gated)))
    }
}
