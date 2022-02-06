public protocol WindowDelegate {
    func shouldClose() -> Bool
}

public protocol Window {
    func show()
    func hide()
}

public func makeWindow(name: String = "", delegate: WindowDelegate? = nil) -> Window { 
    return Platform.makeWindow(name: name, delegate: delegate)
}
