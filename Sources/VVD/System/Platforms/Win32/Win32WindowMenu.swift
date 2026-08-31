//
//  File: Win32WindowMenu.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

#if ENABLE_WIN32
import Foundation
import WinSDK

private func menuKey(_ menu: HMENU) -> UInt {
    UInt(bitPattern: menu)
}

private enum MenuText {
    static func title(_ title: String, accessKey: Character?) -> String {
        var result = ""
        var insertedAccessKey = false

        for character in title {
            if !insertedAccessKey,
               let accessKey,
               String(character).caseInsensitiveCompare(String(accessKey)) ==
                .orderedSame {
                result.append("&")
                insertedAccessKey = true
            }
            if character == "&" {
                result.append("&&")
            } else {
                result.append(character)
            }
        }

        if let accessKey, !insertedAccessKey {
            result += " (&\(accessKey))"
        }
        return result
    }

    static func shortcut(_ shortcut: WindowMenu.Shortcut) -> String {
        var components: [String] = []
        if shortcut.modifiers.contains(.control) { components.append("Ctrl") }
        if shortcut.modifiers.contains(.option) { components.append("Alt") }
        if shortcut.modifiers.contains(.shift) { components.append("Shift") }
        if shortcut.modifiers.contains(.command) { components.append("Win") }
        components.append(keyName(shortcut.key))
        return components.joined(separator: "+")
    }

    private static func keyName(_ key: WindowMenu.Shortcut.Key) -> String {
        switch key {
        case let .character(character):
            return String(character).uppercased()
        case let .virtual(key):
            return switch key {
            case .none: ""
            case .escape: "Esc"
            case .f1: "F1"
            case .f2: "F2"
            case .f3: "F3"
            case .f4: "F4"
            case .f5: "F5"
            case .f6: "F6"
            case .f7: "F7"
            case .f8: "F8"
            case .f9: "F9"
            case .f10: "F10"
            case .f11: "F11"
            case .f12: "F12"
            case .f13: "F13"
            case .f14: "F14"
            case .f15: "F15"
            case .f16: "F16"
            case .f17: "F17"
            case .f18: "F18"
            case .f19: "F19"
            case .f20: "F20"
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
            case .a: "A"
            case .b: "B"
            case .c: "C"
            case .d: "D"
            case .e: "E"
            case .f: "F"
            case .g: "G"
            case .h: "H"
            case .i: "I"
            case .j: "J"
            case .k: "K"
            case .l: "L"
            case .m: "M"
            case .n: "N"
            case .o: "O"
            case .p: "P"
            case .q: "Q"
            case .r: "R"
            case .s: "S"
            case .t: "T"
            case .u: "U"
            case .v: "V"
            case .w: "W"
            case .x: "X"
            case .y: "Y"
            case .z: "Z"
            case .period, .padPeriod: "."
            case .comma: ","
            case .slash, .padSlash: "/"
            case .tab: "Tab"
            case .accentTilde: "`"
            case .backspace: "Backspace"
            case .semicolon: ";"
            case .quote: "'"
            case .backslash: "\\"
            case .equal, .padEqual: "="
            case .hyphen, .padMinus: "-"
            case .space: "Space"
            case .openBracket: "["
            case .closeBracket: "]"
            case .capslock: "Caps Lock"
            case .return, .enter: "Enter"
            case .fn: "Fn"
            case .insert: "Insert"
            case .home: "Home"
            case .pageUp: "Page Up"
            case .pageDown: "Page Down"
            case .end: "End"
            case .delete: "Delete"
            case .left: "Left"
            case .right: "Right"
            case .up: "Up"
            case .down: "Down"
            case .leftShift, .rightShift: "Shift"
            case .leftOption, .rightOption: "Alt"
            case .leftControl, .rightControl: "Ctrl"
            case .leftCommand, .rightCommand: "Win"
            case .numlock: "Num Lock"
            case .padAsterisk: "*"
            case .padPlus: "+"
            }
        }
    }
}

private struct MenuShortcutKey: Hashable {
    let virtualKey: UINT
    let modifiers: KeyboardModifierFlags
}

private final class NativeMenuTree {
    private struct MenuRegistration {
        let id: WindowMenu.ID?
    }

    let root: HMENU
    private var menuRegistrations: [UInt: MenuRegistration] = [:]
    private(set) var actions: [UINT: WindowMenu.Action] = [:]
    private(set) var shortcuts: [MenuShortcutKey: UINT] = [:]
    private var bitmaps: [HBITMAP] = []
    private var nextCommandID: UINT = 0x1000

