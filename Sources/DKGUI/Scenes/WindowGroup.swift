//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private let defaultWindowTitle = "DKGUI.WindowGroup"

public struct WindowGroup<Content>: Scene where Content: View {

    let content: Content
    let contextType: Any.Type
    let title: String
    let identifier: String

    public var body: some Scene {
        WindowContext<Content>(content: self.content,
                               contextType: self.contextType,
                               identifier: self.identifier,
                               title: self.title)
    }

    public init(@ViewBuilder content: ()-> Content) {
        self.content = content()
        self.contextType = Never.self
        self.title = defaultWindowTitle
        self.identifier = ""
    }

    public init(id: String, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.contextType = Never.self
        self.title = defaultWindowTitle
        self.identifier = id
    }

    public init<S>(_ title: S, @ViewBuilder content: () -> Content) where S : StringProtocol {
        self.title = String(title)
        self.content = content()
        self.contextType = Never.self
        self.identifier = ""
    }

    public init<S>(_ title: S, id: String, @ViewBuilder content: () -> Content) where S : StringProtocol {
        self.title = String(title)
        self.content = content()
        self.contextType = Never.self
        self.identifier = id
    }
}
