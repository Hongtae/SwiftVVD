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

// Key differences from AlertModifier:
//   - ConfirmationDialogModifier is a MultiViewModifier.
//   - No `auxiliaryContent` or `representsError` fields
//   - Actions are wrapped directly with PrimitiveButtonStyleContainerModifier.
//   - ConfirmationDialog.PreferenceKey is a regular PreferenceKey.
//   - MakeConfirmationDialog stores position, size, and transform attributes.

// MARK: - ConfirmationDialogPreference

// Presentation preference used by the modal queue and overlay renderer.
struct ConfirmationDialogPreference: @unchecked Sendable {
    let title: Text
    let titleVisibility: Visibility
    let actionsItemList: PlatformItemList?
    let makeActions: () -> AnyView
    let makeMessage: (() -> AnyView)?
    let messageItemList: PlatformItemList?
    let isPresented: Binding<Bool>
    // Used by the modal queue onDismiss path.
    let onDismiss: (() -> Void)?
    // Presentation backend policy captured from the dialog modifier's environment.
    // Default is overlay. Editors can opt into platform modal windows.
    let usesPlatformWindow: Bool
}

// MARK: - ConfirmationDialog
// Dictionary<ViewIdentity, ConfirmationDialog> is the preference value.
struct ConfirmationDialog: @unchecked Sendable {
    let preference: ConfirmationDialogPreference
    let title: String
    let colorScheme: ColorScheme?
    let icon: Image?
    let tintColor: Color.Resolved?
    let suppressionConfiguration: DialogSuppressionConfiguration?
    let accessibilityTitle: NSAttributedString?
    let preventsTermination: Bool?

    // Regular PreferenceKey, not HostPreferenceKey.
    struct PreferenceKey: _PreferenceKeyProto {
        typealias Value = [ViewIdentity: ConfirmationDialog]
        static var defaultValue: Value { [:] }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

// MARK: - MakeConfirmationDialog
// Stateful rule that publishes a dictionary mutation for confirmation-dialog storage.
//
// MakeConfirmationDialog.init extra fields vs MakeAlertStorage:
//   position: Attribute<CGPoint>
//   size:     Attribute<CGSize>      (extracted from Attribute<ViewSize>.value)
//   transform: Attribute<ViewTransform>
// These are retained for popover-style anchor positioning.
// The current modal presentation path does not consume them.
struct MakeConfirmationDialog<Actions: View, Message: View>: StatefulRule {
    typealias Value = (inout [ViewIdentity: ConfirmationDialog]) -> Void

    let environment: Attribute<EnvironmentValues>
    let modifier: Attribute<ConfirmationDialogModifier<Actions, Message>>
    let actionsItemList: WeakAttribute<PlatformItemList>
    let messageItemList: WeakAttribute<PlatformItemList>
    let phase: Attribute<Phase>
    // Pass-through attributes from _ViewInputs for anchor-aware presentation.
    let position: Attribute<CGPoint>
    // Extracted from Attribute<ViewSize>.value (ViewSize.value = CGSize).
    let size: Attribute<CGSize>
    let transform: Attribute<ViewTransform>
    var identityTracker: ViewIdentity.Tracker
    var propertyTracker: _PropertyListTracker

    // Change-detection cache fields retained for platform-dialog update decisions.
    var lastTitle: Optional<String>
    var lastColorScheme: Optional<ColorScheme>
    var lastIcon: Optional<Image>
    var lastTintColor: Optional<Color.Resolved>
    var lastSeverity: DialogSeverity
    var lastSuppressionConfiguration: Optional<DialogSuppressionConfiguration>
    var lastAccessibilityTitle: Optional<NSAttributedString>
    var lastDialogPreventsTermination: Optional<Bool>

