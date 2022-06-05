import Foundation

@ScreenActor
open class Frame {

    public var bounds: CGRect   { CGRect(origin: .zero, size: contentScale) }
    public var transform: Matrix3 = .identity { didSet {
        inverseTransform = transform.inverted() ?? .identity
        self.redraw()
    } }
    public private(set) var inverseTransform: Matrix3 = .identity

    public var contentTransform: Matrix3 = .identity { didSet {
        inverseContentTransform = contentTransform.inverted() ?? .identity
        self.redraw()
    }}
    public private(set) var inverseContentTransform: Matrix3 = .identity

    private var _contentScaleFactor: CGFloat = 1.0
    public private(set) var resolution: CGSize = CGSize(width: 1, height: 1)
    public var contentScale: CGSize { 
        get { _contentScale }
        set(v) { 
            let w = max(v.width, Canvas.minimumScaleFactor)
            let h = max(v.height, Canvas.minimumScaleFactor)
            _contentScale = CGSize(width: w, height: h)
            self.redraw()
        }
    }
    private var _contentScale: CGSize = CGSize(width: 1, height: 1)

    public var color: Color = .black { didSet { self.redraw() } }
    public var pixelFormat: PixelFormat = .rgba8Unorm   { didSet { self.redraw() } }
    public var blendState: BlendState = .defaultOpaque  { didSet { self.redraw() } }

    public private(set) var renderTarget: Texture? = nil

    public var enabled: Bool = false { didSet { self.redraw() } }
    public var hidden: Bool = true { didSet { 
        if let s = self.superframe { s.redraw() }
    } }

    public private(set) weak var screen: Screen? = nil
    public private(set) unowned var superframe: Frame? = nil
    public private(set) var subframes: [Frame] = []
    public private(set) var loaded = false
    private var drawSurface = true

    public var numberOfDescendants: Int {
        var num = 1
        subframes.forEach { num += $0.numberOfDescendants }
        return num
    }

    public func isDescendant(of frame: Frame?) -> Bool {
        if frame == nil { return false }
        if frame === self { return true }
        return superframe?.isDescendant(of: frame) ?? false
    }

    public var localFromRootTransform: Matrix3 {
        let tm = superframe?.localFromRootTransform ?? .identity
        return tm * self.localFromSuperTransform
    }

    public var localToRootTransform: Matrix3 {
        let tm = superframe?.localToRootTransform ?? .identity
        return self.localToSuperTransform * tm
    }

    public var localFromSuperTransform: Matrix3 {
        var tm: Matrix3 = .identity
        if superframe != nil {
            // to normalized local coordinates.
            tm *= self.inverseTransform

            // apply local content scale.
            tm *= AffineTransform2(linear: LinearTransform2(scaleX: Scalar(contentScale.width), scaleY: Scalar(contentScale.height))).matrix3

            // apply inversed content transform.
            tm *= self.inverseContentTransform
        }
        return tm
    }

    public var localToSuperTransform: Matrix3 {
        var tm: Matrix3 = .identity
        if superframe != nil {
            // apply content transform.
            tm *= self.contentTransform

            // normalize local scale to (0.0 ~ 1.0)
            tm *= AffineTransform2(linear: LinearTransform2(scaleX: Scalar(1.0 / contentScale.width), scaleY: Scalar(1.0 / contentScale.height))).matrix3

            // transform to parent
            tm *= self.transform
        }
        return tm
    }

    public func localToSuper(point pt: CGPoint) -> CGPoint {
        if superframe != nil {
            assert(contentScale.width > .leastNormalMagnitude && contentScale.height > .leastNormalMagnitude)

            var v = Vector2(pt)

            // apply content transform.
            v.transform(by: self.contentTransform)

            // normalize coordinates (0.0 ~ 1.0)
            v.x = v.x / Scalar(self.contentScale.width)
            v.y = v.y / Scalar(self.contentScale.height)

            // transform to parent.
            v.transform(by: self.transform)

            return CGPoint(v)
        }
        return pt
    }

