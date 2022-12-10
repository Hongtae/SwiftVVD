//
//  File: EmptyModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct EmptyModifier : ViewModifier {

    public static let identity: EmptyModifier = .init()

    public typealias Body = Never

    public func body(content: EmptyModifier.Content) -> EmptyModifier.Body { neverBody() }
}
