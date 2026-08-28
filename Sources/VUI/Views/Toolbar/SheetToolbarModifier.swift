//
//  File: SheetToolbarModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// MARK: - SheetToolbarModifier

// SheetToolbarModifier: ViewModifier applied as the penultimate step in SheetContent.body.
// body(content:) returns StaticIf<_SemanticFeature<Semantics_v6>, readerBody, forceBody>.
// Stateless modifier (no stored fields).
//
// ReaderBody uses ToolbarReader to feed toolbar storage into ModalButtonRow.
// ForceBody keeps the sheet-content layout path available when the semantic gate
// disables the reader branch.
struct SheetToolbarModifier: ViewModifier {
    func body(content: _ViewModifier_Content<SheetToolbarModifier>) -> some View {
        StaticIf<_SemanticFeature<Semantics_v6>, ReaderBody, ForceBody>(
            trueBody: ReaderBody(content: content),
            falseBody: ForceBody(content: content)
        )
    }

    // ReaderBody uses ToolbarReader with the simplified primitive reader.
    struct ReaderBody: View {
        var content: _ViewModifier_Content<SheetToolbarModifier>

        var body: some View {
            ToolbarReader(AllToolbarEdges.self) { reader in
                _VariadicView.Tree(_LayoutRoot(SheetContentRoot(_VStackLayout()))) {
                    _UnaryViewAdaptor(content)
                    modalToolbar(reader.storage)
                }
            }
            .environment(\._toolbarUpdateContext, Optional<Toolbar.UpdateContext>.none)
            .modifier(ToolbarFilterModifier(predicate: .keyPath(\ToolbarItemPlacement.Role.isModalAction)))
            .transformPreference(SearchContentKey.self) { value in
                value = nil
            }
        }

        @ViewBuilder
        private func modalToolbar(_ storage: ToolbarStorage) -> some View {
            let modalStorage = modalOnlyStorage(storage)
            if !modalStorage.items.isEmpty {
                VStack(spacing: 0) {
                    Divider()
                    ModalButtonRow(storage: modalStorage)
                        .padding(EdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20))
                }
                .frame(maxWidth: .infinity)
                .platformGroupFocusSection()
            } else {
                EmptyView()
            }
        }

        private func modalOnlyStorage(_ storage: ToolbarStorage) -> ToolbarStorage {
            var copy = storage
            copy.items = storage.items.filter { $0.placement.isModalAction }
            return copy
        }
    }

    struct ForceBody: View {
        var content: _ViewModifier_Content<SheetToolbarModifier>

        var body: some View {
            _VariadicView.Tree(_LayoutRoot(SheetContentRoot(_VStackLayout()))) {
                _UnaryViewAdaptor(content)
                EmptyView()
            }
            .modifier(ToolbarFilterModifier(predicate: .keyPath(\ToolbarItemPlacement.Role.isModalAction)))
        }
    }

    // ModalButtonRow stores the current toolbar storage.
    struct ModalButtonRow: View {
        var storage: ToolbarStorage

        var confirmation: IDView<ToolbarStoredItemView, ToolbarStorage.ID>? {
            firstView(in: .confirmationAction)
        }

        var leadingItems: [ToolbarStorage.Item] {
            storage.toolbarItems(in: .destructiveAction)
        }

        func firstView(in role: ToolbarItemPlacement.Role) -> IDView<ToolbarStoredItemView, ToolbarStorage.ID>? {
            guard let item = storage.toolbarItems(in: role).first else { return nil }
            return IDView(ToolbarStoredItemView(item: item), id: item.id)
        }

        var body: some View {
            _VariadicView.Tree(_LayoutRoot(DialogBottomButtonsHLayout(leadingCount: leadingItems.count))) {
                ForEach(leadingItems) { item in
                    ToolbarStoredItemView(item: item)
                        .buttonStyle(SheetToolbarButtonStyle(placement: item.placement))
                }
                firstView(in: .cancellationAction)?
                    .buttonStyle(SheetToolbarButtonStyle(placement: .cancellationAction))
                    ._trait(KeyboardShortcutPickerOptionTraitKey.self, KeyboardShortcut.cancelAction)
                confirmation?
                    .buttonStyle(SheetToolbarButtonStyle(placement: .confirmationAction))
                    ._trait(KeyboardShortcutPickerOptionTraitKey.self, KeyboardShortcut.defaultAction)
            }
        }
    }
}

// Local sheet modal action button style. The exact platform
// button bridge remains a boundary, but role-specific treatment is encoded here.
private struct SheetToolbarButtonStyle: PrimitiveButtonStyle {
    var placement: ToolbarItemPlacement.Role

    func makeBody(configuration: Configuration) -> some View {
        SheetToolbarButtonBody(configuration: configuration, placement: placement)
    }
}

private struct SheetToolbarButtonBody: View {
    let configuration: PrimitiveButtonStyleConfiguration
    let placement: ToolbarItemPlacement.Role
    @State private var isPressed = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            configuration.label
            Spacer(minLength: 0)
        }
        .frame(minWidth: 76, minHeight: 32)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background {
            RoundedRectangle(cornerRadius: 6).fill(background)
            RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: borderWidth)
        }
        ._onButtonGesture(pressing: { isPressed = $0 }, perform: { configuration.trigger() })
    }

    private var foreground: Color {
        if placement.isConfirmationAction { return .white }
        if placement.isDestructiveAction { return Color(red: 1.0, green: 0.12, blue: 0.16) }
        return .black
    }

    private var background: Color {
        if placement.isConfirmationAction {
            return isPressed
                ? Color(red: 0.0, green: 0.36, blue: 0.86)
                : Color(red: 0.0, green: 0.47, blue: 1.0)
        }
        if placement.isDestructiveAction {
            return isPressed
                ? Color(red: 1.0, green: 0.62, blue: 0.64)
                : Color(red: 1.0, green: 0.76, blue: 0.78)
        }
        return Color(white: isPressed ? 0.86 : 0.96)
    }

    private var border: Color {
        if placement.isConfirmationAction { return .clear }
        if placement.isCancellationAction { return Color(red: 0.42, green: 0.62, blue: 0.95) }
        if placement.isDestructiveAction { return .clear }
        return Color(white: 0.64)
    }

    private var borderWidth: CGFloat {
        placement.isCancellationAction ? 2 : 1
    }
}

// Toolbar entry bridge for the current preference path:
// prefer the original unary generator so Button's StaticSourceWriter label
// source remains attached. Keep AnyView as a fallback for erased items.
struct ToolbarStoredItemView: View {
    var item: ToolbarStorage.Item

    typealias Body = Never

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let item = view._attribute.value.item
        if let generator = item.generator,
           let outputs = generator.makeView(inputs: inputs) {
            return outputs
        }
        return AnyView._makeView(view: view[\.item.view], inputs: inputs)
    }

    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }
}

extension ToolbarStoredItemView: PrimitiveView {}