    public func superToLocal(point pt: CGPoint) -> CGPoint {
        if superframe != nil {
            var v = Vector2(pt)

            // apply inversed transform to normalize coordinates (0.0 ~ 1.0)
            v.transform(by: self.inverseTransform)

            // apply content scale
            v.x = v.x * Scalar(self.contentScale.width)
            v.y = v.y * Scalar(self.contentScale.height)

            // apply inversed content transform
            v.transform(by: self.inverseContentTransform)

            return CGPoint(v)
        }
        return pt
    }

    public func localToPixel(point pt: CGPoint) -> CGPoint {
        assert(contentScale.width > .leastNormalMagnitude && contentScale.height > .leastNormalMagnitude)

        var v = Vector2(pt)

        // apply content transform.
        v.transform(by: self.contentTransform)

        // normalize coordinates (0.0 ~ 1.0)
        v.x = v.x / Scalar(self.contentScale.width)
        v.y = v.y / Scalar(self.contentScale.height)

        // convert to pixel-space.
        v.x = v.x * Scalar(self.resolution.width)
        v.y = v.y * Scalar(self.resolution.height)

        return CGPoint(v)
    }

    public func pixelToLocal(point pt: CGPoint) -> CGPoint {
        assert(resolution.width > .leastNormalMagnitude && resolution.height > .leastNormalMagnitude)

        var v = Vector2(pt)

        // normalize coordinates.
        v.x = v.x / Scalar(self.resolution.width)
        v.y = v.y / Scalar(self.resolution.height)

        // apply content scale.
        v.x = v.x * Scalar(self.contentScale.width)
        v.y = v.y * Scalar(self.contentScale.height)

        // apply inversed content transform.
        v.transform(by: self.inverseContentTransform)

        return CGPoint(v)
    }

    public func localToPixel(size: CGSize) -> CGSize {
        let p0 = localToPixel(point: .zero)
        let p1 = localToPixel(point: CGPoint(x: size.width, y: size.height))
        return CGSize(width: p1.x - p0.x, height: p1.y - p0.y)
    }

    public func pixelToLocal(size: CGSize) -> CGSize {
        let p0 = pixelToLocal(point: .zero)
        let p1 = pixelToLocal(point: CGPoint(x: size.width, y: size.height))
        return CGSize(width: p1.x - p0.x, height: p1.y - p0.y)
    }

    public func localToPixel(rect: CGRect) -> CGRect {
        return CGRect(origin: localToPixel(point: rect.origin), size: localToPixel(size: rect.size))
    }

    public func pixelToLocal(rect: CGRect) -> CGRect {
        return CGRect(origin: pixelToLocal(point: rect.origin), size: pixelToLocal(size: rect.size))
    }

    public init() {
    }

    @discardableResult
    public func draw() async -> Bool {
        return await self.drawHierarchy()
    }

    public func redraw() {
        drawSurface = true
    }

    public func discardSurface() {
        renderTarget = nil
        self.redraw()
    }

    public func updateResolution() {
        guard self.loaded else { return }

        var resized = false
        if let screen = self.screen, screen.frame === self {
            let scaleFactor = screen.contentScaleFactor
            let size = screen.resolution
            let w = max(size.width.rounded(), 1.0)
            let h = max(size.height.rounded(), 1.0)

            if self.resolution.width.rounded() != w ||
               self.resolution.height.rounded() != h ||
               self._contentScaleFactor != scaleFactor {
                resized = true
                self.resolution = CGSize(width: w, height: h)
                self._contentScaleFactor = scaleFactor
            }
        } else {
            let size = self.calculateResolution()
            let maxTexSize = 1 << 14  //Texture.maxTextureSize
            let w = clamp(size.width.rounded(), min: 1.0, max: CGFloat(maxTexSize))
            let h = clamp(size.height.rounded(), min: 1.0, max: CGFloat(maxTexSize))

            if self.resolution.width.rounded() != w || self.resolution.height.rounded() != h {
                resized = true
                self.resolution = CGSize(width: w, height: h)
                self._contentScaleFactor = self.screen?.contentScaleFactor ?? 1.0
                self.discardSurface()
            }
        }
        assert(resolution.width > .leastNormalMagnitude)
        assert(resolution.height > .leastNormalMagnitude)

        if resized {
            Task { await self.resolutionChanged(resolution, scaleFactor: self._contentScaleFactor) }
            self.redraw()
        }
        subframes.forEach { $0.updateResolution() }
    }

