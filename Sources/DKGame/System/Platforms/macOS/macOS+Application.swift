private typealias GlobalApplication = Application

extension macOS {
    public class Application : GlobalApplication {

        public init() {

        }

        public func terminate(exitCode: Int) {}
    }
}
