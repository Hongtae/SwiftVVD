//
//  File: GraphicsContext+Recording.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension GraphicsContext {
    // Recorded commands retain resolved drawing values and local state.
    final class DrawingCommands {
        var commands: [(GraphicsContext) -> Void] = []
        var bounds = CGRect.null

        func draw(in context: GraphicsContext) {
            for command in commands { command(context) }
        }
    }

    struct DrawingClip {
        var transform: CGAffineTransform
        var apply: (inout GraphicsContext) -> Void
    }

    private struct DrawingState {
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
                clip.apply(&context)
            }
            context.transform = transform.concatenating(baseTransform)
            context.opacity *= opacity
            if blendMode != .normal { context.blendMode = blendMode }
            context.environment = environment
            context.filters = filters + context.filters
        }
    }

    func recordingContext(size: CGSize) -> GraphicsContext {
        var context = self
        context.recording = DrawingCommands()
        context.recordedClips = []
        context.transform = .identity
        context.opacity = 1
        context.blendMode = .normal
        context.filters = []
        context.clipBoundingRect = CGRect(origin: .zero, size: size)
        return context
    }

    @discardableResult
    func record(bounds: CGRect, _ draw: @escaping (GraphicsContext) -> Void) -> Bool {
        guard let recording else { return false }
        let state = DrawingState(self)
        recording.commands.append { context in
            var context = context
            state.apply(to: &context)
            draw(context)
        }
        if opacity > 0, !bounds.isNull, !bounds.isEmpty {
            let visible = bounds.intersection(clipBoundingRect).applying(transform)
            if !visible.isNull, !visible.isEmpty {
                recording.bounds = recording.bounds.union(visible)
            }
        }
        return true
    }
}
