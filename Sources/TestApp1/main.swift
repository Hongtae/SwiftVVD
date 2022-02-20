
import DKGame

class MyWindowDelegate: WindowDelegate {
    func shouldClose(window: Window) -> Bool { 
        let app = applicationInstance()
        app!.terminate(exitCode: 1234)
        print("window closed, request app exit!")
        return true
     }
}

class MyApplicationDelegate: ApplicationDelegate {

    var window: Window?
    var windowDelegate: WindowDelegate?

    func initialize(application: Application) {
        print("app initialize")

        _ = makeGraphicsDevice()

        self.windowDelegate = MyWindowDelegate()
        self.window = makeWindow(delegate: self.windowDelegate)
        self.window?.show()
    }

    func finalize(application: Application) {
        print("app finalize")

        self.window = nil
    }
}

let appDelegate = MyApplicationDelegate()
let exitCode = runApplication(delegate: appDelegate)

print("exitCode: \(exitCode)")
