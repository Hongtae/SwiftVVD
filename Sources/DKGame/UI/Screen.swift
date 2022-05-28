import Foundation


public class Screen {
    private var _frame: Frame? = nil
    public var frame: Frame? {
        get { synchronizedBy(locking: self.propertyLock) { _frame } }
        set { synchronizedBy(locking: self.propertyLock) { _frame = newValue } }
    }

    public var window: Window? {
        didSet {
            if window !== oldValue {
                oldValue?.removeEventObserver(self)

                if let window = window {
                    let swapChain = commandQueue?.makeSwapChain(target: window)
                    let scaleFactor = window.contentScaleFactor
                    let contentBounds = window.contentBounds
                    let activated = window.activated
                    let visible = window.visible

                    window.addEventObserver(self) {
                        [weak self](event: WindowEvent) in
                        if let self = self, self.window === event.window {
                            self.processWindowEvent(event)
                        }
                    }
                    window.addEventObserver(self) {
                        [weak self](event: KeyboardEvent) in
                        if let self = self, self.window === event.window {
                            self.processKeyboardEvent(event)
                        }
                    }
                    window.addEventObserver(self) {
                        [weak self](event: MouseEvent) in
                        if let self = self, self.window === event.window {
                            self.processMouseEvent(event)
                        }
                    }

                    synchronizedBy(locking: self.propertyLock) {
                        self.swapChain = swapChain
                        self._resolution = CGSize(width: contentBounds.width * scaleFactor,
                                                  height: contentBounds.height * scaleFactor)
                        self._contentScaleFactor = scaleFactor
                        self.activated = activated
                        self.visible = visible
                    }
                } else {
                    synchronizedBy(locking: self.propertyLock) {
                        self.swapChain = nil
                        self.activated = false
                        self.visible = false
                    }
                }
            }
        }
    }

    private var _resolution: CGSize = .zero
    public var resolution: CGSize {
        get { synchronizedBy(locking: self.propertyLock) { _resolution } }
    }

    private var _contentScaleFactor: CGFloat = 1.0
    public var contentScaleFactor: CGFloat {
        get { synchronizedBy(locking: self.propertyLock) { _contentScaleFactor } }
    }

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

    private typealias ThreadTask = ()->Void
    private var threadTasks: [ThreadTask] = []

    private var threadCond = NSCondition()
    private var threadAlive = AtomicNumber32(0)
    private var propertyLock = SpinLock()

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

        let threadProc = { [weak self]() in

            let threadCond = self!.threadCond       // copy reference
            let threadAlive = self!.threadAlive     // copy reference

            Log.info("Screen render thread start.")

            var tickCounter = TickCounter()

            synchronizedBy(locking: threadCond) {
                threadAlive.store(1)
                threadCond.broadcast()
            }

            let frameUpdateCounter = AtomicNumber64(0)
            
            mainLoop: while true {
                guard let self = self else { break }
                
                let executeTask: () -> Bool = {
                    let task: ThreadTask? = synchronizedBy(locking: self.propertyLock) {
                        if let t = self.threadTasks.first {
                            self.threadTasks.remove(at: 0)
                            return Optional(t)
                        }
                        return nil
                    }
                    if let task = task {
                        task()
                        return true
                    }
                    return false
                }

                var frame: Frame? = nil
                var swapChain: SwapChain? = nil
                var visible = false
                var suspended = false
                var frameInterval: Double = 1.0 / 60.0
                var numTasksExecuted = 0
                
                synchronizedBy(locking: self.propertyLock) {
                    frame = self._frame
                    swapChain = self.swapChain

                    visible = self.visible
                    suspended = self.suspended

                    frameInterval = self.activated ? self.activeFrameInterval : self.inactiveFrameInterval
                }

                let delta = tickCounter.reset()
                let tick = tickCounter.timestamp
                let date = Date(timeIntervalSinceNow: 0)

                if let frame = frame, swapChain != nil {
                    if frame.loaded == false {
                        frame.loadHierarchy(screen: self, resolution: self.resolution)
                    }
                    if let dispatchQueue = self.dispatchQueue {
                        assert(frameUpdateCounter.load() == 0)
                        frameUpdateCounter.increment()
                        frame.updateHierarchyAsync(queue: dispatchQueue,
                                                   counter: frameUpdateCounter,
                                                   tick: tick,
                                                   delta: delta,
                                                   date: date)
                        while frameUpdateCounter.load() != 0 {
                            if executeTask() {
                                numTasksExecuted += 1
                            } else {
                                threadYield()
                            }
                        }
                    } else {
                        frame.updateHierarchy(tick: tick, delta: delta, date: date)
                    }
                    // draw!
                    if visible {
                        frame.redraw()
                        if frame.draw() {
                            swapChain?.present()
                        }
                    }
                }

                if numTasksExecuted == 0 && executeTask() {
                    numTasksExecuted += 1
                }
                
                while tickCounter.elapsed < frameInterval {
                    if executeTask() {
                        numTasksExecuted += 1
                    } else {
                        if suspended {
                            Thread.sleep(forTimeInterval: 0.01)
                        } else {
                            threadYield()
                        }
                    }
                }
            }

            synchronizedBy(locking: threadCond) {
                threadAlive.store(0)
                threadCond.broadcast()
            }
        }

