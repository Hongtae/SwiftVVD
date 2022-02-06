public class Platform {

#if os(macOS)
    typealias Impl = macOS
#elseif os(iOS)
    typealias Impl = iOS
#elseif os(Android)
    typealias Impl = Android
#elseif os(Windows)
    typealias Impl = Win32
#elseif os(Linux)
    typealias Impl = Linux
#endif

    public class var name : String { Impl.name }

    public class func makeWindow(name: String, delegate: WindowDelegate?) -> Window {
        return Impl.Window()
    }
    public class func runApplication(delegate: ApplicationDelegate?) -> Int {
        return 0
    }
    public class func applicationInstance() -> Application? {
        return nil
    }
}
