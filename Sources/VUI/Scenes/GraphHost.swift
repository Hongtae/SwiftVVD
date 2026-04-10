//
//  File: GraphHost.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GraphHost — root AG-owning base class.
//
// data: AttributeGraphRef — wraps the shared AG::Graph core with a per-host context pointer.
// Multiple GraphHost instances (e.g. ViewGraph + GestureGraph) may share the same
// underlying AttributeGraph while each holding its own AttributeGraphRef.
class GraphHost {
    var data: AttributeGraphRef

    /// Creates a new AttributeGraph core and wraps it in an AttributeGraphRef owned by self.
    init() {
        let graph = AttributeGraph()
        self.data = AttributeGraphRef(graph: graph)
        self.data.context = self
    }

    /// Wraps an existing AttributeGraph core in a new AttributeGraphRef owned by self.
    /// Used when a second GraphHost (e.g. GestureGraph) shares the same core as another.
    init(graph: AttributeGraph) {
        self.data = AttributeGraphRef(graph: graph)
        self.data.context = self
    }
}

// GraphDelegate — AG transaction / graph change callbacks.
protocol GraphDelegate: AnyObject {
    func beginTransaction()
    func updateGraph<T>(body: (GraphHost) -> T) -> T
    func graphDidChange()
}
