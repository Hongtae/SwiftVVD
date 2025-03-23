//
//  File: SceneBuilder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

@resultBuilder
public struct SceneBuilder {
    public static func buildExpression<Content>(_ content: Content) -> Content where Content : Scene {
        content
    }

    public static func buildBlock<Content>(_ content: Content) -> Content where Content: Scene {
        content
    }

    public static func buildBlock<each Content>(_ content: repeat each Content) -> some Scene where repeat each Content: Scene {
        _TupleScene((repeat each content))
    }
}
