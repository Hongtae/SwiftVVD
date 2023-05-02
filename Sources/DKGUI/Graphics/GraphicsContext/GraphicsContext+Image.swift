//
//  File: GraphicsContext+Image.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2023 Hongtae Kim. All rights reserved.
//

import Foundation
import DKGame

extension GraphicsContext {
    public struct ResolvedImage {
        public var size: CGSize { .zero }
        public let baseline: CGFloat
        public var shading: Shading?
    }

    public func resolve(_ image: Image) -> ResolvedImage {
        fatalError()
    }
    public func draw(_ image: ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
        fatalError()
    }
    public func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        fatalError()
    }
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
        draw(resolve(image), in: rect, style: style)
    }
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(image), at: point, anchor: anchor)
    }

    func encodeDrawTextureCommand(texture: Texture,
                                  in frame: CGRect,
                                  transform: CGAffineTransform = .identity,
                                  textureFrame: CGRect,
                                  textureTransform: CGAffineTransform = .identity,
                                  blendState: BlendState,
                                  color: DKGame.Color,
                                  encoder: RenderCommandEncoder) {
        let trans = transform.concatenating(self.viewTransform)
        let makeVertex = { x, y, u, v in
            _Vertex(position: Vector2(x, y).applying(trans).float2,
                    texcoord: Vector2(u, v).applying(textureTransform).float2,
                    color: color.float4)
        }

        let invW = 1.0 / CGFloat(self.renderTargets.width)
        let invH = 1.0 / CGFloat(self.renderTargets.height)

        let uvMinX = textureFrame.minX * invW
        let uvMaxX = textureFrame.maxX * invW
        let uvMinY = textureFrame.minY * invH
        let uvMaxY = textureFrame.maxY * invH

        let vertices: [_Vertex] = [
            makeVertex(frame.minX, frame.maxY, uvMinX, uvMaxY),
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY),
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY),
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY),
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY),
            makeVertex(frame.maxX, frame.minY, uvMaxX, uvMinY)
        ]

        self.encodeDrawCommand(shader: .image,
                               stencil: .ignore,
                               vertices: vertices,
                               texture: texture,
                               blendState: blendState,
                               encoder: encoder)
    }
}
