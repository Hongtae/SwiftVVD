//
//  File: Never.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

func neverBody(_ s: String = "") -> Never{
    fatalError(s)
}

extension Never: Scene, View {
    public typealias Body = Never
    public var body: Never { neverBody() }
}
