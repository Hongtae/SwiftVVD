import DKGUI

@main
struct TestApp1: App {
    init() {
        Image._mainNamedBundle = .module
    }
    var body: some Scene {
        WindowGroup("TestApp1") {
            ContentView()
        }
    }
}
