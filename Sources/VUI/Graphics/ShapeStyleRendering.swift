//
//  File: ShapeStyleRendering.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension _ShapeStyle_RenderedShape {
    mutating func render(style: _ShapeStyle_Pack.Style) {
        let entryOpacity = opacity
        blendMode = style._blend ?? .normal
        opacity *= style.opacity
        if style.effects.isEmpty, case var .color(color) = style.fill {
            color.opacity *= opacity
            opacity = 1
            render(color: color)
            return
        }
        render(fill: style.fill)
        guard !style.effects.isEmpty else { return }

        var above = CompositedItemAccumulator(
            version: item.version, contentSeed: contentSeed, options: options)
        var below = above
        var mayAdjustItem = blendMode == .normal
        let opaqueFill = opacity == 1 && style.opacity == 1 &&
            blendMode == .normal && fillIsOpaque(style.fill)
        for effect in style.effects {
            guard case let .shadow(shadow) = effect.kind else { continue }
            precondition(shadow.kind.subtracting(.inner).isEmpty && shadow.midpoint == 0.5 &&
                shadow.radius.isFinite && shadow.radius >= 0 &&
                shadow.offset.width.isFinite && shadow.offset.height.isFinite,
                "Shadow composition requires finite nonnegative geometry, default midpoint and public input kinds.")
            var derivedStyle = _ShapeStyle_Pack.Style(style.fill)
            derivedStyle.opacity = shadow.kind.contains(.ignoresFill)
                ? entryOpacity * effect.opacity : opacity
            derivedStyle._blend = effect._blend
            render(shadow: shadow, style: derivedStyle, above: &above, below: &below,
                opaqueFill: opaqueFill, mayAdjustItem: &mayAdjustItem)
        }
        guard !above.items.isEmpty || !above.pendingItems.isEmpty ||
              !below.items.isEmpty || !below.pendingItems.isEmpty else { return }
        let hadBlend = blendMode != .normal
        if hadBlend {
            item.addEffect(.blendMode(blendMode))
            item.canonicalize(options: options)
            blendMode = .normal
        }
        if opacity != 1 {
            item.addEffect(.opacity(opacity))
            item.canonicalize(options: options)
            opacity = 1
        }
        if hadBlend || above.hasBlending || below.hasBlending || layerNeeds.contains(.compositing) {
            if layerNeeds.contains(.drawingGroup) {
                item.addDrawingGroup(contentSeed: contentSeed)
                layerNeeds.remove(.drawingGroup)
            }
            below.commitPendingItems()
            above.commitPendingItems()
            push(layers: &below.items, above: false)
            push(layers: &above.items, above: true)
        } else {
            push(layers: &below.pendingItems, above: false)
            push(layers: &above.pendingItems, above: true)
            if below.drawingGroup || above.drawingGroup { layerNeeds.insert(.drawingGroup) }
        }
    }

    mutating func render(color: Color.ResolvedHDR) {
        defer { attachFillInterpolator() }
        if case let .alphaMask(mask, alphaOnly) = shape {
            precondition(alphaOnly, "Colored mask inputs require a color-matrix producer.")
            let identity = item.identity
            let version = item.version
            item = mask
            item.identity = identity
            item.version = version
            if color != Color.ResolvedHDR(Color.Resolved(red: 1, green: 1, blue: 1)) {
                item.addEffect(.filter(.colorMultiply(color)))
                item.canonicalize(options: options)
            }
        } else {
            setItem(from: displayList(shading: .color(Color(color))))
        }
    }

    mutating func render(paint: AnyResolvedPaint) {
        defer { attachFillInterpolator() }
        let shading: GraphicsContext.Shading
        if let paint = paint as? _AnyResolvedPaint<MeshGradient._Paint> {
            shading = .meshGradient(paint.paint.meshGradient)
        } else {
            shading = GraphicsContext.Shading(property: .resolvedPaint(
                paint: paint, bounds: frame, opacity: 1))
        }
        if case var .alphaMask(mask, _) = shape {
            let savedShape = shape
            let savedFrame = frame
            shape = .path(Path(mask.frame), FillStyle())
            frame = mask.frame
            setItem(from: displayList(shading: shading))
            shape = savedShape
            frame = savedFrame
            mask.frame.origin.x -= item.frame.minX
            mask.frame.origin.y -= item.frame.minY
            var maskList = DisplayList()
            maskList.items = [mask]
            maskList.interpolationBounds = mask.frame
            item.addEffect(.mask(maskList, []))
            item.canonicalize(options: options)
        } else {
            setItem(from: displayList(shading: shading))
        }
    }

    private mutating func attachFillInterpolator() {
        guard let data = interpolatorData else { return }
        if case .empty = item.value { return }
        item.addEffect(.interpolatorLayer(data.group, data.serial))
        item.canonicalize(options: options)
        interpolatorData = nil
    }

    private mutating func render(fill: _ShapeStyle_Pack.Fill) {
        switch fill {
        case let .color(color): render(color: color)
        case let .paint(paint): render(paint: paint)
        }
    }

    mutating func render(
        shadow: ResolvedShadowStyle,
        style: _ShapeStyle_Pack.Style,
        above: inout CompositedItemAccumulator,
        below: inout CompositedItemAccumulator,
        opaqueFill: Bool,
        mayAdjustItem: inout Bool
    ) {
        var shadow = shadow
        if opaqueFill { shadow.kind.subtract([.ignoresFill, .requiresKnockout]) }
        let inner = shadow.kind.contains(.inner)
        if opaqueFill && mayAdjustItem && !layerNeeds.contains(.compositing) {
            mayAdjustItem = false
            item.addEffect(.filter(.shadow(shadow)))
            item.canonicalize(options: options)
            if case .path = shape, !inner, shadow.midpoint == 0.5,
               (style._blend ?? .normal) == .normal {
                return
            }
            layerNeeds.insert(.drawingGroup)
            return
        }

        var rendered = _ShapeStyle_RenderedShape(
            shape: shape.translated(by: CGPoint(x: -frame.minX, y: -frame.minY)),
            contentSeed: contentSeed, frame: CGRect(origin: .zero, size: frame.size),
            version: item.version, options: options, environment: _environment)
        shadow.color.opacity *= style.opacity
        let ignoresFill = opaqueFill || shadow.kind.contains(.ignoresFill)
        let needsDrawingGroup: Bool
        if ignoresFill, !inner, case let .path(path, _) = rendered.shape {
            let content = DisplayList.Content(shadow: shadow, path: path,
                seed: contentSeed, environment: _environment.value.untrackedCopy())
            rendered.item = DisplayList.Item(content: content, frame: path.boundingRect,
                identity: .none, version: item.version)
            needsDrawingGroup = shadow.midpoint != 0.5
        } else {
            let requiresKnockout = shadow.kind.contains(.requiresKnockout)
            shadow.kind.remove(.requiresKnockout)
            shadow.kind.insert(.only)
            if !ignoresFill { shadow.kind.insert(.nonOpaque) }
            if !ignoresFill && !inner {
                rendered.render(fill: style.fill)
            } else {
                rendered.render(color: Color.ResolvedHDR(Color.Resolved(red: 1, green: 1, blue: 1)))
            }
            rendered.item.addEffect(.filter(.shadow(shadow)))
            rendered.item.canonicalize(options: options)
            if !ignoresFill || requiresKnockout {
                if inner {
                    let bounds: CGRect
                    switch rendered.shape {
                    case let .path(path, _): bounds = path.boundingRect
                    case let .alphaMask(mask, _): bounds = mask.frame
                    default: bounds = rendered.frame
                    }
                    var background = _ShapeStyle_RenderedShape(
                        shape: .path(Path(bounds), FillStyle()), contentSeed: contentSeed,
                        frame: bounds, version: item.version, options: options, environment: _environment)
                    background.render(fill: style.fill)
                    rendered.background(&background)
                }
                switch rendered.shape {
                case let .path(path, fillStyle):
                    rendered.item.addEffect(.clip(path.offsetBy(
                        dx: -rendered.item.frame.minX, dy: -rendered.item.frame.minY),
                        fillStyle, inner ? [] : .inverse))
                case .alphaMask:
                    var mask = rendered.freshItemCopy()
                    mask.render(color: Color.ResolvedHDR(Color.Resolved(red: 1, green: 1, blue: 1)))
                    if var maskItem = mask.commitItem() {
                        maskItem.frame.origin.x -= rendered.item.frame.minX
                        maskItem.frame.origin.y -= rendered.item.frame.minY
                        var maskList = DisplayList()
                        maskList.items = [maskItem]
                        maskList.interpolationBounds = maskItem.frame
                        rendered.item.addEffect(.mask(maskList, inner ? [] : .inverse))
                    }
                default:
                    preconditionFailure("Shadow composition requires a path or alpha mask.")
                }
                if inner { rendered.item.addEffect(.compositingGroup) }
            }
            needsDrawingGroup = true
        }
        guard let shadowItem = rendered.commitItem() else { return }
        if inner {
            above.add(item: shadowItem, blend: style._blend ?? .normal,
                needsDrawingGroup: needsDrawingGroup)
        } else {
            below.add(item: shadowItem, blend: style._blend ?? .normal,
                needsDrawingGroup: needsDrawingGroup)
        }
    }

    mutating func background(_ background: inout Self) {
        var background = background
        if layerNeeds.union(background.layerNeeds).contains(.compositing) {
            if layerNeeds.contains(.drawingGroup) {
                item.addDrawingGroup(contentSeed: contentSeed)
                layerNeeds.remove(.drawingGroup)
            }
            if background.layerNeeds.contains(.drawingGroup) {
                background.item.addDrawingGroup(contentSeed: background.contentSeed)
                background.layerNeeds.remove(.drawingGroup)
            }
        }
        if let committed = commitItem() { item = committed }
        if let backgroundItem = background.commitItem() { item.composite(backgroundItem, above: false) }
        layerNeeds.formUnion(background.layerNeeds)
    }

    private mutating func push(layers: inout [DisplayList.Item], above: Bool) {
        guard !layers.isEmpty else { return }
        var list = DisplayList()
        list.items = layers
        list.interpolationBounds = layers.reduce(CGRect.null) { $0.union($1.frame) }
        var group = DisplayList.Item(effect: .identity, contents: list,
            frame: frame, version: item.version)
        group.canonicalize(options: options)
        item.composite(group, above: above)
        layers.removeAll(keepingCapacity: true)
    }

    private func fillIsOpaque(_ fill: _ShapeStyle_Pack.Fill) -> Bool {
        switch fill {
        case let .color(color): return color.opacity == 1
        case let .paint(paint):
            let gradient: ResolvedGradient
            if let paint = paint as? _AnyResolvedPaint<LinearGradient._Paint> {
                gradient = paint.paint.gradient
            } else if let paint = paint as? _AnyResolvedPaint<LinearGradient.AbsolutePaint> {
                gradient = paint.paint.gradient
            } else {
                preconditionFailure("Shadow paint opacity requires a resolved paint consumer.")
            }
            precondition(!gradient.stops.isEmpty, "Empty shadow paints require their resolved opacity contract.")
            return gradient.stops.allSatisfy { $0.color.opacity == 1 }
        }
    }
}
