//
//  File: SheetPresentationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - SheetPreference

/// Namespace for sheet presentation preference types.
struct SheetPreference {

    enum Placement: Equatable {
        case automatic
    }

    /// Runtime data for a single sheet presentation.
    struct Session {
        let makeContent: () -> AnyView
        let isPresented: Binding<Bool>
        let onDismiss: (() -> Void)?
        let drawsBackground: Bool
        let placement: Placement
    }

    /// Preference value containing all active sessions from the view tree.
    struct Value {
        var sessions: [Session]
        init(sessions: [Session] = []) { self.sessions = sessions }
    }

    struct Key: HostPreferenceKey {
        typealias Value = SheetPreference.Value
        static var defaultValue: Value { Value() }
        static func reduce(value: inout Value, nextValue: () -> Value) {
            value.sessions.append(contentsOf: nextValue().sessions)
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

/// Default anchor with no geometry, using a standard preference transform.
/// Drops Transaction when wrapping into _PreferenceTransformModifier.
struct NullSheetAnchor<Key: PreferenceKey>: SheetAnchorProvider {
    typealias Modifier = _PreferenceTransformModifier<SheetPreference.Key>

    func preferenceTransformModifier(
        for body: @escaping (inout SheetPreference.Value, Transaction) -> Void
    ) -> _PreferenceTransformModifier<SheetPreference.Key> {
        _PreferenceTransformModifier<SheetPreference.Key> { value in
            body(&value, Transaction())
        }
    }
}

// MARK: - CoreSheetPresentationModifier

/// EnvironmentalModifier that writes SheetPreference.Value into the view tree.
/// resolve(in:) creates a (inout Value, Transaction) -> Void closure,
/// passes it to anchorProvider.preferenceTransformModifier(for:).
struct CoreSheetPresentationModifier<AnchorProvider: SheetAnchorProvider>: EnvironmentalModifier {
    typealias ResolvedModifier = AnchorProvider.Modifier

    let _isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let makeContent: () -> AnyView
    let placement: SheetPreference.Placement
    let drawsBackground: Bool
    let activeInspector: Bool?
    let anchorProvider: AnchorProvider

    func resolve(in environment: EnvironmentValues) -> AnchorProvider.Modifier {
        let isPresented = _isPresented
        let makeContent = makeContent
        let onDismiss = onDismiss
        let placement = placement
        let drawsBackground = drawsBackground

        return anchorProvider.preferenceTransformModifier { value, _ in
            if isPresented.wrappedValue {
                value.sessions.append(SheetPreference.Session(
                    makeContent: makeContent,
                    isPresented: isPresented,
                    onDismiss: onDismiss,
                    drawsBackground: drawsBackground,
                    placement: placement
                ))
            }
        }
    }
}

// MARK: - SheetContent

/// Wrapper view that decorates the sheet body content.
/// Currently a pass-through stub for future sheet-specific styling.
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

    let _isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let sheetContent: () -> Content
    let placement: SheetPreference.Placement
    let drawsBackground: Bool
    let anchorProvider: AnchorProvider
    let activeInspector: Bool?

    var isPresented: Bool { _isPresented.wrappedValue }

    func body(content: _ViewModifier_Content<SheetPresentationModifier>) -> Body {
        let coreModifier = CoreSheetPresentationModifier<AnchorProvider>(
            _isPresented: _isPresented,
            onDismiss: onDismiss,
            makeContent: { AnyView(sheetContent()) },
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

    func body(content: _ViewModifier_Content<ItemSheetPresentationModifier>) -> Body {
        let item = _item
        let sheetContent = sheetContent
        let isPresentedBinding = Binding<Bool>(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )
        let coreModifier = CoreSheetPresentationModifier<AnchorProvider>(
            _isPresented: isPresentedBinding,
            onDismiss: onDismiss,
            makeContent: {
                if let current = item.wrappedValue {
                    return AnyView(sheetContent(current))
                }
                return AnyView(EmptyView())
            },
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
                _isPresented: isPresented,
                onDismiss: onDismiss,
                sheetContent: content,
                placement: .automatic,
                drawsBackground: true,
                anchorProvider: NullSheetAnchor<SheetPreference.Key>(),
                activeInspector: nil
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
                _item: item,
                onDismiss: onDismiss,
                sheetContent: content,
                placement: .automatic,
                drawsBackground: true,
                anchorProvider: NullSheetAnchor<SheetPreference.Key>()
            )
        )
    }
}
