//
//  File: ResolvedImage.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum AccessibilityImageLabel: Equatable {
    case text(Text)
    case systemSymbol(String)
}

extension Image {
    struct LayoutMetrics: Equatable {
        var baselineOffset: CGFloat
        var capHeight: CGFloat
        var contentSize: CGSize
        var alignmentOrigin: CGPoint
        var backgroundSize: CGSize

        init(baselineOffset: CGFloat, capHeight: CGFloat,
             contentSize: CGSize, alignmentOrigin: CGPoint) {
            self.baselineOffset = baselineOffset
            self.capHeight = capHeight
            self.contentSize = contentSize
            self.alignmentOrigin = alignmentOrigin
            self.backgroundSize = .zero
        }
    }

    struct Resolved: Equatable {
        var image: GraphicsImage {
            didSet {
                let background = styleResolverMode.options.intersection(.background)
                styleResolverMode = image.styleResolverMode
                styleResolverMode.options.subtract(.background)
                styleResolverMode.options.formUnion(background)
            }
        }
        var label: AccessibilityImageLabel?
        @EquatableOptionalObject var basePlatformItemImage: AnyObject?
        @IndirectOptional var layoutMetrics: LayoutMetrics?
        var decorative: Bool
        var backgroundShape: SymbolVariants.Shape?
        var backgroundCornerRadius: Float?
        var styleResolverMode: _ShapeStyle_ResolverMode

        init(image: GraphicsImage, decorative: Bool,
             label: AccessibilityImageLabel? = nil,
             basePlatformItemImage: AnyObject? = nil,
             backgroundShape: SymbolVariants.Shape? = nil,
             backgroundCornerRadius: CGFloat? = nil) {
            self.image = image
            self.label = label
            self.basePlatformItemImage = basePlatformItemImage
            self.layoutMetrics = nil
            self.decorative = decorative
            self.backgroundShape = backgroundShape
            self.backgroundCornerRadius = backgroundCornerRadius.map(Float.init)
            self.styleResolverMode = image.styleResolverMode
            if backgroundShape != nil {
                self.styleResolverMode.options.insert(.background)
            } else {
                self.styleResolverMode.options.remove(.background)
            }
        }

        var size: CGSize { image.size }
        var contentSize: CGSize { layoutMetrics?.contentSize ?? image.size }
        var baselineOffset: CGFloat { layoutMetrics?.baselineOffset ?? 0 }
        var capHeight: CGFloat { layoutMetrics?.capHeight ?? image.size.height }
        var alignmentOrigin: CGPoint { layoutMetrics?.alignmentOrigin ?? .zero }

        func sizeThatFits(in proposal: _ProposedSize) -> CGSize {
            guard let resizing = image.resizingInfo else { return contentSize }
            let intrinsic = image.size
            let insets = resizing.capInsets
            return CGSize(
                width: proposal.width.map {
                    let minimum = insets.trailing + insets.leading
                    return minimum >= $0 ? minimum : $0
                } ?? intrinsic.width,
                height: proposal.height.map {
                    let minimum = insets.bottom + insets.top
                    return minimum >= $0 ? minimum : $0
                } ?? intrinsic.height
            )
        }

        func frame(in size: CGSize) -> CGRect {
            image.resizingInfo == nil
                ? CGRect(origin: alignmentOrigin, size: image.size)
                : CGRect(origin: .zero, size: size)
        }
    }
}
