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

    // called when the modal window is shown for the first time
    func onModalSessionInitiated()
    // called when the modal is closed by user action (e.g. gesture, close button)
    func onModalSessionDismissedByUser()
    // called when the modal is closed because its parent was dismissed
    func onModalSessionDismissedByParent()
    // called when the modal was never shown — cancelled before being initiated
    func onModalSessionCancelled()
}

protocol ModalWindowHost {
    func addModalWindow(_ client: ModalWindowClient) -> Bool
    func removeModalWindow(_ client: ModalWindowClient)
    // removes the client from the host without triggering any session callbacks
    func detachModalWindow(_ client: ModalWindowClient)
}

enum ModalResponse {
    case dismissed   // dismiss() was called programmatically
    case userAction  // closed by user action (e.g. gesture, close button)
    case byParent    // closed because the parent modal was dismissed
    case cancelled   // never shown — cancelled before being initiated
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

enum TransitionAnimationKey: String, Hashable {
    case scale
    case alpha
}

struct TransitionAnimationConfiguration<Key: Hashable> {
    struct Track {
        let curve: UnitCurve
        let keyframes: [(value: CGFloat, time: Double)]

        func value(at rawProgress: Double) -> CGFloat {
            let progress = curve.value(at: rawProgress)
            guard keyframes.count >= 2 else { return 1.0 }
            if progress <= keyframes.first!.time { return keyframes.first!.value }
            if progress >= keyframes.last!.time { return keyframes.last!.value }

            for i in 0..<(keyframes.count - 1) {
                let k0 = keyframes[i]
                let k1 = keyframes[i + 1]
                if progress >= k0.time && progress <= k1.time {
                    let t = (progress - k0.time) / (k1.time - k0.time)
                    let p0 = keyframes[max(i - 1, 0)].value
                    let p1 = k0.value
                    let p2 = k1.value
                    let p3 = keyframes[min(i + 2, keyframes.count - 1)].value
                    let spline = SplineSegment<CGFloat>.catmullRom(p0: p0, p1: p1, p2: p2, p3: p3)
                    return CGFloat(spline.interpolate(Scalar(t)))
                }
            }
            return keyframes.last!.value
        }
    }
    
    let tracks: [Key: Track]
}

// scene context for modal window scene
class ModalWindowSceneContext<Content>: TypedSceneContext<ModalWindowScene<Content>>, ModalWindowClient, @unchecked Sendable where Content: View {
    typealias Scene = ModalWindowScene<Content>
    typealias AnimationKey = TransitionAnimationKey
    typealias AnimationTrack = TransitionAnimationConfiguration<AnimationKey>.Track
    typealias AnimationConfiguration = TransitionAnimationConfiguration<AnimationKey>

    private struct TransitionAnimation: @unchecked Sendable {
        let duration: Double
        let configuration: AnimationConfiguration
        var elapsed: Double = 0
        var completion: (() -> Void)?

        var progress: Double {
            min(elapsed / duration, 1.0)
        }
        var isComplete: Bool { elapsed >= duration }
    }

    var transitionDuration: Double { 0.25 }
    var transitionPresentAnimation: AnimationConfiguration {
        AnimationConfiguration(
            tracks: [
                .scale: AnimationTrack(
                    curve: .easeOut,
                    keyframes: [(0.2, 0.0), (1.1, 0.8), (1.0, 1.0)]
                ),
                .alpha: AnimationTrack(
                    curve: .easeInOut,
                    keyframes: [(0.0, 0.0), (1.0, 1.0)]
                )
            ]
        )
    }
    var transitionDismissAnimation: AnimationConfiguration {
        AnimationConfiguration(
            tracks: [
                .scale: AnimationTrack(
                    curve: .easeIn,
                    keyframes: [(1.0, 0.0), (0.2, 1.0)]
                ),
                .alpha: AnimationTrack(
                    curve: .easeOut,
                    keyframes: [(1.0, 0.0), (0.0, 1.0)]
                )
            ]
        )
    }

    private struct _ModalContext: @unchecked Sendable {
        let window: ModalWindowContext<Content>
        weak var parentWindow: WindowContext?
        weak var parentContext: SharedContext?
        weak var modalWindow: (any PlatformWindow)?
        var windowOffset: CGPoint
        var windowSize: CGSize = .zero
        var activateFirstTime: Bool = true
        var filter: GraphicsContext.Filter?
        var transition: TransitionAnimation? = nil
        var onDismiss: ((ModalResponse) -> Void)? = nil
    }
    private var modalContext: _ModalContext? = nil

    private var window: ModalWindowContext<Content>? {
        self.modalContext?.window
    }

    private var animationProgress: Double {
        self.modalContext?.transition?.progress ?? 1.0
    }

    private func valueForProgress(_ rawProgress: Double, key: AnimationKey) -> CGFloat {
        guard let config = self.modalContext?.transition?.configuration,
              let track = config.tracks[key] else { return 1.0 }
        return track.value(at: rawProgress)
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

        let padding: CGFloat = 4
        var windowSize = view.sizeThatFits(.unspecified)
        windowSize.width = max(windowSize.width, 1) + padding * 2
        windowSize.height = max(windowSize.height, 1) + padding * 2
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
        // Platform window was closed by user action — extract and clear
        // the callback before tearDownModal() is called.
        let onDismiss = self.modalContext?.onDismiss
        self.modalContext?.onDismiss = nil
        tearDownModal()
        onDismiss?(.userAction)
    }

