//
//  File: EntityBuilder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

@resultBuilder
public struct EntityBuilder {
    public static func buildBlock() -> EmptyEntity {
        EmptyEntity()
    }

    public static func buildBlock<Content>(_ content: Content) -> Content where Content: Entity {
        content
    }

    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: Entity {
        content
    }

    public static func buildEither<TrueContent, FalseContent>(
        first: TrueContent
    ) -> ConditionalEntity<TrueContent, FalseContent> where TrueContent: Entity, FalseContent: Entity {
        ConditionalEntity(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent, FalseContent>(
        second: FalseContent
    ) -> ConditionalEntity<TrueContent, FalseContent> where TrueContent: Entity, FalseContent: Entity {
        ConditionalEntity(storage: .falseContent(second))
    }

    public static func buildBlock<each Content>(
        _ content: repeat each Content
    ) -> TupleEntity<(repeat each Content)> where repeat each Content: Entity {
        TupleEntity((repeat each content))
    }
}
