#if ENABLE_APPKIT

public struct DKGameAppKit: PlatformFactory {

    public func sharedApplication() -> Application? {
        return AppKitApplication.shared
    }

    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return AppKitApplication.run(delegate: delegate)
    }

    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window {
        return AppKitWindow(name: name, style: style, delegate: delegate)
    }
}

#endif //ENABLE_APPKIT