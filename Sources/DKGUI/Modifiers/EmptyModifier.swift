//
//  File: EmptyModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct EmptyModifier: ViewModifier {
    public typealias Body = Never

    public static let identity: EmptyModifier = .init()
}
