//
//  File: EnvironmentalModifier.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public protocol EnvironmentalModifier: ViewModifier where Self.Body == Never {
    associatedtype ResolvedModifier: ViewModifier
    func resolve(in: EnvironmentValues) -> Self.ResolvedModifier
}