    init?(_ snapshot: WindowMenu) {
        guard let root = CreateMenu() else { return nil }
        self.root = root
        menuRegistrations[menuKey(root)] = MenuRegistration(id: nil)

        for menu in snapshot.menus {
            if menu.isHidden {
                registerHiddenShortcuts(in: menu.elements)
                continue
            }
            guard insert(menu, into: root, at: GetMenuItemCount(root)) else {
                DestroyMenu(root)
                bitmaps.forEach { DeleteObject($0) }
                return nil
            }
        }
    }

    deinit {
        DestroyMenu(root)
        bitmaps.forEach { DeleteObject($0) }
    }

    func action(for commandID: UINT) -> WindowMenu.Action? {
        actions[commandID]
    }

    func contains(_ menu: HMENU) -> Bool {
        if menu == root {
            return true
        }
        return menuRegistrations[menuKey(menu)] != nil
    }

    func id(for menu: HMENU) -> WindowMenu.ID? {
        if menu == root {
            return nil
        }
        return menuRegistrations[menuKey(menu)]?.id
    }

    func action(forVirtualKey virtualKey: UINT) -> WindowMenu.Action? {
        let key = MenuShortcutKey(
            virtualKey: virtualKey,
            modifiers: Self.currentModifiers()
        )
        guard let commandID = shortcuts[key] else { return nil }
        return actions[commandID]
    }

    private func insert(
        _ menu: WindowMenu.Menu,
        into parent: HMENU,
        at index: Int32
    ) -> Bool {
        guard let submenu = CreatePopupMenu() else { return false }
        menuRegistrations[menuKey(submenu)] = MenuRegistration(id: menu.id)

        for element in menu.elements {
            let position = GetMenuItemCount(submenu)
            let inserted: Bool
            switch element {
            case let .item(item):
                if item.isHidden {
                    registerHiddenShortcut(item)
                    inserted = true
                } else {
                    inserted = insert(item, into: submenu, at: position)
                }
            case let .submenu(child):
                if child.isHidden {
                    registerHiddenShortcuts(in: child.elements)
                    inserted = true
                } else {
                    inserted = insert(child, into: submenu, at: position)
                }
            case .separator:
                inserted = insertSeparator(into: submenu, at: position)
            }
            if !inserted {
                DestroyMenu(submenu)
                return false
            }
        }

        var info = MENUITEMINFOW()
        info.cbSize = UINT(MemoryLayout<MENUITEMINFOW>.size)
        info.fMask = UINT(MIIM_FTYPE | MIIM_STATE | MIIM_STRING | MIIM_SUBMENU)
        info.fType = UINT(MFT_STRING)
        info.fState = menu.isEnabled ? UINT(MFS_ENABLED) : UINT(MFS_DISABLED | MFS_GRAYED)
        info.hSubMenu = submenu

        if let bitmap = makeBitmap(
            menu.image,
            isTemplate: menu.imageIsTemplate,
            scalesToFit: menu.scalesImageToFit
        ) {
            info.fMask |= UINT(MIIM_BITMAP)
            info.hbmpItem = bitmap
        }

        let title = MenuText.title(menu.title, accessKey: menu.accessKey)
        guard insert(info: &info, title: title, into: parent, at: index) else {
            DestroyMenu(submenu)
            return false
        }
        return true
    }

    private func insert(
        _ item: WindowMenu.Item,
        into parent: HMENU,
        at index: Int32
    ) -> Bool {
        guard let commandID = registerAction(for: item) else { return false }

        var info = MENUITEMINFOW()
        info.cbSize = UINT(MemoryLayout<MENUITEMINFOW>.size)
        info.fMask = UINT(MIIM_FTYPE | MIIM_STATE | MIIM_STRING | MIIM_ID)
        info.fType = UINT(MFT_STRING)
        info.fState = item.isEnabled ? UINT(MFS_ENABLED) : UINT(MFS_DISABLED | MFS_GRAYED)
        if item.state != .off {
            info.fState |= UINT(MFS_CHECKED)
        }
        info.wID = commandID

        if let bitmap = makeBitmap(
            item.image,
            isTemplate: item.imageIsTemplate,
            scalesToFit: item.scalesImageToFit
        ) {
            info.fMask |= UINT(MIIM_BITMAP)
            info.hbmpItem = bitmap
        }

        let indentation = String(
            repeating: "    ",
            count: max(item.indentationLevel, 0)
        )
        var title = indentation + MenuText.title(
            item.title,
            accessKey: item.accessKey
        )
        if let shortcut = item.shortcut {
            title += "\t" + MenuText.shortcut(shortcut)
        }
        return insert(info: &info, title: title, into: parent, at: index)
    }

