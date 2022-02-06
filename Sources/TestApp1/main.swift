
import DKGame

print("Hello, world!")

class MyWindowDelegate : WindowDelegate {
    func shouldClose() -> Bool { true }
}

var a = makeWindow(delegate: nil)

