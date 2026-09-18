//
//  File: GraphicsContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct GraphicsContext {

    struct BufferSlice {
        let buffer: GPUBuffer
        let offset: Int
    }

    final class UploadBufferArena {
        // Contexts encoding into one command buffer share this arena. Slices are
        // monotonic so deferred backend encoders never observe overwritten data.
        private static let defaultCapacity = 256 * 1024
        private static let capacityAlignment = 4096
        static let allocationAlignment = 16

        private final class Chunk {
            // Shared-buffer mappings and lengths stay fixed while the buffer is retained.
            let buffer: GPUBuffer
            let length: Int
            let contents: UnsafeMutableRawPointer
            var endOffset: Int = 0

            init(buffer: GPUBuffer, contents: UnsafeMutableRawPointer) {
                self.buffer = buffer
                self.length = buffer.length
                self.contents = contents
            }
        }

        private let device: GraphicsDevice
        private var chunks: [Chunk] = []

        init(device: GraphicsDevice) {
            self.device = device
            self.chunks.reserveCapacity(1)
        }

        func copy(
            _ bytes: UnsafeRawBufferPointer,
            alignment requestedAlignment: Int
        ) -> BufferSlice? {
            guard bytes.count > 0, let source = bytes.baseAddress else {
                return nil
            }

            let alignment = max(
                Self.allocationAlignment,
                requestedAlignment
            )
            assert(alignment.isPowerOfTwo)

            if let chunk = chunks.last {
                let offset = chunk.endOffset.alignedUp(
                    toMultipleOf: alignment
                )
                if bytes.count <= chunk.length,
                   offset <= chunk.length - bytes.count {
                    chunk.contents.advanced(by: offset).copyMemory(
                        from: source,
                        byteCount: bytes.count
                    )
                    chunk.endOffset = offset + bytes.count
                    chunk.buffer.flush()
                    return BufferSlice(buffer: chunk.buffer, offset: offset)
                }
            }

            let minimumCapacity = max(
                Self.defaultCapacity,
                bytes.count
            )
            let capacity = minimumCapacity.alignedUp(
                toMultipleOf: Self.capacityAlignment
            )
            guard let buffer = device.makeBuffer(
                length: capacity,
                storageMode: .shared,
                cpuCacheMode: .writeCombined
            ), let destination = buffer.contents() else {
                return nil
            }

            destination.copyMemory(from: source, byteCount: bytes.count)
            buffer.flush()
            let chunk = Chunk(buffer: buffer, contents: destination)
            chunk.endOffset = bytes.count
            chunks.append(chunk)
            return BufferSlice(buffer: buffer, offset: 0)
        }
    }

    var storage: Storage

    public var opacity: Double {
        get { Double(storage.opacity) }
        set {
            let value = Float(newValue)
            guard value != storage.opacity else { return }
            copyOnWrite()
            storage.opacity = value
        }
    }

    public var blendMode: BlendMode {
        get { BlendMode(rawValue: storage.blendMode.rawValue) }
        set {
            guard newValue.rawValue != storage.blendMode.rawValue else { return }
            copyOnWrite()
            storage.blendMode = RBBlendMode(rawValue: newValue.rawValue)
        }
    }

    public internal(set) var environment: EnvironmentValues {
        get { storage.environmentOverride ?? storage.shared._environment }
        set { storage.environmentOverride = newValue }
        _modify {
            if storage.environmentOverride == nil {
                storage.environmentOverride = storage.shared._environment
            }
            yield &storage.environmentOverride!
        }
    }

    public var transform: CGAffineTransform {
        get { storage.state.pointee.transform }
        set {
            let previous = storage.state.pointee.transform
            guard previous != newValue else { return }
            copyOnWrite()
            storage.state.pointee.transform = newValue
            storage.state.pointee.clipBoundingRect = Self.remappedClipBoundingRect(
                storage.state.pointee.clipBoundingRect,
                from: previous,
                to: newValue
            )
        }
    }

    final class ContentBoundsState {
        var bounds: CGRect = .null
    }

    init?(sceneResources: SceneResources,
          environment: EnvironmentValues,
          viewport: CGRect,
          contentOffset: CGPoint,
          contentScaleFactor: CGFloat,
          renderTargets: RenderTargets,
          commandBuffer: CommandBuffer,
          uploadBufferArena: UploadBufferArena? = nil,
          pathGeometryScratch: StencilPathGeometryScratch? = nil) {

        let viewport = viewport.standardized
        if viewport.isEmpty || viewport.isInfinite {
            Log.error("Invalid viewport!")
            return nil
        }
        if viewport.size.width < 1 || viewport.size.height < 1 {
            Log.error("Invalid viewport size!")
            return nil
        }
        guard let backend = DrawingBackend(
            sceneResources: sceneResources, viewport: viewport,
            contentScaleFactor: contentScaleFactor, renderTargets: renderTargets,
            commandBuffer: commandBuffer, uploadBufferArena: uploadBufferArena,
            pathGeometryScratch: pathGeometryScratch
        ) else { return nil }
        self.init(displayList: RBDisplayList(viewport: viewport), backend: backend, environment: environment)
        self.contentOffset = contentOffset
    }

    public mutating func scaleBy(x: CGFloat, y: CGFloat) {
        self.transform = self.transform.scaledBy(x: x, y: y)
    }

    public mutating func translateBy(x: CGFloat, y: CGFloat) {
        self.transform = self.transform.translatedBy(x: x, y: y)
    }

    public mutating func rotate(by angle: Angle) {
        self.transform = self.transform.rotated(by: angle.radians)
    }

    public mutating func concatenate(_ matrix: CGAffineTransform) {
        self.transform = matrix.concatenating(self.transform)
    }

    static func remappedClipBoundingRect(
        _ bounds: CGRect,
        from oldTransform: CGAffineTransform,
        to newTransform: CGAffineTransform
    ) -> CGRect {
        guard !bounds.isNull, oldTransform != newTransform else {
            return bounds
        }
        return bounds.applying(oldTransform.concatenating(newTransform.inverted()))
    }

    public internal(set) var clipBoundingRect: CGRect {
        get { storage.state.pointee.clipBoundingRect }
        set {
            guard newValue != storage.state.pointee.clipBoundingRect else { return }
            copyOnWrite()
            storage.state.pointee.clipBoundingRect = newValue
        }
    }

    func recordContentBounds(_ bounds: CGRect) {
        guard self.opacity > 0,
              !bounds.isNull,
              !bounds.isEmpty,
              !self.clipBoundingRect.isNull else {
            return
        }
        let transformedBounds = bounds.applying(self.transform)
        let transformedClip = self.clipBoundingRect.applying(self.transform)
        let visibleBounds = transformedBounds.intersection(transformedClip)
        guard !visibleBounds.isNull, !visibleBounds.isEmpty else { return }
        if self.contentBoundsState.bounds.isNull {
            self.contentBoundsState.bounds = visibleBounds
        } else {
            self.contentBoundsState.bounds = self.contentBoundsState.bounds.union(visibleBounds)
        }
    }

    var contentBoundingRect: CGRect {
        guard !self.contentBoundsState.bounds.isNull else { return .null }
        return self.contentBoundsState.bounds.applying(self.transform.inverted())
    }

    var backdrop: Texture { renderTargets.backdrop }
    var stencilBuffer: Texture { renderTargets.stencilBuffer }
    var sourceTexture: Texture { renderTargets.source }

    var colorFormat: PixelFormat { renderTargets.colorFormat }
    var depthFormat: PixelFormat { renderTargets.depthFormat }

    var resolution: CGSize {
        CGSize(width: renderTargets.width, height: renderTargets.height)
    }

    var commandQueue: CommandQueue { commandBuffer.commandQueue }
}

