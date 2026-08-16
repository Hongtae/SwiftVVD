import VUI

@main
struct TestApp1: App {
    var body: some Scene {
        WindowGroup("TestApp1") {
            ContentView()
                .environment(\.resourceBundle, .module)
                //.environment(\._debugLayout, true)
        }
        .defaultSize(width: 860, height: 700)
        .defaultPosition(.zero)
        .drawDebugInfo(.frameInfo,
                       .updateTiming,
                       .queue,
                       .appState,
                       .windowState)
        .updateFrameRate(
            forActiveState: 60,
            forInactiveState: 30,
            renderingMode: .continuousWithDisplaySync
        )
    }
}
