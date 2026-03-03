//
//  File: ViewList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Represents a dynamically-resolved list of views.
/// Used by ForEach and any view that produces a variable number of children at runtime.
/// The AG rule stored in `Attribute<ViewList>` is responsible for diffing items
/// and managing per-item Subgraph lifecycles.
///
/// `generators` holds one `TypedUnaryViewGenerator` per currently-active element, in order.
/// Layout reads this via `Attribute<ViewList>.value.generators`, the same way
/// it reads `ViewListElements.unary(gen)` for the static case.
struct ViewList {
    var generators: [TypedUnaryViewGenerator]

    init(generators: [TypedUnaryViewGenerator] = []) {
        self.generators = generators
    }
}

/// Data carried alongside a `_ViewLayoutModifier` entry in the `modified` case of
/// `ViewListElements`.
/// `{ base: ViewListElements, modifier: AGWeakAttribute, modifierType: any _ViewLayoutModifier.Type, baseInputs: _GraphInputs }`.
struct _ViewListLayoutModifier {
    var modifier: AGWeakAttribute
    var modifierType: any _ViewLayoutModifier.Type
    var baseInputs: _GraphInputs
}

/// Discriminated union representing the structure of a fully-static view list.
///
/// - `unary(TypedUnaryViewGenerator)`: a single leaf primitive view.
/// - `merged([_ViewListOutputs])`: multiple children merged together (e.g. TupleView children).
/// - `modified(ViewListElements, _ViewListLayoutModifier)`: a `_ViewLayoutModifier`
///   wrapping another element group.
indirect enum ViewListElements {
    case unary(TypedUnaryViewGenerator)
    case merged([_ViewListOutputs])
    case modified(ViewListElements, _ViewListLayoutModifier)
}

/// Type-erased storage for a single trait entry in a `ViewTraitCollection`.
protocol AnyViewTrait {}

/// Typed wrapper around one `_ViewTraitKey` value, stored in `ViewTraitCollection.storage`.
struct AnyTrait<Key: _ViewTraitKey>: AnyViewTrait {
    var value: Key.Value
}

/// Per-view trait values propagated from child views up to their container.
/// `storage` holds one `AnyTrait<K>` per distinct key that was written.
struct ViewTraitCollection {
    var storage: [AnyViewTrait] = []

    init() {}

    subscript<K: _ViewTraitKey>(key: K.Type) -> K.Value {
        get {
            for item in storage {
                if let typed = item as? AnyTrait<K> { return typed.value }
            }
            return K.defaultValue
        }
        set {
            for i in 0..<storage.count {
                if storage[i] is AnyTrait<K> {
                    storage[i] = AnyTrait<K>(value: newValue)
                    return
                }
            }
            storage.append(AnyTrait<K>(value: newValue))
        }
    }
}

/// The set of trait keys a view list is tracking.
struct ViewTraitKeys {
    var types: Set<ObjectIdentifier> = []
    var isDataDependent: Bool = false
}

/// Scroll content offset for ScrollView-embedded lists.
/// Stub — full implementation requires ScrollView system.
struct ViewContentOffset {}

/// Internal modifier applied to items in a `_ViewListOutputs.Views.dynamicList`.
/// Always `nil` in VUI — type body not implemented.
struct ListModifier {
}

/// The discriminated-union content of a `_ViewListOutputs`.
/// - `staticList`: all children are statically known at `_makeViewList` time
///   (e.g., a TupleView with no ForEach).
/// - `dynamicList`: at least one child is dynamically determined at runtime
///   (e.g., ForEach, or a view containing ForEach).
///   `ListModifier?` is always `nil` in VUI.
enum ViewListContent {
    case staticList(ViewListElements)
    case dynamicList(Attribute<ViewList>, ListModifier?)
}
