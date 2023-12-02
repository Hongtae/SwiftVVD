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

public struct _ViewInputs {
    let sharedContext: SharedContext

    var preferences: [String?: Any] = [:]

    var modifiers: [any ViewModifier] = []
    var backgroundLayers: [ViewLayer] = []
    var overlayLayers: [ViewLayer] = []
    var traits: [ObjectIdentifier: Any] = [:]
    var sourceWrites: [ObjectIdentifier: Any] = [:]

    var labelStyleModifiers: [any LabelStyle] = []
    
    var environmentValues: EnvironmentValues

    var transform: CGAffineTransform
    var position: CGPoint
    var size: CGSize
    var safeAreaInsets: EdgeInsets
    var defaultLayout: (any Layout)
}

public struct _ViewOutputs {
    var preferences: [String?: Any] = [:]

    enum Item {
        case view(ViewProxy)
        case layout(any Layout, _ViewListOutputs)
    }
    let item: Item
    var view: ViewProxy {
        if case let .view(view) = item { return view }
        fatalError()
    }
}

public struct _ViewListInputs {
    var inputs: _ViewInputs
}

public struct _ViewListOutputs {
    var preferences: [String?: Any] = [:]

    struct ViewInfo {
        let view: AnyView
        let inputs: _ViewInputs
    }

    enum Item {
        case view(ViewInfo)
        case viewList([_ViewListOutputs])
    }
    var item: Item

    var views: [ViewInfo] {
        var outputs: [ViewInfo] = []
        if case let .view(view) = item {
            outputs.append(view)
        }
        if case let .viewList(list) = item {
            outputs.append(contentsOf: list.flatMap { $0.views } )
        }
        return outputs
    }

    var viewProxies: [ViewProxy] {
        let viewOutputs = self.views.map {
            $0.view.makeView(graph: _Graph(), inputs: $0.inputs)
        }
        return viewOutputs.compactMap {
            if case let .view(view) = $0.item { return view }
            return nil
        }
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
