//
//  File: Transition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public protocol Transition {
    associatedtype Body: View
    @ViewBuilder func body(content: Self.Content, phase: TransitionPhase) -> Self.Body
    static var properties: TransitionProperties { get }
    typealias Content = PlaceholderContentView<Self>
    func _makeContentTransition(transition: inout _Transition_ContentTransition)
}

public struct PlaceholderContentView<Value>: View {
    public static func _makeView(view: _GraphValue<Self>, inputs: _ViewInputs) -> _ViewOutputs {
        fatalError()
    }
    public static func _makeViewList(view: _GraphValue<Self>, inputs: _ViewListInputs) -> _ViewListOutputs {
        fatalError()
    }
    public typealias Body = Never
}

extension PlaceholderContentView: _PrimitiveView {
}

public struct _Transition_ContentTransition {
}

public enum TransitionPhase: Hashable, Sendable {
    case willAppear
    case identity
    case didDisappear
    public var isIdentity: Bool {
        self == .identity
    }
}

extension TransitionPhase {
    public var value: Double {
        switch self {
        case .willAppear: return -1
        case .identity: return 0
        case .didDisappear: return 1
        }
    }
}

public struct TransitionProperties: Sendable {
    public var hasMotion: Bool
    public init(hasMotion: Bool = true) {
        self.hasMotion = hasMotion
    }
}

extension Transition {
    public static var properties: TransitionProperties {
        TransitionProperties()
    }

    public func _makeContentTransition(transition: inout _Transition_ContentTransition) {
    }
}

@usableFromInline
class AnyTransitionBox: @unchecked Sendable {
    enum Storage: @unchecked Sendable {
        case identity
        case opacity
        case slide
        case offset(CGSize)
        case push(Edge)
        case scale(CGFloat, UnitPoint)
        case modifier(active: Any, identity: Any)
        case asymmetric(insertion: AnyTransition, removal: AnyTransition)
        case combined(AnyTransition, AnyTransition)
        case animation(AnyTransition, Animation?)
        case custom(Any)
    }

    let storage: Storage

    init(storage: Storage = .identity) {
        self.storage = storage
    }
}

public struct AnyTransition: Sendable {
    fileprivate let box: AnyTransitionBox

    public init<T>(_ transition: T) where T: Transition {
        self.box = AnyTransitionBox(storage: .custom(transition))
    }
    
    init(box: AnyTransitionBox) {
        self.box = box
    }

    public static var slide: AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .slide))
    }
    public static func offset(_ offset: CGSize) -> AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .offset(offset)))
    }
    public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> AnyTransition {
        offset(CGSize(width: x, height: y))
    }
    public func combined(with other: AnyTransition) -> AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .combined(self, other)))
    }
    public static func push(from edge: Edge) -> AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .push(edge)))
    }
    public static var scale: AnyTransition {
        scale(scale: 1)
    }
    public static func scale(scale: CGFloat, anchor: UnitPoint = .center) -> AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .scale(scale, anchor)))
    }
    public static let opacity: AnyTransition = AnyTransition(box: AnyTransitionBox(storage: .opacity))

    public static func modifier<E>(active: E, identity: E) -> AnyTransition where E: ViewModifier {
        AnyTransition(box: AnyTransitionBox(storage: .modifier(active: active, identity: identity)))
    }
    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .asymmetric(insertion: insertion, removal: removal)))
    }

    public static let identity: AnyTransition = AnyTransition(box: AnyTransitionBox(storage: .identity))

    public static func move(edge: Edge) -> AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .push(edge)))
    }

    public func animation(_ animation: Animation?) -> AnyTransition {
        AnyTransition(box: AnyTransitionBox(storage: .animation(self, animation)))
    }
}
