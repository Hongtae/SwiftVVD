//
//  File: WindowContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

typealias PlatformWindow = VVD.Window
typealias PlatformWindowStyle = VVD.WindowStyle

// WindowContext  OS-level window, SwapChain, and render loop.
// Does not know about View content, AG graph, or aux/modal windows.
// Completely decoupled from WindowController: no back-reference.
class WindowContext: @unchecked Sendable {
    private(set) var swapChain: SwapChain?
    private(set) var window: (any PlatformWindow)?
    private var task: Task<Void, Never>?

    struct State {
        var visible = false
        var activated = false
        var suspended = false  // render loop paused; window/swapChain kept alive
        var contentScaleFactor: CGFloat = 1.0
        var frame: CGRect = .zero
        var bounds: CGRect = .zero
        var surfaceRevision: Int = 0
    }
    struct Configuration {
        var activeFrameInterval = 1.0 / 60.0
        var inactiveFrameInterval = 1.0 / 30.0
        var drawEveryFrames: Bool = true
        var backgroundColor = BackendColor(
            rgba8: .init(r: 255, g: 255, b: 241, a: 255)
        )
        var drawDebugInfo: _DrawDebug.Info = []
    }

    var state: State {
        stateConfig.withLock { $0.state }
    }
    var config: Configuration {
        get { stateConfig.withLock { $0.config } }
        set { stateConfig.withLock { $0.config = newValue } }
    }

    private let stateConfig = Mutex<(state: State, config: Configuration)>((state: State(), config: Configuration()))

    // Set by WindowController.makeWindow(); shared with all GraphicsContexts created in drawFrame.
    let sceneResources: SceneResources

    // Called each frame from the render loop.

    // WithGraphicsContext: first Bool is whether to draw (present) the frame or not, second parameter is the drawing closure.
    // If you use this with load resources, you need to set the first Bool to false.(no present)
    typealias WithGraphicsContext = (Bool, (GraphicsContext)->Void)->Void // needPresent, handler
    var updateFrame: ((UInt64, Double, Date,    // tick, delta, date
                       CGSize, Bool,            // contentSize, shouldDrawFrame
                       WithGraphicsContext) -> Void)?
    // Called while the render task is waiting for the next frame. The hook owns
    // its own yield/wait policy; when nil, the render loop yields directly.
    var onIdle: (() async -> Void)?
    // Returns a host-requested frame interval after view graph update work has
    // refreshed scheduling state for the current frame.
    var preferredFrameInterval: (() -> Double?)?
    // Called once when the render task exits, using the latest hook observed
    // while the WindowContext was still retained by the loop.
    var onFinalize: (() -> Void)?

    init(sceneResources: SceneResources) {
        self.sceneResources = sceneResources
    }

    deinit {
        self.task?.cancel()
        self.swapChain = nil
        self.window = nil
    }

    // Creates the OS window and SwapChain if not already present.
    // The caller (WindowController) passes itself as delegate and registers
    // its own event observers after this returns.
    @MainActor
    func makeWindow(title: String, style: PlatformWindowStyle, delegate: (any WindowDelegate)?) -> (any PlatformWindow)? {
        if self.window == nil {

            self.task?.cancel()
            self.task = nil
            self.swapChain = nil

            if let window = VVD.makeWindow(name: title,
                                           style: style,
                                           delegate: delegate) {
                if let graphicsDevice = appContext?.graphicsDeviceContext {
                    if GraphicsContext.cachePipelineContext(graphicsDevice) == false {
                        Log.error("Failed to cache GraphicsPipelineStates")
                    }
                    if let swapChain = graphicsDevice.renderQueue()?.makeSwapChain(target: window) {
                        self.stateConfig.withLock {
                            $0.state.frame = window.windowFrame.standardized
                            $0.state.bounds = window.contentBounds.standardized
                            $0.state.contentScaleFactor = window.contentScaleFactor
                            $0.state.visible = window.visible
                            $0.state.activated = window.activated
                        }
                        self.window = window

                        window.addEventObserver(self) {
                            [weak self](event: WindowEvent) in
                            if let self = self { self.onWindowEvent(event: event) }
                        }

                        self.swapChain = swapChain
                        self.task = self.runUpdateTask()
                    } else {
                        Log.error("Failed to create swapChain.")
                    }
                } else {
                    Log.error("GraphicsDeviceContext is nil")
                }
            }
        }
        return self.window
    }

