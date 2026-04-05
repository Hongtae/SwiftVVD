//
//  File: AuxiliaryWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol AuxiliaryWindowClient: AnyObject {
    func auxiliaryWindowFrame() -> CGRect?
    func drawAuxiliaryWindowBackground(offset: CGPoint, with context: GraphicsContext)
    func drawAuxiliaryWindowOverlay(offset: CGPoint, with context: GraphicsContext)
    func drawAuxiliaryWindowContent(offset: CGPoint, with context: GraphicsContext)
    func updateAuxiliaryWindowContent(tick: UInt64, delta: Double, date: Date,
                                      redraw: inout Bool, _: WindowContext.WithGraphicsContext)

    func auxiliaryWindowInputEventHandler() -> WindowInputEventHandler?
    func auxiliaryWindowHitTest(_ point: CGPoint) -> Bool

    func activateAuxiliaryWindow()
    func inactivateAuxiliaryWindow()

    func onHostWindowActivated()
    func onHostWindowInactivated()
    func onHostWindowMoved()
    func onHostWindowClosed()
    func initiatedGesture(from: AnyObject?, location: CGPoint)
}

protocol AuxiliaryWindowHost {
    func addAuxiliaryWindow(_ client: AuxiliaryWindowClient) -> Bool
    func removeAuxiliaryWindow(_ client: AuxiliaryWindowClient)
}

struct AuxiliarySceneContext {
    weak var hostContext: SharedContext?
    weak var hostController: WindowController?
    var sceneContext: Any?
    
    let dismissOnDeactivate: Bool
    let dismiss: () -> Void
    let dismissPopup: () -> Void
    
    func dismiss(withParentContext: Bool) {
        if withParentContext {
            hostContext?.auxiliarySceneContext?.dismiss(withParentContext: true)
        }
        self.dismiss()
    }
    
    func dismissPopup(withParentContext: Bool) {
        if withParentContext {
            hostContext?.auxiliarySceneContext?.dismissPopup(withParentContext: true)
        }
        self.dismissPopup()
    }
}

// utility window (popup-window or layered window) scene
struct AuxiliaryWindowScene<Content>: _PrimitiveScene where Content: View {
    var content: Content

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        fatalError("Implement with AG")
    }
}

// scene context for utility window scene
class AuxiliaryWindowSceneContext<Content>: AuxiliaryWindowClient, @unchecked Sendable where Content: View {
    typealias Scene = AuxiliaryWindowScene<Content>
    
    let layoutPadding = 4

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
    
    init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
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
            fatalError("AuxiliaryWindowContext: rootLayoutComputer not set — AG wiring incomplete!")
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
    func activate(at location: CGPoint, context parentContext: SharedContext, dismissOnDeactivate: Bool) -> Bool {
         fatalError("Implement with AG")
        return false
    }

    func dismiss() {
        if let context = self.activationContext {
            self.activationContext = nil
            context.parentController?.removeAuxiliaryWindow(self)

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

    func drawAuxiliaryWindowBackground(offset: CGPoint, with context: GraphicsContext) {
        if let activationContext, let frame = self.auxiliaryWindowFrame() {

            let auxFrame = frame.offsetBy(dx: offset.x, dy: offset.y)
            //let path = Rectangle().path(in: auxFrame)
            let path = auxiliaryWindowShape.path(in: auxFrame)

            if let filter = activationContext.filter {
                var context = context
                context.addFilter(filter)
                context.fill(path, with: .color(.white))
            } else {
                context.fill(path, with: .color(.white))
            }
            context.stroke(path, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 1))
        }
    }

    func drawAuxiliaryWindowOverlay(offset: CGPoint, with context: GraphicsContext) {
    }

    func drawAuxiliaryWindowContent(offset: CGPoint, with context: GraphicsContext) {
        if let activationContext {
            activationContext.window
                .drawFrame(offset: activationContext.windowOffset + offset, context)
        }
    }

    func updateAuxiliaryWindowContent(tick: UInt64, delta: Double, date: Date,
                                      redraw: inout Bool,
                                      _ withGC: WindowContext.WithGraphicsContext) {
        if let frame = self.auxiliaryWindowFrame() {
            self.window?.updateView(tick: tick, delta: delta, date: date,
                                    contentSize: frame.size, redraw: &redraw,
                                    withGC)
        }
    }

    func auxiliaryWindowInputEventHandler() -> WindowInputEventHandler? {
        return self.window
    }
    
    func auxiliaryWindowHitTest(_ point: CGPoint) -> Bool {
        if let frame = self.auxiliaryWindowFrame() {
            let path = auxiliaryWindowShape.path(in: frame)
            return path.contains(point)
        }
        return false
    }

    // AuxiliaryWindowDelegate
    func activateAuxiliaryWindow() {
    }

    func inactivateAuxiliaryWindow() {
        self.dismissPopup()
    }

    func onHostWindowActivated() {
    }

    func onHostWindowInactivated() {
        self.dismissPopup()
    }

    func onHostWindowMoved() {
        self.dismissPopup()
    }

    func onHostWindowClosed() {
        self.dismiss()
    }

    func initiatedGesture(from target: AnyObject?, location: CGPoint) {
        if target !== self {
            if let frame = self.auxiliaryWindowFrame(), frame.contains(location) {
                return
            }
            self.dismissPopup()
        }
    }
}

// popup-window for auxiliary window scene
private class AuxiliaryWindowController<Content: View>: WindowController, @unchecked Sendable {
    override var style: PlatformWindowStyle { [.auxiliaryWindow, .autoResize] }

    private weak var _scene: AuxiliaryWindowSceneContext<Content>?

    init(content: _GraphValue<Content>, scene: WindowKey) {
        super.init(content: content, scene: scene)
        guard let scene = scene as? AuxiliaryWindowSceneContext<Content> else {
            fatalError("AuxiliaryWindowController: invalid scene context")
        }
        self._scene = scene
    }

    override func onViewLoaded() {
        //if view != nil {
            _scene?.onViewLoaded()
        //}
    }

    override func layoutBounds(_ bounds: CGRect) -> CGRect {
        _scene?.layoutBounds(bounds) ?? bounds
    }
    
    override func onViewLayoutUpdated() {
        //if view != nil {
            _scene?.onViewLayoutChanged()
        //}
    }

    override func onWindowClosing(_: any PlatformWindow) {
        _scene?.onWindowClosed()
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

