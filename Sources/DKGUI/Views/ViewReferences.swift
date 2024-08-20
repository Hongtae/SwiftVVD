//
//  File: ViewReferences.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2024 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

protocol ViewReferences<Content> where Content : View {
    associatedtype Content
    var content: Content { get }
    var graph: _GraphValue<Content> { get }
    var children: [any ViewReferences] { get }
    var subviews: [ViewContext] { get }

    func validatePath<T : View>(encloser: T, graph: _GraphValue<T>) -> Bool
    func references<T : View>(at path: _GraphValue<T>) -> (any ViewReferences)?
    func enclosingReferences<T : View>(at path: _GraphValue<T>) -> (any ViewReferences)?

    func value<T : View>(at path: _GraphValue<T>) -> T?
    func views() -> [ViewContext]
    func view<T : View>(at path: _GraphValue<T>) -> ViewContext?

    mutating func updateContent<T>(encloser: T, graph: _GraphValue<T>)
    mutating func updateContent(environment: EnvironmentValues)
    mutating func append(view: ViewContext)
}

extension ViewReferences {
    func value<T : View>(at path: _GraphValue<T>) -> T? {
        references(at: path)?.content as? T
    }

    func views() -> [ViewContext] {
        self.children.flatMap { $0.views() } + self.subviews
    }

    func view<T : View>(at path: _GraphValue<T>) -> ViewContext? {
        if path.isDescendant(of: self.graph) {
            for child in children {
                if let view = child.view(at: path) {
                    return view
                }
            }
            for view in subviews {
                if view.graph == path {
                    return view
                }
            }
        }
        return nil
    }

    func validatePath<T>(encloser: T, graph: _GraphValue<T>) -> Bool {
        if let value = graph.value(atPath: self.graph, from: encloser) {
            if children.allSatisfy( { $0.validatePath(encloser: value, graph: self.graph) }) {
                return subviews.allSatisfy {
                    $0.validatePath(encloser: value, graph: self.graph)
                }
            }
        }
        return false
    }

    func enclosingReferences<T : View>(at path: _GraphValue<T>) -> (any ViewReferences)? {
        if path.isDescendant(of: self.graph) {
            if path == self.graph {
                return self
            }
            for child in self.children {
                if let ref = child.enclosingReferences(at: path) {
                    return ref
                }
            }
            return self
        }
        return nil
    }

    func references<T : View>(at path: _GraphValue<T>) -> (any ViewReferences)? {
        if path.isDescendant(of: self.graph) {
            if path == self.graph {
                return self
            }
            for child in self.children {
                if let ref = child.references(at: path) {
                    return ref
                }
            }
        }
        return nil
    }
}

private struct GenericViewReferences<Content> : ViewReferences where Content : View {
    var content: Content
    let graph: _GraphValue<Content>
    var children: [any ViewReferences]
    var subviews: [ViewContext]

    mutating func updateContent<T>(encloser: T, graph: _GraphValue<T>) {
        if let value = graph.value(atPath: self.graph, from: encloser) {
            self.content = value
            children.indices.forEach { index in
                children[index].updateContent(encloser: value, graph: self.graph)
            }
            subviews.forEach {
                $0.updateContent(encloser: value, graph: self.graph)
            }
        } else {
            fatalError("Unable to recover value of type: \(Content.self)")
        }
    }

    mutating func updateContent(environment: EnvironmentValues) {
        self.content = environment._resolve(self.content)
        self.children.indices.forEach { index in
            self.children[index].updateContent(environment: environment)
        }
    }

    mutating func append(view: ViewContext) {
        var paths: [_GraphValue<Any>] = []
        let b = self.graph.trackRelativeGraphs(to: view.graph) {
            paths.append($0)
        }
        if b == false {
            fatalError("Unreachable path: \(view.graph.debugDescription), from: \(self.graph.debugDescription)")
        }
        if paths.isEmpty == false {
            paths = paths.dropLast(1)
            if paths.count > 0 {
                for path in paths {
                    // if sizeof View > 0 create node.
                    if let value = self.graph.value(atPath: path, from: self.content) as? any View, MemoryLayout.size(ofValue: value) > 0 {
                        func isEqual<T>(_ v: some ViewReferences, _ graph: _GraphValue<T>) -> Bool {
                            v.graph == graph
                        }
                        if self.children.firstIndex(where: { isEqual($0, path) } ) == nil {
                            func make<T : View, U>(_ content: T, _ graph: _GraphValue<U>) -> any ViewReferences {
                                GenericViewReferences<T>(content: content, graph: graph.unsafeCast(to: T.self), children: [], subviews: [])
                            }
                            self.children.append(make(value, path))
                        }
                        let index = self.children.firstIndex(where: { isEqual($0, path) } )!
                        self.children[index].append(view: view)
                        return
                    }
                }
            }
        }
        self.subviews.append(view)
    }
}

func buildViewReferences<T : View>(root: T, graph: _GraphValue<T>, subviews: [ViewContext]) -> any ViewReferences<T> {
    var root = GenericViewReferences<T>(content: root, graph: graph, children: [], subviews: [])
    subviews.forEach { root.append(view: $0) }
    return root
}
