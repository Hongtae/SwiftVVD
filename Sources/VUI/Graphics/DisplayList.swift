//
//  File: DisplayList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

nonisolated(unsafe) private var _displayListIdentityCounter: UInt32 = 0

protocol RBDisplayListContents: AnyObject {
}

/// Supplies a logical platform-group boundary while retaining the active renderer.
protocol PlatformGroupFactory: AnyObject {
    var platformGroupContainer: AnyObject { get }

    func renderPlatformGroup(
        contents: DisplayList,
        in context: GraphicsContext,
        render: (DisplayList, GraphicsContext) -> Void
    )
}

struct _DisplayList_Identity: Codable, Hashable, CustomStringConvertible {
    private(set) var value: UInt32

    init() {
        _displayListIdentityCounter &+= 1
        self.value = _displayListIdentityCounter
    }

    init(decodedValue: UInt32) {
        self.value = decodedValue
    }

    static var none: Self {
        Self(decodedValue: 0)
    }

    var description: String {
        "#\(value)"
    }
}

struct _DisplayList_StableIdentity: Codable, Hashable {
    var hash: StrongHash
    var serial: UInt32

    init(hash: StrongHash, serial: UInt32) {
        self.hash = hash
        self.serial = serial
    }
}

struct _DisplayList_StableIdentityMap: Equatable {
    private var map: [_DisplayList_Identity: _DisplayList_StableIdentity]

    init() {
        self.map = [:]
    }

    var isEmpty: Bool {
        map.isEmpty
    }

    subscript(identity: _DisplayList_Identity) -> _DisplayList_StableIdentity? {
        get { map[identity] }
        set { map[identity] = newValue }
    }

    mutating func formUnion(_ other: Self) {
        map.merge(other.map) { current, _ in current }
    }
}

/// Shared owner for weak stable-identity scopes and their collected map.
///
/// Scopes are graph values, so the root retains only weak attribute handles.
/// The map is materialized lazily by consumers that need archived identities.
final class _DisplayList_StableIdentityRoot {
    var scopes: [WeakAttribute<_DisplayList_StableIdentityScope>]
    var map: _DisplayList_StableIdentityMap?

    init() {
        scopes = []
        map = nil
    }

    subscript(identity: _DisplayList_Identity)
        -> _DisplayList_StableIdentity? {
        guard _AGGraph.current != nil else {
            fatalError(
                "Stable identity lookup requires an active graph context."
            )
        }

        if map == nil {
            var merged = _DisplayList_StableIdentityMap()
            var index = scopes.startIndex
            while index < scopes.endIndex {
                guard let attribute = scopes[index].attribute else {
                    scopes.remove(at: index)
                    continue
                }

                // Scope maps are bookkeeping values, not dependencies of the
                // consumer that materializes the root cache.
                let scope = attribute.valueAndFlags(
                    options: .withoutDependency
                ).value
                merged.formUnion(scope.map)
                index += 1
            }
            map = merged
        }
        return map?[identity]
    }
}

/// One hash namespace in the display-list stable-identity hierarchy.
///
/// The same declaration is both a graph-input key and a view-trait key. Each
/// channel carries a weak attribute so descendants can inherit a live scope
/// without extending its graph lifetime.
struct _DisplayList_StableIdentityScope: GraphInput, _ViewTraitKey {
    typealias Value = WeakAttribute<_DisplayList_StableIdentityScope>

    static var defaultValue: Value {
        WeakAttribute()
    }

    var root: _DisplayList_StableIdentityRoot
    var hash: StrongHash
    var map: _DisplayList_StableIdentityMap
    var serial: UInt32

    init(root: _DisplayList_StableIdentityRoot) {
        self.root = root
        hash = StrongHash(of: "root")
        map = _DisplayList_StableIdentityMap()
        serial = 0
    }

    init<ID: StronglyHashable>(
        id: ID,
        parent: _DisplayList_StableIdentityScope
    ) {
        root = parent.root
        var hasher = StrongHasher()
        hasher.combine(id)
        hasher.combine(parent.hash)
        hash = hasher.finalize()
        map = _DisplayList_StableIdentityMap()
        serial = 0
    }

    mutating func makeIdentity() -> _DisplayList_StableIdentity {
        serial &+= 1
        return _DisplayList_StableIdentity(hash: hash, serial: serial)
    }

    mutating func pushIdentity() -> _DisplayList_Identity {
        let identity = _DisplayList_Identity()
        let stableIdentity = makeIdentity()
        map[identity] = stableIdentity

        // The next root lookup must include the newly-published local entry.
        root.map = nil
        return identity
    }
}

extension Attribute
where Value == _DisplayList_StableIdentityScope {
    /// Accesses scope bookkeeping in place without publishing a copied input.
    subscript() -> _DisplayList_StableIdentityScope {
        get {
            valueAndFlags(options: .withoutDependency).value
        }
        _modify {
            guard let graph = _AGGraph.current else {
                fatalError(
                    "Stable identity mutation requires an active graph context."
                )
            }
            let pointer = graph.mutableValuePointer(for: self)
            yield &pointer.pointee
        }
    }
}

extension _DisplayList_StableIdentity: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        encoder.encodeVarint(0x0a)
        try encoder.encodeMessage(hash)
        if serial != 0 {
            encoder.encodeVarint(0x10)
            encoder.encodeVarint(UInt(serial))
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var hash = StrongHash(words: (0, 0, 0, 0, 0))
        var serial: UInt32 = 0

        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            guard tag >= 0x08 else {
                throw ProtobufDecoder.DecodingError.failed
            }

            let field = tag >> 3
            let wireType = tag & 0x07
            switch field {
            case 1:
                guard wireType == 2 else {
                    throw ProtobufDecoder.DecodingError.failed
                }
                hash = try decoder.decodeMessage(StrongHash.self)
            case 2:
                switch wireType {
                case 0:
                    serial = UInt32(truncatingIfNeeded: try decoder.decodeVarint())
                case 2:
                    serial = try decoder.decodeLengthDelimited { packedDecoder in
                        var value: UInt32?
                        while !packedDecoder.isAtEnd {
                            value = UInt32(truncatingIfNeeded: try packedDecoder.decodeVarint())
                        }
                        guard let value else {
                            throw ProtobufDecoder.DecodingError.failed
                        }
                        return value
                    }
                default:
                    throw ProtobufDecoder.DecodingError.failed
                }
            default:
                try decoder.skipField(wireType: wireType)
            }
        }

        self.init(hash: hash, serial: serial)
    }
}

extension _DisplayList_StableIdentityMap: ProtobufEncodableMessage, ProtobufDecodableMessage {
    func encode(to encoder: inout ProtobufEncoder) throws {
        for (identity, stableIdentity) in map {
            encoder.encodeVarint(0x0a)
            encoder.startLengthDelimited()
            if identity.value != 0 {
                encoder.encodeVarint(0x08)
                encoder.encodeVarint(UInt(identity.value))
            }
            encoder.encodeVarint(0x12)
            try encoder.encodeMessage(stableIdentity)
            encoder.endLengthDelimited()
        }
    }

    init(from decoder: inout ProtobufDecoder) throws {
        var map: [_DisplayList_Identity: _DisplayList_StableIdentity] = [:]

        while !decoder.isAtEnd {
            let tag = try decoder.decodeVarint()
            guard tag >= 0x08 else {
                throw ProtobufDecoder.DecodingError.failed
            }

            let field = tag >> 3
            let wireType = tag & 0x07
            if field == 1 {
                guard wireType == 2 else {
                    throw ProtobufDecoder.DecodingError.failed
                }
                let entry = try decoder.decodeLengthDelimited { entryDecoder in
                    var identity: _DisplayList_Identity?
                    var stableIdentity: _DisplayList_StableIdentity?

                    while !entryDecoder.isAtEnd {
                        let entryTag = try entryDecoder.decodeVarint()
                        guard entryTag >= 0x08 else {
                            throw ProtobufDecoder.DecodingError.failed
                        }

                        let entryField = entryTag >> 3
                        let entryWireType = entryTag & 0x07
                        switch entryField {
                        case 1:
                            switch entryWireType {
                            case 0:
                                identity = _DisplayList_Identity(
                                    decodedValue: UInt32(truncatingIfNeeded: try entryDecoder.decodeVarint())
                                )
                            case 2:
                                identity = try entryDecoder.decodeLengthDelimited { packedDecoder in
                                    var value: UInt32?
                                    while !packedDecoder.isAtEnd {
                                        value = UInt32(truncatingIfNeeded: try packedDecoder.decodeVarint())
                                    }
                                    guard let value else {
                                        throw ProtobufDecoder.DecodingError.failed
                                    }
                                    return _DisplayList_Identity(decodedValue: value)
                                }
                            default:
                                throw ProtobufDecoder.DecodingError.failed
                            }
                        case 2:
                            guard entryWireType == 2 else {
                                throw ProtobufDecoder.DecodingError.failed
                            }
                            stableIdentity = try entryDecoder.decodeMessage(_DisplayList_StableIdentity.self)
                        default:
                            try entryDecoder.skipField(wireType: entryWireType)
                        }
                    }

                    guard let identity, let stableIdentity else {
                        throw ProtobufDecoder.DecodingError.failed
                    }
                    return (identity, stableIdentity)
                }
                map[entry.0] = entry.1
            } else {
                try decoder.skipField(wireType: wireType)
            }
        }

        self.map = map
    }
}

// Ordered collection of rendering commands produced by the view tree.
// Propagated to the scene root via the DisplayList.Key preference.
// TODO: Replace closure-backed draw bodies with backend commands as typed coverage is proven.
struct DisplayList: Equatable, CustomStringConvertible {
    final class LocalContents: RBDisplayListContents {
        var list: DisplayList

        init(list: DisplayList) {
            self.list = list
        }
    }

    struct ArchiveIDs: Equatable {
        var uuid: UUID
        var stableIDs: _DisplayList_StableIdentityMap

        init(uuid: UUID, stableIDs: _DisplayList_StableIdentityMap) {
            self.uuid = uuid
            self.stableIDs = stableIDs
        }
    }

    struct Version: Comparable, Hashable {
        let value: Int

        nonisolated(unsafe) private static var lastValue: Int = 0

        init() {
            self.value = 0
        }

        init(value: Int) {
            self.value = value
        }

        init(decodedValue: Int) {
            self.value = decodedValue
            if decodedValue > Self.lastValue {
                Self.lastValue = decodedValue
            }
        }

        init(forUpdate: ()) {
            Self.lastValue &+= 1
            self.value = Self.lastValue
        }

        mutating func combine(with other: Self) {
            if other.value > value {
                self = other
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.value < rhs.value
        }
    }

    struct Options: OptionSet, ViewInput, Sendable {
        typealias Value = Options

        var rawValue: UInt8

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        static let disableCanonicalization = Options(rawValue: 1)
        static let defaultValue = Options()
    }

    struct Features: OptionSet, Sendable {
        var rawValue: UInt16

        init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        static let required = Features(rawValue: 0x0001)
        static let animations = Features(rawValue: 0x0004)
        static let dynamicContent = Features(rawValue: 0x0008)
        static let interpolatorLayers = Features(rawValue: 0x0010)
        static let interpolatorRoots = Features(rawValue: 0x0020)
        static let stateEffects = Features(rawValue: 0x0040)
        static let states = Features(rawValue: 0x0080)
        static let flattened = Features(rawValue: 0x0200)
        static let platformViews = Features(rawValue: 0x0400)
    }

    struct Properties: OptionSet, Sendable {
        var rawValue: UInt32

        init(rawValue: UInt32) {
            self.rawValue = rawValue
        }
    }

    // Compact change token used by interpolation groups to detect display-list content updates.
    struct Seed: Equatable, Hashable {
        private(set) var value: UInt16

        init() {
            self.value = 0
        }

        init(decodedValue: UInt16) {
            self.value = decodedValue
        }

        init(_ version: Version) {
            let bits = UInt(bitPattern: version.value)
            guard bits != 0 else {
                self.value = 0
                return
            }

            let high = UInt32(truncatingIfNeeded: bits >> 16)
            let low = UInt32(truncatingIfNeeded: bits)
            let mixed = (high &+ (high << 5)) ^ low
            self.value = UInt16(truncatingIfNeeded: (mixed << 1) | 1)
        }

        mutating func invalidate() {
            guard value != 0 else { return }
            value = (~value) | 1
        }

        static var undefined: Seed {
            Seed(decodedValue: 2)
        }
    }

    struct Index {
        private struct RestoreOptions: OptionSet {
            var rawValue: UInt8

            static let identity = RestoreOptions(rawValue: 1 << 0)
            static let archiveIdentity = RestoreOptions(rawValue: 1 << 1)
            static let swapIdentityToArchive = RestoreOptions(rawValue: 1 << 2)
            static let swapArchiveToIdentity = RestoreOptions(rawValue: 1 << 3)
        }

        private(set) var identity: _DisplayList_Identity
        private(set) var serial: UInt32
        private(set) var archiveIdentity: _DisplayList_Identity
        private(set) var archiveSerial: UInt32
        private var restored: RestoreOptions

        init() {
            identity = .none
            serial = 0
            archiveIdentity = .none
            archiveSerial = 0
            restored = []
        }

        mutating func enter(identity: _DisplayList_Identity) -> Self {
            if identity != .none {
                let previous = self
                self.identity = identity
                serial = 0
                restored = .identity
                return previous
            }

            serial &+= 1
            let entered = self
            restored = []
            return entered
        }

        mutating func leave(index: Self) {
            let currentIdentity = identity
            let currentSerial = serial
            if restored.contains(.swapIdentityToArchive) {
                identity = archiveIdentity
                serial = archiveSerial
            }
            if restored.contains(.swapArchiveToIdentity) {
                archiveIdentity = currentIdentity
                archiveSerial = currentSerial
            }
            if restored.contains(.identity) {
                identity = index.identity
                serial = index.serial
            }
            if restored.contains(.archiveIdentity) {
                archiveIdentity = index.archiveIdentity
                archiveSerial = index.archiveSerial
            }
            restored = index.restored
        }

