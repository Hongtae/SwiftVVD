//
//  File: TransitionTrait.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
struct TransitionTraitKey : _ViewTraitKey {
    @inlinable static var defaultValue: AnyTransition {
        .opacity
    }
    @usableFromInline
    typealias Value = AnyTransition
}

@usableFromInline
struct CanTransitionTraitKey : _ViewTraitKey {
    @inlinable static var defaultValue: Bool {
        false
    }
    @usableFromInline
    typealias Value = Bool
}

extension View {
    @inlinable public func transition(_ t: AnyTransition) -> some View {
        return _trait(TransitionTraitKey.self, t)
    }
}