    private func runUpdateTask() -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { @Sendable [weak self] in
            var onFinalize = self?.onFinalize
            defer {
                onFinalize?()
                Log.info("WindowContext update task is finished.")
            }
            Log.info("WindowContext update task is started.")

            var timestamp = DispatchTime.now()

            let elapsed = {
                let now = DispatchTime.now()
                let delta = Double(now.uptimeNanoseconds - timestamp.uptimeNanoseconds)
                return delta * 0.000_000_001
            }
            let resetTimestamp = {
                let now = DispatchTime.now()
                let delta = Double(now.uptimeNanoseconds - timestamp.uptimeNanoseconds)
                timestamp = now
                return delta * 0.000_000_001
            }

            var contentSize: CGSize = .zero
            var contentScaleFactor: CGFloat = 1
            var renderTargets: GraphicsContext.RenderTargets? = nil

            var surfaceRevision: Int = 0
            var shouldDrawFrame = true
            var additionalDeltaTimes: Double = 0.0

            var debugFrameCount: UInt64 = 1

            mainLoop: while true {
                guard let self = self else { break }
                if Task.isCancelled { break }
                onFinalize = self.onFinalize

                let (state, config) = self.stateConfig.withLock {
                    ($0.state, $0.config)
                }

                if contentSize != state.bounds.size {
                    contentSize = state.bounds.size
                    shouldDrawFrame = true
                }
                if contentScaleFactor != state.contentScaleFactor {
                    contentScaleFactor = state.contentScaleFactor
                    sceneResources.contentScaleFactor = contentScaleFactor
                    shouldDrawFrame = true
                }
                if surfaceRevision != state.surfaceRevision {
                    surfaceRevision = state.surfaceRevision
                    shouldDrawFrame = true
                }
                if renderTargets == nil {
                    shouldDrawFrame = true
                }
                if config.drawEveryFrames {
                    shouldDrawFrame = true
                }

                let delta = resetTimestamp() + additionalDeltaTimes
                let tick = timestamp.uptimeNanoseconds
                let date = Date(timeIntervalSinceNow: 0)
                additionalDeltaTimes = delta

                if let swapChain {
                    var renderPass = swapChain.currentRenderPassDescriptor()
                    let device = swapChain.commandQueue.device
                    let backBuffer = renderPass.colorAttachments[0].renderTarget!

                    let dim = { (tex: Texture) in (tex.width, tex.height, tex.depth) }

                    if let renderTargets, dim(renderTargets.backdrop) == dim(backBuffer) {
                    } else {
                        renderTargets = GraphicsContext.RenderTargets(
                            device: device,
                            width: backBuffer.width,
                            height: backBuffer.height)
                    }

                    renderPass.colorAttachments[0].clearColor = .clear

                    if let updateFrame {
                        var present = false
                        var commandBuffer: CommandBuffer? = nil
                        var graphicsContext: GraphicsContext? = nil

                        let sceneResources = self.sceneResources
                        let withGC = { (needPresent: Bool, handler: (GraphicsContext)->Void) in
                            if let renderTargets {
                                if commandBuffer == nil {
                                    commandBuffer = swapChain.commandQueue.makeCommandBuffer()
                                }
                                if let commandBuffer, graphicsContext == nil {
                                    graphicsContext = GraphicsContext(
                                        sceneResources: sceneResources,
                                        environment: EnvironmentValues(),
                                        viewport: CGRect(x: 0, y: 0,
                                                         width: backBuffer.width,
                                                         height: backBuffer.height),
                                        contentOffset: .zero,
                                        contentScaleFactor: contentScaleFactor,
                                        renderTargets: renderTargets,
                                        commandBuffer: commandBuffer)

                                    if let graphicsContext {
                                        graphicsContext.clear(with: .clear)
                                    } else {
                                        fatalError("Failed to create GraphicsContext.")
                                    }
                                }
                                if let graphicsContext {
                                    handler(graphicsContext)
                                    if needPresent {
                                        present = true
                                    }
                                }
                            }
                        }

                        let debugDrawInfo = config.drawDebugInfo
                        if debugDrawInfo.isEmpty == false {
                            shouldDrawFrame = true
                        }

                        updateFrame(tick, delta, date, contentSize, shouldDrawFrame, withGC)
                        additionalDeltaTimes = 0.0

                        if debugDrawInfo.isEmpty == false {
                            withGC(true) { context in
                                var offset = CGPoint(x: 5, y: 5)
                                let drawText = { (text: Text) in
                                    let resolvedText = context.resolve(text)
                                    context.draw(resolvedText, at: offset, anchor: .topLeading)
                                    offset.y += resolvedText.measure().height
                                }
                                if debugDrawInfo.contains(.frameInfo) {
                                    if config.drawEveryFrames {
                                        let d = max(delta, 0.001001) // up to 999
                                        drawText(Text(String(format: "%.1f FPS (%f)", 1.0 / d, delta)))
                                    } else {
                                        drawText(Text(String(format: "frame: %llu", debugFrameCount)))
                                    }
                                }
                                if debugDrawInfo.contains(.thread) {
                                    drawText(Text("thread: \(Platform.currentThreadID())"))
                                }
                                if debugDrawInfo.contains(.queue) {
                                    drawText(Text("dispatch-queue: \(isMainQueue() ? "main" : "global")"))
                                }
                                if debugDrawInfo.contains(.appState) {
                                    drawText(Text("app-active: \(appContext?.isActive ?? false)"))
                                }
                                if debugDrawInfo.contains(.windowState) {
                                    drawText(Text("foreground: \(state.activated)"))
                                }
                            }
                        }
                        
                        if present {
                            if let context = graphicsContext {
                                if let rp = context.beginRenderPass(descriptor: renderPass,
                                                                    viewport: context.viewport) {
                                    context.encodeDrawTextureCommand(
                                        renderPass: rp,
                                        texture: context.backdrop,
                                        frame: state.bounds,
                                        textureFrame: context.viewport,
                                        blendState: .opaque,
                                        color: .white)
                                    rp.end()
                                } else {
                                    Log.error("beginRenderPass failed.")
                                }  
                            } else {
                                if let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPass) {
                                    encoder.endEncoding()
                                }
                            }
                        }
                        if let commandBuffer {
                            commandBuffer.commit()

                            if present {
                                _=swapChain.present()

                                shouldDrawFrame = false
                                debugFrameCount += 1
                            }
                        }
                    } else {
                        let clearColor = config.backgroundColor
                        if let commandBuffer = swapChain.commandQueue.makeCommandBuffer() {
                            renderPass.colorAttachments[0].clearColor = clearColor.anyColor
                            renderPass.colorAttachments[0].loadAction = .clear
                            if let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) {
                                encoder.endEncoding()
                            }
                            commandBuffer.commit()
                            _=swapChain.present()
                        }
                    }
                }

