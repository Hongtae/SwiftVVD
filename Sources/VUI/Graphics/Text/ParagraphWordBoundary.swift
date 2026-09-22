//
//  File: ParagraphWordBoundary.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Word-boundary queries for the paragraph glyph backend.
enum ParagraphWordBoundary {
    private static let expression = try! NSRegularExpression(
        pattern: #"\b"#, options: [.useUnicodeWordBoundaries])

    /// The first word may have trailing punctuation, separators or attachments.
    static func isSingleWord(_ text: String) -> Bool {
        let length = text.utf16.count
        let string = text as NSString
        let range = NSRange(location: 0, length: length)
        // Anchored UTF-16 admission is distinct from scalar membership.
        guard string.rangeOfCharacter(from: .alphanumerics,
            options: .anchored, range: range).length != 0 else { return false }
        // Match the supplied remainder independently; dictionary boundaries
        // can differ from those in the complete paragraph.
        let boundaries = expression.matches(in: text, range: range)
        let end = boundaries.first { $0.range.location > 0 }!.range.location
        return string.rangeOfCharacter(from: .alphanumerics,
            range: NSRange(location: end, length: length - end)).location == NSNotFound
    }
}
