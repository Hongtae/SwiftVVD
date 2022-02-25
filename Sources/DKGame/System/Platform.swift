public protocol PlatformFactory {
     func sharedApplication() -> Application? 
     func runApplication(delegate: ApplicationDelegate?) -> Int
     func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window 
}

public class Platform {

    public class var factory: PlatformFactory {
#if ENABLE_APPKIT
        DKGameAppKit()
#elseif ENABLE_UIKIT
        DKGameUIKit()
#elseif ENABLE_WIN32
        DKGameWin32()
#endif
    }

    public class func makeWindow(name: String, style: WindowStyle, delegate: WindowDelegate?) -> Window {
        factory.makeWindow(name: name, style: style, delegate: delegate)
    }
    public class func runApplication(delegate: ApplicationDelegate?) -> Int {
        factory.runApplication(delegate: delegate)
    }
    public class func sharedApplication() -> Application? {
        factory.sharedApplication()
    }
}
