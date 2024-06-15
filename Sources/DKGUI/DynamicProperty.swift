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
    }
}

public struct _DynamicPropertyBuffer {
}

extension View {
    static var _hasDynamicProperty: Bool {
        let nonExist = _forEachField(of: Self.self) { _, _, fieldType in
            if fieldType is DynamicProperty.Type {
                return false
            }
            return true
        }
        return nonExist == false
    }
}
