import Foundation

@globalActor public actor ScreenActor: GlobalActor {
    public static let shared = ScreenActor()
}

@ScreenActor
public class Screen {
    public var frame: Frame? {
        didSet {
            Task {
                if frame !== oldValue {
                    self.keyboardCaptors.removeAll()
                    self.mouseCaptors.removeAll()
                    self.hoverFrames.removeAll()
                }
            }
        }
    }

    public var window: Window? {
        didSet {
            Task { @MainActor in
                if await window !== oldValue {
                    oldValue?.removeEventObserver(self)

                    if let window = await window {

                        let swapChain = await commandQueue?.makeSwapChain(target: window)
                        if swapChain == nil {
                            Log.err("Failed to create swapChain!")
                        }
                        let scaleFactor = window.contentScaleFactor
                        let contentBounds = window.contentBounds
                        let activated = window.activated
                        let visible = window.visible

                        window.addEventObserver(self) { [weak self](event: WindowEvent) in
                            if let self = self {
                                Task { @ScreenActor in
                                    if self.window === event.window {
                                        self.processWindowEvent(event)
                                    }
                                }
                            }
                        }
                        window.addEventObserver(self) { [weak self](event: KeyboardEvent) in
                            if let self = self {
                                Task { @ScreenActor in                      
                                    if self.window === event.window {
                                        self.processKeyboardEvent(event)
                                    }
                                }
                            }
                        }
                        window.addEventObserver(self) { [weak self](event: MouseEvent) in
                            if let self = self {
                                Task { @ScreenActor in
                                    if self.window === event.window {
                                        self.processMouseEvent(event)
                                    }
                                }
                            }
                        }

                        Task { @ScreenActor in
                            self.swapChain = swapChain
                            self.resolution = CGSize(width: contentBounds.width, height: contentBounds.height)
                            self.contentScaleFactor = scaleFactor
                            self.activated = activated
                            self.visible = visible
                            self.frame?.updateResolution()
                        }
                    } else {
                        Task { @ScreenActor in
                            self.swapChain = nil
                            self.activated = false
                            self.visible = false
                        }
                    }
                }
            }
        }
    }

    public var resolution: CGSize = .zero
    public var contentScaleFactor: CGFloat = 1.0

    private var swapChain: SwapChain?

    public private(set) var dispatchQueue: DispatchQueue?
    public private(set) var graphicsDeviceContext: GraphicsDeviceContext?
    public private(set) var audioDeviceContext: AudioDeviceContext?
    public private(set) var commandQueue: CommandQueue?

    private let activeFrameInterval = 1.0 / 60.0
    private let inactiveFrameInterval = 1.0 / 30.0

    private var activated = false
    private var visible = false
    private var suspended = false

    private var keyboardCaptors: [Int: Frame] = [:] // keyboard captors
    private var mouseCaptors: [Int: Frame] = [:]    // mouse captors
    private var hoverFrames: [Int: (frame: Frame, device: MouseEventDevice)] = [:]  // mouse hover frames

    public init(graphicsDeviceContext: GraphicsDeviceContext?,
                audioDeviceContext: AudioDeviceContext?,
                dispatchQueue: DispatchQueue?) {

        var graphicsDeviceContext = graphicsDeviceContext
        if graphicsDeviceContext == nil {
            graphicsDeviceContext = makeGraphicsDeviceContext(dispatchQueue: nil)
        }
        self.graphicsDeviceContext = graphicsDeviceContext
        self.commandQueue = self.graphicsDeviceContext?.renderQueue()

        Canvas.cachePipelineContext(graphicsDeviceContext!)

        Task.detached { @ScreenActor [weak self] in

            Log.info("Screen render task start.")

            var tickCounter = TickCounter()
            var frame: Frame? = nil

            var frameCount: UInt64 = 0

            mainLoop: while true {
                frameCount += 1

                // Log.info("RenderLoop: \(frameCount)")

                guard let self = self else { break }

                var swapChain: SwapChain? = nil
                var visible = false
                var suspended = false
                var frameInterval: Double = 1.0 / 60.0
                
                frame = self.frame
                swapChain = self.swapChain

                visible = self.visible
                suspended = self.suspended

                frameInterval = self.activated ? self.activeFrameInterval : self.inactiveFrameInterval

                let delta = tickCounter.reset()
                let tick = tickCounter.timestamp
                let date = Date(timeIntervalSinceNow: 0)

                if let frame = frame, swapChain != nil {
                    if frame.loaded == false {
                        frame.loadHierarchy(screen: self,
                                            resolution: self.resolution,
                                            scaleFactor: self.contentScaleFactor)
                    }

                    if suspended == false {
                        await frame.updateHierarchy(tick: tick, delta: delta, date: date)
                    }

                    // draw!
                    if visible {
                        frame.redraw()
                        if await frame.draw() {
                            swapChain?.present()
                        }
                    }
                } else {
                    // Log.info("Render Loop frame: \(frame), swapChain: \(swapChain)")
                }
                
                while tickCounter.elapsed < frameInterval {
                    await Task.yield()
                }
            }
            if let frame = frame {
                frame.unloadHierarchy()
            }
            Log.info("Screen render task has been terminated.")
        }
        Log.debug("Screen created.")
    }

    public convenience init() {
        self.init(graphicsDeviceContext: nil, audioDeviceContext: nil, dispatchQueue: nil)
    }

    deinit {
        self.window = nil
        self.frame = nil
        self.swapChain = nil
        self.commandQueue = nil
        self.graphicsDeviceContext = nil
        self.audioDeviceContext = nil

        Log.debug("Screen destoryed.")
    }

