
extension VirtualKey {

    static func fromWin32VK(_ key: Int) -> VirtualKey {
        switch (key) {
        case 0x03:	return .f15             // VK_F15 (ctrl+break)
        case 0x08:	return .backspace       // VK_BACK
        case 0x09:	return .tab             // VK_TAB
        case 0x0D:	return .return          // VK_RETURN
        // case 0x10:	return .shift           // VK_SHIFT
        // case 0x11:	return .control         // VK_CONTROL
        // case 0x12:	return .option          // VK_MENU
        case 0x13:	return .f15             // VK_PAUSE
        case 0x14:	return .capslock        // VK_CAPITAL, CAPSLOCK
        case 0x1B:	return .escape          // VK_ESCAPE
        case 0x1C:	return .none            // VK_CONVERT
        case 0x1D:	return .none            // VK_NONCONVERT
        case 0x1E:	return .none            // VK_ACCEPT
        case 0x1F:	return .none            // VK_MODECHANGE
        case 0x20:	return .space           // VK_SPACE
        case 0x21:	return .pageUp          // VK_PRIOR
        case 0x22:	return .pageDown        // VK_NEXT
        case 0x23:	return .end             // VK_END
        case 0x24:	return .home            // VK_HOME
        case 0x25:	return .left            // VK_LEFT
        case 0x26:	return .up              // VK_UP
        case 0x27:	return .right           // VK_RIGHT
        case 0x28:	return .down            // VK_DOWN
        case 0x29:	return .none            // VK_SELECT
        case 0x2A:	return .none            // VK_PRINT
        case 0x2B:	return .none            // VK_EXECUTE
        case 0x2C:	return .f13             // VK_SNAPSHOT, PRINT SCREEN KEY
        case 0x2D:	return .insert          // VK_INSERT
        case 0x2E:	return .delete          // VK_DELETE
        case 0x2F:	return .none            // VK_HELP
        case 0x30:	return .num0            // 0
        case 0x31:	return .num1            // 1
        case 0x32:	return .num2            // 2
        case 0x33:	return .num3            // 3
        case 0x34:	return .num4            // 4
        case 0x35:	return .num5            // 5
        case 0x36:	return .num6            // 6
        case 0x37:	return .num7            // 7
        case 0x38:	return .num8            // 8
        case 0x39:	return .num9            // 9

        case 0x41:	return .a               // A
        case 0x42:	return .b               // B
        case 0x43:	return .c               // C
        case 0x44:	return .d               // D
        case 0x45:	return .e               // E
        case 0x46:	return .f               // F
        case 0x47:	return .g               // G
        case 0x48:	return .h               // H
        case 0x49:	return .i               // I
        case 0x4A:	return .j               // J
        case 0x4B:	return .k               // K
        case 0x4C:	return .l               // L
        case 0x4D:	return .m               // M
        case 0x4E:	return .n               // N
        case 0x4F:	return .o               // O
        case 0x50:	return .p               // P
        case 0x51:	return .q               // Q
        case 0x52:	return .r               // R
        case 0x53:	return .s               // S
        case 0x54:	return .t               // T
        case 0x55:	return .u               // U
        case 0x56:	return .v               // V
        case 0x57:	return .w               // W
        case 0x58:	return .x               // X
        case 0x59:	return .y               // Y
        case 0x5A:	return .z               // Z
        case 0x5B:	return .leftCommand     // VK_LWIN
        case 0x5C:	return .rightCommand    // VK_RWIN
        case 0x5D:	return .none            // VK_APPS
        case 0x5F:	return .none            // VK_SLEEP
        case 0x60:	return .pad0            // VK_NUMPAD0
        case 0x61:	return .pad1            // VK_NUMPAD1
        case 0x62:	return .pad2            // VK_NUMPAD2
        case 0x63:	return .pad3            // VK_NUMPAD3
        case 0x64:	return .pad4            // VK_NUMPAD4
        case 0x65:	return .pad5            // VK_NUMPAD5
        case 0x66:	return .pad6            // VK_NUMPAD6
        case 0x67:	return .pad7            // VK_NUMPAD7
        case 0x68:	return .pad8            // VK_NUMPAD8
        case 0x69:	return .pad9            // VK_NUMPAD9
        case 0x6A:	return .padAsterisk	    // VK_MULTIPLY
        case 0x6B:	return .padPlus         // VK_ADD
        case 0x6C:	return .none            // VK_SEPARATOR
        case 0x6D:	return .padMinus        // VK_SUBTRACT
        case 0x6E:	return .padPeriod       // VK_DECIMAL
        case 0x6F:	return .padSlash        // VK_DIVIDE
        case 0x70:	return .f1              // VK_F1
        case 0x71:	return .f2              // VK_F2
        case 0x72:	return .f3              // VK_F3
        case 0x73:	return .f4              // VK_F4
        case 0x74:	return .f5              // VK_F5
        case 0x75:	return .f6              // VK_F6
        case 0x76:	return .f7              // VK_F7
        case 0x77:	return .f8              // VK_F8
        case 0x78:	return .f9              // VK_F9
        case 0x79:	return .f10             // VK_F10
        case 0x7A:	return .f11             // VK_F11
        case 0x7B:	return .f12             // VK_F12
        case 0x7C:	return .f13             // VK_F13
        case 0x7D:	return .f14             // VK_F14
        case 0x7E:	return .f15             // VK_F15
        case 0x7F:	return .f16             // VK_F16
        case 0x80:	return .f17             // VK_F17
        case 0x81:	return .f18             // VK_F18
        case 0x82:	return .f19             // VK_F19
        case 0x83:	return .f20             // VK_F20
        case 0x84:	return .none            // VK_F21
        case 0x85:	return .none            // VK_F22
        case 0x86:	return .none            // VK_F23
        case 0x87:	return .none            // VK_F24

        case 0x90:	return .numlock         // VK_NUMLOCK
        case 0x91:	return .f14             // VK_SCROLL, SCROLL LOCK

        case 0xA0:	return .leftShift       // VK_LSHIFT
        case 0xA1:	return .rightShift      // VK_RSHIFT
        case 0xA2:	return .leftControl     // VK_LCONTROL
        case 0xA3:	return .rightControl    // VK_RCONTROL
        case 0xA4:	return .leftOption      // VK_LMENU
        case 0xA5:	return .rightOption     // VK_RMENU

        case 0xBA:	return .semicolon       // VK_OEM_1, 
        case 0xBB:	return .equal           // VK_OEM_PLUS, =
        case 0xBC:	return .comma           // VK_OEM_COMMA, .
        case 0xBD:	return .hyphen          // VK_OEM_MINUS, -
        case 0xBE:	return .period          // VK_OEM_PERIOD
        case 0xBF:	return .slash           // VK_OEM_2, /?
        case 0xC0:	return .accentTilde     // VK_OEM_3, `~

        case 0xDB:	return .openBracket     // VK_OEM_4, [
        case 0xDC:	return .backslash       // VK_OEM_5, backslash
        case 0xDD:	return .closeBracket    // VK_OEM_6, ]
        case 0xDE:	return .quote           // VK_OEM_7, '
        case 0xDF:	return .none            // VK_OEM_8

        case 0xE2:	return .backslash       // VK_OEM_102, backslash for 102-keyboard

        case 0xE5:	return .none            // VK_PROCESSKEY, IME-key

        default:
            break
        }
        return .none
    }
}
