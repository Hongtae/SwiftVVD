//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _Graph {
}

// Placeholder — AG 기반으로 재작성 예정
public struct _GraphValue<Value> {
    func unsafeCast<U>(to: U.Type) -> _GraphValue<U> { fatalError() }
    var isRoot: Bool { fatalError() }
    public subscript<U>(keyPath: KeyPath<Value, U>) -> _GraphValue<U> {
        get { fatalError() }
    }
}

extension _GraphValue: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool { fatalError() }
}

extension _GraphValue: Hashable {
    public func hash(into hasher: inout Hasher) { fatalError() }
}

extension _GraphValue: CustomDebugStringConvertible {
    public var debugDescription: String { fatalError() }
}

// Placeholder — AG 기반으로 재작성 예정
public struct _GraphInputs {
    var customInputs: PropertyList = .init()
}
