//
//  File: Font.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
private import FreeType
private import HarfBuzz

//////////////////////////////////////////////////////////////////////////////
// The coordinate system of the font has a positive Y value
// in the upward direction, based on the 'baseline'.
// This means that in a coordinate system where the top left is the origin,
// the Y value must be inverted relative to the 'baseline'.
//
//
//                                       offset +--------+
//                              (from baseline) | Glyph  |
//   +Y                                         | Bitmap |
//    |    |< advance >|                        +--------+ extent
//    |    |           |
//    |    ooooooooooooo  - - - - - - - - - - - - - - - - - - - ascender (+y)
//    |    8'   888   `8
//    |         888      oooo    ooo oo.ooooo.   .ooooo.
//    |         888       `88.  .8'   888' `88b d88' `88b
//    |         888        `88..8'    888   888 888ooo888
//    |         888         `888'     888   888 888    .o
// ___|________o888o_________.8'______888bod8P'_`Y8bod8P'______ baseline
//  origin                .o..P'      888
//    |                   `Y8P'      o888o _ _ _ _ _ _ _ _ _ _ descender (-y)
//    |
//   -Y
//                               (The ASCII font design is taken from FIGlet)

private final class FTLibrary: @unchecked Sendable {
    private let faceLifecycleLock = Mutex<Void>(())
    var library: FT_Library?

    init() {
        FT_Init_FreeType(&library)
    }

    deinit {
        FT_Done_FreeType(library)
    }

    func withFaceLifecycleLock<T>(_ body: () throws -> T) rethrows -> T {
        try faceLifecycleLock.withLock { _ in try body() }
    }
}

private let library = Mutex<WeakObject<FTLibrary>>(nil)

private func sharedFTLibrary() -> FTLibrary {
    library.withLock {
        if let lib = $0.value {
            return lib
        }
        let lib = FTLibrary()
        $0.value = lib
        return lib
    }
}

@inline(__always)
private func ft26d6ToFloat(_ value: FT_F26Dot6) -> CGFloat {
    CGFloat(value >> 6) + CGFloat(value & 63) / 64.0
}

@inline(__always)
private func ft26d6(_ value: CGFloat) -> FT_F26Dot6 {
    FT_F26Dot6(value * 64.0)
}

@inline(__always)
private func ft26d6Floor(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    value & ~63
}

@inline(__always)
private func ft26d6Round(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    ft26d6Floor(value + 32)
}

@inline(__always)
private func ft26d6Ceil(_ value: FT_F26Dot6) -> FT_F26Dot6 {
    ft26d6Floor(value + 63)
}

@inline(__always)
private func ft16d16ToFloat(_ value: FT_Fixed) -> CGFloat {
    CGFloat(value >> 16) + CGFloat(value & 65535) / 65536.0
}

@inline(__always)
private func ft16d16(_ value: CGFloat) -> FT_Fixed {
    FT_Fixed(value * 65536.0)
}

@inline(__always)
private func FT_HAS_KERNING(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_KERNING != 0
}

@inline(__always)
private func FT_IS_SCALABLE(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_SCALABLE != 0
}

@inline(__always)
private func FT_IS_FIXED_WIDTH(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_FIXED_WIDTH != 0
}

@inline(__always)
private func FT_HAS_FIXED_SIZES(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_FIXED_SIZES != 0
}

@inline(__always)
private func FT_HAS_COLOR(_ face: FT_Face) -> Bool {
    return face.pointee.face_flags & FT_FACE_FLAG_COLOR != 0
}

private extension CGPoint {
    init(_ vector: FT_Vector) {
        self.init(x: CGFloat(vector.x), y: CGFloat(vector.y))
    }
    init(ft26d6: FT_Vector) {
        self.init(x: ft26d6ToFloat(ft26d6.x), y: ft26d6ToFloat(ft26d6.y))
    }
    init(ft16d16: FT_Vector) {
        self.init(x: ft16d16ToFloat(ft16d16.x), y: ft16d16ToFloat(ft16d16.y))
    }
}

public class Font: @unchecked Sendable {
    public typealias DPI = (x: UInt32, y: UInt32)
    //public static let defaultDPI = DPI(x: 96, y: 96)
    public static let defaultDPI = DPI(x: 72, y: 72)

    private let library: FTLibrary

    /// Loaded bytes shared by deliberate copies, independently of mutable faces.
    package final class Source: @unchecked Sendable {
        private struct Storage: @unchecked Sendable {
            let data: any FixedAddressStorageData
        }
        private let storage: Mutex<Storage?>

        fileprivate init(data: (any FixedAddressStorageData)? = nil) {
            storage = Mutex(data.map { Storage(data: $0) })
        }

        // The caller holds the face lock. Never reopen its original path: the
        // loaded stream may survive a rename, replacement or removal of that file.
        fileprivate func data(from stream: FT_Stream) -> (any FixedAddressStorageData)? {
            storage.withLock { data -> Storage? in
                if let data { return data }
                guard let size = Int(exactly: stream.pointee.size), size > 0 else { return nil }
                let bytes: Data
                if let read = stream.pointee.read {
                    let position = stream.pointee.pos
                    defer {
                        _ = read(stream, position, nil, 0)
                        stream.pointee.pos = position
                    }
                    // Compressed streams can publish a sentinel size until EOF.
                    // Read in bounded chunks rather than allocating that size.
                    var result = Data()
                    var buffer = [UInt8](repeating: 0, count: min(size, 65536))
                    while result.count < size {
                        let count = min(buffer.count, size - result.count)
                        let received = buffer.withUnsafeMutableBufferPointer {
                            read(stream, FT_ULong(result.count), $0.baseAddress, FT_ULong(count))
                        }
                        guard received <= count else { return nil }
                        result.append(contentsOf: buffer.prefix(Int(received)))
                        if received < count {
                            guard stream.pointee.size == 0x7fffffff else { return nil }
                            break
                        }
                    }
                    guard !result.isEmpty else { return nil }
                    bytes = result
                } else {
                    guard let base = stream.pointee.base else { return nil }
                    bytes = Data(bytes: base, count: size)
                }
                let retained = Storage(data: bytes.makeFixedAddressStorage())
                data = retained
                return retained
            }?.data
        }
    }

    package let source: Source

    private struct State: @unchecked Sendable {
        let face: FT_Face
        let shapingFont: OpaquePointer
        let layoutFont: OpaquePointer?
        let hasColorPaint: Bool
        var colorRasterizer: OpaquePointer?
        var pointSize: CGFloat
        var size26d6: FT_F26Dot6
        var dpi: DPI

        var featureCatalog: FontFeatures?
        var isBitmapPreferred = false
        var isKerningEnabled = true
        var isColorEnabled = true
    }
    private let state: Mutex<State>

    struct LockedFace {
        fileprivate let pointer: FT_Face
        fileprivate let isBitmapPreferred: Bool
        fileprivate let isColorEnabled: Bool
        fileprivate let shapingFont: OpaquePointer
        fileprivate let colorRasterizer: OpaquePointer?
    }

    func withLockedFace<T>(_ body: (LockedFace) throws -> T) rethrows -> T {
        try state.withLock {
            if $0.hasColorPaint && $0.colorRasterizer == nil {
                $0.colorRasterizer = hb_raster_paint_create_or_fail()
            }
            return try body(LockedFace(
                pointer: $0.face,
                isBitmapPreferred: $0.isBitmapPreferred,
                isColorEnabled: $0.isColorEnabled,
                shapingFont: $0.shapingFont,
                colorRasterizer: $0.colorRasterizer
            ))
        }
    }

    /// The PostScript name of the currently selected face configuration.
    public var postScriptName: String? {
        state.withLock { FT_Get_Postscript_Name($0.face).map { String(cString: $0) } }
    }

    package var featureCatalog: FontFeatures {
        state.withLock { state in
            if let catalog = state.featureCatalog { return catalog }
            let catalog = FontFeatures(face: hb_font_get_face(state.shapingFont))
            state.featureCatalog = catalog
            return catalog
        }
    }

    public let fontData: (any FixedAddressStorageData)?

    public let familyName: String
    public let styleName: String
    public let filePath: String
    /// The selected face within a font collection.
    public let faceIndex: Int
    /// The number of faces contained in the source font or collection.
    public let numFaces: Int
    public let numGlyphs: Int

    public let maxPointSize: CGFloat = CGFloat(1<<25) - CGFloat(1.0/64.0)

    /// Logical point size before rasterizer quantization.
    public var pointSize: CGFloat {
        get { state.withLock { $0.pointSize } }
        set { self.updateSize(pointSize: newValue, dpi: nil) }
    }

    public var dpi: DPI {
        get { state.withLock { $0.dpi } }
        set { self.updateSize(pointSize: nil, dpi: newValue) }
    }

    public var isBitmapPreferred: Bool {
        get { state.withLock { $0.isBitmapPreferred } }
        set {
            state.withLock {
                if $0.isBitmapPreferred != newValue {
                    $0.isBitmapPreferred = newValue
                    self.clearCacheLocked()
                }
            }
        }
    }

    public var isKerningEnabled: Bool {
        get { state.withLock { $0.isKerningEnabled } }
        set {
            state.withLock {
                if $0.isKerningEnabled != newValue {
                    $0.isKerningEnabled = newValue
                    self.clearCacheLocked()
                }
            }
        }
    }

    public var isColorEnabled: Bool {
        get { state.withLock { $0.isColorEnabled } }
        set {
            state.withLock {
                if $0.isColorEnabled != newValue {
                    $0.isColorEnabled = newValue
                    self.clearCacheLocked()
                }
            }
        }
    }

    public var hasColor: Bool {
        self.state.withLock { FT_HAS_COLOR($0.face) }
    }

    public var isScalable: Bool {
        self.state.withLock { FT_IS_SCALABLE($0.face) }
    }

    /// Converts a selected fixed bitmap strike's pixels to the requested size.
    /// Scalable faces already render at the requested size and return one.
    public var bitmapScale: CGFloat {
        state.withLock {
            guard !FT_IS_SCALABLE($0.face) else { return 1 }
            let pixelsPerEM = CGFloat($0.face.pointee.size.pointee.metrics.y_ppem)
            guard pixelsPerEM > 0 else { return 1 }
            return $0.pointSize * CGFloat($0.dpi.y) / 72 / pixelsPerEM
        }
    }

    public struct VariationAxis: Hashable, Sendable {
        public let tag: UInt32
        public let minimumValue: CGFloat
        public let defaultValue: CGFloat
        public let maximumValue: CGFloat
    }

    public struct VariationInstance: Hashable, Sendable {
        /// One-based identity within the source and collection face.
        public let index: Int
        public let styleName: String?
        public let postScriptName: String?
        /// Source name-table identifiers, distinct from the resolved names.
        public let styleNameID: UInt16?
        public let postScriptNameID: UInt16?
        /// Coordinates in the parent FaceMetadata.variationAxes order.
        public let coordinates: [CGFloat]
    }

    public struct SFNTStyleMetadata: Hashable, Sendable {
        public let weightClass: UInt16?
        public let widthClass: UInt16?
        public let familyClass: Int16?
        public let selection: UInt16?
        public let macStyle: UInt16?
        /// The raw post table angle in degrees.
        public let italicAngle: CGFloat?
        public let fixedPitch: UInt32?
    }

    public struct SFNTNameRecord: Hashable, Sendable {
        public let platformID: UInt16
        public let encodingID: UInt16
        public let languageID: UInt16
        public let nameID: UInt16
        /// The original bytes remain available even for unsupported encodings.
        public let data: Data

