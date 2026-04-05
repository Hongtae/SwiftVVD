//
//  File: GraphHost.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// GraphHost — root AG-owning base class.
class GraphHost {
    var data: AttributeGraph

    init() {
        self.data = AttributeGraph()
    }
}

// GraphDelegate — AG transaction / graph change callbacks.
protocol GraphDelegate: AnyObject {
    func beginTransaction()
    func updateGraph<T>(body: (GraphHost) -> T) -> T
    func graphDidChange()
}
