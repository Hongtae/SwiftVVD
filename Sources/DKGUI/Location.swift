//
//  File: Location.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

protocol _Location {
    associatedtype Value
    func getValue() -> Value
    func setValue(_: Value, transaction: Transaction)
}

@usableFromInline
class AnyLocationBase {
    init() {}
}

@usableFromInline
class AnyLocation<Value> : AnyLocationBase {

    override init() {
    }

    func getValue() -> Value {
        fatalError()
    }

    func setValue(_: Value, transaction: Transaction) {
        fatalError()
    }
}