        public var string: String? {
            switch (platformID, encodingID) {
            case (0, _), (3, 0), (3, 1), (3, 10):
                guard data.count.isMultiple(of: 2) else { return nil }
                return String(data: data, encoding: .utf16BigEndian)
            case (1, 0):
                return String(data: data, encoding: .macOSRoman)
            default:
                return nil
            }
        }
    }

    /// Copied resource metadata, independent of a rendering face and source buffer.
    public struct FaceMetadata: Hashable, Sendable {
        public let faceIndex: Int
        public let numFaces: Int
        public let familyName: String?
        public let styleName: String?
        public let postScriptName: String?
        public let variationAxes: [VariationAxis]
        public let variationInstances: [VariationInstance]
        /// One-based instance identity; nil when the face has no default instance.
        public let defaultVariationInstanceIndex: Int?
        public let sfntStyle: SFNTStyleMetadata
        /// Unmerged source records; localized and legacy names keep their identities.
        public let sfntNames: [SFNTNameRecord]
        /// Source table tags, independent of synthesized parser metadata.
        public let sfntTableTags: Set<UInt32>
    }

    /// Inspects a collection face without creating a rendering Font.
    /// Returns nil if the source, collection index, or required variation data is invalid.
    public static func metadata(path: String, faceIndex: Int = 0) -> FaceMetadata? {
        guard !path.utf8.contains(0) else { return nil }
        return withResourceFace(faceIndex: faceIndex) { library, index, face in
            FT_New_Face(library, path, index, &face)
        } read: { face, library in
            readMetadata(face: face, library: library)
        }
    }

    /// Copies selection and feature metadata from one temporary, unsized face.
    package static func resourceMetadata(path: String, faceIndex: Int = 0)
        -> (metadata: FaceMetadata, features: FontFeatures)? {
        guard !path.utf8.contains(0) else { return nil }
        return withResourceFace(faceIndex: faceIndex) { library, index, face in
            FT_New_Face(library, path, index, &face)
        } read: { face, library in
            guard let featureFace = hb_ft_face_create(face, nil) else { return nil }
            defer { hb_face_destroy(featureFace) }
            let features = FontFeatures(face: featureFace)
            guard let metadata = readMetadata(face: face, library: library) else { return nil }
            return (metadata, features)
        }
    }

    /// Inspects the loaded source without reopening its path or changing this face.
    /// The result describes the source collection face; current variation
    /// coordinates and other mutable rendering settings remain separate.
    public final func metadata() -> FaceMetadata? {
        let data = state.withLock { state -> (any FixedAddressStorageData)? in
            guard let stream = state.face.pointee.stream else { return nil }
            return source.data(from: stream)
        }
        guard let data else { return nil }
        return Self.metadata(data: data, faceIndex: faceIndex & 0xffff)
    }

    /// Borrows contiguous bytes when available and copies all returned metadata.
    public static func metadata(data: any DataProtocol, faceIndex: Int = 0) -> FaceMetadata? {
        guard !data.isEmpty, let count = FT_Long(exactly: data.count) else {
            return nil
        }
        func inspect(_ address: UnsafeRawPointer?) -> FaceMetadata? {
            withResourceFace(faceIndex: faceIndex) { library, index, face in
                FT_New_Memory_Face(library, address, count, index, &face)
            } read: { face, library in
                readMetadata(face: face, library: library)
            }
        }
        if let result = data.withContiguousStorageIfAvailable({ bytes in
            inspect(bytes.baseAddress)
        }) {
            return result
        }
        let storage = data.makeFixedAddressStorage()
        // FreeType borrows these bytes until the inspection face is destroyed.
        return withExtendedLifetime(storage) { inspect(storage.address) }
    }

    private static func withResourceFace<Result>(
        faceIndex: Int,
        open: (FT_Library, FT_Long, inout FT_Face?) -> FT_Error,
        read: (FT_Face, FT_Library) -> Result?
    ) -> Result? {
        // Higher bits select named instances in FreeType, not collection faces.
        guard (0...0xffff).contains(faceIndex) else { return nil }
        let library = sharedFTLibrary()
        guard let handle = library.library else { return nil }
        var face: FT_Face?
        let error = library.withFaceLifecycleLock {
            open(handle, FT_Long(faceIndex), &face)
        }
        guard error == 0, let face else { return nil }
        defer {
            _ = library.withFaceLifecycleLock { FT_Done_Face(face) }
        }
        guard face.pointee.face_index == FT_Long(faceIndex),
              face.pointee.num_faces > FT_Long(faceIndex) else {
            return nil
        }
        return read(face, handle)
    }

    private static func readSFNTStyle(face: FT_Face) -> SFNTStyleMetadata {
        let os2 = FT_Get_Sfnt_Table(face, FT_SFNT_OS2)?
            .assumingMemoryBound(to: TT_OS2.self).pointee
        let head = FT_Get_Sfnt_Table(face, FT_SFNT_HEAD)?
            .assumingMemoryBound(to: TT_Header.self).pointee
        var post: TT_Postscript?
        var postLength: FT_ULong = 0
        // The parsed post struct can exist even if the source table is missing.
        if FT_Load_Sfnt_Table(face, 0x706f_7374, 0, nil, &postLength) == 0,
           postLength >= 32 {
            post = FT_Get_Sfnt_Table(face, FT_SFNT_POST)?
                .assumingMemoryBound(to: TT_Postscript.self).pointee
        }
        return SFNTStyleMetadata(
            weightClass: os2?.usWeightClass,
            widthClass: os2?.usWidthClass,
            familyClass: os2?.sFamilyClass,
            selection: os2?.fsSelection,
            macStyle: head?.Mac_Style,
            italicAngle: post.map { ft16d16ToFloat($0.italicAngle) },
            fixedPitch: post.flatMap { UInt32(exactly: $0.isFixedPitch) }
        )
    }

    private static func readMetadata(face: FT_Face, library: FT_Library) -> FaceMetadata? {
        // Instance selection can change names and metrics, so copy the base first.
        let faceIndex = Int(face.pointee.face_index)
        let numFaces = Int(face.pointee.num_faces)
        let familyName = face.pointee.family_name.map { String(cString: $0) }
        let styleName = face.pointee.style_name.map { String(cString: $0) }
        let postScriptName = FT_Get_Postscript_Name(face).map { String(cString: $0) }
        var sfntNames: [SFNTNameRecord] = []
        for index in 0..<FT_Get_Sfnt_Name_Count(face) {
            var record = FT_SfntName()
            guard FT_Get_Sfnt_Name(face, index, &record) == 0 else { continue }
            let bytes: Data
            if record.string_len == 0 {
                bytes = Data()
            } else {
                guard let pointer = record.string else { continue }
                bytes = Data(bytes: pointer, count: Int(record.string_len))
            }
            sfntNames.append(SFNTNameRecord(
                platformID: record.platform_id,
                encodingID: record.encoding_id,
                languageID: record.language_id,
                nameID: record.name_id,
                data: bytes
            ))
        }
        let sfntStyle = readSFNTStyle(face: face)
        var tableTags: Set<UInt32> = []
        var tableCount: FT_ULong = 0
        if FT_Sfnt_Table_Info(face, 0, nil, &tableCount) == 0 {
            for index in 0..<tableCount {
                var tag: FT_ULong = 0
                var length: FT_ULong = 0
                if FT_Sfnt_Table_Info(face, FT_UInt(index), &tag, &length) == 0,
                   let value = UInt32(exactly: tag) {
                    tableTags.insert(value)
                }
            }
        }

        var axes: [VariationAxis] = []
        var instances: [VariationInstance] = []
        var defaultInstanceIndex: Int?
        if face.pointee.face_flags & FT_FACE_FLAG_MULTIPLE_MASTERS != 0 {
            var descriptor: UnsafeMutablePointer<FT_MM_Var>?
            guard FT_Get_MM_Var(face, &descriptor) == 0, let descriptor else {
                return nil
            }
            defer { _ = FT_Done_MM_Var(library, descriptor) }
            let value = descriptor.pointee
            guard value.num_axis > 0, let rawAxes = value.axis,
                  value.num_namedstyles <= 0x7fff else {
                return nil
            }
            axes.reserveCapacity(Int(value.num_axis))
            var tags = Set<UInt32>()
            for index in 0..<Int(value.num_axis) {
                let axis = rawAxes[index]
                guard let tag = UInt32(exactly: axis.tag),
                      tags.insert(tag).inserted,
                      axis.minimum <= axis.def, axis.def <= axis.maximum else {
                    return nil
                }
                axes.append(VariationAxis(
                    tag: tag,
                    minimumValue: ft16d16ToFloat(axis.minimum),
                    defaultValue: ft16d16ToFloat(axis.def),
                    maximumValue: ft16d16ToFloat(axis.maximum)
                ))
            }
            var defaultIndex: FT_UInt = 0
            guard FT_Get_Default_Named_Instance(face, &defaultIndex) == 0,
                  defaultIndex <= value.num_namedstyles else {
                return nil
            }
            defaultInstanceIndex = defaultIndex == 0 ? nil : Int(defaultIndex)
            if value.num_namedstyles > 0 {
                guard let styles = value.namedstyle else { return nil }
                instances.reserveCapacity(Int(value.num_namedstyles))
                for index in 0..<Int(value.num_namedstyles) {
                    guard let rawCoordinates = styles[index].coords else { return nil }
                    var coordinates: [CGFloat] = []
                    coordinates.reserveCapacity(axes.count)
                    for axisIndex in axes.indices {
                        let coordinate = rawCoordinates[axisIndex]
                        let axis = rawAxes[axisIndex]
                        guard coordinate >= axis.minimum, coordinate <= axis.maximum else {
                            return nil
                        }
                        coordinates.append(ft16d16ToFloat(coordinate))
                    }
                    guard FT_Set_Named_Instance(face, FT_UInt(index + 1)) == 0 else {
                        return nil
                    }
                    // Copy resolved names, including generated names when psid is absent.
                    instances.append(VariationInstance(
                        index: index + 1,
                        styleName: face.pointee.style_name.map { String(cString: $0) },
                        postScriptName: FT_Get_Postscript_Name(face).map { String(cString: $0) },
                        styleNameID: UInt16(exactly: styles[index].strid),
                        postScriptNameID: styles[index].psid == 0xffff
                            ? nil : UInt16(exactly: styles[index].psid),
                        coordinates: coordinates
                    ))
                }
            }
            if let defaultInstanceIndex {
                guard instances[defaultInstanceIndex - 1].coordinates == axes.map(\.defaultValue) else {
                    return nil
                }
            }
        }
        return FaceMetadata(
            faceIndex: faceIndex,
            numFaces: numFaces,
            familyName: familyName,
            styleName: styleName,
            postScriptName: postScriptName,
            variationAxes: axes,
            variationInstances: instances,
            defaultVariationInstanceIndex: defaultInstanceIndex,
            sfntStyle: sfntStyle,
            sfntNames: sfntNames,
            sfntTableTags: tableTags
        )
    }

    public enum ShapingDirection: Hashable, Sendable {
        case leftToRight
        case rightToLeft
        case topToBottom
        case bottomToTop
    }

    public struct ShapingFeature: Hashable, Sendable {
        public let tag: UInt32
        public let value: UInt32
        /// Unicode-scalar offsets in the shaped source. `nil` applies globally.
        public let range: Range<Int>?

        public init(
            tag: UInt32,
            value: UInt32 = 1,
            range: Range<Int>? = nil
        ) {
            self.tag = tag
            self.value = value
            self.range = range
        }

