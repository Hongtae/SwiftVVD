//
//  File: SheetPresentationModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

private protocol _SheetModifier: ViewModifier {
    var onDismiss: (() -> Void)? { get }
}

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

extension SheetPresentationModifier: _SheetModifier {}
extension ItemSheetPresentationModifier: _SheetModifier {}

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
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                SheetPresentationViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: .init(view))
        }
        return outputs
    }
}

extension ItemSheetPresentationModifier: _UnaryViewModifier {
    static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        let outputs = body(_Graph(), inputs)
        if let body = outputs.view?.makeView() {
            let view = UnaryViewGenerator(graph: modifier, baseInputs: inputs.base) { graph, inputs in
                ItemSheetPresentationViewContext(graph: graph, body: body, inputs: inputs)
            }
            return _ViewOutputs(view: .init(view))
        }
        return outputs
    }
}

private class SheetModifierViewContext<SheetModifier>: ViewModifierContext<SheetModifier> where SheetModifier: _SheetModifier {
    override init(graph: _GraphValue<SheetModifier>, body: ViewContext, inputs: _GraphInputs) {
        super.init(graph: graph, body: body, inputs: inputs)

    }
}

private class SheetPresentationViewContext<Content>: SheetModifierViewContext<SheetPresentationModifier<Content>> where Content: View {
    override init(graph: _GraphValue<SheetPresentationModifier<Content>>, body: ViewContext, inputs: _GraphInputs) {
        super.init(graph: graph, body: body, inputs: inputs)
    }
}

private class ItemSheetPresentationViewContext<Item, Content>: SheetModifierViewContext<ItemSheetPresentationModifier<Item, Content>> where Item: Identifiable, Content: View {
    override init(graph: _GraphValue<ItemSheetPresentationModifier<Item, Content>>, body: ViewContext, inputs: _GraphInputs) {
        super.init(graph: graph, body: body, inputs: inputs)

    }
}