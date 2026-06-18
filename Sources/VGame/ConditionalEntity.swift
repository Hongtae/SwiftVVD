//
//  File: ConditionalEntity.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

public struct ConditionalEntity<TrueContent, FalseContent>: Entity where TrueContent: Entity, FalseContent: Entity {
    public enum Storage {
        case trueContent(TrueContent)
        case falseContent(FalseContent)
    }

    public init(storage: Storage) {
    }

    public typealias Body = Never
}

extension ConditionalEntity: _PrimitiveEntity {
}
