//
//  File: TransactionModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _TransactionModifier : ViewModifier, _GraphInputsModifier {
    public var transform: (inout Transaction) -> Void

    @inlinable public init(transform: @escaping (inout Transaction) -> Void) {
        self.transform = transform
    }

    public static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs) {
        fatalError()
    }

    public typealias Body = Never
}

public struct _PushPopTransactionModifier<Content> : ViewModifier where Content : ViewModifier {
    public var content: Content
    public var base: _TransactionModifier

    @inlinable public init(content: Content, transform: @escaping (inout Transaction) -> Void) {
        self.content = content
        base = .init(transform: transform)
    }

    public static func _makeView(modifier: _GraphValue<Self>, inputs: _ViewInputs, body: @escaping (_Graph, _ViewInputs) -> _ViewOutputs) -> _ViewOutputs {
        fatalError()
    }

    public typealias Body = Never
}

extension View {
    @inlinable public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some View {
        return modifier(_TransactionModifier(transform: transform))
    }
}

extension ViewModifier {
    @inlinable public func transaction(_ transform: @escaping (inout Transaction) -> Void) -> some ViewModifier {
        return _PushPopTransactionModifier(content: self, transform: transform)
    }

    @inlinable public func animation(_ animation: Animation?) -> some ViewModifier {
        return transaction { t in
            if !t.disablesAnimations {
                t.animation = animation
            }
        }
    }
}
