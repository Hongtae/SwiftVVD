//
//  File: SelectedFont.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

/// Logical face inputs retained before the rasterizer lowers variation coordinates.
/// Device resources and rendering modes do not identify a font for character composition.
struct SelectedFont {
    enum Source: Equatable {
        case file(URL, faceIndex: Int, namedInstance: Int?)
        case data(ExternalFontData, faceIndex: Int)
        case supplied(VVD.Font)

        static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.file(a, ai, an), .file(b, bi, bn)):
                return a == b && ai == bi && an == bn
            case let (.data(a, ai), .data(b, bi)):
                return a === b && ai == bi
            case let (.supplied(a), .supplied(b)):
                return a === b
            default:
                return false
            }
        }
    }

    struct Descriptor: Equatable {
        let source: Source
        let postScriptName: String?
        var isSystemFont = false
        // A cascade can retain an unnormalized descriptor, including an empty
        // feature array. Its requests are independent of the active settings.
        var featureRequests: [TypefaceShapingFeature]?
        var language: String?
    }

    var descriptor: Descriptor
    let pointSize: CGFloat
    let variation: [UInt32: CGFloat]
    let syntheticWeight: CGFloat
    var features: [VVD.FontFeatures.Setting] = []
    var originalFeatures: [TypefaceShapingFeature] = []
    var flags: UInt32 = 0xc0
    var language: String?
    // This retained request controls construction even when the comparison
    // coordinates are empty or differ in precision.
    var variationExtras: [UInt32: CGFloat]?

    var hasExtras: Bool {
        language != nil || variationExtras != nil || !features.isEmpty || !originalFeatures.isEmpty
    }

    init(source: Source, pointSize: CGFloat, variation: FontVariationSelection,
         comparisonCoordinates: [UInt32: CGFloat], syntheticWeight: CGFloat) {
        self.descriptor = Descriptor(source: source, postScriptName: variation.postScriptName)
        self.pointSize = pointSize
        self.variation = comparisonCoordinates
        self.syntheticWeight = syntheticWeight
    }

    init(supplied font: VVD.Font, syntheticWeight: CGFloat) {
        self.descriptor = Descriptor(source: .supplied(font), postScriptName: font.postScriptName)
        self.pointSize = font.pointSize
        self.variation = [:]
        self.syntheticWeight = syntheticWeight
    }

    func isEqual(to other: Self) -> Bool {
        pointSize == other.pointSize && syntheticWeight == other.syntheticWeight &&
            descriptor == other.descriptor && variation == other.variation &&
            flags == other.flags && language == other.language &&
            originalFeatures == other.originalFeatures &&
            VVD.FontFeatures.settingsEqual(features, other.features)
    }

    /// Construction retains the original language separately from its flags.
    static func constructionFlags(language: String?) -> UInt32 {
        guard let language else { return 0xc0 }
        if language.hasPrefix("zh") {
            let localizations = ["zxx", "zh-Hans", "zh-Hant", "zh-HK", "zh-MO"]
            let selected = Bundle.preferredLocalizations(from: localizations, forPreferences: [language]).first
            let normalized = selected == nil || selected == "zxx" ? language : selected!
            return normalized.hasPrefix("zh-") ? 0xe0 : 0xc0
        }
        // Component parsing preserves the distinct raw-prefix branch above.
        // Cantonese and Wu resolve through their own language owners.
        let code = Locale.Components(identifier: language).languageComponents.languageCode?.identifier
        return code == "yue" || code == "wuu" ? 0xe0 : 0xc0
    }
}

/// Selected parser coordinates and their name have a different lifetime and precision
/// from both the original variation request and the rasterizer's fixed-point coordinates.
struct FontVariationSelection {
    /// The result crossing from descriptor matching into physical font construction.
    struct Resolved: Hashable {
        let coordinates: [CGFloat]
        let comparison: [UInt32: CGFloat]
        let extras: [UInt32: CGFloat]?
    }

    let metadata: VVD.Font.FaceMetadata
    let coordinates: [CGFloat]

    init(metadata: VVD.Font.FaceMetadata, instanceIndex: Int? = nil) {
        self.metadata = metadata
        self.coordinates = metadata.variationInstances.first { $0.index == instanceIndex }?.coordinates
            ?? metadata.variationAxes.map(\.defaultValue)
    }

    init(metadata: VVD.Font.FaceMetadata, coordinates: [CGFloat]) {
        self.metadata = metadata
        self.coordinates = coordinates
    }

    func resolved(requested: [UInt32: CGFloat]) -> Resolved {
        let merged = merging(requested)
        return Resolved(coordinates: merged.selection.coordinates,
                        comparison: merged.selection.comparisonCoordinates(requested: merged.extras ?? [:]),
                        extras: merged.extras)
    }

    /// A generated name encodes parser coordinates, before descriptor conversion.
    func parsing(suffix: Substring) -> Self? {
        guard !metadata.variationAxes.isEmpty else { return nil }
        let bytes = Array(suffix.utf8)
        guard bytes.allSatisfy({ $0 < 128 }) else { return nil }
        var index = 0
        var values: [UInt32: CGFloat] = [:]
        func hex(_ byte: UInt8) -> UInt32? {
            switch byte {
            case 48...57: UInt32(byte - 48)
            case 65...70: UInt32(byte - 55)
            case 97...102: UInt32(byte - 87)
            default: nil
            }
        }
        while index < bytes.count {
            guard bytes[index] == 95 else { return nil }
            index += 1
            var tag: UInt32 = 0
            for _ in 0..<4 {
                guard index < bytes.count else { return nil }
                let byte: UInt32
                if bytes[index] == 37 {
                    guard index + 2 < bytes.count,
                          let high = hex(bytes[index + 1]), let low = hex(bytes[index + 2]) else { return nil }
                    byte = high << 4 | low
                    index += 3
                } else {
                    byte = UInt32(bytes[index])
                    index += 1
                }
                tag = tag << 8 | byte
            }
            guard let axis = metadata.variationAxes.first(where: { $0.tag == tag }) else { return nil }
            var value = axis.defaultValue
            if index < bytes.count && bytes[index] != 95 {
                var fixed: UInt32 = 0
                repeat {
                    guard let digit = hex(bytes[index]) else { return nil }
                    fixed = (fixed << 4) &+ digit
                    index += 1
                } while index < bytes.count && bytes[index] != 95
                value = CGFloat(Int32(bitPattern: fixed)) / 65536
            }
            values[tag] = value
        }
        guard !values.isEmpty else { return nil }
        return applying(values)
    }

