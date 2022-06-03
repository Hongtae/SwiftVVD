import Foundation
import DKGame

class MyWindowDelegate: WindowDelegate {
    func shouldClose(window: Window) -> Bool { 
        let app = sharedApplication()
        app!.terminate(exitCode: 1234)
        print("window closed, request app exit!")
        return true
    }
    func minimumContentSize(window: Window) -> CGSize? { CGSize(width: 200, height: 200) }
    func maximumContentSize(window: Window) -> CGSize? { nil }


    public func draggingEntered(target: Window, position: CGPoint, files: [String]) -> DragOperation {
        print("draggingEntered: position:\(position), files:\(files)")
        return .copy
    }
    public func draggingUpdated(target: Window, position: CGPoint, files: [String]) -> DragOperation {
        print("draggingUpdated: position:\(position), files:\(files)")
        return .copy
    }
    public func draggingDropped(target: Window, position: CGPoint, files: [String]) -> DragOperation {
        print("draggingDropped: position:\(position), files:\(files)")
        return .copy
    }
    public func draggingExited(target: Window, files: [String]) {
        print("draggingExited: files:\(files)")
    }
}

class MyFrame: Frame {
    var t = 0.0
    var tickDelta = 0.0
    var textFont: Font?
    var outlineFont: Font?
    var fpsFont: Font?

    let dpi: Font.DPI = (72, 72)

    var baseline = [CGPoint(x: 80, y: 450), CGPoint(x: 620, y: 180)]

    override func loaded(screen: Screen) {
        if let fontData = loadResourceData(name: "Resources/Roboto-Regular.ttf") {
            self.textFont = Font(deviceContext: screen.graphicsDeviceContext!, data: fontData)
            self.outlineFont = Font(deviceContext: screen.graphicsDeviceContext!, data: fontData)
            let pointSize = 32.0
            if let font = self.textFont {
                font.setStyle(pointSize: pointSize, dpi: dpi)
            }
            if let font = self.outlineFont {
                font.setStyle(pointSize: pointSize, dpi: dpi, outline: 1.0, forceBitmap: true)
            }
        }
        if let fontData = loadResourceData(name: "Resources/BitstreamVeraSansMono.ttf") {
            self.fpsFont = Font(deviceContext: screen.graphicsDeviceContext!, data: fontData)
            if let font = self.fpsFont {
                font.setStyle(pointSize: 24, dpi: dpi)
            }
        }
    }

    override func update(tick: UInt64, delta: Double, date: Date) {
        t += delta
        tickDelta = delta
    }

    override func resolutionChanged(_ size: CGSize, scaleFactor: CGFloat) {
        super.resolutionChanged(size, scaleFactor: scaleFactor)

        var dpi = self.dpi
        dpi.x = UInt32(CGFloat(dpi.x) * scaleFactor)
        dpi.y = UInt32(CGFloat(dpi.y) * scaleFactor)

        self.textFont?.dpi = dpi
        self.outlineFont?.dpi = dpi
        self.fpsFont?.dpi = dpi
    }

    override func draw(canvas: Canvas) {
        let v = Scalar(sin(t) + 1.0) * 0.5
        canvas.clear(color: Color(0, 0, 0.6))
        canvas.drawEllipse(bounds: CGRect(x: 150, y: 50, width: 200, height: 200),
            inset: CGSize(width: 20, height: 20),
            color: Color(v, 0, 0), blendState: .defaultOpaque)
        canvas.drawRect(CGRect(x: 50, y: 15, width: 200, height: 200), color: Color(1, 1, 1, 0.5), blendState: .defaultAlpha)
        if let textFont = self.textFont, let outlineFont = self.outlineFont {

            canvas.drawLines(baseline, lineWidth: 2, color: Color(1, 1, 1))

            let text = "Swift DKGL"
            
            canvas.drawText(text, font: outlineFont,
                baselineBegin: baseline[0],
                baselineEnd: baseline[1],
                color: Color(0,0,0))
            canvas.drawText(text, font: textFont,
                baselineBegin: baseline[0],
                baselineEnd: baseline[1],
                color: Color(1,1,0))
        }
        if let font = self.fpsFont {
            let text = String(format:"%.1f FPS (%.4f)", 1.0 / self.tickDelta, self.tickDelta)
            var bounds = self.pixelToLocal(rect: font.bounds(of: text))
            let contentBounds = self.bounds
            bounds.origin = CGPoint(x: contentBounds.width - bounds.width - 10, y: 10)

            canvas.drawText(text, font: font, bounds: bounds, color: Color(1, 1, 1))
        }
    }

    override func handleMouseEvent(_ event: MouseEvent, position: CGPoint, delta: CGPoint) -> Bool {
        if event.type != .move {
            // Log.debug("\(#function): event: \(event), position: \(position), delta: \(delta)")
        }

        if event.type == .buttonDown {
            switch event.buttonId {
            case 0:
                self.baseline[0] = position
            case 1:
                self.baseline[1] = position
            default:
                break
            }
            self.redraw()
        }
        return true 
    }

    override func handleKeyboardEvent(_ event: KeyboardEvent) -> Bool {
        Log.debug("\(#function): event: \(event)")
        return true
    }
    
    override func handleMouseEnter(deviceId: Int, device: MouseEventDevice) {
        Log.debug("\(#function): deviceId: \(deviceId), device: \(device)")
    }

    override func handleMouseLeave(deviceId: Int, device: MouseEventDevice) {
        Log.debug("\(#function): deviceId: \(deviceId), device: \(device)")
    }

    override func handleMouseLost(deviceId: Int) {
        Log.debug("\(#function): deviceId: \(deviceId)")
    }

    override func handleKeyboardLost(deviceId: Int) {
        Log.debug("\(#function): deviceId: \(deviceId)")
    }

}

class MyApplicationDelegate: ApplicationDelegate {

    var window: Window?
    var windowDelegate: WindowDelegate?
    var screen: Screen?
    var frame: Frame?

    func initialize(application: Application) {
        print("app initialize")

        self.windowDelegate = MyWindowDelegate()
        self.window = makeWindow(name: "TestApp1",
                                 style: [.genericWindow, .acceptFileDrop],
                                 delegate: self.windowDelegate)
        self.window?.contentSize = CGSize(width: 800, height: 600)

        Task {
            self.screen = await Screen()
            self.frame = await MyFrame()
            Task { @ScreenActor in
                self.screen?.window = self.window
                self.screen?.frame = self.frame
            }
        }
        self.window?.activate()
    }

    func finalize(application: Application) {
        print("app finalize")

        self.screen = nil
        self.window = nil
        self.frame = nil
    }
}

func loadResourceData(name: String) -> Data? {
    let bundle = Bundle.main
    if let url = bundle.url(forResource: name, withExtension: nil) {
        do {
            return try Data(contentsOf: url, options: [])
        } catch {
            print("Error on loading data: \(error)")
        }
    }
    if let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "DKGame_TestApp1.resources") {
        do {
            return try Data(contentsOf: url, options: [])
        } catch {
            print("Error on loading data: \(error)")
        }
    }
    print("cannot load resource.")
    return nil
}

let appDelegate = MyApplicationDelegate()
let exitCode = runApplication(delegate: appDelegate)

print("exitCode: \(exitCode)")
