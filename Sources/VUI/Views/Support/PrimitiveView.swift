//
//  File: PrimitiveView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

protocol PrimitiveView: View where Body == Never {
}

extension PrimitiveView {
    public var body: Never {
        fatalError("body() should not be called on \(Self.self).")
    }
}
