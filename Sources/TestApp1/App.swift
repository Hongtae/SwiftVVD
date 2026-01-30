import VUI

@main
struct TestApp1: App {
    var body: some Scene {
        WindowGroup("TestApp1") {
            ContentView()
                .environment(\.resourceBundle, .module)
                //.environment(\._viewContextDebugDraw, true)
        }
    }
}
