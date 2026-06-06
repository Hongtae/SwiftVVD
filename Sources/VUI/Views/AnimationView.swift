//
//  File: AnimationView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _AnimationView<Content>: View where Content: Equatable, Content: View {
    public var content: Content
    public var animation: Animation?

    @inlinable public init(content: Content, animation: Animation?) {
        self.content = content
        self.animation = animation
    }

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }
        let contentAttr: Attribute<Content> = graph.makeStatefulRule(
            AnimationViewContentRule(view: view._attribute)
        )
        let parentTransAttr = inputs.base.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeStatefulRule(
            AnimationViewTransactionRule(
                view: view._attribute,
                parent: parentTransAttr
            )
        )
        var modifiedInputs = inputs
        modifiedInputs.base.transaction = newTransAttr
        return Content._makeView(view: _GraphValue(_attribute: contentAttr), inputs: modifiedInputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeViewList called outside an active AttributeGraph context.")
        }
        let contentAttr: Attribute<Content> = graph.makeStatefulRule(
            AnimationViewContentRule(view: view._attribute)
        )
        let parentTransAttr = inputs.base.transaction
        let newTransAttr: Attribute<Transaction> = graph.makeStatefulRule(
            AnimationViewTransactionRule(
                view: view._attribute,
                parent: parentTransAttr
            )
        )
        var modifiedInputs = inputs
        modifiedInputs.base.transaction = newTransAttr
        return Content._makeViewList(view: _GraphValue(_attribute: contentAttr), inputs: modifiedInputs)
    }

    public typealias Body = Never
}

extension _AnimationView: _PrimitiveView {
}

private struct AnimationViewContentRule<Content: View & Equatable>: StatefulRule {
    typealias Value = Content

    var view: Attribute<_AnimationView<Content>>
    var previousContent: Content?

    mutating func updateValue() {
        let content = view.value.content
        if let previousContent,
           previousContent == content {
            return
        }
        previousContent = content
        AttributeGraph.setStatefulOutput(content)
    }
}

private struct AnimationViewTransactionRule<Content: View & Equatable>: StatefulRule {
    typealias Value = Transaction

    var view: Attribute<_AnimationView<Content>>
    var parent: Attribute<Transaction>
    var previousContent: Content?

    mutating func updateValue() {
        let viewValue = view.value
        var transaction = parent.value
        if let previousContent,
           previousContent != viewValue.content,
           !transaction.disablesAnimations {
            if viewValue.animation == nil {
                enqueueNoRegisteredAnimationFallback(transaction.animationCompletionObserver)
            }
            transaction.animation = viewValue.animation
        }
        previousContent = viewValue.content
        AttributeGraph.setStatefulOutput(transaction)
    }
}
