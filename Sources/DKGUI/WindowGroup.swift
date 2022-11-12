//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

public struct SceneViewContent<Content>: Scene where Content: View {
    public typealias Body = Never
    public var body: Never { fatalError() }
    init(@ViewBuilder content: ()-> Content) {
        self.content = content()
    }

    func makeView() -> some View {
        content
    }

    let content: Content
}

public struct WindowGroup<Content>: Scene where Content: View {

    public var body: some Scene {
        self.content
    }

    public init(@ViewBuilder content: ()-> Content) {
        self.content = .init(content: content)
    }

    let content: SceneViewContent<Content>
}
