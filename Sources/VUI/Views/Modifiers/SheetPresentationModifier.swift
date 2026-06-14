//
//  File: SheetPresentationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - SheetPreference

/// Outer struct holding runtime data for a single sheet presentation.
struct SheetPreference {
    let content: AnyView
    let onDismiss: (() -> Void)?
    let namespaceID: Namespace.ID
    let itemID: AnyHashable?
    let drawsBackground: Bool
    let placement: Placement
    let activeInspector: Bool?
    // Presentation backend policy captured from the presentation modifier's environment.
    // Default is overlay. Editors can opt into platform modal windows.
    let usesPlatformWindow: Bool

    enum Placement: Equatable {
        case automatic
        // Additional placement cases belong to the presentation subsystem.
    }

    /// Preference value for collected sheet presentation state.
    ///
    /// Merge rules:
    ///   .keyed + .keyed  -> .keyed(merged)
    ///   .keyed + .single -> .single (nextValue wins)
    ///   .keyed + .none   -> .none
    ///   .single + _      -> .single (first wins)
    ///   .none   + next   -> next
    enum Value {
        case keyed([Namespace.ID: Transaction])
        case single(SheetPreference)
        case none
    }

    /// Host-readable preference key for sheet presentation state.
    struct Key: HostPreferenceKey {
        typealias Value = SheetPreference.Value
        static var defaultValue: Value { .none }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            switch value {
            case .keyed(let d1):
                switch nextValue() {
                case .keyed(let d2):
                    value = .keyed(d1.merging(d2) { _, new in new })
                case let next:
                    value = next
                }
            case .single:
                break  // first wins, so the existing single presentation is kept
            case .none:
                value = nextValue()
            }
        }
    }
}

// MARK: - SheetAnchorProvider

/// Protocol producing a ViewModifier that writes into SheetPreference.Value.
/// The modifier receives both the accumulated preference value and the current transaction.
protocol SheetAnchorProvider {
    associatedtype Modifier: ViewModifier
    func preferenceTransformModifier(
        for body: @escaping (inout SheetPreference.Value, Transaction) -> Void
    ) -> Modifier
}

// MARK: - NullSheetAnchor

/// Default anchor: no geometry, standard preference transform.
struct NullSheetAnchor<Key: PreferenceKey>: SheetAnchorProvider {
    typealias Modifier = _PreferenceTransformModifier<SheetPreference.Key>

    func preferenceTransformModifier(
        for body: @escaping (inout SheetPreference.Value, Transaction) -> Void
    ) -> _PreferenceTransformModifier<SheetPreference.Key> {
        _PreferenceTransformModifier<SheetPreference.Key> { value in
            body(&value, Transaction.current)
        }
    }
}

// MARK: - CoreSheetPresentationModifier

/// EnvironmentalModifier that writes SheetPreference.Value into the view tree.
/// resolve(in:) creates a preference transform closure and asks the anchor
/// provider to install it. The namespace field is read during resolve so the
/// sheet preference payload carries a stable namespace ID.
struct CoreSheetPresentationModifier<AnchorProvider: SheetAnchorProvider>: EnvironmentalModifier {
    typealias ResolvedModifier = AnchorProvider.Modifier

    // Namespace used to key sheet preference transactions.
    var _namespace: Namespace
    let content: AnyView?
    let onDismiss: (() -> Void)?
    let itemID: AnyHashable?
    let placement: SheetPreference.Placement
    let drawsBackground: Bool
    let activeInspector: Bool?
    let anchorProvider: AnchorProvider

    func resolve(in environment: EnvironmentValues) -> AnchorProvider.Modifier {
        let namespace = _namespace
        let content = content
        let onDismiss = onDismiss
        let itemID = itemID
        let placement = placement
        let drawsBackground = drawsBackground
        let activeInspector = activeInspector
        let usesPlatformWindow = environment.modalSessionUsingPlatformWindow

        return anchorProvider.preferenceTransformModifier { value, transaction in
            let namespaceID = namespace.wrappedValue

            if let content {
                switch value {
                case .single:
                    Log.warning(
                        "Currently, only presenting a single sheet is supported.\n" +
                        "The next sheet will be presented when the currently presented sheet gets dismissed."
                    )
                case .keyed, .none:
                    value = .single(SheetPreference(
                        content: content,
                        onDismiss: onDismiss,
                        namespaceID: namespaceID,
                        itemID: itemID,
                        drawsBackground: drawsBackground,
                        placement: placement,
                        activeInspector: activeInspector,
                        usesPlatformWindow: usesPlatformWindow
                    ))
                }
            } else {
                switch value {
                case .keyed(var dict):
                    dict[namespaceID] = transaction
                    value = .keyed(dict)
                case .single, .none:
                    value = .keyed([namespaceID: transaction])
                }
            }
        }
    }
}