    public func calculateResolution() -> CGSize {
        if let superframe = superframe {
            let superRes = superframe.resolution
            if superRes.width > .leastNormalMagnitude && superRes.height > .leastNormalMagnitude {
                let w = contentScale.width
                let h = contentScale.height
                // get each points of box (not rect)

                let lt = superframe.localToPixel(point: self.localToSuper(point: .zero)) // left-top
                let rt = superframe.localToPixel(point: self.localToSuper(point: CGPoint(x: w,   y: 0.0))) // right-top
                let lb = superframe.localToPixel(point: self.localToSuper(point: CGPoint(x: 0.0, y: h))) // left-bottom
                let rb = superframe.localToPixel(point: self.localToSuper(point: CGPoint(x: w,   y: h))) // right-bottom

                let horizontal1 = rb - lb   // vertical length 1
                let horizontal2 = rt - lt   // vertical length 2
                let vertical1 = lt - lb     // horizontal length 1
                let vertical2 = rt - rb     // horizontal length 2

                let result = CGSize(width: max(horizontal1.magnitude, horizontal2.magnitude).rounded(),
                                    height: max(vertical1.magnitude, vertical2.magnitude).rounded())
                return result
            }
        }
        return resolution
    }

    @discardableResult
    public func addSubframe(_ frame: Frame) async -> Bool {
        if frame.superframe == nil && self.isDescendant(of: frame) == false {
            self.subframes.insert(frame, at: 0) // bring to front
            frame.superframe = self
            if self.loaded {
                assert(self.screen != nil)
                await frame.loadHierarchy(screen: self.screen!,
                                    resolution: self.resolution,
                                    scaleFactor: self._contentScaleFactor)
                frame.updateResolution()
                redraw()
            }
            return true
        }
        return false
    }

    public func removeFromSuperframe() {
        if let parent = self.superframe {
            if let screen = self.screen {
                screen.leaveHoverFrame(self)
                screen.releaseAllKeyboardsCapturedBy(frame: self)
                screen.releaseAllMiceCapturedBy(frame: self)
            }
            
            for i in 0..<parent.subframes.count {
                if parent.subframes[i] === self {
                    parent.subframes.remove(at: i)
                    break
                }
            }
            parent.redraw()
            self.superframe = nil
        }
    }

    public func bringSubframeToFront(_ frame: Frame) {}
    public func sendSubframeToBack(_ frame: Frame) {}

    open var canHandleMouse: Bool { true }
    open var canHandleKeyboard: Bool { true }

    public func processMouseEvent(_ event: MouseEvent, position: CGPoint, delta: CGPoint, exclusive: Bool) async -> Bool {

        // convert frame local-space to content-space
        let localPos = position.transformed(by: self.inverseContentTransform)
        let localPosOld = (position - delta).transformed(by: self.inverseContentTransform)
        let localDelta = localPos - localPosOld

        if event.type != .move {
            Log.debug("Frame.\(#function). position: \(position), localPos:\(localPos)")
        }


        if exclusive == false {
            if self.hitTest(position: position) == false { return false }

            if self.contentHitTest(position: localPos) {
                for frame in self.subframes {
                    if frame.hidden { continue }

                    // apply inversed frame transform (convert to normalized frame coordinates)
                    let scale = Vector2(frame.contentScale)
                    assert(scale.x > 0.0 && scale.y > 0.0)
                    let tm = frame.inverseTransform * AffineTransform2(linear: .init(scaleX: scale.x, scaleY: scale.y)).matrix3
                    let posInFrame = localPos.transformed(by: tm)

                    if frame.bounds.contains(posInFrame) {
                        let posInFrameOld = localPosOld.transformed(by: tm)
                        let deltaInFrame = posInFrame - posInFrameOld
                        
                        // send event to frame whether it is able to process or not. (frame is visible-destionation)
                        if await frame.processMouseEvent(event, position: posInFrame, delta: deltaInFrame, exclusive: false) {
                            return true
                        }
                    }
                }
            }
        }
        
        if self.canHandleMouse {
            return await self.handleMouseEvent(event, position: localPos, delta: localDelta)
        }
        return false
    }

