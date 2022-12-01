//
//  File: Screen.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

@globalActor public actor ScreenActor: GlobalActor {
    public static let shared = ScreenActor()
}

@ScreenActor
public class Screen {
    public var frame: Frame? {
        didSet {
            if frame !== oldValue {
                self.keyboardCaptors.removeAll()
                self.mouseCaptors.removeAll()
                self.hoverFrames.removeAll()
            }
        }
    }

    public var window: Window? {
        didSet {
            if window !== oldValue {
                if window == nil { Log.debug("Screen.window is nil.") }

                let window = self.window
                let commandQueue = self.commandQueue

                Task { @MainActor in
                    oldValue?.removeEventObserver(self)

                    if let window = window {
                        let swapChain = commandQueue?.makeSwapChain(target: window)
                        if swapChain == nil {
                            Log.err("Failed to create swapChain!")
                        }

                        let scaleFactor = window.contentScaleFactor
                        let contentBounds = window.contentBounds
                        let activated = window.activated
                        let visible = window.visible

                        assert(contentBounds.width > 0.0 && contentBounds.height > 0.0)
                        assert(scaleFactor > 0.0)

                        Task { @ScreenActor in
                            self.swapChain = swapChain
                            self.resolution = contentBounds.size * scaleFactor
                            self.windowContentScaleFactor = scaleFactor
                            self.windowContentBounds = contentBounds
                            self.activated = activated
                            self.visible = visible
                            self.frame?.updateResolution()

                            Task { @MainActor in
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
                            }
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
    public var windowContentBounds: CGRect = .zero 
    public var windowContentScaleFactor: CGFloat = 1.0

    private var swapChain: SwapChain?

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

    private var task: Task<Void, Never>?

    public init(graphicsDeviceContext: GraphicsDeviceContext?,
                audioDeviceContext: AudioDeviceContext?) {

        self.graphicsDeviceContext = graphicsDeviceContext ?? makeGraphicsDeviceContext()
        self.audioDeviceContext = audioDeviceContext ?? makeAudioDeviceContext()
        self.commandQueue = self.graphicsDeviceContext?.renderQueue()

        Canvas.cachePipelineContext(self.graphicsDeviceContext!)

        self.task = .detached(priority: .userInitiated) { @ScreenActor [weak self] in
            numberOfThreadsToWaitBeforeExiting.increment()
            defer { numberOfThreadsToWaitBeforeExiting.decrement() }

            Log.info("Screen render task start.")

            var tickCounter = TickCounter()
            var frame: Frame? = nil

            mainLoop: while true {
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
                        await frame._loadHierarchy(screen: self,
                            resolution: self.resolution,
                            scaleFactor: self.windowContentScaleFactor)
                    }

                    if suspended == false {
                        await frame._updateHierarchy(tick: tick, delta: delta, date: date)
                    }

                    // draw!
                    if visible {
                        frame.redraw()
                        if frame._drawHierarchy() {
                            await swapChain?.present()
                        }
                    }
                }
                
                while tickCounter.elapsed < frameInterval {
                    if Task.isCancelled {
                        break mainLoop
                    }
                    await Task.yield()
                }
            }
            if let frame = frame {
                await frame._unloadHierarchy()
            }
            Log.info("Screen render task has been terminated.")
        }
        Log.debug("Screen created.")
    }

    public convenience init() {
        self.init(graphicsDeviceContext: nil, audioDeviceContext: nil)
    }

    deinit {
        self.task?.cancel()

        self.keyboardCaptors.removeAll()
        self.mouseCaptors.removeAll()

        self.window = nil
        self.frame = nil
        self.swapChain = nil
        self.commandQueue = nil
        self.graphicsDeviceContext = nil
        self.audioDeviceContext = nil

        Log.debug("Screen destoryed.")
    }

    public func makeCanvas() -> Canvas? {
        if let swapChain = swapChain {
            let rpd = swapChain.currentRenderPassDescriptor()
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

    public func captureKeyboard(frame: Frame?, forDeviceID deviceID: Int) -> Bool {
        let captor = self.keyboardCaptors[deviceID]
        if captor === frame {
            return true
        }

        if let frame = frame {
            if frame.canHandleKeyboard && frame.isDescendant(of: self.frame) {
                self.keyboardCaptors[deviceID] = frame
                if let captor = captor {
                    captor.handleKeyboardLost(deviceID: deviceID)
                }
                return true
            }
            return false
        }
        if let captor = captor {
            self.keyboardCaptors[deviceID] = nil
            captor.handleKeyboardLost(deviceID: deviceID)
        }
        return true
    }

    public func releaseKeyboard(frame: Frame?, forDeviceID deviceID: Int) -> Bool {
        if let captor = self.keyboardCaptors[deviceID], captor === frame {
            self.keyboardCaptors[deviceID] = nil
            captor.handleKeyboardLost(deviceID: deviceID)
            return true
        }
        return false
    }

    public func keyboardCaptor(forDeviceID deviceID: Int) -> Frame? {
        return self.keyboardCaptors[deviceID]
    }

    public func captureMouse(frame: Frame?, forDeviceID deviceID: Int) -> Bool {
        let captor = self.mouseCaptors[deviceID]
        if captor === frame {
            return true
        }

        if let frame = frame {
            if frame.canHandleMouse && frame.isDescendant(of: self.frame) {
                self.mouseCaptors[deviceID] = frame
                if let captor = captor {
                    captor.handleMouseLost(deviceID: deviceID)
                }
                return true
            }
            return false
        }
        if let captor = captor {
            self.mouseCaptors[deviceID] = nil
            captor.handleMouseLost(deviceID: deviceID)
        }
        return true
    }

    public func releaseMouse(frame: Frame?, forDeviceID deviceID: Int) -> Bool {
        if let captor = self.mouseCaptors[deviceID], captor === frame {
            self.mouseCaptors[deviceID] = nil
            captor.handleMouseLost(deviceID: deviceID)
            return true
        }
        return false
    }

    public func mouseCaptor(forDeviceID deviceID: Int) -> Frame? {
        return self.mouseCaptors[deviceID]
    }

    public func releaseAllKeyboardsCaptured(by frame: Frame?) {
        guard let frame = frame else { return }
        var deviceIDs: [Int] = []
        self.keyboardCaptors.forEach { (key, value) in
            if value === frame {
                deviceIDs.append(key)
            }
        }
        for deviceID in deviceIDs {
            self.keyboardCaptors[deviceID] = nil
            frame.handleKeyboardLost(deviceID: deviceID)
        }
    }

    public func releaseAllMiceCaptured(by frame: Frame?) {
        guard let frame = frame else { return }
        var deviceIDs: [Int] = []
        self.mouseCaptors.forEach { (key, value) in
            if value === frame {
                deviceIDs.append(key)
            }
        }
        for deviceID in deviceIDs {
            self.mouseCaptors[deviceID] = nil
            frame.handleMouseLost(deviceID: deviceID)
        }
    }        

    public func releaseAllKeyboards() {
        let captors: [(frame: Frame, deviceID: Int)] = self.keyboardCaptors.map {
            (key, value) in (frame: value, deviceID: key)
        }
        self.keyboardCaptors.removeAll()
        for c in captors {
            c.frame.handleKeyboardLost(deviceID: c.deviceID)
        }
    }

    public func releaseAllMice() {
        let captors: [(frame: Frame, deviceID: Int)] = self.mouseCaptors.map {
            (key, value) in (frame: value, deviceID: key)
        }
        self.mouseCaptors.removeAll()
        for c in captors {
            c.frame.handleMouseLost(deviceID: c.deviceID)
        }
    }

    public func hoverFrame(forDeviceID deviceID: Int) -> Frame? {
        return self.hoverFrames[deviceID]?.frame
    }

    public func leaveHoverFrame(_ frame: Frame?) {
        guard let frame = frame else { return }
        var devices: [(deviceID: Int, device: MouseEventDevice)] = []
        self.hoverFrames.forEach { (key, value) in
            if value.frame === frame {
                devices.append((deviceID: key, device: value.device))
            }
        }
        for d in devices {
            frame.handleMouseLeave(deviceID: d.deviceID, device: d.device)
        }
    }

    public func windowToScreen(point: CGPoint) -> CGPoint {
        let x = point.x / self.windowContentBounds.width
        let y = point.y / self.windowContentBounds.height
        return CGPoint(x: x, y: y)
    }

    public func screenToWindow(point: CGPoint) -> CGPoint {
        let x = point.x * self.windowContentBounds.width
        let y = point.y * self.windowContentBounds.height
        return CGPoint(x: x, y: y)
    }

    public func windowToScreen(size: CGSize) -> CGSize {
        let w = size.width / self.windowContentBounds.width
        let h = size.height / self.windowContentBounds.height
        return CGSize(width: w, height: h)
    }

    public func screenToWindow(size: CGSize) -> CGSize {
        let w = size.width * self.windowContentBounds.width
        let h = size.height * self.windowContentBounds.height
        return CGSize(width: w, height: h)
    }

    public func windowToScreen(rect: CGRect) -> CGRect {
        let origin = windowToScreen(point: CGPoint(x: rect.minX, y: rect.minY))
        let extent = windowToScreen(point: CGPoint(x: rect.maxX, y: rect.maxY))
        let minX = min(origin.x, extent.x)
        let maxX = max(origin.x, extent.x)
        let minY = min(origin.y, extent.y)
        let maxY = max(origin.y, extent.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func screenToWindow(rect: CGRect) -> CGRect {
        let origin = screenToWindow(point: CGPoint(x: rect.minX, y: rect.minY))
        let extent = screenToWindow(point: CGPoint(x: rect.maxX, y: rect.maxY))
        let minX = min(origin.x, extent.x)
        let maxX = max(origin.x, extent.x)
        let minY = min(origin.y, extent.y)
        let maxY = max(origin.y, extent.y)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public func processKeyboardEvent(_ event: KeyboardEvent) {
        Log.debug("Screen.\(#function) event:\(event)")

        if let captor = self.keyboardCaptor(forDeviceID: event.deviceID) {
            assert(captor.screen === self)
            _ = captor.processKeyboardEvent(event)
        }
    }

    public func processMouseEvent(_ event: MouseEvent) {
        if event.type != .move {
            Log.debug("Screen.\(#function) event:\(event)")
        }

        if let frame = self.frame {
            let res = Vector2(self.resolution * (1.0 / self.windowContentScaleFactor))
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
                if let fd = self.hoverFrames[event.deviceID] {
                    assert(fd.device == event.device)
                    leave = fd.frame
                }

                if hover !== leave {
                    if let hover = hover {
                        self.hoverFrames[event.deviceID] = (frame: hover, device: event.device)
                    } else {
                        self.hoverFrames[event.deviceID] = nil
                    }

                    if let leave = leave {
                        assert(leave.screen === self)
                        leave.handleMouseLeave(deviceID: event.deviceID, device: event.device)
                    }
                    if let hover = hover {
                        assert(hover.screen === self)
                        hover.handleMouseEnter(deviceID: event.deviceID, device: event.device)
                    }
                }
            }

            if let captor = self.mouseCaptor(forDeviceID: event.deviceID) {
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

    public func processWindowEvent(_ event: WindowEvent) {
        Log.debug("Screen.\(#function) event:\(event)")

        switch event.type {
        case .resized:
            let scaleFactor = event.contentScaleFactor
            let resolution = CGSize(width: event.contentBounds.width,
                                    height: event.contentBounds.height) * scaleFactor
            self.windowContentScaleFactor = scaleFactor
            self.windowContentBounds = event.contentBounds
            self.resolution = resolution
            self.frame?.updateResolution()
        case .hidden, .minimized:
            self.visible = false
        case .shown:
            self.visible = true
            self.frame?.redraw()
        case .activated:
            self.activated = true
            self.visible = true
        case .inactivated:
            self.activated = false
        case .update:
            self.frame?.redraw()
        case .closed:
            self.window = nil
        default:
            break
        }
    }
}
