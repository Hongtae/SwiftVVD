//
//  File: ImageDrawing.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation
import VVD

// A prepared backend image with the presentation sampled by image-view rules.
// Resource metadata remains a separate value so presentation cannot mutate a
// different image that retains the same texture or vector contents.
struct ImageDrawing {
    struct SymbolReplacementLevelPresentation {
        var scale: CGFloat
        var opacity: Double
    }

    struct SymbolReplacementSymbolPresentation {
        var image: ImageDrawing
        var levels: [SymbolReplacementLevelPresentation]
        var isLayered: Bool
        var drawProgresses: [Double]?
    }

    final class SymbolReplacementPresentation {
        var symbols: [SymbolReplacementSymbolPresentation]

        init(
            symbols: [SymbolReplacementSymbolPresentation]
        ) {
            self.symbols = symbols
        }
    }

    var size: CGSize { image.size }
    let baseline: CGFloat
    var shading: GraphicsContext.Shading?
    var symbolLayerOpacities: [Double]?
    var symbolReplacementLayerOpacities: [Double]?
    var symbolReplacementPresentation: SymbolReplacementPresentation?
    var symbolVariableColorOpacities: [Double]?
    var symbolDrawPathIntervals:
        [[ResolvedVectorSymbol.DrawPathInterval]]?
    var symbolDrawProgresses: [Double]?
    var symbolDrawFallbackProgresses: [Double]?
    var symbolDrawFallbackOpacity: Double?
    var symbolDrawsReversed: Bool = false

    var image: GraphicsImage
    let textureTransform: CGAffineTransform
    var scaleFactor: CGFloat { image.scale == 0 ? 0 : 1 / image.scale }

    var texture: Texture? { image.texture }
    var symbol: ResolvedVectorSymbol? { image.symbol }
    var svg: SVG? { image.svg }
    var vectorID: ObjectIdentifier? { image.vectorID }

    var resizingMode: Image.ResizingMode? {
        get { image.resizingInfo?.mode }
        set {
            image.resizingInfo = newValue.map {
                Image.ResizingInfo(capInsets: image.resizingInfo?.capInsets ?? EdgeInsets(), mode: $0)
            }
        }
    }

    init(_ resolved: GraphicsContext.ResolvedImage) {
        self.image = resolved.resolved
        self.baseline = resolved.baseline
        self.shading = resolved.shading
        self.textureTransform = resolved.resolved.textureTransform
    }

    init(baseline: CGFloat, shading: GraphicsContext.Shading?, texture: Texture?, textureTransform: CGAffineTransform, scaleFactor: CGFloat) {
        self.baseline = baseline
        self.shading = shading
        self.image = GraphicsImage(texture: texture, scale: scaleFactor == 0 ? 0 : 1 / scaleFactor)
        self.textureTransform = textureTransform
    }

    init(symbol: ResolvedVectorSymbol, shading: GraphicsContext.Shading? = nil) {
        self.baseline = symbol.viewport.height * symbol.intrinsicScale
        self.shading = shading
        self.image = GraphicsImage(symbol: symbol)
        self.textureTransform = .identity
    }

    init(svg: SVG, shading: GraphicsContext.Shading? = nil) {
        self.baseline = svg.intrinsicSize?.height ?? svg.viewBox.height
        self.shading = shading
        self.image = GraphicsImage(svg: svg)
        self.textureTransform = .identity
    }
}

extension ImageDrawing {
    func sizeThatFits(_ proposal: _ProposedSize) -> CGSize {
        guard resizingMode != nil else { return size }
        return CGSize(
            width: proposal.width ?? size.width,
            height: proposal.height ?? size.height
        )
    }

    mutating func applyResizingProvider(_ provider: AnyImageProviderBox) {
        guard let resizingProvider = provider.resizingProvider else {
            resizingMode = nil
            return
        }
        image.resizingInfo = Image.ResizingInfo(
            capInsets: resizingProvider.capInsets, mode: resizingProvider.resizingMode
        )
    }
}

extension ImageDrawing: InterpolatableContent {
    static var defaultTransition: ContentTransition {
        _SemanticFeature<Semantics_v4>.isEnabled ? .interpolate : .identity
    }

    func requiresTransition(to target: Self) -> Bool {
        if baseline != target.baseline { return true }
        if scaleFactor != target.scaleFactor { return true }
        if !textureIdentityEquals(texture, target.texture) { return true }
        if symbol?.identity != target.symbol?.identity { return true }
        if vectorID != target.vectorID { return true }
        if !textureTransform.isTransitionEqual(to: target.textureTransform) { return true }
        if shading != nil || target.shading != nil { return true }
        return false
    }

    func modifyTransition(state: inout ContentTransition.State, to target: Self) {
        if symbol != nil,
           let targetSymbol = target.symbol,
           !targetSymbol.allowsContentTransitions {
            state.transition = .identity
            return
        }
        guard !state.options.contains(.animatesDifferentContent) else { return }
        guard requiresTransition(to: target) else { return }
        state.transition = .opacity
    }
}

private func textureIdentityEquals(_ lhs: Texture?, _ rhs: Texture?) -> Bool {
    switch (lhs, rhs) {
    case (.none, .none):
        true
    case let (.some(lhs), .some(rhs)):
        lhs === rhs
    default:
        false
    }
}

private extension CGAffineTransform {
    func isTransitionEqual(to other: CGAffineTransform) -> Bool {
        a == other.a
            && b == other.b
            && c == other.c
            && d == other.d
            && tx == other.tx
            && ty == other.ty
    }
}
