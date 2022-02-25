#if ENABLE_APPKIT

public class AppKitApplication: Application {
    public static var shared: Application? = nil
    public func terminate(exitCode : Int)
    public static func run(delegate: ApplicationDelegate?) -> Int {
        0
    }
}

#endif //ENABLE_APPKIT
