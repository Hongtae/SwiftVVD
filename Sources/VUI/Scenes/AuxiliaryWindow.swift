//
//  File: AuxiliaryWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol AuxiliaryWindowClient: AnyObject {
    func auxiliaryWindowFrame() -> CGRect?
    func drawAuxiliaryWindowBackground(offset: CGPoint, with context: GraphicsContext)
    func drawAuxiliaryWindowOverlay(offset: CGPoint, with context: GraphicsContext)
    func drawAuxiliaryWindowContent(offset: CGPoint, with context: GraphicsContext)
    func updateAuxiliaryWindowContent(tick: UInt64, delta: Double, date: Date)

    func auxiliaryWindowInputEventHandler() -> WindowInputEventHandler?

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
    weak var hostWindow: WindowContext?
    weak var sceneContext: SceneContext?
    
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
        _SceneOutputs(scene: UnarySceneGenerator(graph: scene, inputs: inputs) { graph, inputs in
            AuxiliaryWindowSceneContext(graph: graph, inputs: inputs)
        })
    }
}

// scene context for utility window scene
class AuxiliaryWindowSceneContext<Content>: TypedSceneContext<AuxiliaryWindowScene<Content>>, AuxiliaryWindowClient, @unchecked Sendable where Content: View {
    typealias Scene = AuxiliaryWindowScene<Content>

    private struct _ActivationContext: @unchecked Sendable {
        let window: AuxiliaryWindowContext<Content>
        weak var parentWindow: WindowContext?
        weak var popupWindow: (any PlatformWindow)?
        var windowOffset: CGPoint
        var windowSize: CGSize = .zero
        var dismissOnDeactivate: Bool
        var activateFirstTime: Bool = true
        var filter: GraphicsContext.Filter?
    }
    private var activationContext: _ActivationContext? = nil

    private var window: AuxiliaryWindowContext<Content>? {
        self.activationContext?.window
    }
    
