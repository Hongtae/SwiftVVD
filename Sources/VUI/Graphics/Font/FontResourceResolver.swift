//
//  File: FontResourceResolver.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

/// Immutable candidates and name indexes for one catalog's resource snapshots.
struct FontResourceResolver: Sendable {
    struct Traits: Sendable {
        var symbolic: UInt32
        var weight: CGFloat
        var width: CGFloat
        var slant: CGFloat

        func distance(to other: Self) -> CGFloat {
            let w = weight - other.weight
            let p = width - other.width
            let s = slant - other.slant
            return (w * w + p * p) + s * s
        }

        func precedes(_ other: Self) -> Bool {
            let a = symbolic & 0x0fff_ffff
            let b = other.symbolic & 0x0fff_ffff
            if a != b { return a < b }
            if abs(weight - other.weight) >= 0.0001 { return abs(weight) < abs(other.weight) }
            if abs(slant - other.slant) >= 0.0001 { return abs(slant) < abs(other.slant) }
            if abs(width - other.width) >= 0.0001 { return abs(width) < abs(other.width) }
            func classOrder(_ traits: UInt32) -> Int {
                switch traits >> 28 {
                case 1...8: 1
                case 9...11: 2
                case 12: 3
                default: 999
                }
            }
            return classOrder(symbolic) < classOrder(other.symbolic)
        }
    }

    struct Candidate: Sendable {
        let face: FontResourceCatalog.Face
        let instanceIndex: Int?
        let coordinates: [CGFloat]
        let traits: Traits

        var variations: [BundledFontVariation] {
            zip(face.metadata.variationAxes, coordinates).map {
                BundledFontVariation(tag: $0.tag, value: $1)
            }
        }

        var family: String { face.metadata.familyName ?? "" }

        var instance: VVD.Font.VariationInstance? {
            face.metadata.variationInstances.first { $0.index == instanceIndex }
        }

