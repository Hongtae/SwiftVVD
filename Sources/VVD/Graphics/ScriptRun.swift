//
//  File: ScriptRun.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private import ICUTextAnalysis

/// A script interval within one font and directional shaping input.
struct ScriptRun {
    let range: Range<Int>
    let script: Int32

    var iso15924Tag: UInt32 {
        // The combined kana and music classes use the corresponding layout tags.
        if script == 54 { return 0x4b61_6e61 } // Kana
        if script == 214 { return 0x4279_7a6d } // Byzm
        if script == 215 { return 0x4d75_7363 } // Musc
        guard let name = ICUTextGetScriptName(script) else {
            preconditionFailure("Unknown text shaping script")
        }
        return String(cString: name).utf8.reduce(UInt32.zero) { ($0 << 8) | UInt32($1) }
    }

    static func ranges(in scalars: [UInt32]) -> [Self] {
        guard !scalars.isEmpty else { return [] }
        let scripts = scalars.map(scriptCode)
        var result: [Self] = []
        var start = 0
        var current: Int32 = -1
        for index in scalars.indices {
            var script = scripts[index]
            if script == 0, isRightAssociative(scalars[index]) {
                // Opening punctuation and prefix operators follow the next
                // concrete script, including intervening neutral characters.
                if let next = scripts[(index + 1)...].first(where: { $0 > 0 }) {
                    script = next
                }
            }
            guard script > 0, script != current else { continue }
            if current > 0, continues(current, with: scalars[index]) { continue }
            if current >= 0 {
                result.append(Self(range: start..<index, script: current))
                start = index
            }
            current = script
        }
        result.append(Self(range: start..<scalars.count, script: current >= 0 ? current : 25))
        return result
    }

    private static func scriptCode(_ scalar: UInt32) -> Int32 {
        let script = ICUTextGetScript(Int32(scalar))
        precondition(script >= 0, "Cannot classify the text shaping script")
        switch script {
        case 0, 1:
            if (0x1d000..<0x1d100).contains(scalar) { return 214 }
            if (0x1d100..<0x1d200).contains(scalar) { return 215 }
            return 0
        case 20, 22: return 54
        case 102, 103: return 0
        default: return script
        }
    }

    private static func isRightAssociative(_ scalar: UInt32) -> Bool {
        if scalar == 0x1cf5 || scalar == 0x1cf6 || scalar == 0x25cc { return true }
        let scalar = Int32(scalar)
        return ICUTextGetIntProperty(scalar, 0x1015) == 1 || // Opening paired bracket
            ICUTextHasBinaryProperty(scalar, 72) != 0 || // Unary ideographic operator
            ICUTextHasBinaryProperty(scalar, 18) != 0 || // Binary ideographic operator
            ICUTextHasBinaryProperty(scalar, 19) != 0    // Ternary ideographic operator
    }

    private static func continues(_ script: Int32, with scalar: UInt32) -> Bool {
        let scalar = Int32(scalar)
        if ICUTextHasScript(scalar, script) != 0 { return true }
        return isSimpleMarkScript(script) && ICUTextIsNonspacingMark(scalar) != 0 &&
            isSimpleMarkScript(ICUTextGetScript(scalar))
    }

    private static func isSimpleMarkScript(_ script: Int32) -> Bool {
        switch script {
        case 3, 6, 8, 12, 14, 19, 25, 29, 32: return true
        default: return false
        }
    }
}
