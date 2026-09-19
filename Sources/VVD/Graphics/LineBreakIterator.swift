//
//  File: LineBreakIterator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

private import ICUTextAnalysis

/// A mutable line-boundary cursor over an immutable UTF-16 buffer.
/// Keep each instance on the thread that owns its text layout operation.
public final class LineBreakIterator {
    private let text: UnsafeMutablePointer<UInt16>
    private let iterator: UnsafeMutableRawPointer
    private let keepsHangulWords: Bool
    public let count: Int

    public init(_ string: String, locale: String, keepsHangulWords: Bool) {
        let count = string.utf16.count
        precondition(count < Int32.max, "Text exceeds the line iterator index range")
        let text = UnsafeMutablePointer<UInt16>.allocate(capacity: max(count, 1))
        text.initialize(from: Array(string.utf16), count: count)
        self.count = count
        self.text = text
        self.keepsHangulWords = keepsHangulWords
        var error: Int32 = 0
        let opened = locale.withCString {
            ICUTextLineBreakOpen(text, Int32(count), $0, &error)
        }
        guard error <= 0, let opened else {
            fatalError("Cannot initialize the line boundary service (\(error))")
        }
        iterator = opened
    }

    deinit {
        ICUTextLineBreakClose(iterator)
        text.deinitialize(count: count)
        text.deallocate()
    }

    /// Returns the closest boundary strictly before the supplied UTF-16 offset.
    public func preceding(_ index: Int) -> Int? {
        precondition((0...count).contains(index))
        var boundary = ICUTextLineBreakPreceding(iterator, Int32(index))
        while boundary > 0 && joinsHangul(at: Int(boundary)) {
            boundary = ICUTextLineBreakPreceding(iterator, boundary)
        }
        return boundary >= 0 ? Int(boundary) : nil
    }

    private func joinsHangul(at index: Int) -> Bool {
        guard keepsHangulWords, index > 0, index < count else { return false }
        // Hangul script characters are in the BMP. A surrogate code unit cannot
        // join a Hangul pair, so it needs no scalar reconstruction here.
        return ICUTextIsHangul(Int32(text[index - 1])) != 0 &&
            ICUTextIsHangul(Int32(text[index])) != 0
    }
}
