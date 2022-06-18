#if ENABLE_APPKIT

public struct PlatformFactoryAppKit: PlatformFactory {

    public func sharedApplication() -> Application? {
        return AppKitApplication.shared
    }

    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return AppKitApplication.run(delegate: delegate)
    }

    @MainActor
    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window {
        return AppKitWindow(name: name, style: style, delegate: delegate)
    }
}

#endif //if ENABLE_APPKIT