        mutating func updateArchive(entering: Bool) {
            if entering {
                archiveIdentity = identity
                archiveSerial = serial
                identity = .none
                serial = 0
                restored.formUnion([.archiveIdentity, .swapIdentityToArchive])
            } else {
                identity = archiveIdentity
                serial = archiveSerial
                archiveIdentity = .none
                archiveSerial = 0
                restored.formUnion([.identity, .swapArchiveToIdentity])
            }
        }

        var id: ID {
            ID(
                identity: identity,
                serial: serial,
                archiveIdentity: archiveIdentity,
                archiveSerial: archiveSerial
            )
        }

        mutating func skip(list: DisplayList) {
            for item in list.items {
                skip(item: item)
            }
        }

        mutating func skip(item: Item) {
            guard item.version.value == 0 else { return }

            let previous = enter(identity: .none)
            defer { leave(index: previous) }

            switch item.value {
            case let .content(content):
                if case let .flattened(list, _, _) = content.value {
                    skip(list: list)
                }
            case let .effect(effect, contents):
                skip(list: contents)
                skip(effect: effect)
            case .states, .empty:
                break
            }
        }

        mutating func skip(effect: Effect) {
            switch effect {
            case let .archive(ids):
                updateArchive(entering: ids != nil)
            case let .mask(list, _):
                skip(list: list)
            default:
                break
            }
        }

        struct ID: Hashable {
            private var identity: _DisplayList_Identity
            private var serial: UInt32
            private var archiveIdentity: _DisplayList_Identity
            private var archiveSerial: UInt32

            fileprivate init(
                identity: _DisplayList_Identity,
                serial: UInt32,
                archiveIdentity: _DisplayList_Identity,
                archiveSerial: UInt32
            ) {
                self.identity = identity
                self.serial = serial
                self.archiveIdentity = archiveIdentity
                self.archiveSerial = archiveSerial
            }
        }
    }

    // Renderer-side metadata attached to a display list for state, content transitions, and
    // interpolator group routing.
    enum Effect {
        case identity
        case archive(ArchiveIDs?)
        case platformGroup(any PlatformGroupFactory)
        case opacity(Float)
        case transform(ProjectionTransform)
        case mask(DisplayList, GraphicsContext.ClipOptions)
        case animation(any _DisplayList_AnyEffectAnimation)
        case state(StrongHash)
        case contentTransition(ContentTransition.State)
        case shader(Shader.ResolvedShader)
        case geometryGroup
        case interpolatorRoot(InterpolatorGroup, CGPoint, CGSize)
        case interpolatorLayer(InterpolatorGroup, UInt32)
        case interpolatorAnimation(InterpolatorAnimation)
    }

    // Effect wrapper that keeps the original display-list contents with the effect marker.
    struct EffectItem {
        var effect: Effect
        var contents: DisplayList
        var frame: CGRect
        var identity: _DisplayList_Identity
        var version: Version
        var opacity: Float
        var styleChain: StyleChain
    }

    // Style commands are captured by each item when it is recorded. Keeping the chain on the
    // item preserves nested style scope when independently recorded lists are composed later.
    enum StyleCommand: Equatable {
        struct MetadataIdentity: Equatable {
            var count: UInt32
            var namespace: UUID?

            static let empty = MetadataIdentity(count: 0, namespace: nil)

            func matches(_ other: MetadataIdentity) -> Bool {
                guard count == other.count else { return false }
                if count == 0 { return true }
                guard let namespace, let otherNamespace = other.namespace else {
                    return false
                }
                return namespace == otherNamespace
            }
        }

        struct AnimationStyle: Equatable {
            static let defaultFlags: UInt32 = 0x111

            var animation: RBAnimation
            var id: UUID?
            var flags: UInt32
            var metadataIdentity: MetadataIdentity

            init(
                animation: RBAnimation,
                id: UUID?,
                flags: UInt32,
                metadataIdentity: MetadataIdentity = .empty
            ) {
                self.animation = animation.copy() as? RBAnimation ?? RBAnimation()
                self.id = id
                self.flags = flags
                self.metadataIdentity = metadataIdentity
            }

            static func == (lhs: AnimationStyle, rhs: AnimationStyle) -> Bool {
                lhs.animation.isEqual(rhs.animation) &&
                    lhs.id == rhs.id &&
                    lhs.flags == rhs.flags &&
                    lhs.metadataIdentity == rhs.metadataIdentity
            }
        }

        case animation(AnimationStyle)
    }

    struct StyleChain: Equatable {
        var commands: [StyleCommand] = []

        func appendingOuter(_ outer: StyleChain) -> StyleChain {
            StyleChain(commands: commands + outer.commands)
        }
    }

    // Lightweight render-item summary used by interpolation before backend typed
    // commands replace closure-backed drawing.
    struct ItemRecord: Equatable {
        enum Kind: UInt8, Equatable {
            case closure
            case shapeFill
            case shapeStroke
            case shapeSeparator
            case image
            case text
            case custom
            case effect
            case debug
        }

        enum EffectKind: UInt8, Equatable {
            case generic
            case opacity
            case blur
            case geometry
            case crossFade
            case blendMode
            case shadow
            case colorFilter
        }

        enum ShapeStyleRecord: Equatable {
            case color(Color)
            case gradient(Gradient)
            case meshGradient(MeshGradient)
            case shader(Shader.ResolvedShader)
        }

        enum ShadingRecord: Equatable {
            case color(Color)
        }

        struct ImageRecord: Equatable {
            var baseline: CGFloat
            var textureID: ObjectIdentifier?
            var symbolID: ResolvedVectorSymbol.Identity?
            var vectorID: ObjectIdentifier?
            var placementRect: CGRect
            var textureTransform: CGAffineTransform
            var scaleFactor: CGFloat
            var hasShading: Bool
            var shading: ShadingRecord?

            init(
                baseline: CGFloat,
                textureID: ObjectIdentifier?,
                symbolID: ResolvedVectorSymbol.Identity? = nil,
                vectorID: ObjectIdentifier? = nil,
                placementRect: CGRect,
                textureTransform: CGAffineTransform,
                scaleFactor: CGFloat,
                hasShading: Bool,
                shading: ShadingRecord?
            ) {
                self.baseline = baseline
                self.textureID = textureID
                self.symbolID = symbolID
                self.vectorID = vectorID
                self.placementRect = placementRect
                self.textureTransform = textureTransform
                self.scaleFactor = scaleFactor
                self.hasShading = hasShading
                self.shading = shading
            }

            init(
                _ image: GraphicsContext.ResolvedImage,
                placementRect: CGRect,
                shading: ShadingRecord?
            ) {
                baseline = image.baseline
                textureID = image.texture.map { ObjectIdentifier($0) }
                symbolID = image.symbol?.identity
                vectorID = image.vectorID
                self.placementRect = placementRect
                textureTransform = image.textureTransform
                scaleFactor = image.scaleFactor
                hasShading = image.shading != nil
                self.shading = shading
            }
        }

        struct TextRecord: Equatable {
            var foreground: ShadingRecord?
        }

        struct CustomRecord: Equatable {
            var isOpaque: Bool
            var colorMode: ColorRenderingMode
            var rendersAsynchronously: Bool
        }

        struct ShadowRecord: Equatable {
            var color: Color.Resolved
            var radius: CGFloat
            var offset: CGSize
            var blendModeRawValue: Int32
            var optionsRawValue: UInt32
        }

        enum ColorFilterKind: UInt8, Equatable {
            case colorMultiply
            case hueRotation
            case saturation
            case brightness
            case contrast
            case colorInvert
            case grayscale
            case luminanceToAlpha
            case colorMatrix
        }

        struct ColorFilterRecord: Equatable {
            var kind: ColorFilterKind
            var amount: Double
            var color: Color.Resolved?
            var matrix: ColorMatrix?

            init(
                kind: ColorFilterKind,
                amount: Double,
                color: Color.Resolved? = nil,
                matrix: ColorMatrix? = nil
            ) {
                self.kind = kind
                self.amount = amount
                self.color = color
                self.matrix = matrix
            }
        }

        var kind: Kind
        var effectKind: EffectKind?
        var bounds: CGRect?
        var shapeStyle: ShapeStyleRecord?
        var fillStyle: FillStyle?
        var strokeStyle: StrokeStyle?
        var image: ImageRecord?
        var text: TextRecord?
        var custom: CustomRecord?
        var opacity: Double?
        var blurRadius: CGFloat?
        var blurIsOpaque: Bool?
        var affineTransform: CGAffineTransform?
        var sourceFraction: Float?
        var targetFraction: Float?
        var blendMode: BlendMode?
        var shadow: ShadowRecord?
        var colorFilter: ColorFilterRecord?

        init(
            kind: Kind,
            bounds: CGRect? = nil,
            effectKind: EffectKind? = nil,
            shapeStyle: ShapeStyleRecord? = nil,
            fillStyle: FillStyle? = nil,
            strokeStyle: StrokeStyle? = nil,
            image: ImageRecord? = nil,
            text: TextRecord? = nil,
            custom: CustomRecord? = nil,
            opacity: Double? = nil,
            blurRadius: CGFloat? = nil,
            blurIsOpaque: Bool? = nil,
            affineTransform: CGAffineTransform? = nil,
            sourceFraction: Float? = nil,
            targetFraction: Float? = nil,
            blendMode: BlendMode? = nil,
            shadow: ShadowRecord? = nil,
            colorFilter: ColorFilterRecord? = nil
        ) {
            self.kind = kind
            self.effectKind = kind == .effect ? effectKind ?? .generic : nil
            self.bounds = bounds
            if kind == .shapeFill || kind == .shapeStroke || kind == .shapeSeparator {
                self.shapeStyle = shapeStyle
            } else {
                self.shapeStyle = nil
            }
            if kind == .shapeFill || kind == .shapeSeparator {
                self.fillStyle = fillStyle
            } else {
                self.fillStyle = nil
            }
            if kind == .shapeStroke {
                self.strokeStyle = strokeStyle
            } else {
                self.strokeStyle = nil
            }
            if kind == .image {
                self.image = image
            } else {
                self.image = nil
            }
            if kind == .text {
                self.text = text
            } else {
                self.text = nil
            }
            if kind == .custom {
                self.custom = custom
            } else {
                self.custom = nil
            }
            if kind == .effect && effectKind == .opacity {
                self.opacity = opacity
            } else {
                self.opacity = nil
            }
            if kind == .effect && effectKind == .blur {
                self.blurRadius = blurRadius
                self.blurIsOpaque = blurIsOpaque
            } else {
                self.blurRadius = nil
                self.blurIsOpaque = nil
            }
            if kind == .effect && effectKind == .geometry {
                self.affineTransform = affineTransform
            } else {
                self.affineTransform = nil
            }
            if kind == .effect && effectKind == .crossFade {
                self.sourceFraction = sourceFraction
                self.targetFraction = targetFraction
            } else {
                self.sourceFraction = nil
                self.targetFraction = nil
            }
            if kind == .effect && effectKind == .blendMode {
                self.blendMode = blendMode
            } else {
                self.blendMode = nil
            }
            if kind == .effect && effectKind == .shadow {
                self.shadow = shadow
            } else {
                self.shadow = nil
            }
            if kind == .effect && effectKind == .colorFilter {
                self.colorFilter = colorFilter
            } else {
                self.colorFilter = nil
            }
        }
    }

    enum ItemCommand: Equatable {
        enum EffectCommand: Equatable {
            case generic
            case opacity(Double)
            case blur(radius: CGFloat, isOpaque: Bool)
            case geometry(CGAffineTransform)
            case crossFade(sourceFraction: Float, targetFraction: Float)
            case blendMode(BlendMode)
            case shadow(ItemRecord.ShadowRecord)
            case colorFilter(ItemRecord.ColorFilterRecord)
        }

        case closure(bounds: CGRect?)
        case shape(
            role: ShapeRole,
            style: ItemRecord.ShapeStyleRecord?,
            fillStyle: FillStyle?,
            strokeStyle: StrokeStyle?,
            bounds: CGRect?
        )
        case image(ItemRecord.ImageRecord, bounds: CGRect?)
        case text(ItemRecord.TextRecord, bounds: CGRect?)
        case custom(ItemRecord.CustomRecord, bounds: CGRect?)
        case effect(EffectCommand, bounds: CGRect?)
        case debug(bounds: CGRect?)