@available(*, unavailable)
extension GraphicsContext: Sendable {}

extension GraphicsContext {
    class RenderTargets {
        var source: Texture     // blend source, temporary
        var backdrop: Texture   // output (swap with composited)
        var composited: Texture // composited output
        var temporary: Texture  // temporary buffer for iteration (blur)
        let stencilBuffer: Texture

        let renderTargetMSAA: Texture
        let stencilBufferMSAA: Texture
        let msaaSampleCount = 4

        var width: Int { backdrop.width }
        var height: Int { backdrop.height }
        var dimensions: (Int, Int, Int) { (self.width, self.height, 1) }

        var colorFormat: PixelFormat { backdrop.pixelFormat }
        var depthFormat: PixelFormat { stencilBuffer.pixelFormat }

        init?(device: GraphicsDevice, width: Int, height: Int) {
            let makeRenderTarget = {
                (format: PixelFormat, usage: TextureUsage) -> Texture? in
                device.makeTexture(
                    descriptor: TextureDescriptor(textureType: .type2D,
                                                  pixelFormat: format,
                                                  width: width,
                                                  height: height,
                                                  usage: usage))
            }
            let usage: TextureUsage = [.renderTarget, .sampled, .copySource]
            if let renderTarget = makeRenderTarget(.rgba8Unorm, usage) {
                self.source = renderTarget
            } else { return nil }
            if let renderTarget = makeRenderTarget(.rgba8Unorm, usage) {
                self.backdrop = renderTarget
            } else { return nil }
            if let renderTarget = makeRenderTarget(.rgba8Unorm, usage) {
                self.composited = renderTarget
            } else { return nil }
            if let renderTarget = makeRenderTarget(.rgba8Unorm, usage) {
                self.temporary = renderTarget
            } else { return nil }
            if let renderTarget = device.makeTransientRenderTarget(
                type: .type2D,
                pixelFormat: .stencil8,
                width: width, height: height, depth: 1, sampleCount: 1) {
                self.stencilBuffer = renderTarget
            } else { return nil }
            // msaa temporary buffers
            if let renderTarget = device.makeTransientRenderTarget(
                type: .type2D,
                pixelFormat: .rgba8Unorm,
                width: width, height: height, depth: 1,
                sampleCount: self.msaaSampleCount) {
                self.renderTargetMSAA = renderTarget
            } else { return nil }
            if let renderTarget = device.makeTransientRenderTarget(
                type: .type2D,
                pixelFormat: .stencil8,
                width: width, height: height, depth: 1,
                sampleCount: self.msaaSampleCount) {
                self.stencilBufferMSAA = renderTarget
            } else { return nil }
        }

