import Foundation
import DKGame

class MyWindowDelegate: WindowDelegate {
    func shouldClose(window: Window) -> Bool { 
        let app = applicationInstance()
        app!.terminate(exitCode: 1234)
        print("window closed, request app exit!")
        return true
    }
    func restrictedContentMininumSize(window: Window) -> CGSize? { CGSize(width: 200, height: 200) }
    func restrictedContentMaxinumSize(window: Window) -> CGSize? { nil }
}

class MyApplicationDelegate: ApplicationDelegate {

    var window: Window?
    var windowDelegate: WindowDelegate?

    func initialize(application: Application) {
        print("app initialize")

        _ = makeGraphicsDevice()

        self.windowDelegate = MyWindowDelegate()
        self.window = makeWindow(name: "TestApp1", delegate: self.windowDelegate)
        self.window?.contentSize = CGSize(width: 800, height: 600)
        self.window?.activate()
    }

    func finalize(application: Application) {
        print("app finalize")

        self.window = nil
    }
}

let appDelegate = MyApplicationDelegate()
let exitCode = runApplication(delegate: appDelegate)

print("exitCode: \(exitCode)")
