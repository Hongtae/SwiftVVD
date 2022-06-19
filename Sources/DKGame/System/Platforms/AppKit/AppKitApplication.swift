#if ENABLE_APPKIT
import Foundation
import AppKit

public class AppKitApplication: Application {
    public static var shared: Application? = nil

    weak var delegate: ApplicationDelegate?

    public func terminate(exitCode : Int) {
    }

    public static func run(delegate: ApplicationDelegate?) -> Int {
        assert(Thread.isMainThread)

        let app = AppKitApplication()
        app.delegate = delegate
        self.shared = app

        Task {
            await delegate?.initialize(application: app)
        }

        NSApplication.shared.run()

        Task {
            await delegate?.finalize(application: app)
        }

        self.shared = nil
        return 0
    }
}

#endif //if ENABLE_APPKIT
