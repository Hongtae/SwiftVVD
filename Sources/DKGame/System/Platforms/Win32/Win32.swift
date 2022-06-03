#if ENABLE_WIN32

public struct PlatformFactoryWin32: PlatformFactory {

    public func sharedApplication() -> Application? {
        return Win32Application.shared
    }

    public func runApplication(delegate: ApplicationDelegate?) -> Int {
        return Win32Application.run(delegate: delegate)
    }

    @MainActor public func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window {
        return Win32Window(name: name, style: style, delegate: delegate)
    }
}

#endif //ENABLE_WIN32