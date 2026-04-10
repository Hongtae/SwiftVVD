//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// File-scope state class. It cannot be nested inside a generic function in Swift.
private final class _AnyViewBranchState {
    var typeID: ObjectIdentifier? = nil
    var subgraph: AGSubgraph? = nil
    var lcAttr: Attribute<LayoutComputer>? = nil
}

class AnyViewBox {
    let view: any View
    init(_ view: any View) {
        self.view = view
    }
}

public struct AnyView: View {
    var storage: AnyViewBox

    public init<V>(_ view: V) where V: View {
        if let view = view as? AnyView {
            self.storage = view.storage
        } else {
            self.storage = AnyViewBox(view)
        }
    }

    public init<V>(erasing view: V) where V: View {
        self.init(view)
    }

    public init?(_fromValue value: Any) {
        guard let view = value as? any View else {
            return nil
        }
        if let view = value as? AnyView {
            self.storage = view.storage
        } else {
            self.storage = AnyViewBox(view)
        }
    }

    /// Dynamic-subgraph implementation with type-erased dispatch.
    ///
    /// A master LayoutComputer rule watches the wrapped view's concrete type.
    /// When the type changes (e.g. an `if/else` that switches between `AnyView`s
    /// wrapping different concrete types):
    ///   1. The old AGSubgraph is invalidated.
    ///   2. A fresh AGSubgraph is created.
    ///   3. The new type's `_makeView` is dispatched via a generic helper that
    ///      opens the `any View` existential (SE-0352, Swift 5.7+).
    ///
    /// When only the wrapped *value* changes but the type is the same, the master
    /// rule delegates to the existing subgraph's LC, which re-evaluates naturally
    /// via its own dependency on the type-extraction rule node.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("\(self)._makeView called outside an active AttributeGraph context.")
        }

        let state = _AnyViewBranchState()
        state.subgraph = AGSubgraph() // Created while parent AGSubgraph is active

        let masterLC: Attribute<LayoutComputer> = graph.makeRule {
            // Retrieve the active graph from TaskLocal to avoid a retain cycle
            guard let graph = AttributeGraph.current else {
                fatalError("AnyView rule evaluated outside an active AttributeGraph context.")
            }

            // Reading ._view registers a dependency on view._attribute.
            let currentView = view._attribute.value._view
            let typeID = ObjectIdentifier(type(of: currentView))

            if state.typeID != typeID {
                // --- Wrapped view type changed ---
                // Invalidate clears old nodes/children but keeps this subgraph attached to its parent
                state.subgraph?.invalidate()
                state.typeID = typeID

                func _makeView<V: View>(_: V) -> _ViewOutputs {
                    AGSubgraph.$current.withValue(state.subgraph) {
                        let vAttr: Attribute<V> = graph.makeRule {
                            view._attribute.value._view as! V
                        }
                        return makeView(view: _GraphValue(_attribute: vAttr), inputs: inputs)
                    }
                }
                let outputs = _makeView(currentView)
                state.lcAttr = outputs._layoutComputer.attribute
            }

            return state.lcAttr?.value ?? LayoutComputer.fixed(.zero)
        }

        return _ViewOutputs(preferences: PreferencesOutputs(),
                            layoutComputer: OptionalAttribute(masterLC))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs(
            views: .staticList(.unary(TypedUnaryViewGenerator(view, inputs: inputs))),
            nextImplicitID: 1,
            staticCount: 1
        )
    }

    public typealias Body = Never
}

extension AnyView {
    var _view: any View { storage.view }
}

extension AnyView: _PrimitiveView {
}
