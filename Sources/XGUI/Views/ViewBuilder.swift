//
//  File: ViewBuilder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

@resultBuilder
public struct ViewBuilder {

    public static func buildBlock() -> EmptyView {
        EmptyView()
    }

    public static func buildBlock<Content>(_ content: Content) -> Content where Content: View {
        content
    }

    public static func buildIf<Content>(_ content: Content?) -> Content? where Content: View {
        content
    }

    public static func buildEither<TrueContent, FalseContent>(first: TrueContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View {
        .init(storage: .trueContent(first))
    }

    public static func buildEither<TrueContent, FalseContent>(second: FalseContent) -> _ConditionalContent<TrueContent, FalseContent> where TrueContent: View, FalseContent: View {
        .init(storage: .falseContent(second))
    }

    public static func buildLimitedAvailability<Content>(_ content: Content) -> AnyView where Content: View {
        AnyView(content)
    }

    public static func buildBlock<each Content>(_ content: repeat each Content) -> TupleView<(repeat each Content)> where repeat each Content: View {
        TupleView((repeat each content))
    }
}