    init(
        environment: Attribute<EnvironmentValues>,
        modifier: Attribute<ConfirmationDialogModifier<Actions, Message>>,
        actionsItemList: WeakAttribute<PlatformItemList>,
        messageItemList: WeakAttribute<PlatformItemList>,
        phase: Attribute<Phase>,
        position: Attribute<CGPoint>,
        size: Attribute<CGSize>,
        transform: Attribute<ViewTransform>,
        identityTracker: ViewIdentity.Tracker,
        lastTitle: Optional<String>,
        lastColorScheme: Optional<ColorScheme>,
        lastIcon: Optional<Image>,
        lastTintColor: Optional<Color.Resolved>,
        lastSeverity: DialogSeverity,
        lastSuppressionConfiguration: Optional<DialogSuppressionConfiguration>,
        lastAccessibilityTitle: Optional<NSAttributedString>,
        lastDialogPreventsTermination: Optional<Bool>
    ) {
        self.init(
            environment: environment,
            modifier: modifier,
            actionsItemList: actionsItemList,
            messageItemList: messageItemList,
            phase: phase,
            position: position,
            size: size,
            transform: transform,
            identityTracker: identityTracker,
            propertyTracker: _PropertyListTracker(),
            lastTitle: lastTitle,
            lastColorScheme: lastColorScheme,
            lastIcon: lastIcon,
            lastTintColor: lastTintColor,
            lastSeverity: lastSeverity,
            lastSuppressionConfiguration: lastSuppressionConfiguration,
            lastAccessibilityTitle: lastAccessibilityTitle,
            lastDialogPreventsTermination: lastDialogPreventsTermination
        )
    }

    init(
        environment: Attribute<EnvironmentValues>,
        modifier: Attribute<ConfirmationDialogModifier<Actions, Message>>,
        actionsItemList: WeakAttribute<PlatformItemList>,
        messageItemList: WeakAttribute<PlatformItemList>,
        phase: Attribute<Phase>,
        position: Attribute<CGPoint>,
        size: Attribute<CGSize>,
        transform: Attribute<ViewTransform>,
        identityTracker: ViewIdentity.Tracker,
        propertyTracker: _PropertyListTracker,
        lastTitle: Optional<String>,
        lastColorScheme: Optional<ColorScheme>,
        lastIcon: Optional<Image>,
        lastTintColor: Optional<Color.Resolved>,
        lastSeverity: DialogSeverity,
        lastSuppressionConfiguration: Optional<DialogSuppressionConfiguration>,
        lastAccessibilityTitle: Optional<NSAttributedString>,
        lastDialogPreventsTermination: Optional<Bool>
    ) {
        self.environment = environment
        self.modifier = modifier
        self.actionsItemList = actionsItemList
        self.messageItemList = messageItemList
        self.phase = phase
        self.position = position
        self.size = size
        self.transform = transform
        self.identityTracker = identityTracker
        self.propertyTracker = propertyTracker
        self.lastTitle = lastTitle
        self.lastColorScheme = lastColorScheme
        self.lastIcon = lastIcon
        self.lastTintColor = lastTintColor
        self.lastSeverity = lastSeverity
        self.lastSuppressionConfiguration = lastSuppressionConfiguration
        self.lastAccessibilityTitle = lastAccessibilityTitle
        self.lastDialogPreventsTermination = lastDialogPreventsTermination
    }

