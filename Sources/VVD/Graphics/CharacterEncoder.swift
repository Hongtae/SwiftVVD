//
//  File: CharacterEncoder.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

internal import HarfBuzz
private import ICUTextAnalysis

/// Classifies ignorable characters before font substitution. A mapped mark can
/// retain a visible glyph, while ordinary format controls remain transparent.
enum CharacterEncoder {
    static func encodings(_ scalars: [UInt32], run: ScriptRun,
                          font: OpaquePointer, isLastResort: Bool) -> [HBGlyphEncoding]? {
        guard run.script == 8 || run.script == 14 || run.script == 25 else { return nil }
        let range = run.range
        guard scalars[range].contains(where: {
            ICUTextHasBinaryProperty(Int32($0), 5) != 0
        }) else { return nil }
        var result = [HBGlyphEncoding](repeating: HB_GLYPH_ENCODING_DEFAULT,
                                      count: scalars.count)
        for index in range {
            let scalar = scalars[index]
            guard ICUTextHasBinaryProperty(Int32(scalar), 5) != 0 else { continue }
            let category = ICUTextGetIntProperty(Int32(scalar), 0x1005)
            // Other categories and script shapers retain their encoding policy.
            guard category == 6 || category == 16 else { return nil }
            var glyph: UInt32 = 0
            let mapped = hb_font_get_nominal_glyph(font, scalar, &glyph) != 0 && glyph != 0
            let visible = isVisibleFormatter(scalar)
            // These inputs require font selection or a contextual presentation
            // decision before a concrete font can supply the encoding policy.
            guard mapped || isLastResort || (!visible && scalar != 0xfe0f) else { return nil }
            let ignored = !visible && (category == 16 || !mapped || isLastResort)
            result[index] = ignored ? HB_GLYPH_ENCODING_INVISIBLE : HB_GLYPH_ENCODING_VISIBLE
        }
        return result
    }

    private static func isVisibleFormatter(_ scalar: UInt32) -> Bool {
        (0x180b...0x180f).contains(scalar) || (0x200c...0x200d).contains(scalar) ||
        (0x13430..<0x13440).contains(scalar) || (0xe0030..<0xe003a).contains(scalar) ||
        (0xe0061..<0xe007b).contains(scalar) || scalar == 0xe007f ||
        ICUTextHasBinaryProperty(Int32(scalar), 63) != 0
    }
}
