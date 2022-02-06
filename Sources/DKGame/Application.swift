public protocol ApplicationDelegate {
    func initialize()
    func finalize()
}

public func runApplication(delegate: ApplicationDelegate?) -> Int {
    return Platform.runApplication(delegate: delegate)
}