// MARK: - SheetContent

/// Wrapper view that applies the full sheet decoration chain to Content.
/// The generic wrapper stores the content view and applies the sheet
/// environment/style/toolbar reset chain in order.
struct SheetContent<Content: View>: View {
    var content: Content

    // FixedSidebarModifier: writes Optional<Binding<SidebarState>>.some(Binding.constant(SidebarState(rawValue: 2)))
    // to the env, fixing the sidebar state for sheet presentations.
    // Applied via StaticIf<_SemanticFeature<Semantics_v4>, ...> in body.
    struct FixedSidebarModifier: ViewModifier {
        func body(content: _ViewModifier_Content<FixedSidebarModifier>) -> some View {
            content.environment(\._sidebarStateBinding, .constant(SidebarState(rawValue: 2)))
        }
    }

    var body: some View {
        content
            // Step 1: push SheetStyleContext into StyleContextInput
            .styleContext(.sheet)
            // Step 2: signal to hosting view to render container background
            .renderContainerBackgroundInHostingView(ContainerBackgroundKeys.PresentationKey.self)
            // Step 3: anonymous Optional<Bool> env key (CoreSheetPresentationModifier-associated)
            .environment(\._sheetHostingContext, Optional<Bool>.none)
            // Step 4: reset tint adjustment mode
            .environment(\.tintAdjustmentMode, Optional<TintAdjustmentMode>.none)
            // Step 5: reset scroll environment (gated on Semantics_v6)
            .modifier(StaticIf<_SemanticFeature<Semantics_v6>,
                               ResetScrollEnvironmentModifier,
                               EmptyModifier>(trueBody: ResetScrollEnvironmentModifier(),
                                             falseBody: EmptyModifier()))
            // Step 6: reset list stack behavior
            .resetListStackBehavior()
            // Step 7: reset search environment
            .modifier(ResetSearchEnvironmentModifier())
            // Step 8: reset form environment
            .modifier(ResetFormEnvironmentModifier())
            // Step 9: reset tab view environment
            .modifier(ResetTabViewEnvironmentModifier())
            // Step 10: mark sheet as not presented (resets inherited isSheetPresented)
            .environment(\.isSheetPresented, false)
            // Step 11: clear navigation context via ViewInputsModifier path
            .modifier(ClearNavigationContextModifier())
            // Step 12: reset internal navigation enabled state
            .environment(\.isNavigationEnabledInternal, NavigationEnabled())
            // Step 13: reset navigation selection seed
            .environment(\.navigationSelectionSeed, NavigationState.SelectionSeed())
            // Step 14: clear sharing picker host
            .clearSharingPickerHost()
            // Step 15: mark SheetStyleContext ViewInputFlag in AG customInputs
            .input(SheetStyleContext.self)
            // Step 16: apply fixed sidebar state (gated on Semantics_v4)
            .modifier(StaticIf<_SemanticFeature<Semantics_v4>,
                               FixedSidebarModifier,
                               EmptyModifier>(trueBody: FixedSidebarModifier(),
                                             falseBody: EmptyModifier()))
            // Step 17: apply toolbar (search bar + toolbar buttons + layout)
            .modifier(SheetToolbarModifier())
            // Step 18: write InteractiveResizeDisabledKey = true (first-writer-wins)
            .transformPreference(InteractiveResizeDisabledKey.self) { (value: inout Bool?) in
                if value == nil { value = true }
            }
    }
}

// MARK: - SheetPresentationModifier

/// ViewModifier for presenting a sheet when isPresented is true.
struct SheetPresentationModifier<Content: View, AnchorProvider: SheetAnchorProvider>: ViewModifier {
    typealias Body = SheetContent<
        ModifiedContent<
            _ViewModifier_Content<SheetPresentationModifier>,
            CoreSheetPresentationModifier<AnchorProvider>
        >
    >

    // Property-wrapper storage keeps the binding backing field, wrapped value,
    // and projected value available to the modifier body.
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: () -> Content
    let placement: SheetPreference.Placement
    let drawsBackground: Bool
    let anchorProvider: AnchorProvider
    // Stored field reserved for inspector presentations. Public initializers default it to nil.
    let activeInspector: Bool?

    // activeInspector is stored but not an initializer parameter.
    init(isPresented: Binding<Bool>,
         onDismiss: (() -> Void)?,
         sheetContent: @escaping () -> Content,
         placement: SheetPreference.Placement,
         drawsBackground: Bool,
         anchorProvider: AnchorProvider) {
        self._isPresented = isPresented
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent
        self.placement = placement
        self.drawsBackground = drawsBackground
        self.anchorProvider = anchorProvider
        self.activeInspector = nil
    }

