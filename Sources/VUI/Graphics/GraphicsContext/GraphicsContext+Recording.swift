//
//  File: GraphicsContext+Recording.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension GraphicsContext {
    struct DrawingClip {
        enum Contents {
            case path(Path, FillStyle, ClipOptions)
            case layer(RBMovedDisplayListContents, Double, ClipOptions)
        }

        let transform: CGAffineTransform
        let contents: Contents

        func apply(to context: inout GraphicsContext) {
            switch contents {
            case let .path(path, style, options):
                context.clip(to: path, style: style, options: options)
            case let .layer(contents, opacity, options):
                context.clipToLayer(opacity: opacity, options: options) {
                    contents.draw(in: $0)
                }
            }
        }
    }

    struct DrawingState {
        var transform: CGAffineTransform
        var opacity: Double
        var blendMode: BlendMode
        var environment: EnvironmentValues
        var filters: [(Filter, FilterOptions)]
        var clips: [DrawingClip]

        init(_ context: GraphicsContext) {
            transform = context.transform
            opacity = context.opacity
            blendMode = context.blendMode
            environment = context.environment.untrackedCopy()
            filters = context.filters
            clips = context.recordedClips
        }

        func apply(to context: inout GraphicsContext) {
            let baseTransform = context.transform
            for clip in clips {
                context.transform = clip.transform.concatenating(baseTransform)
                clip.apply(to: &context)
            }
            context.transform = transform.concatenating(baseTransform)
            context.opacity *= opacity
            if blendMode != .normal { context.blendMode = blendMode }
            context.filters = filters + context.filters
            context.environment = environment
        }
    }

    func recordingContext(size: CGSize) -> GraphicsContext {
        var context = GraphicsContext(
            displayList: RBDisplayList(
                viewport: viewport,
                colorSpace: RBDrawingStateGetDefaultColorSpace(storage.state)
            ),
            backend: drawingBackend,
            environment: environment
        )
        context.symbols = symbols
        context.contentOffset = contentOffset
        context.storage.state.pointee.isRecording = true
        context.clipBoundingRect = CGRect(origin: .zero, size: size)
        return context
    }

    @discardableResult
    func record(bounds: CGRect, _ contents: RBDisplayList.Item.Contents) -> Bool {
        guard let recording else { return false }
        var visible = CGRect.null
        if opacity > 0, !bounds.isNull, !bounds.isEmpty {
            visible = bounds.intersection(clipBoundingRect).applying(transform)
        }
        var item = RBDisplayList.Item(state: DrawingState(self), contents: contents, bounds: visible)
        if let shading = item.shading {
            let resolved = resolvedDrawingShading(shading, bounds: item.shadingBounds)
            item.replaceShading(resolved)
            if case let .color(color)? = resolved.properties.first {
                item.color = RecordedColor(color.resolve(in: environment))
            }
        }
        recording.append(item, bounds: visible)
        return true
    }
}

extension RBDisplayList {
    // Backend payloads remain inspectable without retaining a drawing context.
    struct Item {
        enum Contents {
            case fill(Path, GraphicsContext.Shading, FillStyle)
            case stroke(Path, GraphicsContext.Shading, StrokeStyle, isAntialiased: Bool)
            case image(ImageDrawing, CGRect, FillStyle)
            case text(GraphicsContext.TextDrawing, GraphicsContext.Shading)
            case layer(RBMovedDisplayListContents, frame: CGRect?)
            case projectiveLayer(RBMovedDisplayListContents, ProjectionTransform, CGRect)
            case shaderLayer(RBMovedDisplayListContents, Shader.ResolvedShader, CGRect)
        }

        let state: GraphicsContext.DrawingState
        var contents: Contents
        let bounds: CGRect
        var color: RecordedColor? = nil

        func draw(in context: GraphicsContext) {
            var context = context
            state.apply(to: &context)
            switch contents {
            case let .fill(path, shading, style):
                context.fill(path, with: shading, style: style)
            case let .stroke(path, shading, style, antialiased):
                context.stroke(path, with: shading, style: style, isAntialiased: antialiased)
            case let .image(image, rect, style):
                context.draw(image, in: rect, style: style)
            case let .text(drawing, shading):
                context.draw(drawing, shading: shading)
            case let .layer(contents, frame):
                if let frame {
                    context.drawLayer(in: frame) { layer, _ in contents.draw(in: layer) }
                } else {
                    context.drawLayer { contents.draw(in: $0) }
                }
            case let .projectiveLayer(contents, transform, bounds):
                context.drawProjectiveLayer(transform: transform, contentBounds: bounds) {
                    contents.draw(in: $0)
                }
            case let .shaderLayer(contents, shader, frame):
                // Re-record the layer as a typed group when the receiver is another list.
                if context.record(bounds: frame, .shaderLayer(contents, shader, frame)) { return }
                guard let layer = context.makeLayerContext() else {
                    contents.draw(in: context)
                    return
                }
                contents.draw(in: layer)
                if !context.drawCustomShaderLayer(shader, sourceTexture: layer.backdrop, frame: frame) {
                    contents.draw(in: context)
                }
            }
        }
    }
}
