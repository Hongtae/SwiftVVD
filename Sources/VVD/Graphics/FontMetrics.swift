//
//  File: FontMetrics.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
internal import FreeType

extension Font {
    public struct GlyphMetrics: Sendable {
        public let index: UInt32        // glyph index (FT_UInt)
        public let advance: CGSize      // distance to next glyph
        public let bearing: CGPoint     // offset from baseline (left, top)
        public let size: CGSize         // glyph size (width, height)
        public let ascender: CGFloat    // upper distance from baseline
        public let descender: CGFloat   // lower distance from baseline (negative direction)
    }

    /// The outline representation reported by the selected font driver.
    public enum OutlineFormat: Hashable, Sendable {
        case trueType
        case compactFontFormat
        case other
    }

    /// Distances above and below the baseline in font design units.
    /// Fractional and signed variation adjustments are preserved.
    public struct ClippingMetrics: Hashable, Sendable {
        public let ascent: Double
        public let descent: Double
    }

    /// Unscaled horizontal metrics selected by the font backend.
    /// Values use font design units and include the active variation's adjustments.
    public struct DesignMetrics: Hashable, Sendable {
        public let outlineFormat: OutlineFormat
        public let unitsPerEM: Int
        public let ascender: Int
        public let descender: Int
        public let height: Int

        /// Independent clipping distances, when the selected face provides them.
        /// These use unitsPerEM and retain fractional variation adjustments.
        public let clipping: ClippingMetrics?

        /// The signed gap between the descent and the next line's ascent.
        public var lineGap: Int { height - (ascender - descender) }
    }

    public struct SizeMetrics: Sendable {
        public let xPixelsPerEM: Int
        public let yPixelsPerEM: Int
        public let xScale: CGFloat
        public let yScale: CGFloat
        public let ascender: CGFloat
        public let descender: CGFloat
        public let height: CGFloat
        public let maxAdvance: CGFloat
    }
}

/// Reads fractional clipping distances without changing the selected face.
/// The caller must hold the face's existing state lock for the entire read.
enum FontClippingMetricsReader {
    static func read(face: FT_Face, library: FT_Library?) -> Font.ClippingMetrics? {
        let os2 = FontTable(face: face, tag: 0x4f53_2f32)
        guard os2.contains(0, count: 78) else { return nil }
        let fvar = FontTable(face: face, tag: 0x6676_6172)
        let avar = FontTable(face: face, tag: 0x6176_6172)
        let mvar = FontTable(face: face, tag: 0x4d56_4152)

        var descriptor: UnsafeMutablePointer<FT_MM_Var>?
        let result = FT_Get_MM_Var(face, &descriptor)
        defer {
            if let descriptor { FT_Done_MM_Var(library, descriptor) }
        }
        let axisCount = result == 0 ? Int(descriptor?.pointee.num_axis ?? 0) : 0
        // Raw axes without a complete selected vector cannot produce a snapshot.
        guard fvar.isEmpty ? axisCount == 0 :
            fvar.contains(0, count: 16) && axisCount == Int(fvar.uint16(8)) else { return nil }
        var selected = [FT_Fixed](repeating: 0, count: axisCount)
        if axisCount > 0 {
            guard selected.withUnsafeMutableBufferPointer({
                FT_Get_Var_Design_Coordinates(face, FT_UInt(axisCount), $0.baseAddress)
            }) == 0 else { return nil }
        }
        guard let coordinates = normalizedCoordinates(
            fvar: fvar, avar: avar, selected: selected.map { Int32(truncatingIfNeeded: $0) }
        ) else { return nil }
        return Font.ClippingMetrics(
            ascent: Double(os2.uint16(74)) + metricDelta(mvar, tag: 0x6863_6c61, coordinates: coordinates),
            descent: Double(os2.uint16(76)) + metricDelta(mvar, tag: 0x6863_6c64, coordinates: coordinates)
        )
    }

    private static func normalize(_ value: Int32, minimum: Int32, base: Int32, maximum: Int32) -> Int32 {
        guard minimum <= base, base <= maximum else { return 0 }
        let value = min(max(value, minimum), maximum)
        guard value != base else { return 0 }
        let lower = value < base
        // Differences and the quotient are words; only the division is widened.
        let difference = UInt32(bitPattern: value) &- UInt32(bitPattern: base)
        let numerator = lower ? Int64(Int32(bitPattern: difference)) : Int64(difference)
        let span = lower ? base &- minimum : maximum &- base
        let quotient = span == 0 ? 0 : Int32(truncatingIfNeeded: numerator * 65536 / Int64(span))
        return min(max(quotient, -65536), 65536)
    }

