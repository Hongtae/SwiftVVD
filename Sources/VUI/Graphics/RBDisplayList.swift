//
//  File: RBDisplayList.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

struct RBColorSpace: RawRepresentable, Equatable {
    var rawValue: UInt32
    static let sRGB = Self(rawValue: 1)
    static let linearSRGB = Self(rawValue: 2)
}

struct RBBlendMode: RawRepresentable, Equatable {
    var rawValue: Int32
    static let normal = Self(rawValue: 0)
}

typealias RBDrawingState = UnsafeMutablePointer<RBDisplayList.State>

final class RBDisplayList: RBDisplayListContents {
    struct State {
        unowned let list: RBDisplayList
        var defaultColorSpace: RBColorSpace
        var transform: CGAffineTransform = .identity
        var clipBoundingRect: CGRect
        var viewTransform: CGAffineTransform = .identity
        var contentOffset: CGPoint = .zero
        var maskTexture: Texture?
        var filters: [(GraphicsContext.Filter, GraphicsContext.FilterOptions)] = []
        var isRecording = false
        var recordedClips: [GraphicsContext.DrawingClip] = []
        var contentBoundsState = GraphicsContext.ContentBoundsState()

        init(list: RBDisplayList, viewport: CGRect,
             colorSpace: RBColorSpace) {
            self.list = list
            self.defaultColorSpace = colorSpace
            self.clipBoundingRect = viewport
        }
    }

    let drawingState: RBDrawingState
    var defaultColorSpace: RBColorSpace {
        get { RBDrawingStateGetDefaultColorSpace(drawingState) }
        set { RBDrawingStateSetDefaultColorSpace(drawingState, newValue) }
    }
    private(set) var ownedStateCount = 0
    private(set) var items: [Item] = []
    private(set) var boundingRect = CGRect.null
    var isEmpty: Bool { items.isEmpty }

    init(viewport: CGRect, colorSpace: RBColorSpace = .sRGB) {
        self.drawingState = .allocate(capacity: 1)
        drawingState.initialize(to: State(list: self, viewport: viewport, colorSpace: colorSpace))
    }

    deinit {
        precondition(ownedStateCount == 0)
        drawingState.deinitialize(count: 1)
        drawingState.deallocate()
    }

    func append(_ item: Item, bounds: CGRect) {
        items.append(item)
        if !bounds.isNull, !bounds.isEmpty {
            boundingRect = boundingRect.union(bounds)
        }
    }

    func draw(in context: GraphicsContext) {
        // The value snapshot also permits replay into this destination.
        let items = items
        for item in items { item.draw(in: context) }
    }

    func moveContents() -> RBMovedDisplayListContents {
        let contents = RBMovedDisplayListContents(items: items, boundingRect: boundingRect)
        items = []
        boundingRect = .null
        return contents
    }

    fileprivate func copyState(_ source: RBDrawingState) -> RBDrawingState {
        precondition(source.pointee.list === self)
        let state = RBDrawingState.allocate(capacity: 1)
        state.initialize(to: source.pointee)
        ownedStateCount += 1
        return state
    }

    fileprivate func destroyState(_ state: RBDrawingState) {
        precondition(state != drawingState && state.pointee.list === self)
        precondition(ownedStateCount > 0)
        state.deinitialize(count: 1)
        state.deallocate()
        ownedStateCount -= 1
    }
}

final class RBMovedDisplayListContents: RBDisplayListContents {
    let items: [RBDisplayList.Item]
    let boundingRect: CGRect
    var isEmpty: Bool { items.isEmpty }

    init(items: [RBDisplayList.Item], boundingRect: CGRect) {
        self.items = items
        self.boundingRect = boundingRect
    }

    func draw(in context: GraphicsContext) {
        for item in items { item.draw(in: context) }
    }
}

func RBDrawingStateInit(_ state: RBDrawingState) -> RBDrawingState {
    state.pointee.list.copyState(state)
}

func RBDrawingStateDestroy(_ state: RBDrawingState) {
    state.pointee.list.destroyState(state)
}

func RBDrawingStateGetDefaultColorSpace(_ state: RBDrawingState) -> RBColorSpace {
    state.pointee.defaultColorSpace
}

func RBDrawingStateSetDefaultColorSpace(_ state: RBDrawingState, _ colorSpace: RBColorSpace) {
    state.pointee.defaultColorSpace = colorSpace
}