        var record: ItemRecord {
            switch self {
            case let .closure(bounds):
                return ItemRecord(kind: .closure, bounds: bounds)
            case let .shape(role, style, fillStyle, strokeStyle, bounds):
                return ItemRecord(
                    kind: DisplayList.itemRecordKind(for: role),
                    bounds: bounds,
                    shapeStyle: style,
                    fillStyle: fillStyle,
                    strokeStyle: strokeStyle
                )
            case let .image(image, bounds):
                return ItemRecord(kind: .image, bounds: bounds, image: image)
            case let .text(text, bounds):
                return ItemRecord(kind: .text, bounds: bounds, text: text)
            case let .custom(custom, bounds):
                return ItemRecord(kind: .custom, bounds: bounds, custom: custom)
            case let .effect(effect, bounds):
                switch effect {
                case .generic:
                    return ItemRecord(kind: .effect, bounds: bounds, effectKind: .generic)
                case let .opacity(opacity):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .opacity,
                        opacity: opacity
                    )
                case let .blur(radius, isOpaque):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .blur,
                        blurRadius: radius,
                        blurIsOpaque: isOpaque
                    )
                case let .geometry(transform):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .geometry,
                        affineTransform: transform
                    )
                case let .crossFade(sourceFraction, targetFraction):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .crossFade,
                        sourceFraction: sourceFraction,
                        targetFraction: targetFraction
                    )
                case let .blendMode(blendMode):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .blendMode,
                        blendMode: blendMode
                    )
                case let .shadow(shadow):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .shadow,
                        shadow: shadow
                    )
                case let .colorFilter(filter):
                    return ItemRecord(
                        kind: .effect,
                        bounds: bounds,
                        effectKind: .colorFilter,
                        colorFilter: filter
                    )
                }
            case let .debug(bounds):
                return ItemRecord(kind: .debug, bounds: bounds)
            }
        }

        var bounds: CGRect? {
            switch self {
            case let .closure(bounds),
                 let .shape(_, _, _, _, bounds),
                 let .image(_, bounds),
                 let .text(_, bounds),
                 let .custom(_, bounds),
                 let .effect(_, bounds),
                 let .debug(bounds):
                return bounds
            }
        }
    }

    struct Content {
        // Typed drawing payloads retain their source geometry and accumulate replay transforms.
        // This keeps later interpolation and renderer passes from recovering state from closures.
        struct ShapeValue {
            var path: Path
            var shading: GraphicsContext.Shading
            var fillStyle: FillStyle
            var strokeStyle: StrokeStyle?
            var transform: CGAffineTransform
            var command: ItemCommand

            func draw(in context: GraphicsContext) {
                var context = context
                if !transform.isIdentity {
                    context.concatenate(transform)
                }
                guard case let .shape(role, _, _, _, _) = command else {
                    preconditionFailure("DisplayList.ShapeValue requires a shape command")
                }
                switch role {
                case .stroke:
                    guard let strokeStyle else { return }
                    context.stroke(path, with: shading, style: strokeStyle)
                case .fill, .separator:
                    context.fill(path, with: shading, style: fillStyle)
                }
            }

            func transformed(
                command: ItemCommand,
                by affineTransform: CGAffineTransform
            ) -> Self {
                var copy = self
                copy.command = command
                copy.transform = transform.concatenating(affineTransform)
                return copy
            }
        }

        struct ImageValue {
            var image: GraphicsContext.ResolvedImage
            var frame: CGRect
            var transform: CGAffineTransform
            var command: ItemCommand

            func draw(in context: GraphicsContext) {
                guard frame.width > 0, frame.height > 0 else { return }
                var context = context
                if let coverageBounds = command.bounds,
                   coverageBounds != frame {
                    context.clip(to: Path(coverageBounds))
                }
                if !transform.isIdentity {
                    context.concatenate(transform)
                }
                context.draw(image, in: frame)
            }

            func transformed(
                command: ItemCommand,
                by affineTransform: CGAffineTransform
            ) -> Self {
                var copy = self
                copy.command = command
                copy.transform = transform.concatenating(affineTransform)
                return copy
            }
        }

        struct StyleValue {
            enum Style {
                case opacity(Double)
                case blur(radius: CGFloat, isOpaque: Bool)
                case blendMode(BlendMode)
                case shadow(ItemRecord.ShadowRecord, GraphicsContext.Filter)
                case colorFilter(ItemRecord.ColorFilterRecord, GraphicsContext.Filter)
            }

            var style: Style
            var contents: DisplayList
            var transform: CGAffineTransform
            var command: ItemCommand

            func draw(in context: GraphicsContext) {
                draw(in: context) { contents, context in
                    for item in contents.items {
                        item(context)
                    }
                }
            }

            func draw(
                in context: GraphicsContext,
                replayContents: (DisplayList, GraphicsContext) -> Void
            ) {
                // Nested style contents must replay through the caller's renderer so animation
                // sampling, identity traversal, and callback caches remain in one render pass.
                var context = context
                if !transform.isIdentity {
                    context.concatenate(transform)
                }
                switch style {
                case let .opacity(opacity):
                    guard opacity > 0 else { return }
                    context.opacity *= opacity
                    guard context.opacity > 0 else { return }
                    context.drawLayer { layer in
                        replayContents(contents, layer)
                    }
                case let .blur(radius, isOpaque):
                    context.drawLayer { layer in
                        let options: GraphicsContext.BlurOptions = isOpaque ? .opaque : []
                        layer.addFilter(.blur(radius: radius, options: options))
                        replayContents(contents, layer)
                    }
                case let .blendMode(blendMode):
                    context.blendMode = blendMode.graphicsContextBlendMode
                    context.drawLayer { layer in
                        replayContents(contents, layer)
                    }
                case let .shadow(_, filter), let .colorFilter(_, filter):
                    context.drawLayer { layer in
                        layer.addFilter(filter)
                        replayContents(contents, layer)
                    }
                }
            }

            func transformed(
                command: ItemCommand,
                by affineTransform: CGAffineTransform
            ) -> Self {
                var copy = self
                copy.command = command
                copy.transform = transform.concatenating(affineTransform)
                return copy
            }
        }

        struct CrossFadeValue {
            struct Branch {
                var contents: DisplayList
                var sourceBounds: CGRect
                var outputBounds: CGRect

                func draw(
                    opacity: Double,
                    in context: GraphicsContext,
                    replayContents: (DisplayList, GraphicsContext) -> Void
                ) {
                    guard opacity > 0,
                          let transform = Self.interpolationTransform(
                            from: sourceBounds,
                            to: outputBounds
                          ) else {
                        return
                    }

                    var context = context
                    context.opacity *= opacity
                    guard context.opacity > 0 else { return }
                    context.concatenate(transform)
                    replayContents(contents, context)
                }

                static func interpolationTransform(
                    from sourceBounds: CGRect,
                    to outputBounds: CGRect
                ) -> CGAffineTransform? {
                    guard sourceBounds.width.magnitude > .ulpOfOne,
                          sourceBounds.height.magnitude > .ulpOfOne else {
                        return nil
                    }
                    let scaleX = outputBounds.width / sourceBounds.width
                    let scaleY = outputBounds.height / sourceBounds.height
                    return CGAffineTransform(
                        a: scaleX,
                        b: 0,
                        c: 0,
                        d: scaleY,
                        tx: outputBounds.minX - sourceBounds.minX * scaleX,
                        ty: outputBounds.minY - sourceBounds.minY * scaleY
                    )
                }
            }

            var source: Branch?
            var target: Branch?
            var transform: CGAffineTransform
            var command: ItemCommand

            func draw(in context: GraphicsContext) {
                draw(in: context) { contents, context in
                    for item in contents.items {
                        item(context)
                    }
                }
            }

            func draw(
                in context: GraphicsContext,
                replayContents: (DisplayList, GraphicsContext) -> Void
            ) {
                guard case let .effect(
                    .crossFade(sourceFraction, targetFraction),
                    _
                ) = command else {
                    preconditionFailure("DisplayList.CrossFadeValue requires a cross-fade command")
                }
                let sourceOpacity = 1 - Double(sourceFraction)
                let targetOpacity = Double(targetFraction)
                guard (source != nil && sourceOpacity > 0) ||
                        (target != nil && targetOpacity > 0) else {
                    return
                }

                var context = context
                if !transform.isIdentity {
                    context.concatenate(transform)
                }
                // Both branches share one temporary layer. Their complementary alpha values
                // remain local to the branch while clip and outer transform state stay joined.
                context.drawLayer { layer in
                    source?.draw(
                        opacity: sourceOpacity,
                        in: layer,
                        replayContents: replayContents
                    )
                    target?.draw(
                        opacity: targetOpacity,
                        in: layer,
                        replayContents: replayContents
                    )
                }
            }

            func transformed(
                command: ItemCommand,
                by affineTransform: CGAffineTransform
            ) -> Self {
                var copy = self
                copy.command = command
                copy.transform = transform.concatenating(affineTransform)
                return copy
            }

        }

        struct TextValue {
            var view: StyledTextContentView
            var size: CGSize
            var frame: CGRect
            var shading: GraphicsContext.Shading
            var transform: CGAffineTransform
            var command: ItemCommand

            func makeDrawing() -> GraphicsContext.ResolvedText.Drawing? {
                guard view.renderer == nil else { return nil }
                return view.text.resolvedText?.makeDrawing(
                    in: size,
                    layoutProperties: view.text.layoutProperties
                )
            }

            func glyphAtoms() -> [GraphicsContext.ResolvedText.GlyphAtom]? {
                guard view.renderer == nil,
                      let resolvedText = view.text.resolvedText else {
                    return nil
                }
                return resolvedText.glyphAtoms(
                    in: size,
                    layoutProperties: view.text.layoutProperties
                ).map { atom in
                    var atom = atom
                    atom.bounds = atom.bounds
                        .offsetBy(dx: frame.minX, dy: frame.minY)
                        .applying(transform)
                        .standardized
                    return atom
                }
            }

            func draw(in context: GraphicsContext) {
                guard let resolvedText = view.text.resolvedText else { return }
                var context = context
                if !transform.isIdentity {
                    context.concatenate(transform)
                }
                if let renderer = view.renderer {
                    context.environment = renderer.environment
                    context.translateBy(x: frame.minX, y: frame.minY)
                    var source = resolvedText
                    source.shading = shading
                    let bounds = renderer.textLayoutBounds(size: size, text: TextProxy(source))
                    let layout = source.makeLayout(
                        in: bounds.size,
                        layoutDirection: context.environment.layoutDirection,
                        layoutProperties: view.text.layoutProperties
                    )
                    renderer.draw(layout: layout, in: &context)
                } else {
                    context.draw(
                        resolvedText,
                        in: frame,
                        shading: shading,
                        layoutProperties: view.text.layoutProperties
                    )
                }
            }

            func draw(
                _ drawing: GraphicsContext.ResolvedText.Drawing,
                in context: GraphicsContext
            ) {
                var context = context
                if !transform.isIdentity {
                    context.concatenate(transform)
                }
                context.draw(drawing, in: frame, shading: shading)
            }

            func transformed(
                command: ItemCommand,
                by affineTransform: CGAffineTransform
            ) -> Self {
                var copy = self
                copy.command = command
                copy.transform = transform.concatenating(affineTransform)
                return copy
            }
        }

        enum Value {
            case backend(ItemCommand, (GraphicsContext) -> Void)
            case color(ColorView)
            case shape(ShapeValue)
            case image(ImageValue)
            case style(StyleValue)
            case crossFade(CrossFadeValue)
            case text(TextValue)
            case flattened(DisplayList, CGPoint, RasterizationOptions)
            case drawing(any RBDisplayListContents, CGPoint, RasterizationOptions)
        }

        var value: Value
        var seed: Seed
        // Backend-local snapshot used when replaying flattened view content.
        // Nil means that synthetic content inherits the enclosing context.
        var environment: EnvironmentValues?

        init(
            command: ItemCommand,
            seed: Seed = Seed(),
            environment: EnvironmentValues? = nil,
            body: @escaping (GraphicsContext) -> Void
        ) {
            self.value = .backend(command, body)
            self.seed = seed
            self.environment = environment
        }

        init(
            path: Path,
            shading: GraphicsContext.Shading,
            fillStyle: FillStyle,
            strokeStyle: StrokeStyle?,
            command: ItemCommand,
            seed: Seed = Seed(),
            environment: EnvironmentValues? = nil
        ) {
            self.value = .shape(ShapeValue(
                path: path,
                shading: shading,
                fillStyle: fillStyle,
                strokeStyle: strokeStyle,
                transform: .identity,
                command: command
            ))
            self.seed = seed
            self.environment = environment
        }

        init(
            image: GraphicsContext.ResolvedImage,
            frame: CGRect,
            command: ItemCommand,
            seed: Seed = Seed(),
            environment: EnvironmentValues? = nil
        ) {
            self.value = .image(ImageValue(
                image: image,
                frame: frame,
                transform: .identity,
                command: command
            ))
            self.seed = seed
            self.environment = environment
        }

        init(
            style: StyleValue.Style,
            contents: DisplayList,
            command: ItemCommand,
            seed: Seed = Seed(),
            environment: EnvironmentValues? = nil
        ) {
            self.value = .style(StyleValue(
                style: style,
                contents: contents,
                transform: .identity,
                command: command
            ))
            self.seed = seed
            self.environment = environment
        }

        init(
            source: CrossFadeValue.Branch?,
            target: CrossFadeValue.Branch?,
            command: ItemCommand,
            seed: Seed = Seed(),
            environment: EnvironmentValues? = nil
        ) {
            self.value = .crossFade(CrossFadeValue(
                source: source,
                target: target,
                transform: .identity,
                command: command
            ))
            self.seed = seed
            self.environment = environment
        }

        init(
            text: StyledTextContentView,
            size: CGSize,
            frame: CGRect,
            shading: GraphicsContext.Shading,
            command: ItemCommand,
            seed: Seed,
            environment: EnvironmentValues? = nil
        ) {
            self.value = .text(TextValue(
                view: text,
                size: size,
                frame: frame,
                shading: shading,
                transform: .identity,
                command: command
            ))
            self.seed = seed
            self.environment = environment
        }

        init(
            flattened list: DisplayList,
            origin: CGPoint,
            options: RasterizationOptions,
            seed: Seed = Seed()
        ) {
            self.value = .flattened(list, origin, options)
            self.seed = seed
            self.environment = nil
        }

        init(
            drawing: any RBDisplayListContents,
            origin: CGPoint,
            options: RasterizationOptions,
            seed: Seed = Seed()
        ) {
            self.value = .drawing(drawing, origin, options)
            self.seed = seed
            self.environment = nil
        }

        var command: ItemCommand {
            switch value {
            case let .backend(command, _):
                return command
            case .color:
                return .closure(bounds: nil)
            case let .shape(shape):
                return shape.command
            case let .image(image):
                return image.command
            case let .style(style):
                return style.command
            case let .crossFade(crossFade):
                return crossFade.command
            case let .text(text):
                return text.command
            case let .flattened(list, origin, _):
                return .closure(bounds: list.interpolationBounds.map {
                    $0.offsetBy(dx: origin.x, dy: origin.y)
                })
            case let .drawing(contents, origin, _):
                let list = (contents as? LocalContents)?.list
                return .closure(bounds: list?.interpolationBounds.map {
                    $0.offsetBy(dx: origin.x, dy: origin.y)
                })
            }
        }

        func renderContext(from context: GraphicsContext) -> GraphicsContext {
            guard let environment else { return context }
            var context = context
            context.environment = environment
            return context
        }

        func draw(in context: GraphicsContext) {
            let context = renderContext(from: context)
            switch value {
            case let .backend(_, body):
                body(context)
            case .color:
                break
            case let .shape(shape):
                shape.draw(in: context)
            case let .image(image):
                image.draw(in: context)
            case let .style(style):
                style.draw(in: context)
            case let .crossFade(crossFade):
                crossFade.draw(in: context)
            case let .text(text):
                text.draw(in: context)
            case let .flattened(list, origin, _):
                var context = context
                context.translateBy(x: origin.x, y: origin.y)
                list.draw(in: context)
            case let .drawing(contents, origin, _):
                guard let list = (contents as? LocalContents)?.list else { return }
                var context = context
                context.translateBy(x: origin.x, y: origin.y)
                list.draw(in: context)
            }
        }

        func transformed(by affineTransform: CGAffineTransform) -> Content {
            let transformedCommand = command.transformed(by: affineTransform)
            switch value {
            case .backend:
                return Content(
                    command: transformedCommand,
                    seed: seed,
                    environment: environment
                ) { context in
                    var context = context
                    context.concatenate(affineTransform)
                    self.draw(in: context)
                }
            case .color:
                return self
            case let .shape(shape):
                var copy = self
                copy.value = .shape(shape.transformed(
                    command: transformedCommand,
                    by: affineTransform
                ))
                return copy
            case let .image(image):
                var copy = self
                copy.value = .image(image.transformed(
                    command: transformedCommand,
                    by: affineTransform
                ))
                return copy
            case let .style(style):
                var copy = self
                copy.value = .style(style.transformed(
                    command: transformedCommand,
                    by: affineTransform
                ))
                return copy
            case let .crossFade(crossFade):
                var copy = self
                copy.value = .crossFade(crossFade.transformed(
                    command: transformedCommand,
                    by: affineTransform
                ))
                return copy
            case let .text(text):
                var copy = self
                copy.value = .text(text.transformed(
                    command: transformedCommand,
                    by: affineTransform
                ))
                return copy
            case let .flattened(list, origin, options):
                var copy = self
                let transformedOrigin = origin.applying(affineTransform)
                copy.value = .flattened(list, transformedOrigin, options)
                return copy
            case let .drawing(contents, origin, options):
                var copy = self
                let transformedOrigin = origin.applying(affineTransform)
                copy.value = .drawing(contents, transformedOrigin, options)
                return copy
            }
        }

    }

    struct Item: Equatable, CustomStringConvertible {
        enum Value {
            case content(Content)
            case effect(Effect, DisplayList)
            case states([(StrongHash, DisplayList)])
            case empty
        }

        var frame: CGRect
        var version: Version
        var value: Value
        var identity: _DisplayList_Identity
        var opacity: Float
        var styleChain = StyleChain()

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.identity == rhs.identity && lhs.version == rhs.version
        }

        var description: String {
            "(display-list-item \(identity) \(version.value))"
        }

        init() {
            self.frame = .zero
            self.version = Version()
            self.value = .empty
            self.identity = .none
            self.opacity = 1
        }

        init(
            command: ItemCommand,
            identity: _DisplayList_Identity = .none,
            version: Version = Version(value: 0),
            seed: Seed = Seed(),
            opacity: Float = 1,
            environment: EnvironmentValues? = nil,
            _ body: @escaping (GraphicsContext) -> Void
        ) {
            self.frame = command.bounds ?? .zero
            self.version = version
            self.value = .content(Content(
                command: command,
                seed: seed,
                environment: environment,
                body: body
            ))
            self.identity = identity
            self.opacity = opacity
        }

        init(
            effect: Effect,
            contents: DisplayList,
            frame: CGRect? = nil,
            identity: _DisplayList_Identity = .none,
            version: Version = Version(value: 0),
            opacity: Float = 1
        ) {
            self.frame = frame ?? contents.interpolationBounds ?? .zero
            self.version = version
            self.value = .effect(effect, contents)
            self.identity = identity
            self.opacity = opacity
        }

        init(
            path: Path,
            shading: GraphicsContext.Shading,
            fillStyle: FillStyle,
            strokeStyle: StrokeStyle?,
            command: ItemCommand,
            environment: EnvironmentValues? = nil,
            identity: _DisplayList_Identity = .none,
            version: Version = Version(value: 0),
            opacity: Float = 1
        ) {
            self.frame = command.bounds ?? .zero
            self.version = version
            self.value = .content(Content(
                path: path,
                shading: shading,
                fillStyle: fillStyle,
                strokeStyle: strokeStyle,
                command: command,
                environment: environment
            ))
            self.identity = identity
            self.opacity = opacity
        }

        init(
            image: GraphicsContext.ResolvedImage,
            frame: CGRect,
            command: ItemCommand,
            environment: EnvironmentValues? = nil,
            identity: _DisplayList_Identity = .none,
            version: Version = Version(value: 0),
            opacity: Float = 1
        ) {
            self.frame = command.bounds ?? frame
            self.version = version
            self.value = .content(Content(
                image: image,
                frame: frame,
                command: command,
                environment: environment
            ))
            self.identity = identity
            self.opacity = opacity
        }

        init(
            style: Content.StyleValue.Style,
            contents: DisplayList,
            command: ItemCommand,
            environment: EnvironmentValues? = nil,
            identity: _DisplayList_Identity = .none,
            version: Version = Version(value: 0),
            opacity: Float = 1
        ) {
            self.frame = command.bounds ?? contents.interpolationBounds ?? .zero
            self.version = version
            self.value = .content(Content(
                style: style,
                contents: contents,
                command: command,
                environment: environment
            ))
            self.identity = identity
            self.opacity = opacity
        }

        init(
            source: Content.CrossFadeValue.Branch?,
            target: Content.CrossFadeValue.Branch?,
            command: ItemCommand,
            environment: EnvironmentValues? = nil,
            identity: _DisplayList_Identity = .none,
            version: Version = Version(value: 0),
            opacity: Float = 1
        ) {
            self.frame = command.bounds ?? .zero
            self.version = version
            self.value = .content(Content(
                source: source,
                target: target,
                command: command,
                environment: environment
            ))
            self.identity = identity
            self.opacity = opacity
        }

        init(
            text: StyledTextContentView,
            size: CGSize,
            frame: CGRect,
            shading: GraphicsContext.Shading,
            command: ItemCommand,
            seed: Seed,
            environment: EnvironmentValues? = nil,
            identity: _DisplayList_Identity = .none,
            version: Version = Version(),
            opacity: Float = 1
        ) {
            self.frame = command.bounds ?? frame
            self.version = version
            self.value = .content(Content(
                text: text,
                size: size,
                frame: frame,
                shading: shading,
                command: command,
                seed: seed,
                environment: environment
            ))
            self.identity = identity
            self.opacity = opacity
        }

        init(
            content: Content,
            frame: CGRect,
            identity: _DisplayList_Identity,
            version: Version,
            opacity: Float = 1,
            styleChain: StyleChain = StyleChain()
        ) {
            self.frame = frame
            self.version = version
            self.value = .content(content)
            self.identity = identity
            self.opacity = opacity
            self.styleChain = styleChain
        }

        var command: ItemCommand {
            guard case let .content(content) = value else {
                preconditionFailure("DisplayList.Item.command requires content")
            }
            return content.command
        }

        var record: ItemRecord {
            command.record
        }

        var effectItem: EffectItem? {
            guard case let .effect(effect, contents) = value else { return nil }
            return EffectItem(
                effect: effect,
                contents: contents,
                frame: frame,
                identity: identity,
                version: version,
                opacity: opacity,
                styleChain: styleChain
            )
        }

        mutating func addEffect(_ effect: DisplayList.Effect) {
            var child = self
            child.frame.origin = .zero

            var contents = DisplayList()
            contents.items.append(child)
            contents.interpolationBounds = child.frame
            value = .effect(effect, contents)
        }

        mutating func canonicalize(options: DisplayList.Options) {
            guard !options.contains(.disableCanonicalization),
                  case let .effect(.identity, contents) = value,
                  contents.items.count == 1,
                  contents.debugItems.isEmpty,
                  let child = contents.items.first else {
                return
            }

            frame = CGRect(
                origin: CGPoint(
                    x: frame.origin.x + child.frame.origin.x,
                    y: frame.origin.y + child.frame.origin.y
                ),
                size: child.frame.size
            )
            version.combine(with: child.version)
            value = child.value
            if child.identity != .none {
                identity = child.identity
            }
            opacity *= child.opacity
            styleChain = child.styleChain.appendingOuter(styleChain)
        }

        func presentationContext(from context: GraphicsContext) -> GraphicsContext {
            let offset: CGSize
            switch value {
            case let .content(content):
                guard let recordedBounds = content.command.bounds,
                      !recordedBounds.isNull else {
                    return context
                }
                offset = CGSize(
                    width: frame.origin.x - recordedBounds.origin.x,
                    height: frame.origin.y - recordedBounds.origin.y
                )
            case .effect:
                // Effect contents remain in their own local coordinate space.
                // The outer frame is the placement applied before replaying them.
                offset = CGSize(
                    width: frame.origin.x,
                    height: frame.origin.y
                )
            case let .states(states):
                guard let recordedBounds = states.last?.1.interpolationBounds,
                      !recordedBounds.isNull else {
                    return context
                }
                offset = CGSize(
                    width: frame.origin.x - recordedBounds.origin.x,
                    height: frame.origin.y - recordedBounds.origin.y
                )
            case .empty:
                return context
            }
            guard offset.width != 0 || offset.height != 0 else {
                return context
            }
            var context = context
            context.translateBy(x: offset.width, y: offset.height)
            return context
        }

        func callAsFunction(_ context: GraphicsContext) {
            var context = presentationContext(from: context)
            context.opacity *= Double(opacity)
            guard context.opacity > 0 else { return }
            switch value {
            case let .content(content):
                content.draw(in: context)
            case let .effect(_, contents):
                contents.draw(in: context)
            case let .states(states):
                states.last?.1.draw(in: context)
            case .empty:
                break
            }
        }
    }

    var items: [Item] = []
    var debugItems: [Item] = []
    private var activeStyleChain = StyleChain()
    // Backend-local bounds used by display-list interpolation before exact private command storage exists.
    var interpolationBounds: CGRect?
    // Numeric metadata consumed by content-transition matching and direction selection.
    var numericValue: Float? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items == rhs.items
    }

    var description: String {
        guard !items.isEmpty else {
            return "(display-list)"
        }
        return "(display-list \(items.map(\.description).joined(separator: " ")))"
    }

    var itemRecords: [ItemRecord] {
        renderItems.map(\.record)
    }

    var debugItemRecords: [ItemRecord] {
        debugItems.map(\.record)
    }

    var itemCommands: [ItemCommand] {
        renderItems.map(\.command)
    }

    var debugItemCommands: [ItemCommand] {
        debugItems.map(\.command)
    }

    var renderItems: [Item] {
        items.filter {
            if case .content = $0.value { return true }
            return false
        }
    }

    var renderItemList: DisplayList {
        // Modifier styles wrap only ordinary render items. Graph effects stay at their original
        // level and are recursively rewritten by the modifier before this list is constructed.
        var list = DisplayList()
        list.items = renderItems
        list.recordInterpolationBounds(interpolationBounds)
        return list
    }

    var effects: [EffectItem] {
        items.compactMap(\.effectItem)
    }

    mutating func append(contentsOf other: Self) {
        self.items.append(contentsOf: other.items.map(applyingActiveStyles(to:)))
        self.debugItems.append(contentsOf: other.debugItems.map(applyingActiveStyles(to:)))
        self.recordInterpolationBounds(other.interpolationBounds)
    }

    private func applyingActiveStyles(to item: Item) -> Item {
        var item = item
        item.styleChain = item.styleChain.appendingOuter(activeStyleChain)
        return item
    }

    private mutating func appendRecordedItem(_ item: Item) {
        items.append(applyingActiveStyles(to: item))
    }

    private mutating func appendRecordedDebugItem(_ item: Item) {
        debugItems.append(applyingActiveStyles(to: item))
    }

    mutating func appendItem(
        kind: ItemRecord.Kind = .closure,
        bounds: CGRect? = nil,
        effectKind: ItemRecord.EffectKind? = nil,
        environment: EnvironmentValues? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = Self.itemCommand(
            kind: kind,
            bounds: bounds,
            effectKind: effectKind
        )
        appendRecordedItem(Item(command: command, environment: environment, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShapeItem(
        role: ShapeRole,
        bounds: CGRect? = nil,
        fillStyle: FillStyle? = nil,
        strokeStyle: StrokeStyle? = nil,
        environment: EnvironmentValues? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let isStroke = role == .stroke
        let command = ItemCommand.shape(
            role: role,
            style: nil,
            fillStyle: isStroke ? nil : fillStyle,
            strokeStyle: isStroke ? strokeStyle : nil,
            bounds: bounds
        )
        appendRecordedItem(Item(command: command, environment: environment, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShapeItem<S: ShapeStyle>(
        role: ShapeRole,
        style: S,
        bounds: CGRect? = nil,
        fillStyle: FillStyle? = nil,
        strokeStyle: StrokeStyle? = nil,
        environment: EnvironmentValues? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let isStroke = role == .stroke
        let command = ItemCommand.shape(
            role: role,
            style: Self.shapeStyleRecord(
                for: style,
                environment: environment ?? EnvironmentValues(),
                role: role
            ),
            fillStyle: isStroke ? nil : fillStyle,
            strokeStyle: isStroke ? strokeStyle : nil,
            bounds: bounds
        )
        appendRecordedItem(Item(command: command, environment: environment, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShapeItem<S: ShapeStyle>(
        path: Path,
        role: ShapeRole,
        style: S,
        bounds: CGRect? = nil,
        fillStyle: FillStyle = FillStyle(),
        strokeStyle: StrokeStyle? = nil,
        environment: EnvironmentValues? = nil
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let isStroke = role == .stroke
        let command = ItemCommand.shape(
            role: role,
            style: Self.shapeStyleRecord(
                for: style,
                environment: environment ?? EnvironmentValues(),
                role: role
            ),
            fillStyle: isStroke ? nil : fillStyle,
            strokeStyle: isStroke ? strokeStyle : nil,
            bounds: bounds
        )
        appendRecordedItem(Item(
            path: path,
            shading: .style(style),
            fillStyle: fillStyle,
            strokeStyle: isStroke ? strokeStyle : nil,
            command: command,
            environment: environment
        ))
        recordInterpolationBounds(bounds)
    }

    mutating func appendImageItem(
        _ image: GraphicsContext.ResolvedImage,
        bounds: CGRect? = nil,
        opacity: Float = 1,
        environment: EnvironmentValues? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.image(
            ItemRecord.ImageRecord(
                image,
                placementRect: bounds ?? .zero,
                shading: image.shading.flatMap(Self.shadingRecord(for:))
            ),
            bounds: bounds
        )
        appendRecordedItem(Item(
            command: command,
            opacity: opacity,
            environment: environment,
            item
        ))
        recordInterpolationBounds(bounds)
    }

    mutating func appendImageItem(
        _ image: GraphicsContext.ResolvedImage,
        bounds: CGRect,
        placementRect: CGRect? = nil,
        opacity: Float = 1,
        version: Version = Version(),
        environment: EnvironmentValues? = nil
    ) {
        let commandBounds = Self.itemRecordBounds(bounds)
        let placementRect = placementRect ?? bounds
        let command = ItemCommand.image(
            ItemRecord.ImageRecord(
                image,
                placementRect: placementRect,
                shading: image.shading.flatMap(Self.shadingRecord(for:))
            ),
            bounds: commandBounds
        )
        appendRecordedItem(Item(
            image: image,
            frame: placementRect,
            command: command,
            environment: environment,
            version: version,
            opacity: opacity
        ))
        recordInterpolationBounds(commandBounds)
    }

    mutating func appendTextItem(
        foreground: GraphicsContext.Shading,
        bounds: CGRect? = nil,
        environment: EnvironmentValues? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.text(
            ItemRecord.TextRecord(
                foreground: Self.shadingRecord(for: foreground)
            ),
            bounds: bounds
        )
        appendRecordedItem(Item(command: command, environment: environment, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendTextItem(
        _ text: StyledTextContentView,
        size: CGSize,
        foreground: GraphicsContext.Shading,
        bounds: CGRect,
        displayBounds: CGRect? = nil,
        seed: Seed,
        version: Version = Version(),
        environment: EnvironmentValues? = nil
    ) {
        guard let bounds = Self.itemRecordBounds(bounds) else { return }
        let commandBounds = Self.itemRecordBounds(displayBounds ?? bounds) ?? bounds
        let command = ItemCommand.text(
            ItemRecord.TextRecord(
                foreground: Self.shadingRecord(for: foreground)
            ),
            bounds: commandBounds
        )
        appendRecordedItem(Item(
            text: text,
            size: size,
            frame: bounds,
            shading: foreground,
            command: command,
            seed: seed,
            environment: environment,
            version: version
        ))
        recordInterpolationBounds(commandBounds)
    }

    mutating func appendCustomItem(
        bounds: CGRect? = nil,
        isOpaque: Bool,
        colorMode: ColorRenderingMode,
        rendersAsynchronously: Bool,
        environment: EnvironmentValues? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.custom(
            ItemRecord.CustomRecord(
                isOpaque: isOpaque,
                colorMode: colorMode,
                rendersAsynchronously: rendersAsynchronously
            ),
            bounds: bounds
        )
        appendRecordedItem(Item(command: command, environment: environment, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendOpacityItem(
        bounds: CGRect? = nil,
        opacity: Double,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.opacity(opacity), bounds: bounds)
        appendRecordedItem(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendOpacityItem(
        bounds: CGRect? = nil,
        opacity: Double,
        contents: DisplayList
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.opacity(opacity), bounds: bounds)
        appendRecordedItem(Item(
            style: .opacity(opacity),
            contents: contents,
            command: command
        ))
        recordInterpolationBounds(bounds)
    }

    mutating func appendBlurItem(
        bounds: CGRect? = nil,
        radius: CGFloat,
        isOpaque: Bool,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(
            .blur(radius: radius, isOpaque: isOpaque),
            bounds: bounds
        )
        appendRecordedItem(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendBlurItem(
        bounds: CGRect? = nil,
        radius: CGFloat,
        isOpaque: Bool,
        contents: DisplayList
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(
            .blur(radius: radius, isOpaque: isOpaque),
            bounds: bounds
        )
        appendRecordedItem(Item(
            style: .blur(radius: radius, isOpaque: isOpaque),
            contents: contents,
            command: command
        ))
        recordInterpolationBounds(bounds)
    }

    mutating func appendGeometryItem(
        bounds: CGRect? = nil,
        affineTransform: CGAffineTransform,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.geometry(affineTransform), bounds: bounds)
        appendRecordedItem(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendTransformedItem(
        _ item: Item,
        affineTransform: CGAffineTransform
    ) {
        guard case let .content(content) = item.value else {
            preconditionFailure("DisplayList transformed items require content")
        }
        let transformedContent = content.transformed(by: affineTransform)
        let frame = transformedContent.command.bounds ?? item.frame.applying(affineTransform)
        appendRecordedItem(Item(
            content: transformedContent,
            frame: frame,
            identity: item.identity,
            version: item.version,
            opacity: item.opacity,
            styleChain: item.styleChain
        ))
        recordInterpolationBounds(transformedContent.command.bounds)
    }

    mutating func appendTransformedDebugItem(
        _ item: Item,
        affineTransform: CGAffineTransform
    ) {
        guard case let .content(content) = item.value else {
            preconditionFailure("DisplayList transformed debug items require content")
        }
        let transformedContent = content.transformed(by: affineTransform)
        let frame = transformedContent.command.bounds ?? item.frame.applying(affineTransform)
        appendRecordedDebugItem(Item(
            content: transformedContent,
            frame: frame,
            identity: item.identity,
            version: item.version,
            opacity: item.opacity,
            styleChain: item.styleChain
        ))
        recordInterpolationBounds(transformedContent.command.bounds)
    }

    func translated(by offset: CGSize) -> DisplayList {
        guard offset.width != 0 || offset.height != 0 else {
            return self
        }

        return transformed(by: CGAffineTransform(
            translationX: offset.width,
            y: offset.height
        ))
    }

    func transformed(by transform: CGAffineTransform) -> DisplayList {
        guard !transform.isIdentity else {
            return self
        }

        var result = DisplayList()
        result.items = items.map { item in
            var item = item
            item.frame = item.frame.applying(transform)
            switch item.value {
            case let .content(content):
                item.value = .content(content.transformed(by: transform))
            case let .effect(effect, contents):
                let translatedEffect: Effect
                if case let .mask(mask, options) = effect {
                    translatedEffect = .mask(
                        mask.transformed(by: transform),
                        options
                    )
                } else {
                    translatedEffect = effect
                }
                item.value = .effect(
                    translatedEffect,
                    contents.transformed(by: transform)
                )
            case let .states(states):
                item.value = .states(states.map { hash, contents in
                    (hash, contents.transformed(by: transform))
                })
            case .empty:
                break
            }
            return item
        }
        result.debugItems = debugItems.map { item in
            var item = item
            item.frame = item.frame.applying(transform)
            if case let .content(content) = item.value {
                item.value = .content(content.transformed(by: transform))
            }
            return item
        }
        result.interpolationBounds = interpolationBounds?.applying(transform)
        result.numericValue = numericValue
        return result
    }

    private enum InterpolationMaterializationTask {
        case list(DisplayList, CGAffineTransform, Float, StyleChain)
        case finishList(DisplayList, Int, CGAffineTransform, Float, StyleChain)
        case item(Item, CGAffineTransform, Float, StyleChain)
        case finishStyle(Item, Content)
        case finishFlattened(Item, Content)
        case finishDrawing(Item, Content)
        case finishEffect(Item, Effect, Int, CGAffineTransform, Float, StyleChain)
        case finishStates(Item, [StrongHash], CGAffineTransform, Float, StyleChain)
    }

    func materializingInterpolationContents() -> DisplayList {
        // Renderer-state composition is ordered, but it is not recursive. Keep
        // the same ordering while using an explicit work stack so repeated
        // retargeting cannot consume the Swift call stack.
        var tasks: [InterpolationMaterializationTask] = [
            .list(self, .identity, 1, StyleChain())
        ]
        var values: [DisplayList] = []

        func takeValues(_ count: Int) -> [DisplayList] {
            guard count > 0 else { return [] }
            let start = values.index(values.endIndex, offsetBy: -count)
            let result = Array(values[start...])
            values.removeSubrange(start...)
            return result
        }

        func transformedItem(
            _ item: Item,
            by transform: CGAffineTransform,
            opacity: Float,
            outerStyleChain: StyleChain
        ) -> Item {
            var item = item
            item.frame = item.frame.applying(transform)
            item.opacity *= opacity
            item.styleChain = item.styleChain.appendingOuter(outerStyleChain)
            if case let .content(content) = item.value {
                item.value = .content(content.transformed(by: transform))
            }
            return item
        }

        while let task = tasks.popLast() {
            switch task {
            case let .list(list, transform, opacity, outerStyleChain):
                tasks.append(
                    .finishList(
                        list,
                        list.items.count,
                        transform,
                        opacity,
                        outerStyleChain
                    )
                )
                for item in list.items.reversed() {
                    tasks.append(
                        .item(item, transform, opacity, outerStyleChain)
                    )
                }

            case let .finishList(
                source,
                itemCount,
                transform,
                opacity,
                outerStyleChain
            ):
                let materializedItems = takeValues(itemCount)
                var result = DisplayList()
                for contents in materializedItems {
                    result.append(contentsOf: contents)
                }
                result.debugItems = source.debugItems.map {
                    transformedItem(
                        $0,
                        by: transform,
                        opacity: opacity,
                        outerStyleChain: outerStyleChain
                    )
                }
                result.recordInterpolationBounds(
                    source.interpolationBounds?.applying(transform)
                )
                result.numericValue = source.numericValue
                values.append(result)

            case let .item(item, transform, opacity, outerStyleChain):
                switch item.value {
                case let .content(content):
                    switch content.value {
                    case let .crossFade(crossFade):
                        guard case let .effect(
                            .crossFade(sourceFraction, targetFraction),
                            _
                        ) = crossFade.command else {
                            preconditionFailure(
                                "DisplayList.CrossFadeValue requires a cross-fade command"
                            )
                        }
                        let inheritedStyleChain = item.styleChain
                            .appendingOuter(outerStyleChain)
                        var branches: [(
                            Content.CrossFadeValue.Branch,
                            Float,
                            CGAffineTransform
                        )] = []
                        if let source = crossFade.source,
                           1 - sourceFraction > 0,
                           let branchTransform =
                                Content.CrossFadeValue.Branch
                                    .interpolationTransform(
                                        from: source.sourceBounds,
                                        to: source.outputBounds
                                    ) {
                            branches.append((
                                source,
                                1 - sourceFraction,
                                branchTransform
                            ))
                        }
                        if let target = crossFade.target,
                           targetFraction > 0,
                           let branchTransform =
                                Content.CrossFadeValue.Branch
                                    .interpolationTransform(
                                        from: target.sourceBounds,
                                        to: target.outputBounds
                                    ) {
                            branches.append((
                                target,
                                targetFraction,
                                branchTransform
                            ))
                        }
                        tasks.append(
                            .finishList(
                                DisplayList(),
                                branches.count,
                                .identity,
                                1,
                                StyleChain()
                            )
                        )
                        for (
                            branch,
                            fraction,
                            branchTransform
                        ) in branches.reversed() {
                            tasks.append(
                                .list(
                                    branch.contents,
                                    branchTransform
                                        .concatenating(crossFade.transform)
                                        .concatenating(transform),
                                    opacity * item.opacity * fraction,
                                    inheritedStyleChain
                                )
                            )
                        }

                    case let .style(style):
                        if case let .opacity(styleOpacity) = style.style {
                            tasks.append(
                                .list(
                                    style.contents,
                                    style.transform.concatenating(transform),
                                    opacity * item.opacity * Float(styleOpacity),
                                    item.styleChain
                                        .appendingOuter(outerStyleChain)
                                )
                            )
                        } else {
                            let transformedContent = content.transformed(
                                by: transform
                            )
                            tasks.append(
                                .finishStyle(
                                    transformedItem(
                                        item,
                                        by: transform,
                                        opacity: opacity,
                                        outerStyleChain: outerStyleChain
                                    ),
                                    transformedContent
                                )
                            )
                            tasks.append(
                                .list(
                                    style.contents,
                                    .identity,
                                    1,
                                    StyleChain()
                                )
                            )
                        }

                    case let .flattened(list, _, _):
                        let transformedContent = content.transformed(by: transform)
                        tasks.append(
                            .finishFlattened(
                                transformedItem(
                                    item,
                                    by: transform,
                                    opacity: opacity,
                                    outerStyleChain: outerStyleChain
                                ),
                                transformedContent
                            )
                        )
                        tasks.append(
                            .list(list, .identity, 1, StyleChain())
                        )

                    case let .drawing(contents, _, _):
                        guard let local = contents as? LocalContents else {
                            var result = DisplayList()
                            result.items.append(
                                transformedItem(
                                    item,
                                    by: transform,
                                    opacity: opacity,
                                    outerStyleChain: outerStyleChain
                                )
                            )
                            result.recordInterpolationBounds(
                                item.command.bounds?.applying(transform)
                            )
                            values.append(result)
                            break
                        }
                        let transformedContent = content.transformed(by: transform)
                        tasks.append(
                            .finishDrawing(
                                transformedItem(
                                    item,
                                    by: transform,
                                    opacity: opacity,
                                    outerStyleChain: outerStyleChain
                                ),
                                transformedContent
                            )
                        )
                        tasks.append(
                            .list(local.list, .identity, 1, StyleChain())
                        )

                    case .backend, .color, .shape, .image, .text:
                        var result = DisplayList()
                        let item = transformedItem(
                            item,
                            by: transform,
                            opacity: opacity,
                            outerStyleChain: outerStyleChain
                        )
                        result.items.append(item)
                        result.recordInterpolationBounds(item.command.bounds)
                        values.append(result)
                    }

                case let .effect(effect, contents):
                    let childCount: Int
                    if case .mask = effect {
                        childCount = 2
                    } else {
                        childCount = 1
                    }
                    tasks.append(
                        .finishEffect(
                            item,
                            effect,
                            childCount,
                            transform,
                            opacity,
                            outerStyleChain
                        )
                    )
                    tasks.append(
                        .list(contents, transform, 1, StyleChain())
                    )
                    if case let .mask(mask, _) = effect {
                        tasks.append(
                            .list(mask, transform, 1, StyleChain())
                        )
                    }

                case let .states(states):
                    tasks.append(
                        .finishStates(
                            item,
                            states.map(\.0),
                            transform,
                            opacity,
                            outerStyleChain
                        )
                    )
                    for (_, contents) in states.reversed() {
                        tasks.append(
                            .list(contents, transform, 1, StyleChain())
                        )
                    }

                case .empty:
                    var result = DisplayList()
                    var item = item
                    item.frame = item.frame.applying(transform)
                    item.opacity *= opacity
                    item.styleChain = item.styleChain
                        .appendingOuter(outerStyleChain)
                    result.items.append(item)
                    values.append(result)
                }

            case let .finishStyle(item, transformedContent):
                let contents = values.removeLast()
                guard case var .style(style) = transformedContent.value else {
                    preconditionFailure(
                        "DisplayList style materialization requires style content"
                    )
                }
                style.contents = contents
                var content = transformedContent
                content.value = .style(style)
                var item = item
                item.value = .content(content)
                var result = DisplayList()
                result.items.append(item)
                result.recordInterpolationBounds(item.command.bounds)
                values.append(result)

            case let .finishFlattened(item, transformedContent):
                let contents = values.removeLast()
                guard case let .flattened(_, origin, options) =
                    transformedContent.value else {
                    preconditionFailure(
                        "DisplayList flattened materialization requires flattened content"
                    )
                }
                var content = transformedContent
                content.value = .flattened(contents, origin, options)
                var item = item
                item.value = .content(content)
                var result = DisplayList()
                result.items.append(item)
                result.recordInterpolationBounds(item.command.bounds)
                values.append(result)

            case let .finishDrawing(item, transformedContent):
                let contents = values.removeLast()
                guard case let .drawing(_, origin, options) =
                    transformedContent.value else {
                    preconditionFailure(
                        "DisplayList drawing materialization requires drawing content"
                    )
                }
                var content = transformedContent
                content.value = .drawing(
                    LocalContents(list: contents),
                    origin,
                    options
                )
                var item = item
                item.value = .content(content)
                var result = DisplayList()
                result.items.append(item)
                result.recordInterpolationBounds(item.command.bounds)
                values.append(result)

            case let .finishEffect(
                original,
                effect,
                childCount,
                transform,
                opacity,
                outerStyleChain
            ):
                let children = takeValues(childCount)
                let contents: DisplayList
                let materializedEffect: Effect
                if case let .mask(_, options) = effect {
                    materializedEffect = .mask(children[0], options)
                    contents = children[1]
                } else {
                    materializedEffect = effect
                    contents = children[0]
                }
                var item = original
                item.frame = item.frame.applying(transform)
                item.opacity *= opacity
                item.styleChain = item.styleChain
                    .appendingOuter(outerStyleChain)
                item.value = .effect(materializedEffect, contents)
                var result = DisplayList()
                result.items.append(item)
                result.recordInterpolationBounds(item.frame)
                values.append(result)

            case let .finishStates(
                original,
                hashes,
                transform,
                opacity,
                outerStyleChain
            ):
                let contents = takeValues(hashes.count)
                var item = original
                item.frame = item.frame.applying(transform)
                item.opacity *= opacity
                item.styleChain = item.styleChain
                    .appendingOuter(outerStyleChain)
                item.value = .states(Array(zip(hashes, contents)))
                var result = DisplayList()
                result.items.append(item)
                result.recordInterpolationBounds(item.frame)
                values.append(result)
            }
        }

        precondition(values.count == 1)
        return values[0]
    }

    mutating func appendCrossFadeItem(
        sourceItems: [Item],
        sourceBounds: CGRect?,
        sourceOutputBounds: CGRect?,
        targetItems: [Item],
        targetBounds: CGRect?,
        targetOutputBounds: CGRect?,
        bounds: CGRect? = nil,
        sourceFraction: Float,
        targetFraction: Float
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(
            .crossFade(
                sourceFraction: sourceFraction,
                targetFraction: targetFraction
            ),
            bounds: bounds
        )
        let source = Self.crossFadeBranch(
            items: sourceItems,
            sourceBounds: sourceBounds,
            outputBounds: sourceOutputBounds
        )
        let target = Self.crossFadeBranch(
            items: targetItems,
            sourceBounds: targetBounds,
            outputBounds: targetOutputBounds
        )
        appendRecordedItem(Item(
            source: source,
            target: target,
            command: command
        ))
        recordInterpolationBounds(bounds)
    }

    private static func crossFadeBranch(
        items: [Item],
        sourceBounds: CGRect?,
        outputBounds: CGRect?
    ) -> Content.CrossFadeValue.Branch? {
        guard !items.isEmpty,
              let sourceBounds,
              let outputBounds else {
            return nil
        }
        var contents = DisplayList()
        contents.items = items
        contents.recordInterpolationBounds(sourceBounds)
        return Content.CrossFadeValue.Branch(
            contents: contents,
            sourceBounds: sourceBounds,
            outputBounds: outputBounds
        )
    }

    mutating func appendBlendModeItem(
        bounds: CGRect? = nil,
        blendMode: BlendMode,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.blendMode(blendMode), bounds: bounds)
        appendRecordedItem(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendBlendModeItem(
        bounds: CGRect? = nil,
        blendMode: BlendMode,
        contents: DisplayList
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.blendMode(blendMode), bounds: bounds)
        appendRecordedItem(Item(
            style: .blendMode(blendMode),
            contents: contents,
            command: command
        ))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShadowItem(
        bounds: CGRect? = nil,
        color: Color.Resolved,
        radius: CGFloat,
        offset: CGSize,
        blendMode: GraphicsContext.BlendMode = .normal,
        options: GraphicsContext.ShadowOptions = GraphicsContext.ShadowOptions(),
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(
            .shadow(ItemRecord.ShadowRecord(
                color: color,
                radius: radius,
                offset: offset,
                blendModeRawValue: blendMode.rawValue,
                optionsRawValue: options.rawValue
            )),
            bounds: bounds
        )
        appendRecordedItem(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendShadowItem(
        bounds: CGRect? = nil,
        color: Color.Resolved,
        radius: CGFloat,
        offset: CGSize,
        blendMode: GraphicsContext.BlendMode = .normal,
        options: GraphicsContext.ShadowOptions = GraphicsContext.ShadowOptions(),
        contents: DisplayList
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let record = ItemRecord.ShadowRecord(
            color: color,
            radius: radius,
            offset: offset,
            blendModeRawValue: blendMode.rawValue,
            optionsRawValue: options.rawValue
        )
        let command = ItemCommand.effect(.shadow(record), bounds: bounds)
        let filter = GraphicsContext.Filter.shadow(
            color: Color(color),
            radius: radius,
            x: offset.width,
            y: offset.height,
            blendMode: blendMode,
            options: options
        )
        appendRecordedItem(Item(
            style: .shadow(record, filter),
            contents: contents,
            command: command
        ))
        recordInterpolationBounds(bounds)
    }

    mutating func appendColorFilterItem(
        bounds: CGRect? = nil,
        filter: ItemRecord.ColorFilterRecord,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.colorFilter(filter), bounds: bounds)
        appendRecordedItem(Item(command: command, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendColorFilterItem(
        bounds: CGRect? = nil,
        filter record: ItemRecord.ColorFilterRecord,
        graphicsFilter: GraphicsContext.Filter,
        contents: DisplayList
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let command = ItemCommand.effect(.colorFilter(record), bounds: bounds)
        appendRecordedItem(Item(
            style: .colorFilter(record, graphicsFilter),
            contents: contents,
            command: command
        ))
        recordInterpolationBounds(bounds)
    }

    mutating func appendDebugItem(
        bounds: CGRect? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        appendRecordedDebugItem(Item(command: .debug(bounds: bounds), item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendEffect(
        _ effect: Effect,
        contents: DisplayList,
        frame: CGRect? = nil,
        identity: _DisplayList_Identity = .none,
        version: Version = Version(value: 0)
    ) {
        appendRecordedItem(Item(
            effect: effect,
            contents: contents,
            frame: frame,
            identity: identity,
            version: version
        ))
        recordInterpolationBounds(frame ?? contents.interpolationBounds)
    }

    mutating func appendEffect(
        _ item: EffectItem,
        contents: DisplayList
    ) {
        var copied = Item(
            effect: item.effect,
            contents: contents,
            frame: item.frame,
            identity: item.identity,
            version: item.version,
            opacity: item.opacity
        )
        copied.styleChain = item.styleChain
        appendRecordedItem(copied)
        recordInterpolationBounds(item.frame)
    }

    mutating func appendAnimationStyle(
        _ animation: RBAnimation,
        id: UUID? = nil,
        flags: UInt32 = StyleCommand.AnimationStyle.defaultFlags,
        metadataIdentity: StyleCommand.MetadataIdentity = .empty
    ) {
        activeStyleChain.commands.append(.animation(StyleCommand.AnimationStyle(
            animation: animation,
            id: id,
            flags: flags,
            metadataIdentity: metadataIdentity
        )))
    }

    private static func itemRecordBounds(_ bounds: CGRect?) -> CGRect? {
        guard let bounds = bounds?.standardized,
              !bounds.isNull,
              bounds.width > 0,
              bounds.height > 0
        else { return nil }
        return bounds
    }

    private static func itemCommand(
        kind: ItemRecord.Kind,
        bounds: CGRect?,
        effectKind: ItemRecord.EffectKind?
    ) -> ItemCommand {
        switch kind {
        case .closure:
            return .closure(bounds: bounds)
        case .shapeFill:
            return .shape(role: .fill, style: nil, fillStyle: nil, strokeStyle: nil, bounds: bounds)
        case .shapeStroke:
            return .shape(role: .stroke, style: nil, fillStyle: nil, strokeStyle: nil, bounds: bounds)
        case .shapeSeparator:
            return .shape(role: .separator, style: nil, fillStyle: nil, strokeStyle: nil, bounds: bounds)
        case .image:
            return .image(
                ItemRecord.ImageRecord(
                    baseline: 0,
                    textureID: nil,
                    placementRect: bounds ?? .zero,
                    textureTransform: .identity,
                    scaleFactor: 1,
                    hasShading: false,
                    shading: nil
                ),
                bounds: bounds
            )
        case .text:
            return .text(ItemRecord.TextRecord(foreground: nil), bounds: bounds)
        case .custom:
            return .custom(
                ItemRecord.CustomRecord(
                    isOpaque: false,
                    colorMode: .nonLinear,
                    rendersAsynchronously: false
                ),
                bounds: bounds
            )
        case .effect:
            return .effect(effectCommand(for: effectKind), bounds: bounds)
        case .debug:
            return .debug(bounds: bounds)
        }
    }

    private static func effectCommand(
        for kind: ItemRecord.EffectKind?
    ) -> ItemCommand.EffectCommand {
        switch kind {
        case .opacity:
            return .opacity(1)
        case .blur:
            return .blur(radius: 0, isOpaque: false)
        case .geometry:
            return .geometry(.identity)
        case .crossFade:
            return .crossFade(sourceFraction: 0, targetFraction: 0)
        case .blendMode:
            return .blendMode(.normal)
        case .shadow:
            return .shadow(
                ItemRecord.ShadowRecord(
                    color: Color.Resolved(
                        colorSpace: .sRGBLinear,
                        red: 0,
                        green: 0,
                        blue: 0,
                        opacity: 0
                    ),
                    radius: 0,
                    offset: .zero,
                    blendModeRawValue: GraphicsContext.BlendMode.normal.rawValue,
                    optionsRawValue: 0
                )
            )
        case .colorFilter:
            return .colorFilter(
                ItemRecord.ColorFilterRecord(kind: .brightness, amount: 0)
            )
        case .generic, nil:
            return .generic
        }
    }

    private static func itemRecordKind(for role: ShapeRole) -> ItemRecord.Kind {
        switch role {
        case .fill:
            return .shapeFill
        case .stroke:
            return .shapeStroke
        case .separator:
            return .shapeSeparator
        }
    }

    private static func shapeStyleRecord<S: ShapeStyle>(
        for style: S,
        environment: EnvironmentValues,
        role: ShapeRole
    ) -> ItemRecord.ShapeStyleRecord? {
        shapeStyleRecord(
            for: style as any ShapeStyle,
            environment: environment,
            role: role
        )
    }

    private static func shapeStyleRecord(
        for style: any ShapeStyle,
        environment: EnvironmentValues,
        role: ShapeRole
    ) -> ItemRecord.ShapeStyleRecord? {
        if let color = style as? Color {
            return .color(color)
        }
        if let resolved = style as? Color.Resolved {
            return .color(Color(resolved))
        }
        if let gradient = style as? Gradient {
            return .gradient(gradient)
        }
        if let gradient = style as? AnyGradient {
            return .gradient(gradient.provider.gradient)
        }
        if let mesh = style as? MeshGradient {
            return .meshGradient(mesh)
        }
        if let shader = style as? Shader {
            return .shader(shader.resolvePaint(in: environment))
        }
        if let erased = style as? AnyShapeStyle {
            return shapeStyleRecord(
                for: erased.storage.box.style,
                environment: environment,
                role: role
            )
        }
        return shapeStyleRecord(
            resolving: style,
            environment: environment,
            role: role
        )
    }

    private static func shapeStyleRecord(
        resolving style: any ShapeStyle,
        environment: EnvironmentValues,
        role: ShapeRole
    ) -> ItemRecord.ShapeStyleRecord? {
        var shape = _ShapeStyle_Shape(
            operation: .fallbackColor(level: 0),
            environment: environment,
            role: role
        )
        style._apply(to: &shape)
        guard let shading = shape.resolvedShading else { return nil }
        if case let .color(color)? = shadingRecord(for: shading) {
            return .color(color)
        }
        return nil
    }

    private static func shadingRecord(
        for shading: GraphicsContext.Shading
    ) -> ItemRecord.ShadingRecord? {
        guard shading.properties.count == 1 else { return nil }
        if case let .color(color) = shading.properties[0] {
            return .color(color)
        }
        return nil
    }

    mutating func recordInterpolationBounds(_ rect: CGRect?) {
        guard let rect = Self.itemRecordBounds(rect) else { return }
        if let current = interpolationBounds {
            interpolationBounds = current.union(rect)
        } else {
            interpolationBounds = rect
        }
    }

    final class GraphicsRenderer {
        private struct CallbackKey: Hashable {
            var index: Index.ID
            var seed: Seed
            var scale: CGFloat
        }

        private struct AnimatorKey: Hashable {
            var index: Index.ID
        }

        private struct Cache {
            var callbacks: [CallbackKey: GraphicsContext.ResolvedText.Drawing] = [:]
            var animators: [AnimatorKey: any _DisplayList_AnyEffectAnimator] = [:]
        }

        private var oldCache = Cache()
        private var newCache = Cache()
        private(set) var dynamicTextPlaceholders: [DynamicTextPlaceholder] = []
        private(set) var index = Index()
        private(set) var time = Time.zero
        private(set) var nextTime = Time.infinity

        var animatorCount: Int {
            oldCache.animators.count
        }

        var textCallbackCount: Int {
            oldCache.callbacks.count
        }

        var dynamicTextPlaceholderCount: Int {
            dynamicTextPlaceholders.count
        }

        func render(
            list: DisplayList,
            at time: Time,
            in context: GraphicsContext,
            includeDebug: Bool = true
        ) {
            let savedIndex = index
            beginPass(at: time)
            let sampled = sampleItems(in: list)
            renderItems(in: sampled, context: context, includeDebug: includeDebug)
            endPass()
            index = savedIndex
        }

        func sample(list: DisplayList, at time: Time) -> DisplayList {
            let savedIndex = index
            beginPass(at: time)
            let sampled = sampleItems(in: list)
            endPass()
            index = savedIndex
            return sampled
        }

        func beginPass(at time: Time) {
            self.time = time
            nextTime = .infinity
            newCache = Cache()
            dynamicTextPlaceholders.removeAll(keepingCapacity: true)
        }

        func endPass() {
            oldCache = newCache
            newCache = Cache()
        }

        private func sampleItems(in list: DisplayList) -> DisplayList {
            var sampled = list
            sampled.items.removeAll(keepingCapacity: true)

            for item in list.items {
                let previous = index.enter(identity: item.identity)
                var sampledItem = item
                switch item.value {
                case let .content(content):
                    if case var .style(style) = content.value {
                        var sampledContent = content
                        style.contents = sampleItems(in: style.contents)
                        sampledContent.value = .style(style)
                        sampledItem.value = .content(sampledContent)
                    } else if case var .crossFade(crossFade) = content.value {
                        var sampledContent = content
                        if var source = crossFade.source {
                            source.contents = sampleItems(in: source.contents)
                            crossFade.source = source
                        }
                        if var target = crossFade.target {
                            target.contents = sampleItems(in: target.contents)
                            crossFade.target = target
                        }
                        sampledContent.value = .crossFade(crossFade)
                        sampledItem.value = .content(sampledContent)
                    }

                case .empty:
                    break

                case let .effect(effect, contents):
                    if case let .animation(animation) = effect {
                        let key = AnimatorKey(index: index.id)
                        var animator: any _DisplayList_AnyEffectAnimator
                        if let cached = oldCache.animators[key] {
                            animator = cached
                        } else {
                            animator = animation.makeAnimator()
                        }
                        let evaluation = animator.evaluate(
                            animation,
                            at: time,
                            size: item.frame.size
                        )
                        if !evaluation.finished {
                            nextTime = time
                        }
                        newCache.animators[key] = animator
                        sampledItem.value = .effect(
                            evaluation.effect,
                            sampleItems(in: contents)
                        )
                    } else {
                        sampledItem.value = .effect(effect, sampleItems(in: contents))
                    }

                case let .states(states):
                    sampledItem.value = .states(states.map { hash, contents in
                        (hash, sampleItems(in: contents))
                    })
                }
                sampled.items.append(sampledItem)
                index.leave(index: previous)
            }
            return sampled
        }

        private func renderItems(
            in list: DisplayList,
            context: GraphicsContext,
            includeDebug: Bool
        ) {
            for item in list.items {
                let previous = index.enter(identity: item.identity)
                render(item: item, context: context, includeDebug: includeDebug)
                index.leave(index: previous)
            }
            if includeDebug {
                for item in list.debugItems {
                    item(context)
                }
            }
        }

        private func render(
            item: Item,
            context: GraphicsContext,
            includeDebug: Bool
        ) {
            var context = item.presentationContext(from: context)
            context.opacity *= Double(item.opacity)
            guard context.opacity > 0 else { return }
            switch item.value {
            case let .content(content):
                switch content.value {
                case .backend:
                    content.draw(in: context)
                case .color:
                    content.draw(in: context)
                case .shape, .image:
                    content.draw(in: context)
                case let .style(style):
                    render(
                        style: style,
                        context: content.renderContext(from: context),
                        includeDebug: includeDebug
                    )
                case let .crossFade(crossFade):
                    render(
                        crossFade: crossFade,
                        context: content.renderContext(from: context),
                        includeDebug: includeDebug
                    )
                case let .text(text):
                    let context = content.renderContext(from: context)
                    if text.view.renderer != nil {
                        text.draw(in: context)
                        break
                    }
                    if let placeholder = resolveDynamicTextPlaceholder(text) {
                        dynamicTextPlaceholders.append(placeholder)
                        // The immediate renderer cannot defer placeholder resolution,
                        // so draw the current text while retaining the operation for
                        // archive-backed consumers.
                        text.draw(in: context)
                        break
                    }
                    guard let drawing = resolveTextCallback(
                        text,
                        seed: content.seed,
                        scale: context.contentScaleFactor
                    ) else {
                        return
                    }
                    text.draw(drawing, in: context)
                case let .flattened(list, origin, _):
                    var context = content.renderContext(from: context)
                    context.translateBy(x: origin.x, y: origin.y)
                    renderItems(in: list, context: context, includeDebug: includeDebug)
                case let .drawing(contents, origin, _):
                    guard let list = (contents as? LocalContents)?.list else { return }
                    var context = content.renderContext(from: context)
                    context.translateBy(x: origin.x, y: origin.y)
                    renderItems(in: list, context: context, includeDebug: includeDebug)
                }

            case let .effect(effect, contents):
                render(
                    effect: effect,
                    contents: contents,
                    frame: item.frame,
                    context: context,
                    includeDebug: includeDebug
                )

            case let .states(states):
                if let contents = states.last?.1 {
                    renderItems(in: contents, context: context, includeDebug: includeDebug)
                }

            case .empty:
                break
            }
        }

        private func render(
            style: Content.StyleValue,
            context: GraphicsContext,
            includeDebug: Bool
        ) {
            style.draw(in: context) { contents, context in
                self.renderItems(
                    in: contents,
                    context: context,
                    includeDebug: includeDebug
                )
            }
        }

        private func render(
            crossFade: Content.CrossFadeValue,
            context: GraphicsContext,
            includeDebug: Bool
        ) {
            crossFade.draw(in: context) { contents, context in
                self.renderItems(
                    in: contents,
                    context: context,
                    includeDebug: includeDebug
                )
            }
        }

        func resolveTextCallback(
            _ text: Content.TextValue,
            seed: Seed,
            scale: CGFloat
        ) -> GraphicsContext.ResolvedText.Drawing? {
            guard !text.view.text.needsDynamicRenderingInArchive else {
                return nil
            }
            let key = CallbackKey(
                index: index.id,
                seed: seed,
                scale: max(scale.rounded(.toNearestOrEven), 1)
            )
            guard let drawing = oldCache.callbacks[key] ?? text.makeDrawing() else {
                return nil
            }
            newCache.callbacks[key] = drawing
            return drawing
        }

        func resolveDynamicTextPlaceholder(
            _ text: Content.TextValue
        ) -> DynamicTextPlaceholder? {
            guard text.view.text.needsDynamicRenderingInArchive else {
                return nil
            }
            return DynamicTextPlaceholder(text: text.view.text, size: text.size)
        }

        private func render(
            effect: Effect,
            contents: DisplayList,
            frame: CGRect,
            context: GraphicsContext,
            includeDebug: Bool
        ) {
            switch effect {
            case .identity,
                 .archive,
                 .state,
                 .contentTransition,
                 .geometryGroup,
                 .interpolatorRoot,
                 .interpolatorLayer,
                 .interpolatorAnimation:
                renderItems(in: contents, context: context, includeDebug: includeDebug)

            case let .platformGroup(factory):
                factory.renderPlatformGroup(
                    contents: contents,
                    in: context
                ) { contents, context in
                    self.renderItems(
                        in: contents,
                        context: context,
                        includeDebug: includeDebug
                    )
                }

            case let .shader(shader):
                if context.recording != nil, shader.shader != nil {
                    let layer = context.recordingContext(size: frame.size)
                    renderItems(in: contents, context: layer, includeDebug: includeDebug)
                    let commands = layer.recording!
                    context.record(bounds: frame) { context in
                        guard let layer = context.makeLayerContext() else {
                            commands.draw(in: context)
                            return
                        }
                        commands.draw(in: layer)
                        if !context.drawCustomShaderLayer(shader, sourceTexture: layer.backdrop, frame: frame) {
                            commands.draw(in: context)
                        }
                    }
                    return
                }
                guard shader.shader != nil,
                      let layer = context.makeLayerContext() else {
                    renderItems(in: contents, context: context, includeDebug: includeDebug)
                    return
                }
                renderItems(in: contents, context: layer, includeDebug: includeDebug)
                if !context.drawCustomShaderLayer(
                    shader,
                    sourceTexture: layer.backdrop,
                    frame: frame
                ) {
                    renderItems(in: contents, context: context, includeDebug: includeDebug)
                }

            case let .mask(mask, options):
                var context = context
                context.clipToLayer(options: options) { layer in
                    self.renderItems(in: mask, context: layer, includeDebug: includeDebug)
                }
                renderItems(in: contents, context: context, includeDebug: includeDebug)

            case let .opacity(opacity):
                guard opacity > 0 else { return }
                var context = context
                context.opacity *= Double(opacity)
                guard context.opacity > 0 else { return }
                context.drawLayer { layer in
                    self.renderItems(in: contents, context: layer, includeDebug: includeDebug)
                }

            case let .transform(transform):
                if transform.isAffine {
                    var context = context
                    context.concatenate(
                        CGAffineTransform(
                            a: transform.m11,
                            b: transform.m12,
                            c: transform.m21,
                            d: transform.m22,
                            tx: transform.m31,
                            ty: transform.m32
                        )
                    )
                    renderItems(
                        in: contents,
                        context: context,
                        includeDebug: includeDebug
                    )
                } else {
                    context.drawProjectiveLayer(
                        transform: transform,
                        contentBounds: contents.interpolationBounds ?? CGRect(
                            origin: .zero,
                            size: frame.size
                        )
                    ) { layer in
                        self.renderItems(
                            in: contents,
                            context: layer,
                            includeDebug: includeDebug
                        )
                    }
                }

            case .animation:
                preconditionFailure("Effect animations must be sampled before rendering")
            }
        }
    }

    static func effect(_ effect: Effect, contents: DisplayList) -> DisplayList {
        var list = DisplayList()
        list.appendEffect(effect, contents: contents)
        return list
    }

    static func flattened(
        _ contents: DisplayList,
        origin: CGPoint,
        options: RasterizationOptions
    ) -> DisplayList {
        let content = Content(
            flattened: contents,
            origin: origin,
            options: options
        )
        let bounds = content.command.bounds
        var list = DisplayList()
        list.appendRecordedItem(Item(
            content: content,
            frame: bounds ?? .zero,
            identity: .none,
            version: Version()
        ))
        list.recordInterpolationBounds(bounds)
        list.numericValue = contents.numericValue
        return list
    }

    func forEachRenderItem(includeDebug: Bool = true, _ body: (Item) -> Void) {
        for item in items {
            item.forEachRenderItem(includeDebug: includeDebug, body)
        }
        if includeDebug {
            for item in debugItems {
                body(item)
            }
        }
    }

    func draw(in context: GraphicsContext, includeDebug: Bool = true) {
        GraphicsRenderer().render(
            list: self,
            at: .systemUptime,
            in: context,
            includeDebug: includeDebug
        )
    }

    func hasSameInterpolationSurface(as other: DisplayList) -> Bool {
        itemSurfaceMatches(
            items,
            other.items
        ) &&
        commandSurfaceMatches(
            commands: debugItemCommands,
            otherCommands: other.debugItemCommands
        ) &&
            zip(debugItems, other.debugItems).allSatisfy { lhs, rhs in
                lhs.opacity == rhs.opacity && lhs.styleChain == rhs.styleChain
            } &&
            interpolationBounds == other.interpolationBounds
    }

    private func itemSurfaceMatches(
        _ items: [Item],
        _ otherItems: [Item]
    ) -> Bool {
        guard items.count == otherItems.count else { return false }
        return zip(items, otherItems).allSatisfy { lhs, rhs in
            guard lhs.frame == rhs.frame,
                  lhs.version.value == rhs.version.value,
                  lhs.identity == rhs.identity,
                  lhs.opacity == rhs.opacity,
                  lhs.styleChain == rhs.styleChain else {
                return false
            }
            switch (lhs.value, rhs.value) {
            case let (.content(lhs), .content(rhs)):
                guard lhs.seed == rhs.seed else { return false }
                switch (lhs.value, rhs.value) {
                case let (.shape(lhsShape), .shape(rhsShape)):
                    return lhsShape.path == rhsShape.path &&
                        lhsShape.fillStyle == rhsShape.fillStyle &&
                        lhsShape.strokeStyle == rhsShape.strokeStyle &&
                        lhsShape.transform == rhsShape.transform &&
                        explicitGradientSurfaceMatches(
                            lhsShape.shading,
                            rhsShape.shading
                        ) &&
                        lhsShape.command == rhsShape.command
                case (.shape, _), (_, .shape):
                    return false
                case let (.image(lhsImage), .image(rhsImage)):
                    return lhsImage.frame == rhsImage.frame &&
                        lhsImage.transform == rhsImage.transform &&
                        lhsImage.command == rhsImage.command
                case (.image, _), (_, .image):
                    return false
                case let (.style(lhsStyle), .style(rhsStyle)):
                    return lhsStyle.transform == rhsStyle.transform &&
                        lhsStyle.command == rhsStyle.command &&
                        lhsStyle.contents.hasSameInterpolationSurface(as: rhsStyle.contents)
                case (.style, _), (_, .style):
                    return false
                case let (.crossFade(lhsCrossFade), .crossFade(rhsCrossFade)):
                    return lhsCrossFade.transform == rhsCrossFade.transform &&
                        lhsCrossFade.command == rhsCrossFade.command &&
                        crossFadeBranchesHaveSameSurface(
                            lhsCrossFade.source,
                            rhsCrossFade.source
                        ) &&
                        crossFadeBranchesHaveSameSurface(
                            lhsCrossFade.target,
                            rhsCrossFade.target
                        )
                case (.crossFade, _), (_, .crossFade):
                    return false
                case let (.flattened(lhsList, lhsOrigin, lhsOptions),
                          .flattened(rhsList, rhsOrigin, rhsOptions)):
                    return lhsOrigin == rhsOrigin &&
                        lhsOptions == rhsOptions &&
                        lhsList.hasSameInterpolationSurface(as: rhsList)
                case (.flattened, _), (_, .flattened):
                    return false
                case let (.drawing(lhsContents, lhsOrigin, lhsOptions),
                          .drawing(rhsContents, rhsOrigin, rhsOptions)):
                    return (lhsContents as AnyObject) === (rhsContents as AnyObject) &&
                        lhsOrigin == rhsOrigin &&
                        lhsOptions == rhsOptions
                case (.drawing, _), (_, .drawing):
                    return false
                default:
                    return lhs.command == rhs.command
                }
            case let (.effect(lhsEffect, lhsContents), .effect(rhsEffect, rhsContents)):
                return lhsEffect.hasSameSurface(as: rhsEffect) &&
                    lhsContents.hasSameInterpolationSurface(as: rhsContents)
            case let (.states(lhsStates), .states(rhsStates)):
                guard lhsStates.count == rhsStates.count else { return false }
                return zip(lhsStates, rhsStates).allSatisfy { lhs, rhs in
                    lhs.0 == rhs.0 && lhs.1.hasSameInterpolationSurface(as: rhs.1)
                }
            case (.empty, .empty):
                return true
            case (.content, _), (.effect, _), (.states, _), (.empty, _):
                return false
            }
        }
    }

    private func commandSurfaceMatches(
        commands: [ItemCommand],
        otherCommands: [ItemCommand]
    ) -> Bool {
        commands == otherCommands
    }

    private func explicitGradientSurfaceMatches(
        _ lhs: GraphicsContext.Shading,
        _ rhs: GraphicsContext.Shading
    ) -> Bool {
        let lhsHasGradient = lhs.properties.contains { property in
            switch property {
            case .linearGradient, .radialGradient, .conicGradient:
                return true
            default:
                return false
            }
        }
        let rhsHasGradient = rhs.properties.contains { property in
            switch property {
            case .linearGradient, .radialGradient, .conicGradient:
                return true
            default:
                return false
            }
        }
        guard lhsHasGradient || rhsHasGradient else { return true }
        guard lhs.properties.count == 1,
              rhs.properties.count == 1 else {
            return false
        }

        switch (lhs.properties[0], rhs.properties[0]) {
        case let (
            .linearGradient(lhsGradient, lhsStart, lhsEnd, lhsOptions),
            .linearGradient(rhsGradient, rhsStart, rhsEnd, rhsOptions)
        ):
            return lhsGradient == rhsGradient &&
                lhsStart == rhsStart &&
                lhsEnd == rhsEnd &&
                lhsOptions == rhsOptions
        case let (
            .radialGradient(
                lhsGradient,
                lhsCenter,
                lhsStartRadius,
                lhsEndRadius,
                lhsOptions
            ),
            .radialGradient(
                rhsGradient,
                rhsCenter,
                rhsStartRadius,
                rhsEndRadius,
                rhsOptions
            )
        ):
            return lhsGradient == rhsGradient &&
                lhsCenter == rhsCenter &&
                lhsStartRadius == rhsStartRadius &&
                lhsEndRadius == rhsEndRadius &&
                lhsOptions == rhsOptions
        case let (
            .conicGradient(lhsGradient, lhsCenter, lhsAngle, lhsOptions),
            .conicGradient(rhsGradient, rhsCenter, rhsAngle, rhsOptions)
        ):
            return lhsGradient == rhsGradient &&
                lhsCenter == rhsCenter &&
                lhsAngle == rhsAngle &&
                lhsOptions == rhsOptions
        default:
            return false
        }
    }

    private func crossFadeBranchesHaveSameSurface(
        _ lhs: Content.CrossFadeValue.Branch?,
        _ rhs: Content.CrossFadeValue.Branch?
    ) -> Bool {
        switch (lhs, rhs) {
        case let (.some(lhs), .some(rhs)):
            return lhs.sourceBounds == rhs.sourceBounds &&
                lhs.outputBounds == rhs.outputBounds &&
                lhs.contents.hasSameInterpolationSurface(as: rhs.contents)
        case (.none, .none):
            return true
        case (.some, .none), (.none, .some):
            return false
        }
    }
}

private struct DisplayListEffectSurfaceRecord: Equatable {
    enum Kind: UInt8, Equatable {
        case identity
        case archive
        case platformGroup
        case opacity
        case transform
        case mask
        case animation
        case state
        case contentTransition
        case shader
        case geometryGroup
        case interpolatorRoot
        case interpolatorLayer
        case interpolatorAnimation
    }

    var kind: Kind
    var hash: StrongHash?
    var contentTransitionState: ContentTransition.State?
    var shader: Shader.ResolvedShader?
    var groupID: ObjectIdentifier?
    var origin: CGPoint?
    var size: CGSize?
    var layerID: UInt32?
    var animationValue: StrongHash?
    var animation: Animation?
    var opacity: Float?
    var transform: ProjectionTransform?
    var effectAnimation: DisplayListEffectAnimationSurfaceRecord?
    var archiveIDs: DisplayList.ArchiveIDs?
    var clipOptionsRawValue: UInt32?
    var platformGroupID: ObjectIdentifier?
}

private struct DisplayListEffectAnimationSurfaceRecord: Equatable {
    var type: ObjectIdentifier
    var encodedValue: Data?
}

private extension DisplayList.Effect {
    var surfaceRecord: DisplayListEffectSurfaceRecord {
        switch self {
        case .identity:
            return DisplayListEffectSurfaceRecord(kind: .identity)
        case let .archive(ids):
            return DisplayListEffectSurfaceRecord(kind: .archive, archiveIDs: ids)
        case let .platformGroup(factory):
            return DisplayListEffectSurfaceRecord(
                kind: .platformGroup,
                platformGroupID: ObjectIdentifier(factory)
            )
        case let .opacity(opacity):
            return DisplayListEffectSurfaceRecord(kind: .opacity, opacity: opacity)
        case let .transform(transform):
            return DisplayListEffectSurfaceRecord(kind: .transform, transform: transform)
        case let .mask(_, options):
            return DisplayListEffectSurfaceRecord(
                kind: .mask,
                clipOptionsRawValue: options.rawValue
            )
        case let .animation(animation):
            var encoder = ProtobufEncoder()
            let encodedValue: Data?
            do {
                try animation.encode(to: &encoder)
                encodedValue = encoder.data
            } catch {
                encodedValue = nil
            }
            return DisplayListEffectSurfaceRecord(
                kind: .animation,
                effectAnimation: DisplayListEffectAnimationSurfaceRecord(
                    type: ObjectIdentifier(type(of: animation)),
                    encodedValue: encodedValue
                )
            )
        case let .state(hash):
            return DisplayListEffectSurfaceRecord(kind: .state, hash: hash)
        case let .contentTransition(state):
            return DisplayListEffectSurfaceRecord(
                kind: .contentTransition,
                contentTransitionState: state
            )
        case let .shader(shader):
            return DisplayListEffectSurfaceRecord(
                kind: .shader,
                shader: shader
            )
        case .geometryGroup:
            return DisplayListEffectSurfaceRecord(kind: .geometryGroup)
        case let .interpolatorRoot(group, origin, size):
            return DisplayListEffectSurfaceRecord(
                kind: .interpolatorRoot,
                groupID: ObjectIdentifier(group),
                origin: origin,
                size: size
            )
        case let .interpolatorLayer(group, layerID):
            return DisplayListEffectSurfaceRecord(
                kind: .interpolatorLayer,
                groupID: ObjectIdentifier(group),
                layerID: layerID
            )
        case let .interpolatorAnimation(animation):
            return DisplayListEffectSurfaceRecord(
                kind: .interpolatorAnimation,
                animationValue: animation.value,
                animation: animation.animation
            )
        }
    }
}

extension DisplayList.Effect {
    func hasSameSurface(as other: Self) -> Bool {
        guard surfaceRecord == other.surfaceRecord else { return false }
        switch (self, other) {
        case let (.mask(lhs, _), .mask(rhs, _)):
            return lhs.hasSameInterpolationSurface(as: rhs)
        default:
            return true
        }
    }
}

private extension DisplayList.ItemCommand {
    func transformed(by transform: CGAffineTransform) -> Self {
        let transformedBounds = bounds?.applying(transform).standardized
        switch self {
        case .closure:
            return .closure(bounds: transformedBounds)
        case let .shape(role, style, fillStyle, strokeStyle, _):
            return .shape(
                role: role,
                style: style,
                fillStyle: fillStyle,
                strokeStyle: strokeStyle,
                bounds: transformedBounds
            )
        case let .image(image, _):
            return .image(image, bounds: transformedBounds)
        case let .text(text, _):
            return .text(text, bounds: transformedBounds)
        case let .custom(custom, _):
            return .custom(custom, bounds: transformedBounds)
        case let .effect(effect, _):
            return .effect(effect.transformed(by: transform), bounds: transformedBounds)
        case .debug:
            return .debug(bounds: transformedBounds)
        }
    }
}

private extension DisplayList.ItemCommand.EffectCommand {
    func transformed(by transform: CGAffineTransform) -> Self {
        switch self {
        case let .geometry(affineTransform):
            return .geometry(affineTransform.concatenating(transform))
        case .generic,
             .opacity,
             .blur,
             .crossFade,
             .blendMode,
             .shadow,
             .colorFilter:
            return self
        }
    }
}

extension DisplayList.EffectItem {
    fileprivate func forEachRenderItem(
        includeDebug: Bool,
        _ body: (DisplayList.Item) -> Void
    ) {
        switch effect {
        case .identity, .archive, .platformGroup, .opacity, .transform, .mask, .animation, .contentTransition, .shader, .geometryGroup:
            contents.forEachRenderItem(includeDebug: includeDebug, body)
        case .state, .interpolatorRoot, .interpolatorLayer, .interpolatorAnimation:
            break
        }
    }
}

private extension DisplayList.Item {
    func forEachRenderItem(
        includeDebug: Bool,
        _ body: (DisplayList.Item) -> Void
    ) {
        switch value {
        case .content:
            body(self)
        case let .effect(effect, contents):
            switch effect {
            case .identity, .archive, .platformGroup, .opacity, .transform, .mask, .animation, .contentTransition, .shader, .geometryGroup:
                contents.forEachRenderItem(includeDebug: includeDebug, body)
            case .state, .interpolatorRoot, .interpolatorLayer, .interpolatorAnimation:
                break
            }
        case let .states(states):
            states.last?.1.forEachRenderItem(includeDebug: includeDebug, body)
        case .empty:
            break
        }
    }
}

extension DisplayList {
    struct Key: PreferenceKey {
        typealias Value = DisplayList
        // Removed dynamic items remain renderable until their transition ends.
        static var _includesRemovedValues: Bool { true }
        static var defaultValue: DisplayList { DisplayList() }

        static func reduce(value: inout DisplayList, nextValue: () -> DisplayList) {
            value.append(contentsOf: nextValue())
        }
    }
}

struct ResourceList {
    struct Version {
        let value: Int
    }

    struct Task {
        // Resource work can publish graph mutations after view construction. Retaining
        // the owning transaction keeps publication and dependent layout in one host scope.
        var transaction: Transaction
        var updatesGraph: Bool
        var isPending: () -> Bool
        var body: (GraphicsContext) -> Void

        init(
            transaction: Transaction,
            updatesGraph: Bool = true,
            isPending: @escaping () -> Bool = { true },
            body: @escaping (GraphicsContext) -> Void
        ) {
            self.transaction = transaction
            self.updatesGraph = updatesGraph
            self.isPending = isPending
            self.body = body
        }

        func callAsFunction(_ context: GraphicsContext) {
            body(context)
        }
    }

    var items: [Task] = []

    mutating func append(contentsOf other: Self) {
        self.items.append(contentsOf: other.items)
    }
}

extension ResourceList {
    struct Key: PreferenceKey {
        typealias Value = ResourceList
        static var defaultValue: ResourceList { ResourceList() }

        static func reduce(value: inout ResourceList, nextValue: () -> ResourceList) {
            value.append(contentsOf: nextValue())
        }
    }
}

private struct DisplayScaleEnvironmentKey: EnvironmentKey {
    static var defaultValue: CGFloat { return 1 }
}

extension EnvironmentValues {
    public var displayScale: CGFloat {
        set { self[DisplayScaleEnvironmentKey.self] = newValue }
        get { self[DisplayScaleEnvironmentKey.self] }
    }
}

private struct ResourceBundleKey: EnvironmentKey {
    static let defaultValue: Bundle? = nil
}

extension EnvironmentValues {
    public var resourceBundle: Bundle? {
        get { self[ResourceBundleKey.self] }
        set { self[ResourceBundleKey.self] = newValue }
    }
}
