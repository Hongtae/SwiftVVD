//
//  File: FontDecorationMetrics.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

struct TypefaceDecorationMetrics {
    var xHeight: CGFloat?
    var underlinePosition: CGFloat
    var underlineThickness: CGFloat
    var defaultAscent: CGFloat? = nil
    var defaultDescent: CGFloat? = nil

    func scaled(by scale: CGFloat) -> TypefaceDecorationMetrics {
        TypefaceDecorationMetrics(
            xHeight: xHeight.map { $0 * scale },
            underlinePosition: underlinePosition * scale,
            underlineThickness: underlineThickness * scale,
            defaultAscent: defaultAscent.map { $0 * scale },
            defaultDescent: defaultDescent.map { $0 * scale }
        )
    }
}

private struct OpenTypeDecorationMetrics {
    private struct Table {
        var offset: Int
        var length: Int
    }

    private let data: any FixedAddressStorageData
    private let directoryOffset: Int

    init?(font: VVD.Font) {
        let resolvedData: any FixedAddressStorageData
        if let fontData = font.fontData {
            resolvedData = fontData
        } else if !font.filePath.isEmpty,
                  let fileData = try? Data(
                    contentsOf: URL(fileURLWithPath: font.filePath)
                  ) {
            resolvedData = fileData.makeFixedAddressStorage()
        } else {
            return nil
        }

        func uint32(at offset: Int) -> UInt32? {
            guard offset >= 0,
                  offset <= resolvedData.count - 4,
                  let address = resolvedData.address else {
                return nil
            }
            return UInt32(bigEndian: address.loadUnaligned(
                fromByteOffset: offset,
                as: UInt32.self
            ))
        }

        guard resolvedData.count >= 12 else { return nil }
        let resolvedDirectoryOffset: Int
        if uint32(at: 0) == Self.tag("ttcf") {
            guard let numberOfFonts = uint32(at: 8),
                  font.faceIndex >= 0,
                  font.faceIndex < Int(numberOfFonts),
                  let faceOffset = uint32(at: 12 + font.faceIndex * 4),
                  let faceDirectoryOffset = Int(exactly: faceOffset) else {
                return nil
            }
            resolvedDirectoryOffset = faceDirectoryOffset
        } else {
            resolvedDirectoryOffset = 0
        }
        guard resolvedDirectoryOffset <= resolvedData.count - 12 else {
            return nil
        }
        data = resolvedData
        directoryOffset = resolvedDirectoryOffset
    }

    func resolve(font: VVD.Font) -> TypefaceDecorationMetrics? {
        guard let head = table("head"),
              let post = table("post"),
              head.length >= 20,
              post.length >= 12,
              let unitsPerEm = uint16IfPresent(at: head.offset + 18),
              unitsPerEm > 0,
              let underlinePosition = int16IfPresent(at: post.offset + 8),
              let underlineThickness = int16IfPresent(at: post.offset + 10) else {
            return nil
        }

        // Keep logical sizes independent of the rasterizer's fixed-point size.
        let scale = font.pointSize * CGFloat(font.dpi.y) / 72 / CGFloat(unitsPerEm)
        guard scale.isFinite, scale > 0 else { return nil }
        let thickness = abs(CGFloat(underlineThickness) * scale)
        guard thickness > 0 else { return nil }

        var xHeight: CGFloat?
        if let os2 = table("OS/2"),
           os2.length >= 88,
           let version = uint16IfPresent(at: os2.offset),
           version >= 2,
           let value = int16IfPresent(at: os2.offset + 86),
           value != 0 {
            xHeight = CGFloat(value) * scale
        } else {
            xHeight = font.glyphMetrics(
                for: UnicodeScalar("x")
            )?.bearing.y
        }

        let design = font.designMetrics
        return TypefaceDecorationMetrics(
            xHeight: xHeight,
            underlinePosition: CGFloat(underlinePosition) * scale,
            underlineThickness: thickness,
            defaultAscent: design.map { CGFloat($0.ascender) * scale },
            defaultDescent: design.map { abs(CGFloat($0.descender)) * scale }
        )
    }

    private func table(_ name: String) -> Table? {
        guard let numberOfTables = uint16IfPresent(
            at: directoryOffset + 4
        ) else {
            return nil
        }
        let target = Self.tag(name)
        for index in 0..<Int(numberOfTables) {
            let recordOffset = directoryOffset + 12 + index * 16
            guard recordOffset <= data.count - 16 else { return nil }
            guard uint32(at: recordOffset) == target,
                  let offset = uint32IfPresent(at: recordOffset + 8),
                  let length = uint32IfPresent(at: recordOffset + 12),
                  let tableOffset = Int(exactly: offset),
                  let tableLength = Int(exactly: length) else {
                continue
            }
            let table = Table(offset: tableOffset, length: tableLength)
            guard table.offset <= data.count,
                  table.length <= data.count - table.offset else {
                return nil
            }
            return table
        }
        return nil
    }

    private func uint16IfPresent(at offset: Int) -> UInt16? {
        guard offset >= 0,
              offset <= data.count - 2,
              let address = data.address else { return nil }
        return UInt16(bigEndian: address.loadUnaligned(
            fromByteOffset: offset,
            as: UInt16.self
        ))
    }

    private func int16IfPresent(at offset: Int) -> Int16? {
        uint16IfPresent(at: offset).map(Int16.init(bitPattern:))
    }

    private func uint32IfPresent(at offset: Int) -> UInt32? {
        guard offset >= 0,
              offset <= data.count - 4,
              let address = data.address else { return nil }
        return UInt32(bigEndian: address.loadUnaligned(
            fromByteOffset: offset,
            as: UInt32.self
        ))
    }

    private func uint32(at offset: Int) -> UInt32 {
        uint32IfPresent(at: offset) ?? 0
    }

    private static func tag(_ value: String) -> UInt32 {
        value.utf8.reduce(UInt32.zero) {
            ($0 << 8) | UInt32($1)
        }
    }
}

func typefaceDecorationMetrics(
    for font: VVD.Font
) -> TypefaceDecorationMetrics? {
    OpenTypeDecorationMetrics(font: font)?.resolve(font: font)
}
