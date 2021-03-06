//
//  File: BVH.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022 Hongtae Kim. All rights reserved.
//

import Foundation

public class BVH {
    var aabbOffset: Vector3
    var aabbScale: Vector3

    struct AABBNode {
        var min: UInt16
        var max: UInt16
        var treeStride: Int32
    }

    var nodes: [AABBNode] = []

    public init() {
        self.aabbOffset = .zero
        self.aabbScale = .init(1, 1, 1)
    }
}