    private func insertSeparator(into menu: HMENU, at index: Int32) -> Bool {
        var info = MENUITEMINFOW()
        info.cbSize = UINT(MemoryLayout<MENUITEMINFOW>.size)
        info.fMask = UINT(MIIM_FTYPE)
        info.fType = UINT(MFT_SEPARATOR)
        return InsertMenuItemW(menu, UINT(index), true, &info)
    }

    private func insert(
        info: inout MENUITEMINFOW,
        title: String,
        into menu: HMENU,
        at index: Int32
    ) -> Bool {
        info.cch = UINT(title.utf16.count)
        return title.withCString(encodedAs: UTF16.self) { titlePointer in
            info.dwTypeData = UnsafeMutablePointer(mutating: titlePointer)
            return InsertMenuItemW(menu, UINT(index), true, &info)
        }
    }

    private func registerAction(for item: WindowMenu.Item) -> UINT? {
        guard let action = item.action else { return 0 }
        guard nextCommandID < 0xf000 else { return nil }

        let commandID = nextCommandID
        nextCommandID += 1
        actions[commandID] = action

        if item.isEnabled,
           (!item.isHidden || item.allowsShortcutWhenHidden),
           let shortcut = item.shortcut,
           let key = Self.shortcutKey(shortcut),
           shortcuts[key] == nil {
            shortcuts[key] = commandID
        }
        return commandID
    }

    private func registerHiddenShortcut(_ item: WindowMenu.Item) {
        guard item.allowsShortcutWhenHidden else { return }
        _ = registerAction(for: item)
    }

    private func registerHiddenShortcuts(in elements: [WindowMenu.Element]) {
        for element in elements {
            switch element {
            case let .item(item):
                registerHiddenShortcut(item)
            case let .submenu(menu):
                registerHiddenShortcuts(in: menu.elements)
            case .separator:
                break
            }
        }
    }

    private func makeBitmap(
        _ image: Image?,
        isTemplate: Bool,
        scalesToFit: Bool
    ) -> HBITMAP? {
        guard let image else { return nil }

        var width: Int? = nil
        var height: Int? = nil
        if scalesToFit {
            let maximumWidth = max(Int(GetSystemMetrics(SM_CXMENUCHECK)), 1)
            let maximumHeight = max(Int(GetSystemMetrics(SM_CYMENUCHECK)), 1)
            let scale = min(
                1,
                min(
                    Double(maximumWidth) / Double(image.width),
                    Double(maximumHeight) / Double(image.height)
                )
            )
            width = max(Int((Double(image.width) * scale).rounded()), 1)
            height = max(Int((Double(image.height) * scale).rounded()), 1)
        }

        let bitmap = win32CreateARGBBitmap(
            from: image,
            width: width,
            height: height,
            templateColor: isTemplate ? GetSysColor(COLOR_MENUTEXT) : nil
        )
        if let bitmap { bitmaps.append(bitmap) }
        return bitmap
    }

    private static func shortcutKey(
        _ shortcut: WindowMenu.Shortcut
    ) -> MenuShortcutKey? {
        let keyCode: UINT
        var modifiers = normalized(shortcut.modifiers)
        switch shortcut.key {
        case let .character(character):
            guard let translated = translatedKey(for: character) else {
                return nil
            }
            keyCode = translated.virtualKey
            modifiers.formUnion(translated.modifiers)
        case let .virtual(key):
            guard let translated = virtualKey(for: key) else { return nil }
            keyCode = translated
        }
        return MenuShortcutKey(
            virtualKey: keyCode,
            modifiers: modifiers
        )
    }

    private static func normalized(
        _ modifiers: KeyboardModifierFlags
    ) -> KeyboardModifierFlags {
        modifiers.intersection([.control, .option, .shift, .command])
    }

