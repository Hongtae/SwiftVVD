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
        var style: RBDisplayList.Style?
        var filters: [(Filter, FilterOptions)] { style?.executionFilters ?? [] }
        var clips: [DrawingClip]
        var clipBoundingRect: CGRect

        init(_ context: GraphicsContext) {
            transform = context.transform
            opacity = context.opacity
            blendMode = context.blendMode
            environment = context.environment.untrackedCopy()
            style = context.storage.state.pointee.style
            clips = context.recordedClips
            clipBoundingRect = context.clipBoundingRect
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

        func bounds(_ geometry: CGRect) -> CGRect {
            guard opacity > 0, !geometry.isNull, !geometry.isEmpty else { return .null }
            let bounds = geometry.intersection(clipBoundingRect).applying(transform)
            guard transform.isIdentity, clips.isEmpty else { return bounds }
            return style?.bounds(bounds) ?? bounds
        }
    }

    init(recording list: RBDisplayList, environment: EnvironmentValues, inputs: DrawingInputs) {
        precondition(inputs.contentScaleFactor.isFinite && inputs.contentScaleFactor > 0,
                     "Recording requires a positive finite content scale.")
        self.init(displayList: list, inputs: inputs, backend: nil, environment: environment)
        storage.state.pointee.isRecording = true
    }

    func recordingContext(size: CGSize) -> GraphicsContext {
        var context = GraphicsContext(
            recording: RBDisplayList(
                viewport: viewport,
                colorSpace: RBDrawingStateGetDefaultColorSpace(storage.state)
            ),
            environment: environment,
            inputs: storage.inputs
        )
        context.symbols = symbols
        context.contentOffset = contentOffset
        context.clipBoundingRect = CGRect(origin: .zero, size: size)
        return context
    }

    @discardableResult
    func record(bounds: CGRect, _ contents: RBDisplayList.Item.Contents) -> Bool {
        guard let recording else { return false }
        var item = RBDisplayList.Item(state: DrawingState(self), contents: contents, geometryBounds: bounds)
        if let shading = item.shading {
            let resolved = resolvedDrawingShading(shading, bounds: item.shadingBounds)
            item.replaceShading(resolved)
            if case let .color(color)? = resolved.properties.first {
                item.color = RecordedColor(color.resolve(in: environment))
            }
        }
        recording.append(item, bounds: item.bounds)
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

        var state: GraphicsContext.DrawingState
        var contents: Contents
        var geometryBounds: CGRect
        var bounds: CGRect { state.bounds(geometryBounds) }
        var color: RecordedColor? = nil

        func draw(in context: GraphicsContext, copyingStylesWith transform: CachedTransform?) {
            var context = context
            state.apply(to: &context)
            if let transform {
                context.copyOnWrite()
                context.storage.state.pointee.style = transform.transformStyle(state.style)
            }
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
