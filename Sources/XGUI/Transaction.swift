//
//  File: Transaction.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct Transaction {
    public init() {
        self.animation = nil
        self.isContinuous = false
        self.disablesAnimations = false
    }

    public var isContinuous: Bool

    public init(animation: Animation?) {
        self.animation = animation
        self.isContinuous = false
        self.disablesAnimations = false
    }

    public var animation: Animation?
    public var disablesAnimations: Bool
}

@usableFromInline
class AnyTransitionBox {
}

public struct AnyTransition {
    fileprivate let box: AnyTransitionBox

    public static var slide: AnyTransition {
        fatalError()
    }
    public static func offset(_ offset: CGSize) -> AnyTransition {
        fatalError()
    }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        fatalError()
    }
    public func combined(with other: AnyTransition) -> AnyTransition {
        fatalError()
    }
    public static func push(from edge: Edge) -> AnyTransition {
        fatalError()
    }
    public static var scale: AnyTransition {
        fatalError()
    }
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition {
        fatalError()
    }
    public static let opacity: AnyTransition = AnyTransition(box: AnyTransitionBox())

    public static func modifier<E>(active: E, identity: E) -> AnyTransition where E: ViewModifier {
        fatalError()
    }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        fatalError()
    }

    public static let identity: AnyTransition = AnyTransition(box: AnyTransitionBox())

    public static func move(edge: Edge) -> AnyTransition {
        fatalError()
    }

    public func animation(_ animation: Animation?) -> AnyTransition {
        fatalError()
    }
}
