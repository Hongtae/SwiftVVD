private typealias GlobalApplication = Application

extension Android {
    public class Application : GlobalApplication {

        public init() {

        }

        public func terminate(exitCode: Int) {}
    }
}
