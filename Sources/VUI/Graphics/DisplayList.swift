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

    typealias Item = (GraphicsContext) -> Void
    var items: [Item] = []
    var debugItems: [Item] = []

    mutating func append(contentsOf other: Self) {
        self.items.append(contentsOf: other.items)
        self.debugItems.append(contentsOf: other.debugItems)
    }
}

extension DisplayList {
    struct Key: PreferenceKey {
        typealias Value = DisplayList
        static var defaultValue: DisplayList { DisplayList() }

        static func reduce(value: inout DisplayList, nextValue: () -> DisplayList) {
            let next = nextValue()
            value.items.append(contentsOf: next.items)
            value.debugItems.append(contentsOf: next.debugItems)
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
