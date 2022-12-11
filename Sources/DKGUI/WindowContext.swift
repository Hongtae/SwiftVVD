//
//  File: WindowContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import DKGame
import Foundation

class WindowContext<Content>: WindowProxy, Scene, _PrimitiveScene, WindowDelegate where Content: View {

    let contextType: Any.Type
    let identifier: String
    let title: String

    var swapChain: SwapChain?
    var window: Window?
    var view: Content
    var viewProxy: any ViewProxy

    init(content: Content, contextType: Any.Type, identifier: String, title: String) {
        self.contextType = contextType
        self.identifier = identifier
        self.title = title
        self.view = content

        let viewInputs = _ViewInputs(modifiers: [])
        let a = Content._makeView(view: _GraphValue(value: self.view), inputs: viewInputs)
        self.viewProxy = _makeViewProxy(self.view, inputs: viewInputs)
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

            DispatchQueue.main.async {
                appContext?.checkWindowActivities()
            }
        }
    }
}
