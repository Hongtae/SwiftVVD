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
    var environmentValues: EnvironmentValues
}

public protocol _GraphInputsModifier {
    static func _makeInputs(modifier: _GraphValue<Self>, inputs: inout _GraphInputs)
}

public struct _ViewInputs {
    let sharedContext: SharedContext

    var preferences: [String?: Any] = [:]
    var modifiers: [any ViewModifier]
    var environmentValues: EnvironmentValues

    var transform: CGAffineTransform
    var position: CGPoint
    var size: CGSize
    var safeAreaInsets: EdgeInsets
}

public struct _ViewOutputs {
    var preferences: [String?: Any] = [:]
    //var _layoutComputer: Any? = nil

    typealias MakeView = ()-> any ViewProxy
    var makeView: MakeView
}

public struct _ViewListInputs {
    var inputs: _ViewInputs
}

public struct _ViewListOutputs {
    var preferences: [String?: Any] = [:]

    typealias MakeViewList = (_Graph, _ViewListInputs)-> _ViewListOutputs
    typealias MakeView = (_Graph, _ViewInputs)->_ViewOutputs
    enum Item {
        case makeView(_: MakeView)
        case viewList(_: [_ViewListOutputs])
    }
    var item: Item

    func makeViews(inputs: _ViewInputs)->[_ViewOutputs] {
        var list: [_ViewOutputs] = []
        if case let .makeView(mk) = item {
            list.append(mk(_Graph(), inputs))
        } else if case let .viewList(vl) = item {
            list.append(contentsOf: vl.map {
                $0.makeViews(inputs: inputs)
            }.joined())
        }
        return list
    }
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
