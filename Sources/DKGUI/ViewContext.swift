//
//  File: ViewContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame

struct ViewInputs {
//    var states: [String: String] = [:]
//    var stateObjects: [String: String] = [:]
}

struct ViewOutputs {
//    var bindings: [String] = []
}

struct ViewListInputs {
}

struct ViewListOutputs {
    var subviews: [any View] = []
}

extension View {
    static func _makeView(view: GraphValue<Self>, inputs: ViewInputs) -> ViewOutputs {
        ViewOutputs()
    }
    static func _makeViewList(view: GraphValue<Self>, inputs: ViewListInputs) -> ViewListOutputs {
        ViewListOutputs()
    }
}

protocol ViewProxy {
    associatedtype Content: View
    var view: Content { get }
    var subviews: [any ViewProxy] { get }
    var frame: Frame? { get }
}

struct ViewContext<Content>: ViewProxy where Content: View {
    var view: Content
    var graph: GraphValue<Content>
    var inputs: ViewInputs
    var outputs: ViewOutputs
    var subviews: [any ViewProxy]
    var frame: Frame? = nil
}
