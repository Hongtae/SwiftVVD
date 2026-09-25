//
//  File: TextSelectionCopy.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

private struct TextSelectionCopyDocument {
    private struct FontStyle: Hashable {
        var name: String
        var pointSize: CGFloat
        var isBold: Bool
        var isItalic: Bool
    }

    private struct RTFColor: Hashable {
        var red: Int
        var green: Int
        var blue: Int
        var expandedRed: Int
        var expandedGreen: Int
        var expandedBlue: Int
        var alpha: Int

        init(_ color: Color, environment: EnvironmentValues) {
            let resolved = color.resolve(in: environment)

            func byte(_ value: Float) -> Int {
                guard value.isFinite else { return 0 }
                return Int((Double(value).clamped(to: 0...1) * 255).rounded())
            }

            func component(_ value: Float) -> Int {
                guard value.isFinite else { return 0 }
                return Int((Double(value).clamped(to: 0...1) * 100_000).rounded())
            }

            red = byte(resolved.red)
            green = byte(resolved.green)
            blue = byte(resolved.blue)
            expandedRed = component(resolved.red)
            expandedGreen = component(resolved.green)
            expandedBlue = component(resolved.blue)
            alpha = component(resolved.opacity)
        }
    }

    private struct Run {
        var text: String
        var font: FontStyle
        var foregroundColor: RTFColor
        var underlinePattern: Int?

        init(
            text: String,
            faces: [any Typeface],
            attributes: _ResolvedTextRunAttributes,
            environment: EnvironmentValues
        ) {
            let face = faces.first
            let backed = face as? any VVDFontBackedTypeface
            let resource = attributes.fontResource
            let traits = resource?.realizedTraits
            let fontName = face?.selectedFont?.descriptor.postScriptName
                ?? backed?.font.postScriptName
                ?? backed?.font.familyName
                ?? "sans-serif"
            let rawPointSize = resource?.pointSize
                ?? backed?.font.pointSize
                ?? 12
            let pointSize = rawPointSize.isFinite && rawPointSize > 0
                ? rawPointSize
                : 12
            let faceTraits = backed?.font.faceTraits
            let weightClass = faceTraits?.sfntStyle.weightClass

            self.text = text
            self.font = FontStyle(
                name: fontName,
                pointSize: pointSize,
                isBold: traits.map { $0.symbolic & 2 != 0 }
                    ?? weightClass.map { $0 >= 700 }
                    ?? false,
                isItalic: traits.map { $0.symbolic & 1 != 0 }
                    ?? faceTraits?.isItalic
                    ?? false
            )
            self.foregroundColor = RTFColor(
                attributes.foregroundColor ?? .primary,
                environment: environment
            )
            self.underlinePattern = attributes.underlineStyle?.pattern.rawValue
        }
    }

    private var runs: [Run]

    var string: String {
        runs.map(\.text).joined()
    }

    init?(
        layoutManager: ResolvedStyledText.TextLayoutManager,
        selection: Range<Int>,
        selectedText: String,
        environment: EnvironmentValues
    ) {
        guard !selection.isEmpty,
              let source = layoutManager.resolvedText else {
            return nil
        }

        var result: [Run] = []
        var sourceOffset = 0
        for sourceRun in source.runs {
            let value: (
                text: String,
                faces: [any Typeface],
                attributes: _ResolvedTextRunAttributes
            )
            switch sourceRun {
            case let .text(faces, text):
                value = (text, faces, _ResolvedTextRunAttributes())
            case let .attributedText(faces, text, _):
                value = (text, faces, _ResolvedTextRunAttributes())
            case let .styledText(faces, text, _, attributes):
                value = (text, faces, attributes)
            case let .attachment(faces, _):
                value = ("\u{fffc}", faces, _ResolvedTextRunAttributes())
            case let .attributedAttachment(faces, _, _):
                value = ("\u{fffc}", faces, _ResolvedTextRunAttributes())
            case let .styledAttachment(faces, _, _, attributes):
                value = ("\u{fffc}", faces, attributes)
            }

            let length = value.text.utf16.count
            let runRange = sourceOffset..<(sourceOffset + length)
            sourceOffset += length
            let lower = max(selection.lowerBound, runRange.lowerBound)
            let upper = min(selection.upperBound, runRange.upperBound)
            guard lower < upper else { continue }

            let localRange = NSRange(
                location: lower - runRange.lowerBound,
                length: upper - lower
            )
            let text = (value.text as NSString).substring(with: localRange)
            result.append(Run(
                text: text,
                faces: value.faces,
                attributes: value.attributes,
                environment: environment
            ))
        }

        guard !result.isEmpty,
              result.map(\.text).joined() == selectedText else {
            return nil
        }
        runs = result
    }

