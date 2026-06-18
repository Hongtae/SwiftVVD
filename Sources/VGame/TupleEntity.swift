//
//  File: TupleEntity.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct TupleEntity<Content>: Entity {
    public init(_ content: Content) {
    }

    public typealias Body = Never
}

extension TupleEntity: _PrimitiveEntity {
}