        public init?(
            tag: String,
            value: UInt32 = 1,
            range: Range<Int>? = nil
        ) {
            let bytes = Array(tag.utf8)
            guard bytes.count == 4, bytes.allSatisfy({ $0 < 0x80 }) else {
                return nil
            }
            self.init(
                tag: bytes.reduce(UInt32.zero) {
                    ($0 << 8) | UInt32($1)
                },
                value: value,
                range: range
            )
        }
    }

    public struct ShapedGlyph: Hashable, Sendable {
        public let index: UInt32
        /// Unicode-scalar index associated with this individual glyph.
        public let sourceIndex: Int
        /// Unicode-scalar range represented by this glyph's source cluster.
        public let sourceRange: Range<Int>
        /// Source interval shaped as one script run.
        package let scriptRunRange: Range<Int>
        public let advance: CGSize
        public let offset: CGPoint
        /// Internal table attachment or geometric placement has resolved this mark.
        package let hasResolvedMarkPosition: Bool

        package init(
            index: UInt32,
            sourceIndex: Int,
            sourceRange: Range<Int>,
            scriptRunRange: Range<Int>,
            advance: CGSize,
            offset: CGPoint,
            hasResolvedMarkPosition: Bool = false
        ) {
            self.index = index
            self.sourceIndex = sourceIndex
            self.sourceRange = sourceRange
            self.scriptRunRange = scriptRunRange
            self.advance = advance
            self.offset = offset
            self.hasResolvedMarkPosition = hasResolvedMarkPosition
        }
    }

    public struct ShapedText: Hashable, Sendable {
        public let glyphs: [ShapedGlyph]
        public let direction: ShapingDirection
    }

    public init?(path: String, faceIndex: Int = 0) {
        guard let faceIndex = FT_Long(exactly: faceIndex),
              faceIndex >= 0 else {
            return nil
        }

        let size26d6: FT_F26Dot6 = 10 * 64
        let dpi = Self.defaultDPI

        let library = sharedFTLibrary()
        var face: FT_Face? = nil
        let err: FT_Error = library.withFaceLifecycleLock {
            FT_New_Face(
                library.library,
                path,
                faceIndex,
                &face
            )
        }
        if err != 0 {
            return nil
        }
        guard let face else { return nil }
        if face.pointee.charmap == nil {
            if FT_Set_Charmap(face, face.pointee.charmaps[0]) != 0 {
                _ = library.withFaceLifecycleLock {
                    FT_Done_Face(face)
                }
                return nil
            }
        }
        if Self.setSize(face, size26d6: size26d6, dpi: dpi) != 0 {
            Log.warn("Failed to initialize font size. You should call Font.setPointSize() manually.")
        }
        guard let shapingFont = hb_ft_font_create(face, nil) else {
            _ = library.withFaceLifecycleLock {
                FT_Done_Face(face)
            }
            return nil
        }
        self.library = library
        self.fontData = nil
        self.source = Source()
        self.familyName = face.pointee.family_name.map { String(cString: $0) } ?? ""
        self.styleName = face.pointee.style_name.map { String(cString: $0) } ?? ""
        self.faceIndex = Int(face.pointee.face_index)
        self.numFaces = Int(face.pointee.num_faces)
        self.numGlyphs = Int(face.pointee.num_glyphs)
        self.state = Mutex(State(
            face: face,
            shapingFont: shapingFont,
            layoutFont: Self.makeLayoutFont(face: face, parent: shapingFont, pointSize: ft26d6ToFloat(size26d6)),
            hasColorPaint: hb_ot_color_has_paint(hb_font_get_face(shapingFont)) != 0,
            pointSize: ft26d6ToFloat(size26d6),
            size26d6: size26d6,
            dpi: dpi
        ))
        self.filePath = path
    }

    public convenience init?(data: any DataProtocol, faceIndex: Int = 0) {
        self.init(data: data, faceIndex: faceIndex, source: nil, filePath: "")
    }

    init?(data: any DataProtocol, faceIndex: Int, source: Source?, filePath: String) {
        if data.isEmpty { return nil }
        guard let faceIndex = FT_Long(exactly: faceIndex),
              faceIndex >= 0 else {
            return nil
        }

        let size26d6: FT_F26Dot6 = 10 * 64
        let dpi = Self.defaultDPI

        let data = data.makeFixedAddressStorage()
        self.fontData = data
        self.source = source ?? Source(data: data)

        let library = sharedFTLibrary()
        var face: FT_Face? = nil
        let err: FT_Error = library.withFaceLifecycleLock {
            FT_New_Memory_Face(
                library.library,
                data.address,
                FT_Long(data.count),
                faceIndex,
                &face
            )
        }
        if err != 0 {
            return nil
        }
        guard let face else { return nil }
        if face.pointee.charmap == nil {
            if FT_Set_Charmap(face, face.pointee.charmaps[0]) != 0 {
                _ = library.withFaceLifecycleLock {
                    FT_Done_Face(face)
                }
                return nil
            }
        }
        if Self.setSize(face, size26d6: size26d6, dpi: dpi) != 0 {
            Log.warn("Failed to initialize font size. You should call Font.setPointSize() manually.")
        }
        guard let shapingFont = hb_ft_font_create(face, nil) else {
            _ = library.withFaceLifecycleLock {
                FT_Done_Face(face)
            }
            return nil
        }
        self.library = library
        self.familyName = face.pointee.family_name.map { String(cString: $0) } ?? ""
        self.styleName = face.pointee.style_name.map { String(cString: $0) } ?? ""
        self.faceIndex = Int(face.pointee.face_index)
        self.numFaces = Int(face.pointee.num_faces)
        self.numGlyphs = Int(face.pointee.num_glyphs)
        self.state = Mutex(State(
            face: face,
            shapingFont: shapingFont,
            layoutFont: Self.makeLayoutFont(face: face, parent: shapingFont, pointSize: ft26d6ToFloat(size26d6)),
            hasColorPaint: hb_ot_color_has_paint(hb_font_get_face(shapingFont)) != 0,
            pointSize: ft26d6ToFloat(size26d6),
            size26d6: size26d6,
            dpi: dpi
        ))
        self.filePath = filePath
    }

    /// Creates an independently mutable face that preserves the current
    /// selection, point size, DPI, and rendering settings.
    public final func copy() -> Font? {
        copy(pointSizeOverride: nil)
    }

    /// Creates an independently mutable face that preserves the current
    /// selection, DPI, and rendering settings at the requested point size.
    /// Passing zero preserves the current point size. Returns nil when a nonzero
    /// point size is nonfinite or outside the supported range.
    public final func copy(pointSize requestedSize: CGFloat) -> Font? {
        copy(pointSizeOverride: requestedSize)
    }

    private func copy(pointSizeOverride requestedSize: CGFloat?) -> Font? {
        state.withLock { state in
            let size = requestedSize == 0 ? state.pointSize : requestedSize ?? state.pointSize
            guard size.isFinite, size >= 1 / 64, size <= maxPointSize,
                  let stream = state.face.pointee.stream,
                  let data = source.data(from: stream),
                  let copy = makeCopy(data: data) else { return nil }
            // Reapplying even identical coordinates changes a named instance
            // into an explicit variation and can change its reported name.
            if state.face.pointee.face_flags & FT_FACE_FLAG_VARIATION != 0 {
                let coordinates = variationCoordinates(face: state.face)
                guard !coordinates.isEmpty, copy.setVariationCoordinates(coordinates) else { return nil }
            }
            copy.setPointSize(size, dpi: state.dpi)
            guard copy.pointSize == size else { return nil }
            copy.isBitmapPreferred = state.isBitmapPreferred
            copy.isKerningEnabled = state.isKerningEnabled
            copy.isColorEnabled = state.isColorEnabled
            return copy
        }
    }

    // Called with this face locked, before the new face can be observed by a caller.
    func makeCopy(data: any FixedAddressStorageData) -> Font? {
        Font(data: data, faceIndex: faceIndex, source: source, filePath: filePath)
    }

    deinit {
        self.state.withLock {
            let face = $0.face
            // The HarfBuzz font borrows `face`, so it must be destroyed first.
            if let rasterizer = $0.colorRasterizer {
                hb_raster_paint_destroy(rasterizer)
            }
            if let layoutFont = $0.layoutFont {
                hb_font_destroy(layoutFont)
            }
            hb_font_destroy($0.shapingFont)
            _ = self.library.withFaceLifecycleLock {
                FT_Done_Face(face)
            }
        }
    }

    internal func clearCacheLocked() {
    }

    public func clearCache() {
        self.withLockedFace { _ in
            self.clearCacheLocked()
        }
    }

    /// point, embolden is point-size, outline is pixel-size.
    /// 1/64 <= pointSize <= 0x7fffffff / 64
    public func setPointSize(_ pointSize: CGFloat, dpi: DPI) {
        self.updateSize(pointSize: pointSize, dpi: dpi)
    }

    private static func makeLayoutFont(face: FT_Face, parent: OpaquePointer, pointSize: CGFloat) -> OpaquePointer? {
        guard FT_IS_SCALABLE(face),
              face.pointee.face_flags & FT_FACE_FLAG_SFNT != 0,
              face.pointee.units_per_EM > 0,
              let font = hb_font_create_sub_font(parent) else { return nil }
        // Shape scalable OpenType faces in fractional design units. Scaling
        // positions after shaping keeps raster-size quantization out of layout.
        hb_ot_font_set_funcs(font)
        let units = Int32(face.pointee.units_per_EM) * 64
        hb_font_set_scale(font, units, units)
        hb_font_set_ptem(font, Float(pointSize))
        return font
    }

    private static func updateLayoutFont(_ state: State) {
        guard let font = state.layoutFont else { return }
        var count: UInt32 = 0
        let coordinates = hb_font_get_var_coords_normalized(state.shapingFont, &count)
        hb_font_set_var_coords_normalized(font, coordinates, count)
        hb_font_set_ptem(font, Float(state.pointSize))
    }

    private func updateSize(pointSize: CGFloat?, dpi: DPI?) {
        if pointSize == nil && dpi == nil { return }

        var logicalSize: CGFloat?
        var charSize: FT_F26Dot6?
        if let pointSize {
            // Keep the logical request within the rasterizer's supported range,
            // and quantize only the size passed to FreeType.
            let dp: Double = clamp(Double(pointSize) * 64.0, min:1.0, max:Double(0x7fffffff))
            logicalSize = CGFloat(dp / 64)
            charSize = FT_F26Dot6(floor(dp))
        }

        self.state.withLock {
            let logicalSize = logicalSize ?? $0.pointSize
            let charSize: FT_F26Dot6 = charSize ?? $0.size26d6
            let resX, resY: UInt32
            if let dpi {
                resX = max(dpi.x, 1)
                resY = max(dpi.y, 1)
            } else {
                resX = $0.dpi.x
                resY = $0.dpi.y
            }

            if logicalSize != $0.pointSize || charSize != $0.size26d6 || resX != $0.dpi.x || resY != $0.dpi.y {
                let face = $0.face
                if Self.setSize(face, size26d6: charSize, dpi: (resX, resY)) != 0 {
                    Log.err("FT_Set_Char_Size failed! (size:\(String(format:"0x%x", charSize)), dpi:\(resX)x\(resY))")
                    return
                }
                $0.pointSize = logicalSize
                $0.size26d6 = charSize
                $0.dpi = (resX, resY)
                hb_ft_font_changed($0.shapingFont)
                Self.updateLayoutFont($0)
                assert(self.numGlyphs == Int(face.pointee.num_glyphs))
                self.clearCacheLocked()
            }
        }
    }

