private typealias GlobalApplication = Application

extension Win32 {
    public class Application : GlobalApplication {

        public init() {

        }

        public func terminate(exitCode: Int) {}
    }
}
