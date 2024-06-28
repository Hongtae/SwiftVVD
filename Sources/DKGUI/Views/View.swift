//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Self.Body { get }

    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs
}

extension View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        let body = Self.Body._makeView(view: view[\.body], inputs: inputs)
        let generator = GenericViewContext<Self>.Generator(view: view,
                                                           body: body.view,
                                                           baseInputs: inputs.base,
                                                           preferences: inputs.preferences,
                                                           traits: inputs.traits)
        return _ViewOutputs(view: generator, preferences: PreferenceOutputs(preferences: []))
    }

    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        let body: any ViewGenerator
        if Self.Body.self is _PrimitiveView.Type {
            let inputs = _ViewInputs(base: inputs.base,
                                     preferences: inputs.preferences,
                                     traits: inputs.traits)
            body = Self.Body._makeView(view: view[\.body], inputs: inputs).view
        } else {
            body = Self.Body._makeViewList(view: view[\.body], inputs: inputs).view
        }
        let generator = GenericViewContext<Self>.Generator(view: view,
                                                           body: body,
                                                           baseInputs: inputs.base,
                                                           preferences: inputs.preferences,
                                                           traits: inputs.traits)
        return _ViewListOutputs(view: generator, preferences: PreferenceOutputs(preferences: []))
    }
}

extension View where Body == Never {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError("\(Self.self) may not have Body == Never")
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

// _PrimitiveView is a View type that does not have a body. (body = Never)
protocol _PrimitiveView {
}

extension _PrimitiveView {
    public var body: Never {
        fatalError("\(Self.self) may not have Body == Never")
    }
}

extension Never: View {
}

extension Optional: View where Wrapped: View {
    public typealias Body = Never
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Wrapped._makeView(view: view[\.unsafelyUnwrapped], inputs: inputs)
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Wrapped._makeViewList(view: view[\.unsafelyUnwrapped], inputs: inputs)
    }
}

extension Optional: _PrimitiveView where Self: View {
}

//MARK: - View with ID
struct IDView<Content, ID>: View where Content: View, ID: Hashable {
    var content: Content
    var id: ID

    init(_ content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    typealias Body = Never
    var body: Never { neverBody() }
}

extension View {
    public func id<ID>(_ id: ID) -> some View where ID : Hashable {
        IDView(self, id: id)
    }
}

extension IDView {
    static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        Content._makeView(view: view[\.content], inputs: inputs)
    }
    static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        Content._makeViewList(view: view[\.content], inputs: inputs)
    }
}
