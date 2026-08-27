//
//  File: AppKitWindowMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
import Foundation
@_implementationOnly import AppKit

@MainActor
private final class AppKitWindowMenuActionTarget: NSObject {
    let action: WindowMenu.Action

    init(action: @escaping WindowMenu.Action) {
        self.action = action
    }

    @objc
    func performMenuAction(_ sender: Any?) {
        action()
    }
}

/// Maps per-window menu capabilities onto AppKit's single application menu.
///
/// Root windows register only after receiving a snapshot. Presentation-child
/// windows therefore cannot replace the current root menu merely by becoming
/// key or main.
@MainActor
private final class AppKitWindowMenuCoordinator: NSObject {
    private struct Entry {
        weak var controller: AppKitWindowMenuController?
    }

    static let shared = AppKitWindowMenuCoordinator()

    private var controllers: [ObjectIdentifier: Entry] = [:]
    private weak var activeController: AppKitWindowMenuController?

    private override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeKeyOrMain(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeKeyOrMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc
    private func windowDidBecomeKeyOrMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else {
            return
        }
        activateController(for: window)
    }

    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        let application = NSApplication.shared
        guard let window = application.keyWindow ?? application.mainWindow else {
            return
        }
        activateController(for: window)
    }

    func controllerDidChange(_ controller: AppKitWindowMenuController) {
        removeReleasedControllers()

        guard let window = controller.nativeWindow,
              controller.nativeMenuTree != nil else {
            unregister(controller)
            return
        }

        controllers[ObjectIdentifier(window)] = Entry(controller: controller)
        if activeController === controller
            || window.isKeyWindow
            || window.isMainWindow
            || activeController == nil {
            install(controller)
        }
    }

    func unregister(_ controller: AppKitWindowMenuController) {
        if let window = controller.nativeWindow {
            let key = ObjectIdentifier(window)
            if controllers[key]?.controller === controller {
                controllers[key] = nil
            }
        } else {
            controllers = controllers.filter {
                $0.value.controller !== controller
            }
        }

        guard activeController === controller else {
            return
        }
        activeController = nil

        if let fallback = fallbackController() {
            install(fallback)
        } else {
            clearApplicationMenu(ifOwnedBy: controller)
        }
    }

    private func activateController(for window: NSWindow) {
        removeReleasedControllers()
        guard let controller = controllers[ObjectIdentifier(window)]?.controller,
              controller.nativeMenuTree != nil else {
            // Presentation children do not own a root menu. When one becomes
            // key, keep the current root controller installed.
            return
        }
        install(controller)
    }

    private func install(_ controller: AppKitWindowMenuController) {
        guard let tree = controller.nativeMenuTree else {
            return
        }
        activeController = controller

        let application = NSApplication.shared
        application.mainMenu = tree.root
        application.windowsMenu = tree.windowMenu
        application.helpMenu = tree.helpMenu
        application.servicesMenu = tree.servicesMenu
    }

    private func clearApplicationMenu(
        ifOwnedBy controller: AppKitWindowMenuController
    ) {
        let application = NSApplication.shared
        guard application.mainMenu === controller.nativeMenuTree?.root else {
            return
        }
        application.windowsMenu = nil
        application.helpMenu = nil
        application.servicesMenu = nil
        application.mainMenu = nil
    }

    private func fallbackController() -> AppKitWindowMenuController? {
        let application = NSApplication.shared
        if let keyWindow = application.keyWindow,
           let controller = controllers[ObjectIdentifier(keyWindow)]?.controller,
           controller.nativeMenuTree != nil {
            return controller
        }
        if let mainWindow = application.mainWindow,
           let controller = controllers[ObjectIdentifier(mainWindow)]?.controller,
           controller.nativeMenuTree != nil {
            return controller
        }
        return controllers.values.lazy.compactMap(\.controller).first {
            $0.nativeWindow?.isVisible == true && $0.nativeMenuTree != nil
        }
    }

    private func removeReleasedControllers() {
        controllers = controllers.filter {
            $0.value.controller != nil
        }
    }
}

