//
//  File: DynamicProperty.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol DynamicProperty {
    mutating func update()
}

extension DynamicProperty {
    public mutating func update() {
        fatalError()
    }
}
