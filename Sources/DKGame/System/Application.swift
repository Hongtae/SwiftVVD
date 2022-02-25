public protocol Application {
    func terminate(exitCode : Int)
    static func run(delegate: ApplicationDelegate?) -> Int
    static var shared: Application? { get }
}

public protocol ApplicationDelegate {
    func initialize(application: Application)
    func finalize(application: Application)
}

public func sharedApplication() -> Application? {
    Platform.sharedApplication()
}

public func runApplication(delegate: ApplicationDelegate?) -> Int {
    Platform.runApplication(delegate: delegate)
}
