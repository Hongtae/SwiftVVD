//
//  File: ModifiedContent.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

public struct ModifiedContent<Content, Modifier> {
    public typealias Body = Never

    public var content: Content
    public var modifier: Modifier

    public init(content: Content, modifier: Modifier) {
        self.content = content
        self.modifier = modifier
    }
}

extension ModifiedContent: Equatable where Content: Equatable, Modifier: Equatable {
    public static func == (a: ModifiedContent<Content, Modifier>, b: ModifiedContent<Content, Modifier>) -> Bool {
        return a.content == b.content && a.modifier == b.modifier
    }
}
