//
//  File: WaylandVirtualKey.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

#if ENABLE_WAYLAND
import Foundation
import Wayland
import Glibc

extension VirtualKey {
    static func from(scanCode key: UInt32) -> VirtualKey {
        if key > Int32.max {
            return .none
        }

        switch Int32(key) {
        case KEY_ESC:           return .escape
        case KEY_1:             return .num1
        case KEY_2:             return .num2
        case KEY_3:             return .num3
        case KEY_4:             return .num4
        case KEY_5:             return .num5
        case KEY_6:             return .num6
        case KEY_7:             return .num7
        case KEY_8:             return .num8
        case KEY_9:             return .num9
        case KEY_0:             return .num0
        case KEY_MINUS:         return .hyphen
        case KEY_EQUAL:         return .equal
        case KEY_BACKSPACE:     return .backspace
        case KEY_TAB:           return .tab
        case KEY_Q:             return .q
        case KEY_W:             return .w
        case KEY_E:             return .e
        case KEY_R:             return .r
        case KEY_T:             return .t
        case KEY_Y:             return .y
        case KEY_U:             return .u
        case KEY_I:             return .i
        case KEY_O:             return .o
        case KEY_P:             return .p
        case KEY_LEFTBRACE:     return .openBracket
        case KEY_RIGHTBRACE:    return .closeBracket
        case KEY_ENTER:         return .enter
        case KEY_LEFTCTRL:      return .leftControl
        case KEY_A:             return .a
        case KEY_S:             return .s
        case KEY_D:             return .d
        case KEY_F:             return .f
        case KEY_G:             return .g
        case KEY_H:             return .h
        case KEY_J:             return .j
        case KEY_K:             return .k
        case KEY_L:             return .l
        case KEY_SEMICOLON:     return .semicolon   
        case KEY_APOSTROPHE:    return .quote
        case KEY_GRAVE:         return .accentTilde
        case KEY_LEFTSHIFT:     return .leftShift
        case KEY_BACKSLASH:     return .backslash
        case KEY_Z:             return .z
        case KEY_X:             return .x
        case KEY_C:             return .c
        case KEY_V:             return .v
        case KEY_B:             return .b
        case KEY_N:             return .n
        case KEY_M:             return .m
        case KEY_COMMA:         return .comma
        case KEY_DOT:           return .period
        case KEY_SLASH:         return .slash
        case KEY_RIGHTSHIFT:    return .rightShift
        case KEY_KPASTERISK:    return .padAsterisk
        case KEY_LEFTALT:       return .leftOption
        case KEY_SPACE:         return .space
        case KEY_CAPSLOCK:      return .capslock
        case KEY_F1:            return .f1 
        case KEY_F2:            return .f2
        case KEY_F3:            return .f3
        case KEY_F4:            return .f4
        case KEY_F5:            return .f5
        case KEY_F6:            return .f6
        case KEY_F7:            return .f7
        case KEY_F8:            return .f8
        case KEY_F9:            return .f9
        case KEY_F10:           return .f10
        case KEY_NUMLOCK:       return .numlock
        case KEY_SCROLLLOCK:    return .f14
        case KEY_KP7:           return .pad7
        case KEY_KP8:           return .pad8
        case KEY_KP9:           return .pad9
        case KEY_KPMINUS:       return .padMinus
        case KEY_KP4:           return .pad4
        case KEY_KP5:           return .pad5
        case KEY_KP6:           return .pad6
        case KEY_KPPLUS:        return .padPlus
        case KEY_KP1:           return .pad1
        case KEY_KP2:           return .pad2
        case KEY_KP3:           return .pad3
        case KEY_KP0:           return .pad0
        case KEY_KPDOT:         return .padPeriod

        case KEY_F11:           return .f11
        case KEY_F12:           return .f12

        case KEY_RIGHTCTRL:     return .rightControl
        case KEY_RIGHTALT:      return .rightOption

        case KEY_HOME:          return .home
        case KEY_UP:            return .up
        case KEY_PAGEUP:        return .pageUp
        case KEY_LEFT:          return .left
        case KEY_RIGHT:         return .right
        case KEY_END:           return .end
        case KEY_DOWN:          return .down
        case KEY_PAGEDOWN:      return .pageDown
        case KEY_INSERT:        return .insert
        case KEY_DELETE:        return .delete

        case KEY_LEFTMETA:		return .leftCommand
        case KEY_RIGHTMETA:		return .rightCommand

        default: break
        }

        return .none
    }
}