    public func processKeyboardEvent(_ event: KeyboardEvent) async -> Bool {
        if self.canHandleKeyboard {
            return await handleKeyboardEvent(event)
        }
        return false
    }

    public func findHoverFrame(at position: CGPoint) -> Frame? {
        if self.hidden == false {
            if self.bounds.contains(position) {
                if self.hitTest(position: position) {
                    let localPos = position.transformed(by: self.inverseContentTransform)

                    if self.contentHitTest(position: localPos) {
                        for frame in subframes {
                            let scale = Vector2(frame.contentScale)
                            assert(scale.x > 0.0 && scale.y > 0.0)
                            let tm = frame.inverseTransform * AffineTransform2(linear: .init(scaleX: scale.x, scaleY: scale.y)).matrix3
                            let posInFrame = localPos.transformed(by: tm)

                            if let hover = frame.findHoverFrame(at: posInFrame) {
                                return hover
                            }
                        }
                    }

                    if self.canHandleMouse {
                        return self
                    }
                }
            }
        }
        return nil
    }

    public func captureKeyboard(deviceId: Int) -> Bool { false }
    public func captureMouse(deviceId: Int) -> Bool { false }
    public func releaseKeyboard(deviceId: Int) {}
    public func releaseMouse(deviceId: Int) {}
    public func releaseAllKeyboardsCapturedBySelf() {}
    public func releaseAllMiceCapturedBySelf() {}

    public func isKeyboardCatpuredBySelf(deviceId: Int) -> Bool { false }
    public func isMouseCapturedBySelf(deviceId: Int) -> Bool { false }

    open func loaded(screen: Screen) async {}
    open func unload() async {}
    open func update(tick: UInt64, delta: Double, date: Date) async {}
    open func draw(canvas: Canvas) async { canvas.clear(color: .white) }
    open func drawOverlay(canvas: Canvas) async {}

    open func resolutionChanged(_ size: CGSize, scaleFactor: CGFloat) async {
        self.contentScale = CGSize(width: size.width / scaleFactor, height: size.height / scaleFactor)
    }

    open func hitTest(position pt: CGPoint) -> Bool { true }
    open func contentHitTest(position pt: CGPoint) -> Bool { true }

    open func handleMouseEvent(_: MouseEvent, position: CGPoint, delta: CGPoint) async -> Bool { false }
    open func handleKeyboardEvent(_: KeyboardEvent) async -> Bool { false }
    open func handleMouseEnter(deviceId: Int, device: MouseEventDevice) async {}
    open func handleMouseLeave(deviceId: Int, device: MouseEventDevice) async {}
    open func handleMouseLost(deviceId: Int) async {}
    open func handleKeyboardLost(deviceId: Int) async {}

    func updateHierarchy(tick: UInt64, delta: Double, date: Date) async {
        assert(self.loaded)

        await withTaskGroup(of: Void.self) {
            taskGroup in
            taskGroup.addTask {
                await self.update(tick: tick, delta: delta, date: date)
            }
            for frame in subframes {
                taskGroup.addTask {
                    await frame.updateHierarchy(tick: tick, delta: delta, date: date)
                }
            }
        }
    }

