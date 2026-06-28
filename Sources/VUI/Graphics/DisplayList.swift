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

    typealias Item = (GraphicsContext) -> Void
    var items: [Item] = []
    var debugItems: [Item] = []
    var effects: [EffectItem] = []
    // Backend-local bounds used by display-list interpolation before typed command storage exists.
    var interpolationBounds: CGRect?

    mutating func append(contentsOf other: Self) {
        self.items.append(contentsOf: other.items)
        self.debugItems.append(contentsOf: other.debugItems)
        self.effects.append(contentsOf: other.effects)
        self.recordInterpolationBounds(other.interpolationBounds)
    }

    mutating func recordInterpolationBounds(_ rect: CGRect?) {
        guard let rect, !rect.isNull else { return }
        if let current = interpolationBounds {
            interpolationBounds = current.union(rect)
        } else {
            interpolationBounds = rect
        }
    }

    static func effect(_ effect: Effect, contents: DisplayList) -> DisplayList {
        var list = DisplayList()
        list.effects.append(EffectItem(effect: effect, contents: contents))
        list.recordInterpolationBounds(contents.interpolationBounds)
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
