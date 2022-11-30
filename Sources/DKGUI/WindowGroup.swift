//
//  File: WindowGroup.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame
import Foundation

class WindowGroupContext<Content>: WindowProxy, PrimitiveScene, Scene, WindowDelegate where Content: View {

    var content: Content
    let contextType: Any.Type
    let identifier: String
    let title: String

    var window: Window?
    var screen: Screen?
    var frame: Frame?

    var view: Content { content }

    init(content: Content, contextType: Any.Type, identifier: String, title: String) {
        self.content = content
        self.contextType = contextType
        self.identifier = identifier
        self.title = title
    }

    @MainActor 
    func makeWindow() -> Window? {
        if self.window == nil {
            self.window = DKGame.makeWindow(name: self.title,
                                            style: [.genericWindow],
                                            delegate: self)

            self.window?.addEventObserver(self) {
                [weak self](event: WindowEvent) in
                if let self = self {
                    self.onWindowEvent(event: event)
                }
            }

            Task { @ScreenActor in
                self.frame = ViewFrame()
                self.screen = Screen()
                self.screen?.frame = self.frame
                self.screen?.window = self.window
            }
        }
        return self.window
    }

    func makeSceneProxy() -> any SceneProxy {
        SceneContext(scene: self, window: self)
    }

    @MainActor
    func onWindowEvent(event: WindowEvent) {
        if event.type == .closed {
            self.window?.removeEventObserver(self)
            self.window = nil
            self.screen = nil
            self.frame = nil

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DKGUIAppWindowClosedNotification, object: nil)
            }
        }
    }
}

private let defaultWindowTitle = "DKGUI.WindowGroup"

public struct WindowGroup<Content>: Scene where Content: View {

    let content: Content
    let contextType: Any.Type
    let title: String
    let identifier: String

    public var body: some Scene {
        WindowGroupContext<Content>(content: self.content,
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
