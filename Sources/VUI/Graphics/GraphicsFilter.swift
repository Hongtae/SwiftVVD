//
//  File: GraphicsFilter.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

enum GraphicsFilter: Equatable {
    case colorMultiply(Color.ResolvedHDR)
    case shadow(ResolvedShadowStyle)

    func domainOfDefinition(for rect: CGRect) -> CGRect {
        switch self {
        case .colorMultiply:
            return rect
        case let .shadow(shadow):
            if shadow.kind.contains(.inner) || rect.isNull { return rect }
            let spread = 2.8 * shadow.radius
            let bounds = rect.insetBy(dx: -spread, dy: -spread)
                .offsetBy(dx: shadow.offset.width, dy: shadow.offset.height)
            return shadow.kind.contains(.only) ? bounds : rect.union(bounds)
        }
    }

    // Filters operate on the completed contents. The backend's per-draw filters
    // therefore surround an independent layer rather than each primitive in it.
    func draw(in context: GraphicsContext, contents: (GraphicsContext) -> Void) {
        switch self {
        case let .colorMultiply(color):
            var context = context
            context.addFilter(.colorMultiply(Color(color)))
            context.drawLayer { contents($0) }
        case let .shadow(shadow):
            precondition(shadow.midpoint == 0.5,
                "Shadow midpoint transfer functions require a dedicated backend filter.")
            let inner = shadow.kind.contains(.inner)
            let only = shadow.kind.contains(.only)
            // Source traversal belongs to one renderer pass. Reuse immutable
            // commands for the shadow, body and mask raster passes so callback
            // indices and prepared content are not evaluated multiple times.
            var source = context.recordingContext(size: CGSize(
                width: context.viewport.width / context.contentScaleFactor,
                height: context.viewport.height / context.contentScaleFactor))
            source.clipBoundingRect = .infinite
            contents(source)
            let recorded = source.recording!.moveContents()
            context.drawLayer { group in
                if inner && !only { recorded.draw(in: group) }
                var shadowContext = group
                if inner {
                    shadowContext.clipToLayer { recorded.draw(in: $0) }
                }
                let color = Color(shadow.color).backendColor(in: context.environment)
                var matrix = ColorMatrix.zero
                matrix.r5 = Float(color.r)
                matrix.g5 = Float(color.g)
                matrix.b5 = Float(color.b)
                matrix.a4 = Float(color.a) * (inner ? -1 : 1)
                matrix.a5 = inner ? Float(color.a) : 0
                shadowContext.addFilter(.colorMatrix(matrix))
                shadowContext.addFilter(.blur(radius: shadow.radius))
                shadowContext.drawLayer { source in
                    source.translateBy(x: shadow.offset.width, y: shadow.offset.height)
                    recorded.draw(in: source)
                }
                if !inner && !only { recorded.draw(in: group) }
            }
        }
    }
}