@MainActor
final class AppKitWindowMenuController: NSObject,
                                        WindowMenuController,
                                        NSMenuDelegate {
    struct NativeMenuTree {
        let root: NSMenu
        var windowMenu: NSMenu?
        var helpMenu: NSMenu?
        var servicesMenu: NSMenu?
    }

    private struct MenuRegistration {
        let id: WindowMenu.ID?
    }

    weak var delegate: (any WindowMenuControllerDelegate)?
    private(set) var menu: WindowMenu?
    private(set) weak var nativeWindow: NSWindow?
    private(set) var nativeMenuTree: NativeMenuTree?

    private var menuRegistrations: [ObjectIdentifier: MenuRegistration] = [:]
    // NSMenuItem does not own a durable Swift closure. Keep Objective-C targets
    // alive for exactly the lifetime of the native tree built from a snapshot.
    private var actionTargets: [AppKitWindowMenuActionTarget] = []

    init(window: NSWindow) {
        self.nativeWindow = window
    }

    func setMenu(_ menu: WindowMenu?) {
        self.menu = menu

        guard let menu else {
            AppKitWindowMenuCoordinator.shared.unregister(self)
            nativeMenuTree = nil
            menuRegistrations.removeAll()
            actionTargets.removeAll()
            return
        }

        menuRegistrations.removeAll(keepingCapacity: true)
        actionTargets.removeAll(keepingCapacity: true)

        nativeMenuTree = makeNativeMenuTree(menu)
        AppKitWindowMenuCoordinator.shared.controllerDidChange(self)
    }

    func invalidate() {
        AppKitWindowMenuCoordinator.shared.unregister(self)
        nativeMenuTree = nil
        menuRegistrations.removeAll()
        actionTargets.removeAll()
        menu = nil
        nativeWindow = nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let id = menuRegistrations[ObjectIdentifier(menu)]?.id
        delegate?.windowMenuController(self, needsUpdateMenu: id)
    }

    private func makeNativeMenuTree(_ snapshot: WindowMenu) -> NativeMenuTree {
        let root = NSMenu(title: "")
        root.autoenablesItems = false
        register(root, id: nil)

        var tree = NativeMenuTree(root: root)
        for menu in snapshot.menus {
            let nativeItem = makeNativeMenuItem(for: menu)
            let nativeMenu = makeNativeMenu(menu, tree: &tree)
            nativeItem.submenu = nativeMenu
            root.addItem(nativeItem)
        }
        return tree
    }

    private func makeNativeMenu(
        _ menu: WindowMenu.Menu,
        tree: inout NativeMenuTree
    ) -> NSMenu {
        let nativeMenu = NSMenu(title: menu.title)
        nativeMenu.autoenablesItems = menu.usesPlatformItemValidation
        register(nativeMenu, id: menu.id)

        switch menu.role {
        case .window where tree.windowMenu == nil:
            tree.windowMenu = nativeMenu
        case .help where tree.helpMenu == nil:
            tree.helpMenu = nativeMenu
        case .services where tree.servicesMenu == nil:
            tree.servicesMenu = nativeMenu
        default:
            break
        }

        for element in menu.elements {
            switch element {
            case let .item(item):
                nativeMenu.addItem(makeNativeMenuItem(for: item))
            case let .submenu(submenu):
                let nativeItem = makeNativeMenuItem(for: submenu)
                nativeItem.submenu = makeNativeMenu(submenu, tree: &tree)
                nativeMenu.addItem(nativeItem)
            case .separator:
                nativeMenu.addItem(.separator())
            }
        }
        return nativeMenu
    }

    private func makeNativeMenuItem(for item: WindowMenu.Item) -> NSMenuItem {
        let shortcut = item.shortcut.map(nativeShortcut) ?? ("", [])
        let nativeItem = NSMenuItem(
            title: item.title,
            action: nil,
            keyEquivalent: shortcut.0
        )
        nativeItem.keyEquivalentModifierMask = shortcut.1
        nativeItem.isEnabled = item.isEnabled
        nativeItem.isHidden = item.isHidden
        nativeItem.isAlternate = item.isAlternate
        nativeItem.indentationLevel = max(0, item.indentationLevel)
        nativeItem.allowsKeyEquivalentWhenHidden =
            item.allowsShortcutWhenHidden
        nativeItem.state = nativeState(item.state)
        nativeItem.toolTip = item.toolTip
        if let id = item.id {
            nativeItem.identifier = NSUserInterfaceItemIdentifier(id)
        }
        nativeItem.image = makeNativeImage(
            item.image,
            isTemplate: item.imageIsTemplate,
            scalesToFit: item.scalesImageToFit
        )

        if let action = item.action {
            let target = AppKitWindowMenuActionTarget(action: action)
            actionTargets.append(target)
            nativeItem.target = target
            nativeItem.action = #selector(
                AppKitWindowMenuActionTarget.performMenuAction(_:)
            )
        }
        return nativeItem
    }

    private func makeNativeMenuItem(for menu: WindowMenu.Menu) -> NSMenuItem {
        let nativeItem = NSMenuItem(
            title: menu.title,
            action: nil,
            keyEquivalent: ""
        )
        nativeItem.isEnabled = menu.isEnabled
        nativeItem.isHidden = menu.isHidden
        if let id = menu.id {
            nativeItem.identifier = NSUserInterfaceItemIdentifier(id)
        }
        nativeItem.image = makeNativeImage(
            menu.image,
            isTemplate: menu.imageIsTemplate,
            scalesToFit: menu.scalesImageToFit
        )
        return nativeItem
    }

    private func register(_ menu: NSMenu, id: WindowMenu.ID?) {
        menu.delegate = self
        menuRegistrations[ObjectIdentifier(menu)] = MenuRegistration(id: id)
    }

    private func nativeState(_ state: WindowMenu.State) -> NSControl.StateValue {
        switch state {
        case .off: .off
        case .on: .on
        case .mixed: .mixed
        }
    }

    private func nativeShortcut(
        _ shortcut: WindowMenu.Shortcut
    ) -> (String, NSEvent.ModifierFlags) {
        let key: String = switch shortcut.key {
        case let .character(character):
            String(character).lowercased()
        case let .virtual(key):
            nativeKeyEquivalent(key)
        }

        var modifiers: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.capsLock) {
            modifiers.insert(.capsLock)
        }
        if shortcut.modifiers.contains(.shift) {
            modifiers.insert(.shift)
        }
        if shortcut.modifiers.contains(.control) {
            modifiers.insert(.control)
        }
        if shortcut.modifiers.contains(.option) {
            modifiers.insert(.option)
        }
        if shortcut.modifiers.contains(.command) {
            modifiers.insert(.command)
        }
        if shortcut.modifiers.contains(.numericPad) {
            modifiers.insert(.numericPad)
        }
        if shortcut.modifiers.contains(.function) {
            modifiers.insert(.function)
        }
        return (key, modifiers)
    }

    private func nativeKeyEquivalent(_ key: VirtualKey) -> String {
        switch key {
        case .none: ""
        case .escape: "\u{1B}"
        case .f1: "\u{F704}"
        case .f2: "\u{F705}"
        case .f3: "\u{F706}"
        case .f4: "\u{F707}"
        case .f5: "\u{F708}"
        case .f6: "\u{F709}"
        case .f7: "\u{F70A}"
        case .f8: "\u{F70B}"
        case .f9: "\u{F70C}"
        case .f10: "\u{F70D}"
        case .f11: "\u{F70E}"
        case .f12: "\u{F70F}"
        case .f13: "\u{F710}"
        case .f14: "\u{F711}"
        case .f15: "\u{F712}"
        case .f16: "\u{F713}"
        case .f17: "\u{F714}"
        case .f18: "\u{F715}"
        case .f19: "\u{F716}"
        case .f20: "\u{F717}"
        case .num0, .pad0: "0"
        case .num1, .pad1: "1"
        case .num2, .pad2: "2"
        case .num3, .pad3: "3"
        case .num4, .pad4: "4"
        case .num5, .pad5: "5"
        case .num6, .pad6: "6"
        case .num7, .pad7: "7"
        case .num8, .pad8: "8"
        case .num9, .pad9: "9"
        case .a: "a"
        case .b: "b"
        case .c: "c"
        case .d: "d"
        case .e: "e"
        case .f: "f"
        case .g: "g"
        case .h: "h"
        case .i: "i"
        case .j: "j"
        case .k: "k"
        case .l: "l"
        case .m: "m"
        case .n: "n"
        case .o: "o"
        case .p: "p"
        case .q: "q"
        case .r: "r"
        case .s: "s"
        case .t: "t"
        case .u: "u"
        case .v: "v"
        case .w: "w"
        case .x: "x"
        case .y: "y"
        case .z: "z"
        case .period, .padPeriod: "."
        case .comma: ","
        case .slash, .padSlash: "/"
        case .tab: "\t"
        case .accentTilde: "`"
        case .backspace: "\u{7F}"
        case .semicolon: ";"
        case .quote: "'"
        case .backslash: "\\"
        case .equal, .padEqual: "="
        case .hyphen, .padMinus: "-"
        case .space: " "
        case .openBracket: "["
        case .closeBracket: "]"
        case .return, .enter: "\r"
        case .insert: "\u{F727}"
        case .home: "\u{F729}"
        case .pageUp: "\u{F72C}"
        case .pageDown: "\u{F72D}"
        case .end: "\u{F72B}"
        case .delete: "\u{F728}"
        case .left: "\u{F702}"
        case .right: "\u{F703}"
        case .up: "\u{F700}"
        case .down: "\u{F701}"
        case .padAsterisk: "*"
        case .padPlus: "+"
        case .capslock, .fn, .numlock,
             .leftShift, .rightShift,
             .leftOption, .rightOption,
             .leftControl, .rightControl,
             .leftCommand, .rightCommand:
            ""
        }
    }

    private func makeNativeImage(
        _ image: Image?,
        isTemplate: Bool,
        scalesToFit: Bool
    ) -> NSImage? {
        // WindowMenu carries a backend-neutral CPU image. Encoding here keeps
        // AppKit types and image construction confined to this adapter.
        guard let image,
              let data = image.encode(format: .png),
              let nativeImage = NSImage(data: data) else {
            return nil
        }
        nativeImage.isTemplate = isTemplate

        if scalesToFit {
            let maximumDimension: CGFloat = 16
            let size = nativeImage.size
            let largestDimension = max(size.width, size.height)
            if largestDimension > maximumDimension {
                let scale = maximumDimension / largestDimension
                nativeImage.size = NSSize(
                    width: size.width * scale,
                    height: size.height * scale
                )
            }
        }
        return nativeImage
    }
}

#endif // if ENABLE_APPKIT
