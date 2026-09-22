//
//  File: ViewTransformable.swift
//  Author: Hongtae Kim (tiff2766@gmail.com)
//
//  Copyright (c) 2022-2026 Hongtae Kim. All rights reserved.
//

import Foundation

protocol ViewTransformable {
    mutating func convertGlobal(to space: CoordinateSpace, transform: ViewTransform)
    mutating func convertGlobal(from space: CoordinateSpace, transform: ViewTransform)
    mutating func convert(to space: CoordinateSpace, transform: ViewTransform)
    mutating func convert(from space: CoordinateSpace, transform: ViewTransform)
}

protocol ApplyViewTransform: ViewTransformable {
    mutating func applyTransform(item: ViewTransform.Item)
}

extension ApplyViewTransform {
    mutating func convertGlobal(to space: CoordinateSpace, transform: ViewTransform) {
        transform.convert(.spaceToSpace(.global, transform.coordinateSpaceTag(space) ?? .invalid)) {
            applyTransform(item: $0)
        }
    }

    mutating func convertGlobal(from space: CoordinateSpace, transform: ViewTransform) {
        transform.convert(.spaceToSpace(transform.coordinateSpaceTag(space) ?? .invalid, .global)) {
            applyTransform(item: $0)
        }
    }

    mutating func convert(to space: CoordinateSpace, transform: ViewTransform) {
        transform.convert(.localToSpace(transform.coordinateSpaceTag(space) ?? .invalid)) {
            applyTransform(item: $0)
        }
    }

    mutating func convert(from space: CoordinateSpace, transform: ViewTransform) {
        transform.convert(.spaceToLocal(transform.coordinateSpaceTag(space) ?? .invalid)) {
            applyTransform(item: $0)
        }
    }
}

extension CGPoint: ApplyViewTransform {
    mutating func applyTransform(item: ViewTransform.Item) {
        switch item {
        case let .translation(offset):
            x += offset.width
            y += offset.height
        case let .affineTransform(value, inverse):
            self = applying(inverse ? value.inverted() : value)
        case let .projectionTransform(value, inverse):
            var value = value
            if inverse, !value.invert() { return }
            self = applying(value)
        case .coordinateSpace, .sizedSpace, .scrollGeometry:
            break
        }
    }
}