    var rtfData: Data {
        var fonts: [FontStyle] = []
        var fontIndices: [FontStyle: Int] = [:]
        var colors: [RTFColor] = []
        var colorIndices: [RTFColor: Int] = [:]

        for run in runs {
            if fontIndices[run.font] == nil {
                fontIndices[run.font] = fonts.count
                fonts.append(run.font)
            }
            if colorIndices[run.foregroundColor] == nil {
                colorIndices[run.foregroundColor] = colors.count + 1
                colors.append(run.foregroundColor)
            }
        }

        var rtf = "{\\rtf1\\ansi\\ansicpg1252\\deff0\\uc0\n"
        rtf += "{\\fonttbl"
        for (index, font) in fonts.enumerated() {
            rtf += "{\\f\(index)\\fnil\\fcharset0 "
            rtf += Self.escapedFontName(font.name)
            rtf += ";}"
        }
        rtf += "}\n"

        rtf += "{\\colortbl;"
        for color in colors {
            rtf += "\\red\(color.red)\\green\(color.green)"
            rtf += "\\blue\(color.blue);"
        }
        rtf += "}\n"

        rtf += "{\\*\\expandedcolortbl;"
        for color in colors {
            rtf += "\\cssrgb\\c\(color.expandedRed)"
            rtf += "\\c\(color.expandedGreen)"
            rtf += "\\c\(color.expandedBlue)"
            if color.alpha < 100_000 {
                rtf += "\\c\(color.alpha)"
            }
            rtf += ";"
        }
        rtf += "}\n"

        for run in runs {
            let fontIndex = fontIndices[run.font] ?? 0
            let colorIndex = colorIndices[run.foregroundColor] ?? 1
            let halfPoints = max(Int((run.font.pointSize * 2).rounded()), 1)
            rtf += "{\\f\(fontIndex)\\fs\(halfPoints)"
            if run.font.isBold { rtf += "\\b" }
            if run.font.isItalic { rtf += "\\i" }
            rtf += "\\cf\(colorIndex)"
            if let pattern = run.underlinePattern {
                rtf += Self.underlineControl(pattern)
                rtf += "\\ulc\(colorIndex)"
            }
            rtf += " "
            rtf += Self.escapedText(run.text)
            rtf += "}"
        }
        rtf += "}"
        return Data(rtf.utf8)
    }

    private static func underlineControl(_ pattern: Int) -> String {
        switch pattern {
        case Text.LineStyle.Pattern.dot.rawValue:
            "\\uld"
        case Text.LineStyle.Pattern.dash.rawValue:
            "\\uldash"
        case Text.LineStyle.Pattern.dashDot.rawValue:
            "\\uldashd"
        case Text.LineStyle.Pattern.dashDotDot.rawValue:
            "\\uldashdd"
        default:
            "\\ul"
        }
    }

    private static func escapedFontName(_ value: String) -> String {
        escapedText(value.replacingOccurrences(of: ";", with: ""))
    }

    private static func escapedText(_ value: String) -> String {
        var result = ""
        for codeUnit in value.utf16 {
            switch codeUnit {
            case 0x09:
                result += "\\tab "
            case 0x0a:
                result += "\\line "
            case 0x0d:
                continue
            case 0x20...0x7e:
                let scalar = UnicodeScalar(codeUnit)!
                if scalar == "\\" || scalar == "{" || scalar == "}" {
                    result.append("\\")
                }
                result.unicodeScalars.append(scalar)
            default:
                result += "\\u\(Int(Int16(bitPattern: codeUnit))) "
            }
        }
        return result
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension TextSelection.Configuration {
    var copyRepresentations: [String: Data]? {
        guard let selectedText,
              let selection = textSelections.first,
              let layoutManager,
              let document = TextSelectionCopyDocument(
                layoutManager: layoutManager,
                selection: selection,
                selectedText: selectedText,
                environment: copyEnvironment
              ) else {
            return nil
        }

        var utf16 = Data([0xff, 0xfe])
        for codeUnit in selectedText.utf16 {
            utf16.append(UInt8(truncatingIfNeeded: codeUnit))
            utf16.append(UInt8(truncatingIfNeeded: codeUnit >> 8))
        }
        return [
            ClipboardContentType.rtf: document.rtfData,
            ClipboardContentType.utf16ExternalPlainText: utf16,
            ClipboardContentType.utf8PlainText: Data(selectedText.utf8),
        ]
    }
}