// https://wayland-book.com/seat/keyboard.html
// https://xkbcommon.org/doc/current/md_doc_2quick-guide.html

struct XKBContext: ~Copyable {
    var xkb_context: OpaquePointer?
    var xkb_keymap: OpaquePointer?
    var xkb_state : OpaquePointer?

    struct Symbol {
        let key: UInt32
        let raw: String
        let name: String
    }

    func symbol(forKey key: UInt32) -> Symbol? {
        guard let xkb_state = xkb_state else {
            fatalError("xkb_state is nil")
        }
        let xkbCode = xkb_keycode_t(key) + 8
        let sym = xkb_state_key_get_one_sym(xkb_state, xkbCode)
        if sym == XKB_KEY_NoSymbol {
            return nil
        }

        var buffer = InlineArray<64, CChar>(repeating: 0)
        var span = buffer.mutableSpan
        let name = span.withUnsafeMutableBufferPointer { ptr in
            if xkb_keysym_get_name(sym, ptr.baseAddress!, ptr.count) > 0 {
                return String(cString: ptr.baseAddress!)
            }
            return ""
        }
        let utf8Name = span.withUnsafeMutableBufferPointer { ptr in
            if xkb_state_key_get_utf8(xkb_state, xkbCode, ptr.baseAddress!, ptr.count) > 0 {
                return String(cString: ptr.baseAddress!)
            }
            return ""
        }
        return Symbol(key: sym, raw: name, name: utf8Name)
    }

    func updateKey(_ key: UInt32, state: UInt32) -> xkb_state_component {
        guard let xkb_state = xkb_state else {
            fatalError("xkb_state is nil")
        }
        let xkbCode = xkb_keycode_t(key) + 8
        let xkbState = state == WL_KEYBOARD_KEY_STATE_PRESSED.rawValue ? XKB_KEY_DOWN : XKB_KEY_UP
        return xkb_state_update_key(xkb_state, xkbCode, xkbState)
    }

    func updateModifiers(depressed: UInt32, latched: UInt32, locked: UInt32, group: UInt32) -> xkb_state_component {
        guard let xkb_state = xkb_state else {
            fatalError("xkb_state is nil")
        }
        return xkb_state_update_mask(xkb_state, depressed, latched, locked, 0, 0, group)
    }

    func shouldRepeats(_ key: UInt32) -> Bool {
        guard let xkb_keymap = xkb_keymap else {
            fatalError("xkb_keymap is nil")
        }
        return xkb_keymap_key_repeats(xkb_keymap, xkb_keycode_t(key) + 8) != 0
    }

    func isModifierActive(_ name: String, type: xkb_state_component = XKB_STATE_MODS_EFFECTIVE) -> Bool {
        guard let xkb_state = xkb_state else {
            fatalError("xkb_state is nil")
        }
        return xkb_state_mod_name_is_active(xkb_state, name, type) != 0
    }

    mutating func updateKeyMap(fromFD fd: Int32, size: Int) {
        let map_shm = mmap(nil, size, PROT_READ, MAP_PRIVATE, fd, 0)
        assert(map_shm != MAP_FAILED)

        let keymap = xkb_keymap_new_from_string(
            self.xkb_context, map_shm,
            XKB_KEYMAP_FORMAT_TEXT_V1,
            XKB_KEYMAP_COMPILE_NO_FLAGS)

        munmap(map_shm, size)
        close(fd)

        if let xkb_keymap = self.xkb_keymap {
            xkb_keymap_unref(xkb_keymap)
            self.xkb_keymap = nil
        }
        if let xkb_state = self.xkb_state {
            xkb_state_unref(xkb_state)
            self.xkb_state = nil
        }
        self.xkb_keymap = keymap
        self.xkb_state = xkb_state_new(keymap)
    }

    init?() {
        guard let xkb_context = xkb_context_new(XKB_CONTEXT_NO_FLAGS) else {
            Log.error("Failed to create xkb_context")
            return nil
        }
        self.xkb_context = xkb_context
        self.xkb_keymap = nil
        self.xkb_state = nil
    }

    deinit {
        if let xkb_state {
            xkb_state_unref(xkb_state)
        }
        if let xkb_keymap {
            xkb_keymap_unref(xkb_keymap)
        }
        if let xkb_context {
            xkb_context_unref(xkb_context)
        }
    }
}

#endif //if ENABLE_WAYLAND
