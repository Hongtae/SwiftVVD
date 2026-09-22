//
//  File: CoordinateSpace.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

public enum CoordinateSpace {
    case global
    case local
    case named(AnyHashable)
    @_spi(Internal)
    case id(ID)
}

extension CoordinateSpace {
    static var root: CoordinateSpace { .global }

    @_spi(Internal)
    public struct ID: Equatable, Hashable, Sendable {
        let value: UniqueID

        init(rawValue: UniqueID = UniqueID()) {
            value = rawValue
        }
    }

    /// Keeps user-provided names distinct from generated framework identities.
    enum Name: Equatable {
        case name(AnyHashable)
        case id(ID)

        var space: CoordinateSpace {
            switch self {
            case let .name(name):
                return .named(name)
            case let .id(id):
                return .id(id)
            }
        }
    }

    var internalID: ID? {
        guard case let .id(id) = self else {
            return nil
        }
        return id
    }
}

/// A transform-local identifier for a coordinate-space boundary.
///
/// Positive values refer to entries in a `ViewTransform` coordinate-space
/// chain. Non-positive values are reserved for framework coordinate spaces.
struct CoordinateSpaceTag: Equatable, Hashable, Sendable {
    var base: Int

    init(base: Int) {
        self.base = base
    }

    static var local: CoordinateSpaceTag {
        CoordinateSpaceTag(base: -1)
    }

    static var root: CoordinateSpaceTag {
        CoordinateSpaceTag(base: 0)
    }

    static var global: CoordinateSpaceTag {
        root
    }

    static var invalid: CoordinateSpaceTag {
        CoordinateSpaceTag(base: -3)
    }
}

enum ScrollCoordinateSpace: Equatable, Hashable, Sendable {
    case horizontal
    case vertical
    case all
    case content
    case safeArea

    // Each role owns one lazy process identity shared by its producers and
    // every transform marker that resolves that role.
    private static let horizontalID = CoordinateSpace.ID()
    private static let verticalID = CoordinateSpace.ID()
    private static let allID = CoordinateSpace.ID()
    private static let contentID = CoordinateSpace.ID()
    private static let safeAreaID = CoordinateSpace.ID()

    var id: CoordinateSpace.ID {
        switch self {
        case .horizontal:
            return Self.horizontalID
        case .vertical:
            return Self.verticalID
        case .all:
            return Self.allID
        case .content:
            return Self.contentID
        case .safeArea:
            return Self.safeAreaID
        }
    }

    init?(id: CoordinateSpace.ID) {
        switch id {
        case Self.horizontalID:
            self = .horizontal
        case Self.verticalID:
            self = .vertical
        case Self.allID:
            self = .all
        case Self.contentID:
            self = .content
        case Self.safeAreaID:
            self = .safeArea
        default:
            return nil
        }
    }
}

extension CoordinateSpace {
    public var isGlobal: Bool {
        self == .global
    }
    public var isLocal: Bool {
        self == .local
    }
}

extension CoordinateSpace: Equatable, Hashable {
}

@available(*, unavailable)
extension CoordinateSpace: Sendable {}

public protocol CoordinateSpaceProtocol {
    var coordinateSpace: CoordinateSpace { get }
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
    public var coordinateSpace: CoordinateSpace {
        name.space
    }
    var name: CoordinateSpace.Name

    init(name: CoordinateSpace.Name) {
        self.name = name
    }
}

@available(*, unavailable)
extension NamedCoordinateSpace: Sendable {}

public struct _CoordinateSpaceModifier<Name>: Equatable where Name: Hashable {
    public var name: Name

    public init(name: Name) {
        self.name = name
    }

    public typealias Body = Never

    public static func _makeViewInputs(
        modifier: _GraphValue<Self>,
        inputs: inout _ViewInputs
    ) {
        guard let graph = _AGGraph.current else {
            fatalError("_CoordinateSpaceModifier._makeViewInputs requires AG context")
        }
        let animatedFrame = inputs.base.cachedEnvironment.value.animatedFrame
        let position = animatedFrame?._animatedPosition ?? inputs.position
        let size: Attribute<CGSize>
        if let animatedSize = animatedFrame?._animatedCGSize {
            size = animatedSize
        } else {
            let viewSize = animatedFrame?._animatedSize ?? inputs.size
            size = graph.makeRule { viewSize.value.value }
        }
        inputs.transform = graph.makeRule(CoordinateSpaceTransform(
            _modifier: modifier._attribute,
            _transform: inputs.transform,
            _position: position,
            _size: size
        ))
    }
}

extension _CoordinateSpaceModifier: ViewInputsModifier {
}

private struct CoordinateSpaceTransform<Name: Hashable>: Rule {
    typealias Value = ViewTransform

    var _modifier: Attribute<_CoordinateSpaceModifier<Name>>
    var _transform: Attribute<ViewTransform>
    var _position: Attribute<CGPoint>
    var _size: Attribute<CGSize>

    var value: ViewTransform {
        var value = _transform.value
        value.appendPosition(_position.value)
        value.appendSizedSpace(
            name: AnyHashable(_modifier.value.name),
            size: _size.value
        )
        return value
    }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace {
        NamedCoordinateSpace(name: .name(AnyHashable(name)))
    }

    static func id(_ id: CoordinateSpace.ID) -> NamedCoordinateSpace {
        NamedCoordinateSpace(name: .id(id))
    }

    public static func scrollView(axis: Axis) -> Self {
        switch axis {
        case .horizontal:
            return id(ScrollCoordinateSpace.horizontal.id)
        case .vertical:
            return id(ScrollCoordinateSpace.vertical.id)
        }
    }

    public static var scrollView: NamedCoordinateSpace {
        id(ScrollCoordinateSpace.all.id)
    }
}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol, Sendable {
    public init() {}
    public var coordinateSpace: CoordinateSpace {
        .local
    }
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    public static var local: LocalCoordinateSpace {
        LocalCoordinateSpace()
    }
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol, Sendable {
    public init() {}
    public var coordinateSpace: CoordinateSpace {
        .global
    }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    public static var global: GlobalCoordinateSpace {
        GlobalCoordinateSpace()
    }
}