    private static func setSize(_ face: FT_Face, size26d6: FT_F26Dot6, dpi: DPI) -> FT_Error {
        if FT_IS_SCALABLE(face) || face.pointee.num_fixed_sizes == 0 {
            return FT_Set_Char_Size(face, 0, size26d6, dpi.x, dpi.y)
        }
        let requested = Double(size26d6) * Double(dpi.y) / 72
        let sizes = face.pointee.available_sizes!
        let index = (0..<Int(face.pointee.num_fixed_sizes)).min {
            let lhs = abs(Double(sizes[$0].y_ppem) - requested)
            let rhs = abs(Double(sizes[$1].y_ppem) - requested)
            return lhs == rhs ? sizes[$0].y_ppem > sizes[$1].y_ppem : lhs < rhs
        }!
        return FT_Select_Size(face, FT_Int(index))
    }

    public var variationAxes: [VariationAxis] {
        self.state.withLock { state in
            var descriptor: UnsafeMutablePointer<FT_MM_Var>?
            guard FT_Get_MM_Var(state.face, &descriptor) == 0,
                  let descriptor else {
                return []
            }
            defer {
                _ = FT_Done_MM_Var(library.library, descriptor)
            }

            let value = descriptor.pointee
            guard value.num_axis > 0, let axes = value.axis else {
                return []
            }
            return (0..<Int(value.num_axis)).compactMap { index in
                let axis = axes[index]
                guard let tag = UInt32(exactly: axis.tag) else {
                    return nil
                }
                return VariationAxis(
                    tag: tag,
                    minimumValue: ft16d16ToFloat(axis.minimum),
                    defaultValue: ft16d16ToFloat(axis.def),
                    maximumValue: ft16d16ToFloat(axis.maximum)
                )
            }
        }
    }

    public var variationCoordinates: [UInt32: CGFloat] {
        state.withLock { state in variationCoordinates(face: state.face) }
    }

    private func variationCoordinates(face: FT_Face) -> [UInt32: CGFloat] {
        var descriptor: UnsafeMutablePointer<FT_MM_Var>?
        guard FT_Get_MM_Var(face, &descriptor) == 0,
              let descriptor else {
            return [:]
        }
        defer {
            _ = FT_Done_MM_Var(library.library, descriptor)
        }

        let value = descriptor.pointee
        guard value.num_axis > 0, let axes = value.axis else {
            return [:]
        }
        var coordinates = [FT_Fixed](
            repeating: 0,
            count: Int(value.num_axis)
        )
        let result = coordinates.withUnsafeMutableBufferPointer {
            FT_Get_Var_Design_Coordinates(
                face,
                value.num_axis,
                $0.baseAddress
            )
        }
        guard result == 0 else { return [:] }

        var resolved: [UInt32: CGFloat] = [:]
        for index in coordinates.indices {
            if let tag = UInt32(exactly: axes[index].tag) {
                resolved[tag] = ft16d16ToFloat(coordinates[index])
            }
        }
        return resolved
    }

    /// Active style inputs copied atomically with the current size.
    public struct FaceTraits: Hashable, Sendable {
        /// Requested vertical size in pixels, independent of bitmap strike selection.
        public let pixelSize: CGFloat
        public let variationCoordinates: [UInt32: CGFloat]
        public let sfntStyle: SFNTStyleMetadata
        public let isItalic: Bool
    }

    public var faceTraits: FaceTraits {
        state.withLock { state in
            let face = state.face
            return FaceTraits(
                pixelSize: state.pointSize * CGFloat(state.dpi.y) / 72,
                variationCoordinates: variationCoordinates(face: face),
                sfntStyle: Self.readSFNTStyle(face: face),
                isItalic: face.pointee.style_flags & FT_Long(FT_STYLE_FLAG_ITALIC) != 0
            )
        }
    }

    @discardableResult
    public func setVariationCoordinates(
        _ requested: [UInt32: CGFloat]
    ) -> Bool {
        guard requested.values.allSatisfy(\.isFinite) else {
            return false
        }
        return self.state.withLock { state in
            if requested.isEmpty {
                guard FT_Set_Var_Design_Coordinates(
                    state.face,
                    0,
                    nil
                ) == 0 else {
                    return false
                }
                guard FT_Set_Char_Size(
                    state.face,
                    0,
                    state.size26d6,
                    state.dpi.x,
                    state.dpi.y
                ) == 0 else {
                    return false
                }
                hb_ft_font_changed(state.shapingFont)
                Self.updateLayoutFont(state)
                self.clearCacheLocked()
                return true
            }

            var descriptor: UnsafeMutablePointer<FT_MM_Var>?
            guard FT_Get_MM_Var(state.face, &descriptor) == 0,
                  let descriptor else {
                return false
            }
            defer {
                _ = FT_Done_MM_Var(library.library, descriptor)
            }

            let value = descriptor.pointee
            guard value.num_axis > 0, let axes = value.axis else {
                return false
            }
            var coordinates = [FT_Fixed](
                repeating: 0,
                count: Int(value.num_axis)
            )
            var remainingTags = Set(requested.keys)
            for index in coordinates.indices {
                let axis = axes[index]
                coordinates[index] = axis.def
                guard let tag = UInt32(exactly: axis.tag),
                      let coordinate = requested[tag] else {
                    continue
                }
                let minimum = ft16d16ToFloat(axis.minimum)
                let maximum = ft16d16ToFloat(axis.maximum)
                guard coordinate >= minimum, coordinate <= maximum else {
                    return false
                }
                coordinates[index] = ft16d16(coordinate)
                remainingTags.remove(tag)
            }
            guard remainingTags.isEmpty else { return false }

            let result = coordinates.withUnsafeMutableBufferPointer {
                FT_Set_Var_Design_Coordinates(
                    state.face,
                    value.num_axis,
                    $0.baseAddress
                )
            }
            guard result == 0 else { return false }
            guard FT_Set_Char_Size(
                state.face,
                0,
                state.size26d6,
                state.dpi.x,
                state.dpi.y
            ) == 0 else {
                return false
            }
            hb_ft_font_changed(state.shapingFont)
            Self.updateLayoutFont(state)
            self.clearCacheLocked()
            return true
        }
    }

    /// Shapes one directional run with script-specific glyph selection and source clusters.
    /// Feature ranges and source clusters use Unicode-scalar offsets.
    public func shape(
        _ text: String,
        direction: ShapingDirection? = nil,
        language: String? = nil,
        features requestedFeatures: [ShapingFeature] = []
    ) -> ShapedText? {
        shape(text, direction: direction, language: language, features: requestedFeatures,
              optionalLigatureBoundaries: [])
    }

