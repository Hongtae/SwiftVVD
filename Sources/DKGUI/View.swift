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

func nobody(_ s: String = "") -> Never {
    fatalError(s)
}

extension Never: Scene, View {
    public typealias Body = Never
    public var body: Never { nobody() }
}
