//
//  File: TupleView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct TupleView<T>: View {
    public var value: T
    public typealias Body = Never

    public init(_ value: T) {
        self.value = value
    }

    public var body: Never { neverBody() }
}
