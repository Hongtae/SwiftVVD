//
//  File: ResolvedStyledText+Rendering.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension ResolvedStyledText {
    struct Layers {
        var foreground: (any RBDisplayListContents)?
        var keyed: [(index: Int, contents: any RBDisplayListContents)] = []
        var unstyled: (any RBDisplayListContents)?
    }

    func makeRBDisplayList(for size: CGSize, renderer: TextRendererBoxBase?, deviceScale: CGFloat,
                           environment: EnvironmentValues, inputs: GraphicsContext.DrawingInputs) -> any RBDisplayListContents {
        let viewport = CGRect(origin: .zero,
            size: CGSize(width: size.width * deviceScale, height: size.height * deviceScale))
        var context = GraphicsContext(recording: RBDisplayList(viewport: viewport),
            environment: environment, inputs: inputs)
        context.clipBoundingRect = .infinite
        let bounds = frame(in: size, renderer: renderer)
        // Record before the containing shape decides whether its display frame
        // is visible. A zero advance does not make glyph commands empty.
        let value = DisplayList.Content.TextValue(
            view: StyledTextContentView(text: self, renderer: renderer), size: size,
            frame: bounds, shading: .color(Color(.sRGBLinear, red: -1, green: -1, blue: -1)),
            transform: .identity, command: .closure(bounds: bounds))
        value.draw(in: context)
        return context.recording!.moveContents()
    }

    func layers(for size: CGSize, renderer: TextRendererBoxBase?, deviceScale: CGFloat,
                environment: EnvironmentValues, inputs: GraphicsContext.DrawingInputs) -> Layers {
        let contents = makeRBDisplayList(for: size, renderer: renderer, deviceScale: deviceScale,
            environment: environment, inputs: inputs)
        if !needsStyledRendering { return Layers(unstyled: contents) }
        var result = Layers()
        let predicate = RBDisplayListPredicate()
        predicate.addCondition(fillColor: SIMD4(-1, -1, -1, -32768), colorSpace: .linearSRGB)
        let foreground = predicate.copyFilteredDisplayList(contents)
        if !foreground.isEmpty { result.foreground = foreground }
        for index in styles.indices {
            predicate.removeAll()
            predicate.addCondition(fillColor: SIMD4(-1, -1, Float(index) / 1024, -32768), colorSpace: .linearSRGB)
            let keyed = predicate.copyFilteredDisplayList(contents)
            if !keyed.isEmpty { result.keyed.append((index, keyed)) }
        }
        predicate.removeAll()
        predicate.addCondition(fillColor: SIMD4(-1, -1, -32768, -32768), colorSpace: .linearSRGB)
        predicate.invertsResult = true
        let unstyled = predicate.copyFilteredDisplayList(contents)
        if !unstyled.isEmpty { result.unstyled = unstyled }
        return result
    }
}
