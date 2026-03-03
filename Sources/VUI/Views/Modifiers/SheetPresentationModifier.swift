//
//  File: SheetPresentationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct SheetPresentationModifier<Content>: ViewModifier where Content: View {
    typealias Body = Never

    let _isPresented: Binding<Bool>
    let onDismiss: (() -> Void)?
    let sheetContent: () -> Content
}

struct ItemSheetPresentationModifier<Item, Content>: ViewModifier where Item: Identifiable, Content: View {
    typealias Body = Never

    let _item: Binding<Item?>
    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> Content
}

extension View {
    public func sheet<Item, Content>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View where Item: Identifiable, Content: View {
        self.modifier(
            ItemSheetPresentationModifier(_item: item,
                                          onDismiss: onDismiss,
                                          sheetContent: content)
        )
    }

    public func sheet<Content>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View where Content: View {
        self.modifier(
            SheetPresentationModifier(_isPresented: isPresented,
                                      onDismiss: onDismiss,
                                      sheetContent: content)
        )
    }
}

extension SheetPresentationModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
}

extension ItemSheetPresentationModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError("Implement with AG")
    }
}
