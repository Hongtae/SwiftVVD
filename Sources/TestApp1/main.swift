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
    override func update(tick: UInt64, delta: Double, date: Date) {
        t += delta
    }

    override func draw(canvas: Canvas) {
        let v = Scalar(sin(t) + 1.0) * 0.5
        canvas.clear(color: Color(0, 0, v))
        canvas.drawRect(CGRect(x: 15, y: 15, width: 100, height: 100), color: Color(1, 1, 1), blendState: .defaultOpaque)
        canvas.drawEllipse(bounds: CGRect(x: 50, y: 50, width: 100, height: 100), color: Color(1, 1, 0), blendState: .defaultOpaque)
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
        self.screen = Screen()
        self.frame = MyFrame()
        self.window = makeWindow(name: "TestApp1",
                                 style: [.genericWindow, .acceptFileDrop],
                                 delegate: self.windowDelegate)
        self.window?.contentSize = CGSize(width: 800, height: 600)
        self.screen?.window = self.window
        self.screen?.frame = self.frame
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
