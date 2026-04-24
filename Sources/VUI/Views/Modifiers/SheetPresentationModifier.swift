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

    enum Placement: Equatable {
        case automatic
    }

    /// Preference value merged through the view tree.
    ///
    /// Merge behavior:
    ///   .keyed + .keyed: keyed values are merged.
    ///   .keyed + .single: next single value wins.
    ///   .keyed + .none: none clears the value.
    ///   .single + _: existing single value is kept.
    ///   .none + next: next value is used.
    enum Value {
        case keyed([Namespace.ID: Transaction])
        case single(SheetPreference)
        case none
    }

    /// Host-readable preference key for sheet presentations.
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
                break  // first wins, existing single presentation is kept
            case .none:
                value = nextValue()
            }
        }
    }
}

// MARK: - SheetAnchorProvider

/// Protocol producing a ViewModifier that writes into SheetPreference.Value.
protocol SheetAnchorProvider {
    associatedtype Modifier: ViewModifier
    func preferenceTransformModifier(
        for body: @escaping (inout SheetPreference.Value, Transaction) -> Void
    ) -> Modifier
}

// MARK: - NullSheetAnchor

/// Default anchor with no geometry.
struct NullSheetAnchor<Key: PreferenceKey>: SheetAnchorProvider {
    typealias Modifier = _PreferenceTransformModifier<SheetPreference.Key>

    func preferenceTransformModifier(
        for body: @escaping (inout SheetPreference.Value, Transaction) -> Void
    ) -> _PreferenceTransformModifier<SheetPreference.Key> {
        _PreferenceTransformModifier<SheetPreference.Key> { value in
            body(&value, Transaction._current?.transaction ?? Transaction())
        }
    }
}

// MARK: - CoreSheetPresentationModifier

/// EnvironmentalModifier that writes SheetPreference.Value into the view tree.
/// resolve(in:) creates a (inout Value, Transaction) -> Void closure,
/// passes it to anchorProvider.preferenceTransformModifier(for:).
struct CoreSheetPresentationModifier<AnchorProvider: SheetAnchorProvider>: EnvironmentalModifier {
    typealias ResolvedModifier = AnchorProvider.Modifier

    // Namespace used to generate stable presentation identity.
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
                        activeInspector: activeInspector
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

/// Wrapper view that decorates the sheet body content.
/// Currently passes content through unchanged.
struct SheetContent<Content: View>: View {
    var content: Content
    var body: some View { content }
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

    // Backing binding for the presentation state.
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: () -> Content
    let placement: SheetPreference.Placement
    let drawsBackground: Bool
    let anchorProvider: AnchorProvider
    // Reserved for inspector-specific presentation state.
    let activeInspector: Bool?

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
            // DynamicProperty processing assigns this namespace a stable ID.
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
                drawsBackground: true,
                anchorProvider: NullSheetAnchor<SheetPreference.Key>()
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
                drawsBackground: true,
                anchorProvider: NullSheetAnchor<SheetPreference.Key>()
            )
        )
    }
}
