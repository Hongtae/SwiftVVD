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

    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        makeDynamicView(metadata: (), view: view, inputs: inputs)
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        makeDynamicViewList(metadata: (), view: view, inputs: inputs)
    }

    public typealias Body = Never
}

extension AnyView {
    var _view: any View { storage.view }
}

extension AnyView: PrimitiveView {
}

extension AnyView: CustomDebugStringConvertible {
    public var debugDescription: String {
        "AnyView(\(String(reflecting: storage.view)))"
    }
}

@available(*, unavailable)
extension AnyView: Sendable {
}

extension AnyView: DynamicView {
    typealias Metadata = Void
    typealias ID = UniqueID

    static var canTransition: Bool { false }

    func childInfo(metadata: Void) -> (type: Any.Type, id: UniqueID?) {
        (type(of: _view), nil)
    }

    func makeChildView(
        metadata: Void,
        view: Attribute<AnyView>,
        inputs: _ViewInputs
    ) -> _ViewOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("AnyView.makeChildView called outside an active _AGGraph context.")
        }
        let concrete = view.value._view
        func make<V: View>(_: V) -> _ViewOutputs {
            let attribute: Attribute<V> = graph.makeRule {
                view.value._view as! V
            }
            return V._makeView(view: _GraphValue(_attribute: attribute), inputs: inputs)
        }
        return make(concrete)
    }

    func makeChildViewList(
        metadata: Void,
        view: Attribute<AnyView>,
        inputs: _ViewListInputs
    ) -> _ViewListOutputs {
        guard let graph = _AGGraph.current else {
            fatalError("AnyView.makeChildViewList called outside an active _AGGraph context.")
        }
        let concrete = view.value._view
        func make<V: View>(_: V) -> _ViewListOutputs {
            let attribute: Attribute<V> = graph.makeRule {
                view.value._view as! V
            }
            return V._makeViewList(
                view: _GraphValue(_attribute: attribute),
                inputs: inputs
            )
        }
        return make(concrete)
    }
}