    private static func normalizedCoordinates(fvar: FontTable, avar: FontTable,
                                              selected: [Int32]) -> [Int16]? {
        guard !selected.isEmpty else { return fvar.isEmpty ? [] : nil }
        let start = Int(fvar.uint16(4))
        guard fvar.contains(0, count: 16), Int(fvar.uint16(8)) == selected.count,
              fvar.contains(start, count: selected.count, stride: 20) else { return nil }
        let hasMaps = avar.contains(0, count: 8)
        var mapOffset = 8
        var coordinates: [Int16] = []
        coordinates.reserveCapacity(selected.count)
        for axis in selected.indices {
            let offset = start + axis * 20
            var value = normalize(selected[axis], minimum: fvar.int32(offset + 4),
                                  base: fvar.int32(offset + 8), maximum: fvar.int32(offset + 12))
            if hasMaps {
                guard avar.contains(mapOffset, count: 2) else { return nil }
                let count = Int(avar.uint16(mapOffset))
                mapOffset += 2
                guard avar.contains(mapOffset, count: count, stride: 4) else { return nil }
                if value != 0, count >= 2 {
                    var x1 = Int64(avar.int16(mapOffset)) * 4
                    var y1 = Int64(avar.int16(mapOffset + 2)) * 4
                    for index in 1..<count {
                        let x2 = Int64(avar.int16(mapOffset + index * 4)) * 4
                        let y2 = Int64(avar.int16(mapOffset + index * 4 + 2)) * 4
                        if Int64(value) <= x2, x2 > x1, y2 >= y1 {
                            let mapped = y1 + (Int64(value) - x1) * (y2 - y1) / (x2 - x1)
                            value = Int32(min(max(mapped, -65536), 65536))
                            break
                        }
                        x1 = x2
                        y1 = y2
                    }
                }
                mapOffset += count * 4
            }
            coordinates.append(Int16((value + 2) >> 2))
        }
        if hasMaps, avar.uint16(0) >= 2, avar.contains(mapOffset, count: 8) {
            let indexOffset = Int(avar.uint32(mapOffset))
            let storeOffset = Int(avar.uint32(mapOffset + 4))
            guard storeOffset != 0, let store = VariationStore(avar.suffix(storeOffset)) else {
                return coordinates
            }
            let indices = indexOffset == 0 ? FontTable() : avar.suffix(indexOffset)
            if indexOffset != 0 {
                guard indices.contains(0, count: 1) else { return coordinates }
                let format = indices.uint8(0)
                if format <= 1, !indices.contains(0, count: format == 0 ? 4 : 6) { return coordinates }
            }
            // Each correction uses the complete unchanged first-pass vector.
            let before = coordinates
            for axis in coordinates.indices {
                let index = indexOffset == 0 ? UInt32(axis) : mappedIndex(indices, index: UInt32(axis))
                let delta = store.delta(outer: Int(index >> 16), inner: Int(index & 65535), coordinates: before)
                let value = Double(before[axis]) + delta.rounded(.toNearestOrAwayFromZero)
                coordinates[axis] = Int16(min(max(value, -16384), 16384))
            }
        }
        return coordinates
    }

    private static func mappedIndex(_ map: FontTable, index: UInt32) -> UInt32 {
        guard map.contains(0, count: 1) else { return index }
        let format = map.uint8(0)
        let header = format == 0 ? 4 : format == 1 ? 6 : 0
        guard header > 0, map.contains(0, count: header) else { return index }
        let count = format == 0 ? UInt32(map.uint16(2)) : map.uint32(2)
        guard count > 0 else { return index }
        let index = min(index, count - 1)
        let bits = UInt32(map.uint8(1) & 15) + 1
        let stride = Int((map.uint8(1) >> 4) & 3) + 1
        guard map.contains(header, count: Int(index) + 1, stride: stride) else { return index }
        var value: UInt32 = 0
        for byte in 0..<stride { value = (value << 8) | UInt32(map.uint8(header + Int(index) * stride + byte)) }
        return ((value >> bits) << 16) &+ (value & ((1 << bits) - 1))
    }

    private static func metricDelta(_ mvar: FontTable, tag: UInt32, coordinates: [Int16]) -> Double {
        guard mvar.contains(0, count: 12), mvar.uint16(0) == 1 else { return 0 }
        let stride = Int(mvar.uint16(6)), count = Int(mvar.uint16(8)), offset = Int(mvar.uint16(10))
        guard stride >= 8, count > 0, offset > 0,
              mvar.contains(12, count: count, stride: stride),
              let store = VariationStore(mvar.suffix(offset)) else { return 0 }
        var begin = 0, length = count
        while length > 0 {
            let middle = begin + length / 2
            let offset = 12 + middle * stride
            let candidate = mvar.uint32(offset)
            if candidate == tag {
                return store.delta(outer: Int(mvar.uint16(offset + 4)),
                                   inner: Int(mvar.uint16(offset + 6)), coordinates: coordinates)
            }
            if tag > candidate { begin = middle + 1; length -= 1 }
            length /= 2
        }
        return 0
    }
}

/// An owned table buffer with checked, relative byte access and shared suffixes.
private struct FontTable {
    private let bytes: [UInt8]
    private let start: Int
    var isEmpty: Bool { start == bytes.count }

