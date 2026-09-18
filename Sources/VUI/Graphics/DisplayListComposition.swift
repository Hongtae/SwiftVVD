//
//  File: DisplayListComposition.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

extension DisplayList.Item {
    // The flattened origin describes coordinates inside its raster, not a
    // placement. Apply affine placement around the retained typed group so its
    // texture, filters and callback traversal keep the same local coordinates.
    func transformedDrawingGroup(by transform: CGAffineTransform) -> Self? {
        guard !transform.isIdentity,
              case let .content(content) = value,
              case let .flattened(_, _, options) = content.value,
              options.isAccelerated else { return nil }
        let bounds = frame.applying(transform).standardized
        let mappedOrigin = frame.origin.applying(transform)
        var localTransform = transform
        localTransform.tx = mappedOrigin.x - bounds.minX
        localTransform.ty = mappedOrigin.y - bounds.minY
        var child = self
        child.frame.origin = .zero
        child.identity = .none
        var contents = DisplayList()
        contents.items = [child]
        contents.interpolationBounds = child.frame
        return Self(effect: .transform(ProjectionTransform(localTransform)),
            contents: contents, frame: bounds, identity: identity, version: version)
    }

    mutating func composite(_ incoming: Self, above: Bool) {
        if case .empty = incoming.value { return }
        if case .empty = value {
            self = incoming
            return
        }
        var incoming = incoming
        incoming.frame.origin.x -= frame.origin.x
        incoming.frame.origin.y -= frame.origin.y
        incoming.identity = .none

        var children: [Self]
        if case let .effect(.identity, contents) = value,
           opacity == 1, styleChain.commands.isEmpty, contents.debugItems.isEmpty {
            children = contents.items
        } else {
            var child = self
            child.frame.origin = .zero
            child.identity = .none
            children = [child]
            // These backend fields belong to the old content, not the new group.
            opacity = 1
            styleChain = DisplayList.StyleChain()
        }
        if above { children.append(incoming) }
        else { children.insert(incoming, at: 0) }
        var contents = DisplayList()
        contents.items = children
        contents.interpolationBounds = children.reduce(CGRect.null) { $0.union($1.frame) }
        value = .effect(.identity, contents)
    }

    mutating func addDrawingGroup(contentSeed: DisplayList.Seed) {
        if case .empty = value { return }
        var extent = CGRect.null
        addExtent(to: &extent)
        if extent.isNull { extent = .zero }
        extent = extent.integral
        let origin = CGPoint(x: extent.minX - frame.minX, y: extent.minY - frame.minY)
        var child = self
        child.frame.origin = .zero
        child.identity = .none
        var contents = DisplayList()
        contents.items = [child]
        contents.interpolationBounds = CGRect(origin: origin, size: extent.size)
        value = .content(DisplayList.Content(
            flattened: contents,
            origin: origin,
            options: RasterizationOptions(flags: [.defaultFlags, .isAccelerated]),
            seed: contentSeed
        ))
        frame = extent
        opacity = 1
        styleChain = DisplayList.StyleChain()
    }

    func addExtent(to extent: inout CGRect) {
        var bounds = CGRect.null
        switch value {
        case .empty:
            return
        case let .content(content):
            switch content.value {
            case let .shape(shape):
                let path = shape.strokeStyle.map { shape.path.strokedPath($0) } ?? shape.path
                bounds = path.boundingRect.applying(shape.transform)
                let recorded = content.command.bounds ?? frame
                bounds = bounds.offsetBy(dx: frame.minX - recorded.minX, dy: frame.minY - recorded.minY)
            case let .shadow(path, shadow):
                var onlyShadow = shadow
                onlyShadow.kind.insert(.only)
                bounds = GraphicsFilter.shadow(onlyShadow).domainOfDefinition(for: path.boundingRect)
                let recorded = content.command.bounds ?? frame
                bounds = bounds.offsetBy(dx: frame.minX - recorded.minX, dy: frame.minY - recorded.minY)
            default:
                bounds = frame
            }
        case let .effect(effect, contents):
            for child in contents.items { child.addExtent(to: &bounds) }
            switch effect {
            case let .filter(filter):
                bounds = filter.domainOfDefinition(for: bounds)
            case let .clip(path, _, options):
                if !options.contains(.inverse) { bounds = bounds.intersection(path.boundingRect) }
            case let .mask(mask, options):
                if !options.contains(.inverse) {
                    var maskBounds = CGRect.null
                    for child in mask.items { child.addExtent(to: &maskBounds) }
                    bounds = bounds.intersection(maskBounds)
                }
            case let .transform(transform):
                precondition(transform.isAffine, "Drawing-group extents require an affine transform.")
                bounds = bounds.applying(CGAffineTransform(a: transform.m11, b: transform.m12,
                    c: transform.m21, d: transform.m22, tx: transform.m31, ty: transform.m32))
            default:
                break
            }
            bounds = bounds.offsetBy(dx: frame.minX, dy: frame.minY)
        case .states:
            preconditionFailure("Drawing-group extents require a selected display-list state.")
        }
        extent = extent.union(bounds)
    }
}
