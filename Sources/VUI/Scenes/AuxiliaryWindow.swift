//
//  File: AuxiliaryWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// AuxiliaryWindowClient / AuxiliaryWindowHost protocols removed (2026-04-17).
// Replaced by direct WindowController nesting:
//   - AppWindowsController owns strong refs to all dynamic aux windows.
//   - WindowController.auxChildWindows holds weak refs to overlay children.
//   - Parent calls child.updateView() / drawFrame() / onParentWindow*() directly.

// utility window (popup-window or layered window) scene
struct AuxiliaryWindowScene<Content>: _PrimitiveScene where Content: View {
    var content: Content

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("AuxiliaryWindowScene._makeScene requires AG context")
        }
        let context = AuxiliaryWindowSceneContext<Content>(graph: scene, inputs: inputs)
        // Keep the context alive for the lifetime of the AG subgraph.
        graph.makeSideEffectRule { [context] in _ = context }
        return _SceneOutputs(preferences: PreferencesOutputs())
    }
}

// scene context for utility window scene
class AuxiliaryWindowSceneContext<Content>: @unchecked Sendable where Content: View {
    typealias Scene = AuxiliaryWindowScene<Content>

    let layoutPadding = 4

    // Stored at _makeScene time to access content graph and environment.
    private let contentGraph: _GraphValue<Content>
    private let inputs: _SceneInputs

    private struct _ActivationContext: @unchecked Sendable {
        let window: AuxiliaryWindowController<Content>
        weak var parentController: WindowController?
        weak var popupWindow: (any PlatformWindow)?
        var windowOffset: CGPoint
        var windowSize: CGSize = .zero
        var dismissOnDeactivate: Bool
        var activateFirstTime: Bool = true
        var filter: GraphicsContext.Filter?
    }
    private var activationContext: _ActivationContext? = nil

    private var window: AuxiliaryWindowController<Content>? {
        self.activationContext?.window
    }

    // Read from stored scene inputs, e.g. auxiliaryWindowUsingPlatformWindow.
    private var environment: EnvironmentValues {
        inputs.base.cachedEnvironment.value.environment.value
    }

