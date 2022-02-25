#if ENABLE_UIKIT

public struct DKGameUIKit: PlatformFactory {

    public func sharedApplication() -> Application? {
        return iOSApplication.shared
    }

    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return iOSApplication.run(delegate: delegate)
    }

    public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window {
        return iOSWindow(name: name, style: style, delegate: delegate)
    }
}

#endif //ENABLE_UIKIT