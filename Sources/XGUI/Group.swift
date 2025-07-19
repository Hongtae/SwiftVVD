//
//  File: Group.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

public struct Group<Content> {
    public typealias Body = Never
    
    @usableFromInline
    var content: Content
    
    @inlinable public init(_content: Content) {
        self.content = _content
    }
}
