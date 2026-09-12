//
//  File: FontOutsets.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

/// Active metric-face inputs, independent of requested descriptor traits and glyph artwork.
struct FontOutsetAttributes: Sendable {
    var weight: CGFloat?
    var isItalic: Bool
    var familyClass: UInt8
    var pointSize: CGFloat

    init(face: TypefaceFaceTraits, scale: CGFloat) {
        let weightClass = face.variationCoordinates[0x7767_6874]
            ?? face.sfntStyle.weightClass.map(CGFloat.init)
        weight = weightClass.map(FontWeightScale.logicalWeight(forClass:))
        isItalic = face.sfntStyle.macStyle.map { $0 & 2 != 0 } ?? face.isItalic
        familyClass = UInt8(truncatingIfNeeded: (face.sfntStyle.familyClass ?? 0) >> 8)
        pointSize = face.pixelSize * scale
    }

    var needsOutsets: Bool {
        isItalic || (weight.map { $0 > CGFloat(Float(0.56)) } ?? false)
            || familyClass == 9 || familyClass == 10
    }
}

/// Immutable framework reference data, loaded from a generated resource rather than app settings.
final class FontOutsetData: Sendable, Decodable {
    struct Row: Sendable, Decodable {
        /// Physical left, top, right and bottom edges in em units.
        let normal: [Double]
        let extended: [Double]
    }

    private enum CodingKeys: CodingKey { case version, scalarRanges, referenceWeights, scriptGroups, referenceRows }
    /// Inclusive Unicode scalar ranges that select expanded metrics for the complete text.
    let scalarRanges: [ClosedRange<UInt32>]
    /// Logical weight boundaries used to select a reference row without interpolation.
    let referenceWeights: [Double]
    /// Likely-script groups used by the ordered preferred-language selection.
    let scriptGroups: [String: Int]
    /// Weight-indexed margins; these rows do not describe individual font files or glyph bounds.
    let referenceRows: [Row]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        let ranges = try container.decode([[UInt32]].self, forKey: .scalarRanges)
        referenceWeights = try container.decode([Double].self, forKey: .referenceWeights)
        scriptGroups = try container.decode([String: Int].self, forKey: .scriptGroups)
        let values = try container.decode([Row].self, forKey: .referenceRows)
        func invalid() -> DecodingError {
            .dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid font outset data."))
        }
        guard version == 1,
              ranges.allSatisfy({ $0.count == 2 && $0[0] <= $0[1] && $0[1] <= 0x10ffff &&
                  ($0[1] < 0xd800 || $0[0] > 0xdfff) }),
              !referenceWeights.isEmpty, referenceWeights.allSatisfy(\.isFinite),
              referenceWeights.count == values.count,
              zip(referenceWeights, referenceWeights.dropFirst()).allSatisfy({ $0 < $1 }),
              values.allSatisfy({ $0.normal.count == 4 && $0.extended.count == 4 &&
                  ($0.normal + $0.extended).allSatisfy { $0.isFinite && $0 >= 0 } }),
              scriptGroups.values.allSatisfy({ (0...4).contains($0) }) else { throw invalid() }
        scalarRanges = ranges.map { $0[0]...$0[1] }
        guard zip(scalarRanges, scalarRanges.dropFirst()).allSatisfy({ $0.upperBound < $1.lowerBound }) else { throw invalid() }
        referenceRows = values
    }

    func contains(_ scalar: Unicode.Scalar) -> Bool {
        var lower = 0
        var upper = scalarRanges.count
        while lower < upper {
            let middle = (lower + upper) / 2
            let range = scalarRanges[middle]
            if scalar.value < range.lowerBound { upper = middle }
            else if scalar.value > range.upperBound { lower = middle + 1 }
            else { return true }
        }
        return false
    }

    func preferredGroup(for languages: [String]) -> Int {
        var result = 0
        var seenArabic = false
        for identifier in languages {
            // Resolve likely subtags before reading the language and script.
            let language = Locale.Language(identifier: Locale.Language(identifier: identifier).maximalIdentifier)
            let code = language.languageCode?.identifier
            let group = code == "vi" || code == "lut" ? 2 : scriptGroups[language.script?.identifier ?? ""] ?? 0
            seenArabic = seenArabic || code == "ar"
            if group > result && !(code == "ur" && seenArabic) { result = group }
        }
        return result
    }

    func referenceIndex(for weight: CGFloat) -> Int? {
        guard weight.isFinite else { return nil }
        let weight = Double(weight)
        if weight < referenceWeights[0] { return 0 }
        if weight >= referenceWeights.last! { return referenceWeights.count - 1 }
        for index in 0..<(referenceWeights.count - 1) {
            let lower = referenceWeights[index]
            let upper = referenceWeights[index + 1]
            if abs(weight - lower) < 0.001 { return index }
            if abs(weight - upper) < 0.001 { return index + 1 }
            if weight > lower && weight < upper { return index }
        }
        return nil
    }

    func outsets(for attributes: FontOutsetAttributes, pointSize: CGFloat, preferredGroup: Int) -> EdgeInsets? {
        guard pointSize.isFinite, pointSize > 0 else { return nil }
        guard let weight = attributes.weight, let index = referenceIndex(for: weight) else { return nil }
        let row = referenceRows[index]
        let edges = preferredGroup == 4 ? row.extended : row.normal
        return EdgeInsets(top: CGFloat(edges[1]) * pointSize, leading: CGFloat(edges[0]) * pointSize,
                          bottom: CGFloat(edges[3]) * pointSize, trailing: CGFloat(edges[2]) * pointSize)
    }
}