    init() { bytes = []; start = 0 }

    init(face: FT_Face, tag: FT_ULong) {
        var size: FT_ULong = 0
        guard FT_Load_Sfnt_Table(face, tag, 0, nil, &size) == 0,
              size > 0, let count = Int(exactly: size) else { self.init(); return }
        var bytes = [UInt8](repeating: 0, count: count)
        var actual = size
        let result = bytes.withUnsafeMutableBufferPointer {
            FT_Load_Sfnt_Table(face, tag, 0, $0.baseAddress, &actual)
        }
        guard result == 0, actual == size else { self.init(); return }
        self.init(bytes: bytes, start: 0)
    }

    private init(bytes: [UInt8], start: Int) { self.bytes = bytes; self.start = start }

    func contains(_ offset: Int, count: Int, stride: Int = 1) -> Bool {
        let available = bytes.count - start
        return offset >= 0 && offset <= available && count >= 0 && stride >= 0 &&
            (stride == 0 || count <= (available - offset) / stride)
    }

    func suffix(_ offset: Int) -> Self {
        contains(offset, count: 0) ? Self(bytes: bytes, start: start + offset) : Self()
    }

    func uint8(_ offset: Int) -> UInt8 { contains(offset, count: 1) ? bytes[start + offset] : 0 }
    func uint16(_ offset: Int) -> UInt16 {
        guard contains(offset, count: 2) else { return 0 }
        return UInt16(bytes[start + offset]) << 8 | UInt16(bytes[start + offset + 1])
    }
    func int16(_ offset: Int) -> Int16 { Int16(bitPattern: uint16(offset)) }
    func uint32(_ offset: Int) -> UInt32 {
        guard contains(offset, count: 4) else { return 0 }
        return UInt32(uint16(offset)) << 16 | UInt32(uint16(offset + 2))
    }
    func int32(_ offset: Int) -> Int32 { Int32(bitPattern: uint32(offset)) }
}

private struct VariationStore {
    let bytes: FontTable
    let regions: FontTable
    let regionCount: Int
    let axisCount: Int
    let itemCount: Int

    init?(_ bytes: FontTable) {
        guard bytes.contains(0, count: 8),
              bytes.contains(8, count: Int(bytes.uint16(6)), stride: 4) else { return nil }
        let offset = Int(bytes.uint32(2))
        guard offset != 0 else { return nil }
        let regions = bytes.suffix(offset)
        guard regions.contains(0, count: 4) else { return nil }
        let axes = Int(regions.uint16(0)), count = Int(regions.uint16(2))
        guard regions.contains(4, count: count, stride: axes * 6) else { return nil }
        self.bytes = bytes
        self.regions = regions
        self.axisCount = axes
        self.regionCount = count
        self.itemCount = Int(bytes.uint16(6))
    }

    private func scalar(region: Int, coordinates: [Int16]) -> Double {
        var result = 1.0
        for axis in 0..<min(axisCount, coordinates.count) {
            let offset = 4 + (region * axisCount + axis) * 6
            let start = Int(regions.int16(offset)), peak = Int(regions.int16(offset + 2))
            let end = Int(regions.int16(offset + 4)), value = Int(coordinates[axis])
            if start > peak || peak > end || peak == 0 || (start < 0 && end > 0) { continue }
            if value < start || value > end { return 0 }
            if value == peak { continue }
            result *= value < peak ? Double(value - start) / Double(peak - start) :
                Double(end - value) / Double(end - peak)
        }
        return result
    }

    func delta(outer: Int, inner: Int, coordinates: [Int16]) -> Double {
        guard outer < itemCount, !(outer == 65535 && inner == 65535) else { return 0 }
        let itemOffset = Int(bytes.uint32(8 + outer * 4))
        guard itemOffset != 0 else { return 0 }
        let items = bytes.suffix(itemOffset)
        guard items.contains(0, count: 6) else { return 0 }
        let rows = Int(items.uint16(0)), words = Int(items.uint16(2)), count = Int(items.uint16(4))
        let wide = words & 0x7fff, longWords = words & 0x8000 != 0
        guard inner < rows, wide <= count, items.contains(6, count: count, stride: 2) else { return 0 }
        let stride = (count + wide) * (longWords ? 2 : 1), start = 6 + count * 2
        // Validate all rows of the selected item, not only the requested row.
        guard items.contains(start, count: rows, stride: stride) else { return 0 }
        var offset = start + inner * stride
        var sum = 0.0
        for index in 0..<count {
            let region = Int(items.uint16(6 + index * 2))
            guard region < regionCount else { return 0 }
            let value: Int32
            if longWords && index < wide {
                value = items.int32(offset); offset += 4
            } else if longWords || index < wide {
                value = Int32(items.int16(offset)); offset += 2
            } else {
                value = Int32(Int8(bitPattern: items.uint8(offset))); offset += 1
            }
            sum = sum.addingProduct(scalar(region: region, coordinates: coordinates), Double(value))
        }
        return sum
    }
}
