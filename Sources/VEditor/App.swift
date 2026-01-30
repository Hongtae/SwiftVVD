import VUI

@main
struct GameEditorApp: App {
    var body: some Scene {
        WindowGroup("SwiftVVD.EditorApp") {
            ContentView()
                //.environment(\.resourceBundle, .module)
        }
    }
}