    func drawHierarchy() async -> Bool {
        if self.loaded {
            assert(self.screen != nil)
            let screen = self.screen!

            var drawSelf = false
            for frame in subframes {
                if frame.hidden {
                    continue
                }
                if await frame.drawHierarchy() {
                    drawSelf = true
                }
            }

            if drawSelf || self.drawSurface {
                // create canvas.
                var canvas: Canvas? = nil
                if screen.frame === self {
                    canvas = await screen.makeCanvas()
                    self.renderTarget = nil
                } else {
                    if self.renderTarget == nil {
                        // use screen's device (not from commandQueue.device)
                        if let device = screen.graphicsDeviceContext?.device {
                            let width = UInt32(self.resolution.width.rounded())
                            let height = UInt32(self.resolution.height.rounded())

                            assert(self.pixelFormat.isColorFormat())

                            let desc = TextureDescriptor(
                                textureType: .type2D,
                                pixelFormat: self.pixelFormat,
                                width: width,
                                height: height,
                                depth: 1,
                                mipmapLevels: 1,
                                sampleCount: 1,
                                arrayLength: 1,
                                usage: [.sampled, .renderTarget]
                            )
                            self.renderTarget = device.makeTexture(descriptor: desc)
                        }
                    }
                    if renderTarget == nil {
                        Log.err("Frame.draw() failed, cannot create render target texture")
                        return false
                    }

                    if let commandBuffer = screen.commandQueue?.makeCommandBuffer() {
                        canvas = Canvas(commandBuffer: commandBuffer,
                                        renderTarget: self.renderTarget!)
                    } else {
                        Log.err("Frame.draw() failed, invalid command buffer.")
                    }
                }
                if let canvas = canvas {
                    canvas.viewport = CGRect(origin: .zero, size: self.resolution)
                    canvas.contentBounds = CGRect(origin: .zero, size: self.contentScale)
                    canvas.contentTransform = self.contentTransform

                    // draw surface
                    await self.draw(canvas: canvas)

                    // draw subframes in reverse order
                    for i in (0..<subframes.count).reversed() {
                        let frame = self.subframes[i]
                        if frame.hidden { continue }

                        if let texture = frame.renderTarget {
                            let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
                            canvas.drawRect(rect,
                                            transform: frame.transform,
                                            textureRect: rect, 
                                            textureTransform: .identity,
                                            texture: texture,
                                            color: frame.color,
                                            blendState: frame.blendState)
                        }
                    }
                    // draw overlay
                    await self.drawOverlay(canvas: canvas)
                    canvas.commit()

                    self.drawSurface = false
                    return true
                } else {
                    Log.err("Frame.draw() failed, invalid canvas.")
                }
            }
        }
        return false 
    }

    func loadHierarchy(screen: Screen, resolution: CGSize, scaleFactor: CGFloat) async {
        if self.screen !== screen {
            await self.unloadHierarchy()
            assert(self.loaded == false)

            self.screen = screen
            // update resolution
            self.resolution = CGSize(width: resolution.width.rounded(),
                                     height: resolution.height.rounded())
            self._contentScaleFactor = scaleFactor
            self.loaded = true
            await self.loaded(screen: screen)
            await self.resolutionChanged(self.resolution, scaleFactor: scaleFactor)
            self.updateResolution()

            await withTaskGroup(of: Void.self) { taskGroup in
                for frame in self.subframes {
                    taskGroup.addTask {
                        await frame.loadHierarchy(screen: screen,
                            resolution: self.resolution,
                            scaleFactor: scaleFactor)
                    }
                }
            }
        }
    }

    func unloadHierarchy() async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for frame in self.subframes {
                taskGroup.addTask {
                    await frame.unloadHierarchy()
                }
            }
            if self.loaded {
                taskGroup.addTask{
                    if let screen = await self.screen {
                        await screen.leaveHoverFrame(self)
                        await screen.releaseAllKeyboardsCapturedBy(frame: self)
                        await screen.releaseAllMiceCapturedBy(frame: self)
                    }
                    await self.unload()
                }
            }
        }

        self.loaded = false
        self.screen = nil
    }
}
