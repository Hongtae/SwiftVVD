//
//  File: AuxiliaryWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol AuxiliaryWindowHost {
    func addAuxiliaryWindow(_ window: some WindowContext, position: CGPoint) -> Bool
    func removeAuxiliaryWindow(_ window: some WindowContext)
}


// utility window (popup-window or layered window) scene
struct AuxiliaryWindowScene<Content>: _PrimitiveScene where Content: View {
    var content: Content

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        _SceneOutputs(scene: UnarySceneGenerator(graph: scene, inputs: inputs) { graph, inputs in
            AuxiliaryWindowSceneContext(graph: graph, inputs: inputs)
        })
    }
}

// scene context for utility window scene
class AuxiliaryWindowSceneContext<Content>: TypedSceneContext<AuxiliaryWindowScene<Content>>, @unchecked Sendable where Content: View {
    typealias Scene = AuxiliaryWindowScene<Content>
    fileprivate var window: AuxiliaryWindowContext<Content>?
    var initialContentSize: CGSize? = nil

    override init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        super.init(graph: graph, inputs: inputs)
        let window = AuxiliaryWindowContext(content: graph[\.content], scene: self)
        window.onViewLoadedCallback = { [weak self] in
            self?.onViewLoaded()
        }
        window.onViewLayoutChangedCallback = { [weak self] in
            self?.onViewLayoutChanged()
        }
        window.onWindowClosingCallback = { [weak self] in
            self?.onWindowClosed()
        }
        self.window = window
        self.initialContentSize = nil
    }

    override func updateContent() {
        super.updateContent()
        if self.content != nil {
            self.window?.updateContent()
        }
    }

    override var windows: [WindowContext] {
        [window].compactMap(\.self)
    }

    override var primaryWindows: [WindowContext] {
        [window].compactMap(\.self)
    }

    override var isValid: Bool {
        if super.isValid {
            if let window {
                return window.isValid
            }
        }
        return false
    }
    
    private func onViewLoaded() {
    }

    private func onViewLayoutChanged() {
        guard let window = self.window else {
            Log.error("AuxiliaryWindowContext: no backing window")
            return
        }
        guard let view = window.view else {
            Log.error("AuxiliaryWindowContext: Invalid view!")
            return
        }
        let viewSize = view.sizeThatFits(.unspecified)
        if let nativeWindow = window.window {
            let style = window.style

            var initialActivate = false
            if initialContentSize == nil {
                initialContentSize = viewSize
                initialActivate = true
            }

            Task { @MainActor in
                if style.contains(.autoResize) {
                    nativeWindow.contentSize = viewSize
                }
                if initialActivate {
                    nativeWindow.activate()
                }
            }
        } else {
            window.sharedContext.contentBounds.size = viewSize
            view.place(at: .zero, anchor: .topLeading, proposal: ProposedViewSize(viewSize))
        }
    }
    
    private func onWindowClosed() {
    }

    @MainActor
    func activate(at location: CGPoint, parent: WindowContext) -> Bool {
        self.updateContent()

        let popupWindow = self.environment.auxiliaryWindowPopupWindow
        if popupWindow, let window = parent.window {
            let position = window.convertPointToScreen(location)
            return self.makeWindow(position: position) != nil
        } else {
            guard let window = self.window else {
                Log.error("AuxiliaryWindowContext: no backing window")
                return false
            }
            if let host = parent as? AuxiliaryWindowHost {
                let contentScale = parent.window?.contentScaleFactor ?? 1.0
                window.sharedContext.contentScaleFactor = contentScale
                return host.addAuxiliaryWindow(window, position: location)
            }
        }
        return false
    }
    
    @MainActor
    private func makeWindow(position: CGPoint) -> WindowContext.Window? {
        guard let window = self.window else {
            Log.error("AuxiliaryWindowContext: no backing window")
            return nil
        }
        
        let initialized = window.window == nil
        if let win = window.makeWindow() {
            if initialized {
                win.contentSize = CGSize(width: 10, height: 10)
            }
            win.origin = position
            return win
        } else {
            Log.error("ContextMenuViewContext: failed to create menu window")
        }
        return nil
    }
}

// popup-window for auxiliary window scene
private class AuxiliaryWindowContext<Content>: GenericWindowContext<Content>, @unchecked Sendable where Content: View {

    override var style: WindowStyle { [.auxiliaryWindow, .autoResize] }

    var onViewLoadedCallback: (()->Void)?
    var onViewLayoutChangedCallback: (()->Void)?
    var onWindowClosingCallback: (() -> Void)?

    override init(content: _GraphValue<Content>, scene: SceneContext) {
        super.init(content: content, scene: scene)
    }

    override func updateContent() {
        super.updateContent()
    }
    
    override func onViewLoaded() {
        if view != nil {
            self.onViewLoadedCallback?()
        }
    }

    override func onViewLayoutUpdated() {
        if view != nil {
            self.onViewLayoutChangedCallback?()
        }
    }
    
    override func onWindowClosing(_: any GenericWindowContext<Content>.Window) {
        self.onWindowClosingCallback?()
    }
}


private struct AuxiliaryWindowPopupWindow: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var auxiliaryWindowPopupWindow: Bool {
        get { self[AuxiliaryWindowPopupWindow.self] }
        set { self[AuxiliaryWindowPopupWindow.self] = newValue }
    }
}
