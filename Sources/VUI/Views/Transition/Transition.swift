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

public enum TransitionPhase {
    case willAppear
    case identity
    case didDisappear
    public var isIdentity: Bool {
        get { fatalError() }
    }
    public static func == (a: TransitionPhase, b: TransitionPhase) -> Bool {
        fatalError()
    }
    public func hash(into hasher: inout Swift.Hasher) {
        fatalError()
    }
    public var hashValue: Int {
        get { fatalError() }
    }
}

extension TransitionPhase {
    public var value: Double {
        get { fatalError() }
    }
}

public struct TransitionProperties: Sendable {
    public var hasMotion: Bool
    public init(hasMotion: Bool = true) {
        self.hasMotion = hasMotion
    }
}


@usableFromInline
class AnyTransitionBox: @unchecked Sendable {
}

public struct AnyTransition: Sendable {
    fileprivate let box: AnyTransitionBox

    public init<T>(_ transition: T) where T: Transition {
        fatalError()
    }
    
    init(box: AnyTransitionBox) {
        self.box = box
    }

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
