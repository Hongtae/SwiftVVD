//
//  File: View.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol View {
    associatedtype Body: View
    var body: Self.Body { get }
}

protocol _PrimitiveView {
    func makeViewProxy() -> any ViewProxy
}

extension _PrimitiveView {
    public typealias Body = Never
    public var body: Never { neverBody() }
}

extension _PrimitiveView {
    func makeViewProxy() -> any ViewProxy {
        fatalError("Not implemented")
    }
}
