//
//  File: Alignment.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization

public protocol AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat
    static func _combineExplicit(childValue: CGFloat, _ n: Int, into parentValue: inout CGFloat?)
}

@usableFromInline
struct AlignmentKey: Hashable, Comparable {
    let bits: UInt
    public static func < (lhs: AlignmentKey, rhs: AlignmentKey) -> Bool {
        lhs.bits < rhs.bits
    }

    init(bits: UInt) {
        self.bits = bits
    }

    var axis: Axis {
        (bits & 1) == 0 ? .horizontal : .vertical
    }

    var id: AlignmentID.Type {
        AlignmentKeyTypeCache.id(for: self)
    }

    init(id: AlignmentID.Type, axis: Axis) {
        self.bits = AlignmentKeyTypeCache.bits(for: id, axis: axis)
    }

    func defaultValue(in context: ViewDimensions) -> CGFloat {
        id.defaultValue(in: context)
    }

    func combineExplicit<S>(_ values: S) -> CGFloat? where S: Sequence, S.Element == CGFloat? {
        var combined: CGFloat?
        var n = 0
        for value in values {
            guard let value else { continue }
            id._combineExplicit(childValue: value, n, into: &combined)
            n += 1
        }
        return combined
    }

    var suppressesStackExplicitPropagation: Bool {
        let objectID = ObjectIdentifier(id)
        return objectID == ObjectIdentifier(HorizontalAlignment.Leading.self) ||
            objectID == ObjectIdentifier(HorizontalAlignment.Center.self) ||
            objectID == ObjectIdentifier(HorizontalAlignment.Trailing.self) ||
            objectID == ObjectIdentifier(VerticalAlignment.Top.self) ||
            objectID == ObjectIdentifier(VerticalAlignment.Center.self) ||
            objectID == ObjectIdentifier(VerticalAlignment.Bottom.self)
    }
}

extension AlignmentID {
    public static func _combineExplicit(childValue: CGFloat,
                                        _ n: Int,
                                        into parentValue: inout CGFloat?) {
        if let current = parentValue {
            parentValue = (childValue + current * CGFloat(n)) / CGFloat(n + 1)
        } else {
            precondition(n == 0)
            parentValue = childValue
        }
    }
}

private enum AlignmentKeyTypeCache {
    private struct State: @unchecked Sendable {
        var indexes: [ObjectIdentifier: UInt] = [:]
        var ids: [AlignmentID.Type] = []
    }

    private static let state = Mutex(State())

    static func bits(for id: AlignmentID.Type, axis: Axis) -> UInt {
        state.withLock { state in
            let key = ObjectIdentifier(id)
            let index: UInt
            if let existing = state.indexes[key] {
                index = existing
            } else {
                index = UInt(state.ids.count)
                state.ids.append(id)
                state.indexes[key] = index
            }

            return ((index << 1) + 2) | UInt(axis.rawValue)
        }
    }

    static func id(for key: AlignmentKey) -> AlignmentID.Type {
        guard key.bits >= 2 else {
            fatalError("Invalid AlignmentKey bits: \(key.bits)")
        }
        let index = Int((key.bits - 2) >> 1)

        return state.withLock { state in
            guard state.ids.indices.contains(index) else {
                fatalError("Unknown AlignmentKey bits: \(key.bits)")
            }
            return state.ids[index]
        }
    }
}

public struct HorizontalAlignment: Equatable {
    public init(_ id: AlignmentID.Type) {
        self.key = AlignmentKey(id: id, axis: .horizontal)
    }

    @usableFromInline
    let key: AlignmentKey
    init(alignmentKey: UInt) {
        self.key = AlignmentKey(bits: alignmentKey)
    }

    fileprivate enum Leading: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
    }

    fileprivate enum Center: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context.width * 0.5
        }
    }

    fileprivate enum Trailing: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context.width
        }
    }

    public static let leading = HorizontalAlignment(Leading.self)
    public static let center = HorizontalAlignment(Center.self)
    public static let trailing = HorizontalAlignment(Trailing.self)

    public func combineExplicit<S>(_ values: S) -> CGFloat? where S: Sequence, S.Element == CGFloat? {
        key.combineExplicit(values)
    }
}

public struct VerticalAlignment: Equatable {
    public init(_ id: AlignmentID.Type) {
        self.key = AlignmentKey(id: id, axis: .vertical)
    }

    @usableFromInline
    let key: AlignmentKey
    init(alignmentKey: UInt) {
        self.key = AlignmentKey(bits: alignmentKey)
    }

    fileprivate enum Top: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { 0 }
    }

    fileprivate enum Center: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context.height * 0.5
        }
    }

    fileprivate enum Bottom: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context.height
        }
    }

    fileprivate enum FirstTextBaseline: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context.height
        }
    }

    fileprivate enum LastTextBaseline: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context.height
        }

        static func _combineExplicit(childValue: CGFloat,
                                     _ n: Int,
                                     into parentValue: inout CGFloat?) {
            parentValue = max(parentValue ?? -CGFloat.infinity, childValue)
        }
    }

    public static let top = VerticalAlignment(Top.self)
    public static let center = VerticalAlignment(Center.self)
    public static let bottom = VerticalAlignment(Bottom.self)
    public static let firstTextBaseline = VerticalAlignment(FirstTextBaseline.self)
    public static let lastTextBaseline = VerticalAlignment(LastTextBaseline.self)

    public func combineExplicit<S>(_ values: S) -> CGFloat? where S: Sequence, S.Element == CGFloat? {
        key.combineExplicit(values)
    }
}

/// Marker used by HVStack for its minor-axis alignment type.
protocol AlignmentGuide {}

extension HorizontalAlignment: AlignmentGuide {}
extension VerticalAlignment: AlignmentGuide {}

public struct Alignment: Equatable {
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    @inlinable public init(horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public static let center = Alignment(horizontal: .center, vertical: .center)
    public static let leading = Alignment(horizontal: .leading, vertical: .center)
    public static let trailing = Alignment(horizontal: .trailing, vertical: .center)

    public static let top = Alignment(horizontal: .center, vertical: .top)
    public static let bottom = Alignment(horizontal: .center, vertical: .bottom)

    public static let topLeading = Alignment(horizontal: .leading, vertical: .top)
    public static let topTrailing = Alignment(horizontal: .trailing, vertical: .top)

    public static let bottomLeading = Alignment(horizontal: .leading, vertical: .bottom)
    public static let bottomTrailing = Alignment(horizontal: .trailing, vertical: .bottom)
}

extension AlignmentKey: Sendable {}
extension HorizontalAlignment: Sendable {}
extension VerticalAlignment: Sendable {}
extension Alignment: Sendable {}
