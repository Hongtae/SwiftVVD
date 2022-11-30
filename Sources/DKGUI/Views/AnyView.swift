//
//  File: AnyView.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct AnyView: View {
    public init<V>(_ view: V) where V: View {
    }

    public init<V>(erasing view: V) where V: View {
    }
    public var body: Never { neverBody() }
}
