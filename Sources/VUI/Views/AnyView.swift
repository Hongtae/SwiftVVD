//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
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
        fatalError("Implement with AG")
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("Implement with AG")
    }

    public typealias Body = Never
}

extension AnyView {
    var _view: any View { storage.view }
}

extension AnyView: _PrimitiveView {
}

