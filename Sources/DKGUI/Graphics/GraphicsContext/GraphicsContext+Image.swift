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

        public var size: CGSize {
            if let texture {
                let width = CGFloat(texture.width) * self.scaleFactor
                let height = CGFloat(texture.height) * self.scaleFactor
                return CGSize(width: width, height: height)
            }
            return .zero
        }
        public let baseline: CGFloat
        public var shading: Shading?

        let texture: Texture?
        let textureTransform: CGAffineTransform
        let scaleFactor: CGFloat
    }

    public func resolve(_ image: Image) -> ResolvedImage {
        let texture = image.provider.makeTexture(self)
        let displayScale = self.sharedContext.contentScaleFactor
        let scaleFactor = image.provider.scaleFactor / displayScale
        let baseline = CGFloat(texture?.height ?? 0) * scaleFactor
        return ResolvedImage(baseline: baseline, shading: nil, texture: texture, textureTransform: .identity, scaleFactor: scaleFactor)
    }
    public func draw(_ image: ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
        if let texture = image.texture, (rect.width > 0 && rect.height > 0) {
            let textureFrame = CGRect(x: 0, y: 0, width: texture.width, height: texture.height)
            let textureTransform = image.textureTransform

            if let renderPass = self.beginRenderPass(enableStencil: false) {
                self.encodeDrawTextureCommand(renderPass: renderPass,
                                              texture: texture,
                                              frame: rect,
                                              transform: .identity,
                                              textureFrame: textureFrame,
                                              textureTransform: textureTransform,
                                              blendState: .opaque,
                                              color: .white)
                renderPass.end()
                self.drawSource()
            }
        }
    }
    public func draw(_ image: ResolvedImage, at point: CGPoint, anchor: UnitPoint = .center) {
        let size = image.size
        let x = point.x - anchor.x * size.width
        let y = point.y - anchor.y * size.height
        let rect = CGRect(x: x, y: y, width: size.width, height: size.height)
        return draw(image, in: rect, style: FillStyle())
    }
    public func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
        draw(resolve(image), in: rect, style: style)
    }
    public func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
        draw(resolve(image), at: point, anchor: anchor)
    }

    func encodeDrawTextureCommand(renderPass: RenderPass,
                                  texture: Texture,
                                  frame: CGRect,
                                  transform: CGAffineTransform = .identity,
                                  textureFrame: CGRect,
                                  textureTransform: CGAffineTransform = .identity,
                                  blendState: BlendState,
                                  color: DKGame.Color) {
        let trans = transform.concatenating(self.viewTransform)
        let makeVertex = { (x: Scalar, y: Scalar, u: Scalar, v: Scalar) in
            _Vertex(position: Vector2(x, y).applying(trans).float2,
                    texcoord: Vector2(u, v).applying(textureTransform).float2,
                    color: color.float4)
        }

        let invW = 1.0 / CGFloat(texture.width)
        let invH = 1.0 / CGFloat(texture.height)

        let uvMinX = textureFrame.minX * invW
        let uvMaxX = textureFrame.maxX * invW
        let uvMinY = textureFrame.minY * invH
        let uvMaxY = textureFrame.maxY * invH

        let vertices: [_Vertex] = [
            makeVertex(frame.minX, frame.maxY, uvMinX, uvMaxY), // left bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.maxX, frame.maxY, uvMaxX, uvMaxY), // right bottom
            makeVertex(frame.minX, frame.minY, uvMinX, uvMinY), // left top
            makeVertex(frame.maxX, frame.minY, uvMaxX, uvMinY), // right top
        ]

        self.encodeDrawCommand(renderPass: renderPass,
                               shader: .image,
                               stencil: .ignore,
                               vertices: vertices,
                               texture: texture,
                               blendState: blendState)
    }
}
