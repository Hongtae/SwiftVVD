//
//  File: TagValueTrait.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

@usableFromInline
struct TagValueTraitKey<V>: _ViewTraitKey where V: Hashable {
    @usableFromInline
    enum Value {
        case untagged
        case tagged(V)
    }

    @inlinable static var defaultValue: TagValueTraitKey<V>.Value {
        .untagged
    }
}

@usableFromInline
struct IsAuxiliaryContentTraitKey: _ViewTraitKey {
    @inlinable static var defaultValue: Bool {
        false
    }

    @usableFromInline
    typealias Value = Bool
}

extension View {
    @inlinable public func tag<V>(_ tag: V) -> some View where V: Hashable {
        return _trait(TagValueTraitKey<V>.self, .tagged(tag))
    }

    @inlinable public func _untagged() -> some View {
        return _trait(IsAuxiliaryContentTraitKey.self, true)
    }
}
