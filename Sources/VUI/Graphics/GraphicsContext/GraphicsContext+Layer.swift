//
//  File: GraphicsContext+Layer.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

extension GraphicsContext {
    func makeLayerContext() -> Self? {
        guard var context = GraphicsContext(
            sceneResources: self.sceneResources,
            environment: self.environment,
            viewport: self.viewport,
            contentOffset: self.contentOffset,
            contentScaleFactor: self.contentScaleFactor,
            resolution: self.resolution,
            commandBuffer: self.commandBuffer,
            uploadBufferArena: self.uploadBufferArena,
            pathGeometryScratch: self.pathGeometryScratch) else {
            return nil
        }
        // Layer contents stay in the caller's current user space. The caller's transform is
        // applied when the completed layer texture is composited, so copying it here would
        // apply the same transform twice.
        context.clipBoundingRect = self.clipBoundingRect
        context.clear(with: .clear)
        return context
    }

    func makeLayerContext(_ size: CGSize) -> Self? {
        let width = size.width * self.contentScaleFactor
        let height = size.height * self.contentScaleFactor

        guard width > 0 && height > 0 else { return nil }

        let context = GraphicsContext(
            sceneResources: self.sceneResources,
            environment: self.environment,
            viewport: CGRect(x: 0, y: 0, width: width, height: height),
            contentOffset: .zero,
            contentScaleFactor: self.contentScaleFactor,
            resolution: CGSize(width: width, height: height),
            commandBuffer: self.commandBuffer,
            uploadBufferArena: self.uploadBufferArena,
            pathGeometryScratch: self.pathGeometryScratch)
        context?.clear(with: .clear)
        return context
    }

    func drawLayer(in frame: CGRect, content: (inout GraphicsContext, CGSize) throws -> Void) rethrows {
        if frame.minX > self.viewport.maxX * self.contentScaleFactor ||
            frame.minY > self.viewport.maxY * self.contentScaleFactor {
            return
        }

        if var context = self.makeLayerContext(frame.size) {
            let size = context.resolution / context.contentScaleFactor
            try content(&context, size)
            let texture = context.backdrop

            if let renderPass = self.beginRenderPass(enableStencil: false) {
                self.encodeDrawTextureCommand(renderPass: renderPass,
                                              texture: texture,
                                              frame: frame,
                                              transform: .identity,
                                              textureFrame: context.viewport,
                                              textureTransform: .identity,
                                              blendState: .opaque,
                                              color: .white)
                renderPass.end()
                self.drawSource()
                self.recordContentBounds(frame)
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    public func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
        if var context = self.makeLayerContext() {
            try content(&context)
            let offset = -context.contentOffset
            let scale = context.viewport.size / context.contentScaleFactor
            let texture = context.backdrop

            if let renderPass = self.beginRenderPass(enableStencil: false) {
                self.encodeDrawTextureCommand(renderPass: renderPass,
                                              texture: texture,
                                              frame: CGRect(origin: offset,
                                                            size: scale),
                                              textureFrame: context.viewport,
                                              blendState: .opaque,
                                              color: .white)
                renderPass.end()
                self.drawSource()
                self.recordContentBounds(context.contentBoundingRect)
            }
        } else {
            Log.error("GraphicsContext error: failed to create new context.")
        }
    }

    /// Renders local contents once, then composites them with homogeneous clip
    /// coordinates. Keeping the projective divide in the vertex stage gives the
    /// texture sampler perspective-correct coordinates while the caller's mask
    /// and blend state remain the final presentation boundary.
    func drawProjectiveLayer(
        transform: ProjectionTransform,
        contentBounds: CGRect,
        content: (GraphicsContext) -> Void
    ) {
        guard transform.isInvertible,
              let sourceBounds = projectiveSourceBounds(
                  transform: transform,
                  contentBounds: contentBounds
              ),
              var layer = makeLayerContext(sourceBounds.size) else {
            return
        }

        layer.translateBy(x: -sourceBounds.minX, y: -sourceBounds.minY)
        content(layer)

        if let renderPass = beginRenderPass(enableStencil: false) {
            encodeProjectiveTextureCommand(
                renderPass: renderPass,
                texture: layer.backdrop,
                sourceBounds: sourceBounds,
                projection: transform
            )
            renderPass.end()
            drawSource()
        }

        let renderedBounds = layer.contentBoundingRect
        if let projectedBounds = projectiveBounds(
            renderedBounds,
            applying: transform
        ) {
            recordContentBounds(projectedBounds)
        } else {
            recordContentBounds(clipBoundingRect)
        }
    }

    private func projectiveSourceBounds(
        transform: ProjectionTransform,
        contentBounds: CGRect
    ) -> CGRect? {
        guard !contentBounds.isNull,
              !contentBounds.isEmpty,
              contentBounds.minX.isFinite,
              contentBounds.minY.isFinite,
              contentBounds.maxX.isFinite,
              contentBounds.maxY.isFinite else {
            return nil
        }
        let inverse = transform.inverted()
        let visibleBounds = projectiveBounds(
            clipBoundingRect,
            applying: inverse
        ) ?? contentBounds
        var sourceBounds = visibleBounds.intersection(contentBounds)
        guard !sourceBounds.isNull, !sourceBounds.isEmpty else { return nil }

        let pixelLength = 1 / contentScaleFactor
        sourceBounds = sourceBounds.insetBy(dx: -pixelLength, dy: -pixelLength)
            .intersection(contentBounds.insetBy(dx: -pixelLength, dy: -pixelLength))
        let minX = floor(sourceBounds.minX * contentScaleFactor) / contentScaleFactor
        let minY = floor(sourceBounds.minY * contentScaleFactor) / contentScaleFactor
        let maxX = ceil(sourceBounds.maxX * contentScaleFactor) / contentScaleFactor
        let maxY = ceil(sourceBounds.maxY * contentScaleFactor) / contentScaleFactor
        let result = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        return result.isEmpty ? nil : result
    }

    private func projectiveBounds(
        _ rect: CGRect,
        applying transform: ProjectionTransform
    ) -> CGRect? {
        guard !rect.isNull,
              !rect.isEmpty,
              rect.minX.isFinite,
              rect.minY.isFinite,
              rect.maxX.isFinite,
              rect.maxY.isFinite else {
            return nil
        }
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY),
        ]
        var projected: [CGPoint] = []
        projected.reserveCapacity(corners.count)
        var hasPositiveW = false
        var hasNegativeW = false
        for point in corners {
            let x = point.x * transform.m11
                + point.y * transform.m21
                + transform.m31
            let y = point.x * transform.m12
                + point.y * transform.m22
                + transform.m32
            let w = point.x * transform.m13
                + point.y * transform.m23
                + transform.m33
            guard w.isFinite, !w.isZero else { return nil }
            hasPositiveW = hasPositiveW || w > 0
            hasNegativeW = hasNegativeW || w < 0
            let result = CGPoint(x: x / w, y: y / w)
            guard result.x.isFinite, result.y.isFinite else { return nil }
            projected.append(result)
        }
        // A sign change means the mapped rectangle crosses the projective
        // horizon, so its finite corner bounds do not enclose the full image.
        guard !(hasPositiveW && hasNegativeW) else { return nil }
        guard let first = projected.first else { return nil }
        return projected.dropFirst().reduce(
            CGRect(origin: first, size: .zero)
        ) { bounds, point in
            bounds.union(CGRect(origin: point, size: .zero))
        }
    }

