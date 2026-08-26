import Foundation
import VUI

struct ContextMenuLabSheet: View {
    let onClose: () -> Void

    @Environment(\.modalSessionUsingPlatformWindow)
    private var currentSheetUsesPlatformWindow

    @State private var usesPlatformPresentationWindows = true
    @State private var contextMenuToggle = true
    @State private var contextMenuLiveCount = 0

    private var contextMenusUsePlatformWindows: Bool {
        currentSheetUsesPlatformWindow == true && usesPlatformPresentationWindows
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Context Menus")
                .font(.system(size: 22, weight: .semibold))

            Toggle(
                "Open Context Menus in Platform Windows",
                isOn: Binding(
                    get: { contextMenusUsePlatformWindows },
                    set: { usesPlatformPresentationWindows = $0 }
                )
            )
            .disabled(currentSheetUsesPlatformWindow != true)

            HStack {
                menu("Menu Action") {
                    print("PrimaryAction")
                }
                menu("Open Menu")
                menu("Button Style") {
                    print("ButtonStyle PrimaryAction")
                }
                .menuStyle(ButtonMenuStyle())
            }

            Button("Start Live Refresh: \(contextMenuLiveCount)") {
                startLiveRefreshProbe()
            }

            HStack {
                Text("Context Menu")
                    .contextMenu {
                        ContextMenuLabItems(
                            toggle: $contextMenuToggle,
                            liveCount: contextMenuLiveCount
                        )
                    }
                Divider()
                Text("Long Press")
                    .contextMenu {
                        ContextMenuLabItems(
                            toggle: $contextMenuToggle,
                            liveCount: contextMenuLiveCount
                        )
                    }
                    .environment(\.contextMenuTriggerPolicy, .longPress)
            }
            .padding(8)
            .frame(maxHeight: 40)
            .border(.blue, width: 1)

            Text("Open a menu while Live Refresh runs to exercise dynamic item replacement.")
                .font(.system(.caption))
                .foregroundColor(.secondary)

            Button("Close") {
                onClose()
            }
        }
        .padding(20)
        .frame(width: 680, height: 360)
        .environment(
            \.presentationChildUsingPlatformWindow,
            contextMenusUsePlatformWindows
        )
    }

    @ViewBuilder
    func menuContent(_ text: String) -> some View {
        Button("MenuItem1") { print("MenuItem1") }
        Button("MenuItem2") { print("MenuItem2") }
        Label { Text("Label") } icon: { Text("ICON") }
        Menu("Submenu") {
            Button("Sub-button1") { print("Sub-button1") }
            Button("Sub-button2") { print("Sub-button2") }
        } primaryAction: {
            print("Submenu.primaryAction - \(text)")
        }
        Menu("Submenu2") {
            Button("Sub-button1") { print("Sub-button1") }
            Button("Sub-button2") { print("Sub-button2") }
        } primaryAction: {
            print("Submenu2.primaryAction - \(text)")
        }
    }

    func menu(_ text: String, primaryAction: (() -> Void)? = nil) -> some View {
        if let primaryAction {
            Menu(text) {
                menuContent(text)
            } primaryAction: {
                primaryAction()
            }
        } else {
            Menu(text) {
                menuContent(text)
            }
        }
    }

    func startLiveRefreshProbe() {
        contextMenuLiveCount = 0
        contextMenuToggle = false
        let liveCount = $contextMenuLiveCount
        let liveToggle = $contextMenuToggle
        for step in 1...10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(step * 450)) {
                liveCount.wrappedValue = step
                liveToggle.wrappedValue = step.isMultiple(of: 2)
            }
        }
    }
}

private struct ContextMenuLabItems: View {
    @Binding var toggle: Bool
    let liveCount: Int

    var body: some View {
        VStack {
            Text("Live Count \(liveCount)")
            Button("Live Enabled \(liveCount)") {
                print("Live Enabled - clicked \(liveCount)")
            }
            .environment(\.isEnabled, liveCount.isMultiple(of: 2))
            Toggle("Live Toggle \(liveCount)", isOn: $toggle)
            if liveCount > 0 {
                Button("Inserted Live \(liveCount)") {
                    print("Inserted Live - clicked \(liveCount)")
                }
            }
            if liveCount < 6 {
                Button("Removed Live \(liveCount)") {
                    print("Removed Live - clicked \(liveCount)")
                }
            }
            Divider()
            Text("1234")
            Label("Static Label", systemImage: "star.fill")
            Button {
                print("Disabled Image - clicked")
            } label: {
                Label("Disabled Image", systemImage: "star.fill")
            }
            .environment(\.isEnabled, false)
            Button("Disabled Shortcut") {
                print("Disabled Shortcut - clicked")
            }
            .keyboardShortcut("d", modifiers: [.command, .option])
            .environment(\.isEnabled, false)
            Toggle("Disabled Toggle", isOn: .constant(true))
                .environment(\.isEnabled, false)
            Menu("Disabled More") {
                Button("Disabled Nested") {
                    print("Disabled Nested - clicked")
                }
            }
            .environment(\.isEnabled, false)
            Button("Menu1") { print("Menu1 - clicked") }
            Button("Shortcut Menu") { print("Shortcut Menu - clicked") }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            Toggle("Toggle Menu", isOn: $toggle)
            Divider()
            Section("Section Header") {
                Button("Section Action") { print("Section Action - clicked") }
            }
            Button("Menu2") { print("Menu2 - clicked") }
            Menu("More") {
                Button("Nested Live \(liveCount)") {
                    print("Nested Live - clicked \(liveCount)")
                }
                Button("Rename", action: {})
                Button("Developer Mode", action: {})
            }
        }
    }
}
