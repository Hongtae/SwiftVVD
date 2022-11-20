//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

struct WindowGroupViewContent<Content>: PrimitiveScene where Content: View {

    let content: Content

    init(@ViewBuilder content: ()-> Content) {
        self.content = content()
    }

    func makeView() -> some View {
        content
    }

    func makeSceneProxies() -> [SceneProxy] {
        return []
    }
}

public struct WindowGroup<Content>: Scene where Content: View {

    public var body: some Scene {
        self.content
    }

    public init(@ViewBuilder content: ()-> Content) {
        self.content = .init(content: content)
    }

    let content: WindowGroupViewContent<Content>
}
