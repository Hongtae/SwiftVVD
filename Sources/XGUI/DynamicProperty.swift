//
//  File: DynamicProperty.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public protocol DynamicProperty {
    static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs)
    mutating func update()
}

extension DynamicProperty {
    public static func _makeProperty<V>(in buffer: inout _DynamicPropertyBuffer, container: _GraphValue<V>, fieldOffset: Int, inputs: inout _GraphInputs) {
        func make<T: DynamicProperty>(_ type: T.Type, offset: Int) {
            T._makeProperty(in: &buffer, container: container, fieldOffset: offset, inputs: &inputs)
        }
        _forEachField(of: self) { charPtr, offset, fieldType in
            if let propType = fieldType as? any DynamicProperty.Type {
                make(propType, offset: fieldOffset + offset)
            }
            return true
        }
        buffer.properties.append(.init(type: self, offset: fieldOffset))
    }

    public mutating func update() {
    }
}

public struct _DynamicPropertyBuffer {
    struct FieldInfo {
        let type: DynamicProperty.Type
        let offset: Int
    }
    var properties: [FieldInfo] = []
    var contexts: [Int: AnyObject] = [:]
}

func _hasDynamicProperty<V : View>(_ view: V.Type) -> Bool {
    let nonExist = _forEachField(of: view) { _, _, fieldType in
        if fieldType is DynamicProperty.Type {
            return false
        }
        return true
    }
    return nonExist == false
}

func _unsafeCastDynamicProperty<V : View, T : DynamicProperty>(to propertyType: T.Type, at offset: Int, from view: V) -> any DynamicProperty {
    var property: (any DynamicProperty)?
    withUnsafeBytes(of: view) {
        let ptr = $0.baseAddress!.advanced(by: offset)
        property = ptr.assumingMemoryBound(to: propertyType).pointee
    }
    if let property { return property }
    fatalError("Unable to find dynamic property at offset: \(offset)")
}

func _getDynamicProperty<V : View>(at offset: Int, from view: V) -> any DynamicProperty {
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

protocol _DynamicPropertyStorageBinding: DynamicProperty {
    typealias Tracker = ()->Void

    mutating func bind(in buffer: inout _DynamicPropertyBuffer, fieldOffset: Int, view: ViewContext, tracker: @escaping Tracker)
}

struct _DynamicPropertyDataStorage<Container> {
    var dynamicPropertyBuffer: _DynamicPropertyBuffer
    typealias Tracker = _DynamicPropertyStorageBinding.Tracker
    var tracker: Tracker

    init(graph: _GraphValue<Container>, inputs: inout _GraphInputs) {
        var dynamicPropertyBuffer = _DynamicPropertyBuffer()
        _forEachField(of: Container.self) { charPtr, offset, fieldType in
            if let propertyType = fieldType as? DynamicProperty.Type {
                func make<T: DynamicProperty>(_ type: T.Type, offset: Int) {
                    T._makeProperty(in: &dynamicPropertyBuffer,
                                    container: graph,
                                    fieldOffset: offset,
                                    inputs: &inputs)
                }
                make(propertyType, offset: offset)
            }
            return true
        }
        self.dynamicPropertyBuffer = dynamicPropertyBuffer
        self.tracker = {}
    }

    mutating func bind(container: inout Container, view: ViewContext) {
        // bind properties.
        func bind<T: _DynamicPropertyStorageBinding>(_ type: T.Type, _ offset: Int, _ ptr: UnsafeMutableRawPointer) {
            ptr.assumingMemoryBound(to: T.self).pointee.bind(in: &self.dynamicPropertyBuffer,
                                                             fieldOffset: offset,
                                                             view: view,
                                                             tracker: tracker)
        }
        self.dynamicPropertyBuffer.properties.forEach {
            let offset = $0.offset
            let propertyType = $0.type
            if let dpType = propertyType as? _DynamicPropertyStorageBinding.Type {
                withUnsafeMutableBytes(of: &container) {
                    let ptr = $0.baseAddress!.advanced(by: offset)
                    bind(dpType, offset, ptr)
                }
            }
        }
    }

    func update(container: inout Container) {
        // update DynamicProperty properties.
        func update<T: DynamicProperty>(_: T.Type, _ ptr: UnsafeMutableRawPointer) {
            ptr.assumingMemoryBound(to: T.self).pointee.update()
        }
        self.dynamicPropertyBuffer.properties.forEach {
            let offset = $0.offset
            let propertyType = $0.type
            withUnsafeMutableBytes(of: &container) {
                let ptr = $0.baseAddress!.advanced(by: offset)
                update(propertyType, ptr)
            }
        }
    }
}
