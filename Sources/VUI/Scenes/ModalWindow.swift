//
//  File: ModalWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

protocol ModalWindowClient: AnyObject {
    func modalWindowFrame() -> CGRect?
    func drawModalWindowBackground(offset: CGPoint, with context: GraphicsContext)
    func drawModalWindowOverlay(offset: CGPoint, with context: GraphicsContext)
    func drawModalWindowContent(offset: CGPoint, with context: GraphicsContext)
    func updateModalWindowContent(tick: UInt64, delta: Double, date: Date)

    func modalWindowInputEventHandler() -> WindowInputEventHandler?

    // called when the modal window is shown
    func onModalSessionInitiated()
    // called when the window is closed
    func onModalSessionDismissed()
    // called when the modal window is cancelled without being initialized
    func onModalSessionCancelled()
}

protocol ModalWindowHost {
    func addModalWindow(_ client: ModalWindowClient) -> Bool
    func removeModalWindow(_ client: ModalWindowClient)
}

struct ModalWindowScene<Content>: _PrimitiveScene where Content: View {
    let content: ()->Content

    fileprivate var _content: Content { content() }

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        _SceneOutputs(scene: UnarySceneGenerator(graph: scene, inputs: inputs) { graph, inputs in
            ModalWindowSceneContext(graph: graph, inputs: inputs)
        })
    }
}


// scene context for utility window scene
class ModalWindowSceneContext<Content>: TypedSceneContext<ModalWindowScene<Content>>, ModalWindowClient, @unchecked Sendable where Content: View {
    typealias Scene = ModalWindowScene<Content>

    private struct _ModalContext: @unchecked Sendable {
        let window: ModalWindowContext<Content>
        weak var parentWindow: WindowContext?
        weak var parentContext: SharedContext?
        weak var modalWindow: (any PlatformWindow)?
        var windowOffset: CGPoint
        var windowSize: CGSize = .zero
        var activateFirstTime: Bool = true
        var filter: GraphicsContext.Filter?
    }
    private var modalContext: _ModalContext? = nil

    private var window: ModalWindowContext<Content>? {
        self.modalContext?.window
    }
    