    /// Source-scalar boundaries independently constrain optional substitution
    /// and positioning inputs while canonical characters and required
    /// substitutions keep context. Line owners retain deleted slots until their
    /// own public run projection.
    package func shape(
        _ text: String,
        direction: ShapingDirection? = nil,
        language: String? = nil,
        features requestedFeatures: [ShapingFeature] = [],
        optionalLigatureBoundaries: [Int],
        positioningRunBoundaries: [Int] = [],
        sourceRunBoundaries: [Int] = [],
        retainsDeletedGlyphs: Bool = false,
        allowsLeadingMarkBase: Bool = true,
        characterInput: CharacterComposer.Input? = nil
    ) -> ShapedText? {
        let scalars = text.unicodeScalars.map(\.value)
        guard characterInput == nil || characterInput!.scalars.count == scalars.count else { return nil }
        guard Int32(exactly: scalars.count) != nil else {
            return nil
        }
        func boundariesAreValid(_ boundaries: [Int]) -> Bool {
            boundaries.allSatisfy { $0 > 0 && $0 < scalars.count } &&
                zip(boundaries, boundaries.dropFirst()).allSatisfy { $0 < $1 }
        }
        guard boundariesAreValid(optionalLigatureBoundaries),
              boundariesAreValid(positioningRunBoundaries),
              boundariesAreValid(sourceRunBoundaries) else { return nil }
        let optionalBoundaries = optionalLigatureBoundaries.map(UInt32.init)
        let positioningBoundaries = positioningRunBoundaries.map(UInt32.init)
        if scalars.isEmpty {
            return ShapedText(
                glyphs: [],
                direction: direction ?? .leftToRight
            )
        }

        // Glyph identity and an indivisible source cluster serve different
        // consumers. Keep scalar indices through shaping while retaining
        // complete graphemes and ligature intervals for line breaking.
        var graphemeRanges: [Range<Int>] = []
        graphemeRanges.reserveCapacity(scalars.count)
        for character in text {
            let start = graphemeRanges.count
            let length = character.unicodeScalars.count
            graphemeRanges.append(contentsOf: repeatElement(start..<(start + length), count: length))
        }
        let scriptRuns = ScriptRun.ranges(in: scalars)
        let resolvedDirection = direction ?? ShapingDirection(harfbuzzValue:
            hb_script_get_horizontal_direction(hb_script_from_iso15924_tag(scriptRuns[0].iso15924Tag))) ?? .leftToRight
        let orderedRuns = resolvedDirection == .rightToLeft || resolvedDirection == .bottomToTop
            ? Array(scriptRuns.reversed()) : scriptRuns
        let hasComposableMarks = resolvedDirection == .leftToRight &&
            scalars.contains(where: GlyphComposer.accepts)
        let uncombinedRanges: [Range<Int>]
        if hasComposableMarks {
            guard let ranges = GlyphComposer.uncombinedRanges(in: text) else {
                return nil
            }
            uncombinedRanges = ranges
        } else {
            uncombinedRanges = []
        }

        return self.state.withLock { state -> ShapedText? in
            guard let buffer = hb_buffer_create() else { return nil }
            defer { hb_buffer_destroy(buffer) }

            var baseFeatures: [hb_feature_t] = []
            baseFeatures.reserveCapacity(
                requestedFeatures.count + (state.isKerningEnabled ? 0 : 1)
            )
            for requested in requestedFeatures {
                let start: UInt32
                let end: UInt32
                if let range = requested.range {
                    guard range.lowerBound >= 0,
                          range.upperBound <= scalars.count,
                          let lower = UInt32(exactly: range.lowerBound),
                          let upper = UInt32(exactly: range.upperBound) else {
                        return nil
                    }
                    start = lower
                    end = upper
                } else {
                    start = 0
                    end = UInt32.max
                }
                baseFeatures.append(hb_feature_t(
                    tag: requested.tag,
                    value: requested.value,
                    start: start,
                    end: end
                ))
            }
            if !state.isKerningEnabled {
                let kerningTag: UInt32 = 0x6b65_726e // kern
                baseFeatures.removeAll { $0.tag == kerningTag }
                baseFeatures.append(hb_feature_t(
                    tag: kerningTag,
                    value: 0,
                    start: 0,
                    end: UInt32.max
                ))
            }

            let positionScale: CGSize
            let positionUnits: CGFloat
            if state.layoutFont != nil {
                positionUnits = CGFloat(state.face.pointee.units_per_EM) * 64
                positionScale = CGSize(
                    width: state.pointSize * CGFloat(state.dpi.x) / 72,
                    height: state.pointSize * CGFloat(state.dpi.y) / 72
                )
            } else {
                // Fixed strikes and non-OpenType faces retain their native
                // FreeType position units and existing bitmap scaling.
                positionUnits = 64
                positionScale = CGSize(width: 1, height: 1)
            }
            var glyphs: [ShapedGlyph] = []
            glyphs.reserveCapacity(scalars.count)
            let compositionMetrics = hasComposableMarks ? state.layoutFont.flatMap {
                    FontMetricsReader.compositionMetrics(face: state.face, library: library.library, font: $0)
                }?.scaled(by: positionScale.height / CGFloat(state.face.pointee.units_per_EM)) : nil
            for run in orderedRuns {
                hb_buffer_reset(buffer)
                let isLastResort = FT_Get_Postscript_Name(state.face).map {
                    String(cString: $0) == "LastResort"
                } ?? false
                var encodings = resolvedDirection == .leftToRight && state.layoutFont != nil
                    ? CharacterEncoder.encodings(scalars, run: run,
                        font: state.layoutFont!, isLastResort: isLastResort) : nil
                let hasPreparedCharacters = characterInput?.ranges.contains {
                    $0.lowerBound <= run.range.lowerBound && $0.upperBound >= run.range.upperBound
                } == true
                let preservesCharacters = resolvedDirection == .leftToRight && state.layoutFont != nil &&
                    (hasPreparedCharacters || CharacterComposer.accepts(run, scalars: scalars))
                let prepared = hasPreparedCharacters ? characterInput : (preservesCharacters ?
                    CharacterComposer.prepare(scalars,
                        range: run.range, graphemes: graphemeRanges, isLastResort: isLastResort,
                        hasGlyph: { scalar in
                            var glyph: UInt32 = 0
                            return hb_font_get_nominal_glyph(state.layoutFont!, scalar, &glyph) != 0 && glyph != 0
                        }) : nil)
                if let prepared {
                    if encodings == nil {
                        encodings = Array(repeating: HB_GLYPH_ENCODING_DEFAULT, count: scalars.count)
                    }
                    for source in prepared.deletedSources {
                        encodings![source] = HB_GLYPH_ENCODING_INVISIBLE
                    }
                }
                let input = prepared?.scalars ?? scalars
                input.withUnsafeBufferPointer { pointer in
                    // Keep the complete source as context while shaping only
                    // this script interval. Cluster offsets remain absolute.
                    hb_buffer_add_utf32(buffer, pointer.baseAddress, Int32(input.count),
                                        UInt32(run.range.lowerBound), Int32(run.range.count))
                }
                hb_buffer_set_cluster_level(buffer, HB_BUFFER_CLUSTER_LEVEL_CHARACTERS)
                hb_buffer_set_script(buffer, hb_script_from_iso15924_tag(run.iso15924Tag))
                hb_buffer_set_direction(buffer, resolvedDirection.harfbuzzValue)
                if let language, !language.isEmpty {
                    language.withCString { pointer in
                        hb_buffer_set_language(buffer, hb_language_from_string(pointer, -1))
                    }
                }
                hb_buffer_guess_segment_properties(buffer)

                var features = baseFeatures
                if run.script == 18 {
                    // Hangul contextual substitutions are disabled by default.
                    // Explicit low-level feature requests retain precedence.
                    features.insert(hb_feature_t(tag: 0x6361_6c74, value: 0,
                                                 start: 0, end: UInt32.max), at: 0)
                }
                guard let featureCount = UInt32(exactly: features.count) else {
                    return nil
                }

                var attachments: [Range<Int>] = []
                let composesMarks = compositionMetrics != nil &&
                    scalars[run.range].contains(where: GlyphComposer.accepts)
                features.withUnsafeBufferPointer { featurePointer in
                    if composesMarks || preservesCharacters || encodings != nil ||
                        !optionalBoundaries.isEmpty || !positioningBoundaries.isEmpty {
                        (encodings ?? []).withUnsafeBufferPointer { encodingPointer in
                            optionalBoundaries.withUnsafeBufferPointer { optionalBoundaryPointer in
                                positioningBoundaries.withUnsafeBufferPointer { positioningBoundaryPointer in
                                    withUnsafeMutablePointer(to: &attachments) { context in
                                        HBShapeWithGlyphAttachments(state.layoutFont ?? state.shapingFont,
                                            buffer, featurePointer.baseAddress, featureCount,
                                            preservesCharacters ? 1 : 0, encodingPointer.baseAddress,
                                            UInt32(encodingPointer.count), optionalBoundaryPointer.baseAddress,
                                            UInt32(optionalBoundaryPointer.count),
                                            positioningBoundaryPointer.baseAddress,
                                            UInt32(positioningBoundaryPointer.count), { glyph, parent, data in
                                                let lower = Int(min(glyph, parent)), upper = Int(max(glyph, parent)) + 1
                                                data!.assumingMemoryBound(to: [Range<Int>].self).pointee.append(lower..<upper)
                                            }, context)
                                    }
                                }
                            }
                        }
                    } else {
                        hb_shape(state.layoutFont ?? state.shapingFont, buffer,
                                 featurePointer.baseAddress, featureCount)
                    }
                }

                var infoCount: UInt32 = 0
                var positionCount: UInt32 = 0
                guard let infos = hb_buffer_get_glyph_infos(buffer, &infoCount),
                      let positions = hb_buffer_get_glyph_positions(
                        buffer,
                        &positionCount
                      ),
                      infoCount == positionCount else {
                    return nil
                }

                guard let count = Int(exactly: infoCount) else { return nil }
                // Internal deleted slots remain present throughout GPOS. Public
                // glyphs retain only the initial placeholder, when one is needed
                // to represent the beginning of the complete source interval.
                let published = (0..<count).filter {
                    encodings == nil || infos[$0].codepoint != 65535 ||
                        ($0 == 0 && infos[$0].cluster == 0)
                }
                if published.count != count {
                    let publishedIndices = Dictionary(uniqueKeysWithValues:
                        published.enumerated().map { ($0.element, $0.offset) })
                    attachments = attachments.compactMap { range in
                        let members = range.compactMap { publishedIndices[$0] }
                        guard let first = members.first, let last = members.last else { return nil }
                        return first..<(last + 1)
                    }
                }
                var glyphClusters: [Int] = []
                glyphClusters.reserveCapacity(published.count)
                var runGlyphs: [ShapedGlyph] = []
                runGlyphs.reserveCapacity(published.count)
                for index in published {
                    guard let cluster = Int(exactly: infos[index].cluster) else {
                        return nil
                    }
                    glyphClusters.append(cluster)
                }
                let clusterStarts = Set(glyphClusters).sorted()
                guard clusterStarts.allSatisfy({ run.range.contains($0) }) else {
                    return nil
                }
                var clusterEnds: [Int: Int] = [:]
                clusterEnds.reserveCapacity(clusterStarts.count)
                for (index, start) in clusterStarts.enumerated() {
                    clusterEnds[start] = index + 1 < clusterStarts.count
                        ? clusterStarts[index + 1]
                        : run.range.upperBound
                }

                for (publishedIndex, index) in published.enumerated() {
                    let info = infos[index]
                    let position = positions[index]
                    let clusterStart = glyphClusters[publishedIndex]
                    guard let clusterEnd = clusterEnds[clusterStart] else {
                        return nil
                    }
                    runGlyphs.append(ShapedGlyph(
                        index: info.codepoint,
                        sourceIndex: clusterStart,
                        sourceRange: graphemeRanges[clusterStart].lowerBound..<graphemeRanges[clusterEnd - 1].upperBound,
                        scriptRunRange: run.range,
                        advance: CGSize(
                            width: (CGFloat(position.x_advance) / positionUnits) * positionScale.width,
                            height: (CGFloat(position.y_advance) / positionUnits) * positionScale.height
                        ),
                        offset: CGPoint(
                            x: (CGFloat(position.x_offset) / positionUnits) * positionScale.width,
                            y: (CGFloat(position.y_offset) / positionUnits) * positionScale.height
                        ),
                        hasResolvedMarkPosition: attachments.contains { $0.contains(publishedIndex) }
                    ))
                }
                if composesMarks, let font = state.layoutFont, let metrics = compositionMetrics {
                    // The cursor contributes the first marked source interval
                    // in this shaping run to default-ignorable base admission.
                    let uncombinedRange = uncombinedRanges.first { range in
                        range.lowerBound >= run.range.lowerBound &&
                            range.upperBound <= run.range.upperBound &&
                            scalars[range].contains(where: GlyphComposer.isMark)
                    }
                    GlyphComposer.compose(&runGlyphs, scalars: scalars, font: font,
                        metrics: metrics, units: positionUnits, scale: positionScale,
                        attachments: attachments, uncombinedRange: uncombinedRange,
                        allowsLeadingMarkBase: allowsLeadingMarkBase)
                }
                let rawGlyphStart = glyphs.count
                if retainsDeletedGlyphs, published.count != count {
                    // Geometric composition uses its existing visible-glyph
                    // intervals. Publish that geometry alongside the original
                    // shaping buffer's deleted slots.
                    var nextPublished = 0
                    for index in 0..<count {
                        if nextPublished < published.count, published[nextPublished] == index {
                            glyphs.append(runGlyphs[nextPublished])
                            nextPublished += 1
                        } else {
                            let source = Int(infos[index].cluster)
                            guard run.range.contains(source) else { return nil }
                            glyphs.append(ShapedGlyph(index: infos[index].codepoint,
                                sourceIndex: source, sourceRange: graphemeRanges[source],
                                scriptRunRange: run.range,
                                advance: CGSize(
                                    width: (CGFloat(positions[index].x_advance) / positionUnits) * positionScale.width,
                                    height: (CGFloat(positions[index].y_advance) / positionUnits) * positionScale.height),
                                offset: CGPoint(
                                    x: (CGFloat(positions[index].x_offset) / positionUnits) * positionScale.width,
                                    y: (CGFloat(positions[index].y_offset) / positionUnits) * positionScale.height)))
                        }
                    }
                } else {
                    glyphs.append(contentsOf: runGlyphs)
                }
                if retainsDeletedGlyphs, !sourceRunBoundaries.isEmpty {
                    // Required substitutions can consume every glyph owned by
                    // one original attributed run. Keep one zero-width slot at
                    // that shaping owner while leaving same-run ligatures
                    // compact. Optional lookup ranges remain a separate input.
                    let boundaries = [run.range.lowerBound] + sourceRunBoundaries.filter {
                        $0 > run.range.lowerBound && $0 < run.range.upperBound
                    } + [run.range.upperBound]
                    for (lower, upper) in zip(boundaries, boundaries.dropFirst()) {
                        let sourceRange = lower..<upper
                        guard !glyphs[rawGlyphStart...].contains(where: {
                            sourceRange.contains($0.sourceIndex)
                        }) else { continue }
                        let backwards = resolvedDirection == .rightToLeft ||
                            resolvedDirection == .bottomToTop
                        let insertion = glyphs[rawGlyphStart...].firstIndex(where: {
                            backwards ? $0.sourceIndex < lower : $0.sourceIndex > lower
                        }) ?? glyphs.endIndex
                        glyphs.insert(ShapedGlyph(index: 65535,
                            sourceIndex: lower, sourceRange: graphemeRanges[lower],
                            scriptRunRange: run.range,
                            advance: .zero, offset: .zero), at: insertion)
                    }
                }
            }
            return ShapedText(glyphs: glyphs, direction: resolvedDirection)
        }
    }

    /// calculate kern advance between characters.
    public func kernAdvance(left: UnicodeScalar, right: UnicodeScalar) -> CGPoint {
        var point: CGPoint = .zero
        self.state.withLock {
            let face = $0.face
            if FT_HAS_KERNING(face) {
                let index1 = FT_Get_Char_Index(face, FT_ULong(left.value))
                let index2 = FT_Get_Char_Index(face, FT_ULong(right.value))
                if index1 != 0 && index2 != 0 {
                    var advance = FT_Vector()
                    if FT_Get_Kerning(face, index1, index2, FT_UInt(FT_KERNING_DEFAULT.rawValue), &advance) == 0 {
                        point.x = CGFloat(advance.x) / 64.0
                        point.y = CGFloat(advance.y) / 64.0
                    }
                }
            }
        }
        return point
    }