        Thread.detachNewThread(threadProc)
        synchronizedBy(locking: threadCond) {
            while self.threadAlive.load() == 0 {
                self.threadCond.wait()
            }
        }
        Log.debug("Screen created.")
    }

    public convenience init(dispatchQueue: DispatchQueue? = nil) {
        self.init(graphicsDeviceContext: nil, audioDeviceContext: nil, dispatchQueue: dispatchQueue)
    }

    deinit {
        if let window = self.window {
            window.removeEventObserver(self)
        }
        // Wait for the render thread to be terminated.
        synchronizedBy(locking: self.threadCond) {
            while self.threadAlive.load() != 0 {
                self.threadCond.wait()
            }
        }
        Log.debug("Screen destoryed.")
    }

    public func makeCanvas() -> Canvas? {
        var canvas: Canvas? = nil
        if let swapChain = swapChain {
            let rpd = swapChain.currentRenderPassDescriptor()
            if let renderTarget = rpd.colorAttachments.first?.renderTarget {
                let width = Int(renderTarget.width)
                let height = Int(renderTarget.height)
                let viewport = CGRect(x: 0, y: 0, width: width, height: height)

                if let commandBuffer = commandQueue?.makeCommandBuffer() {
                    canvas = Canvas(commandBuffer: commandBuffer, renderTarget: renderTarget)
                    canvas!.viewport = viewport
                    canvas!.contentBounds = viewport
                }
            }
        }
        return canvas
    }

    private func postCommand(_ task: @escaping ThreadTask) {
        synchronizedBy(locking: self.propertyLock) {
            self.threadTasks.append(task)
        }
    }

    public func setKeyFrame(forDeviceId: Int, frame: Frame?) -> Bool { false }
    public func removeKeyFrame(forDeviceId: Int, frame: Frame?) -> Bool { false }
    public func keyFrame(forDeviceId: Int) -> Frame? { nil }

    public func setFocusFrame(forDeviceId: Int, frame: Frame?) -> Bool { false }
    public func removeFocusFrame(forDeviceId: Int, frame: Frame?) -> Bool { false }
    public func focusFrame(forDeviceId: Int) -> Frame? { nil }

    public func removeKeyFrameForAnyDevices(frame: Frame?) {}
    public func removeFocusFrameForAnyDevices(frame: Frame?) {}

    public func removeAllKeyFramesForAnyDevices() {}
    public func removeAllFocusFramesForAnyDevices() {}

    public func hoverFrame(forDeviceId: Int) -> Frame? { nil }
    public func leaveHoverFrame(_ frame: Frame?) {}

    public func windowToScreen(point: CGPoint) -> CGPoint { point }
    public func screenToWindow(point: CGPoint) -> CGPoint { point }
    public func windowToScreen(size: CGSize) -> CGSize { size }
    public func screenToWindow(size: CGSize) -> CGSize { size }
    public func windowToScreen(rect: CGRect) -> CGRect { rect }
    public func screenToWindow(rect: CGRect) -> CGRect { rect }

    public func processKeyboardEvent(_: KeyboardEvent) {}
    public func processMouseEvent(_: MouseEvent) {}
    public func processWindowEvent(_ event: WindowEvent) {

        Log.debug("Screen.\(#function) event:\(event)")

        switch event.type {
        case .resized:
            let scaleFactor = event.contentScaleFactor
            let resolution = CGSize(width: event.contentBounds.width * scaleFactor,
                                    height: event.contentBounds.height * scaleFactor)
            synchronizedBy(locking: self.propertyLock) {
                self._contentScaleFactor = scaleFactor
                self._resolution = resolution
            }
            self.postCommand { self.frame?.updateResolution() }

        case .hidden, .minimized:
            synchronizedBy(locking: self.propertyLock) { visible = false }
        case .shown:
            synchronizedBy(locking: self.propertyLock) { visible = true }
            self.postCommand { self.frame?.redraw() }
        case .activated:
            synchronizedBy(locking: self.propertyLock) { activated = true }
        case .inactivated:
            synchronizedBy(locking: self.propertyLock) { activated = false }
        case .update:
            self.postCommand { self.frame?.redraw() }
        default:
            break
        }
    }
}