    init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        self.contentGraph = graph[\.content]
        self.inputs = inputs
        self.activationContext = nil
    }

    fileprivate func layoutBounds(_ bounds: CGRect) -> CGRect {
        let padding = CGFloat(self.layoutPadding)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var rect = bounds.insetBy(dx: padding, dy: padding)
        if rect.width < 1 || rect.height < 1 {
            let width = max(rect.width, 1)
            let height = max(rect.height, 1)
            rect = CGRect(
                x: center.x - width / 2,
                y: center.y - height / 2,
                width: width,
                height: height)
        }
        return rect
    }
    
    fileprivate func onViewLoaded() {
    }

    fileprivate func onViewLayoutChanged() {
        guard let window = self.window else {
            fatalError("AuxiliaryWindowContext: Invalid window!")
        }
        guard let layoutComputer = window.viewGraph.rootLayoutComputer else {
            fatalError("AuxiliaryWindowContext: rootLayoutComputer not set. AG wiring incomplete!")
        }

        let padding = CGFloat(self.layoutPadding)
        let contentSize = layoutComputer.value.sizeThatFits(.unspecified)
        var windowSize = contentSize
        windowSize.width = max(windowSize.width, 1) + padding * 2
        windowSize.height = max(windowSize.height, 1) + padding * 2
        self.activationContext?.windowSize = windowSize

        if let platformWindow = window.window {
            let style = window.style

            let activate = self.activationContext?.activateFirstTime ?? false
            if activate {
                self.activationContext?.activateFirstTime = false
            }

            Task { @MainActor in
                if style.contains(.autoResize) {
                    platformWindow.contentSize = windowSize
                }
                if activate {
                    platformWindow.activate()
                }
            }
        } else {
            window.sharedContext.contentBounds.size = windowSize
            
            let center = CGPoint(x: windowSize.width * 0.5, y: windowSize.height * 0.5)
            layoutComputer.value.place(at: center,
                                       anchor: .center,
                                       proposal: ProposedViewSize(contentSize))
        }
    }

    fileprivate func onWindowClosed() {
        self.dismiss()
    }

    @MainActor
    func activate(at location: CGPoint,
                  in parentController: WindowController,
                  dismissOnDeactivate: Bool) -> Bool {
        // Already active, just reposition.
        if activationContext != nil {
            activationContext?.windowOffset = location
            activationContext?.activateFirstTime = true
            return true
        }

        // Read environment from the scene to decide platform vs overlay mode.
        // Editors set auxiliaryWindowUsingPlatformWindow = true.
        // Games keep it false for overlay-only rendering.
        let usePlatformWindow = environment.auxiliaryWindowUsingPlatformWindow

        let windowKey = WindowKey(namespace: .app, sceneID: SceneID(Content.self, index: 0))
        let window = AuxiliaryWindowController<Content>(
            content: contentGraph, sceneContext: self, windowKey: windowKey)

        var ctx = _ActivationContext(
            window: window,
            parentController: parentController,
            windowOffset: location,
            dismissOnDeactivate: dismissOnDeactivate
        )

        if usePlatformWindow, let hostPlatformWindow = parentController.window {
            // Platform window mode: create a real OS popup window.
            guard Platform.factory.supportedWindowStyles([.auxiliaryWindow])
                    .contains(.auxiliaryWindow) else {
                Log.error("AuxiliaryWindow: auxiliaryWindow style not supported on this platform")
                return false
            }
            guard let popup = window.makeWindow() else {
                Log.error("AuxiliaryWindow: failed to create platform window")
                return false
            }
            let screenPos = hostPlatformWindow.convertPointToScreen(location)
            popup.contentSize = CGSize(width: 10, height: 10)
            popup.origin = screenPos
            ctx.popupWindow = popup
            self.activationContext = ctx

            // Forward host window events (move/close/deactivate) to this popup.
            hostPlatformWindow.addEventObserver(self) { [weak self] (event: WindowEvent) in
                guard let self else { return }
                switch event.type {
                case .activated:   self.onParentWindowActivated()
                case .inactivated: self.onParentWindowInactivated()
                case .closed:      self.onParentWindowClosed()
                case .moved, .resized: self.onParentWindowMoved()
                default: break
                }
            }
            // Clicking inside the host while popup is open inactivates the popup.
            hostPlatformWindow.addEventObserver(self) { [weak self] (event: MouseEvent) in
                if event.type == .buttonDown { self?.onParentWindowInactivated() }
            }
            parentController.appWindowsController?.presentAuxiliaryWindow(window, in: parentController)
            return true
        } else {
            // Overlay mode: render inside the parent window.
            let contentScale = parentController.window?.contentScaleFactor ?? 1.0
            window.sharedContext.contentScaleFactor = contentScale
            let shadow = GraphicsContext.Filter.shadow(radius: 4.0, x: 0, y: 0)
            ctx.filter = shadow
            self.activationContext = ctx
            parentController.appWindowsController?.presentAuxiliaryWindow(window, in: parentController)
            return true
        }
    }

    // MARK: - Parent window event forwarding

    func onParentWindowActivated()   {}
    func onParentWindowInactivated() { dismissPopup() }
    func onParentWindowMoved()       { dismissPopup() }
    func onParentWindowClosed()      { dismiss() }
    func onGestureInitiated(from initiator: AnyObject?, location: CGPoint) {
        guard initiator !== self else { return }
        if let frame = auxiliaryWindowFrame(), frame.contains(location) { return }
        dismissPopup()
    }

    func dismiss() {
        if let context = self.activationContext {
            self.activationContext = nil
            context.parentController?.removeAuxChild(context.window)

            context.window.dismissAllModalWindows()
            context.window.dismissAllAuxiliaryWindows()

            if let window = context.popupWindow {
                runOnMainQueue { @MainActor [weak window] in
                    window?.close()
                }
            }
            if let window = context.parentController?.window {
                runOnMainQueue { @MainActor [weak window] in
                    window?.removeEventObserver(self)
                }
            }

            Log.debug("AuxiliaryWindowSceneContext: dismissed auxiliary window")
        }
    }

    private func dismissPopup() {
        if self.activationContext?.dismissOnDeactivate == true {
            self.dismiss()
        }
    }

    func auxiliaryWindowFrame() -> CGRect? {
        if let activationContext {
            if activationContext.windowSize.width > .zero &&
                activationContext.windowSize.height > .zero {
                return CGRect(origin: activationContext.windowOffset,
                              size: activationContext.windowSize)
            }
        }
        return nil
    }
    
    var auxiliaryWindowShape: some Shape {
        RoundedRectangle(cornerRadius: 5)
    }

    // Called by AuxiliaryWindowController.drawFrame (overlay mode).
    func drawBackground(offset: CGPoint, frame: CGRect, with context: GraphicsContext) {
        guard let activationContext else { return }
        let rect = frame.offsetBy(dx: offset.x, dy: offset.y)
        let path = auxiliaryWindowShape.path(in: rect)
        if let filter = activationContext.filter {
            var ctx = context; ctx.addFilter(filter)
            ctx.fill(path, with: .color(.white))
        } else {
            context.fill(path, with: .color(.white))
        }
        context.stroke(path, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 1))
    }

    func drawOverlay(offset: CGPoint, frame: CGRect, with context: GraphicsContext) {
        // Reserved for future overlay decorations.
    }

}

