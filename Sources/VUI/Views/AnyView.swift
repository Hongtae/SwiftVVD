//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

class AnyViewBox {
    let view: any View
    init(_ view: any View) {
        self.view = view
    }
}

private struct AnyViewContainer: StatefulRule {
    typealias Value = _ViewOutputs

    var view: Attribute<AnyView>
    var inputs: _ViewInputs
    var placeholders: _ViewOutputs
    var typeID: ObjectIdentifier?
    var subgraph: AGSubgraph?

    mutating func updateValue() {
        guard let graph = _AGGraph.current else {
            fatalError("AnyViewContainer.updateValue evaluated outside an active _AGGraph context.")
        }

        let currentView = view.value._view
        let currentTypeID = ObjectIdentifier(type(of: currentView))

        if typeID != currentTypeID {
            eraseCurrentSubgraph()
            typeID = currentTypeID

            let subgraph = AGSubgraph()
            self.subgraph = subgraph
            let viewAttr = view
            let childInputs = inputs

            func makeConcreteView<V: View>(_: V) -> _ViewOutputs {
                AGSubgraph.$current.withValue(subgraph) {
                    let concreteAttr: Attribute<V> = graph.makeRule {
                        viewAttr.value._view as! V
                    }
                    return makeView(view: _GraphValue(_attribute: concreteAttr), inputs: childInputs)
                }
            }

            let concrete = makeConcreteView(currentView)
            AGSubgraph.$current.withValue(subgraph) {
                concrete.attachIndirectOutputs(to: placeholders)
            }
        }

        _AGGraph.setStatefulOutput(placeholders)
    }

    private mutating func eraseCurrentSubgraph() {
        guard let subgraph else { return }
        placeholders.detachIndirectOutputs()
        subgraph.invalidate()
        subgraph.removeFromParent()
        self.subgraph = nil
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
    /// AnyView must return placeholder `_ViewOutputs`, not just a layout slot,
    /// so DisplayList and other requested preference keys relay through type
    /// erasure. The concrete child outputs are attached when the stateful rule
    /// opens the wrapped existential.
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("\(self)._makeView called outside an active _AGGraph context.")
        }

        let placeholders = inputs.makeIndirectOutputs()
        let containerAttr: Attribute<AnyViewContainer.Value> = graph.makeStatefulRule(
            AnyViewContainer(view: view._attribute, inputs: inputs, placeholders: placeholders)
        )
        placeholders.setIndirectDependency(containerAttr.identifier)
        _ = graph.makeSideEffectRule {
            _ = containerAttr.value
            return ()
        }
        return placeholders
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        _ViewListOutputs.unaryViewList(view: view, inputs: inputs)
    }

    public typealias Body = Never
}

extension AnyView {
    var _view: any View { storage.view }
}

extension AnyView: _PrimitiveView {
}