    func body(content: _ViewModifier_Content<SheetPresentationModifier>) -> Body {
        let dismiss = {
            isPresented = false
            onDismiss?()
        }
        let coreModifier = CoreSheetPresentationModifier<AnchorProvider>(
            // The core modifier owns the namespace. A fresh Namespace gets a
            // persistent ID through DynamicProperty processing.
            _namespace: Namespace(),
            content: isPresented ? AnyView(sheetContent()) : nil,
            onDismiss: dismiss,
            itemID: nil,
            placement: placement,
            drawsBackground: drawsBackground,
            activeInspector: activeInspector,
            anchorProvider: anchorProvider
        )
        return SheetContent(content: content.modifier(coreModifier))
    }
}

extension SheetPresentationModifier where AnchorProvider == NullSheetAnchor<SheetPreference.Key> {
    // Convenience initializer for the default sheet anchor.
    init(isPresented: Binding<Bool>,
         onDismiss: (() -> Void)?,
         sheetContent: @escaping () -> Content,
         placement: SheetPreference.Placement,
         drawsBackground: Bool) {
        self.init(isPresented: isPresented,
                  onDismiss: onDismiss,
                  sheetContent: sheetContent,
                  placement: placement,
                  drawsBackground: drawsBackground,
                  anchorProvider: NullSheetAnchor<SheetPreference.Key>())
    }
}

// MARK: - ItemSheetPresentationModifier

/// ViewModifier for presenting a sheet driven by an optional Identifiable item.
struct ItemSheetPresentationModifier<Item: Identifiable, Content: View, AnchorProvider: SheetAnchorProvider>: ViewModifier {
    typealias Body = SheetContent<
        ModifiedContent<
            _ViewModifier_Content<ItemSheetPresentationModifier>,
            CoreSheetPresentationModifier<AnchorProvider>
        >
    >

    let _item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> Content
    let placement: SheetPreference.Placement
    let drawsBackground: Bool
    let anchorProvider: AnchorProvider

    var isPresented: Bool { _item.wrappedValue != nil }

    // Stores the item binding and content builder used to create the active sheet.
    init(item: Binding<Item?>,
         onDismiss: (() -> Void)?,
         sheetContent: @escaping (Item) -> Content,
         placement: SheetPreference.Placement,
         drawsBackground: Bool,
         anchorProvider: AnchorProvider) {
        self._item = item
        self.onDismiss = onDismiss
        self.sheetContent = sheetContent
        self.placement = placement
        self.drawsBackground = drawsBackground
        self.anchorProvider = anchorProvider
    }

    func body(content: _ViewModifier_Content<ItemSheetPresentationModifier>) -> Body {
        let item = _item
        let sheetContent = sheetContent
        let currentItem = item.wrappedValue
        let dismiss = {
            item.wrappedValue = nil
            onDismiss?()
        }
        let coreModifier = CoreSheetPresentationModifier<AnchorProvider>(
            _namespace: Namespace(),
            content: currentItem.map { AnyView(sheetContent($0)) },
            onDismiss: dismiss,
            itemID: currentItem.map { AnyHashable($0.id) },
            placement: placement,
            drawsBackground: drawsBackground,
            activeInspector: nil,
            anchorProvider: anchorProvider
        )
        return SheetContent(content: content.modifier(coreModifier))
    }
}

extension ItemSheetPresentationModifier where AnchorProvider == NullSheetAnchor<SheetPreference.Key> {
    // Convenience initializer for the default sheet anchor.
    init(item: Binding<Item?>,
         onDismiss: (() -> Void)?,
         sheetContent: @escaping (Item) -> Content,
         placement: SheetPreference.Placement,
         drawsBackground: Bool) {
        self.init(item: item,
                  onDismiss: onDismiss,
                  sheetContent: sheetContent,
                  placement: placement,
                  drawsBackground: drawsBackground,
                  anchorProvider: NullSheetAnchor<SheetPreference.Key>())
    }
}

// MARK: - View extensions

extension View {
    /// Presents a sheet when isPresented is true.
    public func sheet<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(
            SheetPresentationModifier(
                isPresented: isPresented,
                onDismiss: onDismiss,
                sheetContent: content,
                placement: .automatic,
                drawsBackground: true
            )
        )
    }

    /// Presents a sheet when item is non-nil.
    public func sheet<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(
            ItemSheetPresentationModifier(
                item: item,
                onDismiss: onDismiss,
                sheetContent: content,
                placement: .automatic,
                drawsBackground: true
            )
        )
    }
}
