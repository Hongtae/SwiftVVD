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
}

extension CoordinateSpace {
    struct ID: Equatable, Hashable, Sendable {
        let rawValue: UInt32

        init(rawValue: UInt32 = UInt32(truncatingIfNeeded: AGMakeUniqueID())) {
            self.rawValue = rawValue
        }
    }
}

enum ScrollCoordinateSpace: Equatable, Hashable, Sendable {
    case horizontal
    case vertical
    case all
    case content
    case safeArea

    var id: CoordinateSpace.ID {
        switch self {
        case .horizontal:
            return CoordinateSpace.ID(rawValue: UInt32.max - 0)
        case .vertical:
            return CoordinateSpace.ID(rawValue: UInt32.max - 1)
        case .all:
            return CoordinateSpace.ID(rawValue: UInt32.max - 2)
        case .content:
            return CoordinateSpace.ID(rawValue: UInt32.max - 3)
        case .safeArea:
            return CoordinateSpace.ID(rawValue: UInt32.max - 4)
        }
    }

    init?(id: CoordinateSpace.ID) {
        switch id.rawValue {
        case UInt32.max - 0:
            self = .horizontal
        case UInt32.max - 1:
            self = .vertical
        case UInt32.max - 2:
            self = .all
        case UInt32.max - 3:
            self = .content
        case UInt32.max - 4:
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

public protocol CoordinateSpaceProtocol {
    var coordinateSpace: CoordinateSpace { get }
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Equatable {
    public var coordinateSpace: CoordinateSpace {
        .named(name)
    }
    let name: AnyHashable
}

public struct _CoordinateSpaceModifier<Name>: ViewModifier, Equatable where Name: Hashable {
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

extension _CoordinateSpaceModifier: _ViewInputsModifier {
}

private struct CoordinateSpaceTransform<Name: Hashable>: Rule {
    typealias Value = ViewTransform

    var _modifier: Attribute<_CoordinateSpaceModifier<Name>>
    var _transform: Attribute<ViewTransform>
    var _position: Attribute<CGPoint>
    var _size: Attribute<CGSize>

    func updateValue() -> ViewTransform {
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
        NamedCoordinateSpace(name: name)
    }
}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol {
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

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol {
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
