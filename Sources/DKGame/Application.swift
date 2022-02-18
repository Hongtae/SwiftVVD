public protocol Application {
    func terminate(exitCode : Int)
}

public protocol ApplicationDelegate {
    func initialize(application: Application)
    func finalize(application: Application)
}

public func applicationInstance() -> Application? {
    return Platform.applicationInstance()
}

public func runApplication(delegate: ApplicationDelegate?) -> Int {
    return Platform.runApplication(delegate: delegate)
}
