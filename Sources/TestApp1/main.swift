
import DKGame

print("Hello, world!")

class MyWindowDelegate: WindowDelegate {
    func shouldClose() -> Bool { 
        let app = applicationInstance()
        app!.terminate(exitCode: 1234)
        return true
     }
}

let gd = makeGraphicsDevice()
var window = makeWindow(delegate: nil)
window.show()

class MyApplicatoin: ApplicationDelegate {
    func initialize(application: Application) {
        print("app initialize")
    }

    func finalize(application: Application) {
        print("app finalize")
    }
}

let exitCode = runApplication(delegate: MyApplicatoin())

print("exitCode: \(exitCode)")