    private static func currentModifiers() -> KeyboardModifierFlags {
        func isDown(_ key: Int32) -> Bool {
            GetKeyState(key) < 0
        }

        var modifiers: KeyboardModifierFlags = []
        if isDown(VK_CONTROL) { modifiers.insert(.control) }
        if isDown(VK_MENU) { modifiers.insert(.option) }
        if isDown(VK_SHIFT) { modifiers.insert(.shift) }
        if isDown(VK_LWIN) || isDown(VK_RWIN) { modifiers.insert(.command) }
        return modifiers
    }

    private static func translatedKey(
        for character: Character
    ) -> (virtualKey: UINT, modifiers: KeyboardModifierFlags)? {
        let codeUnits = Array(String(character).lowercased().utf16)
        guard codeUnits.count == 1 else { return nil }

        let translated = VkKeyScanW(codeUnits[0])
        guard translated != -1 else { return nil }
        let value = UInt16(bitPattern: translated)

        var modifiers: KeyboardModifierFlags = []
        let shiftState = value >> 8
        if shiftState & 0x01 != 0 { modifiers.insert(.shift) }
        if shiftState & 0x02 != 0 { modifiers.insert(.control) }
        if shiftState & 0x04 != 0 { modifiers.insert(.option) }
        return (UINT(value & 0x00ff), modifiers)
    }

    private static func virtualKey(for key: VirtualKey) -> UINT? {
        switch key {
        case .none, .fn, .padEqual:
            nil
        case .escape: UINT(VK_ESCAPE)
        case .f1: UINT(VK_F1)
        case .f2: UINT(VK_F2)
        case .f3: UINT(VK_F3)
        case .f4: UINT(VK_F4)
        case .f5: UINT(VK_F5)
        case .f6: UINT(VK_F6)
        case .f7: UINT(VK_F7)
        case .f8: UINT(VK_F8)
        case .f9: UINT(VK_F9)
        case .f10: UINT(VK_F10)
        case .f11: UINT(VK_F11)
        case .f12: UINT(VK_F12)
        case .f13: UINT(VK_F13)
        case .f14: UINT(VK_F14)
        case .f15: UINT(VK_F15)
        case .f16: UINT(VK_F16)
        case .f17: UINT(VK_F17)
        case .f18: UINT(VK_F18)
        case .f19: UINT(VK_F19)
        case .f20: UINT(VK_F20)
        case .num0: 0x30
        case .num1: 0x31
        case .num2: 0x32
        case .num3: 0x33
        case .num4: 0x34
        case .num5: 0x35
        case .num6: 0x36
        case .num7: 0x37
        case .num8: 0x38
        case .num9: 0x39
        case .a: 0x41
        case .b: 0x42
        case .c: 0x43
        case .d: 0x44
        case .e: 0x45
        case .f: 0x46
        case .g: 0x47
        case .h: 0x48
        case .i: 0x49
        case .j: 0x4a
        case .k: 0x4b
        case .l: 0x4c
        case .m: 0x4d
        case .n: 0x4e
        case .o: 0x4f
        case .p: 0x50
        case .q: 0x51
        case .r: 0x52
        case .s: 0x53
        case .t: 0x54
        case .u: 0x55
        case .v: 0x56
        case .w: 0x57
        case .x: 0x58
        case .y: 0x59
        case .z: 0x5a
        case .period: UINT(VK_OEM_PERIOD)
        case .comma: UINT(VK_OEM_COMMA)
        case .slash: UINT(VK_OEM_2)
        case .tab: UINT(VK_TAB)
        case .accentTilde: UINT(VK_OEM_3)
        case .backspace: UINT(VK_BACK)
        case .semicolon: UINT(VK_OEM_1)
        case .quote: UINT(VK_OEM_7)
        case .backslash: UINT(VK_OEM_5)
        case .equal: UINT(VK_OEM_PLUS)
        case .hyphen: UINT(VK_OEM_MINUS)
        case .space: UINT(VK_SPACE)
        case .openBracket: UINT(VK_OEM_4)
        case .closeBracket: UINT(VK_OEM_6)
        case .capslock: UINT(VK_CAPITAL)
        case .return, .enter: UINT(VK_RETURN)
        case .insert: UINT(VK_INSERT)
        case .home: UINT(VK_HOME)
        case .pageUp: UINT(VK_PRIOR)
        case .pageDown: UINT(VK_NEXT)
        case .end: UINT(VK_END)
        case .delete: UINT(VK_DELETE)
        case .left: UINT(VK_LEFT)
        case .right: UINT(VK_RIGHT)
        case .up: UINT(VK_UP)
        case .down: UINT(VK_DOWN)
        case .leftShift: UINT(VK_LSHIFT)
        case .rightShift: UINT(VK_RSHIFT)
        case .leftOption: UINT(VK_LMENU)
        case .rightOption: UINT(VK_RMENU)
        case .leftControl: UINT(VK_LCONTROL)
        case .rightControl: UINT(VK_RCONTROL)
        case .leftCommand: UINT(VK_LWIN)
        case .rightCommand: UINT(VK_RWIN)
        case .pad0: UINT(VK_NUMPAD0)
        case .pad1: UINT(VK_NUMPAD1)
        case .pad2: UINT(VK_NUMPAD2)
        case .pad3: UINT(VK_NUMPAD3)
        case .pad4: UINT(VK_NUMPAD4)
        case .pad5: UINT(VK_NUMPAD5)
        case .pad6: UINT(VK_NUMPAD6)
        case .pad7: UINT(VK_NUMPAD7)
        case .pad8: UINT(VK_NUMPAD8)
        case .pad9: UINT(VK_NUMPAD9)
        case .numlock: UINT(VK_NUMLOCK)
        case .padSlash: UINT(VK_DIVIDE)
        case .padAsterisk: UINT(VK_MULTIPLY)
        case .padPlus: UINT(VK_ADD)
        case .padMinus: UINT(VK_SUBTRACT)
        case .padPeriod: UINT(VK_DECIMAL)
        }
    }
}