    private func encodeProjectiveTextureCommand(
        renderPass: RenderPass,
        texture: Texture,
        sourceBounds: CGRect,
        projection: ProjectionTransform
    ) {
        let affine = transform
        let viewportTransform = viewTransform
        let homogeneousPosition: (CGPoint) -> Float4 = { point in
            let projectedX = point.x * projection.m11
                + point.y * projection.m21
                + projection.m31
            let projectedY = point.x * projection.m12
                + point.y * projection.m22
                + projection.m32
            let projectedW = point.x * projection.m13
                + point.y * projection.m23
                + projection.m33
            let affineX = projectedX * affine.a
                + projectedY * affine.c
                + projectedW * affine.tx
            let affineY = projectedX * affine.b
                + projectedY * affine.d
                + projectedW * affine.ty
            let clipX = affineX * viewportTransform.a
                + affineY * viewportTransform.c
                + projectedW * viewportTransform.tx
            let clipY = affineX * viewportTransform.b
                + affineY * viewportTransform.d
                + projectedW * viewportTransform.ty
            return (
                Float(clipX),
                Float(clipY),
                0,
                Float(projectedW)
            )
        }
        let makeVertex = { (point: CGPoint, uv: Float2) in
            _ProjectiveVertex(
                position: homogeneousPosition(point),
                texcoord: uv,
                color: BackendColor.white.float4
            )
        }
        let topLeft = makeVertex(
            CGPoint(x: sourceBounds.minX, y: sourceBounds.minY),
            (0, 0)
        )
        let topRight = makeVertex(
            CGPoint(x: sourceBounds.maxX, y: sourceBounds.minY),
            (1, 0)
        )
        let bottomLeft = makeVertex(
            CGPoint(x: sourceBounds.minX, y: sourceBounds.maxY),
            (0, 1)
        )
        let bottomRight = makeVertex(
            CGPoint(x: sourceBounds.maxX, y: sourceBounds.maxY),
            (1, 1)
        )
        let vertices = [
            bottomLeft, topLeft, bottomRight,
            bottomRight, topLeft, topRight,
        ]

        guard let renderState = pipeline.renderState(
            shader: .projectiveImage,
            colorFormat: renderPass.colorFormat,
            depthFormat: renderPass.depthFormat,
            blendState: .opaque,
            sampleCount: renderPass.sampleCount
        ), let depthState = pipeline.depthStencilState(.ignore),
           let vertexBuffer = makeBuffer(vertices) else {
            Log.error("GraphicsContext projective layer pipeline creation failed.")
            return
        }

        let encoder = renderPass.encoder
        encoder.setRenderPipelineState(renderState)
        encoder.setDepthStencilState(depthState)
        bindingSet1.setTexture(texture, binding: 0)
        encoder.setResource(bindingSet1, index: 0)
        encoder.setCullMode(.none)
        encoder.setVertexBuffer(
            vertexBuffer.buffer,
            offset: vertexBuffer.offset,
            index: 0
        )
        encoder.draw(
            vertexStart: 0,
            vertexCount: vertices.count,
            instanceCount: 1,
            baseInstance: 0
        )
    }
}