                let configuredFrameInterval = state.activated
                    ? config.activeFrameInterval
                    : config.inactiveFrameInterval
                let frameInterval = Self.resolvedFrameInterval(
                    configured: configuredFrameInterval,
                    requested: self.preferredFrameInterval?()
                )
                let timeForBusyWait = state.activated ? 0.001 : 0.0

                repeat {
                    if Task.isCancelled { break mainLoop }
                    if let onIdle = self.onIdle {
                        await onIdle()
                    } else {
                        await Task.yield()
                    }
                } while elapsed() < frameInterval - timeForBusyWait

                // busy waiting, remaining time is too short to yield.
                while elapsed() < frameInterval {
                    if Task.isCancelled { break mainLoop }
                    Platform.threadYield()
                }
            }
        }
    }

    static func resolvedFrameInterval(
        configured: Double,
        requested: Double?
    ) -> Double {
        guard let requested,
              requested.isFinite,
              requested > 0 else {
            return configured
        }
        return min(configured, requested)
    }

    // WindowEvent observer: updates internal OS state only.
    // WindowController receives the same events via its own observer (registered in makeWindow).
    @MainActor
    func onWindowEvent(event: WindowEvent) {
        if event.window !== self.window { return }
        Log.debug("WindowContext.onWindowEvent: \(event)")

        switch event.type {
        case .closed:
            self.task?.cancel()
            self.window?.removeEventObserver(self)
            self.swapChain = nil
            self.window = nil
            self.task = nil

        case .created:
            self.stateConfig.withLock {
                $0.state.frame = event.windowFrame.standardized
                $0.state.bounds = event.contentBounds.standardized
                $0.state.contentScaleFactor = event.contentScaleFactor
                // Reset to 1 (not +=1) so the render loop, which starts at 0, always sees a mismatch on first frame.
                $0.state.surfaceRevision = 1
            }
        case .hidden:
            self.stateConfig.withLock {
                $0.state.visible = false
                $0.state.activated = false
            }
        case .shown:
            self.stateConfig.withLock {
                $0.state.visible = true
            }
        case .activated:
            self.stateConfig.withLock {
                $0.state.visible = true
                $0.state.activated = true
            }
        case .inactivated:
            self.stateConfig.withLock {
                $0.state.activated = false
            }
        case .minimized:
            self.stateConfig.withLock {
                $0.state.activated = false
                $0.state.visible = false
            }
        case .moved, .resized:
            self.stateConfig.withLock {
                $0.state.frame = event.windowFrame.standardized
                $0.state.bounds = event.contentBounds.standardized
                $0.state.contentScaleFactor = event.contentScaleFactor
                if event.type == .resized {
                    $0.state.surfaceRevision += 1
                }
            }
        case .geometryInvalidated:
            break
        case .resizeBegan, .resizeEnded:
            break
        case .update:
            break
        }
    }
}