    func applying(_ requested: [UInt32: CGFloat]) -> Self {
        let coordinates = zip(metadata.variationAxes, coordinates).map { axis, old in
            guard let value = requested[axis.tag], !Self.isNear(old, value) else { return old }
            return value
        }
        return Self(metadata: metadata, coordinates: coordinates)
    }

    func merging(_ requested: [UInt32: CGFloat]) -> (selection: Self, extras: [UInt32: CGFloat]?) {
        let base = comparisonCoordinates(requested: [:])
        guard !requested.isEmpty, requested != base else { return (self, nil) }
        func converted(_ value: CGFloat, axis: VVD.Font.VariationAxis) -> CGFloat {
            let truncated = (value * 10000).rounded(.towardZero) / 10000
            return min(max(truncated, axis.minimumValue), axis.maximumValue)
        }
        func valid(_ values: [UInt32: CGFloat]) -> [UInt32: CGFloat] {
            var result: [UInt32: CGFloat] = [:]
            var changed = false
            for axis in metadata.variationAxes {
                guard let original = values[axis.tag] else { continue }
                let value = converted(original, axis: axis)
                if value == axis.defaultValue {
                    changed = true
                } else {
                    result[axis.tag] = value
                    changed = changed || value != original
                }
            }
            // Unchanged dictionaries retain unknown keys. A converted
            // dictionary is rebuilt from its recognized axes instead.
            return changed ? result : values
        }
        let retained: [UInt32: CGFloat]
        if base.isEmpty {
            guard valid(requested) != base else { return (self, nil) }
            retained = requested
        } else {
            var merged = base
            for axis in metadata.variationAxes {
                if let value = requested[axis.tag] {
                    merged[axis.tag] = converted(value, axis: axis)
                }
            }
            guard valid(merged) != base else { return (self, nil) }
            retained = merged
        }
        return (applying(retained), retained)
    }

    var rasterCoordinates: [UInt32: CGFloat] {
        Dictionary(uniqueKeysWithValues: zip(metadata.variationAxes, coordinates).map { axis, value in
            (axis.tag, min(max(value, axis.minimumValue), axis.maximumValue))
        })
    }

    func comparisonCoordinates(requested: [UInt32: CGFloat]) -> [UInt32: CGFloat] {
        var values: [UInt32: CGFloat] = [:]
        for (axis, selected) in zip(metadata.variationAxes, coordinates) {
            let value = requested[axis.tag] ?? selected
            let truncated = (value * 10000).rounded(.towardZero) / 10000
            if truncated != axis.defaultValue {
                values[axis.tag] = min(max(truncated, axis.minimumValue), axis.maximumValue)
            }
        }
        return values
    }

    /// Named faces obtain their axes from the base; generated faces publish a dictionary.
    var descriptorVariation: [UInt32: CGFloat]? {
        let defaults = metadata.variationAxes.map(\.defaultValue)
        if zip(coordinates, defaults).allSatisfy(Self.isNear) { return nil }
        if metadata.variationInstances.contains(where: {
            zip(coordinates, $0.coordinates).allSatisfy(Self.isNear)
        }) { return nil }
        return comparisonCoordinates(requested: [:])
    }

    var postScriptName: String? {
        guard let base = metadata.postScriptName else { return nil }
        let defaults = metadata.variationAxes.map(\.defaultValue)
        if zip(coordinates, defaults).allSatisfy(Self.isNear) { return base }
        if let instance = metadata.variationInstances.first(where: {
            zip(coordinates, $0.coordinates).allSatisfy(Self.isNear)
        }) {
            if instance.postScriptNameID != nil { return instance.postScriptName }
            if let style = instance.styleName,
               style.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) {
                return base + "_" + String(style.prefix(254)).replacingOccurrences(of: " ", with: "-")
            }
            // The metadata reader owns decoding of non-ASCII source names.
            return instance.postScriptName
        }
        guard coordinates.count <= 63 else { return base }
        var suffix = ""
        for (axis, value) in zip(metadata.variationAxes, coordinates) {
            suffix += "_"
            for shift in stride(from: 24, through: 0, by: -8) {
                let byte = UInt8(truncatingIfNeeded: axis.tag >> shift)
                if (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) {
                    suffix.append(Character(UnicodeScalar(byte)))
                } else {
                    suffix += "%" + String(format: "%02X", byte)
                }
            }
            if !Self.isNear(value, axis.defaultValue) {
                let fixed = (value * 65536).rounded(.towardZero)
                let clamped = min(max(fixed, CGFloat(Int32.min)), CGFloat(Int32.max))
                suffix += String(UInt32(bitPattern: Int32(clamped)), radix: 16, uppercase: true)
            }
            if suffix.utf8.count > 255 { return base }
        }
        return base + suffix
    }

    private static func isNear(_ a: CGFloat, _ b: CGFloat) -> Bool {
        let difference = abs(a - b)
        return difference < 0.0001 || difference / max(abs(a), abs(b)) < 0.0001
    }
}