    /// text pixel-width from baseline. not includes outline.
    public func lineWidth(of text: String,
                          embolden: CGFloat = 0) -> CGFloat {
        var length: CGFloat = 0.0
        if self.isKerningEnabled {
            var c1 = UnicodeScalar(UInt8(0))
            for c2 in text.unicodeScalars {
                if let metrics = self.glyphMetrics(for: c2,
                                                   embolden: embolden) {
                    length += metrics.advance.width
                    length += self.kernAdvance(left: c1, right: c2).x
                }
                c1 = c2
            }
        } else {
            text.unicodeScalars.forEach {
                if let metrics = self.glyphMetrics(for: $0,
                                                   embolden: embolden) {
                    length += metrics.advance.width
                }
            }
        }
        return length
    }

    private var metrics: FT_Size_Metrics {
        self.state.withLock {
            $0.face.pointee.size.pointee.metrics
        }
    }

    /// pixel-height of text. not includes outline.
    public func lineHeight() -> CGFloat {
        return ft26d6ToFloat(self.metrics.height)
    }

    /// text bounding box.
    public func bounds(of text: String) -> CGRect {
        CGRect(x: 0, y: 0, width: lineWidth(of: text), height: lineHeight())
    }

    /// The distance from the baseline to the highest or upper grid coordinate used to place an outline point.
    public var ascender: CGFloat {
        return ft26d6ToFloat(self.metrics.ascender)
    }

    /// The distance from the baseline to the lowest grid coordinate used to place an outline point.
    public var descender: CGFloat {
        return ft26d6ToFloat(self.metrics.descender)
    }

    public var maxAdvance: CGFloat  {
        return ft26d6ToFloat(self.metrics.max_advance)
    }

    public var height: CGFloat  {
        return ft26d6ToFloat(self.metrics.height)
    }

    /// font pixel-width (includes outline)
    public var glyphMaxWidth: CGFloat {
        return ft26d6ToFloat(self.metrics.max_advance)
    }

    /// font pixel-height (includes outline)
    public var glyphMaxHeight: CGFloat  {
        return ft26d6ToFloat(self.metrics.height)
    }

    public var xScale: CGFloat {
        return ft16d16ToFloat(self.metrics.x_scale)
    }

    public var yScale: CGFloat {
        return ft16d16ToFloat(self.metrics.y_scale)
    }

    public var xPixelsPerEM: Int {
        return Int(self.metrics.x_ppem)
    }

    public var yPixelsPerEM: Int {
        return Int(self.metrics.y_ppem)
    }

    public func hasGlyph(for c: UnicodeScalar) -> Bool {
        self.state.withLock {
            FT_Get_Char_Index($0.face, FT_ULong(c.value)) != 0
        }
    }

    func glyphIndex(for c: UnicodeScalar, using lockedFace: LockedFace) -> UInt32? {
        guard c.value != 0 else { return nil }
        let index = if lockedFace.pointer.pointee.charmap != nil {
            FT_Get_Char_Index(lockedFace.pointer, FT_ULong(c.value))
        } else {
            FT_UInt(c.value)
        }
        return UInt32(index)
    }

    private func _glyphMetrics(from face: FT_Face,
                               index: UInt32,
                               embolden: CGFloat = 0) -> GlyphMetrics {
        assert(face.pointee.glyph != nil)
        let metrics = face.pointee.glyph.pointee.metrics
        let strength = ft26d6ToFloat(ft26d6(embolden))
        let advance = CGSize(
            width: ft26d6ToFloat(metrics.horiAdvance) + strength,
            height: ft26d6ToFloat(metrics.vertAdvance) + strength)
        let bearing = CGPoint(
            x: ft26d6ToFloat(metrics.horiBearingX),
            y: ft26d6ToFloat(metrics.horiBearingY) + strength)
        let size = CGSize(
            width: ft26d6ToFloat(metrics.width) + strength,
            height: ft26d6ToFloat(metrics.height) + strength)

        let faceMetrics = face.pointee.size.pointee.metrics
        let ascender = ft26d6ToFloat(faceMetrics.ascender)
        let descender = ft26d6ToFloat(faceMetrics.descender)

        return GlyphMetrics(index: index,
                            advance: advance,
                            bearing: bearing,
                            size: size,
                            ascender: ascender,
                            descender: descender)
    }

    public func glyphMetrics(for c: UnicodeScalar,
                             embolden: CGFloat = 0) -> GlyphMetrics? {
        if c.value == 0 { return nil }
        return self.state.withLock {
            let face = $0.face
            let index = if face.pointee.charmap != nil {
                FT_Get_Char_Index(face, FT_ULong(c.value))
            } else {
                FT_UInt(c.value)
            }
            // loading font.
            var loadFlags = $0.isBitmapPreferred ? FT_Int32(FT_LOAD_RENDER) : FT_Int32(FT_LOAD_DEFAULT)
            if $0.hasColorPaint { loadFlags |= FT_Int32(FT_LOAD_NO_SVG) }
            if $0.isColorEnabled && FT_HAS_COLOR(face) { loadFlags |= FT_Int32(FT_LOAD_COLOR) }
            if FT_Load_Glyph(face, index, loadFlags) != 0 {
                Log.err("Failed to load glyph for char=\(c)(0x\(String(format: "%x", c.value)))")
                return nil
            }

            return _glyphMetrics(from: face,
                                 index: UInt32(index),
                                 embolden: embolden)
        }
    }

    public func glyphMetrics(
        at index: UInt32,
        embolden: CGFloat = 0
    ) -> GlyphMetrics? {
        self.state.withLock { state in
            var loadFlags = state.isBitmapPreferred
                ? FT_Int32(FT_LOAD_RENDER)
                : FT_Int32(FT_LOAD_DEFAULT)
            if state.hasColorPaint { loadFlags |= FT_Int32(FT_LOAD_NO_SVG) }
            if state.isColorEnabled && FT_HAS_COLOR(state.face) {
                loadFlags |= FT_Int32(FT_LOAD_COLOR)
            }
            guard FT_Load_Glyph(
                state.face,
                FT_UInt(index),
                loadFlags
            ) == 0 else {
                Log.err("Failed to load glyph index=\(index)")
                return nil
            }
            return _glyphMetrics(
                from: state.face,
                index: index,
                embolden: embolden
            )
        }
    }

    public enum BitmapPixelMode: Sendable {
        case gray
        case bgra
    }

    public struct BitmapInfo: Sendable {
        public var left: Int
        public var top: Int         // distance from baseline
        public var width: UInt32    // bitmap width
        public var rows: UInt32     // bitmap height
        public var pixelMode: BitmapPixelMode
    }

    struct GlyphBitmap: Sendable {
        let data: [UInt8]
        let glyphMetrics: GlyphMetrics
        let bitmapInfo: BitmapInfo
        let sizeMetrics: SizeMetrics
    }

    private func _makeStrokedOutline(
        from source: inout FT_Outline,
        radius: CGFloat) -> FT_Outline? {
        guard radius > .ulpOfOne else { return nil }

        var stroker: FT_Stroker? = nil
        guard FT_Stroker_New(library.library, &stroker) == 0,
              let stroker else {
            return nil
        }
        defer { FT_Stroker_Done(stroker) }

        FT_Stroker_Set(stroker,
                       ft26d6(radius),
                       FT_STROKER_LINECAP_ROUND,
                       FT_STROKER_LINEJOIN_ROUND,
                       0)
        guard FT_Stroker_ParseOutline(stroker, &source, 0) == 0 else {
            return nil
        }

        var points: FT_UInt = 0
        var contours: FT_UInt = 0
        guard FT_Stroker_GetCounts(stroker, &points, &contours) == 0 else {
            return nil
        }

        var outline = FT_Outline()
        guard FT_Outline_New(library.library,
                             points,
                             FT_Int(contours),
                             &outline) == 0 else {
            return nil
        }
        outline.n_contours = 0
        outline.n_points = 0
        FT_Stroker_Export(stroker, &outline)
        return outline
    }

    func loadGlyphBitmap(
        for c: UnicodeScalar,
        embolden: CGFloat,
        outline: CGFloat,
        using lockedFace: LockedFace
    ) -> GlyphBitmap? {
        guard let index = glyphIndex(for: c, using: lockedFace) else {
            return nil
        }
        return loadGlyphBitmap(
            at: index,
            description: "char=\(c)(0x\(String(format: "%x", c.value)))",
            embolden: embolden,
            outline: outline,
            using: lockedFace
        )
    }

