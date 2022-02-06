
import DKGame

print("Hello, world!")

class MyWindowDelegate : WindowDelegate {
    func shouldClose() -> Bool { true }
}

let gd = makeGraphicsDevice()
var a = makeWindow(delegate: nil)

