//
//  File: DisplayList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Ordered collection of rendering commands produced by the view tree.
// Propagated to the scene root via the DisplayList.Key preference.
// TODO: Define rendering command types and implement accumulation logic.
struct DisplayList {
    struct Version {
        let value: Int
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

    // Renderer-side metadata attached to a display list for state, content transitions, and
    // interpolator group routing.
    enum Effect {
        case state(StrongHash)
        case contentTransition(ContentTransition.State)
        case interpolatorRoot(InterpolatorGroup, CGPoint, CGSize)
        case interpolatorLayer(InterpolatorGroup, UInt32)
        case interpolatorAnimation(InterpolatorAnimation)
    }

    // Effect wrapper that keeps the original display-list contents with the effect marker.
    struct EffectItem {
        var effect: Effect
        var contents: DisplayList
    }

    // Lightweight render-item summary used by interpolation before backend typed
    // commands replace closure-backed drawing.
    struct ItemRecord: Equatable {
        enum Kind: UInt8, Equatable {
            case closure
            case shapeFill
            case image
            case text
            case effect
            case debug
        }

        enum EffectKind: UInt8, Equatable {
            case generic
            case opacity
            case blur
            case geometry
            case crossFade
        }

        var kind: Kind
        var effectKind: EffectKind?
        var bounds: CGRect?
        var opacity: Double?
        var blurRadius: CGFloat?
        var blurIsOpaque: Bool?
        var affineTransform: CGAffineTransform?
        var sourceFraction: Float?
        var targetFraction: Float?

        init(
            kind: Kind,
            bounds: CGRect? = nil,
            effectKind: EffectKind? = nil,
            opacity: Double? = nil,
            blurRadius: CGFloat? = nil,
            blurIsOpaque: Bool? = nil,
            affineTransform: CGAffineTransform? = nil,
            sourceFraction: Float? = nil,
            targetFraction: Float? = nil
        ) {
            self.kind = kind
            self.effectKind = kind == .effect ? effectKind ?? .generic : nil
            self.bounds = bounds
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
        }
    }

    struct Item {
        var record: ItemRecord
        private let body: (GraphicsContext) -> Void

        init(record: ItemRecord, _ body: @escaping (GraphicsContext) -> Void) {
            self.record = record
            self.body = body
        }

        func callAsFunction(_ context: GraphicsContext) {
            body(context)
        }
    }

    var items: [Item] = []
    var debugItems: [Item] = []
    var effects: [EffectItem] = []
    // Backend-local bounds used by display-list interpolation before typed command storage exists.
    var interpolationBounds: CGRect?

    var itemRecords: [ItemRecord] {
        items.map(\.record)
    }

    var debugItemRecords: [ItemRecord] {
        debugItems.map(\.record)
    }

    mutating func append(contentsOf other: Self) {
        self.items.append(contentsOf: other.items)
        self.debugItems.append(contentsOf: other.debugItems)
        self.effects.append(contentsOf: other.effects)
        self.recordInterpolationBounds(other.interpolationBounds)
    }