    func loadGlyphBitmap(
        at index: UInt32,
        description: String? = nil,
        embolden: CGFloat,
        outline: CGFloat,
        using lockedFace: LockedFace
    ) -> GlyphBitmap? {
        let face = lockedFace.pointer
        if let rasterizer = lockedFace.colorRasterizer,
           let bitmap = loadColorGlyphBitmap(at: index, rasterizer: rasterizer, using: lockedFace) {
            return bitmap
        }
        // loading font.
        var loadFlags = lockedFace.isBitmapPreferred ? FT_Int32(FT_LOAD_RENDER) : FT_Int32(FT_LOAD_DEFAULT)
        if lockedFace.isColorEnabled && FT_HAS_COLOR(face) { loadFlags |= FT_Int32(FT_LOAD_COLOR) }
        if FT_Load_Glyph(face, FT_UInt(index), loadFlags) != 0 {
            Log.err("Failed to load glyph \(description ?? "index=\(index)")")
            return nil
        }

        let advance = CGSize(width: ft26d6ToFloat(face.pointee.glyph.pointee.advance.x),
                             height: ft26d6ToFloat(face.pointee.glyph.pointee.advance.y))
        var bitmapInfo = BitmapInfo(left: 0, top: 0, width: 0, rows: 0, pixelMode: .gray)
        var bitmapData: [UInt8] = []
        var bitmapLoaded = false

        let copyBitmapRows = { (bitmap: FT_Bitmap, bytesPerPixel: Int) -> [UInt8]? in
            let width = Int(bitmap.width)
            let rows = Int(bitmap.rows)
            if width == 0 || rows == 0 { return [] }
            guard let buffer = bitmap.buffer else { return nil }

            let rowBytes = width * bytesPerPixel
            let pitch = Int(bitmap.pitch)
            guard abs(pitch) >= rowBytes else { return nil }

            var data = [UInt8](repeating: 0, count: rowBytes * rows)
            var src = buffer
            if pitch < 0 {
                src = src.advanced(by: -pitch * (rows - 1))
            }
            data.withUnsafeMutableBytes {
                guard let base = $0.baseAddress else { return }
                for row in 0..<rows {
                    let dst = base.advanced(by: row * rowBytes)
                    dst.copyMemory(from: src, byteCount: rowBytes)
                    src = src.advanced(by: pitch)
                }
            }
            return data
        }

        let normalizeGrayLevels = { (data: inout [UInt8], numGrays: UInt32) in
            let levels = Int(numGrays)
            if levels > 1 && levels < 256 {
                for i in data.indices {
                    data[i] = UInt8((Int(data[i]) * 255) / (levels - 1))
                }
            }
        }

        let normalizedBitmap = { (bitmap: FT_Bitmap) -> (data: [UInt8], width: UInt32, rows: UInt32, pixelMode: BitmapPixelMode)? in
            switch bitmap.pixel_mode {
            case UInt8(FT_PIXEL_MODE_GRAY.rawValue):
                guard var data = copyBitmapRows(bitmap, 1) else { return nil }
                normalizeGrayLevels(&data, UInt32(bitmap.num_grays))
                return (data, bitmap.width, bitmap.rows, .gray)
            case UInt8(FT_PIXEL_MODE_BGRA.rawValue):
                guard let data = copyBitmapRows(bitmap, 4) else { return nil }
                return (data, bitmap.width, bitmap.rows, .bgra)
            default:
                var source = bitmap
                var converted = FT_Bitmap()
                FT_Bitmap_Init(&converted)
                defer { FT_Bitmap_Done(self.library.library, &converted) }

                if FT_Bitmap_Convert(self.library.library, &source, &converted, 1) != 0 {
                    Log.err("Failed to convert glyph bitmap pixel mode: \(bitmap.pixel_mode)")
                    return nil
                }
                guard var data = copyBitmapRows(converted, 1) else { return nil }
                normalizeGrayLevels(&data, UInt32(converted.num_grays))
                return (data, converted.width, converted.rows, .gray)
            }
        }

        let setBitmap = { (bitmap: FT_Bitmap, left: Int, top: Int) -> Bool in
            guard let normalized = normalizedBitmap(bitmap) else { return false }
            bitmapInfo.left = left
            bitmapInfo.top = top
            bitmapInfo.width = normalized.width
            bitmapInfo.rows = normalized.rows
            bitmapInfo.pixelMode = normalized.pixelMode
            bitmapData = normalized.data
            return true
        }

        let boldStrength = ft26d6(embolden)

        if face.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE {
            face.pointee.glyph.pointee.outline.flags |= FT_OUTLINE_HIGH_PRECISION
            if outline > .ulpOfOne {
                // create outline stroker, drawing outline as bitmap.
                FT_Outline_Embolden(&face.pointee.glyph.pointee.outline, boldStrength)
                guard var ftOutline = _makeStrokedOutline(
                    from: &face.pointee.glyph.pointee.outline,
                    radius: outline) else {
                    return nil
                }
                defer {
                    FT_Outline_Done(library.library, &ftOutline)
                }

                var ftBitmap = FT_Bitmap()
                FT_Bitmap_Init(&ftBitmap)

                var cbox = FT_BBox()
                FT_Outline_Get_CBox(&ftOutline, &cbox)

                cbox.xMin = cbox.xMin & ~63
                cbox.yMin = cbox.yMin & ~63
                cbox.xMax = (cbox.xMax + 63) & ~63
                cbox.yMax = (cbox.yMax + 63) & ~63

                let width = UInt32(cbox.xMax - cbox.xMin) >> 6
                let height = UInt32(cbox.yMax - cbox.yMin) >> 6

                let xShift = FT_Pos(cbox.xMin)
                let yShift = FT_Pos(cbox.yMin)
                let left  = Int(cbox.xMin >> 6)  // left offset of glyph
                let top   = Int(cbox.yMax >> 6)  // upper of offset of glyph (height for origin)

                ftBitmap.width = width
                ftBitmap.rows = height
                ftBitmap.pitch = Int32(width)
                ftBitmap.num_grays = 256
                ftBitmap.pixel_mode = UInt8(FT_PIXEL_MODE_GRAY.rawValue)
                let bufferSize = Int(ftBitmap.pitch) * Int(ftBitmap.rows)
                ftBitmap.buffer = .allocate(capacity: bufferSize)
                ftBitmap.buffer.initialize(repeating: 0, count: bufferSize)

                FT_Outline_Translate(&ftOutline, -xShift, -yShift)

                if FT_Outline_Get_Bitmap(library.library, &ftOutline, &ftBitmap) == 0 {
                    bitmapLoaded = setBitmap(ftBitmap, left, top)
                }

                ftBitmap.buffer.deallocate()
                ftBitmap.buffer = nil
                FT_Bitmap_Done(library.library, &ftBitmap)
            } else {
                FT_Outline_Embolden(&face.pointee.glyph.pointee.outline, boldStrength)

                var glyph: FT_Glyph? = nil
                FT_Get_Glyph(face.pointee.glyph, &glyph)
                if FT_Glyph_To_Bitmap(&glyph, FT_RENDER_MODE_NORMAL, nil, 1) == 0 {
                    let glyphBitmap: FT_BitmapGlyph = withUnsafeBytes(of: glyph!) {
                        $0.baseAddress!.assumingMemoryBound(to: FT_BitmapGlyph.self).pointee
                    }

                    bitmapLoaded = setBitmap(glyphBitmap.pointee.bitmap,
                                             Int(glyphBitmap.pointee.left),
                                             Int(glyphBitmap.pointee.top))
                }
                FT_Done_Glyph(glyph)
            }
        } else {
            if FT_Render_Glyph(face.pointee.glyph, FT_RENDER_MODE_NORMAL) == 0 {
                let outline = outline.rounded()
                if outline > 0.0 {
                    let outerSize = ft26d6(embolden + (outline * 2))
                    let innerSize = ft26d6(embolden - (outline * 2))
                    // create two bitmaps, generate outline from bigger subtract smaller
                    var inner = FT_Bitmap()
                    var outer = FT_Bitmap()
                    FT_Bitmap_New(&inner)
                    FT_Bitmap_New(&outer)
                    FT_Bitmap_Copy(library.library, &face.pointee.glyph.pointee.bitmap, &inner)
                    FT_Bitmap_Copy(library.library, &face.pointee.glyph.pointee.bitmap, &outer)
                    FT_Bitmap_Embolden(library.library, &inner, innerSize, innerSize)
                    FT_Bitmap_Embolden(library.library, &outer, outerSize, outerSize)

                    let offsetX = (outer.width - inner.width) >> 1
                    let offsetY = (outer.rows - inner.rows) >> 1

                    for y in 0..<inner.rows {
                        for x in 0..<inner.width {
                            let value1 = outer.buffer[ Int((y + offsetY) * outer.width + x + offsetX) ]
                            let value2 = inner.buffer[ Int(y * inner.width + x) ]

                            outer.buffer[ Int((y + offsetY) * outer.width + x + offsetX) ] = max(value1 - value2, 0)
                        }
                    }
                    bitmapLoaded = setBitmap(outer,
                                             Int(face.pointee.glyph.pointee.bitmap_left) - Int(outline),
                                             Int(face.pointee.glyph.pointee.bitmap_top) - Int(outline))

                    FT_Bitmap_Done(library.library, &inner)
                    FT_Bitmap_Done(library.library, &outer)

                } else {
                    FT_Bitmap_Embolden(library.library, &(face.pointee.glyph.pointee.bitmap), boldStrength, boldStrength)
                    bitmapLoaded = setBitmap(face.pointee.glyph.pointee.bitmap,
                                             Int(face.pointee.glyph.pointee.bitmap_left),
                                             Int(face.pointee.glyph.pointee.bitmap_top))
                }
            }
        }
        guard bitmapLoaded else {
            Log.warn("Failed to load bitmap for \(description ?? "index=\(index)")")
            return nil
        }

        let metrics = baseMetrics(for: face)
        let slotMetrics = face.pointee.glyph.pointee.metrics
        let glyphMetrics = GlyphMetrics(
            index: UInt32(index),
            advance: advance,
            bearing: CGPoint(
                x: ft26d6ToFloat(slotMetrics.horiBearingX),
                y: ft26d6ToFloat(slotMetrics.horiBearingY)),
            size: CGSize(
                width: ft26d6ToFloat(slotMetrics.width),
                height: ft26d6ToFloat(slotMetrics.height)),
            ascender: metrics.ascender,
            descender: metrics.descender)
        return GlyphBitmap(
            data: bitmapData,
            glyphMetrics: glyphMetrics,
            bitmapInfo: bitmapInfo,
            sizeMetrics: metrics
        )
    }

    private func loadColorGlyphBitmap(
        at index: UInt32,
        rasterizer: OpaquePointer,
        using lockedFace: LockedFace
    ) -> GlyphBitmap? {
        let font = lockedFace.shapingFont
        // Paint coordinates and advances use the same 26.6 scale as shaping.
        hb_raster_paint_set_scale_factor(rasterizer, 64, 64)
        let advance = CGSize(
            width: CGFloat(hb_font_get_glyph_h_advance(font, index)) / 64,
            height: 0
        )
        let painted = hb_raster_paint_glyph_or_fail(rasterizer, font, index) != 0
        // Rendering also clears accumulated state on failed paint operations.
        guard let image = hb_raster_paint_render(rasterizer) else { return nil }
        defer { hb_raster_image_destroy(image) }
        guard painted,
              hb_raster_image_get_format(image) == HB_RASTER_FORMAT_BGRA32,
              let pixels = hb_raster_image_get_buffer(image) else { return nil }
        var extents = hb_raster_extents_t()
        hb_raster_image_get_extents(image, &extents)
        let width = Int(extents.width)
        let rows = Int(extents.height)
        guard width > 0, rows > 0, Int(extents.stride) >= width * 4 else { return nil }
        let bytesPerPixel = lockedFace.isColorEnabled ? 4 : 1
        var data = [UInt8](repeating: 0, count: width * rows * bytesPerPixel)
        data.withUnsafeMutableBytes { destination in
            for row in 0..<rows {
                // The rasterizer's first row is at the bottom of the glyph.
                let source = pixels.advanced(by: (rows - row - 1) * Int(extents.stride))
                if lockedFace.isColorEnabled {
                    destination.baseAddress!.advanced(by: row * width * 4).copyMemory(
                        from: source, byteCount: width * 4
                    )
                } else {
                    for column in 0..<width {
                        destination[row * width + column] = source[column * 4 + 3]
                    }
                }
            }
        }
        let left = Int(extents.x_origin)
        let top = Int(extents.y_origin) + rows
        let metrics = baseMetrics(for: lockedFace.pointer)
        return GlyphBitmap(
            data: data,
            glyphMetrics: GlyphMetrics(
                index: index, advance: advance,
                bearing: CGPoint(x: left, y: top),
                size: CGSize(width: width, height: rows),
                ascender: metrics.ascender, descender: metrics.descender
            ),
            bitmapInfo: BitmapInfo(left: left, top: top, width: extents.width,
                                   rows: extents.height,
                                   pixelMode: lockedFace.isColorEnabled ? .bgra : .gray),
            sizeMetrics: metrics
        )
    }

    public func withGlyphBitmap(
        for c: UnicodeScalar,
        embolden: CGFloat,
        outline: CGFloat,
        _ body: ([UInt8], GlyphMetrics, BitmapInfo, SizeMetrics)->Void) -> Bool {
        guard let bitmap = self.withLockedFace({ lockedFace in
            self.loadGlyphBitmap(
                for: c,
                embolden: embolden,
                outline: outline,
                using: lockedFace
            )
        }) else { return false }

        body(
            bitmap.data,
            bitmap.glyphMetrics,
            bitmap.bitmapInfo,
            bitmap.sizeMetrics
        )
        return true
    }

    public func withGlyphBitmap(
        at index: UInt32,
        embolden: CGFloat,
        outline: CGFloat,
        _ body: ([UInt8], GlyphMetrics, BitmapInfo, SizeMetrics) -> Void
    ) -> Bool {
        guard let bitmap = self.withLockedFace({ lockedFace in
            self.loadGlyphBitmap(
                at: index,
                embolden: embolden,
                outline: outline,
                using: lockedFace
            )
        }) else { return false }

        body(
            bitmap.data,
            bitmap.glyphMetrics,
            bitmap.bitmapInfo,
            bitmap.sizeMetrics
        )
        return true
    }

