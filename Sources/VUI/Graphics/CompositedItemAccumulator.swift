//
//  File: CompositedItemAccumulator.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

struct CompositedItemAccumulator {
    var version: DisplayList.Version
    var contentSeed: DisplayList.Seed
    var options: DisplayList.Options
    var items: [DisplayList.Item] = []
    var pendingItems: [DisplayList.Item] = []
    var currentBlend: GraphicsContext.BlendMode = .normal
    var hasBlending = false
    var drawingGroup = false

    mutating func add(
        item: DisplayList.Item,
        blend: GraphicsContext.BlendMode,
        needsDrawingGroup: Bool
    ) {
        if pendingItems.isEmpty || currentBlend != blend {
            commitPendingItems()
            currentBlend = blend
        }
        var item = item
        item.identity = .none
        pendingItems.append(item)
        hasBlending = hasBlending || blend != .normal
        drawingGroup = drawingGroup || needsDrawingGroup
    }

    mutating func commitPendingItems() {
        guard !pendingItems.isEmpty else { return }
        let frame = pendingItems.reduce(CGRect.null) { $0.union($1.frame) }
        var contents = DisplayList()
        contents.items = pendingItems.map { item in
            var item = item
            item.frame.origin.x -= frame.origin.x
            item.frame.origin.y -= frame.origin.y
            return item
        }
        contents.interpolationBounds = CGRect(origin: .zero, size: frame.size)
        var item = DisplayList.Item(
            effect: .identity, contents: contents, frame: frame, version: version
        )
        item.canonicalize(options: options)
        if drawingGroup {
            item.addDrawingGroup(contentSeed: contentSeed)
            drawingGroup = false
        }
        if currentBlend != .normal {
            item.addEffect(.blendMode(currentBlend))
        }
        items.append(item)
        pendingItems.removeAll(keepingCapacity: true)
    }
}
