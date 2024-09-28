//
//  File: SceneBuilder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

@resultBuilder
public struct SceneBuilder {
    public static func buildBlock<Content>(_ content: Content) -> Content where Content: Scene {
        return content
    }

    public static func buildBlock<each Content>(_ content: repeat each Content) -> some Scene where repeat each Content: Scene {
        return TupleScene((repeat each content))
    }
}