    mutating func appendItem(
        kind: ItemRecord.Kind = .closure,
        bounds: CGRect? = nil,
        effectKind: ItemRecord.EffectKind? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let record = ItemRecord(kind: kind, bounds: bounds, effectKind: effectKind)
        items.append(Item(record: record, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendOpacityItem(
        bounds: CGRect? = nil,
        opacity: Double,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let record = ItemRecord(
            kind: .effect,
            bounds: bounds,
            effectKind: .opacity,
            opacity: opacity
        )
        items.append(Item(record: record, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendBlurItem(
        bounds: CGRect? = nil,
        radius: CGFloat,
        isOpaque: Bool,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let record = ItemRecord(
            kind: .effect,
            bounds: bounds,
            effectKind: .blur,
            blurRadius: radius,
            blurIsOpaque: isOpaque
        )
        items.append(Item(record: record, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendGeometryItem(
        bounds: CGRect? = nil,
        affineTransform: CGAffineTransform,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let record = ItemRecord(
            kind: .effect,
            bounds: bounds,
            effectKind: .geometry,
            affineTransform: affineTransform
        )
        items.append(Item(record: record, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendCrossFadeItem(
        bounds: CGRect? = nil,
        sourceFraction: Float,
        targetFraction: Float,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let record = ItemRecord(
            kind: .effect,
            bounds: bounds,
            effectKind: .crossFade,
            sourceFraction: sourceFraction,
            targetFraction: targetFraction
        )
        items.append(Item(record: record, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendDebugItem(
        bounds: CGRect? = nil,
        _ item: @escaping (GraphicsContext) -> Void
    ) {
        let bounds = Self.itemRecordBounds(bounds)
        let record = ItemRecord(kind: .debug, bounds: bounds)
        debugItems.append(Item(record: record, item))
        recordInterpolationBounds(bounds)
    }

    mutating func appendEffect(_ effect: Effect, contents: DisplayList) {
        effects.append(EffectItem(effect: effect, contents: contents))
        recordInterpolationBounds(contents.interpolationBounds)
    }

    private static func itemRecordBounds(_ bounds: CGRect?) -> CGRect? {
        guard let bounds = bounds?.standardized,
              !bounds.isNull,
              bounds.width > 0,
              bounds.height > 0
        else { return nil }
        return bounds
    }

    mutating func recordInterpolationBounds(_ rect: CGRect?) {
        guard let rect = Self.itemRecordBounds(rect) else { return }
        if let current = interpolationBounds {
            interpolationBounds = current.union(rect)
        } else {
            interpolationBounds = rect
        }
    }

    static func effect(_ effect: Effect, contents: DisplayList) -> DisplayList {
        var list = DisplayList()
        list.appendEffect(effect, contents: contents)
        return list
    }

    func forEachRenderItem(includeDebug: Bool = true, _ body: (Item) -> Void) {
        for item in items {
            body(item)
        }
        for effectItem in effects {
            effectItem.forEachRenderItem(includeDebug: includeDebug, body)
        }
        if includeDebug {
            for item in debugItems {
                body(item)
            }
        }
    }

    func draw(in context: GraphicsContext, includeDebug: Bool = true) {
        forEachRenderItem(includeDebug: includeDebug) { item in
            item(context)
        }
    }

    func hasSameInterpolationSurface(as other: DisplayList) -> Bool {
        itemSurfaceMatches(
            records: itemRecords,
            count: items.count,
            otherRecords: other.itemRecords,
            otherCount: other.items.count
        ) &&
        itemSurfaceMatches(
            records: debugItemRecords,
            count: debugItems.count,
            otherRecords: other.debugItemRecords,
            otherCount: other.debugItems.count
        ) &&
            effectSurfaceMatches(effects, other.effects) &&
            interpolationBounds == other.interpolationBounds
    }

    private func itemSurfaceMatches(
        records: [ItemRecord],
        count: Int,
        otherRecords: [ItemRecord],
        otherCount: Int
    ) -> Bool {
        guard count == otherCount else { return false }
        let hasCompleteRecords = records.count == count && otherRecords.count == otherCount
        if hasCompleteRecords {
            return records == otherRecords
        }
        return records.isEmpty && otherRecords.isEmpty
    }

    private func effectSurfaceMatches(
        _ effects: [EffectItem],
        _ otherEffects: [EffectItem]
    ) -> Bool {
        guard effects.count == otherEffects.count else { return false }
        return zip(effects, otherEffects).allSatisfy { lhs, rhs in
            lhs.effect.surfaceRecord == rhs.effect.surfaceRecord &&
                lhs.contents.hasSameInterpolationSurface(as: rhs.contents)
        }
    }
}

private struct DisplayListEffectSurfaceRecord: Equatable {
    enum Kind: UInt8, Equatable {
        case state
        case contentTransition
        case interpolatorRoot
        case interpolatorLayer
        case interpolatorAnimation
    }

    var kind: Kind
    var hash: StrongHash?
    var contentTransitionState: ContentTransition.State?
    var groupID: ObjectIdentifier?
    var origin: CGPoint?
    var size: CGSize?
    var layerID: UInt32?
    var animationValue: StrongHash?
    var animation: Animation?
}

private extension DisplayList.Effect {
    var surfaceRecord: DisplayListEffectSurfaceRecord {
        switch self {
        case let .state(hash):
            return DisplayListEffectSurfaceRecord(kind: .state, hash: hash)
        case let .contentTransition(state):
            return DisplayListEffectSurfaceRecord(
                kind: .contentTransition,
                contentTransitionState: state
            )
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
        surfaceRecord == other.surfaceRecord
    }
}

extension DisplayList.EffectItem {
    fileprivate func forEachRenderItem(
        includeDebug: Bool,
        _ body: (DisplayList.Item) -> Void
    ) {
        switch effect {
        case .contentTransition:
            contents.forEachRenderItem(includeDebug: includeDebug, body)
        case .state, .interpolatorRoot, .interpolatorLayer, .interpolatorAnimation:
            break
        }
    }
}

extension DisplayList {
    struct Key: PreferenceKey {
        typealias Value = DisplayList
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

    typealias Task = (GraphicsContext) -> Void
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
