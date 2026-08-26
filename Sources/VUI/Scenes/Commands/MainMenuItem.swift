//
//  File: MainMenuItem.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// A resolved main-menu entry retains command groups as views. The presentation
// host decides later whether those views become VUI overlays or platform menu
// items.
struct MainMenuItem {
    enum Identifier: Hashable {
        case custom(UUID)
        case app
        case file
        case edit
        case format
        case view
        case window
        case help
        case dock
        case invalid
        case root
    }

    enum Content: View {
        case item(MainMenuItem)

        var body: some View {
            switch self {
            case let .item(item):
                // Each placement contributes one group. Separators belong
                // between groups, never after the final group.
                ForEach(0..<item.groups.count) { index in
                    TupleView((
                        item.groups[index].viewContent,
                        index == item.groups.count - 1 ? nil : Divider()
                    ))
                }
            }
        }
    }

    fileprivate struct Template {
        struct Options: OptionSet {
            var rawValue: Int

            // View remains available even when no placement has contributed a
            // command group. Other canonical templates are omitted when empty.
            static let keepsEmptyMenu = Options(rawValue: 1 << 0)
        }

        var name: String
        var id: Identifier
        var options: Options
        var expectedPlacements: [CommandGroupPlacement]
    }

    var name: String
    var id: Identifier
    var groups: [CommandAccumulator.Result]
}

extension _ResolvedCommands {
    // Text storage is immutable after construction. These process-wide labels
    // are resolved against the current menu environment on every pass.
    nonisolated(unsafe) private static let fileItem = Text(
        "File",
        bundle: .module,
        comment: "Main Menu"
    )
    nonisolated(unsafe) private static let editItem = Text(
        "Edit",
        bundle: .module,
        comment: "Main Menu"
    )
    nonisolated(unsafe) private static let formatItem = Text(
        "Format",
        bundle: .module,
        comment: "Main Menu"
    )
    nonisolated(unsafe) private static let viewItem = Text(
        "View",
        bundle: .module,
        comment: "Main Menu"
    )
    nonisolated(unsafe) private static let windowItem = Text(
        "Window",
        bundle: .module,
        comment: "Main Menu"
    )
    nonisolated(unsafe) private static let helpItem = Text(
        "Help",
        bundle: .module,
        comment: "Main Menu"
    )

    func mainMenuItems(env: EnvironmentValues) -> [MainMenuItem] {
        var templates: [MainMenuItem.Template] = [
            MainMenuItem.Template(
                name: currentAppName(),
                id: .app,
                options: [],
                expectedPlacements: [
                    .appInfo,
                    .appSettings,
                    .systemServices,
                    .appVisibility,
                    .appTermination,
                ]
            ),
            MainMenuItem.Template(
                name: Self.fileItem._resolveText(in: env),
                id: .file,
                options: [],
                expectedPlacements: [
                    .newItem,
                    .openItem,
                    .saveItem,
                    .importExport,
                    .printItem,
                ]
            ),
            MainMenuItem.Template(
                name: Self.editItem._resolveText(in: env),
                id: .edit,
                options: [],
                expectedPlacements: [
                    .undoRedo,
                    .pasteboard,
                    .textEditing,
                ]
            ),
            MainMenuItem.Template(
                name: Self.formatItem._resolveText(in: env),
                id: .format,
                options: [],
                expectedPlacements: [.textFormatting]
            ),
            MainMenuItem.Template(
                name: Self.viewItem._resolveText(in: env),
                id: .view,
                options: [.keepsEmptyMenu],
                expectedPlacements: [
                    .toolbar,
                    .defaultUtilityWindows,
                    .sidebar,
                ]
            ),
        ]

        // Top-level CommandMenu placements retain declaration order and sit
        // between the canonical View and Window templates.
        templates.append(contentsOf: topLevelCommands.map { key in
            MainMenuItem.Template(
                name: key.placement.name._resolveText(in: env),
                id: .custom(key.placement.id),
                options: [],
                expectedPlacements: [key.placement]
            )
        })

        templates.append(contentsOf: [
            MainMenuItem.Template(
                name: Self.windowItem._resolveText(in: env),
                id: .window,
                options: [],
                expectedPlacements: [
                    .windowSize,
                    .singleWindowList,
                    .windowList,
                    .windowArrangement,
                ]
            ),
            MainMenuItem.Template(
                name: Self.helpItem._resolveText(in: env),
                id: .help,
                options: [],
                expectedPlacements: [.help]
            ),
        ])

        return templates.compactMap { template in
            let groups = template.expectedPlacements.compactMap { placement in
                storage[
                    HashableCommandGroupPlacementWrapper(
                        placement: placement
                    )
                ]?.result
            }
            guard !groups.isEmpty
                    || template.options.contains(.keepsEmptyMenu) else {
                return nil
            }
            return MainMenuItem(
                name: template.name,
                id: template.id,
                groups: groups
            )
        }
    }
}

extension CommandGroupPlacement {
    // These framework-owned groups participate in canonical menu ordering but
    // are not part of the public placement surface.
    fileprivate static let openItem = CommandGroupPlacement(
        Text(verbatim: "Open Item"),
        id: UUID()
    )
    fileprivate static let defaultUtilityWindows = CommandGroupPlacement(
        Text(verbatim: "Utility Windows"),
        id: UUID()
    )
}

private func currentAppName() -> String {
    let bundle = Bundle.main
    if let name = localizedBundleValue("CFBundleDisplayName", bundle: bundle) {
        return name
    }
    if let name = localizedBundleValue("CFBundleName", bundle: bundle) {
        return name
    }
    return ProcessInfo.processInfo.processName
}

private func localizedBundleValue(_ key: String, bundle: Bundle) -> String? {
    if let value = bundle.localizedInfoDictionary?[key] as? String {
        return value
    }
    return bundle.infoDictionary?[key] as? String
}