    @MainActor
    func present(context parentContext: SharedContext, withAnimation: Bool, onDismiss: ((ModalResponse) -> Void)? = nil) -> Bool {
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
        modalContext.onDismiss = onDismiss

        if usePlatformModal, let window = parentWindow.window {
            if let modal = modalContext.window.makeWindow() {
                modal.contentSize = CGSize(width: 10, height: 10)
                modal.origin = .zero
                modalContext.modalWindow = modal
                modal.addEventObserver(self) { [weak self](event: WindowEvent) in
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
                } 
                modal.removeEventObserver(self)    
                Log.error("ModalWindowContext: failed to present modal window")
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
                    if withAnimation {
                        modalContext.transition = TransitionAnimation(
                            duration: self.transitionDuration,
                            configuration: self.transitionPresentAnimation,
                            elapsed: 0,
                            completion: nil)
                    }
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

    func dismiss(withAnimation: Bool) {
        guard let context = self.modalContext else { return }

        // Remove the onDismiss callback before dismissing so that
        // onModalSessionDismissed() does not trigger it — .dismissed
        // is handled here after performImmediateDismiss completes.
        let onDismiss = context.onDismiss
        self.modalContext?.onDismiss = nil

        let isOverlayMode = context.modalWindow == nil
        if withAnimation && isOverlayMode {
            let elapsed = context.transition?.elapsed ?? 0.0
            self.modalContext?.transition = TransitionAnimation(
                duration: self.transitionDuration,
                configuration: self.transitionDismissAnimation,
                elapsed: elapsed,
                completion: { [weak self] in
                    self?.tearDownModal()
                    onDismiss?(.dismissed)
                })
            return
        }

        tearDownModal()
        onDismiss?(.dismissed)
    }

    private func tearDownModal() {
        guard let context = self.modalContext else { return }
        if let host = context.parentWindow as? ModalWindowHost {
            // detach without triggering session callbacks — caller handles response
            host.detachModalWindow(self)
        }
        let parentWindow = context.parentWindow?.window
        if let window = context.modalWindow {
            runOnMainQueue { [weak window, weak self] in
                if let self {
                    window?.removeEventObserver(self)
                }
                if let window {
                    parentWindow?.dismissModalWindow(window)
                    window.close()
                }
            }
        }

        self.modalContext = nil
        // clean up any child modals and auxiliary windows
        context.window.dismissAllModalWindows()
        context.window.dismissAllAuxiliaryWindows()

        Log.debug("ModalWindowSceneContext: dismissed modal window")
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
            let progress = self.animationProgress
            let alpha = self.valueForProgress(progress, key: .alpha)

            if let parentContext = modalContext.parentContext {
                let parentFrame = parentContext.contentBounds
                let backgroundOpacity = 0.3 * alpha
                context.fill(Path(parentFrame), with: .color(.black.opacity(backgroundOpacity)))
            }

            let modal = frame.offsetBy(dx: offset.x, dy: offset.y)
            let scale = self.valueForProgress(progress, key: .scale)
            let center = CGPoint(x: modal.midX, y: modal.midY)

            var context = context
            context.opacity = alpha
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -center.x, y: -center.y)

            let path = RoundedRectangle(cornerRadius: 5).path(in: modal)

            if let filter = modalContext.filter {
                var filteredContext = context
                filteredContext.addFilter(filter)
                filteredContext.fill(path, with: .color(.white))
            } else {
                context.fill(path, with: .color(.white))
            }
            context.stroke(path, with: .color(.black.opacity(0.7)), style: StrokeStyle(lineWidth: 1))
        }
    }

    func drawModalWindowOverlay(offset: CGPoint, with context: GraphicsContext) {
    }

    func drawModalWindowContent(offset: CGPoint, with context: GraphicsContext) {
        if let modalContext, let frame = self.modalWindowFrame() {
            let progress = self.animationProgress

            let alpha = self.valueForProgress(progress, key: .alpha)
            let modal = frame.offsetBy(dx: offset.x, dy: offset.y)
            let scale = self.valueForProgress(progress, key: .scale)
            let center = CGPoint(x: modal.midX, y: modal.midY)

            var context = context
            context.opacity = alpha
            context.translateBy(x: center.x, y: center.y)
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -center.x, y: -center.y)

            if alpha < 1.0 {                
                context.drawLayer { context in
                    modalContext.window
                        .drawFrame(context,
                                offset: modalContext.windowOffset + offset)
                }
            } else {
                modalContext.window
                    .drawFrame(context,
                               offset: modalContext.windowOffset + offset)
            }
        }
    }

    func updateModalWindowContent(tick: UInt64, delta: Double, date: Date) {
        if var transition = self.modalContext?.transition {
            transition.elapsed += delta
            if transition.isComplete {
                self.modalContext?.transition = nil
                transition.completion?()
            } else {
                self.modalContext?.transition = transition
            }
        }
        self.window?.updateView(tick: tick, delta: delta, date: date)
    }

    func modalWindowInputEventHandler() -> WindowInputEventHandler? {
        if self.modalContext?.transition != nil { return nil }
        return self.window
    }

    func onModalSessionInitiated() {
        Log.debug("ModalWindowSceneContext: modal session initiated")
    }

    private func endModalSession(response: ModalResponse?) {
        if let context = self.modalContext {
            let onDismiss = context.onDismiss
            self.modalContext = nil
            context.window.dismissAllModalWindows()
            context.window.dismissAllAuxiliaryWindows()
            if let response {
                onDismiss?(response)
            }
        }
    }

    func onModalSessionDismissedByUser() {
        endModalSession(response: .userAction)
    }

    func onModalSessionDismissedByParent() {
        endModalSession(response: .byParent)
    }

    func onModalSessionCancelled() {
        endModalSession(response: .cancelled)
    }
}

// popup-window for modal window scene
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
