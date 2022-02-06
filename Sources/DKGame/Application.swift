public protocol ApplicationDelegate {
    func initialize()
    func finalize()
}

public protocol Application {
    func terminate(exitCode : Int)
}

public func applicationInstance() -> Application? {
    return Platform.applicationInstance()
}

public func runApplication(delegate: ApplicationDelegate?) -> Int {
    return Platform.runApplication(delegate: delegate)
}
