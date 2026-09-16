//
//  File: TextAttachment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol TextAttachment {
    var ascent: CGFloat { get }
    var descent: CGFloat { get }
    var length: CGFloat { get }
    var customAttributes: _TextAttributeValues { get }
    func draw(with bounds: Text.Layout.TypographicBounds, in context: inout GraphicsContext)
}

class AnyCustomTextAttachment: Equatable {
    var ascent: CGFloat { fatalError("abstract AnyCustomTextAttachment") }
    var descent: CGFloat { fatalError("abstract AnyCustomTextAttachment") }
    var length: CGFloat { fatalError("abstract AnyCustomTextAttachment") }
    var customAttributes: _TextAttributeValues { fatalError("abstract AnyCustomTextAttachment") }

    func draw(with bounds: Text.Layout.TypographicBounds, in context: inout GraphicsContext) {
        fatalError("abstract AnyCustomTextAttachment")
    }

    func nsAttributedString(with attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        var attributes = attributes
        attributes[.customTextAttachment] = self
        return NSAttributedString(string: "\u{fffc}", attributes: attributes)
    }

    static func == (lhs: AnyCustomTextAttachment, rhs: AnyCustomTextAttachment) -> Bool { lhs === rhs }
}

final class ConcreteCustomTextAttachment<Attachment: TextAttachment>: AnyCustomTextAttachment {
    let attachment: Attachment

    init(_ attachment: Attachment) { self.attachment = attachment }

    override var ascent: CGFloat { attachment.ascent }
    override var descent: CGFloat { attachment.descent }
    override var length: CGFloat { attachment.length }
    override var customAttributes: _TextAttributeValues { attachment.customAttributes }

    override func draw(with bounds: Text.Layout.TypographicBounds, in context: inout GraphicsContext) {
        attachment.draw(with: bounds, in: &context)
    }
}

struct LineAttachment: TextAttachment {
    var line: Text.Layout.Line
    var bounds: Text.Layout.TypographicBounds

    var ascent: CGFloat { bounds.ascent }
    var descent: CGFloat { bounds.descent }
    var length: CGFloat { bounds.width }
    var customAttributes: _TextAttributeValues {
        var attributes = _TextAttributeValues()
        for run in line { attributes.merge(run.customAttributes) }
        return attributes
    }

    func draw(with bounds: Text.Layout.TypographicBounds, in context: inout GraphicsContext) {
        var line = line
        line.origin = bounds.origin
        context.draw(line)
    }
}

extension NSAttributedString.Key {
    static let customTextAttachment = Self("VUI.CustomAttachment")
}