    public func makeCanvas() async -> Canvas? {
        if let swapChain = swapChain {
            let rpd = await swapChain.currentRenderPassDescriptor()
            if let renderTarget = rpd.colorAttachments.first?.renderTarget {
                let width = Int(renderTarget.width)
                let height = Int(renderTarget.height)
                let viewport = CGRect(x: 0, y: 0, width: width, height: height)

                if let commandBuffer = commandQueue?.makeCommandBuffer() {
                    let canvas = Canvas(commandBuffer: commandBuffer, renderTarget: renderTarget)
                    canvas.viewport = viewport
                    canvas.contentBounds = viewport
                    return canvas
                }
            }
        }
        return nil
    }

    public func captureKeyboard(frame: Frame?, forDeviceId: Int) -> Bool { false }
    public func releaseKeyboard(frame: Frame?, forDeviceId: Int) -> Bool { false }
    public func keyboardCaptor(forDeviceId: Int) -> Frame? { nil }

    public func captureMouse(frame: Frame?, forDeviceId: Int) -> Bool { false }
    public func releaseMouse(frame: Frame?, forDeviceId: Int) -> Bool { false }
    public func mouseCaptor(forDeviceId: Int) -> Frame? { nil }

    public func releaseAllKeyboardsCapturedBy(frame: Frame?) {}
    public func releaseAllMiceCapturedBy(frame: Frame?) {}

    public func releaseAllKeyboards() {}
    public func releaseAllMice() {}

    public func hoverFrame(forDeviceId: Int) -> Frame? { nil }
    public func leaveHoverFrame(_ frame: Frame?) {}

    public func windowToScreen(point: CGPoint) -> CGPoint { point }
    public func screenToWindow(point: CGPoint) -> CGPoint { point }
    public func windowToScreen(size: CGSize) -> CGSize { size }
    public func screenToWindow(size: CGSize) -> CGSize { size }
    public func windowToScreen(rect: CGRect) -> CGRect { rect }
    public func screenToWindow(rect: CGRect) -> CGRect { rect }

    public func processKeyboardEvent(_ event: KeyboardEvent) {
        // Log.debug("Screen.\(#function) event:\(event)")

        Task { @ScreenActor in
            if let captor = self.keyboardCaptor(forDeviceId: event.deviceId) {
                assert(captor.screen === self)
                _ = captor.processKeyboardEvent(event)
            }
        }
    }

    public func processMouseEvent(_ event: MouseEvent) {
        if event.type != .move {
            Log.debug("Screen.\(#function) event:\(event)")
        }

        Task { @ScreenActor in
            if let frame = self.frame {
                let res = Vector2(self.resolution)
                assert(res.x > 0.0 && res.y > 0.0)
                let scale = Vector2(frame.contentScale)
                assert(scale.x > 0.0 && scale.y > 0.0)

                // rescale vector
                let windowToRoot = AffineTransform2(linear: .init(scaleX: scale.x / res.x, scaleY: scale.y / res.y)).matrix3
                var pos = event.location.transformed(by: windowToRoot)
                var delta = event.delta.transformed(by: windowToRoot)

                if event.type == .move {
                    let hover: Frame?  = frame.findHoverFrame(at: pos)
                    var leave: Frame? = nil
                    if let fd = self.hoverFrames[event.deviceId] {
                        assert(fd.device == event.device)
                        leave = fd.frame
                    }

                    if hover !== leave {
                        if let hover = hover {
                            self.hoverFrames[event.deviceId] = (frame: hover, device: event.device)
                        } else {
                            self.hoverFrames[event.deviceId] = nil
                        }

                        if let leave = leave {
                            assert(leave.screen === self)
                            leave.handleMouseLeave(deviceId: event.deviceId, device: event.device)
                        }
                        if let hover = hover {
                            assert(hover.screen === self)
                            hover.handleMouseEnter(deviceId: event.deviceId, device: event.device)
                        }
                    }
                }

                if let captor = self.mouseCaptor(forDeviceId: event.deviceId) {
                    assert(captor.isDescendant(of: frame))
                    assert(captor.screen === self)

                    if captor !== frame {
                        let parent = captor.superframe!

                        // convert content-space to local frame space
                        var tm = frame.inverseContentTransform

                        // convert coordinates to target's parent space
                        tm = tm * parent.localFromRootTransform

                        // normalize to local space
                        tm = tm * captor.inverseTransform

                        // quantize to contents
                        let scale = Vector2(captor.contentScale)
                        assert(scale.x > 0.0 && scale.y > 0.0)
                        tm = tm * AffineTransform2(linear: .init(scaleX: scale.x, scaleY: scale.y)).matrix3

                        // calculate delta
                        let posInFrame = pos.transformed(by: tm)
                        let posInFrameOld = (pos - delta).transformed(by: tm)

                        pos = posInFrame
                        delta = posInFrame - posInFrameOld
                    }
                    _ = captor.processMouseEvent(event, position: pos, delta: delta, exclusive: true)
                } else {
                    if frame.bounds.contains(pos) {
                        _ = frame.processMouseEvent(event, position: pos, delta: delta, exclusive: false)
                    }
                }
            }
        }
    }

    public func processWindowEvent(_ event: WindowEvent) {
        Log.debug("Screen.\(#function) event:\(event)")

        switch event.type {
        case .resized:
            let scaleFactor = event.contentScaleFactor
            let resolution = CGSize(width: event.contentBounds.width,
                                    height: event.contentBounds.height)

            self.contentScaleFactor = scaleFactor
            self.resolution = resolution
            self.frame?.updateResolution()
        case .hidden, .minimized:
            self.visible = false
        case .shown:
            self.visible = true
            self.frame?.redraw()
        case .activated:
            self.activated = true
        case .inactivated:
            self.activated = false
        case .update:
            self.frame?.redraw()
        default:
            break
        }
    }
}
