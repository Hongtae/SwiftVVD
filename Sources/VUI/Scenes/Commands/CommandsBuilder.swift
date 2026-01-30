//
//  File: CommandsBuilder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

@resultBuilder
public struct CommandsBuilder {
    public static func buildExpression<Content>(_ content: Content) -> Content where Content: Commands {
        content
    }
    
    public static func buildBlock() -> EmptyCommands {
        EmptyCommands()
    }
    
    public static func buildBlock<C>(_ content: C) -> C where C: Commands {
        content
    }
}

extension CommandsBuilder {
    public static func buildIf<C>(_ content: C?) -> C? where C: Commands {
        content
    }

    public static func buildEither<T, F>(first: T) -> _ConditionalContent<T, F> where T: Commands, F: Commands {
        _ConditionalContent<T, F>(storage: .trueContent(first))
    }

    public static func buildEither<T, F>(second: F) -> _ConditionalContent<T, F> where T: Commands, F: Commands {
        _ConditionalContent<T, F>(storage: .falseContent(second))
    }
    
    public static func buildBlock<each Content>(_ content: repeat each Content) -> some Commands where repeat each Content: Commands {
        TupleCommandContent((repeat each content))
    }
}