    /// Returns a value snapshot before size scaling and pixel rounding.
    /// Bitmap-only faces have no scalable design metrics and return nil.
    /// Divide by unitsPerEM and multiply by the desired em size to scale a value.
    public var designMetrics: DesignMetrics? {
        self.state.withLock {
            let face = $0.face
            guard FT_IS_SCALABLE(face), face.pointee.units_per_EM > 0 else {
                return nil
            }
            let outlineFormat: OutlineFormat
            switch FT_Get_Font_Format(face).map({ String(cString: $0) }) {
            case "TrueType": outlineFormat = .trueType
            case "CFF": outlineFormat = .compactFontFormat
            default: outlineFormat = .other
            }
            let clipping = FontMetricsReader.read(face: face, library: library.library)
            let capHeight = $0.layoutFont.flatMap {
                FontMetricsReader.compositionMetrics(face: face, library: library.library, font: $0)
            }.map { Int($0.capHeight) }
            return DesignMetrics(outlineFormat: outlineFormat,
                                 unitsPerEM: Int(face.pointee.units_per_EM),
                                 ascender: Int(face.pointee.ascender),
                                 descender: Int(face.pointee.descender),
                                 height: Int(face.pointee.height),
                                 capHeight: capHeight,
                                 clipping: clipping)
        }
    }

    public var baseMetrics: SizeMetrics {
        self.state.withLock { baseMetrics(for: $0.face) }
    }

    private func baseMetrics(for face: FT_Face) -> SizeMetrics {
        let metrics = face.pointee.size.pointee.metrics
        return SizeMetrics(xPixelsPerEM: Int(metrics.x_ppem),
                           yPixelsPerEM: Int(metrics.y_ppem),
                           xScale: ft16d16ToFloat(metrics.x_scale),
                           yScale: ft16d16ToFloat(metrics.y_scale),
                           ascender: ft26d6ToFloat(metrics.ascender),
                           descender: ft26d6ToFloat(metrics.descender),
                           height: ft26d6ToFloat(metrics.height),
                           maxAdvance: ft26d6ToFloat(metrics.max_advance))
    }

    public enum OutlineCommand: Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case quadCurve(to: CGPoint, control: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
    }

    /// Returns selected-font bounds in design units, independently of size and DPI.
    /// Coordinates are baseline-relative with +Y up. Unsupported faces return nil.
    public func designGlyphBounds(at glyphIndex: UInt32) -> CGRect? {
        self.state.withLock { state in
            guard let font = state.layoutFont, glyphIndex < self.numGlyphs else { return nil }
            var bounds = hb_glyph_extents_t()
            guard hb_font_get_glyph_extents(font, glyphIndex, &bounds) != 0 else { return nil }
            return CGRect(x: CGFloat(bounds.x_bearing) / 64,
                          y: (CGFloat(bounds.y_bearing) + CGFloat(bounds.height)) / 64,
                          width: CGFloat(bounds.width) / 64, height: -CGFloat(bounds.height) / 64)
        }
    }

    package var glyphCompositionMetrics: GlyphComposer.Metrics? {
        self.state.withLock { state in
            guard let font = state.layoutFont,
                  state.face.pointee.units_per_EM > 0 else { return nil }
            let scale = state.pointSize * CGFloat(state.dpi.y) / 72 /
                CGFloat(state.face.pointee.units_per_EM)
            return FontMetricsReader.compositionMetrics(
                face: state.face,
                library: library.library,
                font: font
            )?.scaled(by: scale)
        }
    }

    package func allowsMarkComposition(at glyphIndex: UInt32) -> Bool {
        self.state.withLock { state in
            guard let font = state.layoutFont,
                  glyphIndex < self.numGlyphs else { return false }
            let glyphClass = hb_ot_layout_get_glyph_class(
                hb_font_get_face(font), glyphIndex
            )
            return glyphClass == HB_OT_LAYOUT_GLYPH_CLASS_UNCLASSIFIED ||
                glyphClass == HB_OT_LAYOUT_GLYPH_CLASS_MARK
        }
    }

    /// Decomposes the selected outline in design units without raster hinting.
    /// Contours are implicitly closed. Empty supported glyphs succeed without commands.
    /// The callback runs after releasing the font-state lock.
    public func decomposeDesignGlyphOutline(
        at glyphIndex: UInt32,
        _ body: (OutlineCommand) -> Void
    ) -> Bool {
        var commands: [OutlineCommand] = []
        let supported = self.state.withLock { state in
            guard let font = state.layoutFont, glyphIndex < self.numGlyphs,
                  let functions = hb_draw_funcs_create() else { return false }
            defer { hb_draw_funcs_destroy(functions) }
            hb_draw_funcs_set_move_to_func(functions, { _, data, _, x, y, _ in
                data!.assumingMemoryBound(to: [OutlineCommand].self).pointee.append(
                    .move(to: CGPoint(x: CGFloat(x) / 64, y: CGFloat(y) / 64)))
            }, nil, nil)
            hb_draw_funcs_set_line_to_func(functions, { _, data, _, x, y, _ in
                data!.assumingMemoryBound(to: [OutlineCommand].self).pointee.append(
                    .line(to: CGPoint(x: CGFloat(x) / 64, y: CGFloat(y) / 64)))
            }, nil, nil)
            hb_draw_funcs_set_quadratic_to_func(functions, { _, data, _, cx, cy, x, y, _ in
                data!.assumingMemoryBound(to: [OutlineCommand].self).pointee.append(
                    .quadCurve(to: CGPoint(x: CGFloat(x) / 64, y: CGFloat(y) / 64),
                               control: CGPoint(x: CGFloat(cx) / 64, y: CGFloat(cy) / 64)))
            }, nil, nil)
            hb_draw_funcs_set_cubic_to_func(functions, { _, data, _, ax, ay, bx, by, x, y, _ in
                data!.assumingMemoryBound(to: [OutlineCommand].self).pointee.append(
                    .curve(to: CGPoint(x: CGFloat(x) / 64, y: CGFloat(y) / 64),
                           control1: CGPoint(x: CGFloat(ax) / 64, y: CGFloat(ay) / 64),
                           control2: CGPoint(x: CGFloat(bx) / 64, y: CGFloat(by) / 64)))
            }, nil, nil)
            return withUnsafeMutablePointer(to: &commands) {
                hb_font_draw_glyph_or_fail(font, glyphIndex, functions, $0) != 0
            }
        }
        guard supported else { return false }
        commands.forEach(body)
        return true
    }

    /// Decomposes an optionally emboldened or stroked glyph outline into path
    /// commands and returns its metrics.
    /// Contours are implicitly closed. Coordinates are baseline-relative with +Y up.
    public func decomposeGlyphOutline(
        for c: UnicodeScalar,
        embolden: CGFloat = 0,
        outline: CGFloat = 0,
        _ body: (OutlineCommand) -> Void) -> GlyphMetrics? {
        var commands: [OutlineCommand] = []
        let metrics: GlyphMetrics? = self.state.withLock {
            let face = $0.face
            let index = face.pointee.charmap != nil
                ? FT_Get_Char_Index(face, FT_ULong(c.value)) : FT_UInt(c.value)
            return _decomposeGlyphOutline(
                at: UInt32(index),
                face: face,
                embolden: embolden,
                outline: outline,
                commands: &commands
            )
        }
        guard let metrics else { return nil }

        commands.forEach(body)
        return metrics
    }

    public func decomposeGlyphOutline(
        at index: UInt32,
        embolden: CGFloat = 0,
        outline: CGFloat = 0,
        _ body: (OutlineCommand) -> Void
    ) -> GlyphMetrics? {
        var commands: [OutlineCommand] = []
        let metrics = self.state.withLock { state in
            _decomposeGlyphOutline(
                at: index,
                face: state.face,
                embolden: embolden,
                outline: outline,
                commands: &commands
            )
        }
        guard let metrics else { return nil }
        commands.forEach(body)
        return metrics
    }

    private func _decomposeGlyphOutline(
        at index: UInt32,
        face: FT_Face,
        embolden: CGFloat,
        outline: CGFloat,
        commands: inout [OutlineCommand]
    ) -> GlyphMetrics? {
        let loadFlags = FT_Int32(FT_LOAD_DEFAULT) |
                        FT_Int32(FT_LOAD_NO_BITMAP)
        guard FT_Load_Glyph(face, FT_UInt(index), loadFlags) == 0 else {
            return nil
        }
        guard face.pointee.glyph.pointee.format == FT_GLYPH_FORMAT_OUTLINE else {
            return nil
        }

        let strength = ft26d6(embolden)
        if strength != 0 {
            guard FT_Outline_Embolden(
                &face.pointee.glyph.pointee.outline,
                strength) == 0 else {
                return nil
            }
        }

        var sourceOutline = face.pointee.glyph.pointee.outline
        var decomposedOutline = sourceOutline
        var ownsDecomposedOutline = false
        if outline > .ulpOfOne {
            guard let strokedOutline = _makeStrokedOutline(
                from: &sourceOutline,
                radius: outline) else {
                return nil
            }
            decomposedOutline = strokedOutline
            ownsDecomposedOutline = true
        }
        defer {
            if ownsDecomposedOutline {
                FT_Outline_Done(library.library, &decomposedOutline)
            }
        }

        var functions = FT_Outline_Funcs()
        functions.move_to = { (to: UnsafePointer<FT_Vector>?,
                               context: UnsafeMutableRawPointer?) -> Int32 in
            let commands = context!.assumingMemoryBound(
                to: [OutlineCommand].self
            )
            commands.pointee.append(.move(to: CGPoint(ft26d6: to!.pointee)))
            return 0
        }
        functions.line_to = { (to: UnsafePointer<FT_Vector>?,
                               context: UnsafeMutableRawPointer?) -> Int32 in
            let commands = context!.assumingMemoryBound(
                to: [OutlineCommand].self
            )
            commands.pointee.append(.line(to: CGPoint(ft26d6: to!.pointee)))
            return 0
        }
        functions.conic_to = { (control: UnsafePointer<FT_Vector>?,
                                to: UnsafePointer<FT_Vector>?,
                                context: UnsafeMutableRawPointer?) -> Int32 in
            let commands = context!.assumingMemoryBound(
                to: [OutlineCommand].self
            )
            commands.pointee.append(.quadCurve(
                to: CGPoint(ft26d6: to!.pointee),
                control: CGPoint(ft26d6: control!.pointee)
            ))
            return 0
        }
        functions.cubic_to = { (control1: UnsafePointer<FT_Vector>?,
                                control2: UnsafePointer<FT_Vector>?,
                                to: UnsafePointer<FT_Vector>?,
                                context: UnsafeMutableRawPointer?) -> Int32 in
            let commands = context!.assumingMemoryBound(
                to: [OutlineCommand].self
            )
            commands.pointee.append(.curve(
                to: CGPoint(ft26d6: to!.pointee),
                control1: CGPoint(ft26d6: control1!.pointee),
                control2: CGPoint(ft26d6: control2!.pointee)
            ))
            return 0
        }
        functions.shift = 0
        functions.delta = 0

        let error = withUnsafeMutablePointer(to: &commands) {
            FT_Outline_Decompose(
                &decomposedOutline,
                &functions,
                UnsafeMutableRawPointer($0)
            )
        }
        guard error == 0 else { return nil }
        return _glyphMetrics(
            from: face,
            index: index,
            embolden: embolden
        )
    }
}

private extension Font.ShapingDirection {
    var harfbuzzValue: hb_direction_t {
        switch self {
        case .leftToRight: HB_DIRECTION_LTR
        case .rightToLeft: HB_DIRECTION_RTL
        case .topToBottom: HB_DIRECTION_TTB
        case .bottomToTop: HB_DIRECTION_BTT
        }
    }

    init?(harfbuzzValue: hb_direction_t) {
        switch harfbuzzValue {
        case HB_DIRECTION_LTR: self = .leftToRight
        case HB_DIRECTION_RTL: self = .rightToLeft
        case HB_DIRECTION_TTB: self = .topToBottom
        case HB_DIRECTION_BTT: self = .bottomToTop
        default: return nil
        }
    }
}
