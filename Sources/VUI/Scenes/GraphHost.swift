//
//  File: GraphHost.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GraphHost is the root AttributeGraph-owning base class.
// `data` wraps the shared graph core with a per-host context pointer.
// Multiple hosts can share one underlying AttributeGraph while each holds its
// own AttributeGraphRef.
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

// GraphDelegate provides transaction/update/change callbacks for graph hosts.
protocol GraphDelegate: AnyObject {
    func beginTransaction()
    func updateGraph<T>(body: (GraphHost) -> T) -> T
    func graphDidChange()
}
