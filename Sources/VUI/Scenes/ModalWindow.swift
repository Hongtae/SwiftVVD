//
//  File: ModalWindow.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// MARK: - Deprecated ModalWindowScene
//
// ModalWindowScene is kept as legacy scaffolding for modal overlay animation.
// The intended modal path is:
//   .sheet() / .alert() / .confirmationDialog() modifier
//   -> preference key -> ViewGraph side-effect
//   -> WindowController.updateSheetPresentation / updateAlertPresentation
//   -> WindowController.addModalChild, with the matching presentation session
//
// ModalWindowSceneContext.present() is the OLD path:
//   -> AppWindowsController.presentModalWindow (now removed)
//   -> ModalWindowController (private subclass)
// Both AppWindowsController involvement and the ModalWindowScene scene-builder
// API are removed from the production path. This file is kept because:
//
//   1. ModalWindowController.drawFrame contains overlay animation logic
//      (scale / alpha TransitionAnimation) that MUST be referenced when
//      implementing overlay animation for the new path (TO-DO).
//
//   2. ModalWindowSceneContext contains the platform-window vs overlay
//      selection logic (environment.modalSessionUsingPlatformWindow branch)
//      that is also needed as a reference for the TO-DO overlay mode work.
//
// Do NOT use ModalWindowScene or ModalWindowSceneContext in new code.
// Remove this file once overlay animation is ported to WindowController.

enum ModalResponse {
    case dismissed   // dismiss() was called programmatically
    case userAction  // closed by user action (e.g. gesture, close button)
    case byParent    // closed because the parent modal was dismissed
    case cancelled   // never shown because it was cancelled before being initiated
}

struct ModalWindowScene<Content>: _PrimitiveScene where Content: View {
    let content: ()->Content

    fileprivate var _content: Content { content() }

