//
//  File: GraphicsContext.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

public struct GraphicsContext {

    public var opacity: Double
    public var blendMode: BlendMode
    public internal(set) var environment: EnvironmentValues
    public var transform: CGAffineTransform {
        didSet {
            self.clipBoundingRect = Self.remappedClipBoundingRect(
                self.clipBoundingRect,
                from: oldValue,
                to: self.transform
            )
        }
    }

    // MARK: -
    var viewTransform: CGAffineTransform
    var contentOffset: CGPoint {
        didSet {
            let origin = self.contentOffset
            let scale = self.viewport.size / self.contentScaleFactor
            let offset = CGAffineTransform(translationX: origin.x, y: origin.y)
            let normalize = CGAffineTransform(scaleX: 1.0 / scale.width, y: 1.0 / scale.height)

            // transform to screen viewport space.
            let clipSpace = CGAffineTransform(scaleX: 2.0, y: -2.0)
                .concatenating(CGAffineTransform(translationX: -1.0, y: 1.0))

            self.viewTransform = CGAffineTransform.identity
                .concatenating(offset)
                .concatenating(normalize)
                .concatenating(clipSpace)
        }
    }
    let contentScaleFactor: CGFloat

    var maskTexture: Texture
    let renderTargets: RenderTargets
    let viewport: CGRect

    let sceneResources: SceneResources
    let commandBuffer: CommandBuffer
    let pipeline: GraphicsPipelineStates

    let bindingSet1: ShaderBindingSet // for 1-texture
    let bindingSet2: ShaderBindingSet // for 2-textures
    // Value copies share this reference so nonmutating draw calls accumulate visible content bounds.
    let contentBoundsState: ContentBoundsState

    final class ContentBoundsState {
        var bounds: CGRect = .null
    }

    init?(sceneResources: SceneResources,
          environment: EnvironmentValues,
          viewport: CGRect,
          contentOffset: CGPoint,
          contentScaleFactor: CGFloat,
          renderTargets: RenderTargets,
          commandBuffer: CommandBuffer) {

        let viewport = viewport.standardized
        if viewport.isEmpty || viewport.isInfinite {
            Log.error("Invalid viewport!")
            return nil
        }
        if viewport.size.width < 1 || viewport.size.height < 1 {
            Log.error("Invalid viewport size!")
            return nil
        }
        self.viewport = viewport
        self.sceneResources = sceneResources
        self.opacity = 1
        self.blendMode = .normal
        self.transform = .identity
        self.clipBoundingRect = viewport
        self.environment = environment
        self.commandBuffer = commandBuffer
        self.contentScaleFactor = contentScaleFactor
        self.renderTargets = renderTargets
        self.contentBoundsState = ContentBoundsState()

        let queue = commandBuffer.commandQueue
        guard let pipeline = GraphicsPipelineStates.sharedInstance(
            commandQueue: queue) else {
            Log.error("GraphicsPipelineStates error")
            return nil
        }
        self.pipeline = pipeline
        self.maskTexture = pipeline.defaultMaskTexture
        guard let bindingSet1 = pipeline.makeBindingSet1() else {
            Log.error("Failed to make bindingSet1")
            return nil
        }
        self.bindingSet1 = bindingSet1
        guard let bindingSet2 = pipeline.makeBindingSet2() else {
            Log.error("Failed to make bindingSet2")
            return nil
        }
        self.bindingSet2 = bindingSet2

        self.contentOffset = .zero
        self.viewTransform = .identity

        defer {
            // contentOffset.didSet will be called.
            let initContentOffset = { (context: inout GraphicsContext, offset: CGPoint) in
                context.contentOffset = offset
            }
            initContentOffset(&self, contentOffset)
        }
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

    public internal(set) var clipBoundingRect: CGRect = .zero

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

    var filters: [(Filter, FilterOptions)] = []

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
            let usage: TextureUsage = [.renderTarget, .sampled]
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
          commandBuffer: CommandBuffer) {

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
                  commandBuffer: commandBuffer)
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
