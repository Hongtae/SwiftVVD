//
//  File: DynamicProperty.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public protocol DynamicProperty {
    static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs)
    mutating func update()
}

extension DynamicProperty {
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs) {
        fatalError("This method should not be called.")
    }

    public mutating func update() {
    }
}

public struct _DynamicPropertyBuffer {
}

func _hasDynamicProperty<V: View>(_ view: V.Type) -> Bool {
    let nonExist = _forEachField(of: view) { _, _, fieldType in
        if fieldType is DynamicProperty.Type {
            return false
        }
        return true
    }
    return nonExist == false
}

struct _DynamicPropertyTypeOffset {
    let name: String
    let type: DynamicProperty.Type
    let offset: Int
}

func _getDynamicPropertyOffsets<V: View>(from view: V.Type) -> [_DynamicPropertyTypeOffset] {
    var properties: [_DynamicPropertyTypeOffset] = []
    _forEachField(of: V.self) { charPtr, offset, fieldType in
        if let propertyType = fieldType as? DynamicProperty.Type {
            let name = String(cString: charPtr)
            properties.append(.init(name: name, type: propertyType, offset: offset))
        }
        return true
    }
    return properties
}

func _getDynamicProperty<V: View>(at offset: Int, from view: V) -> any DynamicProperty {
    func restore<T: DynamicProperty>(_ ptr: UnsafeRawPointer, _: T.Type) -> T {
        ptr.assumingMemoryBound(to: T.self).pointee
    }
    var property: (any DynamicProperty)?
    _forEachField(of: V.self) { charPtr, position, fieldType in
        if let propertyType = fieldType as? DynamicProperty.Type {
            if offset == position {
                withUnsafeBytes(of: view) {
                    let ptr = $0.baseAddress!.advanced(by: offset)
                    property = restore(ptr, propertyType)
                }
            }
        }
        return position < offset
    }
    if let property { return property }
    fatalError("Unable to find dynamic property at offset: \(offset)")
}
