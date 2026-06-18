//
//  File: Entity.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public protocol Entity {
    associatedtype Body: Entity
    @EntityBuilder var body: Self.Body { get }
}

extension Never: Entity {
}

protocol _PrimitiveEntity: Entity {
}

extension _PrimitiveEntity {
    public var body: Never {
        neverEntityBody()
    }
}
