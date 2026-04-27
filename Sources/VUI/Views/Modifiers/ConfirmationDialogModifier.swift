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

// MARK: - ConfirmationDialogPreference

// Runtime data needed to render a confirmation dialog overlay.
struct ConfirmationDialogPreference: @unchecked Sendable {
    let title: Text
    let titleVisibility: Visibility
    let actionsItemList: PlatformItemList?
    let makeActions: () -> AnyView
    let makeMessage: (() -> AnyView)?
    let messageItemList: PlatformItemList?
    let isPresented: Binding<Bool>
    // Used by the modal queue during PresentationSession cleanup.
    let onDismiss: (() -> Void)?
}

// MARK: - ConfirmationDialog
// Stores the confirmation dialog preference written into view preferences.
struct ConfirmationDialog: @unchecked Sendable {
    let preference: ConfirmationDialogPreference

    // Merges confirmation dialog storage by identity. The next value wins on collision.
    struct PreferenceKey: _PreferenceKeyProto {
        typealias Value = [ViewIdentity: ConfirmationDialog]
        static var defaultValue: Value { [:] }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

// MARK: - MakeConfirmationDialog
// StatefulRule that produces the confirmation dialog preference mutation closure.
// Position, size, and transform are reserved for popover-style anchor positioning.
struct MakeConfirmationDialog<Actions: View, Message: View>: StatefulRule {
    typealias Value = (inout [ViewIdentity: ConfirmationDialog]) -> Void

    let environment: Attribute<EnvironmentValues>
    let modifier: Attribute<ConfirmationDialogModifier<Actions, Message>>
    let actionsItemList: AGWeakAttribute
    let messageItemList: AGWeakAttribute
    let phase: Attribute<Phase>
    // Popover anchor inputs are currently passed through and not used by the overlay path.
    let position: Attribute<CGPoint>
    let size: Attribute<ViewTransform>   // TODO: replace with Attribute<CGSize> when the size path is available.
    let transform: Attribute<ViewTransform>
    var identityTracker: ViewIdentity.Tracker

    mutating func updateValue() {
        guard let graph = AttributeGraph.current else {
            fatalError("MakeConfirmationDialog.updateValue called outside AG context")
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
            onDismiss: nil
        )
        let storage = ConfirmationDialog(preference: pref)
        let id = identity
        AttributeGraph.setStatefulOutput({ (dict: inout [ViewIdentity: ConfirmationDialog]) in
            dict[id] = storage
        } as Value)
    }
}

// MARK: - ConfirmationDialogModifier
// ViewModifier for presenting a confirmation dialog when isPresented is true.
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
    // Creates a stateful rule that produces the confirmation dialog preference mutation.
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs,
                          body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ConfirmationDialogModifier._makeView called outside AG context")
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

        // Pass position/size/transform from _ViewInputs for future popover anchor support.
        // TODO: size should become Attribute<CGSize> when that attribute path is available.
        let storageRule = MakeConfirmationDialog<Actions, Message>(
            environment: inputs.base.cachedEnvironment.value.environment,
            modifier: modifier._attribute,
            actionsItemList: actionsItemList.asWeak(),
            messageItemList: messageItemList.asWeak(),
            phase: inputs.base.phase,
            position: inputs.position,
            size: inputs.transform,      // TODO: placeholder until a CGSize attribute path is available.
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
        var outputs = body(_Graph(), inputs)
        outputs.preferences.append(ConfirmationDialog.PreferenceKey.self,
                                   node: prefAttr.identifier)
        return outputs
    }

    public static func _makeViewList(modifier: _GraphValue<Self>, inputs: _ViewListInputs,
                                     body: @escaping (_Graph, _ViewListInputs) -> _ViewListOutputs) -> _ViewListOutputs {
        body(_Graph(), inputs)
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
            // Show only the first three action items.
            // 2 buttons use HStack with cancel on the left and default on the right.
            // 3 buttons use VStack sorted by role priority.
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

    // Button display order: default/custom, destructive, then cancel.
    // 2-button horizontal layout places cancel on the left and default on the right.
    private func orderedItems(_ items: [PlatformItemList.Item]) -> [PlatformItemList.Item] {
        let cancel = items.filter { $0.role == .cancel }
        let destructive = items.filter { $0.role == .destructive }
        let other = items.filter { $0.role != .cancel && $0.role != .destructive }
        if items.count == 2 {
            // HStack: cancel goes left (index 0), default goes right (index 1)
            return cancel + other + destructive
        }
        // VStack: default/custom top, destructive middle, cancel bottom
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
        // Collect action items directly through the platform item list button style.
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
