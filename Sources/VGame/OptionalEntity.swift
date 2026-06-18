//
//  File: OptionalEntity.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

extension Optional: Entity where Wrapped: Entity {
    public typealias Body = Never
}

extension Optional: _PrimitiveEntity where Wrapped: Entity {
}