    mutating func updateValue() {
        guard let graph = _AGGraph.current else {
            fatalError("MakeConfirmationDialog.updateValue called outside AG context")
        }
        var actionsList: PlatformItemList?
        var messageList: PlatformItemList?
        if actionsItemList.isValid(in: graph) {
            actionsList = actionsItemList.toStrong().value
        }
        if messageItemList.isValid(in: graph) {
            messageList = messageItemList.toStrong().value
        }
        let m = modifier.value
        let phaseValue = phase.value
        let values = environment.value
        guard let environment = trackedEnvironment(from: values) else { return }
        let title = m.title._resolveText(in: environment)
        let dialogColorScheme = environment.dialogColorScheme
        let explicitPreferredColorScheme = environment.explicitPreferredColorScheme
        let colorScheme = dialogColorScheme ?? explicitPreferredColorScheme
        let icon = environment.dialogIcon
        let tintColor = environment.dialogTintColor?.resolve(in: environment)
        let severity = environment.dialogSeverity
        let suppressionConfiguration = environment.dialogSuppression
        let preventsTermination = environment.dialogPreventsAppTermination
        let accessibilityTitle = resolvedAccessibilityTitle(for: m.title, in: environment)
        lastTitle = title
        lastColorScheme = colorScheme
        lastIcon = icon
        lastTintColor = tintColor
        lastSeverity = severity
        lastSuppressionConfiguration = suppressionConfiguration
        lastAccessibilityTitle = accessibilityTitle
        lastDialogPreventsTermination = preventsTermination
        let identity = identityTracker.update(for: phaseValue)
        guard m.isPresented.wrappedValue else {
            let id = identity
            _AGGraph.setStatefulOutput({ (dict: inout [ViewIdentity: ConfirmationDialog]) in
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
        let storage = ConfirmationDialog(
            preference: pref,
            title: title,
            colorScheme: colorScheme,
            icon: icon,
            tintColor: tintColor,
            suppressionConfiguration: suppressionConfiguration,
            accessibilityTitle: accessibilityTitle,
            preventsTermination: preventsTermination
        )
        let id = identity
        _AGGraph.setStatefulOutput({ (dict: inout [ViewIdentity: ConfirmationDialog]) in
            dict[id] = storage
        } as Value)
    }

    private mutating func trackedEnvironment(from values: EnvironmentValues) -> EnvironmentValues? {
        if _AGGraph.currentStatefulOutput(Value.self) != nil,
           !_AGGraphAnyInputsChanged(),
           !propertyTracker.hasDifferentUsedValues(values._plist) {
            return nil
        }
        propertyTracker.reset()
        return EnvironmentValues(values._plist, tracker: propertyTracker)
    }

    private func resolvedAccessibilityTitle(for title: Text, in environment: EnvironmentValues) -> NSAttributedString? {
        guard environment.accessibilityEnabled else { return nil }
        // Accessibility label storage is not wired yet, so there is no payload to resolve.
        _ = title
        return nil
    }
}

// MARK: - ConfirmationDialogModifier
// Confirmation-dialog modifier storage. Unlike AlertModifier, this has no
// auxiliary content or error-representation field.
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
        guard let graph = _AGGraph.current else {
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
            identityTracker: ViewIdentity.Tracker(),
            lastTitle: nil,
            lastColorScheme: nil,
            lastIcon: nil,
            lastTintColor: nil,
            lastSeverity: .standard,
            lastSuppressionConfiguration: nil,
            lastAccessibilityTitle: nil,
            lastDialogPreventsTermination: nil
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
        guard _AGGraph.current != nil else {
            fatalError("\(Self.self)._makeViewList called outside an active _AGGraph context.")
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
            DialogOverlayPanel(title: panelTitle,
                               makeMessage: preference.makeMessage,
                               buttonItems: panelButtonItems,
                               makeActions: preference.makeActions,
                               isPresented: preference.isPresented)
        }
    }

    private var panelTitle: Text? {
        preference.titleVisibility == .hidden ? nil : preference.title
    }

    private var panelButtonItems: [PlatformItemList.Item]? {
        guard let list = preference.actionsItemList else {
            return nil
        }
        return confirmationDialogItems(list.buttonItems)
    }

    private func confirmationDialogItems(_ items: [PlatformItemList.Item]) -> [PlatformItemList.Item] {
        guard !items.isEmpty && items.allSatisfy({ $0.role == nil }) else {
            return items
        }
        var result = items
        result.append(PlatformItemList.Item(label: AnyView(Text("Cancel")),
                                            action: nil,
                                            role: .cancel))
        return result
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
        // Actions are wrapped directly with the platform item-list button style.
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
