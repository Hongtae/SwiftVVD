//
//  File: GraphicsImage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import Synchronization
import VVD

struct GraphicsImage: Equatable {
    enum Contents: Equatable {
        case texture(ImageTexture)
        indirect case vectorGlyph(ResolvedVectorSymbol)
        indirect case vectorLayer(SVGImageContents)
    }

    var contents: Contents?
    var scale: CGFloat
    var unrotatedPixelSize: CGSize
    var orientation: Image.Orientation
    var maskColor: Color.ResolvedHDR?
    var resizingInfo: Image.ResizingInfo?
    var isAntialiased: Bool
    var interpolation: Image.Interpolation
    var allowedDynamicRange: Image.DynamicRange

    init(
        contents: Contents?,
        scale: CGFloat,
        unrotatedPixelSize: CGSize,
        orientation: Image.Orientation = .up,
        isTemplate: Bool = false,
        resizingInfo: Image.ResizingInfo? = nil,
        antialiased: Bool = true,
        interpolation: Image.Interpolation = .low
    ) {
        self.contents = contents
        self.scale = scale
        self.unrotatedPixelSize = unrotatedPixelSize
        self.orientation = orientation
        self.maskColor = isTemplate ? Color.ResolvedHDR(Color.Resolved(
            colorSpace: .sRGBLinear, red: 1, green: 1, blue: 1, opacity: 1
        )) : nil
        self.resizingInfo = resizingInfo
        self.isAntialiased = antialiased
        self.interpolation = interpolation
        self.allowedDynamicRange = .standard
    }

    var size: CGSize {
        guard scale != 0 else { return .zero }
        let pixelSize: CGSize
        switch orientation {
        case .up, .upMirrored, .down, .downMirrored:
            pixelSize = unrotatedPixelSize
        case .left, .leftMirrored, .right, .rightMirrored:
            pixelSize = CGSize(width: unrotatedPixelSize.height,
                               height: unrotatedPixelSize.width)
        }
        return pixelSize * (1 / scale)
    }
}

extension GraphicsImage {
    init(texture: Texture?, scale: CGFloat, orientation: Image.Orientation = .up) {
        let resource = texture.map(ImageTexture.init)
        self.init(contents: resource.map(Contents.texture), scale: scale,
                  unrotatedPixelSize: resource?.pixelSize ?? .zero,
                  orientation: orientation)
    }

    init(symbol: ResolvedVectorSymbol) {
        self.init(contents: .vectorGlyph(symbol), scale: 1 / symbol.intrinsicScale,
                  unrotatedPixelSize: symbol.viewport.size)
    }

    init(svg: SVG) {
        self.init(contents: .vectorLayer(SVGImageContents(svg)), scale: 1,
                  unrotatedPixelSize: svg.intrinsicSize ?? svg.viewBox.size)
    }

    var texture: Texture? {
        guard case let .texture(resource) = contents else { return nil }
        return resource.texture
    }

    var symbol: ResolvedVectorSymbol? {
        guard case let .vectorGlyph(symbol) = contents else { return nil }
        return symbol
    }

    var svg: SVG? {
        guard case let .vectorLayer(resource) = contents else { return nil }
        return resource.svg
    }

    var vectorID: ObjectIdentifier? {
        guard case let .vectorLayer(resource) = contents else { return nil }
        return ObjectIdentifier(resource)
    }

    // Map destination-normalized coordinates back into the unrotated texture.
    var textureTransform: CGAffineTransform {
        switch orientation {
        case .up: .identity
        case .upMirrored: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 1, ty: 0)
        case .down: CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1, ty: 1)
        case .downMirrored: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 1)
        case .left: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        case .leftMirrored: CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .right: CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1)
        case .rightMirrored: CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: 1, ty: 1)
        }
    }
}

// GPU lifetime is shared independently of an image's mutable value metadata.
final class ImageTexture: AppLifetimeResource, @unchecked Sendable, Equatable {
    private let storage: Mutex<Texture?>
    let pixelSize: CGSize
    let identity: ObjectIdentifier

    init(_ texture: Texture) {
        self.storage = Mutex(texture)
        self.pixelSize = CGSize(width: texture.width, height: texture.height)
        self.identity = ObjectIdentifier(texture)
        super.init()
    }

    var texture: Texture? { storage.withLock { $0 } }

    override func purgeResources(reason: ResourcePurgeReason) {
        if reason == .appTermination {
            storage.withLock { $0 = nil }
        }
    }

    static func == (lhs: ImageTexture, rhs: ImageTexture) -> Bool {
        lhs.identity == rhs.identity
    }
}

// The SVG document remains immutable while recorded drawings share its owner.
final class SVGImageContents: Equatable {
    let svg: SVG

    init(_ svg: SVG) { self.svg = svg }

    static func == (lhs: SVGImageContents, rhs: SVGImageContents) -> Bool {
        lhs === rhs || lhs.svg == rhs.svg
    }
}
