//
//  File: AppKitVirtualKey.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

#if ENABLE_APPKIT
public extension VirtualKey {
    static func from(code: UInt16) -> VirtualKey {
        switch (code)
        {
        case 0x00:  return .a               // a
        case 0x01:  return .s               // s
        case 0x02:  return .d               // d
        case 0x03:  return .f               // f
        case 0x04:  return .h               // h
        case 0x05:  return .g               // g
        case 0x06:  return .z               // z
        case 0x07:  return .x               // x
        case 0x08:  return .c               // c
        case 0x09:  return .v               // v
        case 0x0a:  return .none
        case 0x0b:  return .b               // b
        case 0x0c:  return .q               // q
        case 0x0d:  return .w               // w
        case 0x0e:  return .e               // e
        case 0x0f:  return .r               // r
        case 0x10:  return .y               // y
        case 0x11:  return .t               // t
        case 0x12:  return .num1            // 1
        case 0x13:  return .num2            // 2
        case 0x14:  return .num3            // 3
        case 0x15:  return .num4            // 4
        case 0x16:  return .num6            // 6
        case 0x17:  return .num5            // 5
        case 0x18:  return .equal           // =
        case 0x19:  return .num9            // 9
        case 0x1a:  return .num7            // 7
        case 0x1b:  return .hyphen          // -
        case 0x1c:  return .num8            // 8
        case 0x1d:  return .num0            // 0
        case 0x1e:  return .closeBracket    // ]
        case 0x1f:  return .o               // o
        case 0x20:  return .u               // u
        case 0x21:  return .openBracket     // [
        case 0x22:  return .i               // i
        case 0x23:  return .p               // p
        case 0x24:  return .return          // return
        case 0x25:  return .l               // l
        case 0x26:  return .j               // j
        case 0x27:  return .quote           // '
        case 0x28:  return .k               // k
        case 0x29:  return .semicolon       //
        case 0x2a:  return .backslash       // backslash
        case 0x2b:  return .comma           // ,
        case 0x2c:  return .slash           // /
        case 0x2d:  return .n               // n
        case 0x2e:  return .m               // m
        case 0x2f:  return .period          // .
        case 0x30:  return .tab             // tab
        case 0x31:  return .space           // space
        case 0x32:  return .accentTilde     // ` (~)
        case 0x33:  return .backspace       // delete (backspace)
        case 0x34:  return .none            //
        case 0x35:  return .escape          // esc
        case 0x36:  return .none
        case 0x37:  return .none

        case 0x38:  return .leftShift       // l-shift
        case 0x39:  return .none
        case 0x3a:  return .leftOption      // l-alt
        case 0x3b:  return .leftControl     // l_ctrl
        case 0x3c:  return .rightShift      // r-shift
        case 0x3d:  return .rightOption     // r-alt
        case 0x3e:  return .rightControl    // r-ctrl

        case 0x3f:  return .none
        case 0x40:  return .f17             // f17
        case 0x41:  return .padPeriod       // . (keypad)
        case 0x42:  return .none
        case 0x43:  return .padAsterisk     // * (keypad)
        case 0x44:  return .none
        case 0x45:  return .padPlus         // + (keypad)
        case 0x46:  return .none
        case 0x47:  return .numlock         // clear (keypad)
        case 0x48:  return .none
        case 0x49:  return .none
        case 0x4a:  return .none
        case 0x4b:  return .padSlash        // / (keypad)
        case 0x4c:  return .enter           // enter (keypad)
        case 0x4d:  return .none
        case 0x4e:  return .padMinus        // - (keypad)
        case 0x4f:  return .f18             // f18
        case 0x50:  return .f19             // f19
        case 0x51:  return .padEqual        // = (keypad)
        case 0x52:  return .pad0            // 0 (keypad)
        case 0x53:  return .pad1            // 1 (keypad)
        case 0x54:  return .pad2            // 2 (keypad)
        case 0x55:  return .pad3            // 3 (keypad)
        case 0x56:  return .pad4            // 4 (keypad)
        case 0x57:  return .pad5            // 5 (keypad)
        case 0x58:  return .pad6            // 6 (keypad)
        case 0x59:  return .pad7            // 7 (keypad)
        case 0x5a:  return .none
        case 0x5b:  return .pad8            // 8 (keypad)
        case 0x5c:  return .pad9            // 9 (keypad)
        case 0x5d:  return .none
        case 0x5e:  return .none
        case 0x5f:  return .none
        case 0x60:  return .f5              // f5
        case 0x61:  return .f6              // f6
        case 0x62:  return .f7              // f7
        case 0x63:  return .f3              // f3
        case 0x64:  return .f8              // f8
        case 0x65:  return .none
        case 0x66:  return .none
        case 0x67:  return .none
        case 0x68:  return .none
        case 0x69:  return .f13             // f13
        case 0x6a:  return .f16             // f16
        case 0x6b:  return .f14             // f14
        case 0x6c:  return .none
        case 0x6d:  return .none
        case 0x6e:  return .none
        case 0x6f:  return .none
        case 0x70:  return .none
        case 0x71:  return .f15             // f15
        case 0x72:  return .none
        case 0x73:  return .home            // home
        case 0x74:  return .pageUp          // page up
        case 0x75:  return .delete          // delete (below insert key)
        case 0x76:  return .f4              // f4
        case 0x77:  return .end             // end
        case 0x78:  return .f2              // f2
        case 0x79:  return .pageDown        // page down
        case 0x7a:  return .f1              // f1
        case 0x7b:  return .left            // left
        case 0x7c:  return .right           // right
        case 0x7d:  return .down            // down
        case 0x7e:  return .up              // up
        case 0x7f:  return .none
        default:    return .none
        }
    }
}
#endif //if ENABLE_APPKIT
