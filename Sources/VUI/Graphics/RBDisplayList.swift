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
        let backend: GraphicsContext.DrawingBackend
        var defaultColorSpace: RBColorSpace
        var transform: CGAffineTransform = .identity
        var clipBoundingRect: CGRect
        var viewTransform: CGAffineTransform = .identity
        var contentOffset: CGPoint = .zero
        var maskTexture: Texture
        var filters: [(GraphicsContext.Filter, GraphicsContext.FilterOptions)] = []
        var recording: GraphicsContext.DrawingCommands?
        var recordedClips: [GraphicsContext.DrawingClip] = []
        var contentBoundsState = GraphicsContext.ContentBoundsState()

        init(list: RBDisplayList, backend: GraphicsContext.DrawingBackend,
             colorSpace: RBColorSpace) {
            self.list = list
            self.backend = backend
            self.defaultColorSpace = colorSpace
            self.clipBoundingRect = backend.viewport
            self.maskTexture = backend.pipeline.defaultMaskTexture
        }
    }

    let drawingState: RBDrawingState
    var defaultColorSpace: RBColorSpace {
        get { RBDrawingStateGetDefaultColorSpace(drawingState) }
        set { RBDrawingStateSetDefaultColorSpace(drawingState, newValue) }
    }
    private(set) var ownedStateCount = 0

    init(backend: GraphicsContext.DrawingBackend, colorSpace: RBColorSpace = .sRGB) {
        self.drawingState = .allocate(capacity: 1)
        drawingState.initialize(to: State(list: self, backend: backend, colorSpace: colorSpace))
    }

    deinit {
        precondition(ownedStateCount == 0)
        drawingState.deinitialize(count: 1)
        drawingState.deallocate()
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
