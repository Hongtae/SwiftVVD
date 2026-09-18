//
//  File: GraphicsContext+Storage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    // Resolution inputs can outlive a frame without retaining its render targets,
    // command buffer, bindings or upload arena. A queue is needed only when an
    // image provider creates a GPU resource; geometry and vector text need none.
    struct DrawingInputs {
        let sceneResources: SceneResources
        let viewport: CGRect
        let contentScaleFactor: CGFloat
        let resourceCommandQueue: CommandQueue?
    }

    final class Storage {
        final class Shared {
            let list: RBDisplayList
            var symbols: GraphicsContextSymbols?
            let _environment: EnvironmentValues
            let colorSpace: RBColorSpace

            init(list: RBDisplayList, environment: EnvironmentValues) {
                self.list = list
                self._environment = environment
                self.colorSpace = list.defaultColorSpace
            }
        }

        let shared: Shared
        let state: RBDrawingState
        // Execution resources belong to live contexts, not retained list contents.
        let inputs: DrawingInputs
        let backend: DrawingBackend?
        var environmentOverride: EnvironmentValues?
        var opacity: Float = 1
        var blendMode: RBBlendMode = .normal
        var shapeDistance: CGFloat = .nan
        let ownsState: Bool

        init(shared: Shared, state: RBDrawingState, inputs: DrawingInputs,
             backend: DrawingBackend?, ownsState: Bool) {
            self.shared = shared
            self.state = state
            self.inputs = inputs
            self.backend = backend
            self.ownsState = ownsState
        }

        deinit {
            if ownsState { RBDrawingStateDestroy(state) }
        }
    }

    init(displayList: RBDisplayList, inputs: DrawingInputs,
         backend: DrawingBackend?, environment: EnvironmentValues) {
        storage = Storage(
            shared: Storage.Shared(list: displayList, environment: environment),
            state: displayList.drawingState,
            inputs: inputs,
            backend: backend,
            ownsState: false
        )
    }

    mutating func copyOnWrite() {
        guard !isKnownUniquelyReferenced(&storage) else { return }
        let original = storage
        let state = RBDrawingStateInit(original.state)
        let shared: Storage.Shared
        if original.shared.colorSpace == RBDrawingStateGetDefaultColorSpace(state) {
            shared = original.shared
        } else {
            shared = Storage.Shared(
                list: state.pointee.list,
                environment: original.environmentOverride ?? original.shared._environment
            )
        }
        // Overrides and shape distance are local to the current storage.
        // A detached copy starts with fresh defaults for those fields.
        let copy = Storage(shared: shared, state: state, inputs: original.inputs,
                           backend: original.backend, ownsState: true)
        copy.opacity = original.opacity
        copy.blendMode = original.blendMode
        storage = copy
    }

    var symbols: GraphicsContextSymbols? {
        get { storage.shared.symbols }
        set { storage.shared.symbols = newValue }
    }

    var recording: RBDisplayList? {
        storage.state.pointee.isRecording ? storage.shared.list : nil
    }

    var recordedClips: [DrawingClip] {
        get { storage.state.pointee.recordedClips }
        _modify {
            copyOnWrite()
            yield &storage.state.pointee.recordedClips
        }
    }

    var filters: [(Filter, FilterOptions)] {
        get { storage.state.pointee.filters }
        _modify {
            copyOnWrite()
            yield &storage.state.pointee.filters
        }
    }

    var maskTexture: Texture {
        get { storage.state.pointee.maskTexture ?? drawingBackend.pipeline.defaultMaskTexture }
        set {
            copyOnWrite()
            storage.state.pointee.maskTexture = newValue
        }
    }

    var viewTransform: CGAffineTransform {
        get { storage.state.pointee.viewTransform }
        set {
            guard newValue != storage.state.pointee.viewTransform else { return }
            copyOnWrite()
            storage.state.pointee.viewTransform = newValue
        }
    }

    var contentOffset: CGPoint {
        get { storage.state.pointee.contentOffset }
        set {
            copyOnWrite()
            storage.state.pointee.contentOffset = newValue
            let scale = viewport.size / contentScaleFactor
            let offset = CGAffineTransform(translationX: newValue.x, y: newValue.y)
            let normalize = CGAffineTransform(scaleX: 1 / scale.width, y: 1 / scale.height)
            let clipSpace = CGAffineTransform(scaleX: 2, y: -2)
                .concatenating(CGAffineTransform(translationX: -1, y: 1))
            storage.state.pointee.viewTransform = offset
                .concatenating(normalize)
                .concatenating(clipSpace)
        }
    }

    var contentBoundsState: ContentBoundsState { storage.state.pointee.contentBoundsState }
    var drawingBackend: DrawingBackend {
        guard let backend = storage.backend else {
            preconditionFailure("A recording context cannot encode GPU commands.")
        }
        return backend
    }
    var sceneResources: SceneResources { storage.inputs.sceneResources }
    var viewport: CGRect { storage.inputs.viewport }
    var contentScaleFactor: CGFloat { storage.inputs.contentScaleFactor }
    var resourceCommandQueue: CommandQueue {
        guard let queue = storage.inputs.resourceCommandQueue else {
            preconditionFailure("Creating image resources requires a resource command queue.")
        }
        return queue
    }
    var renderTargets: RenderTargets { drawingBackend.renderTargets }
    var commandBuffer: CommandBuffer { drawingBackend.commandBuffer }
    var pipeline: GraphicsPipelineStates { drawingBackend.pipeline }
    var uploadBufferArena: UploadBufferArena { drawingBackend.uploadBufferArena }
    var pathGeometryScratch: StencilPathGeometryScratch { drawingBackend.pathGeometryScratch }
    var bindingSet1: ShaderBindingSet { drawingBackend.bindingSet1 }
    var bindingSet2: ShaderBindingSet { drawingBackend.bindingSet2 }

    // GPU encoding resources have a separate lifetime from value-state copies.
    // A new render target needs its own bindings; copies within that target
    // continue using the same arena and encoder resources.
    final class DrawingBackend {
        let renderTargets: RenderTargets
        let commandBuffer: CommandBuffer
        let pipeline: GraphicsPipelineStates
        let uploadBufferArena: UploadBufferArena
        let pathGeometryScratch: StencilPathGeometryScratch
        let bindingSet1: ShaderBindingSet
        let bindingSet2: ShaderBindingSet

        init?(renderTargets: RenderTargets,
              commandBuffer: CommandBuffer, uploadBufferArena: UploadBufferArena?,
              pathGeometryScratch: StencilPathGeometryScratch?) {
            guard let pipeline = GraphicsPipelineStates.sharedInstance(
                commandQueue: commandBuffer.commandQueue
            ), let bindingSet1 = pipeline.makeBindingSet1(),
               let bindingSet2 = pipeline.makeBindingSet2() else {
                Log.error("Failed to create drawing backend bindings.")
                return nil
            }
            self.renderTargets = renderTargets
            self.commandBuffer = commandBuffer
            self.pipeline = pipeline
            self.uploadBufferArena = uploadBufferArena ?? UploadBufferArena(device: commandBuffer.device)
            self.pathGeometryScratch = pathGeometryScratch ?? StencilPathGeometryScratch()
            self.bindingSet1 = bindingSet1
            self.bindingSet2 = bindingSet2
        }
    }
}

@available(*, unavailable)
extension GraphicsContext.Storage: Sendable {}
