import DKGUI

@main
struct GameEditorApp: App {
    var body: some Scene {
        WindowGroup("DKGameEditorApp") {
            ContentView()
                .environment(\.testValue, 5678)
        }
    }
}
