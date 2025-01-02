//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private var defaultWindowTitle: Text { Text("XGUI.WindowGroup") }

public struct WindowGroup<Content>: Scene where Content: View {

    let content: ()->Content
    let contextType: Any.Type
    let title: Text
    let identifier: String

    public var body: some Scene {
        WindowContext<Content>(content: self.content,
                               contextType: self.contextType,
                               identifier: self.identifier,
                               title: self.title)
    }

    public init(@ViewBuilder makeContent: @escaping () -> Content) {
        self.content = makeContent
        self.contextType = Never.self
        self.title = defaultWindowTitle
        self.identifier = ""
    }

    public init(id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.content = makeContent
        self.contextType = Never.self
        self.title = defaultWindowTitle
        self.identifier = id
    }

    public init(_ title: Text, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = title
        self.content = makeContent
        self.contextType = Never.self
        self.identifier = ""
    }

    public init(_ title: Text, id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = title
        self.identifier = id
        self.content = makeContent
        self.contextType = Never.self
    }
}

extension WindowGroup {
    public init(_ title: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = Text(title)
        self.identifier = ""
        self.content = makeContent
        self.contextType = Never.self
    }

    public init(_ title: String, id: String, @ViewBuilder makeContent: @escaping () -> Content) {
        self.title = Text(title)
        self.identifier = id
        self.content = makeContent
        self.contextType = Never.self
    }
}
