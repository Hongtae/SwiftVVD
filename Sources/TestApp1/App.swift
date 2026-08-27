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
        .drawDebugInfo(
            .frameInfo,
            .updateTiming,
            .queue,
            .appState,
            .windowState,
            position: .init(x: 5, y: 33)
        )
        .updateFrameRate(
            forActiveState: 60,
            forInactiveState: 30,
            renderingMode: .continuousWithDisplaySync
        )
        .commandMenuPresentationStyle(.window)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("About Command Lab") {
                    print("Command Lab: About")
                }
            }

            CommandMenu("Command Lab") {
                Button("Run Menu Action", systemImage: "play") {
                    print("Command Lab: Run Menu Action")
                }
                .keyboardShortcut("R", modifiers: [.command, .shift])

                Menu("Nested Commands") {
                    Button("Nested Action") {
                        print("Command Lab: Nested Action")
                    }
                }

                Divider()

                Button("Disabled Action") {}
                    .disabled(true)
            }
        }
    }
}