@MainActor
final class Win32WindowMenuController: WindowMenuController {
    private enum PendingUpdate {
        case attach(WindowMenu, NativeMenuTree)
        case detach
    }

    weak var delegate: (any WindowMenuControllerDelegate)?
    private(set) var menu: WindowMenu?
    private weak var window: Win32Window?
    private var nativeTree: NativeMenuTree?
    private var pendingUpdate: PendingUpdate?
    private var isTrackingMenu = false

    var hasAttachedMenu: Bool { nativeTree != nil }

    init(window: Win32Window) {
        self.window = window
    }

    func setMenu(_ menu: WindowMenu?) {
        let update: PendingUpdate
        if let menu {
            guard let tree = NativeMenuTree(menu) else {
                Log.error("Unable to create Win32 menu tree")
                return
            }
            update = .attach(menu, tree)
        } else {
            update = .detach
        }

        if isTrackingMenu {
            self.menu = menu
            pendingUpdate = update
            return
        }
        apply(update)
    }

    func invalidate(detachingFrom nativeWindow: HWND? = nil) {
        pendingUpdate = nil
        isTrackingMenu = false
        if let window, window.hWnd != nil {
            _ = window.installNativeMenu(nil, preserveClientSize: false)
        } else if let nativeWindow {
            SetMenu(nativeWindow, nil)
        }
        delegate = nil
        menu = nil
        nativeTree = nil
        window = nil
    }

    func menuTrackingDidBegin() {
        isTrackingMenu = true
    }

    func menuTrackingDidEnd() {
        isTrackingMenu = false
        guard let pendingUpdate else { return }
        self.pendingUpdate = nil
        apply(pendingUpdate)
    }

    func menuWillOpen(_ nativeMenu: HMENU?) {
        guard let nativeMenu, let nativeTree else { return }
        guard nativeTree.contains(nativeMenu) else { return }
        delegate?.windowMenuController(
            self,
            needsUpdateMenu: nativeTree.id(for: nativeMenu)
        )
    }

    func performCommand(_ commandID: UINT) -> Bool {
        guard let action = nativeTree?.action(for: commandID) else {
            return false
        }
        action()
        return true
    }

    func performShortcut(virtualKey: UINT) -> Bool {
        guard let action = nativeTree?.action(forVirtualKey: virtualKey) else {
            return false
        }
        action()
        return true
    }

    private func apply(_ update: PendingUpdate) {
        let nextMenu: WindowMenu?
        let nextTree: NativeMenuTree?
        switch update {
        case let .attach(menu, tree):
            nextMenu = menu
            nextTree = tree
        case .detach:
            nextMenu = nil
            nextTree = nil
        }

        guard let window,
              window.installNativeMenu(
                nextTree?.root,
                preserveClientSize: true
              ) else {
            return
        }
        menu = nextMenu
        nativeTree = nextTree
    }
}
#endif // ENABLE_WIN32
