//
//  File: ViewGenerator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2025 Hongtae Kim. All rights reserved.
//

import Foundation

// Type hierarchy
//
// [P] ViewGenerator
// - [S] UnaryViewGenerator
//
// [P] StaticViewList
// - [S] StaticViewListGenerator (+ ViewListGenerator)
// - [S] StaticMultiViewGenerator (+ ViewGenerator)
//
// [P] ViewListGenerator
// - [S] StaticViewListGenerator (+ StaticMultiView)
// - [S] DynamicViewListGenerator
// - [S] WrapperViewListGenerator
//
// [P] MultiViewGenerator
// - [S] StaticMultiViewGenerator (+ StaticMultiView)
// - [S] DynamicMultiViewGenerator


protocol ViewGenerator<Content>: Equatable {
    associatedtype Content
    var graph: _GraphValue<Content> { get }
    func makeView() -> ViewContext
    mutating func mergeInputs(_ inputs: _GraphInputs)
}

extension ViewGenerator {
    static func == (lhs: Self, rhs: some ViewGenerator) -> Bool {
        if lhs.graph == rhs.graph {
            assert(type(of: lhs) == type(of: rhs))
            return true
        }
        return false
    }
}

protocol ViewListGenerator {
    func makeViewList(containerView: ViewContext) -> [any ViewGenerator]
    mutating func mergeInputs(_ inputs: _GraphInputs)
}

protocol StaticViewList {
    var views: [any ViewGenerator] { get set }
}

struct StaticViewListGenerator: ViewListGenerator, StaticViewList {
    var views: [any ViewGenerator]

    func makeViewList(containerView _: ViewContext) -> [any ViewGenerator] {
        views
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        views.updateEach { $0.mergeInputs(inputs) }
    }
}

extension ViewListGenerator where Self == StaticViewListGenerator {
    static func staticList(_ list: [any ViewGenerator]) -> StaticViewListGenerator {
        .init(views: list)
    }
    static func staticList(_ view: any ViewGenerator) -> StaticViewListGenerator {
        .init(views: [view])
    }
    static func staticList(_ view: (any ViewGenerator)?) -> StaticViewListGenerator {
        .init(views: [view].compactMap(\.self))
    }
    static var empty: StaticViewListGenerator {
        .staticList([])
    }
}

struct DynamicViewListGenerator: ViewListGenerator {
    var views: [any ViewListGenerator]

    func makeViewList(containerView: ViewContext) -> [any ViewGenerator] {
        views.flatMap {
            $0.makeViewList(containerView: containerView)
        }
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        views.updateEach { $0.mergeInputs(inputs) }
    }
}

extension ViewListGenerator where Self == DynamicViewListGenerator {
    static func dynamicList(_ list: [any ViewListGenerator]) -> DynamicViewListGenerator {
        .init(views: list)
    }
}

struct WrapperViewListGenerator: ViewListGenerator {
    var views: any ViewListGenerator
    var baseInputs: _GraphInputs
    let wrapper: (ViewContext, _GraphInputs, any ViewGenerator) -> any ViewGenerator

    func makeViewList(containerView: ViewContext) -> [any ViewGenerator] {
        views.makeViewList(containerView: containerView).map {
            wrapper(containerView, baseInputs, $0)
        }
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        views.mergeInputs(inputs)
        baseInputs.mergedInputs.append(inputs)
    }
}

extension ViewListGenerator {
    func wrapper(inputs: _GraphInputs,
                 body: @escaping (ViewContext, _GraphInputs, any ViewGenerator) -> any ViewGenerator) -> WrapperViewListGenerator {
        .init(views: self, baseInputs: inputs, wrapper: body)
    }
}

#if DEBUG
// Ensure that the UnaryViewGenerator always returns a ViewContext of the same type.
nonisolated(unsafe) var _debugViewTypes: [_GraphValue<Any>: ViewContext.Type] = [:]
#endif

struct UnaryViewGenerator<Content>: ViewGenerator {
    let graph: _GraphValue<Content>
    var baseInputs: _GraphInputs
    let body: (_GraphValue<Content>, _GraphInputs) -> ViewContext

    func makeView() -> ViewContext {
        let view = body(graph, baseInputs)
#if DEBUG
        let key = graph.unsafeCast(to: Any.self)
        if let t = _debugViewTypes[key] {
            assert(type(of: view) == t)
        } else {
            _debugViewTypes[key] = type(of: view)
        }
#endif
        return view
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        baseInputs.mergedInputs.append(inputs)
    }
}

protocol MultiViewGenerator: ViewGenerator, ViewListGenerator {
}

struct StaticMultiViewGenerator<Content>: MultiViewGenerator, StaticViewList {
    var graph: _GraphValue<Content>
    var baseInputs: _GraphInputs
    var views: [any ViewGenerator]

    func makeView() -> ViewContext {
        let subviews = views.map { $0.makeView() }
        return StaticMultiViewContext(graph: graph, subviews: subviews, inputs: baseInputs)
    }

    func makeViewList(containerView _: ViewContext) -> [any ViewGenerator] {
        views
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        views.updateEach { $0.mergeInputs(inputs) }
        baseInputs.mergedInputs.append(inputs)
    }
}

struct DynamicMultiViewGenerator<Content>: MultiViewGenerator {
    var graph: _GraphValue<Content>
    var baseInputs: _GraphInputs
    var body: any ViewListGenerator

    func makeView() -> ViewContext {
        DynamicMultiViewContext(graph: graph, body: body, inputs: baseInputs)
    }

    func makeViewList(containerView: ViewContext) -> [any ViewGenerator] {
        body.makeViewList(containerView: containerView)
    }

    mutating func mergeInputs(_ inputs: _GraphInputs) {
        body.mergeInputs(inputs)
        baseInputs.mergedInputs.append(inputs)
    }
}