        func switchSourceToComposited() {
            let tmp = self.source
            self.source = self.composited
            self.composited = tmp
        }

        func switchSourceToBackdrop() {
            let tmp = self.source
            self.source = self.backdrop
            self.backdrop = tmp
        }

        func switchCompositedToBackdrop() {
            let tmp = self.composited
            self.composited = self.backdrop
            self.backdrop = tmp
        }

        func switchTemporaryToSource() {
            let tmp = self.temporary
            self.temporary = self.source
            self.source = tmp
        }

        func switchTemporaryToComposited() {
            let tmp = self.temporary
            self.temporary = self.composited
            self.composited = tmp
        }

        func switchTemporaryToBackdrop() {
            let tmp = self.temporary
            self.temporary = self.backdrop
            self.backdrop = tmp
        }
    }

    init?(sceneResources: SceneResources,
          environment: EnvironmentValues,
          viewport: CGRect,
          contentOffset: CGPoint,
          contentScaleFactor: CGFloat,
          resolution: CGSize,
          commandBuffer: CommandBuffer,
          uploadBufferArena: UploadBufferArena? = nil,
          pathGeometryScratch: StencilPathGeometryScratch? = nil) {

        let device = commandBuffer.device

        let width = Int(resolution.width.rounded())
        let height = Int(resolution.height.rounded())
        if width < 1 || height < 1 {
            Log.error("Invalid resolution")
            return nil
        }
        guard let renderTargets = RenderTargets(device: device,
                                             width: width,
                                             height: height) else {
            Log.error("Failed to make renderTargets")
            return nil
        }

        self.init(sceneResources: sceneResources,
                  environment: environment,
                  viewport: viewport,
                  contentOffset: contentOffset,
                  contentScaleFactor: contentScaleFactor,
                  renderTargets: renderTargets,
                  commandBuffer: commandBuffer,
                  uploadBufferArena: uploadBufferArena,
                  pathGeometryScratch: pathGeometryScratch)
    }

    func drawSource() {
        var sourceDiscarded = false
        for (filter, _) in self.filters {
            if case let .shadow(_, _, _, _, opts) = filter.style,
               opts.contains(.shadowOnly) {
                sourceDiscarded = true
                break
            }
        }
        self.applyFilters(sourceDiscarded: sourceDiscarded)
        if sourceDiscarded == false { self.applyBlendMode(applyMask: true) }
        self.applyLayeredFilters(sourceDiscarded: sourceDiscarded)
    }
}