// WindowController subclass for auxiliary popup windows.
private class AuxiliaryWindowController<Content: View>: WindowController, @unchecked Sendable {
    override var style: PlatformWindowStyle { [.auxiliaryWindow, .autoResize] }

    private weak var sceneContext: AuxiliaryWindowSceneContext<Content>?

    init(content: _GraphValue<Content>,
         sceneContext: AuxiliaryWindowSceneContext<Content>,
         windowKey: WindowKey) {
        super.init(content: content, scene: windowKey)
        self.sceneContext = sceneContext
    }

    override func onViewLoaded() {
        sceneContext?.onViewLoaded()
    }

    override func layoutBounds(_ bounds: CGRect) -> CGRect {
        sceneContext?.layoutBounds(bounds) ?? bounds
    }

    override func onViewLayoutUpdated() {
        sceneContext?.onViewLayoutChanged()
    }

    override func onWindowClosing(_: any PlatformWindow) {
        sceneContext?.onWindowClosed()
    }

    // Overlay mode: draw background behind content, then content.
    override func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        if let scene = sceneContext, let frame = scene.auxiliaryWindowFrame() {
            scene.drawBackground(offset: offset, frame: frame, with: context)
        }
        super.drawFrame(offset: offset, context)
        if let scene = sceneContext, let frame = scene.auxiliaryWindowFrame() {
            scene.drawOverlay(offset: offset, frame: frame, with: context)
        }
    }

    // Overlay hit-test: use the aux window's shape.
    override func overlayHitTest(_ locationInParent: CGPoint) -> Bool {
        guard let scene = sceneContext,
              let frame = scene.auxiliaryWindowFrame() else { return false }
        return scene.auxiliaryWindowShape.path(in: frame).contains(locationInParent)
    }

    // Parent window event callbacks.
    override func onParentWindowActivated()   { sceneContext?.onParentWindowActivated() }
    override func onParentWindowInactivated() { sceneContext?.onParentWindowInactivated() }
    override func onParentWindowMoved()       { sceneContext?.onParentWindowMoved() }
    override func onParentWindowClosed()      { sceneContext?.onParentWindowClosed() }
    override func onGestureInitiated(from initiator: AnyObject?, location: CGPoint) {
        sceneContext?.onGestureInitiated(from: initiator, location: location)
    }
}

private struct AuxiliaryWindowUsingPlatformWindow: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var auxiliaryWindowUsingPlatformWindow: Bool {
        get { self[AuxiliaryWindowUsingPlatformWindow.self] }
        set { self[AuxiliaryWindowUsingPlatformWindow.self] = newValue }
    }
}
