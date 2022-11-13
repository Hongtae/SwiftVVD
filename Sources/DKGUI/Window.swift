//
//  File: Window.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

struct WindowViewContent<Content>: Scene where Content: View {

    let content: Content

    init(@ViewBuilder content: ()-> Content) {
        self.content = content()
    }

    func makeView() -> some View {
        content
    }

    public var body: Never { nobody() }
}

public struct Window<Content>: Scene where Content: View {

    public var body: some Scene {
        self.content
    }

    public init(_ title: Text, id: String, @ViewBuilder content: () -> Content) {
        self.content = .init(content: content)
    }

    let content: WindowViewContent<Content>
}
