//
//  File: Graph.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public struct _Graph {
}

public struct _GraphInputs {
}

public struct _ViewInputs {
    let preferences: [String?: Any] = [:]
    let sharedContext: SharedContext
    let modifiers: [any ViewModifier]
    let environmentValues: EnvironmentValues

    let transform: CGAffineTransform
    let position: CGPoint
    //let containerPosition: CGPoint
    let size: CGSize
    let safeAreaInsets: EdgeInsets
}

public struct _ViewOutputs {
    var preferences: [String?: Any] = [:]
    //var _layoutComputer: Any? = nil
    var layout: (any Layout)? = nil
    var viewProxy: any ViewProxy
    var subviews: [any ViewProxy] = []
}

public struct _ViewListInputs {
    let preferences: [String?: Any] = [:]
    let sharedContext: SharedContext
    let modifiers: [any ViewModifier]
    let environmentValues: EnvironmentValues

    let transform: CGAffineTransform
    let position: CGPoint
    let size: CGSize

    let safeAreaInsets: EdgeInsets
}

public struct _ViewListOutputs {
    var preferences: [String?: Any] = [:]
    var views: [any ViewProxy]
}

public struct _GraphValue<Value>: Equatable {
    var value: Value
    init(_ value: Value) {
        self.value = value
    }

    public subscript<U>(keyPath: KeyPath<Value, U>) -> _GraphValue<U> {
        _GraphValue<U>(self.value[keyPath: keyPath])
    }

    public static func == (a: _GraphValue<Value>, b: _GraphValue<Value>) -> Bool {
        let length = MemoryLayout<Value>.size
        return withUnsafeBytes(of: a.value) { a in
            withUnsafeBytes(of: b.value) { b in
                for i in 0..<length {
                    if a[i] != b[i] { return false }
                }
                return true
            }
        }
    }
}
