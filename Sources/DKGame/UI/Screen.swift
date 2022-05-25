import Foundation

public class Screen {

    public var frame: Frame? = nil
    public var window: Window? = nil
    public var resolution: CGSize           { .zero }
    public var contentScaleFactor: CGFloat  { 1.0 }

    public private(set) var swapChain: SwapChain?
    public private(set) var dispatchQueue: DispatchQueue?
    public private(set) var graphicsDeviceContext: GraphicsDeviceContext?
    public private(set) var audioDeviceContext: AudioDeviceContext?

    private let activeFrameInterval = 1.0 / 60.0
    private let inactiveFrameInterval = 1.0 / 30.0

    private var activated = false
    private var visible = false

    private typealias ThreadTask = ()->Void
    private var threadTasks: [ThreadTask] = []

    private enum State: Int32 {
        case stopped = 0
        case suspended
        case running
    }
    private var runningState = AtomicNumber32(State.stopped.rawValue)
    private var threadCond = NSCondition()
    private var threadRunning = false
    private var propertyLock = SpinLock()
    private var tickCounter = TickCounter()
    public init(graphicsDeviceContext: GraphicsDeviceContext?, audioDeviceContext: AudioDeviceContext?, dispatchQueue: DispatchQueue?) {
        var graphicsDeviceContext = graphicsDeviceContext
        if graphicsDeviceContext == nil {
            graphicsDeviceContext = makeGraphicsDeviceContext()
        }
        self.graphicsDeviceContext = graphicsDeviceContext

        let threadProc = { [unowned self]() in
            synchronizedBy(locking: threadCond) {
                self.threadRunning = true
                threadCond.broadcast()
            }

            let state: () -> State = {
                switch self.runningState.load() {
                case State.stopped.rawValue:    return State.stopped
                case State.suspended.rawValue:  return State.suspended
                default:                        return State.running
                }
            }

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

            let frameUpdateCounter = AtomicNumber64(0)

            mainLoop: while state() != .stopped {

                let fs: (Frame?, SwapChain?) = synchronizedBy(locking: propertyLock) { (self.frame, self.swapChain) }

                let delta = self.tickCounter.reset()
                let tick = self.tickCounter.timestamp
                let date = Date(timeIntervalSinceNow: 0)
                var frameDrawn  = false

                if state() == .running {
                    if let frame = fs.0, fs.1 != nil {
                        if let dispatchQueue = self.dispatchQueue {
                            assert(frameUpdateCounter.load() == 0)
                            frameUpdateCounter.increment()
                            frame.updateHierarchyAsync(queue: dispatchQueue,
                                                       counter: frameUpdateCounter,
                                                       tick: tick,
                                                       delta: delta,
                                                       date: date)
                            while frameUpdateCounter.load() != 0 {
                                if executeTask() == false {
                                    threadYield()
                                }
                            }
                        } else {
                            frame.updateHierarchy(tick: tick, delta: delta, date: date)
                        }
                        // draw!
                        if activated || visible {
                            // frame.draw()
                            frameDrawn = true
                        }
                    }
                }

                let interval = activated ? activeFrameInterval : inactiveFrameInterval
                while tickCounter.elapsed < interval {
                    if executeTask() == false {
                        switch state() {
                        case .running:      threadYield()
                        case .suspended:    Thread.sleep(forTimeInterval: 0.01)
                        case .stopped:
                            break mainLoop
                        }
                    }
                }
                
                if frameDrawn && state() == .running {
                    fs.1?.present()
                }
            }

            synchronizedBy(locking: threadCond) {
                self.threadRunning = false
                threadCond.broadcast()
            }
        }
        Thread.detachNewThread(threadProc)
    }

    public convenience init(dispatchQueue: DispatchQueue? = nil) {
        self.init(graphicsDeviceContext: nil, audioDeviceContext: nil, dispatchQueue: dispatchQueue)
    }

    deinit {
        self.runningState.store(State.stopped.rawValue)
        synchronizedBy(locking: threadCond) {
            while self.threadRunning {
                threadCond.wait()
            }
        }
    }

    public func makeCanvas() -> Canvas? {
        return nil
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

    public func processKeyboardEvent() {}
    public func processMouseEvent() {}
    public func processWindowEvent() {}
}