    static func _makeScene(scene: _GraphValue<Self>, inputs: _SceneInputs) -> _SceneOutputs {
        guard let graph = AttributeGraph.current else {
            fatalError("ModalWindowScene._makeScene requires AG context")
        }
        let context = ModalWindowSceneContext<Content>(graph: scene, inputs: inputs)
        graph.makeSideEffectRule { [context] in _ = context }
        return _SceneOutputs(preferences: PreferencesOutputs())
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
class ModalWindowSceneContext<Content>: @unchecked Sendable where Content: View {
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
        let window: ModalWindowController<Content>
        weak var parentController: WindowController?
        weak var modalWindow: (any PlatformWindow)?
        var windowOffset: CGPoint
        var windowSize: CGSize = .zero
        var activateFirstTime: Bool = true
        var filter: GraphicsContext.Filter?
        var transition: TransitionAnimation? = nil
        var onDismiss: ((ModalResponse) -> Void)? = nil
    }
    private var modalContext: _ModalContext? = nil

    private var window: ModalWindowController<Content>? {
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
    
    // Stored at _makeScene time.
    private let contentGraph: _GraphValue<Content>
    private let inputs: _SceneInputs

    var windowContextKey: AnyHashable {
        // AGAttribute is a value type. Use it directly, not via AnyObject boxing.
        // ObjectIdentifier(x as AnyObject) creates a new heap object each call, producing an unstable key.
        AnyHashable(contentGraph._attribute.identifier)
    }

    private var environment: EnvironmentValues {
        inputs.base.cachedEnvironment.value.environment.value
    }

    init(graph: _GraphValue<Scene>, inputs: _SceneInputs) {
        self.contentGraph = graph[\._content]
        self.inputs = inputs
        self.modalContext = nil
    }

    fileprivate func onViewLoaded() {
    }

    fileprivate func onViewLayoutChanged() {
        guard let window = self.window else {
            fatalError("ModalWindowContext: Invalid window!")
        }
        guard let layoutComputer = window.viewGraph.rootLayoutComputer else {
            fatalError("ModalWindowContext: rootLayoutComputer not set. AG wiring incomplete!")
        }

        let padding: CGFloat = 4
        var windowSize = layoutComputer.value.sizeThatFits(.unspecified)
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
                    if let parentWindow = self.modalContext?.parentController?.window {
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
            layoutComputer.value.place(at: center,
                                       anchor: .center,
                                       proposal: ProposedViewSize(windowSize))

            // Center the modal overlay in the parent window.
            if let parentSize = self.modalContext?.parentController?.cachedContentSize {
                self.modalContext?.windowOffset = CGPoint(
                    x: (parentSize.width - windowSize.width) * 0.5,
                    y: (parentSize.height - windowSize.height) * 0.5)
            }
        }
    }

    fileprivate func onWindowClosed() {
        // Platform window was closed by user action. Extract and clear
        // the callback before tearDownModal() is called.
        let onDismiss = self.modalContext?.onDismiss
        self.modalContext?.onDismiss = nil
        tearDownModal()
        onDismiss?(.userAction)
    }

    @MainActor
    func present(in parentController: WindowController,
                 withAnimation: Bool,
                 onDismiss: ((ModalResponse) -> Void)? = nil) -> Bool {
        present(in: parentController, withAnimation: withAnimation,
                alertDismissAction: nil, onDismiss: onDismiss)
    }

    @MainActor
    func present(in parentController: WindowController,
                 withAnimation: Bool,
                 alertDismissAction: (() -> Void)?,
                 onDismiss: ((ModalResponse) -> Void)? = nil) -> Bool {
        if modalContext != nil {
            modalContext?.activateFirstTime = true
            return true
        }

        // Read environment to decide platform vs overlay.
        let usePlatformModal = environment.modalSessionUsingPlatformWindow

        let windowKey = WindowKey(namespace: .app, sceneID: SceneID(Content.self, index: 0))
        let window = ModalWindowController<Content>(
            content: contentGraph,
            sceneContext: self,
            windowKey: windowKey)

        var ctx = _ModalContext(
            window: window,
            parentController: parentController,
            windowOffset: .zero,
            windowSize: .zero
        )
        ctx.onDismiss = onDismiss

        if usePlatformModal, let hostPlatformWindow = parentController.window {
            guard hostPlatformWindow.canPresentModalWindow else {
                Log.error("ModalWindow: platform does not support modal windows")
                return false
            }
            guard let modal = window.makeWindow() else {
                Log.error("ModalWindow: failed to create modal platform window")
                return false
            }
            modal.contentSize = CGSize(width: 10, height: 10)
            modal.origin = .zero
            ctx.modalWindow = modal

            modal.addEventObserver(self) { [weak self] (event: WindowEvent) in
                guard let self else { return }
                switch event.type {
                case .created: break
                case .closed:  self.onWindowClosed()
                default:       break
                }
            }
            window.sharedContext.alertDismissAction = alertDismissAction
            // modalContext must be set before addModalChild: _activateModal fires
            // attachWindow synchronously, which reads modalContext?.modalWindow.
            self.modalContext = ctx
            parentController.addModalChild(window, session: .legacy) { [weak self] attach in
                guard let attach else { return }
                if let w = self?.modalContext?.modalWindow {
                    attach(w)
                }
            }
            return true
        } else {
            // Overlay mode.
            let shadow = GraphicsContext.Filter.shadow(radius: 8.0, x: 0, y: 0)
            ctx.filter = shadow
            if withAnimation {
                ctx.transition = TransitionAnimation(
                    duration: transitionDuration,
                    configuration: transitionPresentAnimation)
            }
            let contentScale = parentController.window?.contentScaleFactor ?? 1.0
            window.sharedContext.contentScaleFactor = contentScale
            window.sharedContext.alertDismissAction = alertDismissAction
            // modalContext must be set before addModalChild (same reason as platform path).
            self.modalContext = ctx
            parentController.addModalChild(window, session: .legacy)  // overlay: no attachWindow needed
            return true
        }
    }

    func dismiss(withAnimation: Bool) {
        guard let context = self.modalContext else { return }

        // Remove the onDismiss callback before dismissing so that
        // onModalSessionDismissed() does not trigger it. .dismissed
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
        if let host = context.parentController {
            // detach without triggering session callbacks. Caller handles response.
            host.detachModalChild(context.window)
        }
        let parentWindow = context.parentController?.window
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
        context.window.sharedContext.alertDismissAction = nil
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

    var isAnimating: Bool { modalContext?.transition != nil }

    // MARK: - Drawing (called by ModalWindowController.drawFrame in overlay mode)

    func drawModalBackground(offset: CGPoint, with context: GraphicsContext) {
        guard let ctx = modalContext, let frame = modalWindowFrame() else { return }
        let progress = animationProgress
        let alpha = valueForProgress(progress, key: .alpha)

        // Dim the parent window behind the modal.
        if let parentController = ctx.parentController {
            let parentBounds = CGRect(origin: .zero,
                                     size: parentController.cachedContentSize)
            context.fill(Path(parentBounds), with: .color(.black.opacity(0.3 * alpha)))
        }

        let modal = frame.offsetBy(dx: offset.x, dy: offset.y)
        let scale = valueForProgress(progress, key: .scale)
        let center = CGPoint(x: modal.midX, y: modal.midY)

        var ctx2 = context
        ctx2.opacity = alpha
        ctx2.translateBy(x: center.x, y: center.y)
        ctx2.scaleBy(x: scale, y: scale)
        ctx2.translateBy(x: -center.x, y: -center.y)

        let path = RoundedRectangle(cornerRadius: 5).path(in: modal)
        if let filter = ctx.filter {
            var fc = ctx2; fc.addFilter(filter)
            fc.fill(path, with: .color(.white))
        } else {
            ctx2.fill(path, with: .color(.white))
        }
        ctx2.stroke(path, with: .color(.black.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 1))
    }

    // drawBody: closure that draws the window's actual display list.
    func drawModalContent(offset: CGPoint, with context: GraphicsContext,
                          drawBody: (CGPoint, GraphicsContext) -> Void) {
        guard let ctx = modalContext, let frame = modalWindowFrame() else { return }
        let progress = animationProgress
        let alpha = valueForProgress(progress, key: .alpha)
        let scale = valueForProgress(progress, key: .scale)
        let modal = frame.offsetBy(dx: offset.x, dy: offset.y)
        let center = CGPoint(x: modal.midX, y: modal.midY)

        var context = context
        context.opacity = alpha
        context.translateBy(x: center.x, y: center.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -center.x, y: -center.y)

        let contentOffset = ctx.windowOffset + offset
        if alpha < 1.0 {
            context.drawLayer { ctx in drawBody(contentOffset, ctx) }
        } else {
            drawBody(contentOffset, context)
        }
    }

    func drawModalOverlay(offset: CGPoint, with context: GraphicsContext) {}

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

// WindowController subclass for modal windows.
private class ModalWindowController<Content: View>: WindowController, @unchecked Sendable {
    override var style: PlatformWindowStyle { [.autoResize] }

    private weak var sceneContext: ModalWindowSceneContext<Content>?

    init(content: _GraphValue<Content>,
         sceneContext: ModalWindowSceneContext<Content>,
         windowKey: WindowKey) {
        super.init(content: content, scene: windowKey)
        self.sceneContext = sceneContext
    }

    override func onViewLoaded()        { sceneContext?.onViewLoaded() }
    override func onViewLayoutUpdated() { sceneContext?.onViewLayoutChanged() }
    override func onWindowClosing(_: any PlatformWindow) { sceneContext?.onWindowClosed() }

    // Overlay mode: apply animation transform then draw content.
    override func drawFrame(offset: CGPoint, _ context: GraphicsContext) {
        guard let scene = sceneContext else {
            super.drawFrame(offset: offset, context)
            return
        }
        scene.drawModalBackground(offset: offset, with: context)
        scene.drawModalContent(offset: offset, with: context) {
            super.drawFrame(offset: $0, $1)
        }
        scene.drawModalOverlay(offset: offset, with: context)
    }

    // Input is blocked during animation.
    override func handleMouseEvent(event: MouseEvent) -> Bool {
        guard sceneContext?.isAnimating == false else { return true }
        return super.handleMouseEvent(event: event)
    }

    // Forward modal session callbacks to the scene context.
    override func onModalSessionInitiated() {
        sceneContext?.onModalSessionInitiated()
    }
    override func onModalSessionDismissedByUser()   { sceneContext?.onModalSessionDismissedByUser() }
    override func onModalSessionDismissedByParent() { sceneContext?.onModalSessionDismissedByParent() }
    override func onModalSessionCancelled()         { sceneContext?.onModalSessionCancelled() }
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