        var postScriptName: String? {
            guard let instance, instance.index != face.metadata.defaultVariationInstanceIndex else {
                return face.metadata.postScriptName
            }
            if instance.postScriptNameID != nil { return instance.postScriptName }
            if let base = face.metadata.postScriptName, let style = instance.styleName,
               style.utf8.count <= 254, style.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) {
                return base + "_" + style.replacingOccurrences(of: " ", with: "-")
            }
            return instance.postScriptName
        }
    }

    let candidates: [Candidate]
    private let postScriptNames: [String: [Int]]
    private let fullNames: [String: [Int]]
    private let familyNames: [String: [Int]]

    init(faces: [FontResourceCatalog.Face]) {
        var candidates: [Candidate] = []
        for face in faces {
            let metadata = face.metadata
            if metadata.variationInstances.isEmpty {
                candidates.append(Self.candidate(face: face, instance: nil))
            } else {
                for instance in metadata.variationInstances {
                    candidates.append(Self.candidate(face: face, instance: instance))
                }
            }
        }
        candidates.sort { $0.traits.precedes($1.traits) }
        self.candidates = candidates

        var postScript: [String: [Int]] = [:]
        var full: [String: [Int]] = [:]
        var families: [String: [Int]] = [:]
        func append(_ name: String?, index: Int, to table: inout [String: [Int]]) {
            guard let name, !name.isEmpty else { return }
            let key = name.lowercased()
            if table[key]?.contains(index) != true { table[key, default: []].append(index) }
        }
        for (index, candidate) in candidates.enumerated() {
            let metadata = candidate.face.metadata
            let isDefault = candidate.instanceIndex == metadata.defaultVariationInstanceIndex
            append(candidate.postScriptName, index: index, to: &postScript)
            append(candidate.instance?.postScriptName, index: index, to: &postScript)
            if isDefault {
                append(metadata.postScriptName, index: index, to: &postScript)
            }
            append(metadata.familyName, index: index, to: &families)
            let prefix = Self.name(25, in: metadata) ?? Self.name(16, in: metadata)
            if let prefix, let style = candidate.instance?.styleName,
               let prefix = Self.postScriptComponent(prefix),
               let suffix = Self.postScriptComponent(style),
               prefix.utf8.count + suffix.utf8.count + 1 <= 127 {
                append(prefix + "-" + suffix, index: index, to: &postScript)
            }
            for record in metadata.sfntNames {
                switch record.nameID {
                case 1, 16:
                    append(record.string, index: index, to: &families)
                case 4:
                    append(record.string, index: index, to: &full)
                    let subfamily = isDefault ? Self.name(2, in: metadata) : candidate.instance?.styleName
                    if let name = record.string, let subfamily {
                        append(name + " " + subfamily, index: index, to: &full)
                    }
                case 6 where isDefault:
                    append(record.string, index: index, to: &postScript)
                default:
                    break
                }
            }
        }
        postScriptNames = postScript
        fullNames = full
        familyNames = families
    }

    func named(_ name: String) -> Candidate? {
        let key = name.lowercased()
        let indices = postScriptNames[key] ?? fullNames[key] ?? familyNames[key]
        return indices?.first.map { candidates[$0] }
    }

    func family(_ name: String) -> [Candidate] {
        familyNames[name.lowercased(), default: []].map { candidates[$0] }
    }

    static func select(_ candidates: [Candidate], matching traits: Traits) -> Candidate? {
        guard var best = candidates.first else { return nil }
        if candidates.count == 1 { return best }
        var distance = best.traits.distance(to: traits)
        for candidate in candidates.dropFirst() {
            let next = candidate.traits.distance(to: traits)
            if next < distance {
                if next == 0 { return candidate }
                best = candidate
                distance = next
            }
        }
        return best
    }

    private static func name(_ id: UInt16, in metadata: VVD.Font.FaceMetadata) -> String? {
        metadata.sfntNames.first { $0.nameID == id && $0.platformID == 3 && $0.languageID == 0x409 }?.string
            ?? metadata.sfntNames.first { $0.nameID == id && $0.string != nil }?.string
    }

    private static func postScriptComponent(_ name: String) -> String? {
        // Preserve non-ASCII source names in their original indexes; no transliteration is applied.
        guard name.utf8.allSatisfy({ $0 < 128 }) else { return nil }
        let bytes = name.utf8.enumerated().compactMap { index, byte -> UInt8? in
            if index == 0 && byte == 46 { return byte }
            return (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte)
                ? byte : nil
        }
        return String(bytes: bytes, encoding: .utf8)
    }

    private static func candidate(
        face: FontResourceCatalog.Face,
        instance: VVD.Font.VariationInstance?
    ) -> Candidate {
        let metadata = face.metadata
        let coordinates = instance?.coordinates ?? metadata.variationAxes.map(\.defaultValue)
        var weight = FontWeightScale.logicalWeight(forClass: CGFloat(metadata.sfntStyle.weightClass ?? 400))
        var width = CGFloat(Float(Int(metadata.sfntStyle.widthClass ?? 5) - 5) * 0.1)
        let italic = (metadata.sfntStyle.selection ?? 0) & 1 != 0 ||
            (metadata.sfntStyle.macStyle ?? 0) & 2 != 0
        let slant = sourceSlant(style: instance?.styleName ?? metadata.styleName,
                                angle: metadata.sfntStyle.italicAngle ?? 0)
        // A default face retains its source traits in the registered descriptor.
        // Its glyph coordinates still use the axis defaults stored above.
        for (axis, coordinate) in zip(metadata.variationAxes, coordinates)
            where instance?.index != metadata.defaultVariationInstanceIndex {
            switch axis.tag {
            case 0x7767_6874:
                weight = FontWeightScale.logicalWeight(forClass: coordinate.rounded())
            case 0x7764_7468:
                width = logicalWidth(forPercent: coordinate)
            default:
                break
            }
        }
        var symbolic: UInt32 = italic ? 1 : 0
        if weight >= CGFloat(Float(0.3)) { symbolic |= 2 }
        if width < 0 { symbolic |= 64 }
        if width > 0 { symbolic |= 32 }
        if metadata.sfntStyle.fixedPitch != 0 && metadata.sfntStyle.fixedPitch != nil { symbolic |= 1024 }
        return Candidate(face: face, instanceIndex: instance?.index, coordinates: coordinates,
                         traits: Traits(symbolic: symbolic, weight: weight, width: width, slant: slant))
    }

    private static func logicalWidth(forPercent percent: CGFloat) -> CGFloat {
        let percentages = widthPercentages
        let values = widthValues
        if percent <= percentages[0] { return CGFloat(values[0]) }
        for index in 0..<10 where percent <= percentages[index + 1] {
            let fraction = Float((percent - percentages[index]) / (percentages[index + 1] - percentages[index]))
            return CGFloat(values[index] + (values[index + 1] - values[index]) * fraction)
        }
        return CGFloat(values[10])
    }

    private static let widthPercentages: [CGFloat] = [37.5, 50, 62.5, 75, 87.5, 100, 112.5, 125, 150, 200, 250]
    private static let widthValues: [Float] = [-0.5, -0.4, -0.3, -0.2, -0.1, 0, 0.1, 0.2, 0.3, 0.4, 0.5]

    private static func sourceSlant(style: String?, angle: CGFloat) -> CGFloat {
        if let style = style?.lowercased(), style.utf8.count < 200 {
            for (token, bits) in slantValues where style.contains(token) {
                return CGFloat(Float(bitPattern: bits))
            }
        }
        // The resource backend exposes the source post angle directly.
        return angle * (-1.0 / 180.0)
    }

    private static let slantValues: [(String, UInt32)] = [
        ("extra slant", 0x3e0e_38e4), ("back slant", 0xbd8e_38de),
        ("extraslant", 0x3e0e_38e4), ("backslant", 0xbd8e_38de),
        ("oblique", 0x3d8e_38e3), ("upright", 0), ("bookit", 0x3d8e_38e3),
        ("italic", 0x3d8e_38e3), ("slant", 0x3d8e_38e3)
    ]
}
