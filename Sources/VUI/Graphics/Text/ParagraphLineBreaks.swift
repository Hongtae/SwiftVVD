//
//  File: ParagraphLineBreaks.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

/// Adapts source scalar ranges to the text backend's UTF-16 boundary cursor.
final class ParagraphLineBreaks {
    private let text: String
    private let offsets: [Int]
    private var iterator: LineBreakIterator?
    private var language: String?
    private var keepsHangulWords = false

    init(_ scalars: [UnicodeScalar]) {
        text = String(String.UnicodeScalarView(scalars))
        var offsets = [0]
        for scalar in scalars {
            offsets.append(offsets.last! + (scalar.value > 0xffff ? 2 : 1))
        }
        self.offsets = offsets
    }

    func boundary(before index: Int, inclusive: Bool, language: String,
                  keepsHangulWords: Bool) -> Int? {
        precondition(offsets.indices.contains(index))
        if iterator == nil || self.language != language || self.keepsHangulWords != keepsHangulWords {
            iterator = LineBreakIterator(text, locale: language, keepsHangulWords: keepsHangulWords)
            self.language = language
            self.keepsHangulWords = keepsHangulWords
        }
        if inclusive, index == offsets.count - 1 { return index }
        let offset = offsets[inclusive ? index + 1 : index]
        guard let boundary = iterator!.preceding(offset) else { return nil }
        var lower = 0
        var upper = offsets.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if offsets[middle] < boundary { lower = middle + 1 } else { upper = middle }
        }
        precondition(lower < offsets.count && offsets[lower] == boundary,
                     "Line boundary splits a Unicode scalar")
        return lower
    }
}
