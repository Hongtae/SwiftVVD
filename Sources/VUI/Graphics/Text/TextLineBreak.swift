//
//  File: TextLineBreak.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Distinguishes paragraph boundaries from forced breaks within a paragraph.
enum TextLineBreak {
    case paragraph
    case line

    init?(_ scalar: UnicodeScalar) {
        switch scalar.value {
        case 0x0a, 0x0d, 0x2029: self = .paragraph
        case 0x0c, 0x85, 0x2028: self = .line
        default: return nil
        }
    }

    /// A one-unit final paragraph has no attributes for its extra fragment.
    static func requiresDefaultFont(in string: String) -> Bool {
        var paragraphLength = 0
        var terminatedLength = 0
        var previous: UnicodeScalar?
        for scalar in string.unicodeScalars {
            if previous?.value == 0x0d, scalar.value == 0x0a {
                terminatedLength += 1
            } else {
                paragraphLength += scalar.value > 0xffff ? 2 : 1
                if Self(scalar) == .paragraph {
                    terminatedLength = paragraphLength
                    paragraphLength = 0
                }
            }
            previous = scalar
        }
        guard let previous else { return true }
        guard let lastBreak = Self(previous) else { return false }
        return (lastBreak == .paragraph ? terminatedLength : paragraphLength) == 1
    }
}