    override init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        super.init(graph: graph, inputs: inputs)
        self.activationContext = nil
    }

    override func updateContent() {
        super.updateContent()
        if self.content != nil {
            self.window?.updateContent()
        }
    }

    override var windows: [WindowContext] {
        [self.window].compactMap(\.self)
    }

    override var primaryWindows: [WindowContext] {
        [self.window].compactMap(\.self)
    }

    override var isValid: Bool {
        if super.isValid {
            if let window {
                return window.isValid
            }
            return true
        }
        return false
    }

    fileprivate func onViewLoaded() {
    }

    fileprivate func onViewLayoutChanged() {
        guard let window = self.window else {
            Log.error("AuxiliaryWindowContext: Invalid window!")
            return
        }
        guard let view = window.view else {
            Log.error("AuxiliaryWindowContext: Invalid view!")
            return
        }

        let padding: CGFloat = 4
        var windowSize = view.sizeThatFits(.unspecified)
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
            view.place(at: center, anchor: .center, proposal: ProposedViewSize(windowSize))
        }
    }

    fileprivate func onWindowClosed() {
        self.dismiss()
    }

    @MainActor
    func activate(at location: CGPoint, context parentContext: SharedContext, dismissOnDeactivate: Bool) -> Bool {
        self.updateContent()
        defer {
            self.window?.updateContent()
        }

        let parentWindow = parentContext.window
        var enablePopup = self.environment.auxiliaryWindowUsingPlatformWindow
        if enablePopup && parentWindow is AuxiliaryWindowHost {
            if Platform.factory.supportedWindowStyles([.auxiliaryWindow]).contains(.auxiliaryWindow) == false {
                Log.error("AuxiliaryWindowContext: Auxiliary windows are not supported on this platform.")
                enablePopup = false
            }
        }

        if activationContext != nil {
            Log.debug("AuxiliaryWindowContext: already activated")
            self.activationContext?.windowOffset = location
            self.activationContext?.activateFirstTime = true
            return true
        }

        let window = AuxiliaryWindowContext(content: self.graph[\.content], scene: self)
        var activationContext = _ActivationContext(window: window,
                                                   parentWindow: parentWindow,
                                                   windowOffset: location,
                                                   windowSize: .zero,
                                                   dismissOnDeactivate: dismissOnDeactivate)
        window.sharedContext.auxiliarySceneContext = AuxiliarySceneContext(
            hostContext: parentContext,
            hostWindow: parentWindow,
            sceneContext: self,

            dismissOnDeactivate: dismissOnDeactivate,
            dismiss: { [weak self] in self?.dismiss() },
            dismissPopup: { [weak self] in self?.dismissPopup() }
        )

        if enablePopup, let window = parentWindow.window {
            if let popup = activationContext.window.makeWindow() {
                let position = window.convertPointToScreen(location)
                popup.contentSize = CGSize(width: 10, height: 10)
                popup.origin = position
                activationContext.popupWindow = popup
                self.activationContext = activationContext
                window.addEventObserver(self) { [weak self](event: WindowEvent) in
                    guard let self else { return }
                    switch event.type {
                    case .activated:
                        self.onHostWindowActivated()
                    case .inactivated:
                        self.onHostWindowInactivated()
                    case .closed:
                        self.onHostWindowClosed()
                    case .moved, .resized:
                        self.onHostWindowMoved()
                    default:
                        break
                    }
                }
                window.addEventObserver(self) { [weak self](event: MouseEvent) in
                    guard let self else { return }
                    switch event.type {
                    case .buttonDown:
                        self.onHostWindowInactivated()
                    default:
                        break
                    }
                }
                return true
            } else {
                Log.error("AuxiliaryWindowContext: failed to create popup window")
            }
        } else {
            if let host = parentWindow as? AuxiliaryWindowHost {
                let contentScale = parentWindow.window?.contentScaleFactor ?? 1.0
                window.sharedContext.contentScaleFactor = contentScale
                if host.addAuxiliaryWindow(self) {
                    let filter = GraphicsContext.Filter.shadow(radius: 4.0, x: 0, y: 0)
                    activationContext.filter = filter
                    self.activationContext = activationContext
                    return true
                }
            } else {
                Log.error("AuxiliaryWindowContext: parent window is not AuxiliaryWindowHost")
            }
        }
        return false
    }

    func dismiss() {
        if let context = self.activationContext {
            self.activationContext = nil
            if let host = context.parentWindow as? AuxiliaryWindowHost {
                host.removeAuxiliaryWindow(self)
            }

            context.window.dismissAllModalWindows()
            context.window.dismissAllAuxiliaryWindows()

            if let window = context.popupWindow {
                runOnMainQueue { @MainActor [weak window] in
                    window?.close()
                }
            }
            if let window = context.parentWindow?.window {
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

    func drawAuxiliaryWindowBackground(offset: CGPoint, with context: GraphicsContext) {
        if let activationContext, let frame = self.auxiliaryWindowFrame() {

            let auxFrame = frame.offsetBy(dx: offset.x, dy: offset.y)
            //let path = Rectangle().path(in: auxFrame)
            let path = RoundedRectangle(cornerRadius: 5).path(in: auxFrame)

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
                .drawFrame(context,
                           offset: activationContext.windowOffset + offset)
        }
    }

    func updateAuxiliaryWindowContent(tick: UInt64, delta: Double, date: Date) {
        self.window?.updateView(tick: tick, delta: delta, date: date)
    }

    func auxiliaryWindowInputEventHandler() -> WindowInputEventHandler? {
        return self.window
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
private class AuxiliaryWindowContext<Content>: GenericWindowContext<Content>, @unchecked Sendable where Content: View {
    override var style: PlatformWindowStyle { [.auxiliaryWindow, .autoResize] }

    private weak var _scene: AuxiliaryWindowSceneContext<Content>?

    override init(content: _GraphValue<Content>, scene: SceneContext) {
        super.init(content: content, scene: scene)
        guard let scene = scene as? AuxiliaryWindowSceneContext<Content> else {
            fatalError("AuxiliaryWindowContext: invalid scene context")
        }
        self._scene = scene
    }

    override func onViewLoaded() {
        if view != nil {
            _scene?.onViewLoaded()
        }
    }

    override func onViewLayoutUpdated() {
        if view != nil {
            _scene?.onViewLayoutChanged()
        }
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
