//
//  File: RBDisplayListPredicate.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

// Half-precision color operands used by recorded command operations.
struct RecordedColor {
    var components: SIMD4<Float>
    let colorSpace: RBColorSpace

    init(_ components: SIMD4<Float>, colorSpace: RBColorSpace) {
        precondition(colorSpace == .sRGB || colorSpace == .linearSRGB)
        self.components = SIMD4(components.x, components.y, components.z, components.w)
        for i in 0..<4 { self.components[i] = Float(Float16(components[i])) }
        self.colorSpace = colorSpace
    }

    init(_ color: Color.Resolved) {
        self.init(SIMD4(color.red, color.green, color.blue, color.opacity), colorSpace: .sRGB)
    }

    var resolved: Color.Resolved {
        Color.Resolved(colorSpace: colorSpace == .sRGB ? .sRGB : .sRGBLinear,
            red: components.x, green: components.y, blue: components.z, opacity: components.w)
    }

    func matches(_ source: RecordedColor) -> Bool {
        var pattern = components
        if colorSpace != source.colorSpace {
            let color = resolved
            pattern = source.colorSpace == .sRGB
                ? SIMD4(color.red, color.green, color.blue, color.opacity)
                : SIMD4(color.linearRed, color.linearGreen, color.linearBlue, color.opacity)
            for i in 0..<4 { pattern[i] = Float(Float16(pattern[i])) }
        }
        for i in 0..<4 where components[i] != -32768 {
            if !(abs(pattern[i] - source.components[i]) < Float(bitPattern: 0x3b008081)) {
                return false
            }
        }
        return true
    }
}

final class RBDisplayListPredicate: NSObject, NSCopying {
    private indirect enum Term {
        case color(RecordedColor)
        case predicate([Term], inverted: Bool)

        func matches(_ color: RecordedColor?) -> Bool {
            switch self {
            case let .color(pattern):
                return color.map(pattern.matches) ?? false
            case let .predicate(terms, inverted):
                return terms.allSatisfy { $0.matches(color) } != inverted
            }
        }
    }

    private var terms: [Term] = []
    var invertsResult = false

    func addCondition(fillColor: SIMD4<Float>, colorSpace: RBColorSpace) {
        terms.append(.color(RecordedColor(fillColor, colorSpace: colorSpace)))
    }

    func addPredicate(_ predicate: RBDisplayListPredicate) {
        terms.append(.predicate(predicate.terms, inverted: predicate.invertsResult))
    }

    func removeAll() { terms.removeAll() }

    func copy(with zone: NSZone? = nil) -> Any {
        let copy = RBDisplayListPredicate()
        copy.addPredicate(self)
        return copy
    }

    func matches(_ color: RecordedColor?) -> Bool {
        terms.allSatisfy { $0.matches(color) }
    }

    private func matches(_ item: RBDisplayList.Item) -> Bool {
        if case let .layer(contents, _) = item.contents {
            return contents.items.contains { matches($0) || matchesStyle($0.state.style, inverted: false) }
        }
        return matches(item.color)
    }

    private func matchesStyle(_ source: RBDisplayList.Style?, inverted: Bool) -> Bool {
        var current = source
        while let style = current {
            let result = style.matches(self)
            if result & 0x100 != 0 && (result & 1 != 0) != inverted { return true }
            current = style.next
        }
        return false
    }

    private func copy(_ item: RBDisplayList.Item, with transform: RBDisplayList.CachedTransform,
                      styleOnly: Bool) -> RBDisplayList.Item {
        var item = item
        item.state.style = transform.transformStyle(item.state.style, styleOnly: styleOnly)
        if case let .layer(contents, frame) = item.contents {
            let children = RBMovedDisplayListContents(items: contents.items.map {
                copy($0, with: transform, styleOnly: styleOnly)
            })
            item.contents = .layer(children, frame: frame)
            if frame == nil { item.geometryBounds = children.boundingRect }
        }
        return item
    }

    func copyFilteredDisplayList(_ contents: any RBDisplayListContents) -> any RBDisplayListContents {
        let items = recordedItems(in: contents)
        for item in items { item.requireColorOperations() }
        let transform = RBDisplayList.CachedTransform(predicate: self)
        let selected = items.compactMap { item -> RBDisplayList.Item? in
            let styleOnly = matches(item) == invertsResult
            guard !styleOnly || matchesStyle(item.state.style, inverted: invertsResult) else { return nil }
            return copy(item, with: transform, styleOnly: styleOnly)
        }
        if selected.isEmpty { return RBEmptyDisplayListContents() }
        return RBMovedDisplayListContents(items: selected)
    }
}

func recordedItems(in contents: any RBDisplayListContents) -> [RBDisplayList.Item] {
    if let contents = contents as? RBMovedDisplayListContents { return contents.items }
    if let list = contents as? RBDisplayList { return list.items }
    if contents is RBEmptyDisplayListContents { return [] }
    preconditionFailure("Color operations require typed recorded contents.")
}

extension RBDisplayList.Item {
    var shading: GraphicsContext.Shading? {
        switch contents {
        case let .fill(_, shading, _), let .stroke(_, shading, _, _): return shading
        case let .text(drawing, shading):
            if case .images = drawing.contents { return nil }
            return shading
        default: return nil
        }
    }

    var shadingBounds: CGRect {
        switch contents {
        case let .fill(path, _, _), let .stroke(path, _, _, _): return path.boundingBoxOfPath
        case let .text(drawing, _): return drawing.shadingBounds
        default: return bounds
        }
    }

    mutating func replaceShading(_ shading: GraphicsContext.Shading) {
        switch contents {
        case let .fill(path, _, style): contents = .fill(path, shading, style)
        case let .stroke(path, _, style, antialiased):
            contents = .stroke(path, shading, style, isAntialiased: antialiased)
        case let .text(drawing, _): contents = .text(drawing, shading)
        default: preconditionFailure("This recorded item has no shading.")
        }
    }

    // Reject unimplemented effect/payload branches before changing any contents.
    func requireColorOperations() {
        if hasRecordedEffects {
            precondition(state.transform.isIdentity && state.clips.isEmpty,
                "Color operations on transformed or clipped effects are not implemented.")
            precondition(geometryBounds.isNull || geometryBounds.isEmpty || state.clipBoundingRect.contains(geometryBounds),
                "Color operations on effects crossing recording clip bounds are not implemented.")
        }
        var style = state.style
        while let current = style {
            precondition(current.supportsColorOperations,
                "Color operations on this recorded effect are not implemented.")
            style = current.next
        }
        switch contents {
        case let .layer(contents, _):
            for item in contents.items { item.requireColorOperations() }
        case let .image(image, _, _):
            precondition(image.texture != nil && image.shading == nil && image.image.maskColor == nil,
                "Color operations require an unshaded texture image.")
        case .projectiveLayer, .shaderLayer:
            preconditionFailure("Color operations on this layer are not implemented.")
        default: break
        }
        if let property = shading?.properties.first {
            switch property {
            case .color, .linearGradient, .radialGradient, .conicGradient: break
            case let .resolvedPaint(paint, _, _):
                precondition(paint is _AnyResolvedPaint<LinearGradient._Paint> ||
                    paint is _AnyResolvedPaint<LinearGradient.AbsolutePaint>,
                    "Color operations on this paint are not implemented.")
            default: preconditionFailure("Color operations on this shading are not implemented.")
            }
        }
    }

    private var hasRecordedEffects: Bool {
        if state.style != nil { return true }
        if case let .layer(contents, _) = contents {
            return contents.items.contains { $0.hasRecordedEffects }
        }
        return false
    }
}
