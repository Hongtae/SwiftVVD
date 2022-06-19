#if ENABLE_UIKIT
import Foundation
import UIKit

class AppLoader: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]?) -> Bool {
        let app = UIKitApplication.shared as! UIKitApplication
        Task { @MainActor in
            await app.delegate?.initialize(application: app)
            app.initialized = true
        }
        return true
    }
}

public class UIKitApplication: Application {
    public static var shared: Application? = nil

    var delegate: ApplicationDelegate?
    var initialized = false

    public func terminate(exitCode : Int) {
        Task { @MainActor in
            if self.initialized {
                await self.delegate?.finalize(application: self)
                self.initialized = false
            }

            DispatchQueue.main.async {
                exit(0)
            }
        }
    }

    public static func run(delegate: ApplicationDelegate?) -> Int {
        assert(Thread.isMainThread)

        let app = UIKitApplication()
        app.delegate = delegate
        self.shared = app

        UIApplicationMain(CommandLine.argc,
                          CommandLine.unsafeArgv,
                          nil,
                          NSStringFromClass(AppLoader.self))

        self.shared = nil
        return 0
    }
}

#endif //if ENABLE_UIKIT
