import DKGUI

@main
struct GameEditorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Image("Test.png")
            Text("Hello, world!")
            Text("Hello, world!")
        }
    }
}
