import VUI

@main
struct TestApp1: App {
    var body: some Scene {
        WindowGroup("TestApp1") {
            ContentView()
                .toolbar(id: "testapp-main-toolbar") {
                    ToolbarItem(id: "run") {
                        Button("Run Toolbar Action", systemImage: "play") {
                            print("Toolbar Lab: Run Toolbar Action")
                        }
                    }

                    ToolbarItem(id: "optional", showsByDefault: false) {
                        Button("Optional Toolbar Action") {
                            print("Toolbar Lab: Optional Toolbar Action")
                        }
                    }
                }
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
            position: .init(x: 5, y: 73)
        )
        .updateFrameRate(
            forActiveState: 60,
            forInactiveState: 30,
            renderingMode: .continuousWithDisplaySync
        )
        .commandMenuPresentationStyle(.window)
        .commands {
            ToolbarCommands()

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