    override init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        super.init(graph: graph, inputs: inputs)
        self.modalContext = nil
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
            Log.error("ModalWindowContext: Invalid window!")
            return
        }
        guard let view = window.view else {
            Log.error("ModalWindowContext: Invalid view!")
            return
        }

        let padding = 4
        var windowSize = view.sizeThatFits(.unspecified)
        windowSize.width = max(windowSize.width, 1) + CGFloat(padding * 2)
        windowSize.height = max(windowSize.height, 1) + CGFloat(padding * 2)
        self.modalContext?.windowSize = windowSize

        if let platformWindow = window.window {
            let style = window.style

            let activate = self.modalContext?.activateFirstTime ?? false
            if activate {
                self.modalContext?.activateFirstTime = false
            }

            Task { @MainActor in
                if style.contains(.autoResize) {
                    platformWindow.contentSize = windowSize
                }
                if activate {
                    // set modal window position to center of parent window
                    if let parentWindow = self.modalContext?.parentWindow?.window {
                        let parentFrame = parentWindow.windowFrame
                        let centerPosition = CGPoint(x: parentFrame.midX, y: parentFrame.midY)
                        let windowSize = platformWindow.windowFrame.size
                        platformWindow.origin = CGPoint(x: centerPosition.x - windowSize.width * 0.5,
                                                        y: centerPosition.y - windowSize.height * 0.5)
                        Log.debug("ModalWindowContext: platform modal window centered at \(centerPosition)")
                    }
                    platformWindow.activate()
                }
            }
        } else {
            window.sharedContext.contentBounds.size = windowSize
            let center = CGPoint(x: windowSize.width * 0.5, y: windowSize.height * 0.5)
            view.place(at: center, anchor: .center, proposal: ProposedViewSize(windowSize))
            
            // set modal window offset to center of parent
            if let parentContext = self.modalContext?.parentContext {
                let parentSize = parentContext.contentBounds.size
                let centerPosition = CGPoint(x: parentSize.width * 0.5, y: parentSize.height * 0.5)
                self.modalContext?.windowOffset = centerPosition
            }
        }
    }

    fileprivate func onWindowClosed() {
        self.dismiss()
    }

    @MainActor
    func present(context parentContext: SharedContext, withAnimation: Bool) -> Bool {
        self.updateContent()
        defer {
            self.window?.updateContent()
        }

        let parentWindow = parentContext.window
        var usePlatformModal = self.environment.modalSessionUsingPlatformWindow
        if usePlatformModal && parentWindow is ModalWindowHost {
            if let window = parentWindow.window, window.canPresentModalWindow == false {
                Log.error("ModalWindowContext: Modal windows are not supported on this window.")
                usePlatformModal = false
            }
        }

        if modalContext != nil {
            Log.debug("ModalWindowContext: already presented")
            self.modalContext?.activateFirstTime = true
            return true
        }

        let window = ModalWindowContext(content: self.graph[\._content], scene: self)
        
        var modalContext = _ModalContext(window: window,
                                        parentWindow: parentWindow,
                                        parentContext: parentContext,
                                        windowOffset: .zero,
                                        windowSize: .zero)

        if usePlatformModal, let window = parentWindow.window {
            if let modal = modalContext.window.makeWindow() {
                modal.contentSize = CGSize(width: 10, height: 10)
                modal.origin = .zero
                modalContext.modalWindow = modal
                window.addEventObserver(self) { [weak self](event: WindowEvent) in
                    guard let self else { return }
                    switch event.type {
                    case .created:
                        self.onModalSessionInitiated()
                    case .closed:
                        self.onWindowClosed()
                    default:
                        break
                    }
                }
                if window.presentModalWindow(modal) {
                    self.modalContext = modalContext
                    return true
                } else {
                    Log.error("ModalWindowContext: failed to present modal window")
                }
            } else {
                Log.error("ModalWindowContext: failed to create modal window")
            }
        } else {
            if let host = parentWindow as? ModalWindowHost {
                let contentScale = parentWindow.window?.contentScaleFactor ?? 1.0
                window.sharedContext.contentScaleFactor = contentScale
                if host.addModalWindow(self) {
                    let filter = GraphicsContext.Filter.shadow(radius: 8.0, x: 0, y: 0)
                    modalContext.filter = filter
                    self.modalContext = modalContext
                    return true
                }
            } else {
                Log.error("ModalWindowContext: parent window is not ModalWindowHost")
            }
        }
        self.modalContext = nil
        return false
    }

    func dismiss(withAnimation: Bool = false, completion: (@Sendable () -> Void)? = nil) {
        if let context = self.modalContext {
            self.modalContext = nil
            if let host = context.parentWindow as? ModalWindowHost {
                host.removeModalWindow(self)
            }
            let parentWindow = context.parentWindow?.window
            if let window = context.modalWindow {
                runOnMainQueue { @MainActor [weak window] in
                    if let window = window {
                        parentWindow?.dismissModalWindow(window)
                        window.close()
                    }
                    completion?()
                }
            } else {            
                self.onModalSessionDismissed()
                completion?()
            }

            Log.debug("ModalWindowSceneContext: dismissed modal window")
        } else {
            completion?()
        }
    }

    func modalWindowFrame() -> CGRect? {
        if let modalContext {
            if modalContext.windowSize.width > .zero &&
                modalContext.windowSize.height > .zero {
                return CGRect(origin: modalContext.windowOffset,
                              size: modalContext.windowSize)
            }
        }
        return nil
    }

    func drawModalWindowBackground(offset: CGPoint, with context: GraphicsContext) {
        if let modalContext, let frame = self.modalWindowFrame() {

            if let parentContext = modalContext.parentContext {
                let frame = parentContext.contentBounds
                context.fill(Path(frame), with: .color(.black.opacity(0.3)))
            }

            let frame = frame.offsetBy(dx: offset.x, dy: offset.y)
            let path = RoundedRectangle(cornerRadius: 5).path(in: frame)

            if let filter = modalContext.filter {
                var context = context
                context.addFilter(filter)
                context.fill(path, with: .color(.white))
            } else {
                context.fill(path, with: .color(.white))
            }
            context.stroke(path, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 1))
        }
    }

    func drawModalWindowOverlay(offset: CGPoint, with context: GraphicsContext) {
    }

    func drawModalWindowContent(offset: CGPoint, with context: GraphicsContext) {
        if let modalContext {
            modalContext.window
                .drawFrame(context,
                           offset: modalContext.windowOffset + offset)
        }
    }

    func updateModalWindowContent(tick: UInt64, delta: Double, date: Date) {
        self.window?.updateView(tick: tick, delta: delta, date: date)
    }

    func modalWindowInputEventHandler() -> WindowInputEventHandler? {
        return self.window
    }

    func onModalSessionInitiated() {
        Log.debug("ModalWindowSceneContext: modal session initiated")
    }

    func onModalSessionDismissed() {
        if let context = self.modalContext {
            self.modalContext = nil
            var clients = context.window.modalClients
            if clients.isEmpty == false {
                clients.removeFirst().onModalSessionDismissed()
            }
            clients.forEach { $0.onModalSessionCancelled() }
        }
    }

    func onModalSessionCancelled() {
        if let context = self.modalContext {
            self.modalContext = nil
            context.window.modalClients.forEach {
                $0.onModalSessionCancelled() 
            }
        }
    }
}

// popup-window for auxiliary window scene
private class ModalWindowContext<Content>: GenericWindowContext<Content>, @unchecked Sendable where Content: View {
    override var style: PlatformWindowStyle { [.autoResize] }

    private weak var _scene: ModalWindowSceneContext<Content>?

    override init(content: _GraphValue<Content>, scene: SceneContext) {
        super.init(content: content, scene: scene)
        guard let scene = scene as? ModalWindowSceneContext<Content> else {
            fatalError("ModalWindowContext: invalid scene context")
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


private struct ModalSessionUsingPlatformWindow: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    public var modalSessionUsingPlatformWindow: Bool {
        get { self[ModalSessionUsingPlatformWindow.self] }
        set { self[ModalSessionUsingPlatformWindow.self] = newValue }
    }
}
