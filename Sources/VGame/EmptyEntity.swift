//
//  File: EmptyEntity.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct EmptyEntity: Entity {
    public init() {
    }

    public typealias Body = Never
}

extension EmptyEntity: _PrimitiveEntity {
}
