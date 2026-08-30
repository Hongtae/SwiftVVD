import VUI

private struct TestAppSettingsPresentedKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var testAppSettingsPresented: Binding<Bool>? {
        get { self[TestAppSettingsPresentedKey.self] }
        set { self[TestAppSettingsPresentedKey.self] = newValue }
    }
}

private struct TestAppSettingsCommands: Commands {
    @FocusedBinding(\.testAppSettingsPresented)
    private var settingsPresented

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "settings") {
                settingsPresented = true
            }
            .keyboardShortcut(",", modifiers: [.command])
            .disabled(settingsPresented == nil)
        }
    }
}

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
            alignment: .topTrailing
        )
        .updateFrameRate(
            forActiveState: 60,
            forInactiveState: 30,
            renderingMode: .continuousWithDisplaySync
        )
        .commandMenuPresentationStyle(.window)
        .commands {
            ToolbarCommands()
            TextEditingCommands()
            TestAppSettingsCommands()

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
