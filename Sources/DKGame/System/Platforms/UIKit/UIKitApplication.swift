#if ENABLE_UIKIT

public class UIKitApplication: Application {
    public static var shared: Application? = nil
    public func terminate(exitCode : Int)
    public static func run(delegate: ApplicationDelegate?) -> Int {
        0
    }
}

#endif //ENABLE_UIKIT
